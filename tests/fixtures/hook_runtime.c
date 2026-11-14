#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "JDXHookRuntime.h"

struct FakeMethod {
    SEL selector;
    const char *encoding;
    IMP implementation;
};

struct FakeClass {
    const char *name;
    Class superclass;
    struct FakeMethod methods[8];
    unsigned int count;
};

static struct FakeClass classes[4];
static unsigned int classCount;
static bool rejectAdd;
static bool rejectEnumeration;
static unsigned int mutationCount;
static unsigned int originalCalls;
static unsigned int replacementCalls;
static unsigned int otherPluginCalls;
static IMP savedOriginal;
static IMP otherPluginOriginal;
static IMP *expectedOriginalStorage;
static IMP expectedOriginalValue;

static void originalImplementation(void) { ++originalCalls; }
static void otherImplementation(void) { originalCalls += 10; }
static void replacementImplementation(void)
{
    ++replacementCalls;
    assert(savedOriginal && savedOriginal != replacementImplementation);
    savedOriginal();
}

static void otherPluginImplementation(void)
{
    ++otherPluginCalls;
    assert(otherPluginOriginal);
    otherPluginOriginal();
}

Class objc_lookUpClass(const char *name)
{
    for (unsigned int i = 0; i < classCount; ++i) {
        if (!strcmp(classes[i].name, name)) {
            return &classes[i];
        }
    }
    return NULL;
}

SEL sel_registerName(const char *name) { return name; }
BOOL sel_isEqual(SEL left, SEL right) { return !strcmp(left, right); }
Class class_getSuperclass(Class cls) { return cls ? cls->superclass : NULL; }
const char *class_getName(Class cls) { return cls ? cls->name : NULL; }
SEL method_getName(Method method) { return method->selector; }
const char *method_getTypeEncoding(Method method) { return method->encoding; }
IMP method_getImplementation(Method method) { return method->implementation; }

Method class_getInstanceMethod(Class cls, SEL selector)
{
    for (; cls; cls = cls->superclass) {
        for (unsigned int i = 0; i < cls->count; ++i) {
            if (sel_isEqual(cls->methods[i].selector, selector)) {
                return &cls->methods[i];
            }
        }
    }
    return NULL;
}

Method *class_copyMethodList(Class cls, unsigned int *count)
{
    *count = 0;
    if (!cls || rejectEnumeration || !cls->count) {
        return NULL;
    }
    Method *result = malloc(sizeof(*result) * cls->count);
    assert(result);
    *count = cls->count;
    for (unsigned int i = 0; i < cls->count; ++i) {
        result[i] = &cls->methods[i];
    }
    return result;
}

static void assertOriginalPublished(void)
{
    if (expectedOriginalStorage) {
        assert(*expectedOriginalStorage == expectedOriginalValue);
    }
}

IMP method_setImplementation(Method method, IMP replacement)
{
    assertOriginalPublished();
    IMP previous = method->implementation;
    method->implementation = replacement;
    ++mutationCount;
    return previous;
}

BOOL class_addMethod(Class cls, SEL selector, IMP implementation, const char *encoding)
{
    assertOriginalPublished();
    if (rejectAdd) {
        return false;
    }
    for (unsigned int i = 0; i < cls->count; ++i) {
        if (sel_isEqual(cls->methods[i].selector, selector)) {
            return false;
        }
    }
    assert(cls->count < 8);
    cls->methods[cls->count++] = (struct FakeMethod){selector, encoding, implementation};
    ++mutationCount;
    return true;
}

