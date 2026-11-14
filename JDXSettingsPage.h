#import <Foundation/Foundation.h>
#ifndef JDX_SETTINGS_PAGE_H
#define JDX_SETTINGS_PAGE_H
// Only page titles/classes are inspected; no JD user data or table cell text.
BOOL JDXIsJDSettingsPage(NSString *navigationTitle, NSString *controllerTitle, NSString *className);
#endif
