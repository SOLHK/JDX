#import "JDXDiagnostics.h"
#import <TargetConditionals.h>
#import <mach-o/dyld.h>
#include <limits.h>
#include <math.h>
#if defined(JDX_DIAGNOSTICS_TESTING)
#include <stdlib.h>
#endif

// This module observes only metadata supplied by JDX. It does not intercept
// networking, collect view text, install exception handlers, or upload data.
static const NSUInteger JDXDiagFileLimit = 256 * 1024;
static const NSUInteger JDXDiagMemoryLimit = 300;
static const NSUInteger JDXDiagPendingLimit = 256;
static const NSUInteger JDXDiagEnhancedLimit = 5000;
static const NSTimeInterval JDXDiagEnhancedDuration = 10 * 60;
static NSLock *JDXDiagLock;
static dispatch_queue_t JDXDiagIO;
static NSMutableArray<NSDictionary *> *JDXDiagEvents;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *JDXDiagRules;
static NSMutableDictionary<NSString *, NSNumber *> *JDXDiagSamples;
static NSMutableDictionary<NSString *, NSDictionary *> *JDXDiagHooks;
static NSDictionary *JDXDiagEnvironment;
static NSString *JDXDiagSession;
static NSString *JDXDiagPage;
static BOOL JDXDiagEnhanced;
static NSUInteger JDXDiagEnhancedCount;
static NSUInteger JDXDiagRateCount;
static NSUInteger JDXDiagRateDropped;
static NSUInteger JDXDiagPending;
static NSUInteger JDXDiagDiskDropped;
static NSUInteger JDXDiagDiskErrors;
static NSUInteger JDXDiagEventCount;
static NSUInteger JDXDiagPageCount;
static NSUInteger JDXDiagGeneration;
static NSTimeInterval JDXDiagRateSecond;
static NSTimeInterval JDXDiagEnhancedSince;
static void *JDXDiagQueueKey = &JDXDiagQueueKey;

static void JDXDiagInitialize(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JDXDiagLock = [[NSLock alloc] init];
        JDXDiagLock.name = @"JDX diagnostics memory";
        JDXDiagIO = dispatch_queue_create("com.solhk.jdx.diagnostics", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(JDXDiagIO, JDXDiagQueueKey, JDXDiagQueueKey, NULL);
        JDXDiagEvents = [NSMutableArray array];
        JDXDiagRules = [NSMutableDictionary dictionary];
        JDXDiagSamples = [NSMutableDictionary dictionary];
        JDXDiagHooks = [NSMutableDictionary dictionary];
        JDXDiagEnvironment = @{};
        JDXDiagSession = NSUUID.UUID.UUIDString;
    });
}

static BOOL JDXDiagSafeKey(NSString *key)
{
    if (![key isKindOfClass:NSString.class] || !key.length || key.length > 120) return NO;
    NSString *lower = key.lowercaseString;
    static NSArray *forbidden;
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        forbidden = @[@"cookie", @"authorization", @"password", @"token", @"secret",
                      @"account", @"email", @"phone", @"address", @"request", @"response",
                      @"payload", @"url", @"query", @"body", @"stack", @"view_text",
                      @"exception_reason", @"user_info", @"userinfo", @"idfa", @"idfv"];
        allowed = [NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-"].invertedSet;
    });
    for (NSString *part in forbidden) if ([lower containsString:part]) return NO;
    return [key rangeOfCharacterFromSet:allowed].location == NSNotFound;
}

