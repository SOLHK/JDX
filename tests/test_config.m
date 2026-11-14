// Native Foundation integration tests. Compile as a separate test executable.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../JDXConfig.m"
#include <stdio.h>
#include <stdlib.h>

static NSUInteger Checks;
static NSUserDefaults *TestPreferences;
static NSString *TestSuiteName;
static BOOL TestEnhanced;

#define CHECK(condition, explanation) do { \
    Checks++; \
    if (!(condition)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, explanation); \
        exit(1); \
    } \
} while (0)

// Production configuration calls only these two diagnostics functions. Stub
// them so this executable tests configuration without touching log files.
void JDXDiagnosticsSetEnhanced(BOOL enabled) { TestEnhanced = enabled; }
void JDXLog(NSString *event, NSDictionary *fields) { (void)event; (void)fields; }

static NSUserDefaults *IsolatedDefaults(id receiver, SEL selector)
{
    (void)receiver;
    (void)selector;
    return TestPreferences;
}

static void ResetSuite(void)
{
    [TestPreferences removePersistentDomainForName:TestSuiteName];
}

static NSString *RulePreference(JDXRule rule)
{
    return [@"com.solhk.jdx.rule." stringByAppendingString:JDXRuleIdentifier(rule)];
}

static BOOL ExpectedRecommended(JDXRule rule)
{
    // Explicit acceptance policy: six identified presentation-only ad controls
    // on; all-banner, recommendation and search-model changes off by default.
    NSSet *enabled = [NSSet setWithArray:@[@"splash", @"home.ceiling", @"home.float",
        @"home.float916", @"home.two-screen", @"home.bottom-ad"]];
    return [enabled containsObject:JDXRuleIdentifier(rule)];
}

static void CheckRecommended(void)
{
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK(JDXRuleEnabled(rule) == ExpectedRecommended(rule), "recommended profile matches conservative acceptance policy");
        CHECK(JDXShouldBlock(rule) == ExpectedRecommended(rule), "recommended effective behavior matches policy");
    }
}

static void TestInitialDefaults(void)
{
    ResetSuite();
    JDXConfigurationStart(YES);
    CHECK(JDXRuleCount == 14, "all fourteen supported positions have independent configuration");
    NSArray *expectedIDs = @[@"splash", @"home.ceiling", @"home.float", @"home.float916", @"home.two-screen",
        @"home.bottom-ad", @"home.bottom-all", @"home.recommendations", @"search.products", @"search.top-shop",
        @"search.belt-shop", @"search.recommendations", @"my.recommendations", @"detail.recommendations"];
    NSMutableSet *observed = [NSMutableSet set];
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        [observed addObject:JDXRuleIdentifier(rule)];
        CHECK([JDXRuleIdentifier(rule) isEqual:expectedIDs[rule]], "position identifier is stable");
    }
    CHECK(observed.count == 14, "position preference identifiers are unique");
    CHECK(JDXConfigurationCompatible() && JDXMasterEnabled(), "compatible first launch enables master");
    CHECK(!TestEnhanced, "enhanced diagnostics are off by default");
    CheckRecommended();
    CHECK([TestPreferences integerForKey:@"com.solhk.jdx.preference-schema"] == 2, "schema marker is persisted");
}

static void TestLegacyDisabledMigration(void)
{
    ResetSuite();
    [TestPreferences setBool:NO forKey:@"com.solhk.jd-adblock.enabled"];
    JDXConfigurationStart(YES);
    CHECK(!JDXMasterEnabled(), "migration preserves existing disabled master preference");
    NSDictionary *persisted = [TestPreferences persistentDomainForName:TestSuiteName];
    CHECK(persisted[@"com.solhk.jd-adblock.enabled"] != nil &&
          ![persisted[@"com.solhk.jd-adblock.enabled"] boolValue], "migration does not overwrite legacy false with registration default");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK(JDXRuleEnabled(rule) == ExpectedRecommended(rule), "migration initializes each position conservatively");
        CHECK(!JDXShouldBlock(rule), "disabled legacy master prevents every rule from blocking");
    }
    JDXConfigurationStart(YES);
    CHECK(!JDXMasterEnabled(), "subsequent configuration load preserves disabled master");
}

static void TestIndependentSwitches(void)
{
    JDXApplyProfile(JDXProfileKeepAll);
    for (JDXRule selected = 0; selected < JDXRuleCount; selected++) {
        JDXSetRuleEnabled(selected, YES);
        for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
            BOOL expected = rule == selected;
            CHECK(JDXRuleEnabled(rule) == expected, "changing one position leaves every other position unchanged");
            CHECK(JDXShouldBlock(rule) == expected, "only the selected position blocks");
        }
        CHECK([TestPreferences boolForKey:RulePreference(selected)], "individual switch persists its choice");
        JDXSetRuleEnabled(selected, NO);
        CHECK(!JDXRuleEnabled(selected) && !JDXShouldBlock(selected), "individual switch returns to passthrough");
    }
    JDXSetRuleEnabled(JDXRuleCount, YES);
    CHECK(!JDXRuleEnabled(JDXRuleCount) && !JDXShouldBlock(JDXRuleCount), "out-of-range rule fails open");
    CHECK([JDXRuleIdentifier(JDXRuleCount) isEqual:@"unknown"], "invalid rule has a bounded diagnostic identifier");
}

