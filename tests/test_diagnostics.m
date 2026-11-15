// Run on macOS against Apple's real Foundation runtime:
// xcrun clang -fobjc-arc -fblocks -fobjc-exceptions -Wall -Wextra -Werror
// (continued) -framework Foundation tests/test_diagnostics.m -o build/test_diagnostics
// build/test_diagnostics
#define JDX_DIAGNOSTICS_TESTING 1
#import "../JDXDiagnostics.m"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSUInteger Checks;
#define CHECK(condition, explanation) do { \
    Checks++; \
    if (!(condition)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, explanation); \
        exit(1); \
    } \
} while (0)

// The test and implementation deliberately share one translation unit. This
// barrier drains asynchronous IO without timing guesses or sleep-based tests.
static void FlushIO(void)
{
    dispatch_sync(JDXDiagIO, ^{});
}

static NSDictionary *ReadReport(NSURL *file)
{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:file options:0 error:&error];
    CHECK(data != nil && error == nil, "export file is readable");
    id report = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    CHECK([report isKindOfClass:NSDictionary.class] && error == nil, "export is valid JSON object");
    return report;
}

static NSDictionary *LastEventNamed(NSString *name)
{
    NSArray *events = JDXDiagnosticsSnapshot()[@"recent_events"];
    for (NSDictionary *event in events.reverseObjectEnumerator)
        if ([event[@"event"] isEqual:name]) return event;
    return nil;
}

static void TestPrivacyAndMetadata(void)
{
    JDXDiagnosticsStart(@{
        @"plugin_version": @"0.2.0", @"bundle_id": @"com.360buy.jdmobile",
        @"app_version": @"171204", @"app_build": @"16.1.83",
        @"cookie": @"COOKIE_CANARY", @"account_id": @"ACCOUNT_CANARY",
        @"unsafe_string": @"https://example.invalid/ENV_CANARY"
    });
    NSDictionary *environment = JDXDiagnosticsSnapshot()[@"environment"];
    CHECK([environment[@"bundle_id"] isEqual:@"com.360buy.jdmobile"], "bundle metadata retained");
    CHECK([environment[@"app_version"] isEqual:@"171204"], "version metadata retained");
    CHECK(environment[@"cookie"] == nil && environment[@"account_id"] == nil, "sensitive environment keys omitted");
    CHECK([environment[@"unsafe_string"] isEqual:@"[omitted:non_metadata]"], "URL value omitted");

    JDXLog(@"metadata_test", @{
        @"rule_id": @"search.sponsoredProducts", @"selector": @"p_createVMWithProductModelArray:",
        @"actual_encoding": @"@24@0:8@16", @"status": @"safe_passthrough", @"amount": @3,
        @"requested_active": @NO, @"requested_active_token": @"PREFIX_CANARY",
        @"token": @"TOKEN_CANARY", @"request": @"REQUEST_CANARY", @"response": @"RESPONSE_CANARY",
        @"view_text": @"VIEW_TEXT_CANARY", @"exception_reason": @"EXCEPTION_CANARY",
        @"nested": @{@"password": @"PASSWORD_CANARY", @"status": @"ok"},
        @"path": @"/private/var/mobile/PATH_CANARY", @"mail_text": @"EMAIL_CANARY@example.invalid",
        @"body": @"BODY_CANARY", @"non_metadata": @"用户输入内容"
    });
    NSDictionary *fields = LastEventNamed(@"metadata_test")[@"fields"];
    CHECK([fields[@"rule_id"] isEqual:@"search.sponsoredProducts"], "rule metadata retained");
    CHECK([fields[@"selector"] isEqual:@"p_createVMWithProductModelArray:"], "selector metadata retained");
    CHECK([fields[@"actual_encoding"] isEqual:@"@24@0:8@16"], "ABI encoding retained");
    CHECK([fields[@"amount"] unsignedIntegerValue] == 3, "numeric metadata retained");
    CHECK([fields[@"requested_active"] isEqual:@NO], "exact rule activity boolean is retained");
    CHECK(fields[@"requested_active_token"] == nil, "exact metadata exception never permits sensitive suffixes");
    for (NSString *key in @[@"token", @"request", @"response", @"view_text", @"exception_reason", @"body"])
        CHECK(fields[key] == nil, "sensitive event key omitted");
    CHECK([fields[@"nested"][@"status"] isEqual:@"ok"] && fields[@"nested"][@"password"] == nil,
          "nested metadata is sanitized recursively");
    CHECK([fields[@"path"] isEqual:@"[omitted:non_metadata]"], "file path omitted");
    CHECK([fields[@"mail_text"] isEqual:@"[omitted:non_metadata]"], "email-like value omitted");
    CHECK([fields[@"non_metadata"] isEqual:@"[omitted:non_metadata]"], "free-form UI text omitted");

    NSError *error = nil;
    NSURL *file = JDXExportDiagnostics(@{
        @"preferences": @{@"com.solhk.jd-adblock.enabled": @YES},
        @"safe_mode": @YES, @"session_safe_mode": @YES, @"restart_required": @NO,
        @"business_hooks_installed": @0,
        @"configuration": @{@"rules": @[@{@"rule_id": @"splash", @"requested_active": @NO}]},
        @"settings_entry": @{@"backup_visible": @YES, @"class": @"JDTabBarController"},
        @"network_path": @{@"status": @"satisfied", @"service_connectivity": @"not_tested"},
        @"token": @"CONFIG_TOKEN_CANARY"
    }, &error);
    CHECK(file != nil && error == nil, "diagnostic export succeeds");
    NSDictionary *report = ReadReport(file);
    CHECK([report[@"configuration"][@"preferences"][@"com.solhk.jd-adblock.enabled"] boolValue],
          "preference snapshot retained");
    CHECK(report[@"configuration"][@"token"] == nil, "export configuration sanitized");
    NSDictionary *state = report[@"configuration"];
    CHECK([state[@"safe_mode"] boolValue] && [state[@"session_safe_mode"] boolValue] &&
          [state[@"restart_required"] isEqual:@NO] && [state[@"business_hooks_installed"] isEqual:@0],
          "pure startup evidence survives real JSON export");
    CHECK([state[@"configuration"][@"rules"][0][@"requested_active"] isEqual:@NO],
          "nested effective rule state survives real JSON export");
    CHECK([state[@"settings_entry"][@"backup_visible"] boolValue], "entry metadata survives real JSON export");
    CHECK([state[@"network_path"][@"service_connectivity"] isEqual:@"not_tested"],
          "system path never claims that the service was tested");
    NSString *text = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL];
    CHECK(![text containsString:@"CANARY"], "sensitive canaries never reach exported JSON or persisted logs");
    CHECK([report[@"persisted_events"] count] > 0, "export includes asynchronous persistent events");
    CHECK(![report[@"privacy"][@"uploaded_automatically"] boolValue], "report does not claim automatic upload");
}

