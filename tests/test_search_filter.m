/* Native Foundation regression tests for the production search filter.
 * macOS:
 * xcrun clang -fobjc-arc -Wall -Wextra -Werror -I. -framework Foundation \
 *     JDXSearchFilter.m tests/test_search_filter.m -o build/test_search_filter
 * ./build/test_search_filter
 */
#import "JDXSearchFilter.h"
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
        exit(1); \
    } \
} while (0)

static NSString *const ListKey = @"FSSProductListVMArrKey";
static NSString *const GridKey = @"FSSProductGridVMArrKey";

@interface FSSearchProductModel : NSObject
@property(nonatomic, copy) NSString *adStatus;
@end
@implementation FSSearchProductModel
@end

@interface FSSearchProductViewModel : NSObject
@property(nonatomic, strong) id fsProductModel;
@property(nonatomic, weak) id correspondViewModel;
@end
@implementation FSSearchProductViewModel
@end

@interface FSSTaroNativeVM : NSObject
@property(nonatomic, strong) id fsProductModel;
@property(nonatomic, weak) id correspondViewModel;
@end
@implementation FSSTaroNativeVM
@end

/* One supported runtime class intentionally lacks accessors. Its subclasses
 * represent versions that do expose them; the production filter must inspect
 * the actual receiver instead of assuming a class name guarantees its ABI. */
@interface FSSimpleProductVM : NSObject
@end
@implementation FSSimpleProductVM
@end

@interface JDXWorkingSimpleVM : FSSimpleProductVM
@property(nonatomic, strong) id fsProductModel;
@property(nonatomic, weak) id correspondViewModel;
@end
@implementation JDXWorkingSimpleVM
@end

@interface JDXGetterOnlySimpleVM : FSSimpleProductVM
@property(nonatomic, strong) id fsProductModel;
@end
@implementation JDXGetterOnlySimpleVM
@end

@interface JDXUnknownVM : NSObject
@property(nonatomic, strong) id fsProductModel;
@property(nonatomic, weak) id correspondViewModel;
@end
@implementation JDXUnknownVM
@end

@interface JDXScalarGetterVM : FSSimpleProductVM
- (NSInteger)fsProductModel;
@end
@implementation JDXScalarGetterVM
- (NSInteger)fsProductModel
{
    CHECK(NO); /* An ABI-incompatible getter must never be invoked. */
    return 1;
}
@end

@interface JDXThrowingRow : FSSearchProductViewModel
@end
@implementation JDXThrowingRow
- (id)fsProductModel
{
    @throw [NSException exceptionWithName:@"FixtureInspectionFailure" reason:@"test data" userInfo:nil];
}
@end

@interface JDXThrowingProduct : FSSearchProductModel
@end
@implementation JDXThrowingProduct
- (NSString *)adStatus
{
    @throw [NSException exceptionWithName:@"FixtureInspectionFailure" reason:@"test data" userInfo:nil];
}
@end

@interface JDXThrowingPairRow : FSSearchProductViewModel
@end
@implementation JDXThrowingPairRow
- (id)correspondViewModel
{
    @throw [NSException exceptionWithName:@"FixtureInspectionFailure" reason:@"test data" userInfo:nil];
}
@end

static FSSearchProductModel *Product(NSString *status)
{
    FSSearchProductModel *product = [[FSSearchProductModel alloc] init];
    product.adStatus = status;
    return product;
}

static id Row(Class cls, id product)
{
    id row = [[cls alloc] init];
    [row setFsProductModel:product];
    return row;
}

static NSDictionary *Result(NSArray *list, NSArray *grid)
{
    return @{ListKey: list, GridKey: grid, @"metadata": [[NSObject alloc] init], @"page": @7};
}

static void ExpectUnchanged(id input, NSString *expectedReason)
{
    NSUInteger removed = 999;
    NSString *reason = @"not_set";
    id output = JDXFilterSearchResult(input, &removed, &reason);
    CHECK(output == input);
    CHECK(removed == 0);
    CHECK([reason isEqualToString:expectedReason]);
}

static void TestNilAndNonDictionary(void)
{
    ExpectUnchanged(nil, @"nil_result");
    for (id input in @[@"text", @[], @1, NSNull.null]) {
        ExpectUnchanged(input, @"unexpected_result_type");
    }
    CHECK(JDXFilterSearchResult(nil, NULL, NULL) == nil);
}