static NSString *JDXDiagMetadataString(NSString *value)
{
    if (value.length > 240) return @"[omitted:long_string]";
    if ([value containsString:@"://"] || [value containsString:@"/"] ||
        [value containsString:@"\\"] || [value containsString:@"\n"] ||
        [value containsString:@"\r"]) return @"[omitted:non_metadata]";
    // Metadata is restricted to ASCII class names, selectors, ABI encodings,
    // version numbers, statuses and fixed diagnostic reason codes.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:+- @(),[]{}#=<>?*!&^\""];
    if ([value rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound)
        return @"[omitted:non_metadata]";
    // Objective-C ABI encodings contain @, so reject address-shaped text without
    // rejecting that character in valid type metadata.
    NSRange at = [value rangeOfString:@"@"];
    if (at.location != NSNotFound && at.location > 0 &&
        [value rangeOfString:@"." options:0 range:NSMakeRange(at.location, value.length - at.location)].location != NSNotFound)
        return @"[omitted:non_metadata]";
    return value;
}

static id JDXDiagSanitize(id value, NSUInteger depth)
{
    if (depth > 6) return @"[omitted:depth]";
    if ([value isKindOfClass:NSString.class]) return JDXDiagMetadataString(value);
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        return isfinite(number) ? value : @0;
    }
    if (value == NSNull.null) return value;
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        NSUInteger count = 0;
        for (id child in value) {
            if (count++ >= 128) break;
            [result addObject:JDXDiagSanitize(child, depth + 1) ?: NSNull.null];
        }
        return result.copy;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        NSUInteger count = 0;
        for (id key in value) {
            if (count++ >= 128) break;
            if (JDXDiagSafeKey(key)) result[key] = JDXDiagSanitize(value[key], depth + 1) ?: NSNull.null;
        }
        return result.copy;
    }
    return @"[omitted:unsupported_type]";
}

static NSURL *JDXDiagDirectory(void)
{
#if defined(JDX_DIAGNOSTICS_TESTING)
    // Native Foundation tests must never fall back to the host user's cache.
    const char *root = getenv("JDX_DIAGNOSTICS_TEST_ROOT");
    return root && root[0] ? [NSURL fileURLWithPath:[NSString stringWithUTF8String:root] isDirectory:YES] : nil;
#else
    NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory
                                                      inDomains:NSUserDomainMask].firstObject;
    return [cache URLByAppendingPathComponent:@"JDX" isDirectory:YES];
#endif
}

static NSDataWritingOptions JDXDiagWritingOptions(void)
{
    NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IOS
    options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    return options;
}

static NSURL *JDXDiagLogURL(NSUInteger index)
{
    NSString *name = index ? [NSString stringWithFormat:@"events.%lu.jsonl", (unsigned long)index] : @"events.jsonl";
    return [JDXDiagDirectory() URLByAppendingPathComponent:name];
}

static void JDXDiagDiskFailure(void)
{
    [JDXDiagLock lock];
    JDXDiagDiskErrors++;
    [JDXDiagLock unlock];
}

// Always runs on JDXDiagIO. Each file is bounded; two old generations are kept.
static void JDXDiagAppendToDisk(NSData *data)
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *directory = JDXDiagDirectory();
    if (!directory || ![manager createDirectoryAtURL:directory withIntermediateDirectories:YES
                                          attributes:nil error:NULL]) {
        JDXDiagDiskFailure();
        return;
    }
    NSURL *current = JDXDiagLogURL(0);
    NSNumber *size = nil;
    [current getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    if (size.unsignedLongLongValue + data.length > JDXDiagFileLimit) {
        [manager removeItemAtURL:JDXDiagLogURL(2) error:NULL];
        if ([manager fileExistsAtPath:JDXDiagLogURL(1).path])
            [manager moveItemAtURL:JDXDiagLogURL(1) toURL:JDXDiagLogURL(2) error:NULL];
        if (![manager moveItemAtURL:current toURL:JDXDiagLogURL(1) error:NULL]) {
            // If rotation fails, never append beyond the cap.
            JDXDiagDiskFailure();
            return;
        }
    }
    if (![manager fileExistsAtPath:current.path]) {
        if (![data writeToURL:current options:JDXDiagWritingOptions()
                       error:NULL]) JDXDiagDiskFailure();
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:current error:NULL];
    if (!handle) { JDXDiagDiskFailure(); return; }
    unsigned long long offset = 0;
    if (![handle seekToEndReturningOffset:&offset error:NULL] ||
        offset + data.length > JDXDiagFileLimit || ![handle writeData:data error:NULL])
        JDXDiagDiskFailure();
    [handle closeAndReturnError:NULL];
}

