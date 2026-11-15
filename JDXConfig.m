#import "JDXConfig.h"
#import "JDXDiagnostics.h"
#include <stdatomic.h>
#include <stdbool.h>

NSString *const JDXConfigurationDidChangeNotification = @"com.solhk.jdx.configuration-changed";
static NSString *const JDXEnabledKey = @"com.solhk.jd-adblock.enabled";
static NSString *const JDXEnhancedKey = @"com.solhk.jdx.enhanced-diagnostics";
static NSString *const JDXSchemaKey = @"com.solhk.jdx.preference-schema";
static NSString *const JDXSafeModeKey = @"com.solhk.jdx.safe-mode";
static NSString *const JDXMigrationKey = @"com.solhk.jdx.migration.schema3";
static _Atomic(bool) JDXMaster;
static _Atomic(bool) JDXCompatible;
// Fail open even if a caller asks before ConfigurationStart has run.
static _Atomic(bool) JDXRequestedSafeMode = true;
static _Atomic(bool) JDXSessionSafeMode = true;
static _Atomic(bool) JDXRuleFlags[JDXRuleCount];

const JDXRuleDefinition JDXRules[JDXRuleCount] = {
    {"splash", "开屏广告", "冷启动与已识别的返回前台开屏展示。", 0, YES},
    {"home.ceiling", "首页顶部动图推广", "拦截顶部推广素材，不隐藏搜索栏和频道导航。", 1, YES},
    {"home.float", "首页普通悬浮卡", "普通样式的首页悬浮推广。", 1, YES},
    {"home.float916", "首页 9:16 悬浮卡", "9:16 样式的首页悬浮推广。", 1, YES},
    {"home.two-screen", "首页双屏悬浮卡", "双屏样式的首页悬浮推广。", 1, YES},
    {"home.bottom-ad", "首页底部广告横幅", "按已知广告标记拦截；保留登录、定位奖励和功能引导。", 1, YES},
    {"home.bottom-all", "首页底部所有横幅", "隐藏这个位置的全部横幅，包括奖励与功能引导；优先于上一项。", 1, NO},
    {"home.recommendations", "首页商品推荐流", "开启后会隐藏正常商品推荐，首页中部可能留白。默认保留。", 1, NO},
    {"search.products", "搜索付费商品卡", "仅在列表与网格模型完整配对时过滤；异常结构原样放行。默认保留，建议逐项测试。", 2, NO},
    {"search.top-shop", "搜索顶部店铺广告", "仅处理 adShop / adSlideShop 类型。默认保留，建议逐项测试。", 2, NO},
    {"search.belt-shop", "搜索列表店铺广告条", "拦截已识别的两类店铺广告条模型。默认保留，建议逐项测试。", 2, NO},
    {"search.recommendations", "搜索尾部推荐", "关闭搜索结果后的推荐分页，保留原始搜索结果。默认保留。", 2, NO},
    {"my.recommendations", "「我的」页商品推荐", "只针对已识别的推荐楼层，不处理订单、资产或账户信息。默认保留。", 3, NO},
    {"detail.recommendations", "商品详情底部推荐", "只隐藏原生商品详情的推荐楼层。默认保留。", 3, NO},
};

NSString *JDXRuleIdentifier(JDXRule rule)
{
    return rule < JDXRuleCount ? @(JDXRules[rule].identifier) : @"unknown";
}

static NSString *JDXPreferenceKey(JDXRule rule)
{
    return [@"com.solhk.jdx.rule." stringByAppendingString:JDXRuleIdentifier(rule)];
}

void JDXConfigurationStart(BOOL compatible)
{
    NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
    NSInteger previousSchema = [preferences integerForKey:JDXSchemaKey];
    BOOL migrating = previousSchema < 3;
    NSMutableDictionary *defaults = [@{JDXEnabledKey: @YES, JDXEnhancedKey: @NO,
                                      JDXSafeModeKey: @YES} mutableCopy];
    for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
        defaults[JDXPreferenceKey(index)] = @(JDXRules[index].recommended);
    }
    [preferences registerDefaults:defaults];

    if (migrating) {
        // 0.2.x's "block all" also removed ordinary recommendation content.
        // Recover that exact preset, while preserving every other custom setup.
        BOOL restoreRecommended = previousSchema == 2;
        NSMutableDictionary *previousRules = [NSMutableDictionary dictionary];
        for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
            BOOL enabled = [preferences boolForKey:JDXPreferenceKey(index)];
            previousRules[JDXRuleIdentifier(index)] = @(enabled);
            restoreRecommended = restoreRecommended && enabled;
        }
        NSMutableDictionary *migration = [@{@"from_schema": @(previousSchema),
            @"to_schema": @3, @"safe_mode_default": @YES,
            @"restored_recommended": @(restoreRecommended),
            @"profile": restoreRecommended ? @"recommended" : @"preserved"} mutableCopy];
        if (restoreRecommended) {
            // Back up only plugin-owned flags, never host defaults or account data.
            migration[@"previous_configuration"] = @{
                @"master_enabled": @([preferences boolForKey:JDXEnabledKey]),
                @"rules": previousRules};
            for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
                [preferences setBool:JDXRules[index].recommended forKey:JDXPreferenceKey(index)];
            }
        }
        [preferences setObject:migration forKey:JDXMigrationKey];
        [preferences setBool:YES forKey:JDXSafeModeKey];
        [preferences setInteger:3 forKey:JDXSchemaKey];
    }

    atomic_store(&JDXCompatible, compatible);
    atomic_store(&JDXMaster, [preferences boolForKey:JDXEnabledKey]);
    BOOL safeMode = [preferences boolForKey:JDXSafeModeKey];
    atomic_store(&JDXRequestedSafeMode, safeMode);
    atomic_store(&JDXSessionSafeMode, safeMode);
    for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
        atomic_store(&JDXRuleFlags[index], [preferences boolForKey:JDXPreferenceKey(index)]);
    }
    JDXDiagnosticsSetEnhanced([preferences boolForKey:JDXEnhancedKey]);
    if (migrating) {
        JDXLog(@"configuration_migrated", @{@"schema_version": @3,
            @"from_schema": @(previousSchema), @"safe_mode": @(safeMode),
            @"restored_recommended": [preferences dictionaryForKey:JDXMigrationKey][@"restored_recommended"],
            @"master_enabled": @(JDXMasterEnabled())});
    }
}

