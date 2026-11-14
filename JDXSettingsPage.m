#import "JDXSettingsPage.h"

BOOL JDXIsJDSettingsPage(NSString *navigationTitle, NSString *controllerTitle, NSString *className)
{
    if (![className isKindOfClass:NSString.class] || !className.length ||
        [className rangeOfString:@"JDX" options:NSCaseInsensitiveSearch].location != NSNotFound)
        return NO;
    static NSSet<NSString *> *titles, *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = [NSSet setWithArray:@[@"设置", @"账户设置", @"账号设置", @"Settings", @"Account Settings"]];
        // Only conservative known-style names, never broad "Settings" substring matching.
        classes = [NSSet setWithArray:@[@"JDSettingViewController", @"JDSettingsViewController",
            @"JDSettingMainViewController", @"JDSettingHomeViewController",
            @"MyJdSettingViewController", @"MyJDSettingViewController",
            @"JDMySettingViewController", @"JDMySettingsViewController"]];
    });
    return ([navigationTitle isKindOfClass:NSString.class] && [titles containsObject:navigationTitle]) ||
           ([controllerTitle isKindOfClass:NSString.class] && [titles containsObject:controllerTitle]) ||
           [classes containsObject:className];
}
