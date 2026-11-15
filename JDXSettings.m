#import "JDXSettings.h"
#import "JDXConfig.h"
#import "JDXDiagnostics.h"
#import "JDXSettingsPage.h"
#include "JDXSettingsPage.m"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface JDXSettingsController : UITableViewController
@property(nonatomic) BOOL exporting;
@end

@implementation JDXSettingsController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = [@"JDX " stringByAppendingString:@JDX_BUILD_VERSION];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 84;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(configurationChanged:)
        name:JDXConfigurationDidChangeNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)configurationChanged:(__unused NSNotification *)notification { [self.tableView reloadData]; }
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSArray<NSNumber *> *)rulesForSection:(NSInteger)section
{
    NSMutableArray *rules = [NSMutableArray array];
    if (section < 2 || section > 5) return rules;
    for (NSUInteger index = 0; index < JDXRuleCount; ++index)
        if (JDXRules[index].group == (NSUInteger)(section - 2)) [rules addObject:@(index)];
    return rules;
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView { return 7; }
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 3;
    if (section == 1) return 3;
    if (section == 6) return 6;
    return [self rulesForSection:section].count;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[@"状态与总开关", @"快速配置", @"开屏", @"首页", @"搜索", @"我的与商品详情", @"日志与增强诊断"][section];
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0)
        return @"京东「我的 → 设置」可点 JDX；其他页面可单击屏幕边缘的 JDX 小按钮，按住拖动可换位置。键盘、分享面板和本设置页显示时小按钮会隐藏。双指长按仍保留。";
    if (section == 1)
        return @"每个位置的开关：开启＝拦截，关闭＝保留。推荐配置保留正常商品推荐与搜索内容。全部拦截也会隐藏正常推荐区。";
    if (section == 6)
        return @"复现前开启增强诊断，复现后立即导出。记录应用版本、开关、规则命中、方法适配与页面类名；不采集账号、订单、地址或网络正文，不自动上传。增强记录最多持续 10 分钟。";
    return nil;
}

- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSInteger tag = NSIntegerMin;
    BOOL on = NO;
    if (indexPath.section == 0 && indexPath.row == 0) {
        cell.textLabel.text = @"启用 JDX 拦截";
        cell.detailTextLabel.text = JDXSafeModeEnabled() || JDXSafeModeActive() ?
            @"纯净模式下业务拦截暂停。关闭纯净模式并彻底退出重开京东后，再启用所需位置。" :
            @"关闭后立即暂停过滤，保留各项选择。若要完全不安装业务钩子，请启用下方纯净模式后退出重开。";
        tag = -1; on = JDXMasterEnabled();
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        NSDictionary *runtime = JDXRuntimeSnapshot();
        NSDictionary *environment = runtime[@"environment"];
        cell.textLabel.text = JDXSafeModeActive() ? @"本次启动：纯净模式" :
            (JDXConfigurationCompatible() ? @"已识别应用版本" : @"当前版本仅启用诊断");
        cell.detailTextLabel.text = [NSString stringWithFormat:@"版本 %@ · 构建 %@\n已安装业务方法 %@/%@%@%@",
            environment[@"app_version"] ?: @"?", environment[@"app_build"] ?: @"?",
            runtime[@"installed_hooks"], runtime[@"total_hooks"],
            JDXConfigurationCompatible() ? @"" : @"；未适配版本不执行广告拦截",
            JDXRestartRequired() ? @"\n模式已更改：请从多任务划掉京东，再重新打开。" : @""];
    } else if (indexPath.section == 0) {
        cell.textLabel.text = @"纯净模式（重启生效）";
        cell.detailTextLabel.text = @"纯净启动完全不安装业务钩子，保留 JDX 设置和日志。切换后从多任务划掉京东再打开；开启时也会立即暂停过滤。";
        tag = -3; on = JDXSafeModeEnabled();
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @[@"恢复推荐配置", @"所有位置：全部拦截", @"所有位置：全部保留"][indexPath.row];
        cell.detailTextLabel.text = @[@"保留正常推荐和搜索结果，只开启已识别的开屏与首页推广拦截。",
            @"开启下面的全部位置，包括正常商品推荐流和全部底部横幅。",
            @"关闭下面的全部位置。也可用总开关临时停用并保留各项选择。"][indexPath.row];
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section >= 2 && indexPath.section <= 5) {
        NSUInteger rule = [[self rulesForSection:indexPath.section][indexPath.row] unsignedIntegerValue];
        cell.textLabel.text = @(JDXRules[rule].title);
        cell.detailTextLabel.text = @(JDXRules[rule].detail);
        tag = (NSInteger)rule; on = JDXRuleEnabled(rule);
    } else if (indexPath.section == 6) {
        cell.textLabel.text = @[@"增强诊断", @"运行检查并查看诊断", @"标记刚才出现的问题",
            @"导出日志与诊断包", @"暂时恢复京东原样", @"清空历史日志"][indexPath.row];
        cell.detailTextLabel.text = @[
            @"增加规则命中样本与页面变化记录，限时、限量保存。",
            @"检查方法签名、父类隔离、当前生效状态和旧插件线索。",
            @"选择首页空白、搜索报错等问题，作为复现时间标记。",
            @"生成 JSON 文件，通过系统分享保存到文件或发送反馈。",
            @"关闭总开关并保留各项选择；返回页面后刷新对比。",
            @"清除本插件的历史日志和导出缓存，保留当前设置。"][indexPath.row];
        if (indexPath.row == 0) {
            tag = -2; on = JDXDiagnosticsEnhanced();
        } else {
            cell.textLabel.textColor = indexPath.row == 5 ? UIColor.systemRedColor : UIColor.systemBlueColor;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        if (indexPath.row == 3 && self.exporting) cell.detailTextLabel.text = @"正在生成诊断文件…";
    }
    if (tag != NSIntegerMin) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.tag = tag;
        toggle.on = on;
        toggle.accessibilityLabel = cell.textLabel.text;
        toggle.accessibilityHint = tag >= 0 ? @"开启拦截这个位置，关闭保留这个位置" : cell.detailTextLabel.text;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)toggle
{
    if (toggle.tag == -1) JDXSetMasterEnabled(toggle.isOn);
    else if (toggle.tag == -2) JDXSetEnhancedEnabled(toggle.isOn);
    else if (toggle.tag == -3) {
        JDXSetSafeModeEnabled(toggle.isOn);
        if (JDXRestartRequired()) [self showMessage:toggle.isOn ?
            @"已暂停业务过滤。请从多任务划掉京东再打开，让下一次启动完全不安装业务钩子。设置和日志会保留。" :
            @"请从多任务划掉京东再打开，才会按总开关和位置选择启用拦截。本次纯净会话仍不安装业务钩子。"];
    }
    else JDXSetRuleEnabled((JDXRule)toggle.tag, toggle.isOn);
}