static void TestMissingAndMismatchedLayouts(void)
{
    ExpectUnchanged(@{}, @"missing_layout_arrays");
    ExpectUnchanged(@{ListKey: @[]}, @"missing_layout_arrays");
    ExpectUnchanged(@{GridKey: @[]}, @"missing_layout_arrays");
    ExpectUnchanged(@{ListKey: @[], GridKey: @"invalid"}, @"missing_layout_arrays");
    ExpectUnchanged(@{ListKey: NSNull.null, GridKey: @[]}, @"missing_layout_arrays");
    ExpectUnchanged(Result(@[@1], @[]), @"layout_count_mismatch");
    ExpectUnchanged(Result(@[], @[@1]), @"layout_count_mismatch");
    ExpectUnchanged(Result(@[], @[]), @"unchanged");
}

static void TestOrganicResultPreservesIdentity(void)
{
    FSSearchProductModel *a = Product(@"0"), *b = Product(nil), *c = Product(@"2");
    NSArray *list = @[Row(FSSearchProductViewModel.class, a), Row(FSSTaroNativeVM.class, b),
                      Row(JDXWorkingSimpleVM.class, c)];
    NSArray *grid = @[Row(JDXWorkingSimpleVM.class, a), Row(FSSearchProductViewModel.class, b),
                      Row(FSSTaroNativeVM.class, c)];
    NSDictionary *input = Result(list, grid);
    ExpectUnchanged(input, @"unchanged");
    CHECK(JDXFilterSearchResult(input, NULL, NULL) == input);
    CHECK(input[ListKey] == list && input[GridKey] == grid);
}

static void TestSponsoredPairsAreRemovedWithoutMutatingInputs(void)
{
    FSSearchProductModel *a = Product(@"0"), *ad1 = Product(@"1"), *b = Product(@"0"), *ad2 = Product(@"1");
    NSMutableArray *list = [@[Row(FSSearchProductViewModel.class, a), Row(FSSTaroNativeVM.class, ad1),
                             Row(JDXWorkingSimpleVM.class, b), Row(FSSearchProductViewModel.class, ad2)] mutableCopy];
    NSMutableArray *grid = [@[Row(JDXWorkingSimpleVM.class, a), Row(FSSearchProductViewModel.class, ad1),
                             Row(FSSTaroNativeVM.class, b), Row(JDXWorkingSimpleVM.class, ad2)] mutableCopy];
    NSArray *originalList = list.copy, *originalGrid = grid.copy;
    NSDictionary *input = Result(list, grid);
    NSUInteger removed = 0;
    NSString *reason = nil;
    NSDictionary *output = JDXFilterSearchResult(input, &removed, &reason);
    CHECK(output != input && removed == 2 && [reason isEqualToString:@"filtered"]);
    CHECK(([output[ListKey] isEqualToArray:@[list[0], list[2]]]));
    CHECK(([output[GridKey] isEqualToArray:@[grid[0], grid[2]]]));
    CHECK([list isEqualToArray:originalList] && [grid isEqualToArray:originalGrid]);
    CHECK(input[ListKey] == list && input[GridKey] == grid);
    CHECK(output[ListKey] != list && output[GridKey] != grid);
    CHECK(output[@"metadata"] == input[@"metadata"] && [output[@"page"] isEqual:@7]);
    CHECK([ad1.adStatus isEqualToString:@"1"] && [ad2.adStatus isEqualToString:@"1"]);
    CHECK([[(JDXWorkingSimpleVM *)list[2] fsProductModel] isEqual:b]);
}

static void TestExplicitBidirectionalPairs(void)
{
    FSSearchProductViewModel *left = Row(FSSearchProductViewModel.class, Product(@"1"));
    FSSTaroNativeVM *right = Row(FSSTaroNativeVM.class, Product(@"1"));
    left.correspondViewModel = right;
    right.correspondViewModel = left;
    FSSearchProductModel *organic = Product(@"0");
    id ordinaryLeft = Row(JDXWorkingSimpleVM.class, organic);
    id ordinaryRight = Row(FSSTaroNativeVM.class, organic);
    NSDictionary *input = Result(@[left, ordinaryLeft], @[right, ordinaryRight]);
    NSUInteger removed = 0;
    NSString *reason = nil;
    NSDictionary *output = JDXFilterSearchResult(input, &removed, &reason);
    CHECK(removed == 1 && [reason isEqualToString:@"filtered"]);
    CHECK([output[ListKey] isEqualToArray:@[ordinaryLeft]]);
    CHECK([output[GridKey] isEqualToArray:@[ordinaryRight]]);
    CHECK(left.correspondViewModel == right && right.correspondViewModel == left);
    CHECK([input[ListKey] count] == 2 && [input[GridKey] count] == 2);
}