BOOL JDXConfigurationCompatible(void) { return atomic_load(&JDXCompatible); }
BOOL JDXMasterEnabled(void) { return atomic_load(&JDXMaster); }
BOOL JDXSafeModeEnabled(void) { return atomic_load(&JDXRequestedSafeMode); }
BOOL JDXSafeModeActive(void) { return atomic_load(&JDXSessionSafeMode); }
BOOL JDXRestartRequired(void) { return JDXSafeModeEnabled() != JDXSafeModeActive(); }
BOOL JDXRuleEnabled(JDXRule rule) { return rule < JDXRuleCount && atomic_load(&JDXRuleFlags[rule]); }
BOOL JDXShouldBlock(JDXRule rule)
{
    return !JDXSafeModeActive() && !JDXSafeModeEnabled() &&
        JDXConfigurationCompatible() && JDXMasterEnabled() && JDXRuleEnabled(rule);
}

static void JDXAnnounceConfiguration(void)
{
    void (^announce)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:JDXConfigurationDidChangeNotification object:nil];
    };
    if (NSThread.isMainThread) announce(); else dispatch_async(dispatch_get_main_queue(), announce);
}

void JDXSetMasterEnabled(BOOL enabled)
{
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:JDXEnabledKey];
    atomic_store(&JDXMaster, enabled);
    JDXLog(@"master_changed", @{@"enabled": @(enabled)});
    JDXAnnounceConfiguration();
}

void JDXSetSafeModeEnabled(BOOL enabled)
{
    // Stop blocking before persisting/announcing so already-installed hooks
    // become transparent as soon as the user requests a clean launch.
    atomic_store(&JDXRequestedSafeMode, enabled);
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:JDXSafeModeKey];
    JDXLog(@"safe_mode_changed", @{@"safe_mode": @(enabled),
        @"session_safe_mode": @(JDXSafeModeActive()),
        @"restart_required": @(JDXRestartRequired())});
    JDXAnnounceConfiguration();
}

void JDXSetRuleEnabled(JDXRule rule, BOOL enabled)
{
    if (rule >= JDXRuleCount) return;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:JDXPreferenceKey(rule)];
    atomic_store(&JDXRuleFlags[rule], enabled);
    JDXLog(@"rule_changed", @{@"rule_id": JDXRuleIdentifier(rule), @"enabled": @(enabled)});
    JDXAnnounceConfiguration();
}

void JDXSetEnhancedEnabled(BOOL enabled)
{
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:JDXEnhancedKey];
    JDXDiagnosticsSetEnhanced(enabled);
    JDXAnnounceConfiguration();
}

void JDXApplyProfile(JDXProfile profile)
{
    NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
    for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
        BOOL enabled = profile == JDXProfileBlockAll ||
            (profile == JDXProfileRecommended && JDXRules[index].recommended);
        [preferences setBool:enabled forKey:JDXPreferenceKey(index)];
        atomic_store(&JDXRuleFlags[index], enabled);
    }
    [preferences setBool:YES forKey:JDXEnabledKey];
    atomic_store(&JDXMaster, true);
    NSString *name = profile == JDXProfileRecommended ? @"recommended" :
        (profile == JDXProfileBlockAll ? @"block_all" : @"keep_all");
    JDXLog(@"profile_changed", @{@"profile": name});
    JDXAnnounceConfiguration();
}

NSDictionary *JDXConfigurationSnapshot(void)
{
    NSMutableArray *rules = [NSMutableArray array];
    BOOL allEnabled = YES;
    BOOL allDisabled = YES;
    BOOL recommended = YES;
    for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
        BOOL enabled = JDXRuleEnabled(index);
        allEnabled = allEnabled && enabled;
        allDisabled = allDisabled && !enabled;
        recommended = recommended && enabled == JDXRules[index].recommended;
        [rules addObject:@{@"rule_id": JDXRuleIdentifier(index),
            @"enabled": @(enabled), @"requested_active": @(JDXShouldBlock(index)),
            @"recommended": @(JDXRules[index].recommended)}];
    }
    NSString *profile = allEnabled ? @"block_all" : (allDisabled ? @"keep_all" :
        (recommended ? @"recommended" : @"custom"));
    NSDictionary *migration = [NSUserDefaults.standardUserDefaults dictionaryForKey:JDXMigrationKey];
    return @{@"schema_version": @3, @"master_enabled": @(JDXMasterEnabled()),
        @"compatible": @(JDXConfigurationCompatible()), @"rules": rules,
        @"safe_mode": @(JDXSafeModeEnabled()), @"session_safe_mode": @(JDXSafeModeActive()),
        @"restart_required": @(JDXRestartRequired()), @"profile": profile,
        @"migration": migration ?: @{}};
}
