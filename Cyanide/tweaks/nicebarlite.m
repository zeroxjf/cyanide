//
//  nicebarlite.m
//  NiceBar Lite: status-bar text slots.
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#import "nicebarlite.h"
#import "nicebarlite_traffic_counter.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <dlfcn.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <math.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <netinet/in.h>
#import <stdio.h>
#import <string.h>
#import <sys/sysctl.h>
#import <time.h>
#import <unistd.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;

typedef struct {
    double x;
    double y;
    double width;
    double height;
} NBLRect;

typedef struct {
    double screenWidth;
    double screenHeight;
    double topAreaHeight;
} NBLLayout;

typedef struct {
    double top;
    double left;
    double bottom;
    double right;
} NBLEdgeInsets;

static const uint64_t kNBLBaseTag = 99540;
static const double kNBLFallbackScreenWidth = 390.0;
static const double kNBLWinH = 18.0;
static const double kNBLFontPt = 11.0;
static const double kNBLTopFontPt = 8.8;
// Was 999999.0/1001.0; keep it below the system status bar so scroll-to-top taps pass through.
static const double kNBLWindowLevel = 999.0;
static const double kNBLSideMargin = 20.0;
static const double kNBLTopSideMargin = 29.0;
static const double kNBLTopY = 0.0;
static const double kNBLBottomY = 38.0;
static const double kNBLDynamicIslandExtraY = 4.0;
static const double kNBLTextHPad = 6.0;
static const double kNBLMinWidth = 34.0;
static const double kNBLNetworkWidth = 91.0;
static const double kNBLCornerRadius = 6.0;
static const double kNBLPillFillAlpha = 0.92;
static const double kNBLPillBorderAlpha = 0.42;
static const uint64_t kNBLPillTagBase = 99640;

// Manually flip to true when collecting detailed NiceBar Lite timing logs.
static const bool kNBLDebugLogging = false;

static const unsigned long long kNBLSlowLogMs = 100;
static const uint64_t kNBLFullTraceTicks = 3;
static const uint64_t kNBLTrafficPersistIntervalUS = 5000000ULL;

#define NBL_DEBUG_LOG(fmt, ...) do { \
    if (kNBLDebugLogging) log_user(fmt, ##__VA_ARGS__); \
} while (0)

static uint64_t gNBLWindow = 0;
static uint64_t gNBLLabels[NiceBarLiteSlotCount] = {0};
static uint64_t gNBLSetTextSel = 0;
static uint64_t gNBLSetTextColorSel = 0;
static uint64_t gNBLPerformMainSel = 0;
static uint64_t gNBLNSStringClass = 0;
static uint64_t gNBLAllocSel = 0;
static uint64_t gNBLInitUTF8Sel = 0;
static uint64_t gNBLUIApplicationClass = 0;
static uint64_t gNBLUIWindowClass = 0;
static uint64_t gNBLUILabelClass = 0;
static uint64_t gNBLUIVisualEffectViewClass = 0;
static uint64_t gNBLUIBlurEffectClass = 0;
static uint64_t gNBLUIFontClass = 0;
static uint64_t gNBLUIColorClass = 0;
static uint64_t gNBLBlackColor = 0;
static uint64_t gNBLWhiteColor = 0;
static uint64_t gNBLTextColor = 0;
static uint64_t gNBLFillColor = 0;
static uint64_t gNBLBorderColor = 0;
static uint64_t gNBLClearColor = 0;
static uint64_t gNBLFontNormal = 0;
static uint64_t gNBLFontTop = 0;
static uint64_t gNBLApplyTick = 0;
static NSString *gNBLLastText[NiceBarLiteSlotCount] = { nil };
static double gNBLLastX[NiceBarLiteSlotCount] = {0};
static double gNBLLastY[NiceBarLiteSlotCount] = {0};
static double gNBLLastW[NiceBarLiteSlotCount] = {0};
static BOOL gNBLLastHidden[NiceBarLiteSlotCount] = {0};
static BOOL gNBLHasLastLayout[NiceBarLiteSlotCount] = {0};
static BOOL gNBLWindowVisible = NO;
static double gNBLLastWindowW = 0.0;
static double gNBLLastWindowH = 0.0;
static BOOL gNBLHasWindowFrame = NO;
static uint64_t gNBLReadTick = 0;
static double gNBLTickDownKB = 0.0;
static double gNBLTickUpKB = 0.0;
static double gNBLTickNowSeconds = 0.0;
static NBLTrafficCounterState gNBLTodayTrafficState = {0};
static BOOL gNBLTrafficPersistenceLoaded = NO;
static NSString *gNBLTrafficDateKey = nil;
static uint64_t gNBLTrafficLastPersistedBytes = 0;
static uint64_t gNBLTrafficLastPersistUS = 0;

static void *g_iokit = NULL;
static CFMutableDictionaryRef (*pIOServiceMatching)(const char *) = NULL;
static io_service_t (*pIOServiceGetMatchingService)(mach_port_t, CFDictionaryRef) = NULL;
static CFTypeRef (*pIORegistryEntryCreateCFProperty)(io_service_t, CFStringRef, CFAllocatorRef, uint32_t) = NULL;
static kern_return_t (*pIOObjectRelease)(io_object_t) = NULL;

static bool nbl_should_log_tick(void)
{
    return gNBLApplyTick == 1;
}

static bool nbl_should_trace_apply(void)
{
    return gNBLApplyTick > 0 && gNBLApplyTick <= kNBLFullTraceTicks;
}

static uint64_t nbl_now_us(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ((uint64_t)ts.tv_sec * 1000000ULL) + ((uint64_t)ts.tv_nsec / 1000ULL);
}

static unsigned long long nbl_elapsed_ms_since(uint64_t startUs)
{
    if (startUs == 0) return 0;
    uint64_t nowUs = nbl_now_us();
    if (nowUs <= startUs) return 0;
    return (unsigned long long)((nowUs - startUs + 500ULL) / 1000ULL);
}

static const char *nbl_slot_name(int slot)
{
    switch (slot) {
        case NiceBarLiteSlotTopLeft: return "top-left";
        case NiceBarLiteSlotTopRight: return "top-right";
        case NiceBarLiteSlotBottomLeft: return "bottom-left";
        case NiceBarLiteSlotBottomRight: return "bottom-right";
        case NiceBarLiteSlotBottomCenter: return "center";
        default: return "unknown";
    }
}

static const char *nbl_kind_name(int kind)
{
    switch (kind) {
        case NiceBarLiteContentOff: return "off";
        case NiceBarLiteContentCustomText: return "custom";
        case NiceBarLiteContentSystem: return "system";
        case NiceBarLiteContentTimeFormat: return "time";
        case NiceBarLiteContentWeather: return "weather";
        default: return "unknown";
    }
}

static const char *nbl_system_item_name(int item)
{
    switch (item) {
        case NiceBarLiteSystemBatteryTemp: return "battery-temp";
        case NiceBarLiteSystemFreeRAM: return "free-ram";
        case NiceBarLiteSystemBatteryPercent: return "battery-percent";
        case NiceBarLiteSystemNetworkSpeed: return "network-speed";
        case NiceBarLiteSystemUptime: return "uptime";
        case NiceBarLiteSystemDate: return "date";
        case NiceBarLiteSystemLunarDate: return "lunar-date";
        case NiceBarLiteSystemTodayTraffic: return "today-traffic";
        case NiceBarLiteSystemCurrentIP: return "current-ip";
        case NiceBarLiteSystemFreeDisk: return "free-disk";
        case NiceBarLiteSystemThermalState: return "thermal-state";
        default: return "unknown";
    }
}

static bool nbl_ensure_iokit_symbols(void)
{
    if (!g_iokit) {
        g_iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_GLOBAL);
        if (!g_iokit) return false;
        pIOServiceMatching               = dlsym(g_iokit, "IOServiceMatching");
        pIOServiceGetMatchingService     = dlsym(g_iokit, "IOServiceGetMatchingService");
        pIORegistryEntryCreateCFProperty = dlsym(g_iokit, "IORegistryEntryCreateCFProperty");
        pIOObjectRelease                 = dlsym(g_iokit, "IOObjectRelease");
    }
    return pIOServiceMatching && pIOServiceGetMatchingService &&
           pIORegistryEntryCreateCFProperty && pIOObjectRelease;
}

static double nbl_read_battery_temp_c_local(void)
{
    if (!nbl_ensure_iokit_symbols()) return -1.0;
    io_service_t svc = pIOServiceGetMatchingService(MACH_PORT_NULL,
                                                    pIOServiceMatching("AppleSmartBattery"));
    if (svc == MACH_PORT_NULL) return -1.0;

    double tempC = -1.0;
    CFNumberRef prop = (CFNumberRef)pIORegistryEntryCreateCFProperty(svc,
                                                                     CFSTR("Temperature"),
                                                                     kCFAllocatorDefault, 0);
    if (prop) {
        int64_t raw = 0;
        if (CFNumberGetValue(prop, kCFNumberSInt64Type, &raw)) {
            tempC = (double)raw / 100.0;
        }
        CFRelease(prop);
    }
    pIOObjectRelease(svc);
    return tempC;
}