static void TestCountersHooksAndEnhancedSamples(void)
{
    JDXRecordRule(@"search_ads", @"blocked", 2);
    JDXRecordRule(@"search_ads", @"blocked", 3);
    JDXRecordRule(@"search_ads", @"passthrough", 1);
    NSDictionary *counters = JDXDiagnosticsSnapshot()[@"rule_counters"];
    CHECK([counters[@"search_ads"][@"blocked"] unsignedIntegerValue] == 5, "amounts accumulate");
    CHECK([counters[@"search_ads"][@"passthrough"] unsignedIntegerValue] == 1, "outcomes remain separate");

    JDXRecordHook(@{@"class": @"Child", @"selector": @"render", @"status": @"pending"});
    JDXRecordHook(@{@"class": @"Child", @"selector": @"render", @"status": @"installed_override", @"owner": @"Parent"});
    JDXRecordHook(@{@"class": @"Sibling", @"selector": @"render", @"status": @"skipped"});
    NSArray *hooks = JDXDiagnosticsSnapshot()[@"hooks"];
    CHECK(hooks.count == 2, "hook state updates use class and selector identity");
    NSDictionary *child = nil;
    for (NSDictionary *hook in hooks) if ([hook[@"class"] isEqual:@"Child"]) child = hook;
    CHECK([child[@"status"] isEqual:@"installed_override"] && [child[@"owner"] isEqual:@"Parent"],
          "latest hook state and inherited owner retained");

    JDXDiagnosticsSetEnhanced(YES);
    CHECK(JDXDiagnosticsEnhanced(), "enhanced switch turns on");
    for (NSUInteger index = 0; index < 1000; index++) JDXRecordRule(@"sample_rule", @"blocked", 1);
    NSDictionary *snapshot = JDXDiagnosticsSnapshot();
    CHECK([snapshot[@"rule_counters"][@"sample_rule"][@"blocked"] unsignedIntegerValue] == 1000,
          "sampling never loses rule counts");
    NSUInteger samples = 0;
    for (NSDictionary *event in snapshot[@"recent_events"])
        if ([event[@"event"] isEqual:@"rule_activity"] && [event[@"fields"][@"rule_id"] isEqual:@"sample_rule"]) samples++;
    CHECK(samples > 0 && samples <= 5, "per-rule enhanced event sampling is bounded");
    JDXDiagnosticsSetEnhanced(NO);
    CHECK(!JDXDiagnosticsEnhanced(), "enhanced switch turns off");
    NSUInteger previous = [JDXDiagnosticsSnapshot()[@"total_events"] unsignedIntegerValue];
    JDXRecordRule(@"sample_rule", @"blocked", 1);
    JDXRecordPage(@"SafeViewController");
    CHECK([JDXDiagnosticsSnapshot()[@"total_events"] unsignedIntegerValue] == previous,
          "disabled enhancement does not emit page or rule samples");
}