- (void)showMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"JDX" message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDiagnostics
{
    JDXRunDiagnostics();
    NSDictionary *runtime = JDXRuntimeSnapshot();
    NSDictionary *diagnostics = JDXDiagnosticsSnapshot();
    NSDictionary *details = @{@"runtime": runtime, @"diagnostics": diagnostics};
    NSData *data = [NSJSONSerialization dataWithJSONObject:details
        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    UIViewController *controller = [UIViewController new];
    controller.title = @"诊断详情";
    UITextView *text = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    text.editable = NO;
    text.alwaysBounceVertical = YES;
    text.backgroundColor = UIColor.systemBackgroundColor;
    text.textColor = UIColor.labelColor;
    text.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    text.textContainerInset = UIEdgeInsetsMake(16, 14, 16, 14);
    text.text = [NSString stringWithFormat:@"%@\n\n未匹配的方法会跳过。旧插件或方法被改写只是排障线索，不能单凭此报告判定网络故障原因。\n\n%@",
        JDXDiagnosticsSummary(), data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"报告生成失败"];
    controller.view = text;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)markIssueAt:(NSIndexPath *)indexPath
{
    NSArray *labels = @[@"首页空白", @"搜索提示断网", @"购物车加载失败", @"订单页空白", @"逛／视频页加载失败", @"其他页面异常"];
    NSArray *codes = @[@"home_blank", @"search_network_error", @"cart_load_failure",
        @"orders_blank", @"discovery_load_failure", @"other_page_failure"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"标记复现问题"
        message:@"只记录问题类型和时间，不记录页面内容。" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger index = 0; index < labels.count; ++index) {
        [sheet addAction:[UIAlertAction actionWithTitle:labels[index] style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) {
                JDXLog(@"symptom_marked", @{@"reason_code": codes[index],
                    @"master_enabled": @(JDXMasterEnabled())});
                [self showMessage:@"已标记。可继续复现或导出诊断包。"];
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)exportAt:(NSIndexPath *)indexPath
{
    if (self.exporting) return;
    self.exporting = YES;
    self.tableView.userInteractionEnabled = NO;
    JDXRunDiagnostics();
    NSDictionary *state = JDXRuntimeSnapshot();
    [self.tableView reloadData];
    __weak JDXSettingsController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSURL *file = JDXExportDiagnostics(state, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            JDXSettingsController *controller = weakSelf;
            if (!controller) return;
            controller.exporting = NO;
            controller.tableView.userInteractionEnabled = YES;
            [controller.tableView reloadData];
            if (!controller.viewIfLoaded.window) return;
            if (!file) {
                [controller showMessage:@"诊断文件生成失败，请稍后重试。磁盘写入状态可在诊断详情中查看。"];
                return;
            }
            UIActivityViewController *activity = [[UIActivityViewController alloc]
                initWithActivityItems:@[file] applicationActivities:nil];
            activity.popoverPresentationController.sourceView = controller.tableView;
            activity.popoverPresentationController.sourceRect = [controller.tableView rectForRowAtIndexPath:indexPath];
            [controller presentViewController:activity animated:YES completion:nil];
        });
    });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        JDXApplyProfile((JDXProfile)indexPath.row);
        [self.tableView reloadData];
    } else if (indexPath.section == 6) {
        switch (indexPath.row) {
            case 1: [self showDiagnostics]; break;
            case 2: [self markIssueAt:indexPath]; break;
            case 3: [self exportAt:indexPath]; break;
            case 4: JDXSetMasterEnabled(NO); [self showMessage:@"拦截已暂停。请关闭设置，刷新或重新进入异常页面，再与开启时对比。"]; break;
            case 5: JDXClearDiagnostics(); [self showMessage:@"历史日志已清空，当前设置保留。"]; break;
            default: break;
        }
    }
}
@end