static bool nbl_ensure_remote_iokit_loaded(void)
{
    if (!nbl_ensure_iokit_symbols()) return false;
    static bool remoteLoaded = false;
    if (remoteLoaded) return true;

    uint64_t path = r_alloc_str("/System/Library/Frameworks/IOKit.framework/IOKit");
    if (!path) return false;
    uint64_t handle = r_dlsym_call(R_TIMEOUT, "dlopen", path, RTLD_LAZY | RTLD_GLOBAL, 0, 0, 0, 0, 0, 0);
    r_free(path);
    remoteLoaded = (handle != 0);
    return remoteLoaded;
}

static double nbl_read_battery_temp_c_remote(void)
{
    if (!nbl_ensure_remote_iokit_loaded()) return -1.0;

    uint64_t name = r_alloc_str("AppleSmartBattery");
    if (!name) return -1.0;
    uint64_t dict = do_remote_call_stable_addr(R_TIMEOUT, (uint64_t)pIOServiceMatching, "IOServiceMatching",
                                               name, 0, 0, 0, 0, 0, 0, 0);
    r_free(name);
    if (!dict) return -1.0;

    uint64_t svc = do_remote_call_stable_addr(R_TIMEOUT, (uint64_t)pIOServiceGetMatchingService,
                                              "IOServiceGetMatchingService",
                                              MACH_PORT_NULL, dict, 0, 0, 0, 0, 0, 0);
    if (!svc) return -1.0;

    double tempC = -1.0;
    uint64_t key = r_cfstr("Temperature");
    if (key) {
        uint64_t prop = do_remote_call_stable_addr(R_TIMEOUT, (uint64_t)pIORegistryEntryCreateCFProperty,
                                                   "IORegistryEntryCreateCFProperty",
                                                   svc, key, 0, 0, 0, 0, 0, 0);
        if (prop) {
            uint64_t scratch = r_dlsym_call(R_TIMEOUT, "malloc", 8, 0, 0, 0, 0, 0, 0, 0);
            if (scratch) {
                remote_write64(scratch, 0);
                uint64_t ok = r_dlsym_call(R_TIMEOUT, "CFNumberGetValue", prop, 4, scratch, 0, 0, 0, 0, 0);
                if (ok) {
                    int64_t raw = (int64_t)remote_read64(scratch);
                    tempC = (double)raw / 100.0;
                }
                r_free(scratch);
            }
            r_dlsym_call(R_TIMEOUT, "CFRelease", prop, 0, 0, 0, 0, 0, 0, 0);
        }
        r_dlsym_call(R_TIMEOUT, "CFRelease", key, 0, 0, 0, 0, 0, 0, 0);
    }

    do_remote_call_stable_addr(R_TIMEOUT, (uint64_t)pIOObjectRelease, "IOObjectRelease",
                               svc, 0, 0, 0, 0, 0, 0, 0);
    return tempC;
}

static double nbl_read_battery_temp_c(void)
{
    uint64_t startUs = nbl_now_us();
    uint64_t localStartUs = nbl_now_us();
    static double cachedTempC = -1.0;
    static time_t lastRemoteRead = 0;

    double localTempC = nbl_read_battery_temp_c_local();
    unsigned long long localMs = nbl_elapsed_ms_since(localStartUs);
    if (localTempC > 0.0) {
        cachedTempC = localTempC;
        unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
        if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][TEMP] source=local value=%.1fC local=%llums total=%llums\n",
                     cachedTempC, localMs, totalMs);
        }
        return cachedTempC;
    }

    time_t now = time(NULL);
    if (lastRemoteRead != 0 && now >= lastRemoteRead && (now - lastRemoteRead) < 60) {
        unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
        if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][TEMP] source=cache value=%.1fC local=%llums total=%llums\n",
                     cachedTempC, localMs, totalMs);
        }
        return cachedTempC;
    }

    lastRemoteRead = now;
    uint64_t remoteStartUs = nbl_now_us();
    double remoteTempC = nbl_read_battery_temp_c_remote();
    unsigned long long remoteMs = nbl_elapsed_ms_since(remoteStartUs);
    if (remoteTempC > 0.0) cachedTempC = remoteTempC;
    unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
    if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][TEMP] source=%s value=%.1fC local=%llums remote=%llums total=%llums\n",
                 remoteTempC > 0.0 ? "remote" : "unavailable",
                 cachedTempC, localMs, remoteMs, totalMs);
    }
    return cachedTempC;
}

static double nbl_read_free_ram_gb(void)
{
    mach_port_t host = mach_host_self();
    vm_statistics64_data_t stat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&stat, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (kr != KERN_SUCCESS) return -1.0;
    uint64_t bytes = (uint64_t)stat.free_count * (uint64_t)vm_kernel_page_size;
    return (double)bytes / (1024.0 * 1024.0 * 1024.0);
}

static int nbl_read_battery_percent(void)
{
    UIDevice *dev = UIDevice.currentDevice;
    dev.batteryMonitoringEnabled = YES;
    float level = dev.batteryLevel;
    if (level < 0.0f) return -1;
    return (int)llroundf(level * 100.0f);
}

static int nbl_read_uptime_minutes(void)
{
    struct timeval boot;
    size_t len = sizeof(boot);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boot, &len, NULL, 0) != 0) return -1;
    time_t now = time(NULL);
    if (now <= boot.tv_sec) return -1;
    return (int)((now - boot.tv_sec) / 60);
}

static bool nbl_read_net_totals(uint64_t *ibytes, uint64_t *obytes)
{
    if (!ibytes || !obytes) return false;
    *ibytes = 0;
    *obytes = 0;

    struct ifaddrs *head = NULL;
    if (getifaddrs(&head) != 0) return false;
    for (struct ifaddrs *ifa = head; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_data || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != AF_LINK) continue;
        if ((ifa->ifa_flags & IFF_LOOPBACK) != 0) continue;
        if (strncmp(ifa->ifa_name, "lo", 2) == 0) continue;
        const struct if_data *data = (const struct if_data *)ifa->ifa_data;
        *ibytes += (uint64_t)data->ifi_ibytes;
        *obytes += (uint64_t)data->ifi_obytes;
    }
    freeifaddrs(head);
    return true;
}

static double nbl_now_seconds(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0.0;
    return (double)ts.tv_sec + ((double)ts.tv_nsec / 1000000000.0);
}

static void nbl_prepare_tick_metrics(void)
{
    if (gNBLReadTick == gNBLApplyTick) return;
    gNBLReadTick = gNBLApplyTick;
    gNBLTickDownKB = 0.0;
    gNBLTickUpKB = 0.0;
    gNBLTickNowSeconds = nbl_now_seconds();
    if (gNBLTickNowSeconds <= 0.0) return;

    static bool havePrev = false;
    static uint64_t prevIn = 0;
    static uint64_t prevOut = 0;
    static double prevTime = 0.0;

    uint64_t totalIn = 0;
    uint64_t totalOut = 0;
    if (!nbl_read_net_totals(&totalIn, &totalOut)) return;
    if (havePrev && gNBLTickNowSeconds > prevTime) {
        double dt = gNBLTickNowSeconds - prevTime;
        gNBLTickDownKB = ((double)((totalIn >= prevIn) ? totalIn - prevIn : 0) / dt) / 1024.0;
        gNBLTickUpKB = ((double)((totalOut >= prevOut) ? totalOut - prevOut : 0) / dt) / 1024.0;
    }
    prevIn = totalIn;
    prevOut = totalOut;
    prevTime = gNBLTickNowSeconds;
    havePrev = true;
}

static NSString *nbl_format_speed(double kbValue)
{
    if (!isfinite(kbValue) || kbValue < 0.0) kbValue = 0.0;
    if (kbValue < 999.5) return [NSString stringWithFormat:@"%lldK", (long long)llround(kbValue)];
    double mbValue = kbValue / 1024.0;
    if (mbValue < 10.0) return [NSString stringWithFormat:@"%.1fM", mbValue];
    return [NSString stringWithFormat:@"%.0fM", mbValue];
}

NSString *nicebarlite_format_traffic_bytes(uint64_t bytes)
{
    double value = (double)bytes;
    if (value < 1024.0) return [NSString stringWithFormat:@"%lluB", (unsigned long long)bytes];
    value /= 1024.0;
    if (value < 1024.0) return [NSString stringWithFormat:@"%.0fK", value];
    value /= 1024.0;
    if (value < 1024.0) return [NSString stringWithFormat:@"%.1fM", value];
    value /= 1024.0;
    return [NSString stringWithFormat:@"%.2fG", value];
}