static void TestConcurrentCounters(void)
{
    dispatch_apply(8, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t worker) {
        (void)worker;
        @autoreleasepool {
            for (NSUInteger index = 0; index < 1000; index++) JDXRecordRule(@"concurrent", @"passed", 1);
        }
    });
    CHECK([JDXDiagnosticsSnapshot()[@"rule_counters"][@"concurrent"][@"passed"] unsignedIntegerValue] == 8000,
          "parallel rule increments are exact");
}

static void TestRotationAndBounds(NSURL *directory)
{
    NSString *padding = [@"X" stringByPaddingToLength:200 withString:@"X" startingAtIndex:0];
    for (NSUInteger batch = 0; batch < 100; batch++) {
        @autoreleasepool {
            for (NSUInteger index = 0; index < 32; index++)
                JDXLog(@"rotation_test", @{@"fixed_metadata": padding, @"batch": @(batch), @"index": @(index)});
            FlushIO();
        }
    }
    NSDictionary *snapshot = JDXDiagnosticsSnapshot();
    CHECK([snapshot[@"recent_events"] count] <= 300, "in-memory event window is bounded");
    CHECK([snapshot[@"storage"][@"pending_writes"] unsignedIntegerValue] == 0, "IO barrier drains queued writes");
    CHECK([snapshot[@"storage"][@"disk_errors"] unsignedIntegerValue] == 0, "all bounded file writes succeed");
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:@[NSURLFileSizeKey] options:0 error:NULL];
    NSUInteger logs = 0;
    for (NSURL *file in files) {
        if (![file.pathExtension isEqual:@"jsonl"]) continue;
        logs++;
        NSNumber *bytes = nil;
        [file getResourceValue:&bytes forKey:NSURLFileSizeKey error:NULL];
        CHECK(bytes.unsignedLongLongValue <= 256 * 1024, "each rotated file respects byte cap");
    }
    CHECK(logs == 3, "rotation retains exactly three log files after sustained logging");
    NSURL *latest = nil;
    for (NSUInteger index = 0; index < 5; index++) {
        // Simulate a backwards wall-clock adjustment: previous exports have
        // future timestamps, but retaining the current share item must not
        // allow the cache to exceed its three-file limit.
        NSArray *existing = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:nil options:0 error:NULL];
        for (NSURL *old in existing)
            if ([old.lastPathComponent hasPrefix:@"JDX-diagnostics-"])
                CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:3600]}
                            ofItemAtPath:old.path error:NULL], "test controls old export timestamps");
        NSError *error = nil;
        latest = JDXExportDiagnostics(@{@"export_number": @(index)}, &error);
        CHECK(latest != nil && error == nil, "repeated exports succeed");
        CHECK([NSFileManager.defaultManager fileExistsAtPath:latest.path], "each current export survives cleanup immediately");
        // Distinct URL representations refer to the same direct child. The
        // production cleanup must not depend on NSURL object equality when
        // Foundation enumerates a relative/base URL for an absolute URL.
        NSURL *relative = [NSURL URLWithString:[@"./" stringByAppendingString:latest.lastPathComponent]
                                  relativeToURL:directory];
        NSURL *absolute = [NSURL fileURLWithPath:latest.path];
        CHECK(relative.baseURL != nil && absolute.baseURL == nil, "regression exercises relative and absolute URL representations");
        CHECK([relative.lastPathComponent isEqual:absolute.lastPathComponent], "same-directory filename is stable across URL representations");
        NSData *relativeData = [NSData dataWithContentsOfURL:relative];
        NSData *absoluteData = [NSData dataWithContentsOfURL:absolute];
        CHECK(relativeData != nil && [relativeData isEqual:absoluteData], "relative and absolute URLs read the same retained export");
        NSArray *listed = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:nil options:0 error:NULL];
        NSURL *enumerated = nil;
        NSUInteger retained = 0;
        for (NSURL *candidate in listed) {
            if ([candidate.lastPathComponent hasPrefix:@"JDX-diagnostics-"]) retained++;
            if ([candidate.lastPathComponent isEqual:latest.lastPathComponent]) enumerated = candidate;
        }
        CHECK(retained <= 3, "cache cap holds after each export even when old timestamps are in the future");
        CHECK(enumerated != nil && [[NSData dataWithContentsOfURL:enumerated] isEqual:absoluteData],
              "directory-enumerated URL identifies the same current export");
    }
    files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:NULL];
    NSUInteger exports = 0;
    for (NSURL *file in files) if ([file.lastPathComponent hasPrefix:@"JDX-diagnostics-"]) exports++;
    CHECK(exports <= 3, "export cache contains at most three files");
    CHECK([NSFileManager.defaultManager fileExistsAtPath:latest.path], "current export is not removed during cache cleanup");
    NSDictionary *report = ReadReport(latest);
    CHECK([report[@"persisted_events"] count] <= 2000, "exported persisted event count is bounded");
    CHECK([report[@"recent_events"] count] <= 300, "exported memory event count is bounded");
}