// JD 16.1.83 can display pages through a custom navigation stack without
// registering them as childViewControllers. Resolve the visible view's responder
// chain as well as UIKit containment; never instantiate a host controller/view.
@interface JDXShortcutButton : UIButton
@property(nonatomic) CGPoint normalizedCenter;
@end
@implementation JDXShortcutButton
@end

@interface JDXVisiblePage : NSObject
@property(nonatomic, strong) UIViewController *page;
@property(nonatomic, strong) UIViewController *presenter;
@property(nonatomic, strong) UIViewController *settingsPage;
@property(nonatomic, copy) NSArray<NSString *> *path;
@property(nonatomic, copy) NSString *discovery;
@property(nonatomic, copy) NSString *settingsMatch;
@property(nonatomic) NSUInteger scannedViews;
@property(nonatomic) BOOL suppressed;
@end
@implementation JDXVisiblePage
@end

static BOOL JDXIsShortcutView(UIView *view)
{
    for (NSUInteger depth = 0; view && depth < 64; ++depth, view = view.superview)
        if ([view isKindOfClass:JDXShortcutButton.class]) return YES;
    return NO;
}

static UIView *JDXContentHitTest(UIWindow *window, CGPoint point)
{
    UIView *hit = [window hitTest:point withEvent:nil];
    if (!JDXIsShortcutView(hit)) return hit;
    // Our two buttons are direct window children. Inspect beneath them without
    // toggling hidden/userInteractionEnabled, which would cancel an active drag.
    for (UIView *child in window.subviews.reverseObjectEnumerator) {
        if ([child isKindOfClass:JDXShortcutButton.class]) continue;
        UIView *underlying = [child hitTest:[child convertPoint:point fromView:window] withEvent:nil];
        if (underlying) return underlying;
    }
    return window;
}

static CGRect JDXVisibleViewRect(UIView *view, UIWindow *window)
{
    if (!view || !window || (view != window && view.window != window)) return CGRectNull;
    CGRect result = [view convertRect:view.bounds toView:window];
    if (!isfinite(result.origin.x) || !isfinite(result.origin.y) ||
        !isfinite(result.size.width) || !isfinite(result.size.height)) return CGRectNull;
    result = CGRectIntersection(result, window.bounds);
    NSUInteger depth = 0;
    for (UIView *ancestor = view; ancestor && depth++ < 64; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha <= 0.01) return CGRectNull;
        if (ancestor.clipsToBounds)
            result = CGRectIntersection(result, [ancestor convertRect:ancestor.bounds toView:window]);
        if (CGRectIsNull(result) || CGRectIsEmpty(result)) return CGRectNull;
        if (ancestor == window) return result;
    }
    return CGRectNull;
}

static BOOL JDXControllerHasVisiblePage(UIViewController *controller, UIWindow *window)
{
    CGRect rect = JDXVisibleViewRect(controller.viewIfLoaded, window);
    return !CGRectIsNull(rect) && CGRectGetWidth(rect) >= CGRectGetWidth(window.bounds) * 0.45 &&
        CGRectGetHeight(rect) >= CGRectGetHeight(window.bounds) * 0.24;
}

