#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <string.h>

// Keep the preference used by the previous builds so an existing choice carries over.
static NSString *const JDXEnabledKey = @"com.solhk.jd-adblock.enabled";
static void (*OriginalMyViewDidLoad)(UIViewController *, SEL);
static NSDictionary *(*OriginalCreateSearchRows)(id, SEL, NSArray *);
static NSString *(*OriginalSearchHeaderType)(id, SEL);
static BOOL (*OriginalBottomBannerCanUse)(id, SEL);
static void (*OriginalInitHomeRecommendation)(id, SEL);
static void (*OriginalRenderDetailRecommendation)(id, SEL);
static Class SearchProductClass;
static Class SearchProductViewModelClass;
static Class SearchTaroViewModelClass;
static Class SearchSimpleViewModelClass;

@protocol JDXSearchProduct <NSObject>
- (NSString *)adStatus;
@end

@protocol JDXSearchRow <NSObject>
- (id<JDXSearchProduct>)fsProductModel;
- (id)correspondViewModel;
@end

@protocol JDXBottomBanner <NSObject>
- (id)extension_id;
- (NSString *)businessType;
- (NSString *)showCondition;
- (BOOL)homeRollBackGuideType;
@end

@protocol JDXHomeRecommendation <NSObject>
- (UIView *)bottomCollectionView;
@end

@protocol JDXDetailRecommendation <NSObject>
- (UIView *)view;
@end

@interface JDXSettingsViewController : UIViewController
@end

@implementation JDXSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"JDX 去广告";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"启用去广告";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    title.adjustsFontForContentSizeCategory = YES;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:JDXEnabledKey];
    toggle.accessibilityLabel = title.text;
    [toggle addTarget:self action:@selector(saveEnabled:) forControlEvents:UIControlEventValueChanged];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, toggle]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.layoutMargins = UIEdgeInsetsMake(10, 16, 10, 16);
    row.layoutMarginsRelativeArrangement = YES;
    row.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    row.layer.cornerRadius = 12;

    UILabel *note = [[UILabel alloc] init];
    note.text = @"更改已自动保存。请从后台结束京东，再重新打开使更改生效。";
    note.textColor = UIColor.secondaryLabelColor;
    note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    note.adjustsFontForContentSizeCategory = YES;
    note.numberOfLines = 0;

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[row, note]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 12;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:content];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [content.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
    ]];
}

- (void)saveEnabled:(UISwitch *)toggle
{
    [NSUserDefaults.standardUserDefaults setBool:toggle.isOn forKey:JDXEnabledKey];
}

- (void)close
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

static void ShowJDXSettings(UIViewController *controller, __unused SEL selector,
                             UILongPressGestureRecognizer *gesture)
{
    if (gesture.state != UIGestureRecognizerStateBegan || controller.presentedViewController ||
        !controller.viewIfLoaded.window) {
        return;
    }

    JDXSettingsViewController *settings = [[JDXSettingsViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                                       UISheetPresentationControllerDetent.largeDetent];
    [controller presentViewController:navigation animated:YES completion:nil];
}

static void MyViewDidLoad(UIViewController *controller, SEL selector)
{
    OriginalMyViewDidLoad(controller, selector);
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
        initWithTarget:controller action:sel_registerName("jdx_presentSettings:")];
    press.numberOfTouchesRequired = 2;
    press.minimumPressDuration = 0.75;
    press.cancelsTouchesInView = NO;
    [controller.view addGestureRecognizer:press];
}

static Method FindMethod(const char *className, const char *selectorName, const char *encoding)
{
    Class cls = objc_lookUpClass(className);
    Method method = class_getInstanceMethod(cls, sel_registerName(selectorName));
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0 ? method : NULL;
}

static BOOL DoNotShowAdvertisement(__unused id instance, __unused SEL selector)
{
    return NO;
}

static BOOL DoNotShowAdvertisementWithModel(__unused id instance, __unused SEL selector, __unused id model)
{
    return NO;
}

static NSInteger NoRecommendationItems(__unused id instance, __unused SEL selector)
{
    return 0;
}

static id NoAdvertisementModel(__unused id instance, __unused SEL selector)
{
    return nil;
}

static NSString *NoSearchRecommendations(__unused id instance, __unused SEL selector)
{
    return @"0";
}