static void resetClasses(bool childOwnsMethod)
{
    memset(classes, 0, sizeof(classes));
    classCount = 4;
    classes[0] = (struct FakeClass){.name = "Parent"};
    classes[1] = (struct FakeClass){.name = "Child", .superclass = &classes[0]};
    classes[2] = (struct FakeClass){.name = "Sibling", .superclass = &classes[0]};
    classes[3] = (struct FakeClass){.name = "Grandchild", .superclass = &classes[1]};
    classes[0].methods[0] = (struct FakeMethod){"render", "v16@0:8", originalImplementation};
    classes[0].count = 1;
    if (childOwnsMethod) {
        classes[1].methods[0] = (struct FakeMethod){"render", "v16@0:8", otherImplementation};
        classes[1].count = 1;
    }
    rejectAdd = false;
    rejectEnumeration = false;
    mutationCount = originalCalls = replacementCalls = otherPluginCalls = 0;
    savedOriginal = NULL;
    otherPluginOriginal = NULL;
    expectedOriginalStorage = NULL;
    expectedOriginalValue = NULL;
}

static void dispatch(const char *className)
{
    method_getImplementation(class_getInstanceMethod(objc_lookUpClass(className), "render"))();
}

static void expectOriginalBeforeInstallation(IMP expected)
{
    expectedOriginalStorage = &savedOriginal;
    expectedOriginalValue = expected;
}

static void testLegacyBugIsReproduced(void)
{
    resetClasses(false);
    /* This is the exact unsafe pattern in JDX 0.1: inherited lookup returns
     * Parent's Method, so the replacement also changes the unrelated Sibling. */
    Method resolved = class_getInstanceMethod(objc_lookUpClass("Child"), "render");
    savedOriginal = method_getImplementation(resolved);
    method_setImplementation(resolved, replacementImplementation);
    dispatch("Parent");
    dispatch("Sibling");
    assert(replacementCalls == 2);
    assert(originalCalls == 2);
}

static void testInheritedHookIsIsolated(void)
{
    resetClasses(false);
    JDXHookReceipt receipt;
    expectOriginalBeforeInstallation(originalImplementation);
    assert(JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                  &savedOriginal, &receipt));
    assert(receipt.status == JDXHookInstalledOverride);
    assert(!strcmp(receipt.ownerName, "Parent"));
    assert(!strcmp(receipt.actualEncoding, "v16@0:8"));
    assert(mutationCount == 1);
    assert(classes[0].methods[0].implementation == originalImplementation);
    assert(classes[1].count == 1);
    dispatch("Parent");
    dispatch("Sibling");
    assert(replacementCalls == 0 && originalCalls == 2);
    dispatch("Child");
    dispatch("Grandchild");
    assert(replacementCalls == 2 && originalCalls == 4);
}

static void testOwnHookChainsOwnImplementation(void)
{
    resetClasses(true);
    JDXHookReceipt receipt;
    expectOriginalBeforeInstallation(otherImplementation);
    assert(JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                  &savedOriginal, &receipt));
    assert(receipt.status == JDXHookInstalledOwn);
    assert(!strcmp(receipt.ownerName, "Child"));
    assert(savedOriginal == otherImplementation);
    dispatch("Parent");
    dispatch("Sibling");
    dispatch("Child");
    assert(replacementCalls == 1 && originalCalls == 12);
    assert(mutationCount == 1 && classes[1].count == 1);
}

static void testRepeatedInstallationNeverChainsToItself(void)
{
    resetClasses(false);
    JDXHookReceipt receipt;
    assert(JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                  &savedOriginal, &receipt));
    assert(!JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookAlreadyInstalled);
    assert(savedOriginal == originalImplementation && mutationCount == 1);
    IMP newStorage = NULL;
    assert(!JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                   &newStorage, &receipt));
    assert(receipt.status == JDXHookAlreadyInstalled && newStorage == NULL);
    /* The same replacement inherited by a descendant is rejected as well. */
    assert(!JDXInstallInstanceHook("Grandchild", "render", "v16@0:8", replacementImplementation,
                                   &newStorage, &receipt));
    assert(receipt.status == JDXHookAlreadyInstalled && newStorage == NULL);
    dispatch("Child");
    assert(replacementCalls == 1 && originalCalls == 1);
}

