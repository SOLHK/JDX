#import "JDXConfig.h"
#import "JDXDiagnostics.h"
#include <stdatomic.h>
#include <stdbool.h>

NSString *const JDXConfigurationDidChangeNotification = @"com.solhk.jdx.configuration-changed";
static NSString *const JDXEnabledKey = @"com.solhk.jd-adblock.enabled";
static NSString *const JDXEnhancedKey = @"com.solhk.jdx.enhanced-diagnostics";
static NSString *const JDXSchemaKey = @"com.solhk.jdx.preference-schema";
static _Atomic(bool) JDXMaster;
static _Atomic(bool) JDXCompatible;
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
    BOOL migrating = [preferences integerForKey:JDXSchemaKey] < 2;
    NSMutableDictionary *defaults = [@{JDXEnabledKey: @YES, JDXEnhancedKey: @NO} mutableCopy];
    for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
        defaults[JDXPreferenceKey(index)] = @(JDXRules[index].recommended);
    }
    [preferences registerDefaults:defaults];
    atomic_store(&JDXCompatible, compatible);
    atomic_store(&JDXMaster, [preferences boolForKey:JDXEnabledKey]);
    for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
        atomic_store(&JDXRuleFlags[index], [preferences boolForKey:JDXPreferenceKey(index)]);
    }
    [preferences setInteger:2 forKey:JDXSchemaKey];
    JDXDiagnosticsSetEnhanced([preferences boolForKey:JDXEnhancedKey]);
    if (migrating) {
        JDXLog(@"configuration_migrated", @{@"schema_version": @2,
            @"profile": @"recommended", @"master_enabled": @(JDXMasterEnabled())});
    }
}

BOOL JDXConfigurationCompatible(void) { return atomic_load(&JDXCompatible); }
BOOL JDXMasterEnabled(void) { return atomic_load(&JDXMaster); }
BOOL JDXRuleEnabled(JDXRule rule) { return rule < JDXRuleCount && atomic_load(&JDXRuleFlags[rule]); }
BOOL JDXShouldBlock(JDXRule rule)
{
    return JDXConfigurationCompatible() && JDXMasterEnabled() && JDXRuleEnabled(rule);
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
    for (NSUInteger index = 0; index < JDXRuleCount; ++index) {
        [rules addObject:@{@"rule_id": JDXRuleIdentifier(index),
            @"enabled": @(JDXRuleEnabled(index)), @"requested_active": @(JDXShouldBlock(index)),
            @"recommended": @(JDXRules[index].recommended)}];
    }
    return @{@"schema_version": @2, @"master_enabled": @(JDXMasterEnabled()),
        @"compatible": @(JDXConfigurationCompatible()), @"rules": rules};
}