static NSString *nbl_format_disk_bytes(uint64_t bytes)
{
    double value = (double)bytes;
    if (value < 1000.0) return [NSString stringWithFormat:@"%lluB", (unsigned long long)bytes];
    value /= 1000.0;
    if (value < 1000.0) return [NSString stringWithFormat:@"%.0fK", value];
    value /= 1000.0;
    if (value < 1000.0) return [NSString stringWithFormat:@"%.1fM", value];
    value /= 1000.0;
    if (value < 100.0) return [NSString stringWithFormat:@"%.1fG", value];
    return [NSString stringWithFormat:@"%.0fG", value];
}

static NSString *nbl_traffic_date_key_for_date(NSDate *date)
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = @"yyyyMMdd";
    return [formatter stringFromDate:date ?: NSDate.date];
}

NSString *nicebarlite_traffic_store_path(void)
{
    NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask,
                                                                    YES);
    NSString *base = dirs.firstObject ?: NSTemporaryDirectory();
    return [[base stringByAppendingPathComponent:@"data"]
            stringByAppendingPathComponent:@"NiceBarLiteTraffic.json"];
}

static NSMutableDictionary<NSString *, NSString *> *nbl_read_traffic_history_mutable(void)
{
    NSString *path = nicebarlite_traffic_store_path();
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) return [NSMutableDictionary dictionary];

    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![obj isKindOfClass:NSDictionary.class]) {
        if (error) {
            NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] history read failed: %s\n",
                          error.localizedDescription.UTF8String ?: "unknown");
        }
        return [NSMutableDictionary dictionary];
    }

    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        (void)stop;
        if (![key isKindOfClass:NSString.class]) return;
        if ([value isKindOfClass:NSString.class]) {
            out[key] = value;
        } else if ([value respondsToSelector:@selector(unsignedLongLongValue)]) {
            out[key] = [NSString stringWithFormat:@"%llu", [value unsignedLongLongValue]];
        }
    }];
    return out;
}

NSDictionary<NSString *, NSString *> *nicebarlite_traffic_history_snapshot(void)
{
    return [nbl_read_traffic_history_mutable() copy];
}

static uint64_t nbl_traffic_bytes_from_value(id value)
{
    if ([value isKindOfClass:NSString.class]) return (uint64_t)[(NSString *)value longLongValue];
    if ([value respondsToSelector:@selector(unsignedLongLongValue)]) return (uint64_t)[value unsignedLongLongValue];
    return 0;
}

static BOOL nbl_write_traffic_history(NSDictionary<NSString *, NSString *> *history)
{
    NSString *path = nicebarlite_traffic_store_path();
    NSString *dir = path.stringByDeletingLastPathComponent;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] history mkdir failed: %s\n",
                      error.localizedDescription.UTF8String ?: "unknown");
        return NO;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:history
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&error];
    if (!data) {
        NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] history encode failed: %s\n",
                      error.localizedDescription.UTF8String ?: "unknown");
        return NO;
    }
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!ok) {
        NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] history write failed: %s\n",
                      error.localizedDescription.UTF8String ?: "unknown");
    }
    return ok;
}

static void nbl_persist_traffic_bytes(NSString *dateKey, uint64_t bytes, BOOL force)
{
    if (dateKey.length == 0) return;
    uint64_t nowUS = nbl_now_us();
    if (!force && bytes == gNBLTrafficLastPersistedBytes) return;
    if (!force &&
        nowUS >= gNBLTrafficLastPersistUS &&
        nowUS - gNBLTrafficLastPersistUS < kNBLTrafficPersistIntervalUS) {
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *history = nbl_read_traffic_history_mutable();
    history[dateKey] = [NSString stringWithFormat:@"%llu", (unsigned long long)bytes];
    if (nbl_write_traffic_history(history)) {
        gNBLTrafficLastPersistedBytes = bytes;
        gNBLTrafficLastPersistUS = nowUS;
        NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] persisted date=%s bytes=%llu force=%d\n",
                      dateKey.UTF8String ?: "",
                      (unsigned long long)bytes,
                      force ? 1 : 0);
    }
}

static void nbl_ensure_today_traffic_persistence_loaded(void)
{
    NSString *todayKey = nbl_traffic_date_key_for_date(NSDate.date);
    if (gNBLTrafficPersistenceLoaded && [gNBLTrafficDateKey isEqualToString:todayKey]) return;

    if (gNBLTrafficPersistenceLoaded && gNBLTrafficDateKey.length > 0) {
        uint64_t current = 0;
        if (nbl_traffic_counter_value(&gNBLTodayTrafficState, &current)) {
            nbl_persist_traffic_bytes(gNBLTrafficDateKey, current, YES);
        }
    }

    NSDictionary<NSString *, NSString *> *history = nicebarlite_traffic_history_snapshot();
    uint64_t saved = nbl_traffic_bytes_from_value(history[todayKey]);
    nbl_traffic_counter_reset(&gNBLTodayTrafficState);
    nbl_traffic_counter_seed_accumulated(&gNBLTodayTrafficState, saved);
    gNBLTrafficPersistenceLoaded = YES;
    gNBLTrafficDateKey = [todayKey copy];
    gNBLTrafficLastPersistedBytes = saved;
    gNBLTrafficLastPersistUS = 0;
    NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] loaded date=%s saved=%llu path=%s\n",
                  todayKey.UTF8String ?: "",
                  (unsigned long long)saved,
                  nicebarlite_traffic_store_path().UTF8String ?: "");
}

static NSString *nbl_today_traffic_text(void)
{
    uint64_t startUs = nbl_now_us();
    nbl_ensure_today_traffic_persistence_loaded();

    uint64_t totalIn = 0;
    uint64_t totalOut = 0;
    if (!nbl_read_net_totals(&totalIn, &totalOut)) {
        uint64_t cached = 0;
        if (nbl_traffic_counter_value(&gNBLTodayTrafficState, &cached)) {
            unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
            if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
                NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] source=getifaddrs-failed cached=%llu total=%llums\n",
                              (unsigned long long)cached,
                              totalMs);
            }
            return [NSString stringWithFormat:@"T %@", nicebarlite_format_traffic_bytes(cached)];
        }

        unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
        if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] source=getifaddrs-failed total=%llums\n", totalMs);
        }
        return @"T --";
    }

    uint64_t trafficBytes = 0;
    NBLTrafficCounterEvent event = nbl_traffic_counter_sample(&gNBLTodayTrafficState,
                                                              totalIn,
                                                              totalOut,
                                                              &trafficBytes);
    nbl_persist_traffic_bytes(gNBLTrafficDateKey, trafficBytes, NO);
    NSString *text = [NSString stringWithFormat:@"T %@", nicebarlite_format_traffic_bytes(trafficBytes)];
    unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
    if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][TRAFFIC] event=%d bytes=%llu in=%llu out=%llu total=%llums\n",
                      (int)event,
                      (unsigned long long)trafficBytes,
                      (unsigned long long)totalIn,
                      (unsigned long long)totalOut,
                      totalMs);
    }
    return text;
}

static NSString *nbl_current_ip_text(void)
{
    uint64_t startUs = nbl_now_us();
    struct ifaddrs *head = NULL;
    if (getifaddrs(&head) != 0) {
        unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
        if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][IP] source=getifaddrs-failed total=%llums\n", totalMs);
        }
        return @"IP --";
    }

    NSString *wifiIP = nil;
    NSString *fallbackIP = nil;
    char addr[INET_ADDRSTRLEN] = {0};

    for (struct ifaddrs *ifa = head; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != AF_INET) continue;
        if ((ifa->ifa_flags & IFF_LOOPBACK) != 0) continue;

        struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
        if (!inet_ntop(AF_INET, &sin->sin_addr, addr, sizeof(addr))) continue;
        NSString *ip = [NSString stringWithUTF8String:addr];
        if (!ip.length) continue;

        if (strcmp(ifa->ifa_name, "en0") == 0) {
            wifiIP = ip;
            break;
        }
        if (!fallbackIP) fallbackIP = ip;
    }

    freeifaddrs(head);
    NSString *ip = wifiIP ?: fallbackIP;
    NSString *text = ip.length ? [NSString stringWithFormat:@"IP %@", ip] : @"IP --";
    unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
    if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][IP] source=%s resultLen=%lu total=%llums\n",
                 wifiIP.length ? "wifi" : (fallbackIP.length ? "fallback" : "none"),
                 (unsigned long)text.length,
                 totalMs);
    }
    return text;
}

