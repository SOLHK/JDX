#import <Foundation/Foundation.h>
#ifndef JDX_SETTINGS_PAGE_H
#define JDX_SETTINGS_PAGE_H
// Only exact, fixed page titles/classes are matched. Callers must never log the
// strings they inspect. A visible navigation label can identify custom headers.
BOOL JDXIsJDSettingsTitle(NSString *title);
BOOL JDXIsJDSettingsPage(NSString *navigationTitle, NSString *controllerTitle, NSString *className);
BOOL JDXIsJDSettingsNavigationLabel(NSString *title, double centerX, double centerY,
                                   double windowWidth, double safeAreaTop);

// Bounded front-to-back traversal, shared by UIKit discovery and Foundation
// regression tests. Children arrive in back-to-front (UIView.subviews) order.
// Invisible nodes prune their entire subtree. Identity tracking breaks cycles.
// The visitor returns YES to stop. The result counts all inspected nodes.
NSUInteger JDXVisitVisibleTree(id root, NSUInteger nodeLimit, NSUInteger depthLimit,
    NSArray *(^children)(id node), BOOL (^visible)(id node),
    BOOL (^visitor)(id node, NSUInteger depth));
#endif