static void JDXDiagQueueEvent(NSDictionary *record, NSUInteger generation)
{
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:NULL];
    if (!json || json.length + 1 > JDXDiagFileLimit) return;
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];
    [JDXDiagLock lock];
    if (generation != JDXDiagGeneration || JDXDiagPending >= JDXDiagPendingLimit) {
        JDXDiagDiskDropped++;
        [JDXDiagLock unlock];
        return;
    }
    JDXDiagPending++;
    [JDXDiagLock unlock];
    dispatch_async(JDXDiagIO, ^{
        @autoreleasepool {
            [JDXDiagLock lock];
            BOOL current = generation == JDXDiagGeneration;
            [JDXDiagLock unlock];
            if (current) JDXDiagAppendToDisk(line);
            [JDXDiagLock lock];
            JDXDiagPending--;
            [JDXDiagLock unlock];
        }
    });
}

static void JDXDiagEmit(NSString *event, NSDictionary *fields, BOOL enhancedOnly)
{
    JDXDiagInitialize();
    if (!JDXDiagSafeKey(event)) return;
    NSDictionary *safe = JDXDiagSanitize(fields ?: @{}, 0);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    [JDXDiagLock lock];
    if (enhancedOnly) {
        if (!JDXDiagEnhanced) { [JDXDiagLock unlock]; return; }
        if (JDXDiagEnhancedCount >= JDXDiagEnhancedLimit || now - JDXDiagEnhancedSince >= JDXDiagEnhancedDuration) {
            JDXDiagEnhanced = NO;
            event = @"enhanced_auto_stopped";
            safe = @{@"reason_code": @"capture_budget_exhausted"};
        } else {
            NSTimeInterval second = floor(now);
            if (JDXDiagRateSecond != second) { JDXDiagRateSecond = second; JDXDiagRateCount = 0; }
            if (JDXDiagRateCount >= 20) {
                JDXDiagRateDropped++;
                [JDXDiagLock unlock];
                return;
            }
            JDXDiagRateCount++;
            JDXDiagEnhancedCount++;
        }
    }
    JDXDiagEventCount++;
    NSDictionary *record = @{@"time_unix": @(now), @"session_id": JDXDiagSession,
                             @"sequence": @(JDXDiagEventCount), @"event": event,
                             @"main_thread": @(NSThread.isMainThread), @"fields": safe};
    [JDXDiagEvents addObject:record];
    if (JDXDiagEvents.count > JDXDiagMemoryLimit) [JDXDiagEvents removeObjectAtIndex:0];
    NSUInteger generation = JDXDiagGeneration;
    [JDXDiagLock unlock];
    JDXDiagQueueEvent(record, generation);
}

void JDXDiagnosticsStart(NSDictionary *environment)
{
    JDXDiagInitialize();
    NSDictionary *safe = JDXDiagSanitize(environment ?: @{}, 0);
    [JDXDiagLock lock];
    JDXDiagEnvironment = safe;
    [JDXDiagLock unlock];
    JDXDiagEmit(@"session_start", safe, NO);
}

void JDXLog(NSString *event, NSDictionary *fields)
{
    JDXDiagEmit(event, fields, NO);
}

void JDXDiagnosticsSetEnhanced(BOOL enabled)
{
    JDXDiagInitialize();
    [JDXDiagLock lock];
    JDXDiagEnhanced = enabled;
    if (enabled) {
        JDXDiagEnhancedSince = NSDate.date.timeIntervalSince1970;
        JDXDiagEnhancedCount = 0;
        JDXDiagRateCount = 0;
        JDXDiagRateDropped = 0;
        [JDXDiagSamples removeAllObjects];
    }
    [JDXDiagLock unlock];
    JDXDiagEmit(@"enhanced_changed", @{@"enabled": @(enabled), @"record_limit": @(JDXDiagEnhancedLimit),
                                       @"duration_seconds": @(JDXDiagEnhancedDuration)}, NO);
}

BOOL JDXDiagnosticsEnhanced(void)
{
    JDXDiagInitialize();
    [JDXDiagLock lock];
    BOOL expired = JDXDiagEnhanced &&
        NSDate.date.timeIntervalSince1970 - JDXDiagEnhancedSince >= JDXDiagEnhancedDuration;
    if (expired) JDXDiagEnhanced = NO;
    BOOL enabled = JDXDiagEnhanced;
    [JDXDiagLock unlock];
    if (expired) JDXDiagEmit(@"enhanced_auto_stopped", @{@"reason_code": @"time_budget_exhausted"}, NO);
    return enabled;
}

