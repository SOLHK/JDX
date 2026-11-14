#ifndef JDX_TEST_OBJC_RUNTIME_H
#define JDX_TEST_OBJC_RUNTIME_H

#include <stdbool.h>

/* Minimal ABI-neutral surface used to execute the production hook installer
 * against a faithful model of Objective-C's class method lookup rules. */
typedef struct FakeClass *Class;
typedef struct FakeMethod *Method;
typedef const char *SEL;
typedef void (*IMP)(void);
typedef bool BOOL;

Class objc_lookUpClass(const char *name);
SEL sel_registerName(const char *name);
BOOL sel_isEqual(SEL left, SEL right);
Method class_getInstanceMethod(Class cls, SEL selector);
Method *class_copyMethodList(Class cls, unsigned int *count);
Class class_getSuperclass(Class cls);
const char *class_getName(Class cls);
SEL method_getName(Method method);
const char *method_getTypeEncoding(Method method);
IMP method_getImplementation(Method method);
IMP method_setImplementation(Method method, IMP replacement);
BOOL class_addMethod(Class cls, SEL selector, IMP implementation, const char *encoding);

#endif