static BOOL JDXIsSystemOrPluginController(UIViewController *controller)
{
    for (NSUInteger depth = 0; controller && depth < 24; ++depth, controller = controller.parentViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name hasPrefix:@"JDX"] || [controller isKindOfClass:UIAlertController.class] ||
            [controller isKindOfClass:UIActivityViewController.class] ||
            [controller isKindOfClass:UIImagePickerController.class] ||
            [controller isKindOfClass:UIDocumentPickerViewController.class] ||
            [name hasPrefix:@"UIInput"] || [name hasPrefix:@"UIRemote"] ||
            [name hasPrefix:@"_UIRemote"] || [name hasPrefix:@"_UIScene"]) return YES;
        if ([controller isKindOfClass:UINavigationController.class] &&
            [[(UINavigationController *)controller viewControllers].firstObject isKindOfClass:JDXSettingsController.class])
            return YES;
    }
    return NO;
}

static UIViewController *JDXResponderPage(UIView *view, UIWindow *window)
{
    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 64; ++depth) {
        if ([responder isKindOfClass:UIViewController.class] &&
            JDXControllerHasVisiblePage((UIViewController *)responder, window)) return (UIViewController *)responder;
        UIResponder *next = responder.nextResponder;
        if (next == responder) break;
        responder = next;
    }
    return nil;
}

static NSUInteger JDXViewDepth(UIView *view)
{
    NSUInteger result = 0;
    for (; view && result < 64; view = view.superview) result++;
    return result;
}

static BOOL JDXViewContainsVisibleHit(UIView *view, UIWindow *window)
{
    CGRect rect = JDXVisibleViewRect(view, window);
    if (CGRectIsNull(rect)) return NO;
    UIView *hit = JDXContentHitTest(window, CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect)));
    return hit && [hit isDescendantOfView:view];
}

static JDXVisiblePage *JDXFindVisiblePage(UIWindow *window)
{
    JDXVisiblePage *result = [JDXVisiblePage new];
    NSMutableArray<UIViewController *> *chain = [NSMutableArray array];
    UIViewController *controller = window.rootViewController;
    for (NSUInteger depth = 0; controller && depth < 24; ++depth) {
        if ([chain containsObject:controller]) break;
        [chain addObject:controller];
        UIViewController *next = nil;
        UIViewController *presented = controller.presentedViewController;
        if (presented && !presented.isBeingDismissed && presented.viewIfLoaded.window == window)
            next = presented;
        else if ([controller isKindOfClass:UINavigationController.class])
            next = [(UINavigationController *)controller visibleViewController];
        else if ([controller isKindOfClass:UITabBarController.class])
            next = [(UITabBarController *)controller selectedViewController];
        else for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
            if (JDXControllerHasVisiblePage(child, window) && JDXViewContainsVisibleHit(child.viewIfLoaded, window)) {
                next = child;
                break;
            }
        }
        if (!next || next == controller || next.viewIfLoaded.window != window) break;
        controller = next;
    }
    result.presenter = chain.lastObject;
    result.page = result.presenter;
    result.discovery = @"containment";
    result.settingsMatch = @"none";
    for (UIViewController *entry in chain)
        if (JDXIsSystemOrPluginController(entry)) result.suppressed = YES;

    if (!result.suppressed) {
        CGRect safe = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
        // Several content points avoid a small overlay/child component becoming
        // the reported page. Only page-sized controller views are accepted.
        const CGFloat points[][2] = {{0.5, 0.5}, {0.5, 0.25}, {0.35, 0.72}, {0.65, 0.72}};
        NSUInteger bestDepth = JDXViewDepth(result.page.viewIfLoaded);
        for (NSUInteger index = 0; index < sizeof(points) / sizeof(points[0]); ++index) {
            CGPoint point = CGPointMake(CGRectGetMinX(safe) + CGRectGetWidth(safe) * points[index][0],
                                        CGRectGetMinY(safe) + CGRectGetHeight(safe) * points[index][1]);
            UIView *hit = JDXContentHitTest(window, point);
            UIViewController *candidate = JDXResponderPage(hit, window);
            if (!candidate || JDXIsSystemOrPluginController(candidate)) continue;
            NSUInteger depth = JDXViewDepth(candidate.viewIfLoaded);
            if (depth > bestDepth) {
                result.page = candidate;
                result.discovery = @"view_responder";
                bestDepth = depth;
            }
        }
        if (result.page && ![chain containsObject:result.page]) [chain addObject:result.page];
        UIViewController *candidate = result.page;
        for (NSUInteger depth = 0; candidate && depth < 16; ++depth, candidate = candidate.parentViewController) {
            if (JDXControllerHasVisiblePage(candidate, window) &&
                JDXIsJDSettingsPage(candidate.navigationItem.title, candidate.title, NSStringFromClass(candidate.class))) {
                result.settingsPage = candidate;
                result.settingsMatch = @"controller_metadata";
                break;
            }
        }
        if (!result.settingsPage) {
            // Inspect only the on-screen navigation band. A settings row in the
            // account/content area is outside this band. No text is retained.
            CGRect band = CGRectMake(CGRectGetMinX(window.bounds), window.safeAreaInsets.top - 4,
                                     CGRectGetWidth(window.bounds), 76);
            result.scannedViews = JDXVisitVisibleTree(window, 192, 32,
                ^NSArray *(id node) { return [(UIView *)node subviews]; },
                ^BOOL(id node) {
                    UIView *view = node;
                    if ([view isKindOfClass:JDXShortcutButton.class]) return NO;
                    CGRect rect = JDXVisibleViewRect(view, window);
                    return !CGRectIsNull(rect) && CGRectIntersectsRect(rect, band);
                },
                ^BOOL(id node, __unused NSUInteger depth) {
                    UIView *view = node;
                    if (![view isKindOfClass:UILabel.class]) return NO;
                    CGRect rect = [view convertRect:view.bounds toView:window];
                    if (!JDXIsJDSettingsNavigationLabel([(UILabel *)view text], CGRectGetMidX(rect),
                        CGRectGetMidY(rect), CGRectGetWidth(window.bounds), window.safeAreaInsets.top)) return NO;
                    UIView *hit = JDXContentHitTest(window, CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect)));
                    // Non-interactive title labels hit their parent. A sibling
                    // overlay/control covering the title must fail this check.
                    if (!hit || (![view isDescendantOfView:hit] && ![hit isDescendantOfView:view])) return NO;
                    UIViewController *owner = JDXResponderPage(view, window) ?: result.page;
                    if (!owner || JDXIsSystemOrPluginController(owner)) return NO;
                    result.settingsPage = owner;
                    result.settingsMatch = @"visible_navigation_label";
                    return YES;
                });
        }
    }
    NSMutableArray *classes = [NSMutableArray array];
    for (UIViewController *entry in chain) [classes addObject:NSStringFromClass(entry.class)];
    if (result.settingsPage && ![chain containsObject:result.settingsPage])
        [classes addObject:NSStringFromClass(result.settingsPage.class)];
    result.path = classes;
    return result;
}