static NSString *nbl_free_disk_text(void)
{
    uint64_t startUs = nbl_now_us();
    NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
    NSNumber *available = nil;
    uint64_t importantStartUs = nbl_now_us();
    if ([homeURL getResourceValue:&available
                            forKey:NSURLVolumeAvailableCapacityForImportantUsageKey
                             error:nil] && available) {
        unsigned long long importantMs = nbl_elapsed_ms_since(importantStartUs);
        NSString *text = [NSString stringWithFormat:@"Disk %@", nbl_format_disk_bytes(available.unsignedLongLongValue)];
        unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
        if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][DISK] source=important bytes=%llu important=%llums total=%llums\n",
                     available.unsignedLongLongValue,
                     importantMs,
                     totalMs);
        }
        return text;
    }
    unsigned long long importantMs = nbl_elapsed_ms_since(importantStartUs);

    uint64_t capacityStartUs = nbl_now_us();
    if ([homeURL getResourceValue:&available
                            forKey:NSURLVolumeAvailableCapacityKey
                             error:nil] && available) {
        unsigned long long capacityMs = nbl_elapsed_ms_since(capacityStartUs);
        NSString *text = [NSString stringWithFormat:@"Disk %@", nbl_format_disk_bytes(available.unsignedLongLongValue)];
        unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
        if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][DISK] source=available bytes=%llu important=%llums available=%llums total=%llums\n",
                     available.unsignedLongLongValue,
                     importantMs,
                     capacityMs,
                     totalMs);
        }
        return text;
    }
    unsigned long long capacityMs = nbl_elapsed_ms_since(capacityStartUs);

    NSError *error = nil;
    uint64_t fsStartUs = nbl_now_us();
    NSDictionary<NSFileAttributeKey, id> *attrs =
        [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory()
                                                                error:&error];
    unsigned long long fsMs = nbl_elapsed_ms_since(fsStartUs);
    NSNumber *freeBytes = attrs[NSFileSystemFreeSize];
    unsigned long long totalMs = nbl_elapsed_ms_since(startUs);
    if (!freeBytes || error) {
        if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][DISK] source=failed important=%llums available=%llums fs=%llums total=%llums error=%s\n",
                     importantMs,
                     capacityMs,
                     fsMs,
                     totalMs,
                     error.localizedDescription.UTF8String ?: "none");
        }
        return @"Disk --";
    }
    NSString *text = [NSString stringWithFormat:@"Disk %@", nbl_format_disk_bytes(freeBytes.unsignedLongLongValue)];
    if (nbl_should_trace_apply() || totalMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][DISK] source=filesystem bytes=%llu important=%llums available=%llums fs=%llums total=%llums\n",
                 freeBytes.unsignedLongLongValue,
                 importantMs,
                 capacityMs,
                 fsMs,
                 totalMs);
    }
    return text;
}

static NSString *nbl_thermal_state_text(const char *language)
{
    BOOL chinese = language && strcmp(language, "zh") == 0;
    NSProcessInfoThermalState state = NSProcessInfo.processInfo.thermalState;
    switch (state) {
        case NSProcessInfoThermalStateNominal:
            return chinese ? @"❄️ 凉爽" : @"❄️ Cool";
        case NSProcessInfoThermalStateFair:
            return chinese ? @"🌡️ 温热" : @"🌡️ Warm";
        case NSProcessInfoThermalStateSerious:
            return chinese ? @"🔥 偏热" : @"🔥 Hot";
        case NSProcessInfoThermalStateCritical:
            return chinese ? @"🚨 过热" : @"🚨 Critical";
        default:
            return chinese ? @"🌡️ --" : @"🌡️ --";
    }
}

static NSString *nbl_lunar_date_text(void);
static NSString *nbl_lunar_date_text_cn(bool full);

static bool nbl_date_format_uses_chinese_locale(NSString *format)
{
    return [format isEqualToString:@"a h:mm"] ||
           [format rangeOfString:@"月"].location != NSNotFound;
}

static NSString *nbl_chinese_weekday_text(void)
{
    NSInteger weekday = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:[NSDate date]];
    NSArray<NSString *> *weekdays = @[@"", @"星期日", @"星期一", @"星期二", @"星期三", @"星期四", @"星期五", @"星期六"];
    if (weekday < 1 || weekday >= (NSInteger)weekdays.count) return @"星期-";
    return weekdays[(NSUInteger)weekday];
}