static NSString *SearchHeaderType(id model, SEL selector)
{
    NSString *type = OriginalSearchHeaderType(model, selector);
    return [@"adShop" isEqual:type] || [@"adSlideShop" isEqual:type] ? @"" : type;
}

static BOOL IsSponsoredSearchRow(id row)
{
    if ((SearchProductViewModelClass && [row isKindOfClass:SearchProductViewModelClass]) ||
        (SearchTaroViewModelClass && [row isKindOfClass:SearchTaroViewModelClass]) ||
        (SearchSimpleViewModelClass && [row isKindOfClass:SearchSimpleViewModelClass])) {
        id<JDXSearchProduct> product = [(id<JDXSearchRow>)row fsProductModel];
        if ([product isKindOfClass:SearchProductClass]) {
            return [@"1" isEqual:[product adStatus]];
        }
    }
    return NO;
}

static NSDictionary *CreateSearchRows(id controller, SEL selector, NSArray *products)
{
    NSDictionary *result = OriginalCreateSearchRows(controller, selector, products);
    NSArray<NSString *> *keys = @[@"FSSProductListVMArrKey", @"FSSProductGridVMArrKey"];
    NSHashTable *ads = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NSString *key in keys) {
        NSArray *rows = result[key];
        if (![rows isKindOfClass:NSArray.class]) {
            continue;
        }
        for (id<JDXSearchRow> row in rows) {
            if (IsSponsoredSearchRow(row)) {
                [ads addObject:row];
                id otherLayout = [row correspondViewModel];
                if (otherLayout) {
                    [ads addObject:otherLayout];
                }
            }
        }
    }
    if (!ads.count) {
        return result;
    }

    NSMutableDictionary *updated = nil;
    for (NSString *key in keys) {
        NSArray *rows = result[key];
        if (![rows isKindOfClass:NSArray.class]) {
            continue;
        }
        NSMutableArray *filtered = nil;
        for (NSUInteger index = 0; index < rows.count; index++) {
            id row = rows[index];
            if ([ads containsObject:row]) {
                if (!filtered) {
                    filtered = [[rows subarrayWithRange:NSMakeRange(0, index)] mutableCopy];
                }
            } else {
                [filtered addObject:row];
            }
        }
        if (filtered) {
            if (!updated) {
                updated = [result mutableCopy];
            }
            updated[key] = filtered;
        }
    }
    return updated ?: result;
}

static BOOL AllowBottomBanner(id<JDXBottomBanner> banner, SEL selector)
{
    if (!OriginalBottomBannerCanUse(banner, selector)) {
        return NO;
    }
    id extension = [banner extension_id];
    if (![extension isKindOfClass:NSString.class] || ![extension length]) {
        return YES;
    }
    return [banner businessType].integerValue == 40 || [@"1" isEqual:[banner showCondition]] ||
           [banner homeRollBackGuideType];
}

static double NoHomeRecommendationHeight(__unused id manager, __unused SEL selector, __unused BOOL flag)
{
    return 0;
}

static void InitHomeRecommendation(id<JDXHomeRecommendation> manager, SEL selector)
{
    OriginalInitHomeRecommendation(manager, selector);
    [manager bottomCollectionView].hidden = YES;
}

static void RenderDetailRecommendation(id<JDXDetailRecommendation> floor, SEL selector)
{
    OriginalRenderDetailRecommendation(floor, selector);
    [floor view].hidden = YES;
}

static void ReplaceMethod(const char *className, const char *selectorName, const char *encoding, IMP replacement)
{
    Method method = FindMethod(className, selectorName, encoding);
    if (method) {
        method_setImplementation(method, replacement);
    }
}

