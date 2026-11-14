#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>

#import "JDXConfig.h"
#import "JDXDiagnostics.h"
#import "JDXHookRuntime.h"
#import "JDXSearchFilter.h"
#import "JDXSettings.h"

// A single translation unit also works with the original lightweight builder.
#include "JDXDiagnostics.m"
#include "JDXConfig.m"
#include "JDXSearchFilter.m"

static NSDictionary *JDXEnvironment;
static IMP JDXOriginalSplash;
static IMP JDXOriginalCeiling;
static IMP JDXOriginalFloat;
static IMP JDXOriginalFloat916;
static IMP JDXOriginalTwoScreen;
static IMP JDXOriginalBottomBanner;
static IMP JDXOriginalHomeHeight;
static IMP JDXOriginalHomeInit;
static IMP JDXOriginalSearchRows;
static IMP JDXOriginalSearchHeader;
static IMP JDXOriginalBelt;
static IMP JDXOriginalBeltTn;
static IMP JDXOriginalSearchRecommendation;
static IMP JDXOriginalMyCount;
static IMP JDXOriginalDetailRender;

static void JDXDecision(JDXRule rule, NSString *outcome, NSUInteger amount)
{
    JDXRecordRule(JDXRuleIdentifier(rule), outcome, amount);
}

// Every replacement invokes its own saved original exactly once. The master
// switch and every rule are evaluated at call time, including after installation.
static BOOL JDXBoolGate(id instance, SEL selector, IMP original, JDXRule rule)
{
    BOOL result = ((BOOL (*)(id, SEL))original)(instance, selector);
    if (result && JDXShouldBlock(rule)) {
        JDXDecision(rule, @"blocked", 1);
        return NO;
    }
    JDXDecision(rule, @"passed", 1);
    return result;
}

static BOOL JDXModelGate(id instance, SEL selector, id model, IMP original, JDXRule rule)
{
    BOOL result = ((BOOL (*)(id, SEL, id))original)(instance, selector, model);
    if (result && JDXShouldBlock(rule)) {
        JDXDecision(rule, @"blocked", 1);
        return NO;
    }
    JDXDecision(rule, @"passed", 1);
    return result;
}

static BOOL JDXSplash(id instance, SEL selector)
{ return JDXBoolGate(instance, selector, JDXOriginalSplash, JDXRuleSplash); }
static BOOL JDXCeiling(id instance, SEL selector)
{ return JDXBoolGate(instance, selector, JDXOriginalCeiling, JDXRuleHomeCeiling); }
static BOOL JDXFloat(id instance, SEL selector, id model)
{ return JDXModelGate(instance, selector, model, JDXOriginalFloat, JDXRuleHomeFloat); }
static BOOL JDXFloat916(id instance, SEL selector, id model)
{ return JDXModelGate(instance, selector, model, JDXOriginalFloat916, JDXRuleHomeFloat916); }
static BOOL JDXTwoScreen(id instance, SEL selector, id model)
{ return JDXModelGate(instance, selector, model, JDXOriginalTwoScreen, JDXRuleHomeTwoScreen); }

static id JDXObjectGate(id instance, SEL selector, IMP original, JDXRule rule)
{
    id result = ((id (*)(id, SEL))original)(instance, selector);
    if (result && JDXShouldBlock(rule)) {
        JDXDecision(rule, @"blocked", 1);
        return nil;
    }
    JDXDecision(rule, @"passed", 1);
    return result;
}

static id JDXBelt(id instance, SEL selector)
{ return JDXObjectGate(instance, selector, JDXOriginalBelt, JDXRuleSearchBeltShop); }
static id JDXBeltTn(id instance, SEL selector)
{ return JDXObjectGate(instance, selector, JDXOriginalBeltTn, JDXRuleSearchBeltShop); }

static id JDXSearchHeader(id instance, SEL selector)
{
    id result = ((id (*)(id, SEL))JDXOriginalSearchHeader)(instance, selector);
    if (JDXShouldBlock(JDXRuleSearchTopShop) &&
        ([@"adShop" isEqual:result] || [@"adSlideShop" isEqual:result])) {
        JDXDecision(JDXRuleSearchTopShop, @"blocked", 1);
        return @"";
    }
    JDXDecision(JDXRuleSearchTopShop, @"passed", 1);
    return result;
}