static NSString *nbl_date_with_format(NSString *format)
{
    if (format.length == 0) format = @"HH:mm";
    if ([format isEqualToString:@"cyanide:lunar"]) return nbl_lunar_date_text();
    if ([format isEqualToString:@"cyanide:lunar-cn"]) return nbl_lunar_date_text_cn(false);
    if ([format isEqualToString:@"cyanide:lunar-cn-full"]) return nbl_lunar_date_text_cn(true);
    if ([format isEqualToString:@"cyanide:cn-date-weekday"] || [format isEqualToString:@"M月d日 EEE"]) {
        return [NSString stringWithFormat:@"%@ %@", nbl_date_with_format(@"M月d日"), nbl_chinese_weekday_text()];
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = nbl_date_format_uses_chinese_locale(format)
        ? [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"]
        : [NSLocale currentLocale];
    formatter.dateFormat = format;
    NSString *text = [formatter stringFromDate:[NSDate date]];
    return text.length ? text : @"--";
}

static NSString *nbl_lunar_date_text(void)
{
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *c = [cal components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    if (c.month <= 0 || c.day <= 0) return @"Lunar --";
    return [NSString stringWithFormat:@"L%02ld/%02ld", (long)c.month, (long)c.day];
}

static NSString *nbl_lunar_date_text_cn(bool full)
{
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *c = [cal components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    if (c.month <= 0 || c.day <= 0) return @"农历--";
    NSArray<NSString *> *months = @[
        @"正月", @"二月", @"三月", @"四月", @"五月", @"六月",
        @"七月", @"八月", @"九月", @"十月", @"冬月", @"腊月",
    ];
    NSArray<NSString *> *days = @[
        @"初一", @"初二", @"初三", @"初四", @"初五", @"初六", @"初七", @"初八", @"初九", @"初十",
        @"十一", @"十二", @"十三", @"十四", @"十五", @"十六", @"十七", @"十八", @"十九", @"二十",
        @"廿一", @"廿二", @"廿三", @"廿四", @"廿五", @"廿六", @"廿七", @"廿八", @"廿九", @"三十",
    ];
    NSString *month = (c.month >= 1 && c.month <= (NSInteger)months.count) ? months[(NSUInteger)c.month - 1] : @"";
    NSString *day = (c.day >= 1 && c.day <= (NSInteger)days.count) ? days[(NSUInteger)c.day - 1] : @"";
    if (!month.length || !day.length) return @"农历--";
    return full ? [NSString stringWithFormat:@"农历%@%@", month, day]
                : [NSString stringWithFormat:@"%@%@", month, day];
}

static NSString *nbl_system_text(int item, bool celsius, const char *language)
{
    switch (item) {
        case NiceBarLiteSystemBatteryTemp: {
            double tempC = nbl_read_battery_temp_c();
            if (tempC <= 0.0) return @"--";
            double v = celsius ? tempC : (tempC * 9.0 / 5.0 + 32.0);
            return [NSString stringWithFormat:@"%.1f%c", v, celsius ? 'C' : 'F'];
        }
        case NiceBarLiteSystemFreeRAM: {
            double ram = nbl_read_free_ram_gb();
            if (ram <= 0.0) return @"--";
            if (ram < 1.0) return [NSString stringWithFormat:@"%.0fMB", ram * 1024.0];
            return [NSString stringWithFormat:@"%.2fGB", ram];
        }
        case NiceBarLiteSystemBatteryPercent: {
            int pct = nbl_read_battery_percent();
            return pct >= 0 ? [NSString stringWithFormat:@"%d%%", pct] : @"--";
        }
        case NiceBarLiteSystemNetworkSpeed: {
            double down = gNBLTickDownKB;
            double up = gNBLTickUpKB;
            return [NSString stringWithFormat:@"↓%@↑%@", nbl_format_speed(down), nbl_format_speed(up)];
        }
        case NiceBarLiteSystemUptime: {
            int minutes = nbl_read_uptime_minutes();
            if (minutes < 0) return @"--";
            int hours = minutes / 60;
            int mins = minutes % 60;
            if (hours >= 24) return [NSString stringWithFormat:@"%dd%dh", hours / 24, hours % 24];
            return [NSString stringWithFormat:@"%dh%02dm", hours, mins];
        }
        case NiceBarLiteSystemDate:
            return nbl_date_with_format(@"M/d");
        case NiceBarLiteSystemLunarDate:
            return nbl_lunar_date_text();
        case NiceBarLiteSystemTodayTraffic:
            return nbl_today_traffic_text();
        case NiceBarLiteSystemCurrentIP:
            return nbl_current_ip_text();
        case NiceBarLiteSystemFreeDisk:
            return nbl_free_disk_text();
        case NiceBarLiteSystemThermalState:
            return nbl_thermal_state_text(language);
        default:
            return @"--";
    }
}

static NSString *nbl_text_for_slot(NiceBarLiteSlotConfig slot, bool celsius)
{
    switch (slot.kind) {
        case NiceBarLiteContentCustomText:
            return slot.customText && slot.customText[0] ? @(slot.customText) : @"Text";
        case NiceBarLiteContentSystem:
            return nbl_system_text(slot.systemItem, celsius, slot.systemLanguage);
        case NiceBarLiteContentTimeFormat:
            return nbl_date_with_format(slot.timeFormat && slot.timeFormat[0] ? @(slot.timeFormat) : @"HH:mm");
        case NiceBarLiteContentWeather:
            return slot.weatherText && slot.weatherText[0] ? @(slot.weatherText) : @"Weather --";
        case NiceBarLiteContentOff:
        default:
            return @"";
    }
}

static bool nbl_valid_screen_length(double v)
{
    return isfinite(v) && v >= 100.0 && v <= 2000.0;
}

static bool nbl_valid_top_area(double v)
{
    return isfinite(v) && v >= 8.0 && v <= 140.0;
}

static double nbl_fallback_top_area(double screenWidth, double screenHeight)
{
    double shortSide = fmin(screenWidth, screenHeight);
    double longSide = fmax(screenWidth, screenHeight);
    if (!nbl_valid_screen_length(shortSide) || !nbl_valid_screen_length(longSide)) return 20.0;
    if (longSide >= 852.0 && shortSide >= 390.0) return 59.0;
    if (longSide >= 844.0 && shortSide >= 390.0) return 47.0;
    if (longSide >= 812.0 && shortSide >= 375.0) return 44.0;
    return 20.0;
}

static uint64_t nbl_remote_key_window(void)
{
    if (!r_is_objc_ptr(gNBLUIApplicationClass)) gNBLUIApplicationClass = r_class("UIApplication");
    if (!r_is_objc_ptr(gNBLUIApplicationClass)) return 0;
    uint64_t app = r_msg2_main(gNBLUIApplicationClass, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;

    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    if (r_is_objc_ptr(keyWin)) return keyWin;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    if (count > 0 && count < 64) return r_msg2_main(windows, "objectAtIndex:", 0, 0, 0, 0);
    return 0;
}

static double nbl_remote_safe_area_top(void)
{
    uint64_t keyWin = nbl_remote_key_window();
    if (!r_is_objc_ptr(keyWin)) return 0.0;

    NBLEdgeInsets insets = {0};
    bool ok = r_msg2_main_struct_ret(keyWin, "safeAreaInsets",
                                     &insets, sizeof(insets),
                                     NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    if (!ok || !nbl_valid_top_area(insets.top)) return 0.0;
    return insets.top;
}

static NBLLayout nbl_read_layout(void)
{
    NBLLayout m = { kNBLFallbackScreenWidth, 844.0, 47.0 };
    CGRect b = UIScreen.mainScreen.bounds;
    if (nbl_valid_screen_length(b.size.width)) m.screenWidth = b.size.width;
    if (nbl_valid_screen_length(b.size.height)) m.screenHeight = b.size.height;
    m.topAreaHeight = nbl_remote_safe_area_top();
    if (!nbl_valid_top_area(m.topAreaHeight)) {
        m.topAreaHeight = nbl_fallback_top_area(m.screenWidth, m.screenHeight);
    }
    return m;
}

static double nbl_top_row_y(double topAreaHeight, NiceBarLiteConfig config)
{
    (void)topAreaHeight;
    return kNBLTopY + config.topYOffset;
}

static double nbl_bottom_row_y(double topAreaHeight, NiceBarLiteConfig config)
{
    if (!nbl_valid_top_area(topAreaHeight)) return kNBLBottomY + config.bottomYOffset;
    double y = topAreaHeight - (kNBLWinH / 2.0);
    if (topAreaHeight >= 55.0) y += kNBLDynamicIslandExtraY;
    return fmax(kNBLBottomY, floor(y)) + config.bottomYOffset;
}

static bool nbl_send_double_main(uint64_t obj, const char *selName, double value)
{
    if (!r_is_objc_ptr(obj)) return false;
    r_msg2_main_raw(obj, selName,
                    &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
    return true;
}

static bool nbl_send_rect_main(uint64_t obj, const char *selName,
                               double x, double y, double width, double height)
{
    if (!r_is_objc_ptr(obj)) return false;
    NBLRect rect = { x, y, width, height };
    r_msg2_main_raw(obj, selName,
                    &rect, sizeof(rect),
                    NULL, 0, NULL, 0, NULL, 0);
    return true;
}

static void nbl_make_window_click_through(uint64_t win)
{
    if (!r_is_objc_ptr(win)) return;
    r_msg2_main(win, "setUserInteractionEnabled:", 0, 0, 0, 0);
}

static void nbl_purge_legacy_window_views(void)
{
    if (!r_is_objc_ptr(gNBLWindow)) return;
    uint64_t subviews = r_msg2_main(gNBLWindow, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count == 0 || count > 128) return;

    for (uint64_t idx = count; idx > 0; idx--) {
        uint64_t child = r_msg2_main(subviews, "objectAtIndex:", idx - 1, 0, 0, 0);
        if (!r_is_objc_ptr(child)) continue;
        uint64_t tag = r_msg2_main(child, "tag", 0, 0, 0, 0);
        BOOL isLegacyLabel = tag >= kNBLBaseTag && tag < kNBLBaseTag + NiceBarLiteSlotCount;
        BOOL isLegacyPill = tag >= kNBLPillTagBase && tag < kNBLPillTagBase + NiceBarLiteSlotCount;
        if (isLegacyLabel || isLegacyPill) {
            r_msg2_main(child, "setHidden:", 1, 0, 0, 0);
            r_msg2_main(child, "removeFromSuperview", 0, 0, 0, 0);
        }
    }
}

static bool nbl_create_or_fetch_window(void);
static uint64_t nbl_nsstring_utf8_fast(const char *cstr)
{
    if (!cstr) cstr = "";
    uint64_t buf = r_alloc_str(cstr);
    if (!buf) return 0;
    if (!gNBLNSStringClass) gNBLNSStringClass = r_class("NSString");
    if (!gNBLAllocSel) gNBLAllocSel = r_sel("alloc");
    if (!gNBLInitUTF8Sel) gNBLInitUTF8Sel = r_sel("initWithUTF8String:");
    if (!r_is_objc_ptr(gNBLNSStringClass) || !gNBLAllocSel || !gNBLInitUTF8Sel) {
        r_free(buf);
        return 0;
    }
    uint64_t allocated = r_msg(gNBLNSStringClass, gNBLAllocSel, 0, 0, 0, 0);
    uint64_t ns = r_is_objc_ptr(allocated) ? r_msg(allocated, gNBLInitUTF8Sel, buf, 0, 0, 0) : 0;
    r_free(buf);
    return ns;
}

static void nbl_release_remote_obj(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return;
    r_dlsym_call(R_TIMEOUT, "CFRelease", obj, 0, 0, 0, 0, 0, 0, 0);
}

static bool nbl_set_text_fast(uint64_t label, uint64_t textObj)
{
    if (!r_is_objc_ptr(label) || !r_is_objc_ptr(textObj)) return false;
    if (!gNBLSetTextSel) gNBLSetTextSel = r_sel("setText:");
    if (!gNBLSetTextSel) return false;
    r_msg2_main(label, "setText:", textObj, 0, 0, 0);
    return true;
}

static uint64_t nbl_status_text_color(void)
{
    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (!r_is_objc_ptr(gNBLUIColorClass)) return 0;
    if (!r_is_objc_ptr(gNBLTextColor)) {
        double white = 1.0;
        double alpha = 0.96;
        gNBLTextColor = r_msg2_main_raw(gNBLUIColorClass, "colorWithWhite:alpha:",
                                        &white, sizeof(white),
                                        &alpha, sizeof(alpha),
                                        NULL, 0, NULL, 0);
    }
    if (r_is_objc_ptr(gNBLTextColor)) return gNBLTextColor;
    if (!r_is_objc_ptr(gNBLWhiteColor)) {
        gNBLWhiteColor = r_msg2_main(gNBLUIColorClass, "whiteColor", 0, 0, 0, 0);
    }
    return gNBLWhiteColor;
}

static uint64_t nbl_pill_fill_color(void)
{
    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (!r_is_objc_ptr(gNBLUIColorClass)) return 0;
    if (!r_is_objc_ptr(gNBLFillColor)) {
        double white = 0.0;
        double alpha = kNBLPillFillAlpha;
        gNBLFillColor = r_msg2_main_raw(gNBLUIColorClass, "colorWithWhite:alpha:",
                                        &white, sizeof(white),
                                        &alpha, sizeof(alpha),
                                        NULL, 0, NULL, 0);
    }
    if (r_is_objc_ptr(gNBLFillColor)) return gNBLFillColor;
    if (!r_is_objc_ptr(gNBLBlackColor)) {
        gNBLBlackColor = r_msg2_main(gNBLUIColorClass, "blackColor", 0, 0, 0, 0);
    }
    return gNBLBlackColor;
}

static uint64_t nbl_pill_border_color(void)
{
    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (!r_is_objc_ptr(gNBLUIColorClass)) return 0;
    if (!r_is_objc_ptr(gNBLBorderColor)) {
        double white = 0.72;
        double alpha = kNBLPillBorderAlpha;
        gNBLBorderColor = r_msg2_main_raw(gNBLUIColorClass, "colorWithWhite:alpha:",
                                          &white, sizeof(white),
                                          &alpha, sizeof(alpha),
                                          NULL, 0, NULL, 0);
    }
    return gNBLBorderColor;
}

static double nbl_font_size_for_slot(NiceBarLiteSlot slot)
{
    return (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
        ? kNBLTopFontPt
        : kNBLFontPt;
}

static double nbl_side_margin_for_slot(NiceBarLiteSlot slot, NiceBarLiteConfig config)
{
    bool topSlot = slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight;
    double base = (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
        ? kNBLTopSideMargin
        : kNBLSideMargin;
    double offset = topSlot ? config.topSideInsetOffset : config.bottomSideInsetOffset;
    return fmax(2.0, base + offset);
}

static void nbl_apply_label_style(uint64_t label, NiceBarLiteSlot slot)
{
    if (!r_is_objc_ptr(label)) return;

    if (!r_is_objc_ptr(gNBLUIFontClass)) gNBLUIFontClass = r_class("UIFont");
    if (r_is_objc_ptr(gNBLUIFontClass)) {
        uint64_t *fontCache = (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
            ? &gNBLFontTop
            : &gNBLFontNormal;
        double size = nbl_font_size_for_slot(slot);
        double weight = 0.0;
        if (!r_is_objc_ptr(*fontCache)) {
            *fontCache = r_msg2_main_raw(gNBLUIFontClass, "monospacedDigitSystemFontOfSize:weight:",
                                         &size, sizeof(size),
                                         &weight, sizeof(weight),
                                         NULL, 0, NULL, 0);
            if (!r_is_objc_ptr(*fontCache)) {
                *fontCache = r_msg2_main_raw(gNBLUIFontClass, "systemFontOfSize:",
                                             &size, sizeof(size),
                                             NULL, 0, NULL, 0, NULL, 0);
            }
        }
        if (r_is_objc_ptr(*fontCache)) r_msg2_main(label, "setFont:", *fontCache, 0, 0, 0);
    }

    uint64_t color = nbl_status_text_color();
    if (r_is_objc_ptr(color)) r_msg2_main(label, "setTextColor:", color, 0, 0, 0);
    uint64_t fill = nbl_pill_fill_color();
    if (r_is_objc_ptr(fill)) r_msg2_main(label, "setBackgroundColor:", fill, 0, 0, 0);

    uint64_t layer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = kNBLCornerRadius;
        double borderWidth = 0.5;
        nbl_send_double_main(layer, "setCornerRadius:", radius);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
        nbl_send_double_main(layer, "setBorderWidth:", borderWidth);
        uint64_t borderColor = nbl_pill_border_color();
        if (r_is_objc_ptr(borderColor)) {
            uint64_t cgColor = r_msg2_main(borderColor, "CGColor", 0, 0, 0, 0);
            if (cgColor) r_msg2_main(layer, "setBorderColor:", cgColor, 0, 0, 0);
        }
    }
}

static void nbl_refresh_text_colors(void)
{
    uint64_t color = nbl_status_text_color();
    if (!r_is_objc_ptr(color)) return;
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        if (r_is_objc_ptr(gNBLLabels[i])) {
            r_msg2_main(gNBLLabels[i], "setTextColor:", color, 0, 0, 0);
        }
    }
}

static double nbl_measure_text_width(NSString *text, NiceBarLiteSlot slot)
{
    if (text.length == 0) return 0.0;
    UIFont *font = nil;
    double size = nbl_font_size_for_slot(slot);
    if (@available(iOS 9.0, *)) {
        font = [UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightRegular];
    }
    if (!font) font = [UIFont systemFontOfSize:size];
    NSDictionary *attrs = @{ NSFontAttributeName: font };
    return ceil([text sizeWithAttributes:attrs].width);
}

static BOOL nbl_slot_is_network_speed(NiceBarLiteSlotConfig slot)
{
    return slot.kind == NiceBarLiteContentSystem &&
           slot.systemItem == NiceBarLiteSystemNetworkSpeed;
}

static double nbl_width_for_text(NSString *text,
                                 NiceBarLiteSlot slot,
                                 NiceBarLiteSlotConfig config,
                                 NBLLayout layout,
                                 NiceBarLiteConfig fullConfig)
{
    if (text.length == 0) return 1.0;
    double maxWidth = slot == NiceBarLiteSlotBottomCenter
        ? (layout.screenWidth * 0.34)
        : (layout.screenWidth * 0.5) - nbl_side_margin_for_slot(slot, fullConfig) - 4.0;
    if (maxWidth < kNBLMinWidth) maxWidth = kNBLMinWidth;
    double width = nbl_slot_is_network_speed(config)
        ? kNBLNetworkWidth
        : nbl_measure_text_width(text, slot) + (kNBLTextHPad * 2.0);
    if (width < kNBLMinWidth) width = kNBLMinWidth;
    if (width > maxWidth) width = maxWidth;
    return width;
}

static NBLRect nbl_rect_for_slot(NiceBarLiteSlot slot,
                                 NiceBarLiteSlotConfig config,
                                 NSString *text,
                                 NBLLayout layout,
                                 NiceBarLiteConfig fullConfig)
{
    double width = nbl_width_for_text(text, slot, config, layout, fullConfig);
    double x = 0.0;
    double sideMargin = nbl_side_margin_for_slot(slot, fullConfig);
    double y = (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
        ? nbl_top_row_y(layout.topAreaHeight, fullConfig)
        : nbl_bottom_row_y(layout.topAreaHeight, fullConfig);

    if (slot == NiceBarLiteSlotBottomCenter) {
        x = ((layout.screenWidth - width) * 0.5) + fullConfig.centerXOffset;
    } else if (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotBottomLeft) {
        x = sideMargin;
    } else {
        x = layout.screenWidth - width - sideMargin;
    }
    return (NBLRect){ floor(x), floor(y), width, kNBLWinH };
}

static bool nbl_create_or_fetch_window(void)
{
    if (r_is_objc_ptr(gNBLWindow)) return true;

    if (!r_is_objc_ptr(gNBLUIApplicationClass)) gNBLUIApplicationClass = r_class("UIApplication");
    if (!r_is_objc_ptr(gNBLUIApplicationClass)) return false;
    uint64_t app = r_msg2_main(gNBLUIApplicationClass, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t assocKey = r_sel("cyanideNiceBarLiteWindow");
    if (!assocKey) return false;
    uint64_t cached = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                   app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(cached)) {
        gNBLWindow = cached;
        nbl_make_window_click_through(gNBLWindow);
        nbl_purge_legacy_window_views();
        return true;
    }

    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    if (!r_is_objc_ptr(keyWin)) {
        uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
        uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
        if (count > 0 && count < 64) keyWin = r_msg2_main(windows, "objectAtIndex:", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(keyWin)) return false;
    uint64_t scene = r_msg2_main(keyWin, "windowScene", 0, 0, 0, 0);
    if (!r_is_objc_ptr(scene)) return false;

    if (!r_is_objc_ptr(gNBLUIWindowClass)) gNBLUIWindowClass = r_class("UIWindow");
    if (!r_is_objc_ptr(gNBLUIWindowClass)) return false;
    uint64_t winAlloc = r_msg2_main(gNBLUIWindowClass, "alloc", 0, 0, 0, 0);
    uint64_t win = r_is_objc_ptr(winAlloc) ? r_msg2_main(winAlloc, "initWithWindowScene:", scene, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(win)) return false;

    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (r_is_objc_ptr(gNBLUIColorClass)) {
        if (!r_is_objc_ptr(gNBLClearColor)) {
            gNBLClearColor = r_msg2_main(gNBLUIColorClass, "clearColor", 0, 0, 0, 0);
        }
        if (r_is_objc_ptr(gNBLClearColor)) r_msg2_main(win, "setBackgroundColor:", gNBLClearColor, 0, 0, 0);
    }
    nbl_send_double_main(win, "setWindowLevel:", kNBLWindowLevel);
    nbl_make_window_click_through(win);

    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", app, assocKey, win, 1, 0, 0, 0, 0);
    gNBLWindow = win;
    nbl_purge_legacy_window_views();
    return true;
}

static uint64_t nbl_ensure_label(NiceBarLiteSlot slot)
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return 0;
    if (r_is_objc_ptr(gNBLLabels[slot])) return gNBLLabels[slot];
    if (!nbl_create_or_fetch_window()) return 0;

    uint64_t existing = r_msg2_main(gNBLWindow, "viewWithTag:", kNBLBaseTag + slot, 0, 0, 0);
    if (r_is_objc_ptr(existing)) {
        gNBLLabels[slot] = existing;
        gNBLHasLastLayout[slot] = NO;
        gNBLLastText[slot] = nil;
        nbl_apply_label_style(existing, slot);
        return existing;
    }

    if (!r_is_objc_ptr(gNBLUILabelClass)) gNBLUILabelClass = r_class("UILabel");
    if (!r_is_objc_ptr(gNBLUILabelClass)) return 0;
    uint64_t labelAlloc = r_msg2_main(gNBLUILabelClass, "alloc", 0, 0, 0, 0);
    uint64_t label = r_is_objc_ptr(labelAlloc) ? r_msg2_main(labelAlloc, "init", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(label)) return 0;

    r_msg2_main(label, "setTag:", kNBLBaseTag + slot, 0, 0, 0);
    r_msg2_main(label, "setHidden:", 1, 0, 0, 0);
    nbl_apply_label_style(label, slot);
    r_msg2_main(gNBLWindow, "addSubview:", label, 0, 0, 0);

    gNBLLabels[slot] = label;
    gNBLHasLastLayout[slot] = NO;
    gNBLLastText[slot] = nil;
    return label;
}

bool nicebarlite_apply_in_session(NiceBarLiteConfig config)
{
    uint64_t applyStartUs = nbl_now_us();
    gNBLApplyTick++;
    uint32_t oldSettleUS = r_settle_us(0);
    uint32_t updateMask = config.updateMask;
    BOOL updateAll = (updateMask == 0);
    BOOL trace = nbl_should_trace_apply();

    if (trace) {
        NBL_DEBUG_LOG("[NICEBARLITE][APPLY] start tick=%llu updateMask=0x%08x updateAll=%d celsius=%d settleUS=%u->0\n",
                 (unsigned long long)gNBLApplyTick,
                 updateMask,
                 updateAll ? 1 : 0,
                 config.celsius ? 1 : 0,
                 oldSettleUS);
    }

    uint64_t metricsStartUs = nbl_now_us();
    nbl_prepare_tick_metrics();
    unsigned long long metricsMs = nbl_elapsed_ms_since(metricsStartUs);
    if (trace || metricsMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][METRICS] tick=%llu down=%.1fKB/s up=%.1fKB/s elapsed=%llums\n",
                 (unsigned long long)gNBLApplyTick,
                 gNBLTickDownKB,
                 gNBLTickUpKB,
                 metricsMs);
    }

    NSString *texts[NiceBarLiteSlotCount] = { nil };
    BOOL hidden[NiceBarLiteSlotCount] = { NO };
    BOOL hasVisibleSlot = NO;
    uint64_t textAllStartUs = nbl_now_us();
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        if (!updateAll && ((updateMask & (1u << i)) == 0)) {
            if (trace) {
                NBL_DEBUG_LOG("[NICEBARLITE][TEXT] skip slot=%s updateMask=0x%08x\n",
                         nbl_slot_name(i),
                         updateMask);
            }
            continue;
        }
        uint64_t textStartUs = nbl_now_us();
        texts[i] = nbl_text_for_slot(config.slots[i], config.celsius);
        unsigned long long textMs = nbl_elapsed_ms_since(textStartUs);
        hidden[i] = texts[i].length == 0;
        if (!hidden[i]) hasVisibleSlot = YES;
        if (trace || textMs >= kNBLSlowLogMs) {
            const char *item = config.slots[i].kind == NiceBarLiteContentSystem
                ? nbl_system_item_name(config.slots[i].systemItem)
                : "-";
            const char *language = (config.slots[i].systemLanguage && config.slots[i].systemLanguage[0])
                ? config.slots[i].systemLanguage
                : "-";
            NBL_DEBUG_LOG("[NICEBARLITE][TEXT] slot=%s kind=%s item=%s lang=%s len=%lu hidden=%d elapsed=%llums\n",
                     nbl_slot_name(i),
                     nbl_kind_name(config.slots[i].kind),
                     item,
                     language,
                     (unsigned long)texts[i].length,
                     hidden[i] ? 1 : 0,
                     textMs);
        }
    }
    unsigned long long textAllMs = nbl_elapsed_ms_since(textAllStartUs);
    if (trace || textAllMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][TEXT] total=%llums visible=%d\n",
                 textAllMs,
                 hasVisibleSlot ? 1 : 0);
    }

    if (updateAll && !hasVisibleSlot) {
        uint64_t hideStartUs = nbl_now_us();
        BOOL hidWindow = NO;
        int hidSlots = 0;
        if (r_is_objc_ptr(gNBLWindow) && gNBLWindowVisible) {
            r_msg2_main(gNBLWindow, "setHidden:", 1, 0, 0, 0);
            gNBLWindowVisible = NO;
            hidWindow = YES;
        }
        for (int i = 0; i < NiceBarLiteSlotCount; i++) {
            uint64_t view = gNBLLabels[i];
            if (r_is_objc_ptr(view) && (!gNBLHasLastLayout[i] || !gNBLLastHidden[i])) {
                r_msg2_main(view, "setHidden:", 1, 0, 0, 0);
                gNBLLastHidden[i] = YES;
                gNBLHasLastLayout[i] = YES;
                hidSlots++;
            }
        }
        unsigned long long hideMs = nbl_elapsed_ms_since(hideStartUs);
        unsigned long long totalMs = nbl_elapsed_ms_since(applyStartUs);
        if (trace || hideMs >= kNBLSlowLogMs || totalMs >= kNBLSlowLogMs) {
            NBL_DEBUG_LOG("[NICEBARLITE][APPLY] end tick=%llu ok=1 reason=no-visible hideWindow=%d hideSlots=%d hide=%llums total=%llums\n",
                     (unsigned long long)gNBLApplyTick,
                     hidWindow ? 1 : 0,
                     hidSlots,
                     hideMs,
                     totalMs);
        }
        r_settle_us(oldSettleUS);
        return true;
    }

    BOOL hadWindowPointer = (gNBLWindow != 0);
    uint64_t windowStartUs = nbl_now_us();
    if (!nbl_create_or_fetch_window()) {
        unsigned long long windowMs = nbl_elapsed_ms_since(windowStartUs);
        unsigned long long totalMs = nbl_elapsed_ms_since(applyStartUs);
        NBL_DEBUG_LOG("[NICEBARLITE][WINDOW] failed hadPointer=%d elapsed=%llums total=%llums\n",
                 hadWindowPointer ? 1 : 0,
                 windowMs,
                 totalMs);
        printf("[NICEBARLITE] failed to create overlay window\n");
        r_settle_us(oldSettleUS);
        return false;
    }
    unsigned long long windowMs = nbl_elapsed_ms_since(windowStartUs);
    if (trace || windowMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][WINDOW] ok=1 hadPointer=%d ptr=0x%llx elapsed=%llums\n",
                 hadWindowPointer ? 1 : 0,
                 (unsigned long long)gNBLWindow,
                 windowMs);
    }

    uint64_t layoutStartUs = nbl_now_us();
    NBLLayout layout = nbl_read_layout();
    unsigned long long layoutMs = nbl_elapsed_ms_since(layoutStartUs);
    if (trace || layoutMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][LAYOUT] screen=%.1fx%.1f top=%.1f elapsed=%llums\n",
                 layout.screenWidth,
                 layout.screenHeight,
                 layout.topAreaHeight,
                 layoutMs);
    }
    double windowH = layout.topAreaHeight + 24.0;
    BOOL frameChanged = !gNBLHasWindowFrame ||
                        fabs(gNBLLastWindowW - layout.screenWidth) > 0.5 ||
                        fabs(gNBLLastWindowH - windowH) > 0.5;
    uint64_t windowFrameStartUs = nbl_now_us();
    if (!gNBLHasWindowFrame ||
        fabs(gNBLLastWindowW - layout.screenWidth) > 0.5 ||
        fabs(gNBLLastWindowH - windowH) > 0.5) {
        nbl_send_rect_main(gNBLWindow, "setFrame:", 0.0, 0.0, layout.screenWidth, windowH);
        nbl_send_double_main(gNBLWindow, "setWindowLevel:", kNBLWindowLevel);
        gNBLLastWindowW = layout.screenWidth;
        gNBLLastWindowH = windowH;
        gNBLHasWindowFrame = YES;
    }
    unsigned long long windowFrameMs = nbl_elapsed_ms_since(windowFrameStartUs);
    if (trace || windowFrameMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][WINDOW] frameChanged=%d width=%.1f height=%.1f elapsed=%llums\n",
                 frameChanged ? 1 : 0,
                 layout.screenWidth,
                 windowH,
                 windowFrameMs);
    }
    uint64_t colorStartUs = nbl_now_us();
    BOOL refreshedColors = !gNBLWindowVisible;
    if (!gNBLWindowVisible) {
        nbl_refresh_text_colors();
    }
    unsigned long long colorMs = nbl_elapsed_ms_since(colorStartUs);
    if ((refreshedColors && trace) || colorMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][COLORS] refreshed=%d elapsed=%llums\n",
                 refreshedColors ? 1 : 0,
                 colorMs);
    }

    bool ok = true;
    uint64_t slotsStartUs = nbl_now_us();
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        if (!updateAll && ((updateMask & (1u << i)) == 0)) continue;
        uint64_t slotStartUs = nbl_now_us();
        NSString *text = texts[i];
        uint64_t label = gNBLLabels[i];
        if (hidden[i]) {
            BOOL hiddenChangedNow = NO;
            uint64_t view = label;
            if (r_is_objc_ptr(view) && (!gNBLHasLastLayout[i] || !gNBLLastHidden[i])) {
                r_msg2_main(view, "setHidden:", 1, 0, 0, 0);
                gNBLLastHidden[i] = YES;
                gNBLHasLastLayout[i] = YES;
                hiddenChangedNow = YES;
            }
            unsigned long long slotMs = nbl_elapsed_ms_since(slotStartUs);
            if (trace || slotMs >= kNBLSlowLogMs) {
                NBL_DEBUG_LOG("[NICEBARLITE][SLOT] slot=%s hidden=1 changed=%d total=%llums\n",
                         nbl_slot_name(i),
                         hiddenChangedNow ? 1 : 0,
                         slotMs);
            }
            continue;
        }

        uint64_t ensureStartUs = nbl_now_us();
        label = nbl_ensure_label((NiceBarLiteSlot)i);
        unsigned long long ensureMs = nbl_elapsed_ms_since(ensureStartUs);
        if (!r_is_objc_ptr(label)) {
            ok = false;
            unsigned long long slotMs = nbl_elapsed_ms_since(slotStartUs);
            NBL_DEBUG_LOG("[NICEBARLITE][SLOT] slot=%s failed=ensure-label ensure=%llums total=%llums\n",
                     nbl_slot_name(i),
                     ensureMs,
                     slotMs);
            continue;
        }
        BOOL networkSpeed = nbl_slot_is_network_speed(config.slots[i]);
        uint64_t styleStartUs = nbl_now_us();
        r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", networkSpeed ? 0 : 1, 0, 0, 0);
        unsigned long long styleMs = nbl_elapsed_ms_since(styleStartUs);
        uint64_t rectStartUs = nbl_now_us();
        NBLRect rect = nbl_rect_for_slot((NiceBarLiteSlot)i, config.slots[i], text, layout, config);
        unsigned long long rectMs = nbl_elapsed_ms_since(rectStartUs);
        BOOL textChanged = !gNBLLastText[i] || ![gNBLLastText[i] isEqualToString:text];
        BOOL layoutChanged = !gNBLHasLastLayout[i] ||
                             fabs(gNBLLastX[i] - rect.x) > 0.5 ||
                             fabs(gNBLLastY[i] - rect.y) > 0.5 ||
                             fabs(gNBLLastW[i] - rect.width) > 0.5;
        BOOL hiddenChanged = !gNBLHasLastLayout[i] || gNBLLastHidden[i] != hidden[i];

        unsigned long long setTextMs = 0;
        unsigned long long setFrameMs = 0;
        unsigned long long setHiddenMs = 0;
        BOOL textSetOK = YES;
        if (textChanged) {
            uint64_t setTextStartUs = nbl_now_us();
            uint64_t textObj = nbl_nsstring_utf8_fast(text.UTF8String);
            if (!r_is_objc_ptr(textObj)) {
                ok = false;
                textSetOK = NO;
            } else {
                bool setOK = nbl_set_text_fast(label, textObj);
                ok &= setOK;
                textSetOK = setOK ? YES : NO;
                nbl_release_remote_obj(textObj);
                gNBLLastText[i] = [text copy];
            }
            setTextMs = nbl_elapsed_ms_since(setTextStartUs);
        }
        if (layoutChanged) {
            uint64_t setFrameStartUs = nbl_now_us();
            r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
            ok &= nbl_send_rect_main(label, "setFrame:", rect.x, rect.y, rect.width, rect.height);
            gNBLLastX[i] = rect.x;
            gNBLLastY[i] = rect.y;
            gNBLLastW[i] = rect.width;
            setFrameMs = nbl_elapsed_ms_since(setFrameStartUs);
        }
        if (hiddenChanged) {
            uint64_t setHiddenStartUs = nbl_now_us();
            r_msg2_main(label, "setHidden:", hidden[i] ? 1 : 0, 0, 0, 0);
            gNBLLastHidden[i] = hidden[i];
            setHiddenMs = nbl_elapsed_ms_since(setHiddenStartUs);
        }
        gNBLHasLastLayout[i] = YES;
        unsigned long long slotMs = nbl_elapsed_ms_since(slotStartUs);
        if (trace || slotMs >= kNBLSlowLogMs || !textSetOK) {
            NBL_DEBUG_LOG("[NICEBARLITE][SLOT] slot=%s kind=%s item=%s len=%lu textChanged=%d layoutChanged=%d hiddenChanged=%d textOK=%d rect=%.0f,%.0f %.0fx%.0f ensure=%llums style=%llums measure=%llums setText=%llums setFrame=%llums setHidden=%llums total=%llums\n",
                     nbl_slot_name(i),
                     nbl_kind_name(config.slots[i].kind),
                     config.slots[i].kind == NiceBarLiteContentSystem ? nbl_system_item_name(config.slots[i].systemItem) : "-",
                     (unsigned long)text.length,
                     textChanged ? 1 : 0,
                     layoutChanged ? 1 : 0,
                     hiddenChanged ? 1 : 0,
                     textSetOK ? 1 : 0,
                     rect.x,
                     rect.y,
                     rect.width,
                     rect.height,
                     ensureMs,
                     styleMs,
                     rectMs,
                     setTextMs,
                     setFrameMs,
                     setHiddenMs,
                     slotMs);
        }
    }
    unsigned long long slotsMs = nbl_elapsed_ms_since(slotsStartUs);
    if (trace || slotsMs >= kNBLSlowLogMs) {
        NBL_DEBUG_LOG("[NICEBARLITE][SLOTS] total=%llums ok=%d\n",
                 slotsMs,
                 ok ? 1 : 0);
    }

    uint64_t unhideStartUs = nbl_now_us();
    BOOL unhidWindow = NO;
    if (!gNBLWindowVisible) {
        r_msg2_main(gNBLWindow, "setHidden:", 0, 0, 0, 0);
        gNBLWindowVisible = YES;
        unhidWindow = YES;
    }
    unsigned long long unhideMs = nbl_elapsed_ms_since(unhideStartUs);
    unsigned long long totalMs = nbl_elapsed_ms_since(applyStartUs);

    if (trace || totalMs >= kNBLSlowLogMs || !ok) {
        NBL_DEBUG_LOG("[NICEBARLITE][APPLY] end tick=%llu ok=%d visible=%d unhidWindow=%d unhide=%llums total=%llums\n",
                 (unsigned long long)gNBLApplyTick,
                 ok ? 1 : 0,
                 gNBLWindowVisible ? 1 : 0,
                 unhidWindow ? 1 : 0,
                 unhideMs,
                 totalMs);
    }

    if (nbl_should_log_tick()) {
        printf("[NICEBARLITE] applied overlay screen=%.1fx%.1f top=%.1f ok=%d\n",
               layout.screenWidth, layout.screenHeight, layout.topAreaHeight, ok);
    }
    r_settle_us(oldSettleUS);
    return ok;
}

