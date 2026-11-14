#import <Foundation/Foundation.h>
#import "../JDXSettingsPage.m"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\\n", __LINE__, #x); exit(1); } } while (0)
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
        puts("PASS: native settings page matching is narrow");
    }
    return 0;
}