void JDXRecordRule(NSString *ruleID, NSString *outcome, NSUInteger amount)
{
    JDXDiagInitialize();
    if (!JDXDiagSafeKey(ruleID) || !JDXDiagSafeKey(outcome) || !amount) return;
    [JDXDiagLock lock];
    NSMutableDictionary *rule = JDXDiagRules[ruleID];
    if (!rule && JDXDiagRules.count < 64) {
        rule = [NSMutableDictionary dictionary];
        JDXDiagRules[ruleID] = rule;
    }
    if (!rule || (!rule[outcome] && rule.count >= 16)) { [JDXDiagLock unlock]; return; }
    unsigned long long old = [rule[outcome] unsignedLongLongValue];
    rule[outcome] = @(old > ULLONG_MAX - amount ? ULLONG_MAX : old + amount);
    NSString *sampleKey = [NSString stringWithFormat:@"%@:%@", ruleID, outcome];
    NSUInteger samples = [JDXDiagSamples[sampleKey] unsignedIntegerValue];
    BOOL sample = JDXDiagEnhanced && samples < 5;
    if (sample) JDXDiagSamples[sampleKey] = @(samples + 1);
    [JDXDiagLock unlock];
    if (sample) JDXDiagEmit(@"rule_activity", @{@"rule_id": ruleID, @"outcome": outcome, @"amount": @(amount)}, YES);
}

void JDXRecordHook(NSDictionary *record)
{
    JDXDiagInitialize();
    NSDictionary *safe = JDXDiagSanitize(record ?: @{}, 0);
    NSString *className = safe[@"class"] ?: safe[@"class_name"] ?: @"unknown";
    NSString *selector = safe[@"selector"] ?: safe[@"selector_name"] ?: @"unknown";
    if (![className isKindOfClass:NSString.class] || ![selector isKindOfClass:NSString.class]) return;
    NSString *key = [NSString stringWithFormat:@"%@:%@", className, selector];
    [JDXDiagLock lock];
    if (JDXDiagHooks[key] || JDXDiagHooks.count < 128) JDXDiagHooks[key] = safe;
    [JDXDiagLock unlock];
    JDXDiagEmit(@"hook_status", safe, NO);
}

void JDXRecordPage(NSString *className)
{
    JDXDiagInitialize();
    if (!JDXDiagSafeKey(className)) return;
    [JDXDiagLock lock];
    BOOL changed = ![JDXDiagPage isEqualToString:className];
    JDXDiagPage = className.copy;
    if (changed) JDXDiagPageCount++;
    BOOL record = changed && JDXDiagEnhanced;
    [JDXDiagLock unlock];
    if (record) JDXDiagEmit(@"page_observed", @{@"class": className}, YES);
}

static NSDictionary *JDXDiagLoadedImages(void)
{
    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *hints = [NSMutableArray array];
    NSUInteger jdxCount = 0;
    BOOL oldPlugin = NO;
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count && names.count < 64; index++) {
        const char *path = _dyld_get_image_name(index);
        if (!path) continue;
        NSString *name = [NSString stringWithUTF8String:path].lastPathComponent;
        NSString *lower = name.lowercaseString;
        BOOL jdx = [lower containsString:@"jdx"];
        BOOL old = [lower containsString:@"jdadblock"];
        BOOL loader = [lower containsString:@"ellekit"] || [lower containsString:@"substrate"] ||
                      [lower containsString:@"substitute"] || [lower containsString:@"libhooker"];
        if (jdx || old || loader) [names addObject:JDXDiagMetadataString(name)];
        if (jdx) jdxCount++;
        if (old) oldPlugin = YES;
    }
    if (jdxCount > 1) [hints addObject:@"multiple_jdx_images_observed"];
    if (oldPlugin) [hints addObject:@"legacy_jdadblock_image_observed"];
    return @{@"related_image_names": names, @"conflict_hints": hints,
             @"hints_are_proof_of_conflict": @NO};
}