static id JDXSearchRecommendation(id instance, SEL selector)
{
    id result = ((id (*)(id, SEL))JDXOriginalSearchRecommendation)(instance, selector);
    if (JDXShouldBlock(JDXRuleSearchRecommendations) && [result isKindOfClass:NSString.class]) {
        JDXDecision(JDXRuleSearchRecommendations, @"blocked", 1);
        return @"0";
    }
    JDXDecision(JDXRuleSearchRecommendations, @"passed", 1);
    return result;
}

static id JDXSearchRows(id instance, SEL selector, id products)
{
    id result = ((id (*)(id, SEL, id))JDXOriginalSearchRows)(instance, selector, products);
    if (!JDXShouldBlock(JDXRuleSearchProducts)) {
        JDXDecision(JDXRuleSearchProducts, @"passed", 1);
        return result;
    }
    NSUInteger removed = 0;
    NSString *reason = nil;
    id updated = JDXFilterSearchResult(result, &removed, &reason);
    JDXDecision(JDXRuleSearchProducts, removed ? @"blocked" : (reason ?: @"unchanged"), removed ?: 1);
    return updated;
}

static BOOL JDXReadBool(id instance, const char *name, BOOL *value)
{
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(instance), selector);
    if (!method || strcmp(method_getTypeEncoding(method), "B16@0:8") != 0 ||
        ![instance respondsToSelector:selector]) return NO;
    *value = ((BOOL (*)(id, SEL))[instance methodForSelector:selector])(instance, selector);
    return YES;
}

static BOOL JDXBottomBanner(id instance, SEL selector)
{
    BOOL original = ((BOOL (*)(id, SEL))JDXOriginalBottomBanner)(instance, selector);
    if (!original) return original;
    if (JDXShouldBlock(JDXRuleHomeBottomAll)) {
        JDXDecision(JDXRuleHomeBottomAll, @"blocked", 1);
        return NO;
    }
    if (!JDXShouldBlock(JDXRuleHomeBottomAdvertisement)) {
        JDXDecision(JDXRuleHomeBottomAdvertisement, @"passed", 1);
        return original;
    }
    @try {
        id extension = JDXGetObject(instance, "extension_id");
        id business = JDXGetObject(instance, "businessType");
        id condition = JDXGetObject(instance, "showCondition");
        BOOL guide = NO;
        BOOL guideKnown = JDXReadBool(instance, "homeRollBackGuideType", &guide);
        BOOL marked = ([extension isKindOfClass:NSString.class] && [extension length] > 0) ||
            ([extension isKindOfClass:NSNumber.class] && [extension longLongValue] != 0);
        BOOL businessKnown = [business isKindOfClass:NSString.class] || [business isKindOfClass:NSNumber.class];
        BOOL conditionKnown = [condition isKindOfClass:NSString.class] || [condition isKindOfClass:NSNumber.class];
        // Missing metadata is not evidence of advertising.
        if (!marked || !guideKnown || !businessKnown || !conditionKnown) {
            JDXDecision(JDXRuleHomeBottomAdvertisement, @"unknown_banner_metadata", 1);
            return original;
        }
        if ([business integerValue] == 40 || [condition integerValue] == 1 || guide) {
            JDXDecision(JDXRuleHomeBottomAdvertisement, @"functional_banner_preserved", 1);
            return original;
        }
        JDXDecision(JDXRuleHomeBottomAdvertisement, @"blocked", 1);
        return NO;
    } @catch (__unused NSException *exception) {
        JDXDecision(JDXRuleHomeBottomAdvertisement, @"inspection_exception", 1);
        return original;
    }
}

@interface JDXManagedVisibility : NSObject
@property(nonatomic) JDXRule rule;
@property(nonatomic) BOOL applied;
@property(nonatomic) BOOL originalHidden;
@end
@implementation JDXManagedVisibility
@end

static NSHashTable<UIView *> *JDXManagedViews;
static char JDXVisibilityKey;

static BOOL JDXCanApplyVisibility(JDXRule rule)
{
    return JDXShouldBlock(rule) && (rule != JDXRuleHomeRecommendations ||
        (JDXOriginalHomeHeight && JDXOriginalHomeInit));
}

static void JDXApplyVisibility(UIView *view, JDXManagedVisibility *state)
{
    if (JDXCanApplyVisibility(state.rule)) {
        if (!state.applied) {
            state.originalHidden = view.hidden;
            state.applied = YES;
        }
        view.hidden = YES;
    } else if (state.applied) {
        view.hidden = state.originalHidden;
        state.applied = NO;
    }
    [view.superview setNeedsLayout];
}