__attribute__((constructor)) static void InstallJDX(void)
{
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if (![bundle.bundleIdentifier isEqualToString:@"com.360buy.jdmobile"] ||
            ![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"171204"] ||
            ![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"16.1.83"]) {
            return;
        }

        NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
        [preferences registerDefaults:@{JDXEnabledKey: @YES}];

        Method viewDidLoad = FindMethod("MyJdHomeViewController", "viewDidLoad", "v16@0:8");
        Class myController = objc_lookUpClass("MyJdHomeViewController");
        if (viewDidLoad && class_addMethod(myController, sel_registerName("jdx_presentSettings:"),
                                           (IMP)ShowJDXSettings, "v24@0:8@16")) {
            OriginalMyViewDidLoad = (void (*)(UIViewController *, SEL))method_getImplementation(viewDidLoad);
            method_setImplementation(viewDidLoad, (IMP)MyViewDidLoad);
        }

        if (![preferences boolForKey:JDXEnabledKey]) {
            return;
        }

        ReplaceMethod("LaunchAnimationManager", "canShowLaunchADView", "B16@0:8", (IMP)DoNotShowAdvertisement);
        ReplaceMethod("JDMainPageFloatPhotoCeilingModel", "canShowCeilingPhoto", "B16@0:8", (IMP)DoNotShowAdvertisement);
        ReplaceMethod("JDMainPageViewController", "shouldDisplayFloat:", "B24@0:8@16", (IMP)DoNotShowAdvertisementWithModel);
        ReplaceMethod("JDMainPageViewController", "shouldDisplayFloat916:", "B24@0:8@16", (IMP)DoNotShowAdvertisementWithModel);
        ReplaceMethod("JDMainPageViewController", "shouldShowTwoScreenFloatViewForModel:", "B24@0:8@16", (IMP)DoNotShowAdvertisementWithModel);
        ReplaceMethod("FSSearchModel", "beltAdShop", "@16@0:8", (IMP)NoAdvertisementModel);
        ReplaceMethod("FSSearchModel", "beltAdShopTn", "@16@0:8", (IMP)NoAdvertisementModel);
        ReplaceMethod("MyJdRecommendFloor15250", "myjd_numberOfItems", "q16@0:8", (IMP)NoRecommendationItems);
        ReplaceMethod("FSSearchModel", "recommendShow", "@16@0:8", (IMP)NoSearchRecommendations);

        Method searchHeader = FindMethod("FSSearchModel", "topInfoType", "@16@0:8");
        if (searchHeader) {
            OriginalSearchHeaderType = (NSString *(*)(id, SEL))method_getImplementation(searchHeader);
            method_setImplementation(searchHeader, (IMP)SearchHeaderType);
        }

        SearchProductClass = objc_lookUpClass("FSSearchProductModel");
        SearchProductViewModelClass = objc_lookUpClass("FSSearchProductViewModel");
        SearchTaroViewModelClass = objc_lookUpClass("FSSTaroNativeVM");
        SearchSimpleViewModelClass = objc_lookUpClass("FSSimpleProductVM");
        Method searchRows = FindMethod("FinalSearchListViewController", "p_createVMWithProductModelArray:", "@24@0:8@16");
        if (searchRows && SearchProductClass) {
            OriginalCreateSearchRows = (NSDictionary *(*)(id, SEL, NSArray *))method_getImplementation(searchRows);
            method_setImplementation(searchRows, (IMP)CreateSearchRows);
        }

        Method bottomBanner = FindMethod("JDMainPageBottomXViewBoxModel", "mp_canUse", "B16@0:8");
        if (bottomBanner) {
            OriginalBottomBannerCanUse = (BOOL (*)(id, SEL))method_getImplementation(bottomBanner);
            method_setImplementation(bottomBanner, (IMP)AllowBottomBanner);
        }

        Method homeRecommendation = FindMethod("JDURMulTabBridgeManager", "initBottomCollectionView", "v16@0:8");
        Method homeHeight = FindMethod("JDURMulTabBridgeManager", "getRecommendViewHeight:", "d20@0:8B16");
        if (homeRecommendation && homeHeight) {
            OriginalInitHomeRecommendation = (void (*)(id, SEL))method_getImplementation(homeRecommendation);
            method_setImplementation(homeRecommendation, (IMP)InitHomeRecommendation);
            method_setImplementation(homeHeight, (IMP)NoHomeRecommendationHeight);
        }

        Method detailRecommendation = FindMethod("PDRecommendListFloor", "render", "v16@0:8");
        if (detailRecommendation) {
            OriginalRenderDetailRecommendation = (void (*)(id, SEL))method_getImplementation(detailRecommendation);
            method_setImplementation(detailRecommendation, (IMP)RenderDetailRecommendation);
        }
    }
}
