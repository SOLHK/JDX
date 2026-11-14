#ifndef JDX_HOOK_RUNTIME_H
#define JDX_HOOK_RUNTIME_H

#include <objc/runtime.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef enum JDXHookStatus {
    JDXHookInstalledOwn = 1,
    JDXHookInstalledOverride = 2,
    JDXHookAlreadyInstalled = 3,
    JDXHookMissingClass = -1,
    JDXHookMissingMethod = -2,
    JDXHookTypeMismatch = -3,
    JDXHookFailed = -4
} JDXHookStatus;

typedef struct JDXHookReceipt {
    int status;
    const char *actualEncoding;
    const char *ownerName;
} JDXHookReceipt;

/* class_getInstanceMethod also returns inherited methods. Never pass such a
 * Method directly to method_setImplementation: doing so edits the ancestor. */
static inline Method JDXOwnInstanceMethod(Class cls, SEL selector)
{
    unsigned int count = 0;
    Method result = NULL;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int index = 0; methods && index < count; ++index) {
        if (sel_isEqual(method_getName(methods[index]), selector)) {
            result = methods[index];
            break;
        }
    }
    free(methods);
    return result;
}

/* Call on a serial installation path. The supplied original storage must have
 * static lifetime and be initialized to NULL by the caller. Runtime class/method names
 * and encoding strings in the receipt are borrowed, stable runtime strings.
 *
 * true means this call installed a new hook. AlreadyInstalled returns false,
 * preserves the saved original, and never chains a replacement to itself.
 * Failures leave the caller's original storage and host methods unchanged. */
static inline bool JDXInstallInstanceHook(const char *className,
                                         const char *selectorName,
                                         const char *expectedEncoding,
                                         IMP replacement,
                                         IMP *original,
                                         JDXHookReceipt *receipt)
{
    JDXHookReceipt local = {JDXHookFailed, NULL, NULL};
    if (!receipt) {
        receipt = &local;
    }
    *receipt = local;
    if (!className || !*className || !selectorName || !*selectorName ||
        !expectedEncoding || !*expectedEncoding || !replacement || !original) {
        return false;
    }

    Class target = objc_lookUpClass(className);
    if (!target) {
        receipt->status = JDXHookMissingClass;
        return false;
    }
    SEL selector = sel_registerName(selectorName);
    Method resolved = class_getInstanceMethod(target, selector);
    if (!resolved) {
        receipt->status = JDXHookMissingMethod;
        return false;
    }

    receipt->actualEncoding = method_getTypeEncoding(resolved);
    Method own = NULL;
    for (Class owner = target; owner; owner = class_getSuperclass(owner)) {
        Method candidate = JDXOwnInstanceMethod(owner, selector);
        if (candidate) {
            receipt->ownerName = class_getName(owner);
            if (owner == target) {
                own = candidate;
            }
            break;
        }
    }
    if (!receipt->actualEncoding ||
        strcmp(receipt->actualEncoding, expectedEncoding) != 0) {
        receipt->status = JDXHookTypeMismatch;
        return false;
    }

    IMP current = method_getImplementation(resolved);
    if (!current) {
        return false;
    }
    if (current == replacement) {
        receipt->status = JDXHookAlreadyInstalled;
        return false;
    }
    /* If owner enumeration failed, fail open rather than guessing whether a
     * Method belongs to the target or to one of its ancestors. */
    if (!receipt->ownerName) {
        return false;
    }
    /* Another plugin may have wrapped our hook since its first installation.
     * Recapturing that wrapper as our original would form an indirect cycle. */
    if (*original) {
        receipt->status = JDXHookAlreadyInstalled;
        return false;
    }

    IMP previousStorage = *original;
    *original = current; /* Publish before any host thread can enter the hook. */
    if (own) {
        method_setImplementation(own, replacement);
        receipt->status = JDXHookInstalledOwn;
        return true;
    }
    if (class_addMethod(target, selector, replacement, receipt->actualEncoding)) {
        receipt->status = JDXHookInstalledOverride;
        return true;
    }

    /* A rejected add must never fall back to replacing the inherited Method. */
    *original = previousStorage;
    return false;
}

#endif /* JDX_HOOK_RUNTIME_H */
