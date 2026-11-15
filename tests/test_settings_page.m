#import <Foundation/Foundation.h>
#import "../JDXSettingsPage.m"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\\n", __LINE__, #x); exit(1); } } while (0)

@interface JDXTestView : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSArray<JDXTestView *> *children;
@property(nonatomic) BOOL hidden;
@end
@implementation JDXTestView
@end

static JDXTestView *View(NSString *name, NSArray *children)
{
    JDXTestView *view = [JDXTestView new];
    view.name = name;
    view.children = children ?: @[];
    return view;
}

static NSUInteger Walk(JDXTestView *root, NSUInteger nodes, NSUInteger depth,
                      NSMutableArray *visited, NSString *stop)
{
    return JDXVisitVisibleTree(root, nodes, depth,
        ^NSArray *(id node) { return [(JDXTestView *)node children]; },
        ^BOOL(id node) { return ![(JDXTestView *)node hidden]; },
        ^BOOL(id node, __unused NSUInteger level) {
            NSString *name = [(JDXTestView *)node name];
            [visited addObject:name];
            return [name isEqual:stop];
        });
}

static void TestVisibleTree(void)
{
    JDXTestView *header = View(@"custom-navbar", @[View(@"settings-title", nil)]);
    JDXTestView *oldPage = View(@"offscreen-old-page", @[View(@"old-settings-title", nil)]);
    oldPage.hidden = YES;
    JDXTestView *root = View(@"window", @[oldPage, View(@"content", nil), header]);
    NSMutableArray *visited = [NSMutableArray array];
    CHECK(Walk(root, 192, 32, visited, @"settings-title") == 3);
    CHECK(([visited isEqualToArray:@[@"window", @"custom-navbar", @"settings-title"]]));
    [visited removeAllObjects];
    CHECK(Walk(root, 192, 32, visited, nil) == 5);
    CHECK(![visited containsObject:@"offscreen-old-page"]);
    CHECK(![visited containsObject:@"old-settings-title"]);

    // Depth and node limits apply to real traversal, including hidden views.
    [visited removeAllObjects];
    CHECK(Walk(root, 2, 32, visited, nil) == 2);
    CHECK(([visited isEqualToArray:@[@"window", @"custom-navbar"]]));
    [visited removeAllObjects];
    CHECK(Walk(root, 192, 0, visited, nil) == 1);
    CHECK(([visited isEqualToArray:@[@"window"]]));
    [visited removeAllObjects];
    CHECK(Walk(root, 192, 1, visited, nil) == 4);
    CHECK(![visited containsObject:@"settings-title"]);

    // A broad ancestor must not consume the entire budget with old siblings
    // before we inspect the frontmost custom navigation subtree.
    NSMutableArray *siblings = [NSMutableArray array];
    for (NSUInteger index = 0; index < 1000; ++index) [siblings addObject:View(@"old-sibling", nil)];
    [siblings addObject:header];
    JDXTestView *wide = View(@"wide-root", siblings);
    [visited removeAllObjects];
    CHECK(Walk(wide, 4, 32, visited, @"settings-title") == 3);
    CHECK([visited containsObject:@"settings-title"]);

    // Custom containers may expose a repeated reference or even a cycle.
    // Match by identity, never by a node's value equality.
    JDXTestView *first = View(@"same-name", nil), *second = View(@"same-name", nil);
    JDXTestView *cycle = View(@"cycle", @[first, second, first]);
    first.children = @[cycle];
    [visited removeAllObjects];
    CHECK(Walk(cycle, 192, 32, visited, nil) == 3);
    CHECK(visited.count == 3);
    first.children = @[];
    [visited removeAllObjects];
    CHECK(Walk(nil, 192, 32, visited, nil) == 0);
    CHECK(Walk(root, 0, 32, visited, nil) == 0);
    CHECK(visited.count == 0);
}

int main(void)
{
    @autoreleasepool {
        CHECK(JDXIsJDSettingsPage(@"设置", nil, @"JDGenericPageController"));
        CHECK(JDXIsJDSettingsPage(nil, @"账户设置", @"GenericTableController"));
        CHECK(JDXIsJDSettingsPage(@"账号设置", nil, @"JDWebViewController"));
        CHECK(JDXIsJDSettingsPage(@"Settings", nil, @"JDSettingsScreen"));
        CHECK(JDXIsJDSettingsPage(@"Account Settings", nil, @"JDAccountScreen"));
        CHECK(JDXIsJDSettingsPage(nil, nil, @"JDSettingViewController"));
        CHECK(JDXIsJDSettingsPage(nil, nil, @"MyJdSettingViewController"));
        CHECK(!JDXIsJDSettingsPage(@"搜索", nil, @"FinalSearchListViewController"));
        CHECK(!JDXIsJDSettingsPage(@"消息设置", nil, @"JDMessageSettingsController"));
        CHECK(!JDXIsJDSettingsPage(@"支付设置", nil, @"PaymentSettingsController"));
        CHECK(!JDXIsJDSettingsPage(@"设置", nil, @"JDXSettingsController"));
        CHECK(!JDXIsJDSettingsPage(nil, nil, @"JDXSettingsController"));
        CHECK(!JDXIsJDSettingsPage(nil, nil, @"GenericPageController"));
        CHECK(!JDXIsJDSettingsPage(nil, nil, nil));
        CHECK(JDXIsJDSettingsNavigationLabel(@"设置", 220, 84, 440, 62));
        CHECK(JDXIsJDSettingsNavigationLabel(@"Settings", 195, 74, 390, 47));
        CHECK(!JDXIsJDSettingsNavigationLabel(@"设置", 220, 300, 440, 62));
        CHECK(!JDXIsJDSettingsNavigationLabel(@"设置", 22, 84, 440, 62));
        CHECK(!JDXIsJDSettingsNavigationLabel(@"消息设置", 220, 84, 440, 62));
        CHECK(!JDXIsJDSettingsNavigationLabel(@"设置", NAN, 84, 440, 62));
        CHECK(!JDXIsJDSettingsNavigationLabel(@"设置", 220, INFINITY, 440, 62));
        CHECK(!JDXIsJDSettingsNavigationLabel(@"设置", 220, 84, 0, 62));
        CHECK(!JDXIsJDSettingsTitle((id)@123));
        TestVisibleTree();
        puts("PASS: settings matching, custom-header geometry, visible-tree order and traversal bounds");
    }
    return 0;
}