@interface JDXWindowShortcuts : NSObject
@property(nonatomic, strong) JDXShortcutButton *floating;
@property(nonatomic, strong) JDXShortcutButton *settings;
@property(nonatomic, strong) UIBarButtonItem *navigationItem;
@property(nonatomic, weak) UIViewController *navigationOwner;
@property(nonatomic, copy) NSString *lastState;
@end
@implementation JDXWindowShortcuts
@end

@interface JDXSettingsEntry : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSHashTable<UIWindow *> *knownWindows;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic) BOOL presentingSettings;
@end

static char JDXGestureKey;
static char JDXWindowShortcutsKey;
static JDXSettingsEntry *JDXEntry;
static NSString *const JDXFloatingPositionKey = @"com.solhk.jdx.shortcut-position";

@implementation JDXSettingsEntry
- (NSArray<UIWindow *> *)normalWindows:(NSArray<UIWindow *> *)candidates
{
    NSMutableArray *windows = [NSMutableArray array];
    for (UIWindow *window in candidates) {
        if (window.hidden || window.alpha <= 0.01 || window.windowLevel != UIWindowLevelNormal ||
            !window.rootViewController || !window.rootViewController.viewIfLoaded) continue;
        if (window.windowScene && window.windowScene.activationState != UISceneActivationStateForegroundActive) continue;
        if (window.isKeyWindow) return @[window];
        [windows addObject:window];
    }
    return windows.count ? @[windows.lastObject] : @[];
}

- (NSArray<UIWindow *> *)windows
{
    NSMutableArray *windows = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive)
            [windows addObjectsFromArray:[self normalWindows:[(UIWindowScene *)scene windows]]];
    }
    if (!windows.count) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:[self normalWindows:application.windows]];
#pragma clang diagnostic pop
    }
    return windows;
}

