#import "JDXConnectivity.h"
#import "JDXDiagnostics.h"
#import <Network/Network.h>

static NSLock *JDXConnectivityLock;
static NSDictionary *JDXConnectivityState;
static nw_path_monitor_t JDXPathMonitor;

static void JDXConnectivityInitialize(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JDXConnectivityLock = [NSLock new];
        JDXConnectivityLock.name = @"JDX system path metadata";
        JDXConnectivityState = @{@"status": @"waiting", @"passive": @YES,
            @"service_connectivity": @"not_tested"};
    });
}

NSDictionary *JDXConnectivitySnapshot(void)
{
    JDXConnectivityInitialize();
    [JDXConnectivityLock lock];
    NSDictionary *state = JDXConnectivityState;
    [JDXConnectivityLock unlock];
    return state;
}

static void JDXConnectivityPublish(NSDictionary *state)
{
    [JDXConnectivityLock lock];
    BOOL changed = ![JDXConnectivityState isEqualToDictionary:state];
    JDXConnectivityState = state.copy;
    [JDXConnectivityLock unlock];
    if (changed) JDXLog(@"network_path_changed", state);
}

void JDXConnectivityStart(void)
{
    JDXConnectivityInitialize();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JDXPathMonitor = nw_path_monitor_create();
        if (!JDXPathMonitor) {
            JDXConnectivityPublish(@{@"status": @"unavailable", @"passive": @YES,
                @"service_connectivity": @"not_tested"});
            return;
        }
        dispatch_queue_t queue = dispatch_queue_create("com.solhk.jdx.system-path", DISPATCH_QUEUE_SERIAL);
        nw_path_monitor_set_queue(JDXPathMonitor, queue);
        nw_path_monitor_set_update_handler(JDXPathMonitor, ^(nw_path_t path) {
            @autoreleasepool {
                NSString *status = @"unknown";
                switch (nw_path_get_status(path)) {
                    case nw_path_status_satisfied: status = @"satisfied"; break;
                    case nw_path_status_unsatisfied: status = @"unsatisfied"; break;
                    case nw_path_status_satisfiable: status = @"requires_connection"; break;
                    default: break;
                }
                // A usable system route does NOT establish JD service success.
                // Do not enumerate interface names, gateways, or IP addresses.
                JDXConnectivityPublish(@{
                    @"status": status, @"passive": @YES, @"service_connectivity": @"not_tested",
                    @"wifi": @(nw_path_uses_interface_type(path, nw_interface_type_wifi)),
                    @"cellular": @(nw_path_uses_interface_type(path, nw_interface_type_cellular)),
                    @"wired": @(nw_path_uses_interface_type(path, nw_interface_type_wired)),
                    @"other_interface": @(nw_path_uses_interface_type(path, nw_interface_type_other)),
                    @"expensive": @(nw_path_is_expensive(path)),
                    @"constrained": @(nw_path_is_constrained(path)),
                    @"has_dns": @(nw_path_has_dns(path)),
                    @"has_ipv4": @(nw_path_has_ipv4(path)),
                    @"has_ipv6": @(nw_path_has_ipv6(path)),
                    @"unsatisfied_reason_code": @((NSInteger)nw_path_get_unsatisfied_reason(path))
                });
            }
        });
        nw_path_monitor_start(JDXPathMonitor);
    });
}