NSDictionary *JDXDiagnosticsSnapshot(void)
{
    JDXDiagInitialize();
    BOOL enabled = JDXDiagnosticsEnhanced();
    [JDXDiagLock lock];
    NSMutableDictionary *rules = [NSMutableDictionary dictionary];
    for (NSString *key in JDXDiagRules) rules[key] = JDXDiagRules[key].copy;
    NSArray *hookKeys = [JDXDiagHooks.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *hooks = [NSMutableArray array];
    for (NSString *key in hookKeys) [hooks addObject:JDXDiagHooks[key]];
    NSDictionary *snapshot = @{
        @"schema_version": @1, @"session_id": JDXDiagSession, @"environment": JDXDiagEnvironment,
        @"enhanced": @{@"enabled": @(enabled), @"records": @(JDXDiagEnhancedCount),
                        @"record_limit": @(JDXDiagEnhancedLimit), @"duration_seconds": @(JDXDiagEnhancedDuration),
                        @"rate_dropped": @(JDXDiagRateDropped)},
        @"storage": @{@"max_file_bytes": @(JDXDiagFileLimit), @"max_files": @3,
                       @"max_memory_events": @(JDXDiagMemoryLimit), @"pending_writes": @(JDXDiagPending),
                       @"dropped_disk_events": @(JDXDiagDiskDropped), @"disk_errors": @(JDXDiagDiskErrors)},
        @"rule_counters": rules.copy, @"hooks": hooks.copy, @"recent_events": JDXDiagEvents.copy,
        @"total_events": @(JDXDiagEventCount), @"page_transitions": @(JDXDiagPageCount),
        @"last_observed_page_class": JDXDiagPage ?: @"none"
    };
    [JDXDiagLock unlock];
    NSMutableDictionary *result = snapshot.mutableCopy;
    result[@"loaded_images"] = JDXDiagLoadedImages();
    return result.copy;
}

NSString *JDXDiagnosticsSummary(void)
{
    NSDictionary *snapshot = JDXDiagnosticsSnapshot();
    NSDictionary *enhanced = snapshot[@"enhanced"];
    return [NSString stringWithFormat:@"本次记录 %lu 条，%lu 个 Hook；增强诊断%@（%lu/%lu）。",
            (unsigned long)[snapshot[@"total_events"] unsignedIntegerValue],
            (unsigned long)[snapshot[@"hooks"] count], [enhanced[@"enabled"] boolValue] ? @"开启" : @"关闭",
            (unsigned long)[enhanced[@"records"] unsignedIntegerValue], (unsigned long)JDXDiagEnhancedLimit];
}

// Reads only our three capped JSONL files, oldest first, after queued writes.
static NSArray *JDXDiagReadPersistedEvents(void)
{
    NSMutableArray *events = [NSMutableArray array];
    for (NSInteger index = 2; index >= 0; index--) {
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:JDXDiagLogURL((NSUInteger)index) error:NULL];
        if (!handle) continue;
        NSData *data = [handle readDataUpToLength:JDXDiagFileLimit + 1 error:NULL];
        [handle closeAndReturnError:NULL];
        if (data.length > JDXDiagFileLimit) continue;
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (!line.length) continue;
            id record = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            if ([record isKindOfClass:NSDictionary.class]) [events addObject:JDXDiagSanitize(record, 0)];
            if (events.count > 2000) [events removeObjectAtIndex:0];
        }
    }
    return events.copy;
}