static void JDXTrackView(id candidate, JDXRule rule)
{
    if (![candidate isKindOfClass:UIView.class]) {
        JDXDecision(rule, @"missing_view", 1);
        return;
    }
    __weak UIView *weakView = candidate;
    void (^update)(void) = ^{
        UIView *view = weakView;
        if (!view) return;
        if (!JDXManagedViews) JDXManagedViews = [NSHashTable weakObjectsHashTable];
        JDXManagedVisibility *state = objc_getAssociatedObject(view, &JDXVisibilityKey);
        if (!state) {
            state = [JDXManagedVisibility new];
            state.rule = rule;
            objc_setAssociatedObject(view, &JDXVisibilityKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [JDXManagedViews addObject:view];
        JDXApplyVisibility(view, state);
    };
    if (NSThread.isMainThread) update(); else dispatch_async(dispatch_get_main_queue(), update);
}

static void JDXRefreshManagedViews(void)
{
    for (UIView *view in JDXManagedViews.allObjects) {
        JDXManagedVisibility *state = objc_getAssociatedObject(view, &JDXVisibilityKey);
        if (state) JDXApplyVisibility(view, state);
    }
}

static double JDXHomeHeight(id instance, SEL selector, BOOL flag)
{
    double original = ((double (*)(id, SEL, BOOL))JDXOriginalHomeHeight)(instance, selector, flag);
    if (JDXCanApplyVisibility(JDXRuleHomeRecommendations)) {
        JDXDecision(JDXRuleHomeRecommendations, @"height_hidden", 1);
        return 0;
    }
    return original;
}

static void JDXHomeInit(id instance, SEL selector)
{
    ((void (*)(id, SEL))JDXOriginalHomeInit)(instance, selector);
    @try {
        JDXTrackView(JDXGetObject(instance, "bottomCollectionView"), JDXRuleHomeRecommendations);
    } @catch (__unused NSException *exception) {
        JDXDecision(JDXRuleHomeRecommendations, @"inspection_exception", 1);
    }
}

static NSInteger JDXMyCount(id instance, SEL selector)
{
    NSInteger original = ((NSInteger (*)(id, SEL))JDXOriginalMyCount)(instance, selector);
    if (JDXShouldBlock(JDXRuleMyRecommendations)) {
        JDXDecision(JDXRuleMyRecommendations, @"blocked", original > 0 ? (NSUInteger)original : 1);
        return 0;
    }
    return original;
}

static void JDXDetailRender(id instance, SEL selector)
{
    ((void (*)(id, SEL))JDXOriginalDetailRender)(instance, selector);
    @try {
        JDXTrackView(JDXGetObject(instance, "view"), JDXRuleDetailRecommendations);
        if (JDXShouldBlock(JDXRuleDetailRecommendations))
            JDXDecision(JDXRuleDetailRecommendations, @"view_hidden", 1);
    } @catch (__unused NSException *exception) {
        JDXDecision(JDXRuleDetailRecommendations, @"inspection_exception", 1);
    }
}

typedef struct {
    const char *className;
    const char *selector;
    const char *encoding;
    IMP replacement;
    IMP *original;
    JDXRule rule;
    JDXHookReceipt receipt;
    BOOL installed;
    NSUInteger attempts;
} JDXHook;

#define JDX_HOOK(cls, sel, enc, hook, saved, rule) \
    { cls, sel, enc, (IMP)hook, &saved, rule, {0, NULL, NULL}, NO, 0 }
static JDXHook JDXHooks[] = {
    JDX_HOOK("LaunchAnimationManager", "canShowLaunchADView", "B16@0:8", JDXSplash, JDXOriginalSplash, JDXRuleSplash),
    JDX_HOOK("JDMainPageFloatPhotoCeilingModel", "canShowCeilingPhoto", "B16@0:8", JDXCeiling, JDXOriginalCeiling, JDXRuleHomeCeiling),
    JDX_HOOK("JDMainPageViewController", "shouldDisplayFloat:", "B24@0:8@16", JDXFloat, JDXOriginalFloat, JDXRuleHomeFloat),
    JDX_HOOK("JDMainPageViewController", "shouldDisplayFloat916:", "B24@0:8@16", JDXFloat916, JDXOriginalFloat916, JDXRuleHomeFloat916),
    JDX_HOOK("JDMainPageViewController", "shouldShowTwoScreenFloatViewForModel:", "B24@0:8@16", JDXTwoScreen, JDXOriginalTwoScreen, JDXRuleHomeTwoScreen),
    JDX_HOOK("JDMainPageBottomXViewBoxModel", "mp_canUse", "B16@0:8", JDXBottomBanner, JDXOriginalBottomBanner, JDXRuleHomeBottomAdvertisement),
    JDX_HOOK("JDURMulTabBridgeManager", "getRecommendViewHeight:", "d20@0:8B16", JDXHomeHeight, JDXOriginalHomeHeight, JDXRuleHomeRecommendations),
    JDX_HOOK("JDURMulTabBridgeManager", "initBottomCollectionView", "v16@0:8", JDXHomeInit, JDXOriginalHomeInit, JDXRuleHomeRecommendations),
    JDX_HOOK("FinalSearchListViewController", "p_createVMWithProductModelArray:", "@24@0:8@16", JDXSearchRows, JDXOriginalSearchRows, JDXRuleSearchProducts),
    JDX_HOOK("FSSearchModel", "topInfoType", "@16@0:8", JDXSearchHeader, JDXOriginalSearchHeader, JDXRuleSearchTopShop),
    JDX_HOOK("FSSearchModel", "beltAdShop", "@16@0:8", JDXBelt, JDXOriginalBelt, JDXRuleSearchBeltShop),
    JDX_HOOK("FSSearchModel", "beltAdShopTn", "@16@0:8", JDXBeltTn, JDXOriginalBeltTn, JDXRuleSearchBeltShop),
    JDX_HOOK("FSSearchModel", "recommendShow", "@16@0:8", JDXSearchRecommendation, JDXOriginalSearchRecommendation, JDXRuleSearchRecommendations),
    JDX_HOOK("MyJdRecommendFloor15250", "myjd_numberOfItems", "q16@0:8", JDXMyCount, JDXOriginalMyCount, JDXRuleMyRecommendations),
    JDX_HOOK("PDRecommendListFloor", "render", "v16@0:8", JDXDetailRender, JDXOriginalDetailRender, JDXRuleDetailRecommendations),
};
#undef JDX_HOOK

static NSString *JDXHookStatusName(int status)
{
    switch (status) {
        case JDXHookInstalledOwn: return @"installed_own";
        case JDXHookInstalledOverride: return @"installed_override";
        case JDXHookAlreadyInstalled: return @"already_installed";
        case JDXHookMissingClass: return @"missing_class";
        case JDXHookMissingMethod: return @"missing_method";
        case JDXHookTypeMismatch: return @"type_mismatch";
        case JDXHookFailed: return @"failed_open";
        default: return @"not_attempted";
    }
}

static NSDictionary *JDXHookState(JDXHook *hook)
{
    Class cls = objc_lookUpClass(hook->className);
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName(hook->selector)) : NULL;
    NSString *status = JDXConfigurationCompatible() ? JDXHookStatusName(hook->receipt.status) : @"unsupported_version";
    BOOL entryMatches = hook->installed && method && method_getImplementation(method) == hook->replacement;
    if (hook->installed && !entryMatches) status = @"wrapped_or_replaced";
    NSMutableDictionary *state = [@{@"class": @(hook->className), @"selector": @(hook->selector),
        @"rule_id": JDXRuleIdentifier(hook->rule), @"status": status,
        @"original_owner": hook->receipt.ownerName ? @(hook->receipt.ownerName) : @"",
        @"expected_encoding": @(hook->encoding),
        @"actual_encoding": hook->receipt.actualEncoding ? @(hook->receipt.actualEncoding) : @"",
        @"installed": @(hook->installed), @"entry_matches": @(entryMatches),
        @"attempts": @(hook->attempts), @"enabled": @(JDXShouldBlock(hook->rule))} mutableCopy];
    if (hook->rule == JDXRuleHomeBottomAdvertisement) {
        state[@"secondary_rule_id"] = JDXRuleIdentifier(JDXRuleHomeBottomAll);
        state[@"secondary_enabled"] = @(JDXShouldBlock(JDXRuleHomeBottomAll));
        state[@"enabled"] = @(JDXShouldBlock(hook->rule) || JDXShouldBlock(JDXRuleHomeBottomAll));
    }
    if (hook->rule == JDXRuleHomeRecommendations)
        state[@"paired_hooks_ready"] = @(JDXOriginalHomeHeight && JDXOriginalHomeInit);
    return state;
}

static BOOL JDXHomePairAvailable(void)
{
    Class cls = objc_lookUpClass("JDURMulTabBridgeManager");
    Method first = class_getInstanceMethod(cls, sel_registerName("getRecommendViewHeight:"));
    Method second = class_getInstanceMethod(cls, sel_registerName("initBottomCollectionView"));
    return first && second && strcmp(method_getTypeEncoding(first), "d20@0:8B16") == 0 &&
        strcmp(method_getTypeEncoding(second), "v16@0:8") == 0;
}

static void JDXInstallKnownHooks(void)
{
    if (!JDXConfigurationCompatible()) return;
    for (NSUInteger index = 0; index < sizeof(JDXHooks) / sizeof(JDXHooks[0]); ++index) {
        JDXHook *hook = &JDXHooks[index];
        if (hook->installed || hook->attempts >= 4) continue;
        hook->attempts++;
        if (hook->rule == JDXRuleHomeRecommendations && !JDXHomePairAvailable()) {
            hook->receipt.status = JDXHookFailed;
        } else {
            hook->installed = JDXInstallInstanceHook(hook->className, hook->selector, hook->encoding,
                hook->replacement, hook->original, &hook->receipt);
        }
        JDXRecordHook(JDXHookState(hook));
    }
}

NSDictionary *JDXRuntimeSnapshot(void)
{
    NSMutableArray *hooks = [NSMutableArray array];
    NSUInteger installed = 0;
    for (NSUInteger index = 0; index < sizeof(JDXHooks) / sizeof(JDXHooks[0]); ++index) {
        [hooks addObject:JDXHookState(&JDXHooks[index])];
        installed += JDXHooks[index].installed ? 1 : 0;
    }
    return @{@"environment": JDXEnvironment ?: @{}, @"configuration": JDXConfigurationSnapshot(),
        @"hooks": hooks, @"installed_hooks": @(installed), @"total_hooks": @(hooks.count),
        @"network_interception": @NO, @"device_validation": @"pending"};
}

void JDXRunDiagnostics(void)
{
    JDXInstallKnownHooks();
    for (NSUInteger index = 0; index < sizeof(JDXHooks) / sizeof(JDXHooks[0]); ++index)
        JDXRecordHook(JDXHookState(&JDXHooks[index]));
    JDXLog(@"diagnostics_checked", @{@"compatible": @(JDXConfigurationCompatible()),
        @"master_enabled": @(JDXMasterEnabled())});
}

static BOOL JDXKnownVersion(NSString *version, NSString *build)
{
    // Re-signing tools sometimes normalize the two version fields.
    return ([version isEqual:@"171204"] && [build isEqual:@"16.1.83"]) ||
        ([version isEqual:@"16.1.83"] && [build isEqual:@"171204"]);
}

__attribute__((constructor)) static void JDXStart(void)
{
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSString *identifier = bundle.bundleIdentifier ?: @"";
        NSString *executable = [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
        if (![identifier isEqual:@"com.360buy.jdmobile"] &&
            ![identifier hasPrefix:@"com.360buy.jdmobile."] &&
            ![executable isEqual:@"JD4iPhone"]) return;
        NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
        NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
        BOOL compatible = JDXKnownVersion(version, build);
        JDXEnvironment = @{@"plugin_version": @JDX_BUILD_VERSION, @"bundle_id": identifier,
            @"app_version": version, @"app_build": build,
            @"ios_version": UIDevice.currentDevice.systemVersion,
            @"compatible": @(compatible), @"architecture": @"arm64"};
        JDXDiagnosticsStart(JDXEnvironment);
        JDXConfigurationStart(compatible);
        if (NSThread.isMainThread) JDXInstallKnownHooks();
        dispatch_async(dispatch_get_main_queue(), ^{
            JDXInstallKnownHooks();
            JDXInstallSettingsEntry();
            [NSNotificationCenter.defaultCenter addObserverForName:JDXConfigurationDidChangeNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    JDXRefreshManagedViews();
                }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    JDXInstallKnownHooks();
                }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ JDXInstallKnownHooks(); });
        });
    }
}

#include "JDXSettings.m"