static void TestDisagreementAndUnpairedAdsFailOpen(void)
{
    id left = Row(FSSearchProductViewModel.class, Product(@"1"));
    id right = Row(FSSTaroNativeVM.class, Product(@"0"));
    ExpectUnchanged(Result(@[left], @[right]), @"unpaired_advertisement");
    right = Row(FSSTaroNativeVM.class, Product(@"1"));
    ExpectUnchanged(Result(@[left], @[right]), @"unpaired_advertisement");
    [left setCorrespondViewModel:right];
    ExpectUnchanged(Result(@[left], @[right]), @"unpaired_advertisement");
    id unknown = Row(JDXUnknownVM.class, Product(@"1"));
    ExpectUnchanged(Result(@[left], @[unknown]), @"unpaired_advertisement");
}

static void TestAllSponsoredResultsFailOpen(void)
{
    FSSearchProductModel *ad = Product(@"1");
    id left = Row(FSSearchProductViewModel.class, ad), right = Row(FSSTaroNativeVM.class, ad);
    ExpectUnchanged(Result(@[left], @[right]), @"would_empty_results");
    ExpectUnchanged(Result(@[left, left], @[right, right]), @"would_empty_results");
}

static void TestUnknownModelsAndMissingGetters(void)
{
    id unknown = Row(JDXUnknownVM.class, Product(@"1"));
    id missing = [[FSSimpleProductVM alloc] init];
    id wrongProduct = Row(FSSearchProductViewModel.class, @"not a product model");
    id nilProduct = Row(FSSTaroNativeVM.class, nil);
    ExpectUnchanged(Result(@[unknown, missing, wrongProduct, nilProduct, NSNull.null],
                           @[unknown, missing, wrongProduct, nilProduct, NSNull.null]), @"unchanged");
    id getterOnlyLeft = Row(JDXGetterOnlySimpleVM.class, Product(@"1"));
    id getterOnlyRight = Row(JDXGetterOnlySimpleVM.class, Product(@"1"));
    ExpectUnchanged(Result(@[getterOnlyLeft], @[getterOnlyRight]), @"unpaired_advertisement");
}

static void TestIncompatibleGetterIsNeverCalled(void)
{
    id scalar = [[JDXScalarGetterVM alloc] init];
    ExpectUnchanged(Result(@[scalar], @[scalar]), @"unchanged");
}

static void TestGetterExceptionsPreserveCompleteResult(void)
{
    id throwingRow = [[JDXThrowingRow alloc] init];
    ExpectUnchanged(Result(@[throwingRow], @[throwingRow]), @"inspection_exception");
    id throwingProductRow = Row(FSSTaroNativeVM.class, [[JDXThrowingProduct alloc] init]);
    ExpectUnchanged(Result(@[throwingProductRow], @[throwingProductRow]), @"inspection_exception");
    id throwingPair = Row(JDXThrowingPairRow.class, Product(@"1"));
    id differentProductPair = Row(FSSearchProductViewModel.class, Product(@"1"));
    ExpectUnchanged(Result(@[throwingPair], @[differentProductPair]), @"inspection_exception");
    /* If an exception occurs after a valid ad has been found, no partially
     * filtered result or partial removal count may escape. */
    FSSearchProductModel *ad = Product(@"1");
    id left = Row(FSSearchProductViewModel.class, ad), right = Row(FSSTaroNativeVM.class, ad);
    ExpectUnchanged(Result(@[left, throwingRow], @[right, throwingRow]), @"inspection_exception");
}

static void TestInspectionLimit(void)
{
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:2001];
    for (NSUInteger index = 0; index < 2001; ++index) [rows addObject:NSNull.null];
    ExpectUnchanged(Result(rows, rows), @"result_limit");
}

int main(void)
{
    @autoreleasepool {
        TestNilAndNonDictionary();
        TestMissingAndMismatchedLayouts();
        TestOrganicResultPreservesIdentity();
        TestSponsoredPairsAreRemovedWithoutMutatingInputs();
        TestExplicitBidirectionalPairs();
        TestDisagreementAndUnpairedAdsFailOpen();
        TestAllSponsoredResultsFailOpen();
        TestUnknownModelsAndMissingGetters();
        TestIncompatibleGetterIsNeverCalled();
        TestGetterExceptionsPreserveCompleteResult();
        TestInspectionLimit();
        puts("PASS: 11 native Foundation search-filter regression scenarios");
    }
    return 0;
}
