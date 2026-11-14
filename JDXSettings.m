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
    if (section == 0) return 2;
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
        return @"京东「我的 → 设置」右上角点「JDX」进入；没有标准导航栏时点「JDX 设置」按钮。双指长按仍可作为备用入口。已移除的内容需刷新页面。";
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
        cell.detailTextLabel.text = @"出现异常时先关闭此总开关，再刷新页面对比。设置与日志仍可使用。";
        tag = -1; on = JDXMasterEnabled();
    } else if (indexPath.section == 0) {
        NSDictionary *runtime = JDXRuntimeSnapshot();
        NSDictionary *environment = runtime[@"environment"];
        cell.textLabel.text = JDXConfigurationCompatible() ? @"已识别应用版本" : @"当前版本仅启用诊断";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"版本 %@ · 构建 %@\n已安装方法 %@/%@%@",
            environment[@"app_version"] ?: @"?", environment[@"app_build"] ?: @"?",
            runtime[@"installed_hooks"], runtime[@"total_hooks"],
            JDXConfigurationCompatible() ? @"" : @"；未适配版本不执行广告拦截"];
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

static UIViewController *JDXTopController(UIWindow *window)
{
    UIViewController *controller = window.rootViewController;
    for (NSUInteger depth = 0; controller && depth < 24; ++depth) {
        UIViewController *next = nil;
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
            next = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class])
            next = [(UINavigationController *)controller visibleViewController];
        else if ([controller isKindOfClass:UITabBarController.class])
            next = [(UITabBarController *)controller selectedViewController];
        else for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator)
            if (child.viewIfLoaded.window) { next = child; break; }
        if (!next || next == controller) break;
        controller = next;
    }
    return controller;
}

static UIViewController *JDXVisibleSettingsPage(UIViewController *controller)
{
    // JD settings may contain a web/child controller. Inspect only the visible
    // containment chain; do not inspect the page's cells or account contents.
    for (NSUInteger depth = 0; controller && depth < 12; ++depth) {
        if ([controller isKindOfClass:UINavigationController.class] ||
            [controller isKindOfClass:UITabBarController.class]) break;
        if (JDXIsJDSettingsPage(controller.navigationItem.title, controller.title,
                                NSStringFromClass(controller.class))) return controller;
        controller = controller.parentViewController;
    }
    return nil;
}

@interface JDXSettingsEntry : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, strong) NSTimer *timer;
@end

static char JDXGestureKey;
static char JDXNavigationShortcutKey;
static char JDXFloatingShortcutKey;
static JDXSettingsEntry *JDXEntry;

@implementation JDXSettingsEntry
- (NSArray<UIWindow *> *)windows
{
    NSMutableArray *windows = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive)
            [windows addObjectsFromArray:[(UIWindowScene *)scene windows]];
    }
    // JD builds using the UIApplicationDelegate lifecycle may have no scenes.
    // Inspect already-created windows as well as observing future key windows.
    if (!windows.count) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in application.windows)
            if (!window.hidden && window.windowLevel == UIWindowLevelNormal) [windows addObject:window];
#pragma clang diagnostic pop
    }
    return windows;
}

- (void)attachWindow:(UIWindow *)window
{
    if (!window || window.windowLevel != UIWindowLevelNormal ||
        objc_getAssociatedObject(window, &JDXGestureKey)) return;
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(open:)];
    gesture.numberOfTouchesRequired = 2;
    gesture.minimumPressDuration = 0.8;
    gesture.cancelsTouchesInView = NO;
    gesture.delegate = self;
    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(window, &JDXGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)refresh:(NSNotification *)notification
{
    if ([notification.object isKindOfClass:UIWindow.class]) [self attachWindow:notification.object];
    for (UIWindow *window in [self windows]) [self attachWindow:window];
    [self observePage];
}

- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gesture
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(__unused UIGestureRecognizer *)other
{ return YES; }