- (JDXShortcutButton *)buttonWithTitle:(NSString *)title selector:(SEL)selector
{
    JDXShortcutButton *button = [JDXShortcutButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityLabel = @"打开 JDX 插件设置";
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.tintColor = UIColor.systemRedColor;
    button.layer.cornerRadius = 12;
    button.layer.borderWidth = 1;
    button.layer.borderColor = UIColor.separatorColor.CGColor;
    button.hidden = YES;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)attachWindow:(UIWindow *)window
{
    if (!window || window.windowLevel != UIWindowLevelNormal) return;
    [self.knownWindows addObject:window];
    if (!objc_getAssociatedObject(window, &JDXGestureKey)) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(open:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 0.8;
        gesture.cancelsTouchesInView = NO;
        gesture.delegate = self;
        [window addGestureRecognizer:gesture];
        objc_setAssociatedObject(window, &JDXGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (objc_getAssociatedObject(window, &JDXWindowShortcutsKey)) return;
    JDXWindowShortcuts *state = [JDXWindowShortcuts new];
    state.floating = [self buttonWithTitle:@"JDX" selector:@selector(openFloating:)];
    state.floating.accessibilityHint = @"单击打开，按住拖动可移动到屏幕边缘其他位置";
    state.floating.normalizedCenter = CGPointMake(1, 0.65);
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:JDXFloatingPositionKey];
    if ([saved isKindOfClass:NSDictionary.class] && [saved[@"x"] isKindOfClass:NSNumber.class] &&
        [saved[@"y"] isKindOfClass:NSNumber.class]) {
        double x = [saved[@"x"] doubleValue], y = [saved[@"y"] doubleValue];
        if (isfinite(x) && isfinite(y) && x >= 0 && x <= 1 && y >= 0 && y <= 1)
            state.floating.normalizedCenter = CGPointMake(x, y);
    }
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFloating:)];
    [state.floating addGestureRecognizer:pan];
    [window addSubview:state.floating];
    objc_setAssociatedObject(window, &JDXWindowShortcutsKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    JDXLog(@"settings_shortcut_attached", @{@"class": NSStringFromClass(window.rootViewController.class),
                                            @"mode": @"window_floating"});
}

- (CGRect)floatingCenterBounds:(UIWindow *)window
{
    CGRect safe = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
    CGRect rect = CGRectInset(safe, 8 + 26, 8 + 22);
    if (CGRectGetWidth(rect) <= 0 || CGRectGetHeight(rect) <= 0)
        rect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    return rect;
}

- (void)layoutFloating:(JDXShortcutButton *)button inWindow:(UIWindow *)window
{
    CGRect bounds = [self floatingCenterBounds:window];
    button.bounds = CGRectMake(0, 0, 52, 44);
    button.center = CGPointMake(CGRectGetMinX(bounds) + CGRectGetWidth(bounds) * button.normalizedCenter.x,
                               CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * button.normalizedCenter.y);
}

- (void)dragFloating:(UIPanGestureRecognizer *)gesture
{
    JDXShortcutButton *button = (JDXShortcutButton *)gesture.view;
    UIWindow *window = button.window;
    if (!window) return;
    CGPoint delta = [gesture translationInView:window];
    CGRect bounds = [self floatingCenterBounds:window];
    CGPoint center = CGPointMake(MAX(CGRectGetMinX(bounds), MIN(CGRectGetMaxX(bounds), button.center.x + delta.x)),
                                 MAX(CGRectGetMinY(bounds), MIN(CGRectGetMaxY(bounds), button.center.y + delta.y)));
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled)
        center.x = center.x < CGRectGetMidX(bounds) ? CGRectGetMinX(bounds) : CGRectGetMaxX(bounds);
    button.center = center;
    button.normalizedCenter = CGPointMake(CGRectGetWidth(bounds) > 0 ? (center.x - CGRectGetMinX(bounds)) / CGRectGetWidth(bounds) : 1,
                                          CGRectGetHeight(bounds) > 0 ? (center.y - CGRectGetMinY(bounds)) / CGRectGetHeight(bounds) : 0.65);
    [gesture setTranslation:CGPointZero inView:window];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled)
        [NSUserDefaults.standardUserDefaults setObject:@{@"x": @(button.normalizedCenter.x), @"y": @(button.normalizedCenter.y)}
                                               forKey:JDXFloatingPositionKey];
}

- (void)removeNavigationShortcut:(JDXWindowShortcuts *)state
{
    if (state.navigationItem && state.navigationOwner) {
        NSMutableArray *items = [state.navigationOwner.navigationItem.rightBarButtonItems mutableCopy];
        [items removeObject:state.navigationItem];
        state.navigationOwner.navigationItem.rightBarButtonItems = items;
    }
    state.navigationOwner = nil;
    state.navigationItem = nil;
}

- (BOOL)headerSlotIsFree:(CGRect)rect window:(UIWindow *)window
{
    const CGFloat samples[] = {0.1, 0.5, 0.9};
    for (NSUInteger index = 0; index < 3; ++index) {
        CGPoint point = CGPointMake(CGRectGetMinX(rect) + CGRectGetWidth(rect) * samples[index], CGRectGetMidY(rect));
        UIView *hit = JDXContentHitTest(window, point);
        for (NSUInteger depth = 0; hit && hit != window && depth < 24; ++depth, hit = hit.superview) {
            if ([hit isKindOfClass:UIControl.class] && hit.userInteractionEnabled) return NO;
            CGRect frame = JDXVisibleViewRect(hit, window);
            if (hit.gestureRecognizers.count && !CGRectIsNull(frame) &&
                CGRectGetWidth(frame) < CGRectGetWidth(window.bounds) * 0.5 && CGRectGetHeight(frame) <= 80) return NO;
        }
    }
    return YES;
}

