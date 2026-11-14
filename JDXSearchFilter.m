#import "JDXSearchFilter.h"
#import <objc/runtime.h>
#include <stdlib.h>

static BOOL JDXObjectGetterAvailable(id object, SEL selector)
{
    if (!object || ![object respondsToSelector:selector]) return NO;
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char *encoding = method_copyReturnType(method);
    BOOL valid = encoding && encoding[0] == '@';
    free(encoding);
    return valid;
}

static id JDXGetObject(id object, const char *name)
{
    SEL selector = sel_registerName(name);
    if (!JDXObjectGetterAvailable(object, selector)) return nil;
    id (*implementation)(id, SEL) = (id (*)(id, SEL))[object methodForSelector:selector];
    return implementation(object, selector);
}

static BOOL JDXKnownSearchRow(id row)
{
    const char *names[] = {"FSSearchProductViewModel", "FSSTaroNativeVM", "FSSimpleProductVM"};
    for (NSUInteger index = 0; index < sizeof(names) / sizeof(names[0]); ++index) {
        Class cls = objc_lookUpClass(names[index]);
        if (cls && [row isKindOfClass:cls]) return YES;
    }
    return NO;
}

static id JDXSearchProduct(id row)
{
    if (!JDXKnownSearchRow(row)) return nil;
    Class cls = objc_lookUpClass("FSSearchProductModel");
    id product = JDXGetObject(row, "fsProductModel");
    return cls && [product isKindOfClass:cls] ? product : nil;
}

static BOOL JDXProductIsSponsored(id product)
{
    return [@"1" isEqual:JDXGetObject(product, "adStatus")];
}

id JDXFilterSearchResult(id result, NSUInteger *removed, NSString **reasonCode)
{
    if (removed) *removed = 0;
    if (reasonCode) *reasonCode = @"unchanged";
    if (!result) {
        if (reasonCode) *reasonCode = @"nil_result";
        return result;
    }
    @try {
        if (![result isKindOfClass:NSDictionary.class]) {
            if (reasonCode) *reasonCode = @"unexpected_result_type";
            return result;
        }
        NSString *listKey = @"FSSProductListVMArrKey";
        NSString *gridKey = @"FSSProductGridVMArrKey";
        NSArray *list = result[listKey];
        NSArray *grid = result[gridKey];
        if (![list isKindOfClass:NSArray.class] || ![grid isKindOfClass:NSArray.class]) {
            if (reasonCode) *reasonCode = @"missing_layout_arrays";
            return result;
        }
        if (list.count != grid.count) {
            if (reasonCode) *reasonCode = @"layout_count_mismatch";
            return result;
        }
        /* Bound defensive inspection; an unusual result must not stall search. */
        if (list.count > 2000) {
            if (reasonCode) *reasonCode = @"result_limit";
            return result;
        }
        NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
        for (NSUInteger index = 0; index < list.count; ++index) {
            id left = list[index], right = grid[index];
            id leftProduct = JDXSearchProduct(left), rightProduct = JDXSearchProduct(right);
            BOOL leftAd = JDXProductIsSponsored(leftProduct);
            BOOL rightAd = JDXProductIsSponsored(rightProduct);
            if (!leftAd && !rightAd) continue;
            /* Both layouts must agree, with object identity or explicit pairing.
             * Otherwise preserve the complete original result, including metadata. */
            BOOL paired = leftProduct && rightProduct &&
                (leftProduct == rightProduct ||
                 (JDXGetObject(left, "correspondViewModel") == right &&
                  JDXGetObject(right, "correspondViewModel") == left));
            if (!leftAd || !rightAd || !paired) {
                if (reasonCode) *reasonCode = @"unpaired_advertisement";
                return result;
            }
            [indexes addIndex:index];
        }
        if (!indexes.count) return result;
        if (indexes.count == list.count) {
            if (reasonCode) *reasonCode = @"would_empty_results";
            return result;
        }
        NSMutableArray *updatedList = [list mutableCopy];
        NSMutableArray *updatedGrid = [grid mutableCopy];
        [updatedList removeObjectsAtIndexes:indexes];
        [updatedGrid removeObjectsAtIndexes:indexes];
        NSMutableDictionary *updated = [result mutableCopy];
        updated[listKey] = updatedList;
        updated[gridKey] = updatedGrid;
        if (removed) *removed = indexes.count;
        if (reasonCode) *reasonCode = @"filtered";
        return updated;
    } @catch (__unused NSException *exception) {
        /* Never log exception.reason: a host exception may contain account data. */
        if (reasonCode) *reasonCode = @"inspection_exception";
        return result;
    }
}