- (void)presentSettingsFromController:(UIViewController *)controller source:(NSString *)source
{
    if (!controller || !controller.viewIfLoaded.window || controller.presentedViewController ||
        [controller isKindOfClass:JDXSettingsController.class] ||
        [controller isKindOfClass:UIAlertController.class] ||
        [controller.navigationController.viewControllers.firstObject isKindOfClass:JDXSettingsController.class])
        return;
    JDXRecordPage(NSStringFromClass(controller.class));
    JDXLog(@"settings_opened", @{@"class": NSStringFromClass(controller.class), @"entry": source});
    JDXSettingsController *settings = [[JDXSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
    [controller presentViewController:navigation animated:YES completion:nil];
}

- (void)open:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIWindow *window = [gesture.view isKindOfClass:UIWindow.class] ? (UIWindow *)gesture.view : gesture.view.window;
    [self presentSettingsFromController:JDXTopController(window) source:@"two_finger"];
}

- (void)openFromJDSettings:(__unused id)sender
{
    for (UIWindow *window in [self windows]) {
        if (window.hidden || window.windowLevel != UIWindowLevelNormal || !window.isKeyWindow) continue;
        UIViewController *top = JDXTopController(window);
        if (JDXVisibleSettingsPage(top)) {
            [self presentSettingsFromController:top source:@"jd_settings"];
            return;
        }
    }
}

- (void)attachJDSettingsShortcut:(UIViewController *)controller
{
    if (!controller || !controller.viewIfLoaded.window) return;
    UINavigationController *navigation = controller.navigationController;
    BOOL hasBar = navigation && !navigation.navigationBarHidden && navigation.navigationBar.window;
    UIViewController *itemOwner = navigation.visibleViewController ?: controller;
    UIButton *floating = objc_getAssociatedObject(controller, &JDXFloatingShortcutKey);
    if (floating) floating.hidden = hasBar;
    if (hasBar) {
        UIBarButtonItem *item = objc_getAssociatedObject(itemOwner, &JDXNavigationShortcutKey);
        if (!item) {
            item = [[UIBarButtonItem alloc] initWithTitle:@"JDX" style:UIBarButtonItemStylePlain
                                                  target:self action:@selector(openFromJDSettings:)];
            item.accessibilityLabel = @"JDX 插件设置";
            objc_setAssociatedObject(itemOwner, &JDXNavigationShortcutKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSArray<UIBarButtonItem *> *existing = itemOwner.navigationItem.rightBarButtonItems ?: @[];
        if (![existing containsObject:item]) {
            NSMutableArray<UIBarButtonItem *> *items = [existing mutableCopy];
            [items insertObject:item atIndex:0]; // Preserve JD's original buttons.
            itemOwner.navigationItem.rightBarButtonItems = items;
            JDXLog(@"settings_shortcut_attached", @{@"class": NSStringFromClass(controller.class),
                                                   @"mode": @"navigation_bar"});
        }
        return;
    }
    // Nonstandard settings pages receive a visible 44pt-high, single-tap
    // shortcut. Only a positively identified settings page is modified.
    if (!floating) {
        floating = [UIButton buttonWithType:UIButtonTypeSystem];
        [floating setTitle:@"JDX 设置" forState:UIControlStateNormal];
        floating.accessibilityLabel = @"打开 JDX 插件设置";
        floating.backgroundColor = UIColor.secondarySystemBackgroundColor;
        floating.tintColor = UIColor.systemBlueColor;
        floating.layer.cornerRadius = 12;
        floating.layer.borderWidth = 1;
        floating.layer.borderColor = UIColor.separatorColor.CGColor;
        floating.translatesAutoresizingMaskIntoConstraints = NO;
        [floating addTarget:self action:@selector(openFromJDSettings:)
            forControlEvents:UIControlEventTouchUpInside];
        [controller.view addSubview:floating];
        [NSLayoutConstraint activateConstraints:@[
            [floating.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:8],
            [floating.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
            [floating.widthAnchor constraintGreaterThanOrEqualToConstant:104],
            [floating.heightAnchor constraintEqualToConstant:44]
        ]];
        objc_setAssociatedObject(controller, &JDXFloatingShortcutKey, floating, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        JDXLog(@"settings_shortcut_attached", @{@"class": NSStringFromClass(controller.class),
                                               @"mode": @"fallback_button"});
    }
    floating.hidden = NO;
    [controller.view bringSubviewToFront:floating];
}

- (void)observePage
{
    BOOL enhanced = JDXDiagnosticsEnhanced();
    for (UIWindow *window in [self windows]) {
        if (window.hidden || window.windowLevel != UIWindowLevelNormal || !window.isKeyWindow) continue;
        UIViewController *controller = JDXTopController(window);
        if (!controller || !controller.viewIfLoaded.window) continue;
        UIViewController *settingsPage = JDXVisibleSettingsPage(controller);
        if (settingsPage) [self attachJDSettingsShortcut:settingsPage];
        if (enhanced && ![controller isKindOfClass:JDXSettingsController.class] &&
            ![controller.navigationController.viewControllers.firstObject isKindOfClass:JDXSettingsController.class])
            JDXRecordPage(NSStringFromClass(controller.class));
    }
}

@end

void JDXInstallSettingsEntry(void)
{
    if (JDXEntry) return;
    JDXEntry = [JDXSettingsEntry new];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIWindowDidBecomeKeyNotification,
        UIApplicationDidBecomeActiveNotification, UIApplicationDidFinishLaunchingNotification])
        [center addObserver:JDXEntry selector:@selector(refresh:) name:name object:nil];
    [JDXEntry refresh:nil];
    JDXEntry.timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
        [JDXEntry observePage];
    }];
    JDXEntry.timer.tolerance = 0.3;
}