static void TestMasterPreservesIndividualChoices(void)
{
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) JDXSetRuleEnabled(rule, rule % 2 == 0);
    JDXSetMasterEnabled(NO);
    CHECK(!JDXMasterEnabled(), "master disables immediately");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK(!JDXShouldBlock(rule), "disabled master bypasses every rule");
        CHECK(JDXRuleEnabled(rule) == (rule % 2 == 0), "master off preserves each individual preference in memory");
        CHECK([TestPreferences boolForKey:RulePreference(rule)] == (rule % 2 == 0), "master off preserves each persisted preference");
    }
    JDXSetMasterEnabled(YES);
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        CHECK(JDXShouldBlock(rule) == (rule % 2 == 0), "master on restores the user's previous selection");
}

static void TestProfiles(void)
{
    JDXSetMasterEnabled(NO);
    JDXApplyProfile(JDXProfileBlockAll);
    CHECK(JDXMasterEnabled(), "all-block profile enables master");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        CHECK(JDXRuleEnabled(rule) && JDXShouldBlock(rule), "all-block profile enables all fourteen positions");
    JDXApplyProfile(JDXProfileKeepAll);
    CHECK(JDXMasterEnabled(), "keep-all profile leaves configuration active");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        CHECK(!JDXRuleEnabled(rule) && !JDXShouldBlock(rule), "keep-all profile passes through every position");
    JDXApplyProfile(JDXProfileRecommended);
    CHECK(JDXMasterEnabled(), "recommended profile enables master");
    CheckRecommended();
}

static void TestReloadFromPersistence(void)
{
    // Change stored values without going through production setters, then use
    // a fresh NSUserDefaults instance so Start must reread persisted choices.
    [TestPreferences setBool:NO forKey:@"com.solhk.jd-adblock.enabled"];
    [TestPreferences setBool:YES forKey:@"com.solhk.jdx.enhanced-diagnostics"];
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        [TestPreferences setBool:rule % 3 == 1 forKey:RulePreference(rule)];
    CHECK([TestPreferences synchronize], "isolated test preferences are flushed");
    TestPreferences = [[NSUserDefaults alloc] initWithSuiteName:TestSuiteName];
    CHECK(TestPreferences != nil, "fresh defaults instance opens isolated suite");
    JDXConfigurationStart(YES);
    CHECK(!JDXMasterEnabled(), "reload reads persisted master rather than stale atomic state");
    CHECK(TestEnhanced, "reload restores the saved enhanced-diagnostics switch");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK(JDXRuleEnabled(rule) == (rule % 3 == 1), "reload restores each stored position");
        CHECK(!JDXShouldBlock(rule), "reloaded disabled master still passes through all positions");
    }
    JDXSetMasterEnabled(YES);
    JDXSetEnhancedEnabled(NO);
    CHECK(!TestEnhanced && ![TestPreferences boolForKey:@"com.solhk.jdx.enhanced-diagnostics"],
          "enhancement setter updates runtime and persistence");
    NSDictionary *snapshot = JDXConfigurationSnapshot();
    CHECK([snapshot[@"rules"] count] == 14 && [snapshot[@"master_enabled"] boolValue], "export snapshot covers all positions and master");
    CHECK([NSJSONSerialization isValidJSONObject:snapshot], "configuration snapshot is JSON serializable");
    for (NSDictionary *rule in snapshot[@"rules"])
        CHECK([rule[@"requested_active"] boolValue] == [rule[@"enabled"] boolValue], "snapshot reflects effective compatible selection");
}

static void TestIncompatibleVersionPassesThrough(void)
{
    JDXApplyProfile(JDXProfileBlockAll);
    JDXConfigurationStart(NO);
    CHECK(!JDXConfigurationCompatible(), "unsupported version is recorded as incompatible");
    CHECK(JDXMasterEnabled(), "incompatibility does not destroy saved master preference");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK(JDXRuleEnabled(rule), "incompatibility preserves individual choices");
        CHECK(!JDXShouldBlock(rule), "unsupported version passes through even with every switch enabled");
    }
    JDXSetRuleEnabled(JDXRuleSplash, NO);
    JDXSetRuleEnabled(JDXRuleSplash, YES);
    JDXSetMasterEnabled(NO);
    JDXSetMasterEnabled(YES);
    CHECK(!JDXShouldBlock(JDXRuleSplash), "interactive changes cannot bypass compatibility gate");
    NSDictionary *snapshot = JDXConfigurationSnapshot();
    CHECK(![snapshot[@"compatible"] boolValue], "snapshot reports compatibility gate");
    for (NSDictionary *rule in snapshot[@"rules"])
        CHECK(![rule[@"requested_active"] boolValue], "snapshot never reports incompatible blocking as active");
    JDXConfigurationStart(YES);
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        CHECK(JDXShouldBlock(rule), "returning to a compatible host restores persisted selection");
}

int main(void)
{
    @autoreleasepool {
        TestSuiteName = [@"com.solhk.jdx.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        TestPreferences = [[NSUserDefaults alloc] initWithSuiteName:TestSuiteName];
        CHECK(TestPreferences != nil, "isolated preferences suite is created");
        Method standard = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
        CHECK(standard != NULL, "Foundation standard-defaults entry point exists");
        IMP original = method_setImplementation(standard, (IMP)IsolatedDefaults);
        CHECK(NSUserDefaults.standardUserDefaults == TestPreferences, "test process uses only the isolated preferences suite");
        TestInitialDefaults();
        TestLegacyDisabledMigration();
        TestIndependentSwitches();
        TestMasterPreservesIndividualChoices();
        TestProfiles();
        TestReloadFromPersistence();
        TestIncompatibleVersionPassesThrough();
        [TestPreferences removePersistentDomainForName:TestSuiteName];
        CHECK([TestPreferences synchronize], "isolated preferences domain is removed from persistent storage");
        method_setImplementation(standard, original);
        printf("JDX configuration: %lu native Foundation checks passed.\n", (unsigned long)Checks);
        return 0;
    }
}