- (NSString *)attachSettingsShortcut:(JDXVisiblePage *)page window:(UIWindow *)window state:(JDXWindowShortcuts *)state
{
    UIViewController *controller = page.settingsPage;
    UINavigationController *navigation = controller.navigationController;
    if ([controller isKindOfClass:UINavigationController.class]) navigation = (UINavigationController *)controller;
    UIViewController *owner = navigation.visibleViewController;
    BOOL hasBar = navigation && owner && !navigation.navigationBarHidden &&
        navigation.navigationBar.topItem == owner.navigationItem && JDXViewContainsVisibleHit(navigation.navigationBar, window);
    NSArray *items = owner.navigationItem.rightBarButtonItems ?: @[];
    NSUInteger ownCount = state.navigationItem && [items containsObject:state.navigationItem] ? 1 : 0;
    if (hasBar && items.count - ownCount <= 1) {
        if (state.navigationOwner != owner) [self removeNavigationShortcut:state];
        if (!state.navigationItem) {
            state.navigationItem = [[UIBarButtonItem alloc] initWithTitle:@"JDX" style:UIBarButtonItemStylePlain
                target:self action:@selector(openNativeSettings:)];
            state.navigationItem.accessibilityLabel = @"打开 JDX 插件设置";
            state.navigationOwner = owner;
        }
        if (![owner.navigationItem.rightBarButtonItems containsObject:state.navigationItem]) {
            NSMutableArray *updated = [owner.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
            [updated insertObject:state.navigationItem atIndex:0];
            owner.navigationItem.rightBarButtonItems = updated;
        }
        return @"navigation_bar";
    }
    [self removeNavigationShortcut:state];
    CGRect safe = UIEdgeInsetsInsetRect(window.bounds, window.safeAreaInsets);
    CGRect slot = CGRectMake(CGRectGetMaxX(safe) - 116, CGRectGetMinY(safe), 104, 44);
    if (CGRectGetWidth(safe) < 300 || ![self headerSlotIsFree:slot window:window]) return @"window_floating";
    if (!state.settings) {
        state.settings = [self buttonWithTitle:@"JDX 设置" selector:@selector(openSettingsButton:)];
        [window addSubview:state.settings];
    }
    state.settings.frame = slot;
    state.settings.hidden = NO;
    [window bringSubviewToFront:state.settings];
    return @"custom_header";
}

- (void)observePage
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self observePage]; });
        return;
    }
    NSArray *windows = UIApplication.sharedApplication.applicationState == UIApplicationStateActive ? [self windows] : @[];
    for (UIWindow *window in self.knownWindows.allObjects) {
        if ([windows containsObject:window]) continue;
        JDXWindowShortcuts *state = objc_getAssociatedObject(window, &JDXWindowShortcutsKey);
        state.floating.hidden = YES;
        state.settings.hidden = YES;
        [self removeNavigationShortcut:state];
    }
    BOOL enhanced = JDXDiagnosticsEnhanced();
    for (UIWindow *window in windows) {
        [self attachWindow:window];
        JDXWindowShortcuts *state = objc_getAssociatedObject(window, &JDXWindowShortcutsKey);
        JDXVisiblePage *page = JDXFindVisiblePage(window);
        BOOL suppressed = self.keyboardVisible || self.presentingSettings || page.suppressed || !page.page;
        NSString *mode = @"suppressed";
        if (!suppressed) {
            mode = page.settingsPage ? [self attachSettingsShortcut:page window:window state:state] : @"window_floating";
            if (!page.settingsPage) [self removeNavigationShortcut:state];
            if ([mode isEqual:@"window_floating"]) {
                [self layoutFloating:state.floating inWindow:window];
                state.floating.hidden = NO;
                [window bringSubviewToFront:state.floating];
            } else state.floating.hidden = YES;
            if (![mode isEqual:@"custom_header"]) state.settings.hidden = YES;
            if (enhanced) JDXRecordPage(NSStringFromClass(page.page.class));
        } else {
            state.floating.hidden = YES;
            state.settings.hidden = YES;
            [self removeNavigationShortcut:state];
        }
        NSDictionary *snapshot = @{@"class": page.page ? NSStringFromClass(page.page.class) : @"none",
            @"visible_controller_path": page.path ?: @[], @"discovery": page.discovery ?: @"none",
            @"settings_page_detected": @(page.settingsPage != nil), @"settings_match": page.settingsMatch ?: @"none",
            @"mode": mode, @"scanned_views": @(page.scannedViews), @"window_count": @(windows.count),
            @"floating_attached": @(state.floating.superview == window), @"floating_visible": @(!state.floating.hidden),
            @"settings_button_visible": @(state.settings && !state.settings.hidden), @"keyboard_visible": @(self.keyboardVisible)};
        @synchronized (self) { self.snapshot = snapshot; }
        NSString *signature = [NSString stringWithFormat:@"%@:%@:%@", snapshot[@"class"], mode, page.settingsMatch];
        if (![state.lastState isEqual:signature]) {
            state.lastState = signature;
            JDXLog(@"settings_entry_state", snapshot);
        }
    }
}

