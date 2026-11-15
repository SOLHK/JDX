#import "JDXSettingsPage.h"
#include <math.h>

BOOL JDXIsJDSettingsTitle(NSString *title)
{
    if (![title isKindOfClass:NSString.class]) return NO;
    static NSSet<NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = [NSSet setWithArray:@[@"设置", @"账户设置", @"账号设置", @"Settings", @"Account Settings"]];
    });
    return [titles containsObject:title];
}

BOOL JDXIsJDSettingsPage(NSString *navigationTitle, NSString *controllerTitle, NSString *className)
{
    if (![className isKindOfClass:NSString.class] || !className.length ||
        [className rangeOfString:@"JDX" options:NSCaseInsensitiveSearch].location != NSNotFound)
        return NO;
    static NSSet<NSString *> *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Only conservative known-style names, never broad "Settings" substring matching.
        classes = [NSSet setWithArray:@[@"JDSettingViewController", @"JDSettingsViewController",
            @"JDSettingMainViewController", @"JDSettingHomeViewController",
            @"MyJdSettingViewController", @"MyJDSettingViewController",
            @"JDMySettingViewController", @"JDMySettingsViewController"]];
    });
    return JDXIsJDSettingsTitle(navigationTitle) || JDXIsJDSettingsTitle(controllerTitle) ||
           [classes containsObject:className];
}

BOOL JDXIsJDSettingsNavigationLabel(NSString *title, double centerX, double centerY,
                                   double windowWidth, double safeAreaTop)
{
    // A settings row somewhere inside another page must not turn that page into
    // the settings screen. The custom header in JD 16.1.83 is centered here.
    return isfinite(centerX) && isfinite(centerY) && isfinite(windowWidth) &&
        isfinite(safeAreaTop) && windowWidth > 0 && safeAreaTop >= 0 &&
        centerX >= windowWidth * 0.28 && centerX <= windowWidth * 0.72 &&
        centerY >= safeAreaTop - 4 && centerY <= safeAreaTop + 72 &&
        JDXIsJDSettingsTitle(title);
}

NSUInteger JDXVisitVisibleTree(id root, NSUInteger nodeLimit, NSUInteger depthLimit,
    NSArray *(^children)(id node), BOOL (^visible)(id node),
    BOOL (^visitor)(id node, NSUInteger depth))
{
    if (!root || !nodeLimit || !children || !visible || !visitor) return 0;
    NSMutableArray<NSArray *> *pending = [NSMutableArray arrayWithObject:@[root, @0]];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    NSUInteger inspected = 0;
    while (pending.count && inspected < nodeLimit) {
        NSArray *entry = pending.lastObject;
        [pending removeLastObject];
        id node = entry[0];
        NSUInteger depth = [entry[1] unsignedIntegerValue];
        if ([seen containsObject:node]) continue;
        [seen addObject:node];
        inspected++;
        if (!visible(node)) continue;
        if (visitor(node, depth)) break;
        if (depth >= depthLimit) continue;
        NSArray *descendants = children(node);
        if (![descendants isKindOfClass:NSArray.class]) continue;
        NSUInteger toPush = MIN(descendants.count, nodeLimit - inspected);
        NSUInteger keepPending = nodeLimit - inspected - toPush;
        // Keep pending storage bounded too. Descend into the frontmost view
        // before spending the budget on its obscured, backmost siblings.
        if (pending.count > keepPending)
            [pending removeObjectsInRange:NSMakeRange(0, pending.count - keepPending)];
        NSUInteger start = descendants.count - toPush;
        for (NSUInteger index = start; index < descendants.count; ++index)
            [pending addObject:@[descendants[index], @(depth + 1)]];
    }
    return inspected;
}
