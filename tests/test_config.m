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

static void CheckRecommended(BOOL expectBlocking)
{
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK(JDXRuleEnabled(rule) == ExpectedRecommended(rule), "recommended profile matches conservative acceptance policy");
        CHECK(JDXShouldBlock(rule) == (expectBlocking && ExpectedRecommended(rule)), "recommended effective behavior respects launch mode");
    }
}

static void CheckPassthrough(void)
{
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        CHECK(!JDXShouldBlock(rule), "every rule passes through while a safety gate is active");
    NSDictionary *snapshot = JDXConfigurationSnapshot();
    for (NSDictionary *rule in snapshot[@"rules"])
        CHECK(![rule[@"requested_active"] boolValue], "diagnostics never report a gated rule as active");
}

// Calling Start again represents a new process launch in this configuration-only
// executable. Setters must never change the session mode between those calls.
static void StartNormalConfiguration(void)
{
    ResetSuite();
    JDXConfigurationStart(YES);
    JDXSetSafeModeEnabled(NO);
    CHECK(JDXSafeModeActive() && !JDXSafeModeEnabled() && JDXRestartRequired(),
          "opting out after a clean launch requires a restart");
    JDXConfigurationStart(YES);
    CHECK(!JDXSafeModeActive() && !JDXSafeModeEnabled() && !JDXRestartRequired(),
          "explicit next launch applies the persisted normal-mode choice");
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
    CHECK(JDXSafeModeEnabled() && JDXSafeModeActive() && !JDXRestartRequired(), "first launch is clean even with master enabled");
    CheckRecommended(NO);
    CheckPassthrough();
    NSDictionary *persisted = [TestPreferences persistentDomainForName:TestSuiteName];
    CHECK([persisted[@"com.solhk.jdx.preference-schema"] integerValue] == 3, "schema marker is persisted");
    CHECK([persisted[@"com.solhk.jdx.safe-mode"] boolValue], "first-launch safe mode is persisted rather than only registered");
    NSDictionary *snapshot = JDXConfigurationSnapshot();
    CHECK([snapshot[@"schema_version"] integerValue] == 3, "export uses configuration schema three");
    CHECK([snapshot[@"safe_mode"] boolValue] && [snapshot[@"session_safe_mode"] boolValue] &&
          ![snapshot[@"restart_required"] boolValue], "export distinguishes requested and current launch modes");
    CHECK([snapshot[@"profile"] isEqual:@"recommended"], "saved recommended profile is visible even in clean mode");
    CHECK([NSJSONSerialization isValidJSONObject:snapshot], "first-launch migration metadata is JSON serializable");
}

static void TestLegacyDisabledMigration(void)
{
    ResetSuite();
    [TestPreferences setBool:NO forKey:@"com.solhk.jd-adblock.enabled"];
    JDXConfigurationStart(YES);
    CHECK(!JDXMasterEnabled(), "migration preserves existing disabled master preference");
    CHECK(JDXSafeModeEnabled() && JDXSafeModeActive(), "legacy migration starts in clean mode");
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

static void TestSchemaTwoBlockAllMigration(void)
{
    ResetSuite();
    [TestPreferences setInteger:2 forKey:@"com.solhk.jdx.preference-schema"];
    [TestPreferences setBool:NO forKey:@"com.solhk.jd-adblock.enabled"];
    [TestPreferences setBool:NO forKey:@"com.solhk.jdx.safe-mode"];
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        [TestPreferences setBool:YES forKey:RulePreference(rule)];
    JDXConfigurationStart(YES);
    CHECK(JDXSafeModeEnabled() && JDXSafeModeActive(), "schema-two upgrade forces the first clean launch");
    CHECK(!JDXMasterEnabled(), "recovering block-all never changes the master preference");
    CheckRecommended(NO);
    NSDictionary *migration = [TestPreferences dictionaryForKey:@"com.solhk.jdx.migration.schema3"];
    CHECK([migration[@"from_schema"] integerValue] == 2 && [migration[@"to_schema"] integerValue] == 3,
          "migration metadata identifies both versions");
    CHECK([migration[@"restored_recommended"] boolValue] && [migration[@"profile"] isEqual:@"recommended"],
          "exact old block-all preset is recovered to the recommended profile");
    NSDictionary *previous = migration[@"previous_configuration"];
    CHECK(previous.count == 2 && ![previous[@"master_enabled"] boolValue], "backup contains only plugin master and rule flags");
    CHECK([previous[@"rules"] count] == 14, "all fourteen previous choices are backed up");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK([previous[@"rules"][JDXRuleIdentifier(rule)] boolValue], "backup preserves every previous enabled flag");
        CHECK([TestPreferences boolForKey:RulePreference(rule)] == ExpectedRecommended(rule),
              "recommended recovery is persisted for each position");
    }
    CHECK([JDXConfigurationSnapshot()[@"migration"] isEqual:migration], "export exposes the plugin-only migration backup");
    JDXSetSafeModeEnabled(NO);
    JDXApplyProfile(JDXProfileBlockAll);
    CheckPassthrough();
    CHECK([TestPreferences synchronize], "upgraded choices are flushed before reopening defaults");
    TestPreferences = [[NSUserDefaults alloc] initWithSuiteName:TestSuiteName];
    JDXConfigurationStart(YES);
    CHECK(!JDXSafeModeEnabled() && !JDXSafeModeActive(), "schema-three reload preserves the user's chosen launch mode");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        CHECK(JDXRuleEnabled(rule) && JDXShouldBlock(rule), "schema-three block-all is never repeatedly reset by migration");
    CHECK([[TestPreferences dictionaryForKey:@"com.solhk.jdx.migration.schema3"] isEqual:migration],
          "one-time migration backup is not overwritten on subsequent launches");
}