static void TestClearBoundary(void)
{
    FlushIO();
    // Hold IO so pre-clear writes are certainly pending. Clear must discard
    // them, queue deletion, and preserve every subsequently submitted record.
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    dispatch_async(JDXDiagIO, ^{ dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); });
    for (NSUInteger index = 0; index < 32; index++) JDXLog(@"before_clear", @{@"index": @(index)});
    JDXClearDiagnostics();
    dispatch_apply(4, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t worker) {
        @autoreleasepool {
            for (NSUInteger index = 0; index < 8; index++)
                JDXLog(@"after_clear", @{@"worker": @(worker), @"index": @(index)});
        }
    });
    JDXRecordRule(@"after_clear_rule", @"passed", 7);
    dispatch_semaphore_signal(gate);
    FlushIO();
    NSDictionary *snapshot = JDXDiagnosticsSnapshot();
    CHECK([snapshot[@"rule_counters"] count] == 1, "clear removes old rule counters");
    CHECK([snapshot[@"rule_counters"][@"after_clear_rule"][@"passed"] unsignedIntegerValue] == 7,
          "clear preserves new rule counters");
    CHECK([snapshot[@"hooks"] count] == 2, "clear retains live hook installation state");
    CHECK([snapshot[@"environment"][@"bundle_id"] isEqual:@"com.360buy.jdmobile"], "clear retains live environment");
    CHECK([snapshot[@"recent_events"] count] == 33, "clear resets memory window and preserves new parallel events");
    CHECK([snapshot[@"total_events"] unsignedIntegerValue] == 33, "clear resets event sequence");
    NSURL *file = JDXExportDiagnostics(@{}, NULL);
    CHECK(file != nil, "export succeeds after clear");
    NSDictionary *report = ReadReport(file);
    NSUInteger after = 0;
    for (NSDictionary *event in report[@"persisted_events"]) {
        CHECK(![event[@"event"] isEqual:@"before_clear"], "old pending records cannot reappear after clear");
        CHECK(![event[@"event"] isEqual:@"rotation_test"], "clear removes previous rotated logs");
        if ([event[@"event"] isEqual:@"after_clear"]) after++;
    }
    CHECK(after == 32, "clear preserves all new records submitted in parallel");
}

int main(void)
{
    @autoreleasepool {
        NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@"jdx-diag-test-XXXXXX"];
        char *buffer = strdup(template.fileSystemRepresentation);
        CHECK(buffer != NULL, "temporary path allocation succeeds");
        char *created = mkdtemp(buffer);
        CHECK(created != NULL, "unique temporary directory is created");
        CHECK(setenv("JDX_DIAGNOSTICS_TEST_ROOT", created, 1) == 0, "test cache is isolated from user cache");
        NSURL *directory = [NSURL fileURLWithPath:[NSString stringWithUTF8String:created] isDirectory:YES];
        free(buffer);
        TestPrivacyAndMetadata();
        TestCountersHooksAndEnhancedSamples();
        TestConcurrentCounters();
        TestRotationAndBounds(directory);
        TestClearBoundary();
        FlushIO();
        CHECK([NSFileManager.defaultManager removeItemAtURL:directory error:NULL], "temporary test directory is removed");
        unsetenv("JDX_DIAGNOSTICS_TEST_ROOT");
        printf("JDX diagnostics: %lu native Foundation checks passed.\n", (unsigned long)Checks);
        return 0;
    }
}