static void testInvalidTargetsAndSignaturesFailOpen(void)
{
    resetClasses(false);
    savedOriginal = otherImplementation;
    JDXHookReceipt receipt;
    assert(!JDXInstallInstanceHook("Missing", "render", "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookMissingClass && !receipt.actualEncoding && !receipt.ownerName);
    assert(!JDXInstallInstanceHook("Child", "missing", "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookMissingMethod && !receipt.actualEncoding && !receipt.ownerName);
    assert(!JDXInstallInstanceHook("Child", "render", "@16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookTypeMismatch);
    assert(!strcmp(receipt.actualEncoding, "v16@0:8"));
    assert(!strcmp(receipt.ownerName, "Parent"));
    assert(savedOriginal == otherImplementation && mutationCount == 0);
    dispatch("Child");
    dispatch("Sibling");
    assert(replacementCalls == 0 && originalCalls == 2);
}

static void testAnotherPluginCannotCauseAnIndirectCycle(void)
{
    resetClasses(false);
    JDXHookReceipt receipt;
    assert(JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                  &savedOriginal, &receipt));
    Method own = class_getInstanceMethod(objc_lookUpClass("Child"), "render");
    otherPluginOriginal = method_setImplementation(own, otherPluginImplementation);
    assert(otherPluginOriginal == replacementImplementation && mutationCount == 2);
    assert(!JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookAlreadyInstalled);
    assert(savedOriginal == originalImplementation && mutationCount == 2);
    assert(method_getImplementation(own) == otherPluginImplementation);
    dispatch("Child");
    assert(otherPluginCalls == 1 && replacementCalls == 1 && originalCalls == 1);
}

static void testRejectedOverrideNeverTouchesAncestor(void)
{
    resetClasses(false);
    rejectAdd = true;
    expectOriginalBeforeInstallation(originalImplementation);
    JDXHookReceipt receipt;
    assert(!JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookFailed);
    assert(savedOriginal == NULL && mutationCount == 0);
    assert(classes[1].count == 0);
    dispatch("Parent");
    dispatch("Child");
    dispatch("Sibling");
    assert(replacementCalls == 0 && originalCalls == 3);
}

static void testFailedOwnerEnumerationFailsOpen(void)
{
    resetClasses(true);
    savedOriginal = originalImplementation;
    rejectEnumeration = true;
    JDXHookReceipt receipt;
    assert(!JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookFailed && !receipt.ownerName);
    assert(savedOriginal == originalImplementation && mutationCount == 0);
    dispatch("Child");
    assert(originalCalls == 10 && replacementCalls == 0);
}

static void testNullArgumentsAndOptionalReceipt(void)
{
    resetClasses(false);
    JDXHookReceipt receipt;
    assert(!JDXInstallInstanceHook(NULL, "render", "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(receipt.status == JDXHookFailed);
    assert(!JDXInstallInstanceHook("Child", NULL, "v16@0:8", replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(!JDXInstallInstanceHook("Child", "render", NULL, replacementImplementation,
                                   &savedOriginal, &receipt));
    assert(!JDXInstallInstanceHook("Child", "render", "v16@0:8", NULL, &savedOriginal, &receipt));
    assert(!JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                   NULL, &receipt));
    assert(mutationCount == 0);
    assert(JDXInstallInstanceHook("Child", "render", "v16@0:8", replacementImplementation,
                                  &savedOriginal, NULL));
    dispatch("Child");
    assert(originalCalls == 1 && replacementCalls == 1);
}

int main(void)
{
    testLegacyBugIsReproduced();
    testInheritedHookIsIsolated();
    testOwnHookChainsOwnImplementation();
    testRepeatedInstallationNeverChainsToItself();
    testInvalidTargetsAndSignaturesFailOpen();
    testAnotherPluginCannotCauseAnIndirectCycle();
    testRejectedOverrideNeverTouchesAncestor();
    testFailedOwnerEnumerationFailsOpen();
    testNullArgumentsAndOptionalReceipt();
    puts("PASS: 9 compiled hook-runtime regression scenarios");
    return 0;
}