static void TestSchemaTwoCustomMigration(void)
{
    ResetSuite();
    [TestPreferences setInteger:2 forKey:@"com.solhk.jdx.preference-schema"];
    [TestPreferences setBool:NO forKey:@"com.solhk.jd-adblock.enabled"];
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        [TestPreferences setBool:rule % 2 == 0 forKey:RulePreference(rule)];
    JDXConfigurationStart(YES);
    CHECK(JDXSafeModeEnabled() && JDXSafeModeActive() && !JDXMasterEnabled(),
          "custom upgrade changes only launch safety, preserving the disabled master");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++) {
        CHECK(JDXRuleEnabled(rule) == (rule % 2 == 0), "migration retains each custom rule selection");
        CHECK([TestPreferences boolForKey:RulePreference(rule)] == (rule % 2 == 0), "custom selections remain persisted");
    }
    NSDictionary *migration = JDXConfigurationSnapshot()[@"migration"];
    CHECK(![migration[@"restored_recommended"] boolValue] && [migration[@"profile"] isEqual:@"preserved"],
          "custom setup is marked preserved rather than reset");
    CHECK(migration[@"previous_configuration"] == nil, "custom setup needs no rewritten-profile backup");
    CHECK([JDXConfigurationSnapshot()[@"profile"] isEqual:@"custom"], "snapshot identifies custom selection accurately");
    CheckPassthrough();

    // A missing optional flag must not be mistaken for the all-enabled preset.
    ResetSuite();
    [TestPreferences setInteger:2 forKey:@"com.solhk.jdx.preference-schema"];
    for (JDXRule rule = 0; rule + 1 < JDXRuleCount; rule++)
        [TestPreferences setBool:YES forKey:RulePreference(rule)];
    JDXConfigurationStart(YES);
    CHECK(![JDXConfigurationSnapshot()[@"migration"][@"restored_recommended"] boolValue],
          "partial stored preferences are not treated as an exact old block-all preset");
    CHECK(JDXRuleEnabled(JDXRuleSearchProducts) && !JDXRuleEnabled(JDXRuleDetailRecommendations),
          "partial custom setup keeps explicit choices and fills only missing defaults");
}