bool nicebarlite_stop_in_session(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t assocKey = r_sel("cyanideNiceBarLiteWindow");
    if (!assocKey) return false;
    uint64_t win = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(win)) {
        r_msg2_main(win, "setHidden:", 1, 0, 0, 0);
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", app, assocKey, 0, 1, 0, 0, 0, 0);
    }
    nicebarlite_forget_remote_state();
    printf("[NICEBARLITE] stopped\n");
    return true;
}

void nicebarlite_forget_remote_state(void)
{
    gNBLWindow = 0;
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        gNBLLabels[i] = 0;
        gNBLLastText[i] = nil;
        gNBLLastX[i] = 0.0;
        gNBLLastY[i] = 0.0;
        gNBLLastW[i] = 0.0;
        gNBLLastHidden[i] = NO;
        gNBLHasLastLayout[i] = NO;
    }
    gNBLWindowVisible = NO;
    gNBLLastWindowW = 0.0;
    gNBLLastWindowH = 0.0;
    gNBLHasWindowFrame = NO;
    gNBLSetTextSel = 0;
    gNBLSetTextColorSel = 0;
    gNBLPerformMainSel = 0;
    gNBLNSStringClass = 0;
    gNBLAllocSel = 0;
    gNBLInitUTF8Sel = 0;
    gNBLUIApplicationClass = 0;
    gNBLUIWindowClass = 0;
    gNBLUILabelClass = 0;
    gNBLUIVisualEffectViewClass = 0;
    gNBLUIBlurEffectClass = 0;
    gNBLUIFontClass = 0;
    gNBLUIColorClass = 0;
    gNBLBlackColor = 0;
    gNBLWhiteColor = 0;
    gNBLTextColor = 0;
    gNBLFillColor = 0;
    gNBLBorderColor = 0;
    gNBLClearColor = 0;
    gNBLFontNormal = 0;
    gNBLFontTop = 0;
}