NSURL *JDXExportDiagnostics(NSDictionary *state, NSError **error)
{
    JDXDiagInitialize();
    JDXDiagEmit(@"export_started", @{}, NO);
    NSDictionary *snapshot = JDXDiagnosticsSnapshot();
    NSDictionary *safeState = JDXDiagSanitize(state ?: @{}, 0);
    __block NSURL *result = nil;
    __block NSError *failure = nil;
    void (^write)(void) = ^{
        @autoreleasepool {
            NSMutableDictionary *report = snapshot.mutableCopy;
            report[@"format"] = @"JDX diagnostic report";
            report[@"generated_time_unix"] = @(NSDate.date.timeIntervalSince1970);
            report[@"configuration"] = safeState;
            report[@"persisted_events"] = JDXDiagReadPersistedEvents();
            report[@"privacy"] = @{
                @"network_content_collected": @NO, @"view_text_collected": @NO,
                @"account_data_collected": @NO, @"uploaded_automatically": @NO,
                @"contains_fixed_metadata_and_local_counters": @YES
            };
            NSURL *directory = JDXDiagDirectory();
            if (!directory || ![NSFileManager.defaultManager createDirectoryAtURL:directory
                      withIntermediateDirectories:YES attributes:nil error:&failure]) return;
            NSData *data = [NSJSONSerialization dataWithJSONObject:report
                options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&failure];
            if (!data) return;
            NSString *name = [NSString stringWithFormat:@"JDX-diagnostics-%@.json", NSUUID.UUID.UUIDString];
            NSURL *file = [directory URLByAppendingPathComponent:name];
            if (![data writeToURL:file options:JDXDiagWritingOptions()
                            error:&failure]) return;
            result = file;
            // Keep at most three exports in the app cache. Shared copies belong
            // to the user's chosen destination and are never touched here.
            NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
                includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:NULL];
            NSMutableArray *exports = [NSMutableArray array];
            for (NSURL *candidate in files)
                if ([candidate.lastPathComponent hasPrefix:@"JDX-diagnostics-"] &&
                    [candidate.pathExtension isEqualToString:@"json"])
                    [exports addObject:candidate];
            [exports sortUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
                // Keep the export being handed to the share sheet first even
                // when timestamps tie or the device clock moved backwards.
                if ([left isEqual:right]) return NSOrderedSame;
                if ([left isEqual:result]) return NSOrderedAscending;
                if ([right isEqual:result]) return NSOrderedDescending;
                NSDate *a = nil, *b = nil;
                [left getResourceValue:&a forKey:NSURLContentModificationDateKey error:NULL];
                [right getResourceValue:&b forKey:NSURLContentModificationDateKey error:NULL];
                NSComparisonResult order = [(b ?: NSDate.distantPast) compare:(a ?: NSDate.distantPast)];
                return order == NSOrderedSame ? [left.lastPathComponent compare:right.lastPathComponent] : order;
            }];
            for (NSUInteger index = 3; index < exports.count; index++)
                if (![exports[index] isEqual:result]) [NSFileManager.defaultManager removeItemAtURL:exports[index] error:NULL];
        }
    };
    if (dispatch_get_specific(JDXDiagQueueKey)) write(); else dispatch_sync(JDXDiagIO, write);
    if (!result && !failure) failure = [NSError errorWithDomain:@"com.solhk.jdx.diagnostics" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"诊断文件生成失败，请稍后重试。"}];
    if (error) *error = failure;
    JDXDiagEmit(result ? @"export_finished" : @"export_failed", @{}, NO);
    return result;
}

void JDXClearDiagnostics(void)
{
    JDXDiagInitialize();
    [JDXDiagLock lock];
    JDXDiagGeneration++;
    [JDXDiagEvents removeAllObjects];
    [JDXDiagRules removeAllObjects];
    [JDXDiagSamples removeAllObjects];
    JDXDiagPage = nil;
    JDXDiagEventCount = 0;
    JDXDiagPageCount = 0;
    JDXDiagRateDropped = 0;
    JDXDiagDiskDropped = 0;
    JDXDiagDiskErrors = 0;
    JDXDiagSession = NSUUID.UUID.UUIDString;
    // Put the deletion in queue order before another producer can observe the
    // new generation. Old pending records skip themselves; new records follow
    // this deletion and therefore survive the clear operation.
    dispatch_async(JDXDiagIO, ^{
        NSFileManager *manager = NSFileManager.defaultManager;
        for (NSUInteger index = 0; index < 3; index++) [manager removeItemAtURL:JDXDiagLogURL(index) error:NULL];
        NSArray *files = [manager contentsOfDirectoryAtURL:JDXDiagDirectory() includingPropertiesForKeys:nil options:0 error:NULL];
        for (NSURL *file in files) if ([file.lastPathComponent hasPrefix:@"JDX-diagnostics-"] &&
                                    [file.pathExtension isEqualToString:@"json"])
            [manager removeItemAtURL:file error:NULL];
    });
    [JDXDiagLock unlock];
    // Hook installation and environment are live state, not historical logs.
    // Keep them so the next diagnostic report is still useful after clearing.
    JDXDiagEmit(@"logs_cleared", @{}, NO);
}