static void TestSafeModeTransitions(void)
{
    StartNormalConfiguration();
    JDXApplyProfile(JDXProfileBlockAll);
    CHECK(JDXShouldBlock(JDXRuleSplash), "normal launch begins with working rule selection");
    JDXSetSafeModeEnabled(YES);
    CHECK(JDXSafeModeEnabled() && !JDXSafeModeActive() && JDXRestartRequired(),
          "requesting clean mode does not claim existing hooks were uninstalled");
    CHECK([TestPreferences boolForKey:@"com.solhk.jdx.safe-mode"], "clean-mode choice persists immediately");
    CheckPassthrough();
    NSDictionary *pending = JDXConfigurationSnapshot();
    CHECK([pending[@"safe_mode"] boolValue] && ![pending[@"session_safe_mode"] boolValue] &&
          [pending[@"restart_required"] boolValue], "snapshot accurately describes pending clean restart");
    for (JDXProfile profile = JDXProfileRecommended; profile <= JDXProfileKeepAll; profile++) {
        JDXApplyProfile(profile);
        JDXSetMasterEnabled(NO);
        JDXSetMasterEnabled(YES);
        JDXSetRuleEnabled(JDXRuleSplash, YES);
        CHECK(JDXSafeModeEnabled() && !JDXSafeModeActive(), "quick profiles and master cannot cancel the requested clean launch");
        CheckPassthrough();
    }
    JDXApplyProfile(JDXProfileBlockAll);
    JDXSetSafeModeEnabled(NO);
    CHECK(!JDXSafeModeEnabled() && !JDXSafeModeActive() && !JDXRestartRequired(),
          "cancelling a pending clean launch retains the existing normal-session hooks");
    CHECK(JDXShouldBlock(JDXRuleSplash), "explicit cancellation in a normal session can resume existing rules");

    JDXSetSafeModeEnabled(YES);
    JDXConfigurationStart(YES);
    CHECK(JDXSafeModeEnabled() && JDXSafeModeActive() && !JDXRestartRequired(),
          "next process launch actually enters clean mode");
    CheckPassthrough();
    JDXSetSafeModeEnabled(NO);
    CHECK(!JDXSafeModeEnabled() && JDXSafeModeActive() && JDXRestartRequired(),
          "disabling clean mode cannot install hooks into an already clean session");
    pending = JDXConfigurationSnapshot();
    CHECK(![pending[@"safe_mode"] boolValue] && [pending[@"session_safe_mode"] boolValue] &&
          [pending[@"restart_required"] boolValue], "snapshot accurately describes pending normal restart");
    for (JDXProfile profile = JDXProfileRecommended; profile <= JDXProfileKeepAll; profile++) {
        JDXApplyProfile(profile);
        JDXSetMasterEnabled(NO);
        JDXSetMasterEnabled(YES);
        JDXSetRuleEnabled(JDXRuleSplash, YES);
        CHECK(!JDXSafeModeEnabled() && JDXSafeModeActive(), "interactive changes never mutate the fixed current launch mode");
        CheckPassthrough();
    }
    JDXSetSafeModeEnabled(YES);
    CHECK(!JDXRestartRequired() && JDXSafeModeActive(), "cancelling a pending normal launch keeps clean mode active");
    JDXSetSafeModeEnabled(NO);
    JDXApplyProfile(JDXProfileRecommended);
    JDXConfigurationStart(YES);
    CHECK(!JDXSafeModeEnabled() && !JDXSafeModeActive() && !JDXRestartRequired(),
          "restart clears pending status and permits the saved normal-mode rules");
    CheckRecommended(YES);
}

static void TestIndependentSwitches(void)
{
    StartNormalConfiguration();
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
    StartNormalConfiguration();
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
    StartNormalConfiguration();
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
    CheckRecommended(YES);
}

static void TestReloadFromPersistence(void)
{
    StartNormalConfiguration();
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
    CHECK(!JDXSafeModeEnabled() && !JDXSafeModeActive() && !JDXRestartRequired(),
          "repeated schema-three load preserves normal launch instead of reapplying first-launch defaults");
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
    StartNormalConfiguration();
    JDXApplyProfile(JDXProfileBlockAll);
    JDXConfigurationStart(NO);
    CHECK(!JDXConfigurationCompatible(), "unsupported version is recorded as incompatible");
    CHECK(!JDXSafeModeEnabled() && !JDXSafeModeActive(), "compatibility is tested independently of the clean-mode gate");
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

static void TestFutureSchemaIsNotDowngraded(void)
{
    ResetSuite();
    [TestPreferences setInteger:4 forKey:@"com.solhk.jdx.preference-schema"];
    [TestPreferences setBool:NO forKey:@"com.solhk.jdx.safe-mode"];
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        [TestPreferences setBool:YES forKey:RulePreference(rule)];
    JDXConfigurationStart(YES);
    CHECK([TestPreferences integerForKey:@"com.solhk.jdx.preference-schema"] == 4,
          "an unknown newer preference schema is not downgraded");
    CHECK(!JDXSafeModeEnabled() && !JDXSafeModeActive(), "newer stored choices are not treated as an old migration");
    CHECK([TestPreferences dictionaryForKey:@"com.solhk.jdx.migration.schema3"] == nil,
          "no migration backup is fabricated for a newer schema");
    for (JDXRule rule = 0; rule < JDXRuleCount; rule++)
        CHECK(JDXRuleEnabled(rule), "known individual preferences survive a newer schema unchanged");
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
        TestSchemaTwoBlockAllMigration();
        TestSchemaTwoCustomMigration();
        TestSafeModeTransitions();
        TestIndependentSwitches();
        TestMasterPreservesIndividualChoices();
        TestProfiles();
        TestReloadFromPersistence();
        TestIncompatibleVersionPassesThrough();
        TestFutureSchemaIsNotDowngraded();
        [TestPreferences removePersistentDomainForName:TestSuiteName];
        CHECK([TestPreferences synchronize], "isolated preferences domain is removed from persistent storage");
        method_setImplementation(standard, original);
        printf("JDX configuration: %lu native Foundation checks passed.\n", (unsigned long)Checks);
        return 0;
    }
}