- (void)refresh:(__unused NSNotification *)notification { [self observePage]; }

- (void)keyboardChanged:(NSNotification *)notification
{
    void (^update)(void) = ^{
        self.keyboardVisible = ![notification.name isEqual:UIKeyboardWillHideNotification];
        [self observePage];
    };
    if (NSThread.isMainThread) update(); else dispatch_async(dispatch_get_main_queue(), update);
}

- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gesture
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(__unused UIGestureRecognizer *)other
{ return YES; }

- (void)presentSettingsInWindow:(UIWindow *)window source:(NSString *)source
{
    if (!window || self.presentingSettings || self.keyboardVisible) return;
    JDXVisiblePage *page = JDXFindVisiblePage(window);
    UIViewController *presenter = page.presenter;
    if (page.suppressed || !presenter.viewIfLoaded.window || presenter.presentedViewController ||
        presenter.isBeingPresented || presenter.isBeingDismissed || presenter.transitionCoordinator.isAnimated) return;
    self.presentingSettings = YES;
    [self observePage];
    JDXRecordPage(NSStringFromClass(page.page.class));
    JDXLog(@"settings_opened", @{@"class": NSStringFromClass(page.page.class), @"entry": source});
    JDXSettingsController *settings = [[JDXSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
    [presenter presentViewController:navigation animated:YES completion:^{
        self.presentingSettings = NO;
        [self observePage];
    }];
    // UIKit can reject a presentation during an external transition. Do not
    // leave the only recovery entry permanently hidden if that happens.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.presentingSettings && presenter.presentedViewController != navigation) {
            self.presentingSettings = NO;
            [self observePage];
        }
    });
}

- (void)open:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIWindow *window = [gesture.view isKindOfClass:UIWindow.class] ? (UIWindow *)gesture.view : gesture.view.window;
    [self presentSettingsInWindow:window source:@"two_finger"];
}

- (void)openFloating:(UIButton *)button { [self presentSettingsInWindow:button.window source:@"floating_button"]; }
- (void)openSettingsButton:(UIButton *)button { [self presentSettingsInWindow:button.window source:@"jd_settings"]; }
- (void)openNativeSettings:(UIBarButtonItem *)item
{
    for (UIWindow *window in [self windows]) {
        JDXWindowShortcuts *state = objc_getAssociatedObject(window, &JDXWindowShortcutsKey);
        if (state.navigationItem == item) {
            [self presentSettingsInWindow:window source:@"jd_settings"];
            return;
        }
    }
}
@end

NSDictionary *JDXSettingsEntrySnapshot(void)
{
    JDXSettingsEntry *entry = JDXEntry;
    if (!entry) return @{@"mode": @"not_initialized"};
    @synchronized (entry) { return entry.snapshot ?: @{@"mode": @"waiting_for_window"}; }
}

void JDXInstallSettingsEntry(void)
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ JDXInstallSettingsEntry(); });
        return;
    }
    if (JDXEntry) return;
    JDXEntry = [JDXSettingsEntry new];
    JDXEntry.knownWindows = [NSHashTable weakObjectsHashTable];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIWindowDidBecomeKeyNotification, UIWindowDidBecomeVisibleNotification,
        UIApplicationDidBecomeActiveNotification, UIApplicationDidFinishLaunchingNotification,
        UIApplicationWillResignActiveNotification])
        [center addObserver:JDXEntry selector:@selector(refresh:) name:name object:nil];
    for (NSNotificationName name in @[UIKeyboardWillShowNotification, UIKeyboardWillHideNotification])
        [center addObserver:JDXEntry selector:@selector(keyboardChanged:) name:name object:nil];
    [JDXEntry observePage];
    JDXEntry.timer = [NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(__unused NSTimer *timer) {
        [JDXEntry observePage];
    }];
    JDXEntry.timer.tolerance = 0.15;
    [NSRunLoop.mainRunLoop addTimer:JDXEntry.timer forMode:NSRunLoopCommonModes];
}
