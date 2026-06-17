//
//  CyanideEngine.m
//  Cyanide
//

#import "CyanideEngine.h"
#import "CyanideEngine+Internal.h"
#import "kexploit/kexploit_opa334.h"
#import "cyanide-vphone/vphone_krw.h"
#import "tweaks/sbcustomizer.h"
#import "tweaks/powercuff.h"
#import "tweaks/statbar.h"
#import "tweaks/private_compat.h"
#import "tweaks/nsbar.h"
#import "tweaks/nicebarlite.h"
#import "tweaks/axonlite.h"
#import "tweaks/darksword_tweaks.h"
#import "tweaks/darksword_drag.h"
#import "tweaks/darksword_ota.h"
#import "tweaks/darksword_layout.h"
#import "tweaks/nano_registry.h"
#import "tweaks/killallapps.h"
#import "tweaks/themer.h"
#import "tweaks/snowboardlite.h"
#import "tweaks/livewp.h"
#import "tweaks/gravitylite.h"
#import "tweaks/appswitchergrid.h"
#import "tweaks/hide_home_bar.h"
#import <CoreMotion/CoreMotion.h>

#import <objc/runtime.h>
#import <sys/time.h>
#import "DSKeepAlive.h"
#import "TaskRop/RemoteCall.h"
#import "kexploit/kutils.h"
#import "kexploit/persistence.h"
#import "Cyanide-Swift.h"
#import "installer/PackageQueueConstants.h"
#import "PatreonAuth.h"
#import "UpdateChecker.h"
#import "SBLArchiveExtractor.h"
#import "NiceBarSettingsSupport.h"
#import <WebKit/WebKit.h>
#import <MessageUI/MessageUI.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <notify.h>
#import <float.h>
#import <math.h>
#import <stdlib.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <time.h>
#import <unistd.h>

@interface DSRespringOverlayView : UIView
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) BOOL didLoadPayload;
@end

@implementation DSRespringOverlayView

- (NSString *)respringHTML {
    // Verbatim port of Lara's respring.swift payload (by rooootdev,
    // skidded from jailbreak.party; web approach by @neonmodder123).
    return @"<!DOCTYPE html>\n"
           @"<html>\n"
           @"    <body>\n"
           @"        <!--  big credit to @neonmodder123  -->\n"
           @"        <iframe id=\"frame\" srcdoc=\"\" sandbox=\"allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts\"></iframe>\n"
           @"        <script>\n"
           @"            const frame = document.getElementById('frame');\n"
           @"            const script = `\n"
           @"                <html>\n"
           @"                <body>\n"
           @"                    <script>\n"
           @"                        const container = document.createElement('div');\n"
           @"                        container.style.cssText = 'perspective: 1px; perspective-origin: 9999999% 9999999%;';\n"
           @"                        document.body.appendChild(container);\n"
           @"    \n"
           @"                        for (let i = 0; i < 500; i++) {\n"
           @"                            let d = document.createElement('div');\n"
           @"                            d.style.cssText = 'position: absolute; width: 100vw; height: 100vh; backdrop-filter: blur(100px); -webkit-backdrop-filter: blur(100px); transform: translate3d(100000px, 100000px, ' + i + 'px) rotateY(90deg);';\n"
           @"                            container.appendChild(d);\n"
           @"                        }\n"
           @"    \n"
           @"                        setInterval(() => {\n"
           @"                            navigator.share({ title: 'R', text: 'R'.repeat(100000) }).catch(() => {});\n"
           @"                            let x = new Uint8Array(1024 * 1024 * 10);\n"
           @"                            crypto.getRandomValues(x);\n"
           @"                        }, 0);\n"
           @"                    <\\/script>\n"
           @"                </body>\n"
           @"                </html>\n"
           @"            `;\n"
           @"    \n"
           @"            frame.srcdoc = script;\n"
           @"        </script>\n"
           @"    </body>\n"
           @"</html>";
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor blackColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self loadRespringPayload];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.webView.frame = self.bounds;
}

- (void)loadRespringPayload {
    if (self.didLoadPayload) return;
    self.didLoadPayload = YES;
    printf("[RESPRING] loading Lara-style in-app WebKit overlay\n");

    // Mirrors Lara's respringview verbatim: default-init WKWebView, the
    // throwaway WKWebpagePreferences assignment (a no-op in Lara's Swift
    // source — kept for fidelity), then loadHTMLString.
    WKWebView *webView = [[WKWebView alloc] initWithFrame:self.bounds];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [WKWebpagePreferences new].allowsContentJavaScript = YES;
    [self addSubview:webView];
    self.webView = webView;
    [webView loadHTMLString:[self respringHTML] baseURL:nil];
}

@end

NSString * const kSettingsAutoRunKexploit    = @"AutoRunKexploit";
NSString * const kSettingsRunSandboxEscape   = @"RunSandboxEscape";
NSString * const kSettingsRunPatchSandboxExt = @"RunPatchSandboxExt";
NSString * const kSettingsKeepAlive          = @"KeepAlive";

NSString * const kSettingsSBCEnabled    = @"SBCEnabled";
NSString * const kSettingsSBCDockIcons  = @"SBCDockIcons";
NSString * const kSettingsSBCCols       = @"SBCCols";
NSString * const kSettingsSBCRows       = @"SBCRows";
NSString * const kSettingsSBCHideLabels = @"SBCHideLabels";

NSString * const kSettingsPowercuffEnabled = @"PowercuffEnabled";
NSString * const kSettingsPowercuffLevel   = @"PowercuffLevel";
NSString * const kSettingsPowercuffNominalNoticeShown = @"cyanide.powercuff.nominalDefaultNoticeShown.v1";

NSString * const kSettingsDSDisableAppLibrary = @"DSDisableAppLibrary";
NSString * const kSettingsDSDisableIconFlyIn  = @"DSDisableIconFlyIn";
NSString * const kSettingsDSZeroWakeAnimation = @"DSZeroWakeAnimation";
NSString * const kSettingsDSZeroBacklightFade = @"DSZeroBacklightFade";
NSString * const kSettingsDSDoubleTapToLock   = @"DSDoubleTapToLock";

NSString * const kSettingsDSDragCoefficientEnabled = @"DSDragCoefficientEnabled";
NSString * const kSettingsDSDragCoefficientValue   = @"DSDragCoefficientValue";

NSString * const kSettingsLayoutExtrasEnabled  = @"LayoutExtrasEnabled";
NSString * const kSettingsLayoutHomeExtraLeft   = @"LayoutHomeExtraLeft";
NSString * const kSettingsLayoutHomeExtraRight  = @"LayoutHomeExtraRight";
NSString * const kSettingsLayoutHomeExtraTop    = @"LayoutHomeExtraTop";
NSString * const kSettingsLayoutHomeExtraBottom = @"LayoutHomeExtraBottom";
NSString * const kSettingsLayoutDockExtraHorizontal = @"LayoutDockExtraHorizontal";
NSString * const kSettingsLayoutHomeScalePct    = @"LayoutHomeScalePct";
NSString * const kSettingsLayoutDockScalePct    = @"LayoutDockScalePct";

double settings_number_row_normalized_value(NSDictionary *row, double value)
{
    double minV = row[@"min"] ? [row[@"min"] doubleValue] : -DBL_MAX;
    double maxV = row[@"max"] ? [row[@"max"] doubleValue] : DBL_MAX;
    if (value < minV) value = minV;
    if (value > maxV) value = maxV;

    double step = row[@"step"] ? [row[@"step"] doubleValue] : 0.0;
    if (step > 0.0) {
        value = round(value / step) * step;
        if (value < minV) value = minV;
        if (value > maxV) value = maxV;
    }

    NSInteger precision = row[@"precision"] ? [row[@"precision"] integerValue] : 0;
    if (precision <= 0) value = (double)llround(value);
    return value;
}

double settings_drag_coefficient_value(NSUserDefaults *d)
{
    id raw = [d objectForKey:kSettingsDSDragCoefficientValue];
    double value = [raw respondsToSelector:@selector(doubleValue)] ? [raw doubleValue] : 0.5;
    if (value <= 0.0) value = 0.5;

    // Older Cyanide builds stored this row as an integer percent (50 = 0.50).
    // New builds store the actual coefficient so typed values can reach 0.01.
    if (value > 2.0) value /= 100.0;

    NSDictionary *bounds = @{ @"min": @0.01, @"max": @2.0, @"step": @0.01, @"precision": @2 };
    return settings_number_row_normalized_value(bounds, value);
}

double settings_number_row_current_value(NSDictionary *row, NSUserDefaults *d)
{
    NSString *key = row[@"key"];
    if ([key isEqualToString:kSettingsDSDragCoefficientValue]) {
        return settings_drag_coefficient_value(d);
    }

    id raw = key.length > 0 ? [d objectForKey:key] : nil;
    double value = [raw respondsToSelector:@selector(doubleValue)]
        ? [raw doubleValue]
        : [row[@"default"] doubleValue];
    return settings_number_row_normalized_value(row, value);
}

NSString *settings_number_row_value_string(NSDictionary *row, double value, BOOL includeUnit)
{
    NSInteger precision = row[@"precision"] ? [row[@"precision"] integerValue] : 0;
    NSString *unit = includeUnit ? (row[@"unit"] ?: @"") : @"";
    if (precision <= 0) {
        return [NSString stringWithFormat:@"%ld%@", (long)llround(value), unit];
    }
    return [NSString stringWithFormat:@"%.*f%@", (int)precision, value, unit];
}

NSString * const kSettingsStatBarEnabled = @"StatBarEnabled";
NSString * const kSettingsStatBarCelsius = @"StatBarCelsius";
NSString * const kSettingsStatBarShowNet = @"StatBarShowNet";
NSString * const kSettingsStatBarShowCPU = @"StatBarShowCPU";
NSString * const kSettingsStatBarShowLabels = @"StatBarShowLabels";
NSString * const kSettingsStatBarNetworkOnly = @"StatBarNetworkOnly";
NSString * const kSettingsStatBarRefreshRateSec = @"StatBarRefreshRateSec";

NSString * const kSettingsNSBarEnabled = @"NSBarEnabled";
NSString * const kSettingsNSBarPosition = @"NSBarPosition";

NSString * const kSettingsNiceBarLiteEnabled = @"NiceBarLiteEnabled";
NSString * const kSettingsNiceBarLiteCelsius = @"NiceBarLiteCelsius";
NSString * const kSettingsNiceBarLiteSlotKindPrefix = @"NiceBarLiteSlotKind";
NSString * const kSettingsNiceBarLiteSlotSystemPrefix = @"NiceBarLiteSlotSystem";
NSString * const kSettingsNiceBarLiteSlotTextPrefix = @"NiceBarLiteSlotText";
NSString * const kSettingsNiceBarLiteSlotTimePrefix = @"NiceBarLiteSlotTime";
static NSString * const kSettingsNiceBarLiteSlotWeatherPrefix = @"NiceBarLiteSlotWeather";
NSString * const kSettingsNiceBarLiteSlotWeatherLanguagePrefix = @"NiceBarLiteSlotWeatherLanguage";
NSString * const kSettingsNiceBarLiteSlotSystemLanguagePrefix = @"NiceBarLiteSlotSystemLanguage";
static NSString * const kSettingsNiceBarLiteWeatherTemp = @"NiceBarLiteWeatherTemp";
static NSString * const kSettingsNiceBarLiteWeatherCode = @"NiceBarLiteWeatherCode";
NSString * const kSettingsNiceBarLiteWeatherCache = @"NiceBarLiteWeatherCache";
static NSString * const kSettingsNiceBarLiteWeatherLastAttemptAt = @"NiceBarLiteWeatherLastAttemptAt";
static NSString * const kSettingsNiceBarLiteWeatherUpdatedAt = @"NiceBarLiteWeatherUpdatedAt";
NSString * const kSettingsNiceBarLiteLayoutTopSideInset = @"NiceBarLiteLayoutTopSideInset";
NSString * const kSettingsNiceBarLiteLayoutBottomSideInset = @"NiceBarLiteLayoutBottomSideInset";
NSString * const kSettingsNiceBarLiteLayoutTopY = @"NiceBarLiteLayoutTopY";
NSString * const kSettingsNiceBarLiteLayoutBottomY = @"NiceBarLiteLayoutBottomY";
NSString * const kSettingsNiceBarLiteLayoutCenterX = @"NiceBarLiteLayoutCenterX";

NSString * const kSettingsRSSIDisplayEnabled = @"RSSIDisplayEnabled";
NSString * const kSettingsRSSIDisplayWifi    = @"RSSIDisplayWifi";
NSString * const kSettingsRSSIDisplayCell    = @"RSSIDisplayCell";

NSString * const kSettingsAxonLiteEnabled = @"AxonLiteEnabled";

NSString * const kSettingsTypeBannerEnabled = @"TypeBannerEnabled";
NSString * const kSettingsNotificationIslandEnabled = @"NotificationIslandEnabled";
NSString * const kSettingsAppSwitcherGridEnabled = @"AppSwitcherGridEnabled";
NSString * const kSettingsFastLockXLiteEnabled = @"FastLockXLiteEnabled";
NSString * const kSettingsFastLockXLiteBlockMusic = @"FastLockXLiteBlockMusic";
NSString * const kSettingsFastLockXLiteBlockFlashlight = @"FastLockXLiteBlockFlashlight";
NSString * const kSettingsFastLockXLiteBlockLowPower = @"FastLockXLiteBlockLowPower";
NSString * const kSettingsFastLockXLiteRetryInterval = @"FastLockXLiteRetryInterval";
NSString * const kSettingsHideHomeBarMaterialKitBootTime = @"HideHomeBarMaterialKitBootTime";

NSString * const kSettingsGravityLiteEnabled = @"GravityLiteEnabled";
NSString * const kSettingsGravityLiteDockEnabled = @"GravityLiteDockEnabled";
NSString * const kSettingsGravityLiteMagnitudePct = @"GravityLiteMagnitudePct";
NSString * const kSettingsGravityLiteBouncePct = @"GravityLiteBouncePct";
NSString * const kSettingsGravityLiteFrictionPct = @"GravityLiteFrictionPct";
NSString * const kSettingsGravityLiteResistancePct = @"GravityLiteResistancePct";
NSString * const kSettingsGravityLiteAngularResistancePct = @"GravityLiteAngularResistancePct";

NSString * const kSettingsStageStripEnabled = @"StageStripEnabled";

NSString * const kSettingsLocationSimEnabled = @"LocationSimEnabled";
NSString * const kSettingsLocationSimLatitude = @"LocationSimLatitude";
NSString * const kSettingsLocationSimLongitude = @"LocationSimLongitude";
NSString * const kSettingsLocationSimAltitude = @"LocationSimAltitude";
NSString * const kSettingsLocationSimHorizontalAccuracy = @"LocationSimHorizontalAccuracy";
NSString * const kSettingsLocationSimHostProcess = @"LocationSimHostProcess";
NSString * const kSettingsLocationSimStarted = @"LocationSimStarted";

NSString * const kSettingsIPADecryptorTargetBundleID = @"IPADecryptorTargetBundleID";
NSString * const kSettingsIPADecryptorAppStoreInput = @"IPADecryptorAppStoreInput";
NSString * const kSettingsIPADecryptorAppStoreID = @"IPADecryptorAppStoreID";
NSString * const kSettingsIPADecryptorAppStoreName = @"IPADecryptorAppStoreName";
NSString * const kSettingsIPADecryptorAppStoreVersion = @"IPADecryptorAppStoreVersion";
NSString * const kSettingsIPADecryptorAppStoreURL = @"IPADecryptorAppStoreURL";
NSString * const kSettingsIPADecryptorDownloadedIPAPath = @"IPADecryptorDownloadedIPAPath";
NSString * const kSettingsIPADecryptorDownloadStatus = @"IPADecryptorDownloadStatus";

NSString * const kSettingsThemerEnabled = @"ThemerEnabled";
NSString * const kSettingsThemerThemeID = @"ThemerThemeID";
NSString * const kSettingsThemerCustomThemePath = @"ThemerCustomThemePath";
NSString * const kSettingsThemerCustomThemeName = @"ThemerCustomThemeName";

NSString * const kSettingsSnowBoardLiteEnabled = @"SnowBoardLiteEnabled";
NSString * const kSettingsSnowBoardLiteSelectedThemeID = @"SnowBoardLiteSelectedThemeID";

NSString * const kSettingsLiveWPEnabled = @"LiveWPEnabled";
NSString * const kSettingsLiveWPVideoPath = @"LiveWPVideoPath";

// Master gate for experimental tweaks. When NO (default), packages that opt
// into the experimental category are hidden from the Installer and the
// Settings bundle list, and any currently-enabled experimental tweak is
// force-disabled when this is flipped off.
NSString * const kSettingsExperimentalTweaksEnabled = @"ExperimentalTweaksEnabled";

NSString * const kCyanideLastKnownIsPatron = @"CyanideLastKnownIsPatron";

// NanoRegistry pairing-compatibility editor. Numbers are the watchOS pairing
// compatibility versions that NRPairingCompatibilityVersionInfo reads from
// /var/mobile/Library/Preferences/com.apple.NanoRegistry.plist via
// CFPreferencesCopyValue("com.apple.NanoRegistry").
NSString * const kSettingsNanoMaxPairing       = @"NanoRegistryMaxPairing";
NSString * const kSettingsNanoMinPairing       = @"NanoRegistryMinPairing";
NSString * const kSettingsNanoMinPairingChipID = @"NanoRegistryMinPairingChipID";
NSString * const kSettingsNanoMinQuickSwitch   = @"NanoRegistryMinQuickSwitch";

NSString * const kSettingsLogUploadEnabled = @"LogUploadEnabled";


// Session-scoped state so uploaded snapshots from one chain run get grouped on
// the server side (same sessionId, monotonically increasing seq). A fresh
// session begins at every settings_run_actions() entry.
static dispatch_source_t g_cyanide_upload_timer = NULL;
static NSString         *g_cyanide_upload_session_id = nil;
static NSMutableSet<NSString *> *g_cyanide_upload_milestones = nil;
static volatile int      g_cyanide_upload_seq = 0;

// kind = "milestone" (important chain transition) or "final"
// (post-completion). Milestones are explicit so uploads line up with exploit,
// RemoteCall, tweak, and live-loop boundaries instead of timer noise.
static void cyanide_upload_log_with_kind_event(NSString *kind, NSString *event) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSettingsLogUploadEnabled]) return;
    NSString *path = log_most_recent_session_path();
    if (!path) return;
    NSString *rawLog = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!rawLog.length) return;

    int seq = __sync_add_and_fetch(&g_cyanide_upload_seq, 1);
    NSString *sessionId = g_cyanide_upload_session_id ?: @"adhoc";

    NSString *appVersion = settings_app_version_string();
    NSString *appBuild = settings_app_build_string();
    NSString *iosVersion = [UIDevice currentDevice].systemVersion;

    struct utsname sysInfo;
    uname(&sysInfo);
    NSString *machine = [NSString stringWithUTF8String:sysInfo.machine];

    // Prepend a diagnostic header so each uploaded log is self-contained.
    NSString *header = [NSString stringWithFormat:
        @"=== Cyanide Diagnostic Log ===\n"
        @"app_version : %@\n"
        @"app_build   : %@\n"
        @"ios_version : %@\n"
        @"device      : %@\n"
        @"log_file    : %@\n"
        @"session_id  : %@\n"
        @"kind        : %@\n"
        @"event       : %@\n"
        @"seq         : %d\n"
        @"==============================\n\n",
        appVersion, appBuild, iosVersion, machine, path.lastPathComponent,
        sessionId, kind, event ?: @"", seq];

    NSDictionary *body = @{
        @"log": [header stringByAppendingString:rawLog],
        @"meta": @{
            @"build":      [NSString stringWithFormat:@"cyanide-%@-%@", appVersion, appBuild],
            @"appVersion": appVersion,
            @"appBuild":   appBuild,
            @"source":     @"cyanide",
            @"ios":        iosVersion,
            @"device":     machine,
            @"sessionId":  sessionId,
            @"kind":       kind,
            @"event":      event ?: @"",
            @"seq":        @(seq),
        }
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!data) return;
    NSURL *url = [NSURL URLWithString:@"https://brokenblade-weblogs.hackerboii.workers.dev/log"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = data;
    printf("[LOG] uploading diagnostic (%s%s%s seq=%d, %zu bytes)...\n",
           kind.UTF8String,
           event.length ? ":" : "",
           event.length ? event.UTF8String : "",
           seq,
           (size_t)data.length);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) {
            printf("[LOG] upload %s%s%s failed: %s\n",
                   kind.UTF8String,
                   event.length ? ":" : "",
                   event.length ? event.UTF8String : "",
                   e.localizedDescription.UTF8String);
        } else {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
            printf("[LOG] upload %s%s%s ok: HTTP %ld\n",
                   kind.UTF8String,
                   event.length ? ":" : "",
                   event.length ? event.UTF8String : "",
                   (long)http.statusCode);
        }
    }] resume];
}

static void cyanide_upload_log_with_kind(NSString *kind) {
    cyanide_upload_log_with_kind_event(kind, nil);
}

static void cyanide_upload_log_milestone(NSString *event) {
    if (!event.length) return;

    @synchronized ([NSUserDefaults standardUserDefaults]) {
        if (!g_cyanide_upload_milestones)
            g_cyanide_upload_milestones = [NSMutableSet set];
        if ([g_cyanide_upload_milestones containsObject:event])
            return;
        [g_cyanide_upload_milestones addObject:event];
    }

    cyanide_upload_log_with_kind_event(@"milestone", event);
}

static void cyanide_upload_log_if_enabled(void) {
    cyanide_upload_log_with_kind(@"final");
}

// Begin a diagnostic upload session. Uploads are milestone-driven; this no
// longer starts the old 3s/8s periodic checkpoint timer.
static void cyanide_start_session_uploads(void) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSettingsLogUploadEnabled]) return;
    if (g_cyanide_upload_timer) return;

    g_cyanide_upload_session_id = [[NSUUID UUID] UUIDString];
    @synchronized ([NSUserDefaults standardUserDefaults]) {
        g_cyanide_upload_milestones = [NSMutableSet set];
    }
    g_cyanide_upload_seq = 0;
}

static void cyanide_stop_session_uploads(void) {
    if (g_cyanide_upload_timer) {
        dispatch_source_cancel(g_cyanide_upload_timer);
        g_cyanide_upload_timer = NULL;
    }
}

NSObject *settings_rc_lock(void);
BOOL settings_cleanup_in_progress(void);
static BOOL settings_screen_awake_cached(void);
static BOOL settings_screen_locked_cached(void);
static void settings_restart_gravity_motion_if_active(const char *reason);

extern int  escape_sbx_demo2(void);
extern int  escape_sbx_demo2_in_session(void);
extern int  escape_sbx_demo3(void);

BOOL g_kexploit_done = NO;
volatile int g_settings_actions_running = 0;
volatile int g_settings_respring_cleanup_running = 0;
static volatile int g_settings_actions_rerun_requested = 0;
volatile int g_springboard_rc_ready = 0;
static volatile int g_springboard_sandbox_escaped = 0;
static volatile int g_statbar_live_running = 0;
static volatile int g_statbar_live_stop_requested = 0;
static volatile int g_nsbar_live_running = 0;
static volatile int g_nsbar_live_stop_requested = 0;
static volatile int g_nicebarlite_live_running = 0;
static volatile int g_nicebarlite_live_stop_requested = 0;
static volatile int g_rssi_live_running = 0;
static volatile int g_rssi_live_stop_requested = 0;
static volatile int g_axonlite_live_running = 0;
static volatile int g_axonlite_live_stop_requested = 0;
volatile int g_typebanner_live_running = 0;
volatile int g_typebanner_live_stop_requested = 0;
static volatile int g_notificationisland_live_running = 0;
static volatile int g_notificationisland_live_stop_requested = 0;
volatile int g_gravitylite_background_armed = 0;
static volatile int g_gravitylite_start_worker_running = 0;
static volatile int g_gravity_motion_stop_requested = 1;
static volatile uint64_t g_gravity_motion_generation = 0;
static CMMotionManager *g_gravity_motion_manager = nil;
static volatile int g_themer_live_running = 0;
volatile int g_themer_live_stop_requested = 0;
static volatile int g_themer_repair_running = 0;
static volatile uint64_t g_themer_repair_generation = 0;
static volatile int g_themer_stage_suppression_logged = 0;
static volatile int g_livewp_live_running = 0;
volatile int g_livewp_live_stop_requested = 0;

void settings_mark_tweak_applied(NSString *key, BOOL applied);
void settings_notify_package_queue_changed_async(void);

static BOOL settings_gravity_motion_can_remote_call(uint64_t generation,
                                                    CMMotionManager *manager)
{
    return manager &&
           manager == g_gravity_motion_manager &&
           generation == g_gravity_motion_generation &&
           g_gravity_motion_stop_requested == 0 &&
           g_springboard_rc_ready != 0 &&
           !settings_screen_locked_cached() &&
           settings_screen_awake_cached() &&
           !settings_cleanup_in_progress();
}

static void settings_start_gravity_motion(double magnitude, double explosionForce)
{
    (void)explosionForce;
    if (g_gravity_motion_manager) {
        [g_gravity_motion_manager stopDeviceMotionUpdates];
        [g_gravity_motion_manager stopAccelerometerUpdates];
        g_gravity_motion_manager = nil;
    }
    CMMotionManager *mm = [[CMMotionManager alloc] init];
    g_gravity_motion_manager = mm;
    uint64_t generation = __sync_add_and_fetch(&g_gravity_motion_generation, 1);
    __sync_lock_test_and_set(&g_gravity_motion_stop_requested, 0);
    NSOperationQueue *q = [[NSOperationQueue alloc] init];
    q.maxConcurrentOperationCount = 1;

    if (mm.deviceMotionAvailable) {
        mm.deviceMotionUpdateInterval = 0.05;
        [mm startDeviceMotionUpdatesToQueue:q withHandler:^(CMDeviceMotion *motion, NSError *err) {
            if (!motion || err || !settings_gravity_motion_can_remote_call(generation, mm)) return;
            // gravity.x/y are already isolated from user movement.
            double tilt = hypot(motion.gravity.x, motion.gravity.y);
            double angle = (tilt < 0.14) ? M_PI_2 : atan2(-motion.gravity.y, motion.gravity.x);
            double effectiveMagnitude = magnitude * ((tilt < 0.14)
                                                     ? 0.65
                                                     : (0.90 + fmin(tilt, 1.0) * 0.60));

            @synchronized (settings_rc_lock()) {
                if (!settings_gravity_motion_can_remote_call(generation, mm)) return;
                gravitylite_update_gravity_angle_in_session(angle, effectiveMagnitude);
            }
        }];
    } else {
        mm.accelerometerUpdateInterval = 0.05;
        [mm startAccelerometerUpdatesToQueue:q withHandler:^(CMAccelerometerData *data, NSError *err) {
            if (!data || err || !settings_gravity_motion_can_remote_call(generation, mm)) return;
            double tilt = hypot(data.acceleration.x, data.acceleration.y);
            double angle = (tilt < 0.14) ? M_PI_2 : atan2(-data.acceleration.y, data.acceleration.x);
            double effectiveMagnitude = magnitude * ((tilt < 0.14)
                                                     ? 0.65
                                                     : (0.90 + fmin(tilt, 1.2) * 0.50));
            @synchronized (settings_rc_lock()) {
                if (!settings_gravity_motion_can_remote_call(generation, mm)) return;
                gravitylite_update_gravity_angle_in_session(angle, effectiveMagnitude);
            }
        }];
    }
    printf("[GRAVITY] Accelerometer active — tilt-only icon physics (magnitude=%.1fx)\n",
           magnitude);
}

void settings_stop_gravity_motion(void)
{
    __sync_lock_test_and_set(&g_gravity_motion_stop_requested, 1);
    __sync_add_and_fetch(&g_gravity_motion_generation, 1);
    CMMotionManager *mm = g_gravity_motion_manager;
    if (!mm) return;
    g_gravity_motion_manager = nil;
    [mm stopDeviceMotionUpdates];
    [mm stopAccelerometerUpdates];
    printf("[GRAVITY] Accelerometer stopped.\n");
}

typedef void (*SettingsTweakRequestStopFunc)(void);
typedef bool (*SettingsTweakStopFunc)(BOOL springboardWillDie);
typedef void (*SettingsTweakForgetFunc)(void);
typedef BOOL (*SettingsTweakRunningFunc)(void);

typedef struct {
    __unsafe_unretained NSString *key;
    const char *name;
    SettingsTweakRequestStopFunc requestStop;
    SettingsTweakStopFunc stop;
    SettingsTweakForgetFunc forget;
    SettingsTweakRunningFunc isRunning;
    BOOL cleanupOnTermination;
    BOOL keepsSpringBoardSession;
} SettingsSpringBoardTweakCleanupEntry;

static void settings_request_statbar_stop(void) { g_statbar_live_stop_requested = 1; }
static void settings_request_nsbar_stop(void) { g_nsbar_live_stop_requested = 1; }
static void settings_request_nicebarlite_stop(void) { g_nicebarlite_live_stop_requested = 1; }
static void settings_request_rssi_stop(void) { g_rssi_live_stop_requested = 1; }
static void settings_request_axonlite_stop(void) { g_axonlite_live_stop_requested = 1; }
static void settings_request_typebanner_stop(void) { g_typebanner_live_stop_requested = 1; }
static void settings_request_notificationisland_stop(void) { g_notificationisland_live_stop_requested = 1; }
static void settings_request_themer_stop(void) { g_themer_live_stop_requested = 1; }
static void settings_request_gravitylite_stop(void)
{
    __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
    settings_stop_gravity_motion();
}
static void settings_request_stagestrip_stop(void) { stagestrip_stop_control_loop(); }
static void settings_request_livewp_stop(void) { g_livewp_live_stop_requested = 1; }

static BOOL settings_statbar_running(void) { return g_statbar_live_running != 0; }
static BOOL settings_nsbar_running(void) { return g_nsbar_live_running != 0; }
static BOOL settings_nicebarlite_running(void) { return g_nicebarlite_live_running != 0; }
static BOOL settings_rssi_running(void) { return g_rssi_live_running != 0; }
static BOOL settings_axonlite_running(void) { return g_axonlite_live_running != 0; }
static BOOL settings_typebanner_running(void) { return g_typebanner_live_running != 0; }
static BOOL settings_notificationisland_running(void) { return g_notificationisland_live_running != 0; }
static BOOL settings_themer_running(void) { return g_themer_live_running != 0 || g_themer_repair_running != 0; }
static BOOL settings_livewp_running(void) { return g_livewp_live_running != 0; }

static bool settings_stop_statbar_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return statbar_stop_in_session();
}

static bool settings_stop_nsbar_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return nsbar_stop_in_session();
}

static bool settings_stop_nicebarlite_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return nicebarlite_stop_in_session();
}

static bool settings_stop_rssi_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return rssidisplay_stop_in_session();
}

static bool settings_stop_axonlite_registered(BOOL springboardWillDie)
{
    return springboardWillDie ? axonlite_stop_in_session_fast()
                              : axonlite_stop_in_session();
}

static bool settings_stop_typebanner_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    bool keepAlive = typebanner_release_mobilesms_keepalive_in_springboard_session();
    bool hidden = typebanner_hide_in_springboard_session();
    printf("[TYPEBANNER] cleanup keepAlive=%d hide=%d\n", keepAlive, hidden);
    return keepAlive && hidden;
}

static bool settings_stop_notificationisland_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return notificationisland_stop_in_session();
}

static bool settings_stop_appswitchergrid_registered(BOOL springboardWillDie)
{
    if (springboardWillDie) {
        appswitchergrid_forget_remote_state();
        return false;
    }
    return appswitchergrid_stop_in_session();
}

static bool settings_stop_gravitylite_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    settings_request_gravitylite_stop();
    return gravitylite_stop_in_session();
}

static bool settings_stop_themer_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return themer_stop_in_session();
}

static bool settings_stop_stagestrip_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return stagestrip_stop_in_session();
}

static bool settings_stop_fastlockx_lite_registered(BOOL springboardWillDie)
{
    if (springboardWillDie) {
        fastlockx_lite_forget_remote_state();
        return true;
    }
    return fastlockx_lite_disable_always_on_in_session();
}

static bool settings_stop_livewp_registered(BOOL springboardWillDie)
{
    (void)springboardWillDie;
    return livewp_stop_in_session();
}

static void settings_each_springboard_cleanup_entry(void (^block)(const SettingsSpringBoardTweakCleanupEntry *entry))
{
    if (!block) return;
    // Add new SpringBoard-backed tweaks here so Clean Up, Respring cleanup,
    // termination cleanup, live-loop waits, and applied-state reset stay in sync.
    const SettingsSpringBoardTweakCleanupEntry entries[] = {
        { kSettingsStatBarEnabled, "StatBar", settings_request_statbar_stop, settings_stop_statbar_registered, statbar_forget_remote_state, settings_statbar_running, YES, YES },
        { kSettingsNSBarEnabled, "NSBar", settings_request_nsbar_stop, settings_stop_nsbar_registered, nsbar_forget_remote_state, settings_nsbar_running, YES, YES },
        { kSettingsNiceBarLiteEnabled, "NiceBar Lite", settings_request_nicebarlite_stop, settings_stop_nicebarlite_registered, nicebarlite_forget_remote_state, settings_nicebarlite_running, YES, YES },
        { kSettingsRSSIDisplayEnabled, "RSSI", settings_request_rssi_stop, settings_stop_rssi_registered, rssidisplay_forget_remote_state, settings_rssi_running, YES, YES },
        { kSettingsAxonLiteEnabled, "Axon Lite", settings_request_axonlite_stop, settings_stop_axonlite_registered, axonlite_forget_remote_state, settings_axonlite_running, YES, YES },
        { kSettingsTypeBannerEnabled, "TypeBanner", settings_request_typebanner_stop, settings_stop_typebanner_registered, typebanner_forget_remote_state, settings_typebanner_running, YES, YES },
        { kSettingsNotificationIslandEnabled, "Notification Island", settings_request_notificationisland_stop, settings_stop_notificationisland_registered, notificationisland_forget_remote_state, settings_notificationisland_running, YES, YES },
        { kSettingsAppSwitcherGridEnabled, "App Switcher Grid", NULL, settings_stop_appswitchergrid_registered, appswitchergrid_forget_remote_state, NULL, YES, YES },
        { kSettingsGravityLiteEnabled, "Gravity Lite", settings_request_gravitylite_stop, settings_stop_gravitylite_registered, gravitylite_forget_remote_state, NULL, YES, YES },
        { kSettingsThemerEnabled, "Themer", settings_request_themer_stop, settings_stop_themer_registered, themer_forget_remote_state, settings_themer_running, YES, YES },
        { kSettingsSnowBoardLiteEnabled, "SnowBoard Lite", settings_request_themer_stop, settings_stop_themer_registered, themer_forget_remote_state, settings_themer_running, YES, YES },
        { kSettingsLiveWPEnabled, "LiveWP", settings_request_livewp_stop, settings_stop_livewp_registered, livewp_forget_remote_state, settings_livewp_running, YES, YES },
        { kSettingsStageStripEnabled, "Stage Strip", settings_request_stagestrip_stop, settings_stop_stagestrip_registered, stagestrip_forget_remote_state, NULL, YES, YES },
        { kSettingsFastLockXLiteEnabled, "FastLockX Lite", NULL, settings_stop_fastlockx_lite_registered, fastlockx_lite_forget_remote_state, NULL, YES, YES },
        { nil, "Kill All Apps", NULL, NULL, killallapps_forget_remote_state, NULL, NO, NO },
    };
    size_t count = sizeof(entries) / sizeof(entries[0]);
    for (size_t i = 0; i < count; i++) {
        block(&entries[i]);
    }
}

static BOOL settings_any_registered_live_loop_running(void)
{
    __block BOOL running = NO;
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (!running && entry->isRunning && entry->isRunning()) running = YES;
    });
    return running;
}

static NSString *settings_registered_live_loop_status_string(void)
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (!entry->isRunning) return;
        [parts addObject:[NSString stringWithFormat:@"%s=%d",
                                                    entry->name ?: "tweak",
                                                    entry->isRunning() ? 1 : 0]];
    });
    return [parts componentsJoinedByString:@" "];
}
static volatile int g_app_in_background = 0;
static volatile int g_screen_awake = 1;
static volatile int g_screen_locked = 0;
static volatile int g_screen_lock_state_logged = 0;
static volatile int g_settings_termination_cleanup_started = 0;
volatile int g_settings_cleanup_running = 0;
static volatile uint64_t g_sbc_live_apply_generation = 0;
static UIBackgroundTaskIdentifier g_statbar_bg_task = (UIBackgroundTaskIdentifier)-1;
static int g_springboard_blanked_notify_token = NOTIFY_TOKEN_INVALID;
static int g_display_status_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_lockstate_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_finished_startup_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_app_state_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_frontmost_notify_token = NOTIFY_TOKEN_INVALID;
const NSInteger kSBCDefaultDockIcons = 4;
const NSInteger kSBCDefaultCols = 4;
const NSInteger kSBCDefaultRows = 6;
static const BOOL kSBCDefaultHideLabels = NO;
// Conservative seed values for the NanoRegistry editor. These represent the
// current "newer watch" baseline without changing the legacy-watch gates.
const NSInteger kNanoDefaultMaxPairing       = 25;
const NSInteger kNanoDefaultMinPairing       = 24;
const NSInteger kNanoDefaultMinPairingChipID = 10;
const NSInteger kNanoDefaultMinQuickSwitch   = 6;
// Pairing range used to let setup accept newer watchOS pairing generations
// while still accepting generation-23 setup messages from the existing flow.
const NSInteger kNanoPresetNewerMaxPairing       = 99;
const NSInteger kNanoPresetNewerMinPairing       = 23;
const NSInteger kNanoPresetNewerMinPairingChipID = 10;
const NSInteger kNanoPresetNewerMinQuickSwitch   = 6;
static const double kLocationSimDefaultLatitude = 40.55162017033417;
static const double kLocationSimDefaultLongitude = -73.93282297058470;
const NSInteger kLocationSimDefaultAltitude = 0;
const NSInteger kLocationSimDefaultAccuracy = 5;
const NSInteger kNanoUIRowMin = 1;
const NSInteger kNanoUIRowMax = 999;
const NSInteger kStatBarDefaultRefreshRateSec = 3;
static const NSUInteger kStatBarLiveMaxTicks = 43200;
static const useconds_t kNSBarLiveIntervalUS = 1000000;
static const useconds_t kNSBarLiveBackgroundIntervalUS = 1500000;
static const NSUInteger kNSBarLiveMaxTicks = 43200;
static const useconds_t kNiceBarLiteLiveIntervalUS = 1000000;
static const useconds_t kNiceBarLiteLiveBackgroundIntervalUS = 1500000;
static const NSUInteger kNiceBarLiteLiveMaxTicks = 43200;
static const NSTimeInterval kNiceBarLiteWeatherRefreshInterval = 15.0 * 60.0;
static const useconds_t kLiveWPLiveIntervalUS = 2000000;
static const useconds_t kLiveWPLiveBackgroundIntervalUS = 3000000;
static const NSUInteger kLiveWPLiveMaxTicks = 43200;
static const int64_t kLiveBackgroundTaskGraceSeconds = 10;
static const useconds_t kRSSILiveIntervalUS = 250000;
static const useconds_t kRSSILiveBackgroundIntervalUS = 1000000;
static const NSUInteger kRSSILiveMaxTicks = 43200;
static const useconds_t kAxonLiteLiveIntervalUS = 500000;
static const useconds_t kAxonLiteLiveBackgroundIntervalUS = 1500000;
static const NSUInteger kAxonLiteLiveMaxTicks = 43200;
const int kSettingsSpringBoardRCFirstExceptionTimeoutMS = 3000;
// TypeBanner polls imagent for typing indicators with original-thread-only
// RemoteCall probes and opens SpringBoard only when the banner state changes.
static const useconds_t kTypeBannerLiveIntervalUS = 1000000;
static const useconds_t kTypeBannerLiveBackgroundIntervalUS = 1000000;
static const useconds_t kTypeBannerInitialDaemonSettleUS = 250000;
static const NSUInteger kTypeBannerLiveMaxTicks = 28800;
static const useconds_t kNotificationIslandLiveIntervalUS = 750000;
static const useconds_t kNotificationIslandLiveBackgroundIntervalUS = 1500000;
static const NSUInteger kNotificationIslandLiveMaxTicks = 43200;
// Only Clock/Calendar need periodic repair; normal icons persist through the
// model graft and should not be repainted during SpringBoard animations.
static const useconds_t kThemerLiveIntervalUS = 2000000;
static const useconds_t kThemerLiveBackgroundIntervalUS = 10000000;
static const NSUInteger kThemerLiveMaxTicks = 1;
static const NSUInteger kThemerLegacyLiveMaxTicks = 1;
static const useconds_t kThemerRepairInitialDelayUS = 900000;
static const useconds_t kThemerRepairIntervalUS = 450000;
static const uint64_t kSettingsTerminationCleanupWaitUS = 8000000ULL;
NSString * const kSettingsRemoteCallStateDidChangeNotification = @"SettingsRemoteCallStateDidChangeNotification";
NSString * const kSettingsActionsDidCompleteNotification = @"SettingsActionsDidCompleteNotification";
NSString * const kSettingsActionsDidCompleteSuccessKey = @"success";
NSString * const kSettingsActionsDidCompleteMessageKey = @"message";
NSString * const kSettingsCleanupStateDidChangeNotification = @"SettingsCleanupStateDidChangeNotification";

void settings_notify_cleanup_state_changed(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kSettingsCleanupStateDidChangeNotification
                          object:nil];
    });
}

void settings_post_actions_complete_async(BOOL success, NSString *message)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *info = @{
            kSettingsActionsDidCompleteSuccessKey: @(success),
            kSettingsActionsDidCompleteMessageKey: message ?: @""
        };
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kSettingsActionsDidCompleteNotification
                          object:nil
                        userInfo:info];
    });
}

static NSArray<NSString *> * const kPowercuffLevels = nil;

// Session-scoped record of which tweaks were actually applied since launch.
// Distinct from the persisted NSUserDefaults enable flag — these are wiped on
// app launch and whenever the SpringBoard RemoteCall session is torn down, so
// the UI can show accurate "Installed" state rather than a stale toggle.
static NSMutableSet<NSString *> *g_applied_tweak_keys = nil;

static NSMutableSet<NSString *> *settings_applied_keys_set(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_applied_tweak_keys = [NSMutableSet set];
    });
    return g_applied_tweak_keys;
}

void settings_mark_tweak_applied(NSString *key, BOOL applied)
{
    if (!key) return;
    NSMutableSet *set = settings_applied_keys_set();
    @synchronized (set) {
        if (applied) [set addObject:key];
        else         [set removeObject:key];
    }
}

BOOL settings_tweak_is_applied(NSString *key)
{
    if (!key) return NO;
    NSMutableSet *set = settings_applied_keys_set();
    @synchronized (set) {
        return [set containsObject:key];
    }
}

static BOOL settings_clear_all_applied_locked(void)
{
    NSMutableSet *set = settings_applied_keys_set();
    BOOL changed = NO;
    @synchronized (set) {
        if (set.count > 0) {
            [set removeAllObjects];
            changed = YES;
        }
    }
    return changed;
}

static NSArray<NSString *> *settings_rc_backed_tweak_keys(void)
{
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *allKeys = [NSMutableArray arrayWithArray:@[
            kSettingsSBCEnabled,
            kSettingsPowercuffEnabled,
            kSettingsDSDisableAppLibrary,
            kSettingsDSDisableIconFlyIn,
            kSettingsDSZeroWakeAnimation,
            kSettingsDSZeroBacklightFade,
            kSettingsDSDoubleTapToLock,
            kSettingsDSDragCoefficientEnabled,
            kSettingsLayoutExtrasEnabled,
        ]];
        settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
            if (entry->key && ![allKeys containsObject:entry->key]) {
                [allKeys addObject:entry->key];
            }
        });
        keys = [allKeys copy];
    });
    return keys;
}

static void settings_reconcile_applied_from_defaults(void)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in settings_rc_backed_tweak_keys()) {
        if (![d boolForKey:key]) settings_mark_tweak_applied(key, NO);
    }
}

void settings_notify_package_queue_changed_async(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                            object:[PackageQueue sharedQueue]];
    });
}

NSObject *settings_rc_lock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static NSObject *settings_bg_lock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static uint64_t settings_now_us(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ((uint64_t)ts.tv_sec * 1000000ULL) + ((uint64_t)ts.tv_nsec / 1000ULL);
}

static void settings_apply_statbar_once_async(const char *reason);
static void settings_apply_nsbar_once_async(const char *reason);
static void settings_apply_nicebarlite_once_async(const char *reason);
void settings_start_livewp_live_loop(void);
static void settings_resume_livewp_after_wake_async(const char *reason);
static void settings_pause_livewp_for_sleep_async(const char *reason);
static void settings_apply_rssi_once_async(const char *reason);
static void settings_start_rssi_live_loop(void);
void settings_start_typebanner_live_loop(void);
void settings_start_notificationisland_live_loop(void);
static void settings_start_themer_live_loop(void);
static void settings_schedule_themer_repair_burst(const char *reason);
static void settings_schedule_themer_quiet_repair_burst(const char *reason);
static void settings_notify_remote_call_state_changed(void);
static void settings_notify_remote_call_state_changed_preserving_applied(BOOL preserveApplied);
static void settings_request_all_live_loops_stop(const char *reason);

static BOOL settings_should_log_statbar_tick(NSUInteger tick) {
    // One-shot: log the very first tick so the user can see the loop took
    // off, then go silent forever. The polling continues; we just stop
    // narrating it.
    return tick == 0;
}

static useconds_t settings_live_interval(useconds_t foregroundUS, useconds_t backgroundUS)
{
    return (g_app_in_background != 0) ? backgroundUS : foregroundUS;
}

static useconds_t settings_statbar_refresh_rate_us(void)
{
    NSInteger sec = [[NSUserDefaults standardUserDefaults] integerForKey:kSettingsStatBarRefreshRateSec];
    if (sec <= 0) sec = kStatBarDefaultRefreshRateSec;
    if (sec < kStatBarDefaultRefreshRateSec) sec = kStatBarDefaultRefreshRateSec;
    if (sec > 30) sec = 30;
    return (useconds_t)sec * 1000000;
}

static useconds_t settings_statbar_live_interval_us(void)
{
    // StatBar can update temp + CPU + RAM + network at the same time. Respect
    // the configured refresh rate in foreground too instead of forcing a 1s
    // RemoteCall/UI update loop while the Activity sheet is visible.
    return settings_statbar_refresh_rate_us();
}

static const char *settings_live_context(void)
{
    return (g_app_in_background != 0) ? "background" : "foreground";
}

static BOOL settings_app_state_is_foreground(void)
{
    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    return state == UIApplicationStateActive || state == UIApplicationStateInactive;
}

static NSUInteger settings_live_failure_limit(NSUInteger foregroundLimit)
{
    return (g_app_in_background != 0 || g_screen_awake == 0) ? 1 : foregroundLimit;
}

BOOL settings_experimental_access_allowed(void)
{
    return cyanide_is_patron() || cyanide_is_creator();
}

BOOL settings_experimental_tweaks_enabled(void)
{
    return settings_experimental_access_allowed() &&
           [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsExperimentalTweaksEnabled];
}

static BOOL settings_rssi_install_allowed(void)
{
    return cyanide_private_tweaks_available() && settings_experimental_tweaks_enabled();
}

static BOOL settings_typebanner_install_allowed(void)
{
    return cyanide_private_tweaks_available() && settings_experimental_tweaks_enabled();
}

BOOL settings_notificationisland_install_allowed(void)
{
    return cyanide_private_tweaks_available() && settings_experimental_tweaks_enabled();
}

static BOOL settings_stagestrip_install_allowed(void)
{
    return cyanide_private_tweaks_available() && settings_experimental_tweaks_enabled();
}

BOOL settings_fastlockx_lite_install_allowed(void)
{
    return cyanide_private_tweaks_available() && settings_experimental_tweaks_enabled();
}

static BOOL settings_themer_dynamic_updates_blocked_by_stage(NSUserDefaults *d)
{
    if (!settings_stagestrip_install_allowed()) return NO;
    if (![d boolForKey:kSettingsStageStripEnabled]) return NO;
    return [d boolForKey:kSettingsThemerEnabled] ||
           [d boolForKey:kSettingsSnowBoardLiteEnabled];
}

static void settings_note_themer_stage_conflict(BOOL userVisible)
{
    g_themer_live_stop_requested = 1;
    printf("[SETTINGS] Themer live icon repair paused while Dynamic Stage Lite is enabled\n");
    if (userVisible && __sync_bool_compare_and_swap(&g_themer_stage_suppression_logged, 0, 1)) {
        log_user("[COMPAT] Dynamic Stage Lite is enabled, so icon theme live repair is paused to avoid SpringBoard resprings. The selected theme still applies once; live repair resumes after Dynamic Stage is disabled.\n");
    }
}

BOOL settings_location_sim_install_allowed(void)
{
    return YES;
}

static BOOL settings_read_screen_awake(void)
{
    BOOL haveState = NO;
    BOOL awake = YES;

    if (g_springboard_blanked_notify_token != NOTIFY_TOKEN_INVALID) {
        uint64_t state = 0;
        if (notify_get_state(g_springboard_blanked_notify_token, &state) == NOTIFY_STATUS_OK) {
            haveState = YES;
            awake = (state == 0);
        }
    }

    if (!haveState && g_display_status_notify_token != NOTIFY_TOKEN_INVALID) {
        uint64_t state = 0;
        if (notify_get_state(g_display_status_notify_token, &state) == NOTIFY_STATUS_OK) {
            awake = (state != 0);
        }
    }

    return awake;
}

static BOOL settings_screen_awake_cached(void)
{
    return g_screen_awake != 0;
}

static BOOL settings_refresh_screen_awake_state(const char *reason)
{
    BOOL awake = settings_read_screen_awake();
    int newValue = awake ? 1 : 0;
    int old = __sync_lock_test_and_set(&g_screen_awake, newValue);
    if (old != newValue) {
        printf("[SETTINGS] screen state=%s%s%s\n",
               awake ? "awake" : "asleep",
               reason ? " via " : "",
               reason ?: "");
    }
    return old == 0 && newValue != 0;
}

static BOOL settings_statbar_screen_awake(void)
{
    (void)settings_refresh_screen_awake_state(NULL);
    return settings_screen_awake_cached();
}

static BOOL settings_read_screen_locked(void)
{
    if (g_springboard_lockstate_notify_token == NOTIFY_TOKEN_INVALID) return NO;

    uint64_t state = 0;
    if (notify_get_state(g_springboard_lockstate_notify_token, &state) != NOTIFY_STATUS_OK) {
        return NO;
    }

    return state != 0;
}

static BOOL settings_screen_locked_cached(void)
{
    return g_screen_locked != 0;
}

static BOOL settings_refresh_screen_lock_state(const char *reason)
{
    BOOL locked = settings_read_screen_locked();
    int newValue = locked ? 1 : 0;
    int old = __sync_lock_test_and_set(&g_screen_locked, newValue);
    (void)__sync_lock_test_and_set(&g_screen_lock_state_logged, 1);
    return old != newValue;
}

static BOOL settings_axonlite_can_poll_springboard(void)
{
    // Locked-but-awake is the lockscreen — that's where Axon must run, so the
    // lock state is intentionally not part of this predicate. Only pause while
    // the screen is fully blanked, since SB tears down the cover-sheet VCs and
    // our cached pointers would PAC-fault if we kept calling through them.
    (void)settings_refresh_screen_awake_state(NULL);
    return settings_screen_awake_cached();
}

static const char *settings_axonlite_pause_reason(void)
{
    if (!settings_screen_awake_cached()) return "screen asleep";
    return "screen unavailable";
}

static BOOL settings_typebanner_can_poll_messages(void)
{
    (void)settings_refresh_screen_awake_state(NULL);
    (void)settings_refresh_screen_lock_state(NULL);
    return settings_screen_awake_cached() && !settings_screen_locked_cached();
}

static const char *settings_typebanner_pause_reason(void)
{
    if (!settings_screen_awake_cached()) return "screen asleep";
    if (settings_screen_locked_cached()) return "device locked";
    return "screen unavailable";
}

static void settings_stop_axonlite_then_forget_locked(const char *reason)
{
    if (g_springboard_rc_ready) {
        bool stopped = axonlite_stop_in_session();
        printf("[SETTINGS] Axon Lite stopped before state drop%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", stopped);
    }
    axonlite_forget_remote_state();
}

static void settings_forget_springboard_tweak_state_locked(void)
{
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (entry->forget) entry->forget();
    });
}

static void settings_stop_springboard_tweaks_locked(const char *reason,
                                                    BOOL springboardWillDie)
{
    if (!g_springboard_rc_ready) {
        settings_forget_springboard_tweak_state_locked();
        return;
    }

    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (!entry->stop) return;
        @try {
            bool stopped = entry->stop(springboardWillDie);
            printf("[SETTINGS] %s %s stop%s result=%d\n",
                   reason ?: "SpringBoard cleanup",
                   entry->name ?: "tweak",
                   springboardWillDie ? " (fast)" : "",
                   stopped);
        } @catch (NSException *e) {
            printf("[SETTINGS] %s %s cleanup exception: %s\n",
                   reason ?: "SpringBoard cleanup",
                   entry->name ?: "tweak",
                   e.reason.UTF8String);
        }
    });

    settings_forget_springboard_tweak_state_locked();
}

static BOOL settings_disabled_applied_springboard_cleanup_needed(NSUserDefaults *d)
{
    __block BOOL needed = NO;
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (needed || !entry->key || !entry->stop) return;
        needed = ![d boolForKey:entry->key] && settings_tweak_is_applied(entry->key);
    });
    return needed;
}

static void settings_stop_disabled_applied_springboard_tweaks_locked(NSUserDefaults *d)
{
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (!entry->key || !entry->stop) return;
        if ([d boolForKey:entry->key] || !settings_tweak_is_applied(entry->key)) return;
        if (entry->requestStop) entry->requestStop();
        @try {
            bool stopped = g_springboard_rc_ready ? entry->stop(NO) : false;
            if (entry->forget) entry->forget();
            settings_mark_tweak_applied(entry->key, NO);
            printf("[SETTINGS] disabled %s cleanup result=%d\n",
                   entry->name ?: "tweak",
                   stopped);
        } @catch (NSException *e) {
            printf("[SETTINGS] disabled %s cleanup exception: %s\n",
                   entry->name ?: "tweak",
                   e.reason.UTF8String);
        }
    });
}

static void settings_handle_springboard_restart(void)
{
    // SpringBoard just (re)started. Every pointer we cached from the previous
    // SB incarnation — class addresses, selector slots, retained objects,
    // ivar offsets, the trojan thread, our shmem map — is stale. Calling
    // through any of them under SB-2 hands a wild signed function pointer to
    // BLRAA and PAC-faults us. Drop everything before the next loop tick.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL hadSession = NO;
        @synchronized (settings_rc_lock()) {
            hadSession = (g_springboard_rc_ready != 0);
            // Tell live loops to bail at their next interval check.
            settings_request_all_live_loops_stop("SpringBoard restart");
            g_springboard_rc_ready = 0;
            g_springboard_sandbox_escaped = 0;

            settings_forget_springboard_tweak_state_locked();
            if (hadSession) {
                abandon_remote_call();
            }
        }
        printf("[SETTINGS] SpringBoard restart observed; dropped RemoteCall state (hadSession=%d)\n",
               (int)hadSession);
        if (hadSession) {
            log_user("[APP] SpringBoard restarted; tweak sessions cleared. Hit Run to rebuild.\n");
        }
        settings_notify_remote_call_state_changed();
    });
}

static void settings_install_screen_awake_observers(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int status = notify_register_dispatch("com.apple.springboard.hasBlankedScreen",
                                              &g_springboard_blanked_notify_token,
                                              dispatch_get_main_queue(), ^(int token) {
            (void)token;
            if (settings_refresh_screen_awake_state("springboard.hasBlankedScreen")) {
                settings_apply_statbar_once_async("screen awake");
                settings_apply_nsbar_once_async("screen awake");
                settings_apply_nicebarlite_once_async("screen awake");
                settings_resume_livewp_after_wake_async("screen awake");
                settings_schedule_themer_quiet_repair_burst("screen awake");
                settings_restart_gravity_motion_if_active("screen awake");
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_blanked_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.iokit.hid.displayStatus",
                                          &g_display_status_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            if (settings_refresh_screen_awake_state("iokit.displayStatus")) {
                settings_apply_statbar_once_async("screen awake");
                settings_apply_nsbar_once_async("screen awake");
                settings_apply_nicebarlite_once_async("screen awake");
                settings_resume_livewp_after_wake_async("display awake");
                settings_schedule_themer_quiet_repair_burst("display awake");
                settings_restart_gravity_motion_if_active("display awake");
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            g_display_status_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.springboard.lockstate",
                                          &g_springboard_lockstate_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            BOOL changed = settings_refresh_screen_lock_state("springboard.lockstate");
            if (changed && g_screen_locked) {
                // Stop the accelerometer before the XPC/shmem stack tears down on lock —
                // otherwise the next callback fires into a stale shmem mapping.
                settings_stop_gravity_motion();
                gravitylite_forget_remote_state();
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_lockstate_notify_token = NOTIFY_TOKEN_INVALID;
        }

        // Darwin notify fires when SpringBoard finishes its boot/respawn.
        // Either we just launched and SB is fine (cleanup is a no-op against
        // already-zero state) or SB crashed under us and we MUST drop every
        // cached pointer before the live loops fire again into SB-2.
        status = notify_register_dispatch("com.apple.springboard.finishedstartup",
                                          &g_springboard_finished_startup_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            settings_handle_springboard_restart();
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_finished_startup_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.springboard.applicationStateChanged",
                                          &g_springboard_app_state_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            uint64_t state = 0;
            (void)notify_get_state(token, &state);
            printf("[SETTINGS] springboard application state notify state=%llu\n",
                   (unsigned long long)state);
            settings_schedule_themer_repair_burst("springboard app state changed");
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_app_state_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.springboard.frontmostApplicationChanged",
                                          &g_springboard_frontmost_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            uint64_t state = 0;
            (void)notify_get_state(token, &state);
            printf("[SETTINGS] springboard frontmost app notify state=%llu\n",
                   (unsigned long long)state);
            settings_schedule_themer_repair_burst("springboard frontmost changed");
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_frontmost_notify_token = NOTIFY_TOKEN_INVALID;
        }

        // If the live loop tripped its 3-failure exit during a background
        // window, the screen-wake darwin notifications won't fire (the screen
        // never blanked) and the loop stays dead. Re-arm on app foreground.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            (void)note;
            (void)settings_refresh_screen_awake_state("app became active");
            settings_apply_statbar_once_async("app became active");
            settings_schedule_themer_quiet_repair_burst("app became active");
        }];

        (void)settings_refresh_screen_awake_state("startup");
        (void)settings_refresh_screen_lock_state("startup");
    });
}

static void settings_end_statbar_background_task_async(const char *reason)
{
    void (^endTask)(void) = ^{
        @synchronized (settings_bg_lock()) {
            if (g_statbar_bg_task == UIBackgroundTaskInvalid) return;
            UIBackgroundTaskIdentifier task = g_statbar_bg_task;
            g_statbar_bg_task = UIBackgroundTaskInvalid;
            [[UIApplication sharedApplication] endBackgroundTask:task];
            printf("[SETTINGS] StatBar background task ended%s%s\n",
                   reason ? ": " : "", reason ?: "");
        }
    };

    if ([NSThread isMainThread]) {
        endTask();
    } else {
        dispatch_async(dispatch_get_main_queue(), endTask);
    }
}

// Bridge the foreground -> background transition with a short explicit
// UIBackgroundTask. DSKeepAlive's audio background mode carries the ongoing
// live feed; holding a UIBackgroundTask indefinitely trips UIKit's 30s watchdog
// warning and can get the app terminated.
static void settings_begin_statbar_background_task_async(const char *reason)
{
    void (^beginTask)(void) = ^{
        @synchronized (settings_bg_lock()) {
            if (g_statbar_bg_task != UIBackgroundTaskInvalid) return;
            UIApplication *app = [UIApplication sharedApplication];
            __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
            task = [app beginBackgroundTaskWithName:@"cyanide.statbar.live"
                                  expirationHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized (settings_bg_lock()) {
                        if (g_statbar_bg_task != task) return;
                        g_statbar_bg_task = UIBackgroundTaskInvalid;
                        [[UIApplication sharedApplication] endBackgroundTask:task];
                        printf("[SETTINGS] StatBar background task expired by iOS; live loop may pause\n");
                    }
                });
            }];
            if (task == UIBackgroundTaskInvalid) {
                printf("[SETTINGS] StatBar background task could not be acquired%s%s\n",
                       reason ? ": " : "", reason ?: "");
                return;
            }
            g_statbar_bg_task = task;
            printf("[SETTINGS] StatBar background task acquired id=%lu%s%s\n",
                   (unsigned long)task,
                   reason ? ": " : "", reason ?: "");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         kLiveBackgroundTaskGraceSeconds * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                @synchronized (settings_bg_lock()) {
                    if (g_statbar_bg_task != task) return;
                    g_statbar_bg_task = UIBackgroundTaskInvalid;
                    [[UIApplication sharedApplication] endBackgroundTask:task];
                    printf("[SETTINGS] StatBar background task ended: transition grace elapsed; keepAlive=%d\n",
                           ds_keepalive_is_running());
                }
            });
        }
    };

    if ([NSThread isMainThread]) {
        beginTask();
    } else {
        dispatch_sync(dispatch_get_main_queue(), beginTask);
    }
}

static void settings_notify_remote_call_state_changed(void)
{
    settings_notify_remote_call_state_changed_preserving_applied(NO);
}

static void settings_notify_remote_call_state_changed_preserving_applied(BOOL preserveApplied)
{
    BOOL ready = (g_springboard_rc_ready != 0);
    BOOL cleared = NO;
    if (!ready && !preserveApplied) {
        cleared = settings_clear_all_applied_locked();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsRemoteCallStateDidChangeNotification
                                                            object:nil];
        if (cleared) {
            [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                object:[PackageQueue sharedQueue]];
            [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsActionsDidCompleteNotification
                                                                object:nil];
        }
    });
}

BOOL settings_cleanup_in_progress(void)
{
    return g_settings_cleanup_running != 0 ||
           g_settings_respring_cleanup_running != 0;
}

static void settings_request_all_live_loops_stop(const char *reason)
{
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (entry->requestStop) entry->requestStop();
    });
    if (reason) {
        printf("[SETTINGS] requested all live RemoteCall loops stop: %s\n", reason);
    }
}

static BOOL settings_has_active_termination_live_tweak(void)
{
    if (settings_any_registered_live_loop_running()) {
        return YES;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    __block BOOL active = NO;
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (active || !entry->cleanupOnTermination || !entry->key) return;
        active = [d boolForKey:entry->key] && settings_tweak_is_applied(entry->key);
    });
    return active;
}

static BOOL settings_has_persistent_springboard_remote_call_user(void)
{
    if (settings_has_active_termination_live_tweak()) {
        return YES;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    __block BOOL active = NO;
    settings_each_springboard_cleanup_entry(^(const SettingsSpringBoardTweakCleanupEntry *entry) {
        if (active || !entry->keepsSpringBoardSession || !entry->key) return;
        active = [d boolForKey:entry->key] && settings_tweak_is_applied(entry->key);
    });
    return active;
}

static void settings_wait_live_loops_stopped_for_switch(const char *reason)
{
    uint64_t startUS = settings_now_us();
    BOOL logged = NO;
    while (settings_any_registered_live_loop_running()) {
        uint64_t nowUS = settings_now_us();
        uint64_t elapsedUS = (startUS != 0 && nowUS >= startUS) ? nowUS - startUS : 0;
        if (!logged) {
            printf("[SETTINGS] waiting for live RemoteCall loops to stop%s%s\n",
                   reason ? ": " : "", reason ?: "");
            logged = YES;
        }
        if (elapsedUS >= 2000000ULL) {
            NSString *status = settings_registered_live_loop_status_string();
            printf("[SETTINGS] live loop stop wait timed out%s%s %s\n",
                   reason ? ": " : "", reason ?: "",
                   status.UTF8String);
            break;
        }
        usleep(50000);
    }
    if (logged && !settings_any_registered_live_loop_running()) {
        printf("[SETTINGS] live RemoteCall loops stopped%s%s\n",
               reason ? ": " : "", reason ?: "");
    }
}

static void settings_live_loop_sleep_interruptible(uint64_t targetUS,
                                                  useconds_t fallbackUS,
                                                  volatile int *stopFlag)
{
    uint64_t sleptFallbackUS = 0;
    while (!settings_cleanup_in_progress() && (!stopFlag || *stopFlag == 0)) {
        uint64_t nowUS = settings_now_us();
        uint64_t remainingUS = 0;
        if (targetUS != 0 && nowUS != 0 && nowUS < targetUS) {
            remainingUS = targetUS - nowUS;
        } else if (targetUS == 0 && sleptFallbackUS < fallbackUS) {
            remainingUS = (uint64_t)fallbackUS - sleptFallbackUS;
        } else {
            break;
        }

        useconds_t chunkUS = (useconds_t)(remainingUS < 100000ULL ? remainingUS : 100000ULL);
        if (chunkUS == 0) break;
        usleep(chunkUS);
        if (targetUS == 0) sleptFallbackUS += chunkUS;
    }
}

static UIViewController *settings_top_view_controller(UIViewController *vc)
{
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) {
        return settings_top_view_controller(((UINavigationController *)vc).visibleViewController);
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        return settings_top_view_controller(((UITabBarController *)vc).selectedViewController);
    }
    return vc;
}

static UIViewController *settings_active_presenter(UIViewController *fallback)
{
    if (fallback.view.window) return settings_top_view_controller(fallback);

    UIWindow *candidate = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive &&
            ws.activationState != UISceneActivationStateForegroundInactive) {
            continue;
        }
        for (UIWindow *window in ws.windows) {
            if (window.isKeyWindow) {
                candidate = window;
                break;
            }
            if (!candidate && !window.hidden && window.rootViewController) {
                candidate = window;
            }
        }
        if (candidate) break;
    }

    return settings_top_view_controller(candidate.rootViewController ?: fallback);
}

static UIWindow *settings_active_window(UIViewController *fallback)
{
    if (fallback.view.window) return fallback.view.window;

    UIWindow *candidate = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive &&
            ws.activationState != UISceneActivationStateForegroundInactive) {
            continue;
        }
        for (UIWindow *window in ws.windows) {
            if (window.isKeyWindow) return window;
            if (!candidate && !window.hidden && window.rootViewController) {
                candidate = window;
            }
        }
    }
    return candidate;
}

void settings_present_controller(UIViewController *controller, UIViewController *fallback)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = settings_active_presenter(fallback);
        if (!presenter) {
            printf("[SETTINGS] presentation skipped: no attached presenter\n");
            return;
        }
        [presenter presentViewController:controller animated:YES completion:nil];
    });
}

void settings_show_respring_overlay(UIViewController *fallback)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = settings_active_window(fallback);
        if (!window) {
            printf("[RESPRING] overlay skipped: no active window\n");
            return;
        }
        DSRespringOverlayView *overlay = [[DSRespringOverlayView alloc] initWithFrame:window.bounds];
        [window addSubview:overlay];
        [overlay loadRespringPayload];
    });
}

NSArray<NSString *> *powercuff_levels(void) {
    return @[ @"off", @"nominal", @"light", @"moderate", @"heavy" ];
}

static NSComparisonResult settings_compare_system_version(NSString *target)
{
    NSString *version = UIDevice.currentDevice.systemVersion ?: @"0";
    return [version compare:target options:NSNumericSearch];
}

static BOOL settings_string_contains_livecontainer(NSString *value)
{
    return [value rangeOfString:@"LiveContainer"
                        options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL settings_running_inside_livecontainer(void)
{
    const char *lcHome = getenv("LC_HOME_PATH");
    if (lcHome && lcHome[0]) return YES;

    const char *lcTweaks = getenv("LC_GLOBAL_TWEAKS_FOLDER");
    if (lcTweaks && lcTweaks[0]) return YES;

    if (settings_string_contains_livecontainer(NSBundle.mainBundle.bundlePath ?: @"")) return YES;
    if (settings_string_contains_livecontainer(NSBundle.mainBundle.executablePath ?: @"")) return YES;
    if (settings_string_contains_livecontainer(NSProcessInfo.processInfo.arguments.firstObject ?: @"")) return YES;

    return NO;
}

static BOOL settings_ios_vphone_range(void)
{
    return settings_compare_system_version(@"26.1") != NSOrderedAscending &&
           settings_compare_system_version(@"26.5") != NSOrderedDescending;
}

static BOOL settings_wait_for_vphone_springboard_bridge(NSTimeInterval timeoutSeconds)
{
    if (!settings_ios_vphone_range()) return NO;

    int attempts = (int)ceil(timeoutSeconds / 0.25);
    if (attempts < 1) attempts = 1;
    for (int i = 0; i < attempts; i++) {
        if (remote_call_vphone_springboard_bridge_available()) return YES;
        usleep(250000);
    }
    return remote_call_vphone_springboard_bridge_available();
}

BOOL settings_device_supported(void)
{
    if (settings_running_inside_livecontainer()) return NO;

    BOOL vphonePresent = g_vphone_mode || vphone_tfp0_available();
    if (vphonePresent) {
        return vphone_ios_version_supported();
    }

    // Do not require tfp0 just to pass the UI support gate. On vphone, tfp0 is
    // the bootstrap primitive we are about to initialize; requiring it here can
    // reject a supported 26.1-26.5 guest before vphone_bootstrap() gets to log
    // the real failure. settings_ensure_kexploit() below keeps this range on
    // the vphone path only and never falls back to the normal exploit.
    if (settings_ios_vphone_range()) return YES;

    BOOL ios17to18 =
        settings_compare_system_version(@"17.0") != NSOrderedAscending &&
        settings_compare_system_version(@"18.7.1") != NSOrderedDescending;

    BOOL ios26 =
        settings_compare_system_version(@"26.0") != NSOrderedAscending &&
        settings_compare_system_version(@"26.0.1") != NSOrderedDescending;

    if (ios17to18 || ios26) return YES;

    return NO;
}

NSString *settings_unsupported_message(void)
{
    if (settings_running_inside_livecontainer()) {
        return @"LiveContainer is not supported for applying Cyanide tweaks. Install Cyanide as a normal sideloaded app with AltStore, SideStore/Sideloadly, or TrollStore before running the chain.";
    }
    NSString *version = UIDevice.currentDevice.systemVersion ?: @"unknown";
    return [NSString stringWithFormat:@"Not supported on iOS %@. Supported: iOS/iPadOS 17.0-18.7.1, 26.0-26.0.1, or 26.1-26.5 (vphone).", version];
}

static void settings_progress(NSUInteger *step, NSUInteger total, const char *message)
{
    if (!step || !message) return;
    (*step)++;
    log_user("[RUN %lu/%lu] %s\n",
             (unsigned long)*step,
             (unsigned long)total,
             message);
}

BOOL settings_try_claim_actions_lock(const char *owner, const char *busyMessage)
{
    if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
        printf("[SETTINGS] %s blocked: actions already running\n",
               owner ?: "action");
        if (busyMessage) log_user("%s\n", busyMessage);
        return NO;
    }
    return YES;
}

void settings_release_actions_lock(void)
{
    __sync_lock_release(&g_settings_actions_running);
}

static NSString *settings_bundle_string(NSString *key, NSString *fallback)
{
    id value = [NSBundle mainBundle].infoDictionary[key];
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) {
        return value;
    }
    return fallback;
}

NSString *settings_app_version_string(void)
{
    return settings_bundle_string(@"CFBundleShortVersionString", @"unknown");
}

NSString *settings_app_build_string(void)
{
    return settings_bundle_string(@"CFBundleVersion", @"unknown");
}

static void settings_log_run_context(void)
{
    if (settings_running_inside_livecontainer()) {
        log_user("[RUN] LiveContainer environment detected; refusing to run kernel/tweak stages.\n");
    }
}

BOOL settings_ensure_kexploit(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] unsupported device: %s\n", settings_unsupported_message().UTF8String);
        return NO;
    }

    if (g_kexploit_done) {
        BOOL vphoneBridgeReady = settings_wait_for_vphone_springboard_bridge(2.0);
        BOOL ready = g_vphone_mode ? (vphone_krw_ready() || vphoneBridgeReady) : kexploit_krw_ready();
        if (ready) {
            log_user("[KRW] Reusing the live %s session; no exploit rerun needed.\n",
                     g_vphone_mode
                         ? (vphone_krw_ready() ? "vphone tfp0" : "vphone SpringBoard bridge")
                         : "app KRW");
            return YES;
        }
        printf("[SETTINGS] cached KRW is stale; clearing RemoteCall state and recovering\n");
        log_user("[KRW] Cached app KRW failed validation; clearing RemoteCall state and trying recovery.\n");
        g_kexploit_done = NO;
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
        kutils_reset_self_cache();
        settings_notify_remote_call_state_changed();
    }

    if (settings_ios_vphone_range()) {
        log_user("[VPHONE] Waiting for SpringBoard TweakLoader bridge after restart...\n");
        if (settings_wait_for_vphone_springboard_bridge(30.0)) {
            g_vphone_mode = true;
            g_kexploit_done = YES;
            log_user("[VPHONE] SpringBoard TweakLoader bridge ready — kernel r/w is not required for SpringBoard tweaks.\n");
            settings_notify_remote_call_state_changed();
            return YES;
        }

        printf("[SETTINGS] vphone SpringBoard bridge unavailable; refusing broken KRW fallback on iOS 26.1-26.5\n");
        log_user("[VPHONE] SpringBoard bridge unavailable — reboot/respring vphone and reinstall Cyanide. Refusing the broken vphone KRW fallback.\n");
        return NO;
    }

    if (vphone_is_available()) {
        if (!vphone_bootstrap()) {
            printf("[SETTINGS] vphone_bootstrap failed\n");
            return NO;
        }
        g_kexploit_done = YES;
        settings_notify_remote_call_state_changed();
        return YES;
    }

    int res = kexploit_opa334();
    if (res != 0) {
        printf("[SETTINGS] kexploit_opa334 failed: %d\n", res);
        return NO;
    }
    g_kexploit_done = YES;
    settings_notify_remote_call_state_changed();
    return YES;
}

BOOL settings_nano_load_override_enabled(void)
{
    if (!settings_device_supported()) return NO;
    return krw_persistence_launchd_holds_krw() || krw_persistence_has_saved_recovery();
}

BOOL settings_ensure_kexploit_recovery_only(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] unsupported device: %s\n", settings_unsupported_message().UTF8String);
        return NO;
    }

    if (g_kexploit_done) {
        if (kexploit_krw_ready() && krw_persistence_launchd_holds_krw()) {
            log_user("[KRW] Reusing parked/recovered KRW for NanoRegistry load.\n");
            return YES;
        }
        log_user("[KRW] NanoRegistry load requires parked KRW recovery; live state is not eligible.\n");
        return NO;
    }

    if (!krw_persistence_has_saved_recovery()) {
        log_user("[KRW] NanoRegistry load disabled: no parked KRW recovery state is saved.\n");
        return NO;
    }

    log_user("[KRW] NanoRegistry load: attempting parked recovery only; fresh spray is disabled for this button.\n");
    if (!krw_persistence_recover()) {
        log_user("[KRW] NanoRegistry load failed: parked KRW recovery was not available.\n");
        return NO;
    }

    g_kexploit_done = YES;
    settings_notify_remote_call_state_changed();
    return YES;
}

BOOL settings_ensure_springboard_remote_call_locked(void)
{
    if (g_springboard_rc_ready) {
        printf("[SETTINGS] reusing SpringBoard RemoteCall session\n");
        return YES;
    }

    if (settings_ios_vphone_range() && !settings_wait_for_vphone_springboard_bridge(30.0)) {
        printf("[SETTINGS] vphone SpringBoard bridge unavailable before RemoteCall init\n");
        return NO;
    }

    if (init_remote_call_with_first_exception_timeout("SpringBoard",
                                                      false,
                                                      kSettingsSpringBoardRCFirstExceptionTimeoutMS) != 0) {
        printf("[SETTINGS] init_remote_call(SpringBoard) failed\n");
        return NO;
    }

    g_springboard_rc_ready = 1;
    g_springboard_sandbox_escaped = 0;
    settings_notify_remote_call_state_changed();
    return YES;
}

static void settings_destroy_springboard_remote_call_locked_internal_ex(const char *reason, BOOL notifyState, BOOL preserveApplied)
{
    if (!g_springboard_rc_ready) return;

    printf("[SETTINGS] destroying SpringBoard RemoteCall session%s%s\n",
           reason ? ": " : "", reason ?: "");
    destroy_remote_call();
    g_springboard_rc_ready = 0;
    g_springboard_sandbox_escaped = 0;
    if (notifyState) settings_notify_remote_call_state_changed_preserving_applied(preserveApplied);
}

void settings_destroy_springboard_remote_call_locked_internal(const char *reason, BOOL notifyState)
{
    settings_destroy_springboard_remote_call_locked_internal_ex(reason, notifyState, NO);
}

static void settings_destroy_springboard_remote_call_locked(const char *reason)
{
    settings_destroy_springboard_remote_call_locked_internal(reason, YES);
}

void settings_prepare_for_respring_sync(void)
{
    log_user("[RESPRING] Stopping live sessions before respring.\n");
    printf("[SETTINGS] preparing for respring cleanup rcReady=%d\n", g_springboard_rc_ready);
    settings_request_all_live_loops_stop("pre-respring cleanup");
    settings_end_statbar_background_task_async("pre-respring cleanup");
    settings_wait_live_loops_stopped_for_switch("pre-respring cleanup");

    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            // SB is about to be killed by the respring, so cleanup uses the
            // fast variant for tweaks where full remote restoration is wasted.
            settings_stop_springboard_tweaks_locked("pre-respring cleanup", YES);
            settings_destroy_springboard_remote_call_locked("pre-respring cleanup");
        }
    }

    if (g_kexploit_done) {
        bool parked = kexploit_terminal_cleanup();
        printf("[SETTINGS] pre-respring terminal KRW cleanup parked=%d\n", parked);
        g_kexploit_done = NO;
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
        kutils_reset_self_cache();
        settings_notify_remote_call_state_changed();
    }

    log_user("[RESPRING] Cleanup complete. Opening respring flow.\n");
    usleep(300000);
}

static void settings_terminal_kexploit_cleanup_sync_internal(const char *reason)
{
    log_user("[CLEANUP] Tearing down live tweaks and releasing KRW state...\n");
    printf("[SETTINGS] terminal KRW cleanup requested%s%s done=%d rcReady=%d\n",
           reason ? ": " : "", reason ?: "",
           g_kexploit_done, g_springboard_rc_ready);
    settings_request_all_live_loops_stop("terminal KRW cleanup");
    settings_end_statbar_background_task_async("terminal KRW cleanup");
    settings_wait_live_loops_stopped_for_switch("terminal KRW cleanup");

    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            settings_stop_springboard_tweaks_locked("terminal cleanup", NO);
            settings_destroy_springboard_remote_call_locked(reason ?: "terminal KRW cleanup");
        } else {
            settings_forget_springboard_tweak_state_locked();
        }
    }

    if (!g_kexploit_done) {
        printf("[SETTINGS] terminal KRW cleanup skipped: no local KRW session\n");
        log_user("[CLEANUP] Nothing to clean up — no active KRW session.\n");
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
        kutils_reset_self_cache();
        settings_notify_remote_call_state_changed();
        return;
    }

    bool parked = kexploit_terminal_cleanup();
    printf("[SETTINGS] terminal KRW cleanup result parked=%d\n", parked);
    log_user("%s Clean Up complete. %s\n",
             parked ? "[OK]" : "[WARN]",
             parked ? "KRW parked — next Run will recover in seconds." : "KRW not parked — next Run will re-exploit.");
    g_kexploit_done = NO;
    g_springboard_rc_ready = 0;
    g_springboard_sandbox_escaped = 0;
    kutils_reset_self_cache();
    settings_notify_remote_call_state_changed();
}

static void settings_terminal_kexploit_cleanup_sync(const char *reason)
{
    settings_terminal_kexploit_cleanup_sync_internal(reason);
}

static BOOL settings_acquire_actions_lock_wait(const char *owner, uint64_t timeoutUS)
{
    uint64_t startUS = settings_now_us();
    BOOL loggedWait = NO;

    while (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
        if (!loggedWait) {
            printf("[SETTINGS] %s waiting for active action before cleanup\n",
                   owner ?: "cleanup");
            log_user("[CLEANUP] Run in progress — cleanup queued for when it finishes.\n");
            loggedWait = YES;
        }

        if (timeoutUS != 0) {
            uint64_t nowUS = settings_now_us();
            if (startUS != 0 && nowUS >= startUS && nowUS - startUS >= timeoutUS) {
                printf("[SETTINGS] %s timed out waiting for action lock\n",
                       owner ?: "cleanup");
                log_user("[CLEANUP] Timed out waiting for the current run to finish.\n");
                return NO;
            }
        }

        usleep(100000);
    }

    if (loggedWait) {
        uint64_t nowUS = settings_now_us();
        uint64_t waitedUS = (startUS != 0 && nowUS >= startUS) ? nowUS - startUS : 0;
        printf("[SETTINGS] %s acquired action lock after %lluus\n",
               owner ?: "cleanup", waitedUS);
    }
    return YES;
}

void settings_queue_terminal_kexploit_cleanup(const char *reason)
{
    if (__sync_lock_test_and_set(&g_settings_cleanup_running, 1)) {
        printf("[SETTINGS] terminal cleanup already queued/running%s%s\n",
               reason ? ": " : "", reason ?: "");
        log_user("[CLEANUP] Clean Up is already queued.\n");
        return;
    }
    settings_notify_cleanup_state_changed();

    settings_request_all_live_loops_stop("queued terminal cleanup");
    settings_end_statbar_background_task_async("queued terminal cleanup");

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL locked = settings_acquire_actions_lock_wait("terminal cleanup", 0);
        @try {
            settings_terminal_kexploit_cleanup_sync_internal(reason ?: "manual action");
        } @finally {
            if (locked) __sync_lock_release(&g_settings_actions_running);
            __sync_lock_release(&g_settings_cleanup_running);
            settings_notify_cleanup_state_changed();
        }
    });
}

void settings_best_effort_termination_cleanup(const char *reason)
{
    if (__sync_lock_test_and_set(&g_settings_termination_cleanup_started, 1)) {
        printf("[SETTINGS] termination cleanup already attempted%s%s\n",
               reason ? ": " : "", reason ?: "");
        return;
    }

    const char *why = reason ?: "app termination";
    log_user("[CLEANUP] App exiting (%s) — running last-chance teardown.\n", why);
    printf("[SETTINGS] best-effort termination cleanup requested: %s\n", why);

    if (!settings_has_active_termination_live_tweak()) {
        printf("[SETTINGS] termination cleanup skipped: no live tweaks active\n");
        log_user("[CLEANUP] No live tweaks active — nothing to tear down.\n");
        return;
    }

    settings_request_all_live_loops_stop("termination cleanup");

    BOOL locked = settings_acquire_actions_lock_wait("termination cleanup",
                                                     kSettingsTerminationCleanupWaitUS);
    if (!locked) {
        log_user("[CLEANUP] Last-chance cleanup skipped because another operation is still active.\n");
        return;
    }

    @try {
        settings_terminal_kexploit_cleanup_sync_internal(why);
    } @finally {
        __sync_lock_release(&g_settings_actions_running);
    }
}

void settings_destroy_springboard_remote_call_sync(void)
{
    settings_request_all_live_loops_stop("remote call sync cleanup");
    settings_end_statbar_background_task_async("remote call sync cleanup");
    settings_wait_live_loops_stopped_for_switch("remote call sync cleanup");
    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            settings_stop_springboard_tweaks_locked("remote call sync cleanup", NO);
        }
        settings_destroy_springboard_remote_call_locked("manual/sync cleanup");
    }
}

void settings_destroy_springboard_remote_call(void)
{
    settings_request_all_live_loops_stop("remote call cleanup");
    settings_end_statbar_background_task_async("remote call cleanup");
    log_user("[SESSION] Closing SpringBoard injection session...\n");
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        settings_wait_live_loops_stopped_for_switch("remote call cleanup");
        @synchronized (settings_rc_lock()) {
            BOOL hadSession = g_springboard_rc_ready != 0;
            if (g_springboard_rc_ready) {
                settings_stop_springboard_tweaks_locked("remote call cleanup", NO);
            }
            settings_destroy_springboard_remote_call_locked("manual cleanup");
            log_user(hadSession ? "[OK] SpringBoard channel closed — live tweaks stopped.\n" :
                                  "[SESSION] No active SpringBoard session to close.\n");
        }
    });
}

static bool settings_apply_sbc_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsSBCEnabled]) return false;

    return sbcustomizer_apply_in_session((int)[d integerForKey:kSettingsSBCDockIcons],
                                         (int)[d integerForKey:kSettingsSBCCols],
                                         (int)[d integerForKey:kSettingsSBCRows],
                                         [d boolForKey:kSettingsSBCHideLabels]);
}

NSString *settings_nicebar_key(NSString *prefix, NSInteger slot)
{
    return [NSString stringWithFormat:@"%@%ld", prefix, (long)slot];
}

NSString *settings_nicebar_slot_name(NSInteger slot)
{
    switch ((NiceBarLiteSlot)slot) {
        case NiceBarLiteSlotTopLeft: return @"Top Left";
        case NiceBarLiteSlotTopRight: return @"Top Right";
        case NiceBarLiteSlotBottomLeft: return @"Bottom Left";
        case NiceBarLiteSlotBottomRight: return @"Bottom Right";
        case NiceBarLiteSlotBottomCenter: return @"Bottom Center";
        case NiceBarLiteSlotCount: return @"Slot";
    }
    return @"Slot";
}

NSString *settings_nicebar_kind_name(NSInteger kind)
{
    switch ((NiceBarLiteContentKind)kind) {
        case NiceBarLiteContentOff: return @"Off";
        case NiceBarLiteContentCustomText: return @"Custom Text";
        case NiceBarLiteContentSystem: return @"System";
        case NiceBarLiteContentTimeFormat: return @"Date / Time";
        case NiceBarLiteContentWeather: return @"Weather";
    }
    return @"Off";
}

NSString *settings_nicebar_system_name(NSInteger item)
{
    switch ((NiceBarLiteSystemItem)item) {
        case NiceBarLiteSystemBatteryTemp: return @"Battery Temp";
        case NiceBarLiteSystemFreeRAM: return @"Free RAM";
        case NiceBarLiteSystemBatteryPercent: return @"Battery";
        case NiceBarLiteSystemNetworkSpeed: return @"Network Speed";
        case NiceBarLiteSystemUptime: return @"Uptime";
        case NiceBarLiteSystemDate: return @"Date";
        case NiceBarLiteSystemLunarDate: return @"Lunar Date";
        case NiceBarLiteSystemTodayTraffic: return @"Today Traffic";
        case NiceBarLiteSystemCurrentIP: return @"Current IP";
        case NiceBarLiteSystemFreeDisk: return @"Free Disk";
        case NiceBarLiteSystemThermalState: return @"Thermal State";
    }
    return @"System";
}

BOOL settings_nicebar_has_weather_slots(NSUserDefaults *d)
{
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        if (kind == NiceBarLiteContentWeather) return YES;
    }
    return NO;
}

NSString *settings_nicebar_weather_text_for_slot(NSUserDefaults *d, NSInteger slot)
{
    NSNumber *tempNumber = [d objectForKey:kSettingsNiceBarLiteWeatherTemp];
    NSNumber *codeNumber = [d objectForKey:kSettingsNiceBarLiteWeatherCode];
    if (![tempNumber isKindOfClass:NSNumber.class] || ![codeNumber isKindOfClass:NSNumber.class]) {
        return [d stringForKey:kSettingsNiceBarLiteWeatherCache] ?:
               [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, slot)] ?:
               @"Weather --";
    }

    NSString *language = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, slot)] ?: @"en";
    BOOL chinese = [language isEqualToString:@"zh"];
    NSString *summary = CyanideNiceBarWeatherSummary(codeNumber.integerValue, chinese);
    return [NSString stringWithFormat:@"%@ %.0f°", summary, tempNumber.doubleValue];
}

static BOOL settings_nicebar_has_resolved_weather(NSUserDefaults *d)
{
    NSNumber *tempNumber = [d objectForKey:kSettingsNiceBarLiteWeatherTemp];
    NSNumber *codeNumber = [d objectForKey:kSettingsNiceBarLiteWeatherCode];
    return [tempNumber isKindOfClass:NSNumber.class] &&
           [codeNumber isKindOfClass:NSNumber.class];
}

void settings_nicebar_update_weather_slot_texts(NSUserDefaults *d)
{
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        [d setObject:settings_nicebar_weather_text_for_slot(d, i)
              forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, i)];
    }
}

void settings_nicebar_store_weather_result(NSUserDefaults *d,
                                                  NSNumber *temp,
                                                  NSNumber *code,
                                                  NSString *fallbackText,
                                                  BOOL fetched)
{
    if ([temp isKindOfClass:NSNumber.class] && [code isKindOfClass:NSNumber.class]) {
        [d setObject:temp forKey:kSettingsNiceBarLiteWeatherTemp];
        [d setObject:code forKey:kSettingsNiceBarLiteWeatherCode];
        NSString *cache = [NSString stringWithFormat:@"%@ %.0f°",
                           CyanideNiceBarWeatherSummary(code.integerValue, NO),
                           temp.doubleValue];
        [d setObject:cache forKey:kSettingsNiceBarLiteWeatherCache];
    } else {
        NSString *resolved = fallbackText.length ? fallbackText : @"Weather --";
        [d setObject:resolved forKey:kSettingsNiceBarLiteWeatherCache];
    }

    [d setObject:[NSDate date] forKey:kSettingsNiceBarLiteWeatherLastAttemptAt];
    if (fetched) {
        [d setObject:[NSDate date] forKey:kSettingsNiceBarLiteWeatherUpdatedAt];
    }
    settings_nicebar_update_weather_slot_texts(d);
    [d synchronize];
}

NSString *settings_nsbar_position_name(NSInteger position)
{
    switch ((NSBarPosition)position) {
        case NSBarPositionTopLeft: return @"Top Left";
        case NSBarPositionBottomLeft: return @"Bottom Left";
        case NSBarPositionTopRight: return @"Top Right";
        case NSBarPositionBottomRight: return @"Bottom Right";
        case NSBarPositionCenter: return @"Center";
    }
    return @"Top Left";
}

NSString *settings_livewp_video_detail(void)
{
    NSString *path = livewp_absolute_path();
    if (path.length == 0) return @"No video selected.";
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (attrs) {
        unsigned long long bytes = [attrs fileSize];
        NSByteCountFormatter *fmt = [[NSByteCountFormatter alloc] init];
        fmt.allowedUnits = NSByteCountFormatterUseMB | NSByteCountFormatterUseGB;
        fmt.countStyle = NSByteCountFormatterCountStyleFile;
        return [NSString stringWithFormat:@"%@ (%@)", path.lastPathComponent, [fmt stringFromByteCount:(long long)bytes]];
    }
    return [NSString stringWithFormat:@"%@ (missing)", path.lastPathComponent ?: path];
}

static NiceBarLiteConfig settings_nicebar_config_from_defaults(NSUserDefaults *d)
{
    NiceBarLiteConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.celsius = [d boolForKey:kSettingsNiceBarLiteCelsius];
    cfg.topSideInsetOffset = [d integerForKey:kSettingsNiceBarLiteLayoutTopSideInset];
    cfg.bottomSideInsetOffset = [d integerForKey:kSettingsNiceBarLiteLayoutBottomSideInset];
    cfg.topYOffset = [d integerForKey:kSettingsNiceBarLiteLayoutTopY];
    cfg.bottomYOffset = [d integerForKey:kSettingsNiceBarLiteLayoutBottomY];
    cfg.centerXOffset = [d integerForKey:kSettingsNiceBarLiteLayoutCenterX];
    cfg.updateMask = UINT32_MAX;

    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        NSString *text = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, i)] ?: @"";
        NSString *time = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, i)] ?: @"HH:mm";
        NSString *weather = settings_nicebar_weather_text_for_slot(d, i);
        NSString *language = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, i)] ?: @"en";
        cfg.slots[i].kind = (int)[d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        cfg.slots[i].systemItem = (int)[d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)];
        cfg.slots[i].customText = text.UTF8String;
        cfg.slots[i].timeFormat = time.UTF8String;
        cfg.slots[i].weatherText = weather.UTF8String;
        cfg.slots[i].systemLanguage = language.UTF8String;
    }
    return cfg;
}

bool settings_apply_nicebarlite_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsNiceBarLiteEnabled]) return false;
    return nicebarlite_apply_in_session(settings_nicebar_config_from_defaults(d));
}

static void settings_nicebar_schedule_apply_after_weather_update(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if (![d boolForKey:kSettingsNiceBarLiteEnabled] || !g_springboard_rc_ready) return;
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsNiceBarLiteEnabled] ||
                !g_springboard_rc_ready) {
                return;
            }
            bool ok = settings_apply_nicebarlite_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled, ok);
            printf("[SETTINGS] NiceBar Lite weather refresh apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

static volatile int g_nicebarlite_weather_refresh_requested = 0;

void settings_nicebar_refresh_weather_if_needed(BOOL force,
                                                       void (^completion)(BOOL ok, NSString *text))
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_nicebar_has_weather_slots(d)) {
        if (force || completion) {
            log_user("[NICEBAR] Weather refresh skipped: no weather slot configured.\n");
        }
        if (completion) completion(NO, [d stringForKey:kSettingsNiceBarLiteWeatherCache] ?: @"");
        return;
    }

    BOOL hasResolvedWeather = settings_nicebar_has_resolved_weather(d);
    NSTimeInterval retryInterval = hasResolvedWeather ? kNiceBarLiteWeatherRefreshInterval : 60.0;
    if (!force && completion == nil) {
        NSDate *lastAttempt = [d objectForKey:kSettingsNiceBarLiteWeatherLastAttemptAt];
        if ([lastAttempt isKindOfClass:NSDate.class] &&
            [[NSDate date] timeIntervalSinceDate:lastAttempt] < retryInterval) {
            return;
        }
    }
    if (!force && completion == nil &&
        !__sync_bool_compare_and_swap(&g_nicebarlite_weather_refresh_requested, 0, 1)) {
        return;
    }

    [d setObject:[NSDate date] forKey:kSettingsNiceBarLiteWeatherLastAttemptAt];
    [d synchronize];
    log_user("[NICEBAR] Weather refresh requested force=%d cached=%d.\n",
             force ? 1 : 0,
             hasResolvedWeather ? 1 : 0);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[CyanideNiceBarWeatherRefresher sharedRefresher]
            refreshWeatherForce:force
                      useCelsius:[d boolForKey:kSettingsNiceBarLiteCelsius]
                      completion:^(BOOL ok, NSString *text, NSNumber *temp, NSNumber *code, BOOL fetched) {
            __sync_lock_release(&g_nicebarlite_weather_refresh_requested);
            NSUserDefaults *innerDefaults = [NSUserDefaults standardUserDefaults];
            if (fetched || force) {
                settings_nicebar_store_weather_result(innerDefaults, temp, code, text, ok);
            }
            if (fetched || force || completion) {
                log_user("[NICEBAR] Weather refresh finished ok=%d fetched=%d text=%s temp=%s code=%s\n",
                         ok ? 1 : 0,
                         fetched ? 1 : 0,
                         text.UTF8String ?: "(nil)",
                         temp ? temp.stringValue.UTF8String : "(nil)",
                         code ? code.stringValue.UTF8String : "(nil)");
            }
            if ((fetched || force) &&
                [innerDefaults boolForKey:kSettingsNiceBarLiteEnabled] &&
                g_springboard_rc_ready) {
                settings_nicebar_schedule_apply_after_weather_update();
            }
            if (completion) completion(ok, text);
        }];
    });
}

static BOOL settings_dark_tweaks_any_enabled(NSUserDefaults *d)
{
    return [d boolForKey:kSettingsDSDisableAppLibrary] ||
           [d boolForKey:kSettingsDSDisableIconFlyIn] ||
           [d boolForKey:kSettingsDSZeroWakeAnimation] ||
           [d boolForKey:kSettingsDSZeroBacklightFade] ||
           [d boolForKey:kSettingsDSDoubleTapToLock];
}

static BOOL settings_enabled_tweak_should_run(NSUserDefaults *d, NSString *key, BOOL pendingOnly)
{
    if (![d boolForKey:key]) return NO;
    return !pendingOnly || !settings_tweak_is_applied(key);
}

static NSTimeInterval settings_current_boot_epoch_seconds(void)
{
    struct timeval boottime;
    size_t len = sizeof(boottime);
    memset(&boottime, 0, sizeof(boottime));
    if (sysctlbyname("kern.boottime", &boottime, &len, NULL, 0) == 0 &&
        boottime.tv_sec > 0) {
        return (NSTimeInterval)boottime.tv_sec;
    }

    return [[NSDate date] timeIntervalSince1970] -
           [[NSProcessInfo processInfo] systemUptime];
}

static BOOL settings_hide_home_bar_materialkit_zero_active(NSUserDefaults *d)
{
    NSTimeInterval storedBoot = [d doubleForKey:kSettingsHideHomeBarMaterialKitBootTime];
    if (storedBoot <= 0.0) return NO;

    NSTimeInterval currentBoot = settings_current_boot_epoch_seconds();
    if (currentBoot <= 0.0) return YES;
    if (fabs(currentBoot - storedBoot) > 120.0) {
        // The MaterialKit page zero is memory-backed/transient; a reboot
        // restores the asset catalog, so stale conflict state can be dropped.
        [d removeObjectForKey:kSettingsHideHomeBarMaterialKitBootTime];
        [d synchronize];
        return NO;
    }
    return YES;
}

static void settings_note_hide_home_bar_materialkit_zero_active(NSUserDefaults *d)
{
    [d setDouble:settings_current_boot_epoch_seconds()
          forKey:kSettingsHideHomeBarMaterialKitBootTime];
    [d synchronize];
}

BOOL settings_hide_home_bar_respring_pending(void)
{
    return settings_hide_home_bar_materialkit_zero_active(NSUserDefaults.standardUserDefaults);
}

void settings_present_hide_home_bar_respring_prompt(UIViewController *host)
{
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Respring to Hide Home Bar?"
                         message:@"Hide Home Bar was applied, but SpringBoard needs to restart before the home indicator disappears."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Later"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    __weak UIViewController *weakHost = host;
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *_) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
                printf("[SETTINGS] hide home bar respring blocked: actions already running\n");
                log_user("[RESPRING] Another action is still running. Try Respring again in a moment.\n");
                return;
            }

            __sync_lock_test_and_set(&g_settings_respring_cleanup_running, 1);
            settings_notify_cleanup_state_changed();
            @try {
                settings_prepare_for_respring_sync();
            } @finally {
                __sync_lock_release(&g_settings_actions_running);
                __sync_lock_release(&g_settings_respring_cleanup_running);
                settings_notify_cleanup_state_changed();
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                settings_show_respring_overlay(weakHost);
            });
        });
    }]];
    settings_present_controller(ac, host);
}

static BOOL settings_dark_tweaks_should_run(NSUserDefaults *d, BOOL pendingOnly)
{
    NSArray<NSString *> *keys = @[
        kSettingsDSDisableAppLibrary,
        kSettingsDSDisableIconFlyIn,
        kSettingsDSZeroWakeAnimation,
        kSettingsDSZeroBacklightFade,
        kSettingsDSDoubleTapToLock,
        kSettingsDSDragCoefficientEnabled,
    ];
    for (NSString *key in keys) {
        if (settings_enabled_tweak_should_run(d, key, pendingOnly)) return YES;
    }
    return NO;
}

typedef struct {
    bool any;
    bool disableAppLibrary;
    bool disableIconFlyIn;
    bool zeroWakeAnimation;
    bool zeroBacklightFade;
    bool doubleTapToLock;
    bool dragCoefficient;
} SettingsDarkTweaksResult;

static bool settings_dark_tweaks_result_all_ok(SettingsDarkTweaksResult result)
{
    return result.any &&
           result.disableAppLibrary &&
           result.disableIconFlyIn &&
           result.zeroWakeAnimation &&
           result.zeroBacklightFade &&
           result.doubleTapToLock &&
           result.dragCoefficient;
}

static SettingsDarkTweaksResult settings_apply_dark_tweaks_from_defaults_locked(NSUserDefaults *d)
{
    BOOL disableAppLibrary = [d boolForKey:kSettingsDSDisableAppLibrary];
    BOOL disableIconFlyIn = [d boolForKey:kSettingsDSDisableIconFlyIn];
    BOOL zeroWakeAnimation = [d boolForKey:kSettingsDSZeroWakeAnimation];
    BOOL zeroBacklightFade = [d boolForKey:kSettingsDSZeroBacklightFade];
    BOOL doubleTapToLock = [d boolForKey:kSettingsDSDoubleTapToLock];
    BOOL dragCoefficientEnabled = [d boolForKey:kSettingsDSDragCoefficientEnabled];
    SettingsDarkTweaksResult result = {
        .disableAppLibrary = true,
        .disableIconFlyIn = true,
        .zeroWakeAnimation = true,
        .zeroBacklightFade = true,
        .doubleTapToLock = true,
        .dragCoefficient = true,
    };

    printf("[DST] apply appLib=%d flyIn=%d wake=%d backlight=%d dblTap=%d drag=%d\n",
           disableAppLibrary,
           disableIconFlyIn,
           zeroWakeAnimation,
           zeroBacklightFade,
           doubleTapToLock,
           dragCoefficientEnabled);

    if (disableAppLibrary) {
        result.any = true;
        result.disableAppLibrary = darksword_tweak_disable_app_library_in_session();
    }
    if (disableIconFlyIn) {
        result.any = true;
        result.disableIconFlyIn = darksword_tweak_disable_icon_fly_in_in_session();
    }
    if (zeroWakeAnimation) {
        result.any = true;
        result.zeroWakeAnimation = darksword_tweak_zero_wake_animation_in_session();
    }
    if (zeroBacklightFade) {
        result.any = true;
        result.zeroBacklightFade = darksword_tweak_zero_backlight_fade_in_session();
    }
    if (doubleTapToLock) {
        result.any = true;
        result.doubleTapToLock = darksword_tweak_double_tap_to_lock_in_session();
    }
    if (dragCoefficientEnabled) {
        result.any = true;
        result.dragCoefficient = darksword_drag_coefficient_apply(settings_drag_coefficient_value(d));
    }
    return result;
}

static bool settings_apply_layout_extras_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsLayoutExtrasEnabled]) return false;
    double exL  = (double)[d integerForKey:kSettingsLayoutHomeExtraLeft];
    double exR  = (double)[d integerForKey:kSettingsLayoutHomeExtraRight];
    double exT  = (double)[d integerForKey:kSettingsLayoutHomeExtraTop];
    double exB  = (double)[d integerForKey:kSettingsLayoutHomeExtraBottom];
    double dockExH = (double)[d integerForKey:kSettingsLayoutDockExtraHorizontal];
    NSInteger hsPct = [d integerForKey:kSettingsLayoutHomeScalePct];
    NSInteger dkPct = [d integerForKey:kSettingsLayoutDockScalePct];
    double homeScale = (hsPct > 0) ? (double)hsPct / 100.0 : 1.0;
    double dockScale = (dkPct > 0) ? (double)dkPct / 100.0 : 1.0;
    return darksword_layout_apply_in_session(exL, exR, exT, exB, dockExH, homeScale, dockScale);
}

GravityLiteConfig settings_gravitylite_config_from_defaults(NSUserDefaults *d)
{
    NSInteger magnitudePct = [d integerForKey:kSettingsGravityLiteMagnitudePct];
    NSInteger bouncePct = [d integerForKey:kSettingsGravityLiteBouncePct];
    NSInteger frictionPct = [d integerForKey:kSettingsGravityLiteFrictionPct];
    NSInteger resistancePct = [d integerForKey:kSettingsGravityLiteResistancePct];
    NSInteger angularResistancePct = [d integerForKey:kSettingsGravityLiteAngularResistancePct];
    if (magnitudePct <= 0) magnitudePct = 100;
    if (resistancePct < 0) resistancePct = 0;
    if (angularResistancePct < 0) angularResistancePct = 0;

    GravityLiteConfig config = {
        .includeDock = [d boolForKey:kSettingsGravityLiteDockEnabled],
        .allowsRotation = true,
        .magnitude = (double)magnitudePct / 45.0,
        .bounce = (double)bouncePct / 100.0,
        .friction = (double)frictionPct / 100.0,
        .resistance = (double)resistancePct / 100.0,
        .angularResistance = (double)angularResistancePct / 100.0,
        .explosionForce = 7.0,
    };
    return config;
}

static bool settings_apply_gravitylite_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsGravityLiteEnabled]) return false;
    return gravitylite_apply_in_session(settings_gravitylite_config_from_defaults(d));
}

double settings_fastlockx_lite_retry_interval(NSUserDefaults *d)
{
    id raw = [d objectForKey:kSettingsFastLockXLiteRetryInterval];
    double value = [raw respondsToSelector:@selector(doubleValue)] ? [raw doubleValue] : 0.3;
    if (!isfinite(value) || value <= 0.0) value = 0.3;
    if (value < 0.1) value = 0.1;
    if (value > 2.0) value = 2.0;
    return value;
}

FastLockXLiteConfig settings_fastlockx_lite_config_from_defaults(NSUserDefaults *d,
                                                                        BOOL pulse,
                                                                        BOOL unlock)
{
    FastLockXLiteConfig config = {
        .pulseBiometricRetry = pulse,
        .attemptUnlock = unlock,
        // Blockers are UI-disabled for now; keep the backend behavior aligned
        // so stale saved defaults don't silently change unlock behavior.
        .blockOnMusic = false,
        .blockOnFlashlight = false,
        .blockOnLowPowerMode = false,
        .diagnosticLogging = YES,
        .retryIntervalSeconds = settings_fastlockx_lite_retry_interval(d),
    };
    return config;
}

static void settings_restart_gravity_motion_if_active(const char *reason)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsGravityLiteEnabled]) return;
    if (!settings_tweak_is_applied(kSettingsGravityLiteEnabled)) return;
    if (!g_springboard_rc_ready || settings_cleanup_in_progress()) return;
    if (!settings_screen_awake_cached() || settings_screen_locked_cached()) return;
    if (g_gravity_motion_stop_requested == 0 && g_gravity_motion_manager) return;

    GravityLiteConfig config = settings_gravitylite_config_from_defaults(d);
    settings_start_gravity_motion(config.magnitude, config.explosionForce);
    printf("[GRAVITY] accelerometer loop restarted%s%s\n",
           reason ? ": " : "", reason ?: "");
}

static bool settings_arm_gravitylite_for_background_start_locked(NSUserDefaults *d,
                                                                 const char *reason)
{
    if (![d boolForKey:kSettingsGravityLiteEnabled]) return false;
    bool stopped = gravitylite_stop_in_session();
    __sync_lock_test_and_set(&g_gravitylite_background_armed, 1);
    settings_mark_tweak_applied(kSettingsGravityLiteEnabled, YES);
    printf("[SETTINGS] Gravity Lite armed for background start%s%s stop=%d\n",
           reason ? ": " : "", reason ?: "", stopped);
    return true;
}

static BOOL settings_gravitylite_start_window_ready(const char *reason)
{
    (void)settings_refresh_screen_awake_state(reason ?: "gravity start");
    (void)settings_refresh_screen_lock_state(reason ?: "gravity start");
    return settings_screen_awake_cached() && !settings_screen_locked_cached();
}

static void settings_apply_armed_gravitylite_once_async(const char *reason)
{
    if (g_gravitylite_start_worker_running != 0) {
        printf("[SETTINGS] Gravity async dispatch already running\n");
        return;
    }
    if (g_gravitylite_background_armed == 0) {
        printf("[SETTINGS] Gravity armed check failed: wasArmed=0\n");
        return;
    }
    if (settings_cleanup_in_progress()) {
        printf("[SETTINGS] Gravity skipped: cleanup in progress\n");
        return;
    }
    if (__sync_lock_test_and_set(&g_gravitylite_start_worker_running, 1)) {
        printf("[SETTINGS] Gravity async dispatch already running\n");
        return;
    }
    printf("[SETTINGS] Gravity async dispatch starting%s%s\n",
           reason ? ": " : "", reason ?: "");

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            printf("[SETTINGS] Gravity async worker entered state=%ld armed=%d rcReady=%d\n",
                   (long)[UIApplication sharedApplication].applicationState,
                   g_gravitylite_background_armed,
                   g_springboard_rc_ready);
            uint64_t waitDeadline = settings_now_us() + 30000000ULL;
            while (!settings_cleanup_in_progress() &&
                   g_gravitylite_background_armed != 0 &&
                   [d boolForKey:kSettingsGravityLiteEnabled] &&
                   g_springboard_rc_ready &&
                   !settings_gravitylite_start_window_ready(reason ?: "gravity start")) {
                if (settings_now_us() >= waitDeadline) {
                    printf("[SETTINGS] Gravity async dispatch waiting for app exit timed out\n");
                    return;
                }
                usleep(50000);
            }

            if (settings_cleanup_in_progress()) return;
            if (![d boolForKey:kSettingsGravityLiteEnabled] || !g_springboard_rc_ready) return;
            if (!settings_gravitylite_start_window_ready(reason ?: "gravity start")) return;

            bool ok = false;
            GravityLiteConfig appliedConfig = {0};
            uint64_t applyDeadline = settings_now_us() + 2000000ULL;
            int attempt = 0;
            do {
                usleep(80000);
                printf("[SETTINGS] Gravity async apply waiting for RemoteCall lock attempt=%d armed=%d state=%ld\n",
                       attempt + 1,
                       g_gravitylite_background_armed,
                       (long)[UIApplication sharedApplication].applicationState);
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        !g_springboard_rc_ready ||
                        ![d boolForKey:kSettingsGravityLiteEnabled] ||
                        !settings_gravitylite_start_window_ready(reason ?: "gravity start")) {
                        return;
                    }
                    if (!__sync_bool_compare_and_swap(&g_gravitylite_background_armed, 1, 0) && attempt == 0) {
                        printf("[SETTINGS] Gravity armed check failed inside worker: wasArmed=%d\n",
                               g_gravitylite_background_armed);
                        return;
                    }
                    appliedConfig = settings_gravitylite_config_from_defaults(d);
                    printf("[SETTINGS] Gravity async apply attempt=%d begin\n", attempt + 1);
                    ok = gravitylite_apply_in_session(appliedConfig);
                    printf("[SETTINGS] Gravity async apply attempt=%d result=%d\n", attempt + 1, ok);
                    settings_mark_tweak_applied(kSettingsGravityLiteEnabled,
                                                ok && [d boolForKey:kSettingsGravityLiteEnabled]);
                }
                if (ok) break;
                attempt++;
                usleep(120000);
            } while (settings_now_us() < applyDeadline);

            if (ok) {
                settings_start_gravity_motion(appliedConfig.magnitude,
                                              appliedConfig.explosionForce);
                log_user("[OK] Gravity Lite active.\n");
                cyanide_upload_log_milestone(@"gravity-lite-applied");
            } else {
                log_user("[WARN] Gravity Lite did not start cleanly.\n");
                cyanide_upload_log_milestone(@"gravity-lite-warning");
            }

            printf("[SETTINGS] Gravity Lite start%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
            settings_notify_package_queue_changed_async();
        } @finally {
            __sync_lock_release(&g_gravitylite_start_worker_running);
        }
    });
}

NSString * const kThemerThemeNone = @"";
NSString * const kThemerThemeBuiltinIOS6 = @"builtin-ios6";
NSString * const kThemerThemeCustom = @"custom";

static NSString *settings_themer_builtin_ios6_path(void)
{
    return [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Themes-iOS6.plist"];
}

NSString *settings_themer_documents_theme_root(void)
{
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count == 0) return nil;
    return [docs.firstObject stringByAppendingPathComponent:@"Themes"];
}

NSString *settings_themer_imported_theme_dir(void)
{
    NSString *root = settings_themer_documents_theme_root();
    return root ? [root stringByAppendingPathComponent:@"Imported"] : nil;
}

NSString *settings_themer_imported_plist_path(void)
{
    NSString *root = settings_themer_documents_theme_root();
    return root ? [root stringByAppendingPathComponent:@"Imported.plist"] : nil;
}

static NSString *settings_themer_selected_theme_id(void)
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kSettingsThemerThemeID] ?: kThemerThemeNone;
}

BOOL settings_themer_has_selected_theme(void)
{
    NSString *theme = settings_themer_selected_theme_id();
    if ([theme isEqualToString:kThemerThemeBuiltinIOS6]) {
        return [[NSFileManager defaultManager] fileExistsAtPath:settings_themer_builtin_ios6_path()];
    }
    if ([theme isEqualToString:kThemerThemeCustom]) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSString *path = [d stringForKey:kSettingsThemerCustomThemePath];
        BOOL isDir = NO;
        return path.length > 0 &&
               [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    }
    return NO;
}

NSString *settings_themer_selected_theme_display_name(void)
{
    NSString *theme = settings_themer_selected_theme_id();
    if ([theme isEqualToString:kThemerThemeBuiltinIOS6]) return @"iOS 6 Theme";
    if ([theme isEqualToString:kThemerThemeCustom]) {
        NSString *name = [[NSUserDefaults standardUserDefaults]
            stringForKey:kSettingsThemerCustomThemeName];
        return name.length > 0 ? name : @"Imported Theme";
    }
    return @"None";
}

NSDictionary<NSString *, NSData *> *settings_themer_load_plist_theme(NSString *plistPath)
{
    NSError *err = nil;
    NSData *raw = [NSData dataWithContentsOfFile:plistPath options:0 error:&err];
    if (!raw) {
        printf("[THEMER] resolve: failed to read plist err=%s\n",
               err.localizedDescription.UTF8String ?: "?");
        return nil;
    }
    id parsed = [NSPropertyListSerialization
        propertyListWithData:raw
                     options:NSPropertyListImmutable
                      format:NULL
                       error:&err];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        printf("[THEMER] resolve: plist parse failed err=%s\n",
               err.localizedDescription.UTF8String ?: "?");
        return nil;
    }
    NSDictionary *dict = (NSDictionary *)parsed;
    NSMutableDictionary<NSString *, NSData *> *out = [NSMutableDictionary dictionary];
    for (id key in dict) {
        id value = dict[key];
        if (![key isKindOfClass:NSString.class] ||
            ![value isKindOfClass:NSData.class] ||
            [(NSData *)value length] == 0) {
            continue;
        }
        out[key] = value;
    }
    printf("[THEMER] resolve: loaded plist theme entries=%lu size=%lu path=%s\n",
           (unsigned long)out.count,
           (unsigned long)raw.length,
           plistPath.UTF8String);
    return out;
}

// Per-bundle icon swap. A theme must be selected explicitly: either the bundled
// iOS 6 plist, or an imported folder/plist in Documents/Themes/.
static bool settings_apply_themer_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsThemerEnabled]) {
        printf("[THEMER] resolve: toggle off, skipping\n");
        return false;
    }

    NSString *theme = settings_themer_selected_theme_id();
    if (![theme isEqualToString:kThemerThemeBuiltinIOS6] &&
        ![theme isEqualToString:kThemerThemeCustom]) {
        printf("[THEMER] resolve: no selected theme; install/apply blocked\n");
        log_user("[THEMER] Pick a theme in SnowBoard Lite settings before running.\n");
        return false;
    }

    if ([theme isEqualToString:kThemerThemeBuiltinIOS6]) {
        NSString *plistPath = settings_themer_builtin_ios6_path();
        if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
            printf("[THEMER] resolve: bundled plist missing at %s\n",
                   plistPath.UTF8String);
            return false;
        }
        NSDictionary *dict = settings_themer_load_plist_theme(plistPath);
        return dict.count > 0 ? themer_apply_data_in_session(dict) : false;
    }

    NSString *path = [d stringForKey:kSettingsThemerCustomThemePath];
    BOOL isDir = NO;
    if (path.length == 0 ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        printf("[THEMER] resolve: selected custom theme missing path=%s\n",
               path.UTF8String ?: "");
        return false;
    }
    if (isDir) {
        printf("[THEMER] resolve: using imported folder %s\n", path.UTF8String);
        return themer_apply_in_session(path.fileSystemRepresentation);
    }
    NSDictionary *dict = settings_themer_load_plist_theme(path);
    return dict.count > 0 ? themer_apply_data_in_session(dict) : false;
}

void settings_reset_sbc_defaults(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] SBC reset blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:YES forKey:kSettingsSBCEnabled];
    [d setInteger:kSBCDefaultDockIcons forKey:kSettingsSBCDockIcons];
    [d setInteger:kSBCDefaultCols forKey:kSettingsSBCCols];
    [d setInteger:kSBCDefaultRows forKey:kSettingsSBCRows];
    [d setBool:kSBCDefaultHideLabels forKey:kSettingsSBCHideLabels];
    [d synchronize];

    printf("[SETTINGS] SBC reset defaults dock=%ld hs=%ldx%ld hideLabels=%d rcReady=%d\n",
           (long)kSBCDefaultDockIcons,
           (long)kSBCDefaultCols,
           (long)kSBCDefaultRows,
           kSBCDefaultHideLabels,
           g_springboard_rc_ready);

    if (!g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @synchronized (settings_rc_lock()) {
            if (!g_springboard_rc_ready) return;
            bool ok = settings_apply_sbc_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsSBCEnabled,
                                        ok && [d boolForKey:kSettingsSBCEnabled]);
            printf("[SETTINGS] SBC reset apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

static bool settings_apply_ota_disabled_body(BOOL disable)
{
    if (!settings_ensure_kexploit()) {
        printf("[OTA] kernel primitives were not acquired\n");
        log_user("[OTA] Failed: kernel primitives were not acquired. Please try running chain again.\n");
        return false;
    }

    bool ok = darksword_ota_set_disabled(disable);

    settings_notify_package_queue_changed_async();
    return ok;
}

BOOL settings_apply_ota_disabled(BOOL disable)
{
    if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
        printf("[SETTINGS] actions already running; ignoring OTA request\n");
        log_user("[OTA] Another action is already running.\n");
        return NO;
    }
    @try {
        return settings_apply_ota_disabled_body(disable);
    } @finally {
        __sync_lock_release(&g_settings_actions_running);
    }
}

void settings_run_ota_action(BOOL disable)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        log_user("[OTA] %s OTA updates.\n", disable ? "Disabling" : "Enabling");
        bool ok = settings_apply_ota_disabled(disable);
        printf("[SETTINGS] OTA %s result=%d\n", disable ? "disable" : "enable", ok);
        if (ok) {
            log_user("[OK] OTA updates %s. Respring or reboot required for changes to take effect.\n",
                     disable ? "disabled" : "enabled");
        } else {
            log_user("[FAIL] OTA %s failed — see log for [OTA] lines (likely sandbox patch or disabled.plist write).\n",
                     disable ? "disable" : "enable");
        }
    });
}

void settings_nano_set_defaults_values(NSInteger maxV, NSInteger minV, NSInteger minChipV, NSInteger minQuickV)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:maxV     forKey:kSettingsNanoMaxPairing];
    [d setInteger:minV     forKey:kSettingsNanoMinPairing];
    [d setInteger:minChipV forKey:kSettingsNanoMinPairingChipID];
    [d setInteger:minQuickV forKey:kSettingsNanoMinQuickSwitch];
}

void settings_nano_load_from_plist_into_defaults(BOOL logResult)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    nano_registry_values values = {
        .max_pairing         = (int)[d integerForKey:kSettingsNanoMaxPairing],
        .min_pairing         = (int)[d integerForKey:kSettingsNanoMinPairing],
        .min_pairing_chip_id = (int)[d integerForKey:kSettingsNanoMinPairingChipID],
        .min_quick_switch    = (int)[d integerForKey:kSettingsNanoMinQuickSwitch],
    };
    bool present = false;
    bool ok = nano_registry_load(&values, &present);
    if (!ok) {
        if (logResult) log_user("[NANO] Could not read existing override plist (parse failure).\n");
        return;
    }
    [d setInteger:values.max_pairing         forKey:kSettingsNanoMaxPairing];
    [d setInteger:values.min_pairing         forKey:kSettingsNanoMinPairing];
    [d setInteger:values.min_pairing_chip_id forKey:kSettingsNanoMinPairingChipID];
    [d setInteger:values.min_quick_switch    forKey:kSettingsNanoMinQuickSwitch];
    if (logResult) {
        log_user(present
                 ? "[NANO] Loaded existing override: max=%d min=%d minChip=%d minQuick=%d.\n"
                 : "[NANO] No override present on device. Editor populated with current/seed values.\n",
                 values.max_pairing, values.min_pairing,
                 values.min_pairing_chip_id, values.min_quick_switch);
    }
}

// Synchronous entry point used by both the Settings UI buttons and the
// Installer's PackageQueue commit path. Logs progress to the in-app log so
// the InstallProgressViewController shows real lines during the apply.
BOOL settings_apply_nano_registry_now(BOOL apply)
{
    if (!settings_try_claim_actions_lock("NanoRegistry apply",
                                         "[NANO] Another action is already running.")) {
        return NO;
    }

    @try {
        if (!settings_ensure_kexploit()) {
            log_user("[NANO] Failed: kernel primitives were not acquired. Please try running chain again.\n");
            return NO;
        }

        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        bool ok;
        nano_registry_values values = {
            .max_pairing         = (int)[d integerForKey:kSettingsNanoMaxPairing],
            .min_pairing         = (int)[d integerForKey:kSettingsNanoMinPairing],
            .min_pairing_chip_id = (int)[d integerForKey:kSettingsNanoMinPairingChipID],
            .min_quick_switch    = (int)[d integerForKey:kSettingsNanoMinQuickSwitch],
        };
        if (apply) {
            log_user("[NANO] Applying pairing override max=%d min=%d minChip=%d minQuick=%d.\n",
                     values.max_pairing, values.min_pairing,
                     values.min_pairing_chip_id, values.min_quick_switch);
            ok = nano_registry_apply(&values);
            if (!ok) {
                log_user("[FAIL] NanoRegistry override write failed — see log for [NANO] lines.\n");
            }
        } else {
            log_user("[NANO] Removing pairing override keys.\n");
            ok = nano_registry_clear();
            if (!ok) {
                log_user("[FAIL] NanoRegistry override clear failed — see log for [NANO] lines.\n");
            }
        }

        // The file write above is necessary but not sufficient — cfprefsd owns
        // the in-memory cache that every CFPreferencesCopyValue call serves
        // from, and it will overwrite our plist with its stale cache the next
        // time any process writes to com.apple.NanoRegistry via the API. Push
        // the same values into cfprefsd's cache so the cache *has* our
        // override and future serializations preserve it.
        if (ok) {
            bool pushed = nano_registry_push_to_cfprefsd(&values, apply ? true : false);
            if (!pushed) {
                log_user("[NANO] cfprefsd push failed; on-disk override may be overwritten by cfprefsd's stale cache.\n");
            }
        }

        return ok ? YES : NO;
    } @finally {
        settings_release_actions_lock();
    }
}

BOOL settings_apply_call_recording_sound_disabled(BOOL disabled)
{
    if (!settings_try_claim_actions_lock("CallRec sound apply",
                                         "[CALLREC] Another action is already running.")) {
        return NO;
    }

    @try {
        if (!settings_ensure_kexploit()) {
            log_user("[CALLREC] Failed: kernel primitives were not acquired. Please try running chain again.\n");
            return NO;
        }
        return call_recording_sound_set_disabled(disabled) ? YES : NO;
    } @finally {
        settings_release_actions_lock();
    }
}

BOOL settings_apply_hide_home_bar_hidden(BOOL hidden)
{
    if (!settings_try_claim_actions_lock("Hide Home Bar apply",
                                         "[HOME BAR] Another action is already running.")) {
        return NO;
    }

    @try {
        if (!hidden) {
            return hide_home_bar_restore() ? YES : NO;
        }
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if (!settings_ensure_kexploit()) {
            log_user("[HOME BAR] Failed: kernel primitives were not acquired. Please try running chain again.\n");
            return NO;
        }
        BOOL ok = hide_home_bar_apply() ? YES : NO;
        if (ok) settings_note_hide_home_bar_materialkit_zero_active(d);
        return ok;
    } @finally {
        settings_release_actions_lock();
    }
}

void settings_run_nano_apply_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        (void)settings_apply_nano_registry_now(YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

void settings_run_nano_clear_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        (void)settings_apply_nano_registry_now(NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

void settings_run_nano_probe_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!settings_try_claim_actions_lock("NanoRegistry probe",
                                             "[NANO-PROBE] Another action is already running.")) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:kSettingsActionsDidCompleteNotification
                                  object:nil];
            });
            return;
        }
        @try {
            if (!settings_ensure_kexploit()) {
                log_user("[NANO-PROBE] Failed: kernel primitives were not acquired. Please try running chain again.\n");
            } else {
                (void)nano_registry_probe_pairing_assets();
            }
        } @finally {
            settings_release_actions_lock();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

void settings_run_nano_steer_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!settings_try_claim_actions_lock("NanoRegistry steer",
                                             "[NANO-STEER] Another action is already running.")) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:kSettingsActionsDidCompleteNotification
                                  object:nil];
            });
            return;
        }
        @try {
            if (!settings_ensure_kexploit()) {
                log_user("[NANO-STEER] Failed: kernel primitives were not acquired. Please try running chain again.\n");
            } else {
                (void)nano_registry_steer_new_watch_product_alias();
            }
        } @finally {
            settings_release_actions_lock();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

void settings_run_nano_seed_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!settings_try_claim_actions_lock("NanoRegistry seed",
                                             "[NANO-SEED] Another action is already running.")) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:kSettingsActionsDidCompleteNotification
                                  object:nil];
            });
            return;
        }
        @try {
            if (!settings_ensure_kexploit()) {
                log_user("[NANO-SEED] Failed: kernel primitives were not acquired. Please try running chain again.\n");
            } else {
                NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
                nano_registry_values values = {
                    .max_pairing         = (int)[d integerForKey:kSettingsNanoMaxPairing],
                    .min_pairing         = (int)[d integerForKey:kSettingsNanoMinPairing],
                    .min_pairing_chip_id = (int)[d integerForKey:kSettingsNanoMinPairingChipID],
                    .min_quick_switch    = (int)[d integerForKey:kSettingsNanoMinQuickSwitch],
                };
                bool ok = nano_registry_seed_current_phone_compatibility_index(values.max_pairing);
                if (ok) {
                    (void)nano_registry_push_to_cfprefsd(&values, true);
                }
            }
        } @finally {
            settings_release_actions_lock();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

static void settings_start_statbar_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsStatBarEnabled]) return;

    if (__sync_lock_test_and_set(&g_statbar_live_running, 1)) {
        // Log-once for the process lifetime; further "already running" hits
        // during foreground/background lifecycle churn are pure noise.
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] StatBar live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_statbar_live_running);
        return;
    }

    g_statbar_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] StatBar live loop started interval=%uus max=%lu\n",
               settings_statbar_live_interval_us(),
               (unsigned long)kStatBarLiveMaxTicks);
        cyanide_upload_log_milestone(@"statbar-live-started");

        @try {
            while ([d boolForKey:kSettingsStatBarEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_statbar_live_stop_requested &&
                   tick < kStatBarLiveMaxTicks) {
                useconds_t intervalUS = settings_statbar_live_interval_us();
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] StatBar paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_statbar_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] StatBar resumed after screen wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_statbar_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] StatBar loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                  [d boolForKey:kSettingsStatBarShowNet],
                                                  [d boolForKey:kSettingsStatBarShowCPU],
                                                  [d boolForKey:kSettingsStatBarShowLabels],
                                                  [d boolForKey:kSettingsStatBarNetworkOnly]);
                }

                if (tick == 0) {
                    printf("[SETTINGS] StatBar result=%d\n", ok);
                    cyanide_upload_log_milestone(ok ? @"statbar-live-first-ok" : @"statbar-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] StatBar tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsStatBarEnabled] ||
                    g_statbar_live_stop_requested ||
                    tick >= kStatBarLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                uint64_t elapsedUS = (tickStartUS != 0 && nowUS >= tickStartUS) ? (nowUS - tickStartUS) : 0;
                if (nextTickUS != 0) {
                    intervalUS = settings_statbar_live_interval_us();
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        uint64_t sleepUS = nextTickUS - nowUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] StatBar tick=%lu elapsed=%lluus sleep=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   sleepUS,
                                   settings_live_context());
                        }
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)sleepUS,
                                                               &g_statbar_live_stop_requested);
                    } else {
                        uint64_t overrunUS = nowUS - nextTickUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] StatBar tick=%lu elapsed=%lluus overrun=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   overrunUS,
                                   settings_live_context());
                        }
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_statbar_live_interval_us(),
                                                           &g_statbar_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] StatBar live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsStatBarEnabled],
                   (unsigned long)failures,
                   g_statbar_live_stop_requested);
            if (![d boolForKey:kSettingsStatBarEnabled] || g_statbar_live_stop_requested || failures > 0) {
                settings_end_statbar_background_task_async("live loop exited");
            }
            if (failures > 0)
                cyanide_upload_log_milestone(@"statbar-live-exited-failed");
            __sync_lock_release(&g_statbar_live_running);
        }
    });
}

static void settings_apply_statbar_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsStatBarEnabled] || !g_springboard_rc_ready) return;
    if (g_statbar_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "statbar apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] StatBar lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_statbar_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsStatBarEnabled] ||
                !g_springboard_rc_ready) return;
            ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                          [d boolForKey:kSettingsStatBarShowNet],
                                          [d boolForKey:kSettingsStatBarShowCPU],
                                          [d boolForKey:kSettingsStatBarShowLabels],
                                          [d boolForKey:kSettingsStatBarNetworkOnly]);
        }
        // Only log lifecycle applies that change result; a clean success on
        // every foreground/background flip is noise.
        static volatile int lastResult = -1;
        int now = ok ? 1 : 0;
        if (now != lastResult) {
            lastResult = now;
            printf("[SETTINGS] StatBar lifecycle apply%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
        }
        settings_start_statbar_live_loop();
    });
}

static void settings_start_nsbar_live_loop(void)
{
    if (!settings_device_supported() || settings_cleanup_in_progress()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNSBarEnabled] || !g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_nsbar_live_running, 1)) return;
    g_nsbar_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        BOOL pausedForSleep = NO;
        @try {
            while ([d boolForKey:kSettingsNSBarEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_nsbar_live_stop_requested &&
                   tick < kNSBarLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kNSBarLiveIntervalUS,
                                                               kNSBarLiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] NSBar paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_nsbar_live_stop_requested);
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] NSBar resumed after screen wake\n");
                }

                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        ![d boolForKey:kSettingsNSBarEnabled] ||
                        !g_springboard_rc_ready) break;
                    ok = nsbar_apply_in_session((NSBarPosition)[d integerForKey:kSettingsNSBarPosition]);
                    settings_mark_tweak_applied(kSettingsNSBarEnabled,
                                                ok && [d boolForKey:kSettingsNSBarEnabled]);
                }
                if (tick == 0 || !ok) {
                    printf("[SETTINGS] NSBar live tick=%lu result=%d\n",
                           (unsigned long)tick, ok);
                }
                failures = ok ? 0 : failures + 1;
                if (failures >= settings_live_failure_limit(3)) break;
                tick++;
                settings_live_loop_sleep_interruptible(0,
                    intervalUS,
                    &g_nsbar_live_stop_requested);
            }
        } @finally {
            printf("[SETTINGS] NSBar live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsNSBarEnabled],
                   (unsigned long)failures,
                   g_nsbar_live_stop_requested);
            __sync_lock_release(&g_nsbar_live_running);
        }
    });
}

static void settings_apply_nsbar_once_async(const char *reason)
{
    if (!settings_device_supported() || settings_cleanup_in_progress()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNSBarEnabled] || !g_springboard_rc_ready) return;
    if (g_nsbar_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "nsbar apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] NSBar lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_nsbar_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsNSBarEnabled] ||
                !g_springboard_rc_ready) return;
            ok = nsbar_apply_in_session((NSBarPosition)[d integerForKey:kSettingsNSBarPosition]);
            settings_mark_tweak_applied(kSettingsNSBarEnabled,
                                        ok && [d boolForKey:kSettingsNSBarEnabled]);
        }
        printf("[SETTINGS] NSBar lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_nsbar_live_loop();
        settings_notify_package_queue_changed_async();
    });
}

void settings_start_nicebarlite_live_loop(void)
{
    if (!settings_device_supported() || settings_cleanup_in_progress()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNiceBarLiteEnabled] || !g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_nicebarlite_live_running, 1)) return;
    g_nicebarlite_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        BOOL pausedForSleep = NO;
        @try {
            while ([d boolForKey:kSettingsNiceBarLiteEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_nicebarlite_live_stop_requested &&
                   tick < kNiceBarLiteLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kNiceBarLiteLiveIntervalUS,
                                                               kNiceBarLiteLiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] NiceBar Lite paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_nicebarlite_live_stop_requested);
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] NiceBar Lite resumed after screen wake\n");
                }

                bool ok = false;
                settings_nicebar_refresh_weather_if_needed(NO, nil);
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        ![d boolForKey:kSettingsNiceBarLiteEnabled] ||
                        !g_springboard_rc_ready) break;
                    ok = settings_apply_nicebarlite_from_defaults_locked(d);
                    settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled,
                                                ok && [d boolForKey:kSettingsNiceBarLiteEnabled]);
                }
                if (tick == 0 || !ok) {
                    printf("[SETTINGS] NiceBar Lite live tick=%lu result=%d\n",
                           (unsigned long)tick, ok);
                }
                failures = ok ? 0 : failures + 1;
                if (failures >= settings_live_failure_limit(3)) break;
                tick++;
                settings_live_loop_sleep_interruptible(0,
                    intervalUS,
                    &g_nicebarlite_live_stop_requested);
            }
        } @finally {
            printf("[SETTINGS] NiceBar Lite live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsNiceBarLiteEnabled],
                   (unsigned long)failures,
                   g_nicebarlite_live_stop_requested);
            __sync_lock_release(&g_nicebarlite_live_running);
        }
    });
}

static void settings_apply_nicebarlite_once_async(const char *reason)
{
    if (!settings_device_supported() || settings_cleanup_in_progress()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNiceBarLiteEnabled] || !g_springboard_rc_ready) return;
    if (g_nicebarlite_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        bool ok = false;
        settings_nicebar_refresh_weather_if_needed(!settings_nicebar_has_resolved_weather(d), nil);
        (void)settings_refresh_screen_awake_state(reason ?: "nicebarlite apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] NiceBar Lite lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_nicebarlite_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsNiceBarLiteEnabled] ||
                !g_springboard_rc_ready) return;
            ok = settings_apply_nicebarlite_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled,
                                        ok && [d boolForKey:kSettingsNiceBarLiteEnabled]);
        }
        printf("[SETTINGS] NiceBar Lite lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_nicebarlite_live_loop();
        settings_notify_package_queue_changed_async();
    });
}

static BOOL settings_livewp_should_play(void)
{
    (void)settings_refresh_screen_awake_state("LiveWP playback check");
    return settings_screen_awake_cached();
}

void settings_start_livewp_live_loop(void)
{
    if (!settings_device_supported() || settings_cleanup_in_progress()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsLiveWPEnabled] || !g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_livewp_live_running, 1)) return;
    g_livewp_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        @try {
            while ([d boolForKey:kSettingsLiveWPEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_livewp_live_stop_requested &&
                   tick < kLiveWPLiveMaxTicks) {
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        ![d boolForKey:kSettingsLiveWPEnabled] ||
                        !g_springboard_rc_ready) break;
                    if (settings_livewp_should_play()) {
                        (void)livewp_resume_in_session();
                        (void)livewp_repair_in_session();
                    } else {
                        (void)livewp_pause_in_session();
                    }
                }
                tick++;
                settings_live_loop_sleep_interruptible(0,
                    settings_live_interval(kLiveWPLiveIntervalUS, kLiveWPLiveBackgroundIntervalUS),
                    &g_livewp_live_stop_requested);
            }
        } @finally {
            printf("[SETTINGS] LiveWP live loop exited ticks=%lu enabled=%d stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsLiveWPEnabled],
                   g_livewp_live_stop_requested);
            __sync_lock_release(&g_livewp_live_running);
        }
    });
}

static void settings_pause_livewp_for_sleep_async(const char *reason)
{
    if (!settings_device_supported() || settings_cleanup_in_progress()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsLiveWPEnabled] || !g_springboard_rc_ready) return;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsLiveWPEnabled] ||
                !g_springboard_rc_ready) return;
            if (settings_livewp_should_play()) return;
            bool ok = livewp_pause_in_session();
            printf("[SETTINGS] LiveWP pause%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
        }
    });
}

static void settings_resume_livewp_after_wake_async(const char *reason)
{
    if (!settings_device_supported() || settings_cleanup_in_progress()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsLiveWPEnabled] || !g_springboard_rc_ready) return;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        bool ok = false;
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsLiveWPEnabled] ||
                !g_springboard_rc_ready) return;
            if (!settings_livewp_should_play()) {
                (void)livewp_pause_in_session();
                return;
            }
            ok = livewp_resume_in_session();
            if (ok) settings_mark_tweak_applied(kSettingsLiveWPEnabled, YES);
        }
        printf("[SETTINGS] LiveWP resume%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        if (ok) settings_start_livewp_live_loop();
        settings_notify_package_queue_changed_async();
    });
}

static void settings_start_rssi_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_rssi_install_allowed()) return;
    if (![d boolForKey:kSettingsRSSIDisplayEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_rssi_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] RSSI live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_rssi_live_running);
        return;
    }

    g_rssi_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] RSSI live loop started interval=%uus background=%uus max=%lu\n",
               kRSSILiveIntervalUS,
               kRSSILiveBackgroundIntervalUS,
               (unsigned long)kRSSILiveMaxTicks);
        cyanide_upload_log_milestone(@"rssi-live-started");

        @try {
            while ([d boolForKey:kSettingsRSSIDisplayEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_rssi_live_stop_requested &&
                   tick < kRSSILiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kRSSILiveIntervalUS,
                                                               kRSSILiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] RSSI paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_rssi_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] RSSI resumed after screen wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_rssi_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] RSSI loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                      [d boolForKey:kSettingsRSSIDisplayCell]);
                }

                uint64_t tickEndUS = settings_now_us();
                if (tick == 0) {
                    uint64_t elapsedUS = tickEndUS >= tickStartUS ? tickEndUS - tickStartUS : 0;
                    printf("[SETTINGS] RSSI first tick result=%d elapsed=%lluus\n",
                           ok,
                           (unsigned long long)elapsedUS);
                    cyanide_upload_log_milestone(ok ? @"rssi-live-first-ok" : @"rssi-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] RSSI tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(5)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsRSSIDisplayEnabled] ||
                    g_rssi_live_stop_requested ||
                    tick >= kRSSILiveMaxTicks) break;

                uint64_t nowUS = tickEndUS;
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kRSSILiveIntervalUS,
                                                        kRSSILiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - nowUS),
                                                               &g_rssi_live_stop_requested);
                    } else {
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kRSSILiveIntervalUS,
                                                                                  kRSSILiveBackgroundIntervalUS),
                                                           &g_rssi_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] RSSI live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsRSSIDisplayEnabled],
                   (unsigned long)failures,
                   g_rssi_live_stop_requested);
            if (failures > 0)
                cyanide_upload_log_milestone(@"rssi-live-exited-failed");
            __sync_lock_release(&g_rssi_live_running);
        }
    });
}

static void settings_apply_rssi_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_rssi_install_allowed()) return;
    if (![d boolForKey:kSettingsRSSIDisplayEnabled] || !g_springboard_rc_ready) return;
    if (g_rssi_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "rssi apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] RSSI lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_rssi_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsRSSIDisplayEnabled] ||
                !g_springboard_rc_ready) return;
            ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                              [d boolForKey:kSettingsRSSIDisplayCell]);
        }
        printf("[SETTINGS] RSSI lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_rssi_live_loop();
    });
}

static void settings_start_axonlite_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsAxonLiteEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_axonlite_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] Axon Lite live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_axonlite_live_running);
        return;
    }

    g_axonlite_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForUnavailableScreen = NO;

        printf("[SETTINGS] Axon Lite live loop started interval=%uus background=%uus max=%lu\n",
               kAxonLiteLiveIntervalUS,
               kAxonLiteLiveBackgroundIntervalUS,
               (unsigned long)kAxonLiteLiveMaxTicks);
        cyanide_upload_log_milestone(@"axon-lite-live-started");

        @try {
            settings_live_loop_sleep_interruptible(0,
                                                   settings_live_interval(kAxonLiteLiveIntervalUS,
                                                                          kAxonLiteLiveBackgroundIntervalUS),
                                                   &g_axonlite_live_stop_requested);
            nextTickUS = settings_now_us();
            while ([d boolForKey:kSettingsAxonLiteEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_axonlite_live_stop_requested &&
                   tick < kAxonLiteLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kAxonLiteLiveIntervalUS,
                                                               kAxonLiteLiveBackgroundIntervalUS);
                // While locked/asleep, CoverSheet churn is exactly where Axon
                // can put sustained pressure on SB. Pause locally without
                // messaging SB so the existing Axon roster/filter state is
                // still there when the screen wakes. The initial cache pass
                // is exempt — interrupting it leaves SB with requests we've
                // already removed but no segmented-control polling to bring
                // them back.
                if (!settings_axonlite_can_poll_springboard() &&
                    axonlite_initial_cache_ready()) {
                    if (!pausedForUnavailableScreen) {
                        pausedForUnavailableScreen = YES;
                        printf("[SETTINGS] Axon Lite paused while %s\n",
                               settings_axonlite_pause_reason());
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_axonlite_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForUnavailableScreen) {
                    pausedForUnavailableScreen = NO;
                    printf("[SETTINGS] Axon Lite resumed after screen unlock/wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_axonlite_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] Axon Lite loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    if (!settings_axonlite_can_poll_springboard() &&
                        axonlite_initial_cache_ready()) {
                        printf("[SETTINGS] Axon Lite tick skipped inside lock: %s\n",
                               settings_axonlite_pause_reason());
                        nextTickUS = settings_now_us();
                        continue;
                    }
                    ok = axonlite_apply_in_session();
                }

                if (tick == 0) {
                    printf("[SETTINGS] Axon Lite result=%d\n", ok);
                    cyanide_upload_log_milestone(ok ? @"axon-lite-live-first-ok" : @"axon-lite-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] Axon Lite tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsAxonLiteEnabled] ||
                    g_axonlite_live_stop_requested ||
                    tick >= kAxonLiteLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kAxonLiteLiveIntervalUS,
                                                        kAxonLiteLiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - nowUS),
                                                               &g_axonlite_live_stop_requested);
                    } else {
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kAxonLiteLiveIntervalUS,
                                                                                  kAxonLiteLiveBackgroundIntervalUS),
                                                           &g_axonlite_live_stop_requested);
                }

                uint64_t elapsedUS = tickStartUS != 0 && nowUS >= tickStartUS ? nowUS - tickStartUS : 0;
                if (tick == 1) {
                    printf("[SETTINGS] Axon Lite tick=0 elapsed=%lluus\n", elapsedUS);
                }
            }
        } @finally {
            printf("[SETTINGS] Axon Lite live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsAxonLiteEnabled],
                   (unsigned long)failures,
                   g_axonlite_live_stop_requested);
            if (failures > 0)
                cyanide_upload_log_milestone(@"axon-lite-live-exited-failed");
            __sync_lock_release(&g_axonlite_live_running);
        }
    });
}

void settings_start_typebanner_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsTypeBannerEnabled]) return;

    if (__sync_lock_test_and_set(&g_typebanner_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] TypeBanner live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_typebanner_live_running);
        return;
    }

    g_typebanner_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        BOOL deferredLogged = NO;
        BOOL pausedForMessages = NO;
        RemoteCallSession *mobileSession = nil;
        RemoteCallSession *daemonSession = nil;

        printf("[SETTINGS] TypeBanner live loop started interval=%uus background=%uus max=%lu\n",
               kTypeBannerLiveIntervalUS,
               kTypeBannerLiveBackgroundIntervalUS,
               (unsigned long)kTypeBannerLiveMaxTicks);

        @try {
            while ([d boolForKey:kSettingsTypeBannerEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_typebanner_live_stop_requested &&
                   tick < kTypeBannerLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kTypeBannerLiveIntervalUS,
                                                               kTypeBannerLiveBackgroundIntervalUS);
                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                if (!g_kexploit_done || g_settings_actions_running) {
                    if (!deferredLogged) {
                        printf("[SETTINGS] TypeBanner tick deferred krw=%d actions=%d\n",
                               g_kexploit_done, g_settings_actions_running);
                        deferredLogged = YES;
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_typebanner_live_stop_requested);
                    continue;
                }
                deferredLogged = NO;

                if (!settings_typebanner_can_poll_messages()) {
                    if (!pausedForMessages) {
                        pausedForMessages = YES;
                        printf("[SETTINGS] TypeBanner paused while %s\n",
                               settings_typebanner_pause_reason());
                    }
                    if (mobileSession) {
                        @synchronized (settings_rc_lock()) {
                            [mobileSession abandonRemoteCall];
                            mobileSession = nil;
                        }
                    }
                    if (daemonSession) {
                        @synchronized (settings_rc_lock()) {
                            [daemonSession abandonRemoteCall];
                            daemonSession = nil;
                        }
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_typebanner_live_stop_requested);
                    continue;
                }
                if (pausedForMessages) {
                    pausedForMessages = NO;
                    printf("[SETTINGS] TypeBanner resumed after screen unlock/wake\n");
                }

                // TypeBanner now uses imagent original-thread probes for
                // detection. The MobileSMS session pointer is kept only for
                // fallback builds where that path is re-enabled.
                @try {
                    @synchronized (settings_rc_lock()) {
                        if (!g_typebanner_live_stop_requested &&
                            !g_settings_actions_running &&
                            g_kexploit_done &&
                            settings_typebanner_can_poll_messages()) {
                            ok = typebanner_run_once_with_cached_sessions(&mobileSession,
                                                                          &daemonSession,
                                                                          g_springboard_rc_ready != 0);
                        } else {
                            ok = true;
                        }
                    }
                } @catch (NSException *e) {
                    printf("[SETTINGS] TypeBanner tick exception: %s\n", e.reason.UTF8String);
                    ok = false;
                }

                if (tick == 0) printf("[SETTINGS] TypeBanner result=%d\n", ok);
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] TypeBanner tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsTypeBannerEnabled] ||
                    g_typebanner_live_stop_requested ||
                    tick >= kTypeBannerLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                uint64_t elapsedUS = tickStartUS != 0 && nowUS >= tickStartUS ? nowUS - tickStartUS : 0;
                if (elapsedUS < intervalUS) {
                    settings_live_loop_sleep_interruptible(0,
                                                           (useconds_t)(intervalUS - elapsedUS),
                                                           &g_typebanner_live_stop_requested);
                }

                if (tick == 1) {
                    printf("[SETTINGS] TypeBanner tick=0 elapsed=%lluus\n", elapsedUS);
                }
            }
        } @finally {
            if (mobileSession) {
                @synchronized (settings_rc_lock()) {
                    [mobileSession destroyRemoteCall];
                    mobileSession = nil;
                }
            }
            if (daemonSession) {
                @synchronized (settings_rc_lock()) {
                    [daemonSession destroyRemoteCall];
                    daemonSession = nil;
                }
            }

            // Best-effort hide the banner before exiting — drops any stale
            // pill that might persist in SpringBoard's window list.
            if (typebanner_has_remote_state() &&
                g_kexploit_done && !g_settings_actions_running && !settings_cleanup_in_progress()) {
                @synchronized (settings_rc_lock()) {
                    RemoteCallSession *springboardSession = [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                                                     useMigFilterBypass:NO
                                                                                firstExceptionTimeoutMS:TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS];
                    if (springboardSession) {
                        @try {
                            typebanner_release_mobilesms_keepalive_in_springboard_remote_session(springboardSession);
                            typebanner_hide_in_springboard_remote_session(springboardSession);
                        } @catch (NSException *e) {
                            printf("[SETTINGS] TypeBanner final hide exception: %s\n", e.reason.UTF8String);
                        }
                        [springboardSession destroyRemoteCall];
                    }
                }
            } else {
                printf("[SETTINGS] TypeBanner final hide skipped state=%d krw=%d actions=%d cleanup=%d\n",
                       typebanner_has_remote_state(),
                       g_kexploit_done, g_settings_actions_running, settings_cleanup_in_progress());
            }
            typebanner_forget_remote_state();

            printf("[SETTINGS] TypeBanner live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsTypeBannerEnabled],
                   (unsigned long)failures,
                   g_typebanner_live_stop_requested);
            __sync_lock_release(&g_typebanner_live_running);
        }
    });
}

void settings_start_notificationisland_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_notificationisland_install_allowed()) return;
    if (![d boolForKey:kSettingsNotificationIslandEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_notificationisland_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] Notification Island live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_notificationisland_live_running);
        return;
    }

    g_notificationisland_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL deferredLogged = NO;

        printf("[SETTINGS] Notification Island live loop started interval=%uus background=%uus max=%lu\n",
               kNotificationIslandLiveIntervalUS,
               kNotificationIslandLiveBackgroundIntervalUS,
               (unsigned long)kNotificationIslandLiveMaxTicks);
        cyanide_upload_log_milestone(@"notification-island-live-started");

        @try {
            while ([d boolForKey:kSettingsNotificationIslandEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_notificationisland_live_stop_requested &&
                   tick < kNotificationIslandLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kNotificationIslandLiveIntervalUS,
                                                               kNotificationIslandLiveBackgroundIntervalUS);
                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                if (!g_kexploit_done || g_settings_actions_running) {
                    if (!deferredLogged) {
                        printf("[SETTINGS] Notification Island tick deferred krw=%d actions=%d\n",
                               g_kexploit_done, g_settings_actions_running);
                        deferredLogged = YES;
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_notificationisland_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                deferredLogged = NO;

                @synchronized (settings_rc_lock()) {
                    if (g_notificationisland_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] Notification Island loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = notificationisland_tick_in_session();
                }

                if (tick == 0) {
                    printf("[SETTINGS] Notification Island result=%d\n", ok);
                    cyanide_upload_log_milestone(ok ? @"notification-island-live-first-ok" :
                                                     @"notification-island-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] Notification Island tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsNotificationIslandEnabled] ||
                    g_notificationisland_live_stop_requested ||
                    tick >= kNotificationIslandLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                intervalUS = settings_live_interval(kNotificationIslandLiveIntervalUS,
                                                    kNotificationIslandLiveBackgroundIntervalUS);
                nextTickUS += intervalUS;
                if (nowUS < nextTickUS) {
                    settings_live_loop_sleep_interruptible(nextTickUS,
                                                           (useconds_t)(nextTickUS - nowUS),
                                                           &g_notificationisland_live_stop_requested);
                } else {
                    nextTickUS = nowUS;
                }

                uint64_t elapsedUS = tickStartUS != 0 && nowUS >= tickStartUS ? nowUS - tickStartUS : 0;
                if (tick == 1) {
                    printf("[SETTINGS] Notification Island tick=0 elapsed=%lluus\n", elapsedUS);
                }
            }
        } @finally {
            printf("[SETTINGS] Notification Island live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsNotificationIslandEnabled],
                   (unsigned long)failures,
                   g_notificationisland_live_stop_requested);
            if (failures > 0)
                cyanide_upload_log_milestone(@"notification-island-live-exited-failed");
            __sync_lock_release(&g_notificationisland_live_running);
        }
    });
}

static void settings_start_themer_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsThemerEnabled] &&
        ![d boolForKey:kSettingsSnowBoardLiteEnabled]) return;
    if (!g_springboard_rc_ready) return;
    if (settings_themer_dynamic_updates_blocked_by_stage(d)) {
        settings_note_themer_stage_conflict(YES);
        return;
    }

    if (__sync_lock_test_and_set(&g_themer_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] Themer dynamic live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_themer_live_running);
        return;
    }

    g_themer_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        NSInteger iosMajor = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        NSUInteger maxTicks = (iosMajor > 0 && iosMajor < 26)
            ? kThemerLegacyLiveMaxTicks
            : kThemerLiveMaxTicks;

        printf("[SETTINGS] Themer dynamic live loop started interval=%uus background=%uus max=%lu iosMajor=%ld\n",
               kThemerLiveIntervalUS,
               kThemerLiveBackgroundIntervalUS,
               (unsigned long)maxTicks,
               (long)iosMajor);

        @try {
            // Start with a sleep so we don't pile a tick on top of the
            // initial Run apply that just completed.
            settings_live_loop_sleep_interruptible(0,
                                                   settings_live_interval(kThemerLiveIntervalUS,
                                                                          kThemerLiveBackgroundIntervalUS),
                                                   &g_themer_live_stop_requested);
            while (([d boolForKey:kSettingsThemerEnabled] ||
                    [d boolForKey:kSettingsSnowBoardLiteEnabled]) &&
                   !settings_themer_dynamic_updates_blocked_by_stage(d) &&
                   !settings_cleanup_in_progress() &&
                   !g_themer_live_stop_requested &&
                   tick < maxTicks) {
                useconds_t intervalUS = settings_live_interval(kThemerLiveIntervalUS,
                                                               kThemerLiveBackgroundIntervalUS);
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_themer_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] Themer dynamic loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    if (!g_kexploit_done || g_settings_actions_running) {
                        // Wait for actions to finish before next tick.
                        ok = true;
                    } else {
                        ok = themer_repaint_dynamic_cached_views_in_session();
                    }
                }

                if (tick == 0) {
                    printf("[SETTINGS] Themer dynamic live first tick result=%d\n", ok);
                }
                failures = ok ? 0 : failures + 1;

                tick++;
                if ((![d boolForKey:kSettingsThemerEnabled] &&
                     ![d boolForKey:kSettingsSnowBoardLiteEnabled]) ||
                    settings_themer_dynamic_updates_blocked_by_stage(d) ||
                    g_themer_live_stop_requested ||
                    tick >= maxTicks) break;

                intervalUS = settings_live_interval(kThemerLiveIntervalUS,
                                                    kThemerLiveBackgroundIntervalUS);
                settings_live_loop_sleep_interruptible(0, intervalUS,
                                                       &g_themer_live_stop_requested);
            }
        } @finally {
            if (settings_themer_dynamic_updates_blocked_by_stage(d)) {
                settings_note_themer_stage_conflict(YES);
            }
            printf("[SETTINGS] Themer dynamic live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsThemerEnabled] || [d boolForKey:kSettingsSnowBoardLiteEnabled],
                   (unsigned long)failures,
                   g_themer_live_stop_requested);
            __sync_lock_release(&g_themer_live_running);
        }
    });
}

static void settings_schedule_themer_repair_burst_internal(const char *reason, BOOL force)
{
    (void)force;
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsThemerEnabled] &&
        ![d boolForKey:kSettingsSnowBoardLiteEnabled]) return;
    if (!g_springboard_rc_ready) return;
    if (settings_themer_dynamic_updates_blocked_by_stage(d)) {
        settings_note_themer_stage_conflict(force);
        return;
    }

    __sync_add_and_fetch(&g_themer_repair_generation, 1);
    if (__sync_lock_test_and_set(&g_themer_repair_running, 1)) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        uint64_t seenGeneration = g_themer_repair_generation;
        NSUInteger tick = 0;
        NSUInteger quietTicks = 0;

        printf("[SETTINGS] Themer dynamic repair burst started%s%s\n",
               reason ? ": " : "", reason ?: "");

        @try {
            while (([d boolForKey:kSettingsThemerEnabled] ||
                    [d boolForKey:kSettingsSnowBoardLiteEnabled]) &&
                   !settings_themer_dynamic_updates_blocked_by_stage(d) &&
                   !settings_cleanup_in_progress() &&
                   !g_themer_live_stop_requested &&
                   tick < 1) {
                settings_live_loop_sleep_interruptible(0,
                                                       tick == 0
                                                           ? kThemerRepairInitialDelayUS
                                                           : kThemerRepairIntervalUS,
                                                       &g_themer_live_stop_requested);
                if (g_themer_live_stop_requested) break;

                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (!g_springboard_rc_ready || !g_kexploit_done ||
                        g_settings_actions_running) {
                        ok = true;
                    } else {
                        ok = themer_repaint_dynamic_cached_views_in_session();
                    }
                }

                tick++;
                uint64_t currentGeneration = g_themer_repair_generation;
                if (currentGeneration != seenGeneration) {
                    seenGeneration = currentGeneration;
                    quietTicks = 0;
                } else {
                    quietTicks++;
                    if (quietTicks >= 2) break;
                }

                if (tick == 1) {
                    printf("[SETTINGS] Themer dynamic repair first repaint=%d\n", ok);
                }
            }
        } @finally {
            printf("[SETTINGS] Themer dynamic repair burst exited ticks=%lu\n",
                   (unsigned long)tick);
            __sync_lock_release(&g_themer_repair_running);
        }
    });
}

static void settings_schedule_themer_repair_burst(const char *reason)
{
    settings_schedule_themer_repair_burst_internal(reason, YES);
}

static void settings_schedule_themer_quiet_repair_burst(const char *reason)
{
    settings_schedule_themer_repair_burst_internal(reason, NO);
}

static void settings_apply_axonlite_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;
    if (g_axonlite_live_running) {
        if (reason) {
            printf("[SETTINGS] Axon Lite lifecycle apply skipped: live loop owns Axon (%s)\n",
                   reason);
        }
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsAxonLiteEnabled] || !g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        if (!settings_axonlite_can_poll_springboard()) {
            printf("[SETTINGS] Axon Lite lifecycle apply%s%s skipped: %s\n",
                   reason ? ": " : "", reason ?: "",
                   settings_axonlite_pause_reason());
            settings_start_axonlite_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsAxonLiteEnabled] ||
                !g_springboard_rc_ready) return;
            if (!settings_axonlite_can_poll_springboard()) {
                printf("[SETTINGS] Axon Lite lifecycle apply%s%s skipped inside lock: %s\n",
                       reason ? ": " : "", reason ?: "",
                       settings_axonlite_pause_reason());
                settings_start_axonlite_live_loop();
                return;
            }
            ok = axonlite_apply_in_session();
        }
        printf("[SETTINGS] Axon Lite lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_axonlite_live_loop();
    });
}

void settings_application_did_enter_background(void)
{
    if (__sync_lock_test_and_set(&g_app_in_background, 1)) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL themerLiveNeeded = g_springboard_rc_ready &&
        !settings_themer_dynamic_updates_blocked_by_stage(d) &&
        ([d boolForKey:kSettingsThemerEnabled] ||
         [d boolForKey:kSettingsSnowBoardLiteEnabled]);
    BOOL anyLiveLoopNeeded =
        ([d boolForKey:kSettingsAxonLiteEnabled]    && g_springboard_rc_ready) ||
        (settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsStatBarEnabled]     && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsNSBarEnabled]       && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsNiceBarLiteEnabled] && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsGravityLiteEnabled] && g_springboard_rc_ready) ||
        themerLiveNeeded ||
        ([d boolForKey:kSettingsLiveWPEnabled]      && g_springboard_rc_ready) ||
        (settings_notificationisland_install_allowed() && [d boolForKey:kSettingsNotificationIslandEnabled] && g_springboard_rc_ready) ||
        (settings_typebanner_install_allowed() && [d boolForKey:kSettingsTypeBannerEnabled]);
    if (anyLiveLoopNeeded) {
        if ([d boolForKey:kSettingsKeepAlive]) {
            ds_keepalive_apply_enabled(YES);
        }
        settings_begin_statbar_background_task_async("entered background");
    }

    if ([d boolForKey:kSettingsAxonLiteEnabled] && g_springboard_rc_ready) {
        settings_apply_axonlite_once_async("entered background");
    }
    if (settings_notificationisland_install_allowed() &&
        [d boolForKey:kSettingsNotificationIslandEnabled] &&
        g_springboard_rc_ready) {
        settings_start_notificationisland_live_loop();
    }
    if ([d boolForKey:kSettingsGravityLiteEnabled] && g_springboard_rc_ready) {
        if (g_gravitylite_background_armed != 0) {
            settings_apply_armed_gravitylite_once_async("entered background");
        }
    }
    if (settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) {
        settings_apply_rssi_once_async("entered background");
    }
    if ([d boolForKey:kSettingsNSBarEnabled] && g_springboard_rc_ready) {
        settings_apply_nsbar_once_async("entered background");
    }
    if ([d boolForKey:kSettingsNiceBarLiteEnabled] && g_springboard_rc_ready) {
        settings_apply_nicebarlite_once_async("entered background");
    }
    if ([d boolForKey:kSettingsLiveWPEnabled] && g_springboard_rc_ready) {
        settings_pause_livewp_for_sleep_async("entered background");
    }
    if (![d boolForKey:kSettingsStatBarEnabled] || !g_springboard_rc_ready) {
        return;
    }

    printf("[SETTINGS] app entered background with app-side StatBar loop\n");
    settings_apply_statbar_once_async("entered background");
}

void settings_application_will_enter_foreground(void)
{
    if (!settings_app_state_is_foreground()) return;
    g_app_in_background = 0;
    settings_end_statbar_background_task_async("foreground");
    if (settings_cleanup_in_progress()) return;
    settings_apply_statbar_once_async("will enter foreground");
    settings_apply_nsbar_once_async("will enter foreground");
    settings_apply_nicebarlite_once_async("will enter foreground");
    settings_apply_rssi_once_async("will enter foreground");
    settings_apply_axonlite_once_async("will enter foreground");
    if (settings_notificationisland_install_allowed() &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsNotificationIslandEnabled] &&
        g_springboard_rc_ready) {
        settings_start_notificationisland_live_loop();
    }
    settings_start_themer_live_loop();
    settings_resume_livewp_after_wake_async("will enter foreground");
    if (settings_typebanner_install_allowed() &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsTypeBannerEnabled]) {
        settings_start_typebanner_live_loop();
    }
}

void settings_application_did_become_active(void)
{
    if (!settings_app_state_is_foreground()) return;
    g_app_in_background = 0;
    if (settings_cleanup_in_progress()) return;
    settings_apply_statbar_once_async("became active");
    settings_apply_nsbar_once_async("became active");
    settings_apply_nicebarlite_once_async("became active");
    settings_apply_rssi_once_async("became active");
    settings_apply_axonlite_once_async("became active");
    if (settings_notificationisland_install_allowed() &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsNotificationIslandEnabled] &&
        g_springboard_rc_ready) {
        settings_start_notificationisland_live_loop();
    }
    settings_start_themer_live_loop();
    settings_resume_livewp_after_wake_async("became active");
    if (settings_typebanner_install_allowed() &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsTypeBannerEnabled]) {
        settings_start_typebanner_live_loop();
    }
}

static BOOL settings_key_is_sbc(NSString *key)
{
    return [key isEqualToString:kSettingsSBCEnabled] ||
           [key isEqualToString:kSettingsSBCDockIcons] ||
           [key isEqualToString:kSettingsSBCCols] ||
           [key isEqualToString:kSettingsSBCRows] ||
           [key isEqualToString:kSettingsSBCHideLabels];
}

static BOOL settings_key_is_statbar(NSString *key)
{
    return [key isEqualToString:kSettingsStatBarEnabled] ||
           [key isEqualToString:kSettingsStatBarCelsius] ||
           [key isEqualToString:kSettingsStatBarShowNet] ||
           [key isEqualToString:kSettingsStatBarShowCPU] ||
           [key isEqualToString:kSettingsStatBarShowLabels] ||
           [key isEqualToString:kSettingsStatBarNetworkOnly] ||
           [key isEqualToString:kSettingsStatBarRefreshRateSec];
}

static BOOL settings_key_is_nsbar(NSString *key)
{
    return [key isEqualToString:kSettingsNSBarEnabled] ||
           [key isEqualToString:kSettingsNSBarPosition];
}

static BOOL settings_key_is_nicebarlite(NSString *key)
{
    if ([key isEqualToString:kSettingsNiceBarLiteEnabled] ||
        [key isEqualToString:kSettingsNiceBarLiteCelsius] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutTopSideInset] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutBottomSideInset] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutTopY] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutBottomY] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutCenterX]) {
        return YES;
    }
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        if ([key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, i)]) {
            return YES;
        }
    }
    return NO;
}

static BOOL settings_key_is_rssi(NSString *key)
{
    return [key isEqualToString:kSettingsRSSIDisplayEnabled] ||
           [key isEqualToString:kSettingsRSSIDisplayWifi] ||
           [key isEqualToString:kSettingsRSSIDisplayCell];
}

static BOOL settings_key_is_axonlite(NSString *key)
{
    return [key isEqualToString:kSettingsAxonLiteEnabled];
}

static BOOL settings_key_is_typebanner(NSString *key)
{
    return [key isEqualToString:kSettingsTypeBannerEnabled];
}

static BOOL settings_key_is_notificationisland(NSString *key)
{
    return [key isEqualToString:kSettingsNotificationIslandEnabled];
}

static BOOL settings_key_is_appswitchergrid(NSString *key)
{
    return [key isEqualToString:kSettingsAppSwitcherGridEnabled];
}

static BOOL settings_key_is_gravitylite(NSString *key)
{
    return [key isEqualToString:kSettingsGravityLiteEnabled] ||
           [key isEqualToString:kSettingsGravityLiteDockEnabled] ||
           [key isEqualToString:kSettingsGravityLiteMagnitudePct] ||
           [key isEqualToString:kSettingsGravityLiteBouncePct] ||
           [key isEqualToString:kSettingsGravityLiteFrictionPct] ||
           [key isEqualToString:kSettingsGravityLiteResistancePct] ||
           [key isEqualToString:kSettingsGravityLiteAngularResistancePct];
}

BOOL settings_key_is_location_sim(NSString *key)
{
    return [key isEqualToString:kSettingsLocationSimEnabled] ||
           [key isEqualToString:kSettingsLocationSimLatitude] ||
           [key isEqualToString:kSettingsLocationSimLongitude] ||
           [key isEqualToString:kSettingsLocationSimAltitude] ||
           [key isEqualToString:kSettingsLocationSimHorizontalAccuracy] ||
           [key isEqualToString:kSettingsLocationSimHostProcess];
}

static NSString *settings_location_sim_host_process(NSUserDefaults *d)
{
    NSString *host = [d stringForKey:kSettingsLocationSimHostProcess];
    return host.length > 0 ? host : @"Maps";
}

static NSArray<NSDictionary *> *settings_location_sim_number_tokens_from_text(NSString *text)
{
    NSMutableArray<NSDictionary *> *tokens = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
    scanner.charactersToBeSkipped = nil;
    while (!scanner.isAtEnd) {
        double value = 0.0;
        NSUInteger start = scanner.scanLocation;
        if ([scanner scanDouble:&value]) {
            if (isfinite(value)) {
                NSRange range = NSMakeRange(start, scanner.scanLocation - start);
                [tokens addObject:@{ @"value": @(value),
                                     @"range": [NSValue valueWithRange:range] }];
            }
            continue;
        }
        scanner.scanLocation = scanner.scanLocation + 1;
    }
    return tokens;
}

static NSInteger settings_location_sim_axis_sign_for_word(NSString *word, BOOL latitude)
{
    NSString *upper = [(word ?: @"") uppercaseString];
    if (upper.length != 1) return 0;
    unichar c = [upper characterAtIndex:0];
    if (latitude) {
        if (c == 'N') return 1;
        if (c == 'S') return -1;
    } else {
        if (c == 'E') return 1;
        if (c == 'W') return -1;
    }
    return 0;
}

static NSInteger settings_location_sim_axis_kind_for_word(NSString *word)
{
    NSString *upper = [(word ?: @"") uppercaseString];
    if ([upper isEqualToString:@"LAT"] ||
        [upper isEqualToString:@"LATITUDE"]) {
        return 1;
    }
    if ([upper isEqualToString:@"LON"] ||
        [upper isEqualToString:@"LNG"] ||
        [upper isEqualToString:@"LONG"] ||
        [upper isEqualToString:@"LONGITUDE"]) {
        return 2;
    }
    return 0;
}

static BOOL settings_location_sim_is_axis_separator(unichar c)
{
    if ([NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:c]) return YES;
    if ([NSCharacterSet.punctuationCharacterSet characterIsMember:c]) return YES;
    if ([NSCharacterSet.symbolCharacterSet characterIsMember:c]) return YES;
    return NO;
}

static NSString *settings_location_sim_axis_word_after_range(NSString *text, NSRange range)
{
    NSUInteger i = NSMaxRange(range);
    while (i < text.length &&
           settings_location_sim_is_axis_separator([text characterAtIndex:i])) {
        i++;
    }
    NSUInteger start = i;
    while (i < text.length &&
           [NSCharacterSet.letterCharacterSet characterIsMember:[text characterAtIndex:i]]) {
        i++;
    }
    return i > start ? [text substringWithRange:NSMakeRange(start, i - start)] : @"";
}

static NSString *settings_location_sim_axis_word_before_range(NSString *text, NSRange range)
{
    if (range.location == 0) return @"";
    NSInteger i = (NSInteger)range.location - 1;
    while (i >= 0 &&
           settings_location_sim_is_axis_separator([text characterAtIndex:(NSUInteger)i])) {
        i--;
    }
    NSInteger end = i + 1;
    while (i >= 0 &&
           [NSCharacterSet.letterCharacterSet characterIsMember:[text characterAtIndex:(NSUInteger)i]]) {
        i--;
    }
    NSInteger start = i + 1;
    return end > start ? [text substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))] : @"";
}

static NSInteger settings_location_sim_axis_sign_near_range(NSString *text,
                                                            NSRange range,
                                                            BOOL latitude)
{
    NSInteger sign = settings_location_sim_axis_sign_for_word(settings_location_sim_axis_word_after_range(text ?: @"", range),
                                                              latitude);
    if (sign != 0) return sign;
    return settings_location_sim_axis_sign_for_word(settings_location_sim_axis_word_before_range(text ?: @"", range),
                                                   latitude);
}

static NSInteger settings_location_sim_axis_kind_near_range(NSString *text, NSRange range)
{
    NSInteger kind = settings_location_sim_axis_kind_for_word(settings_location_sim_axis_word_before_range(text ?: @"", range));
    if (kind != 0) return kind;
    return settings_location_sim_axis_kind_for_word(settings_location_sim_axis_word_after_range(text ?: @"", range));
}

static NSInteger settings_location_sim_axis_sign_from_text(NSString *text, BOOL latitude)
{
    NSString *upper = [(text ?: @"") uppercaseString];
    NSInteger sign = 0;
    for (NSUInteger i = 0; i < upper.length; i++) {
        unichar c = [upper characterAtIndex:i];
        NSInteger candidate = settings_location_sim_axis_sign_for_word([NSString stringWithCharacters:&c length:1],
                                                                       latitude);
        if (candidate == 0) continue;

        BOOL prevIsLetter = (i > 0) && [NSCharacterSet.letterCharacterSet characterIsMember:[upper characterAtIndex:i - 1]];
        BOOL nextIsLetter = (i + 1 < upper.length) && [NSCharacterSet.letterCharacterSet characterIsMember:[upper characterAtIndex:i + 1]];
        if (!prevIsLetter && !nextIsLetter) sign = candidate;
    }
    return sign;
}

static double settings_location_sim_apply_axis_sign(double value, NSInteger sign)
{
    return sign != 0 ? fabs(value) * (double)sign : value;
}

BOOL settings_location_sim_coordinates_valid(double latitude, double longitude)
{
    return isfinite(latitude) && isfinite(longitude) &&
           latitude >= -90.0 && latitude <= 90.0 &&
           longitude >= -180.0 && longitude <= 180.0;
}

static BOOL settings_location_sim_component_valid(double value, BOOL latitude)
{
    if (!isfinite(value)) return NO;
    return latitude
        ? (value >= -90.0 && value <= 90.0)
        : (value >= -180.0 && value <= 180.0);
}

static BOOL settings_location_sim_parse_coordinate_component(NSString *text,
                                                             BOOL latitude,
                                                             double *outValue)
{
    if (!outValue) return NO;
    NSArray<NSDictionary *> *tokens = settings_location_sim_number_tokens_from_text(text);
    if (tokens.count != 1) return NO;

    NSDictionary *token = tokens.firstObject;
    double value = [token[@"value"] doubleValue];
    NSRange range = [token[@"range"] rangeValue];
    NSInteger sign = settings_location_sim_axis_sign_near_range(text, range, latitude);
    if (sign == 0) sign = settings_location_sim_axis_sign_from_text(text, latitude);
    value = settings_location_sim_apply_axis_sign(value, sign);
    if (!settings_location_sim_component_valid(value, latitude)) return NO;

    *outValue = value;
    return YES;
}

static BOOL settings_location_sim_parse_coordinate_pair(NSString *text,
                                                        double *latitudeOut,
                                                        double *longitudeOut)
{
    if (!latitudeOut || !longitudeOut) return NO;
    NSArray<NSDictionary *> *tokens = settings_location_sim_number_tokens_from_text(text);
    if (tokens.count != 2) return NO;

    NSDictionary *firstToken = tokens[0];
    NSDictionary *secondToken = tokens[1];
    double first = [firstToken[@"value"] doubleValue];
    double second = [secondToken[@"value"] doubleValue];
    NSRange firstRange = [firstToken[@"range"] rangeValue];
    NSRange secondRange = [secondToken[@"range"] rangeValue];
    NSInteger firstLatSign = settings_location_sim_axis_sign_near_range(text, firstRange, YES);
    NSInteger firstLonSign = settings_location_sim_axis_sign_near_range(text, firstRange, NO);
    NSInteger secondLatSign = settings_location_sim_axis_sign_near_range(text, secondRange, YES);
    NSInteger secondLonSign = settings_location_sim_axis_sign_near_range(text, secondRange, NO);
    NSInteger firstKind = settings_location_sim_axis_kind_near_range(text, firstRange);
    NSInteger secondKind = settings_location_sim_axis_kind_near_range(text, secondRange);

    if (firstKind == 1 && secondKind == 2) {
        double latitude = settings_location_sim_apply_axis_sign(first, firstLatSign);
        double longitude = settings_location_sim_apply_axis_sign(second, secondLonSign);
        if (!settings_location_sim_coordinates_valid(latitude, longitude)) return NO;
        *latitudeOut = latitude;
        *longitudeOut = longitude;
        return YES;
    }

    if (firstKind == 2 && secondKind == 1) {
        double latitude = settings_location_sim_apply_axis_sign(second, secondLatSign);
        double longitude = settings_location_sim_apply_axis_sign(first, firstLonSign);
        if (!settings_location_sim_coordinates_valid(latitude, longitude)) return NO;
        *latitudeOut = latitude;
        *longitudeOut = longitude;
        return YES;
    }

    if (firstLatSign != 0 && secondLonSign != 0) {
        double latitude = settings_location_sim_apply_axis_sign(first, firstLatSign);
        double longitude = settings_location_sim_apply_axis_sign(second, secondLonSign);
        if (!settings_location_sim_coordinates_valid(latitude, longitude)) return NO;
        *latitudeOut = latitude;
        *longitudeOut = longitude;
        return YES;
    }

    if (firstLonSign != 0 && secondLatSign != 0) {
        double latitude = settings_location_sim_apply_axis_sign(second, secondLatSign);
        double longitude = settings_location_sim_apply_axis_sign(first, firstLonSign);
        if (!settings_location_sim_coordinates_valid(latitude, longitude)) return NO;
        *latitudeOut = latitude;
        *longitudeOut = longitude;
        return YES;
    }

    NSInteger latitudeSign = settings_location_sim_axis_sign_from_text(text, YES);
    NSInteger longitudeSign = settings_location_sim_axis_sign_from_text(text, NO);

    double latitude = first;
    double longitude = second;
    latitude = settings_location_sim_apply_axis_sign(latitude, latitudeSign);
    longitude = settings_location_sim_apply_axis_sign(longitude, longitudeSign);
    if (!settings_location_sim_coordinates_valid(latitude, longitude)) {
        latitude = second;
        longitude = first;
        latitude = settings_location_sim_apply_axis_sign(latitude, latitudeSign);
        longitude = settings_location_sim_apply_axis_sign(longitude, longitudeSign);
        if (!settings_location_sim_coordinates_valid(latitude, longitude)) return NO;
    }

    *latitudeOut = latitude;
    *longitudeOut = longitude;
    return YES;
}

BOOL settings_location_sim_parse_coordinate_fields(NSString *latitudeText,
                                                          NSString *longitudeText,
                                                          double *latitudeOut,
                                                          double *longitudeOut)
{
    if (!latitudeOut || !longitudeOut) return NO;
    if (settings_location_sim_parse_coordinate_pair(latitudeText, latitudeOut, longitudeOut)) return YES;
    if (settings_location_sim_parse_coordinate_pair(longitudeText, latitudeOut, longitudeOut)) return YES;

    double latitude = 0.0;
    double longitude = 0.0;
    BOOL ok = settings_location_sim_parse_coordinate_component(latitudeText, YES, &latitude) &&
              settings_location_sim_parse_coordinate_component(longitudeText, NO, &longitude) &&
              settings_location_sim_coordinates_valid(latitude, longitude);
    if (!ok) return NO;

    *latitudeOut = latitude;
    *longitudeOut = longitude;
    return YES;
}

BOOL settings_location_sim_is_active(NSUserDefaults *d)
{
    return [d boolForKey:kSettingsLocationSimStarted];
}

void settings_location_sim_set_target(NSUserDefaults *d,
                                             double latitude,
                                             double longitude)
{
    [d setDouble:latitude forKey:kSettingsLocationSimLatitude];
    [d setDouble:longitude forKey:kSettingsLocationSimLongitude];
    [d setObject:@"Maps" forKey:kSettingsLocationSimHostProcess];
    [d synchronize];
}

void settings_location_sim_set_rockaway_defaults(NSUserDefaults *d)
{
    settings_location_sim_set_target(d, kLocationSimDefaultLatitude, kLocationSimDefaultLongitude);
    [d setInteger:kLocationSimDefaultAltitude forKey:kSettingsLocationSimAltitude];
    [d setInteger:kLocationSimDefaultAccuracy forKey:kSettingsLocationSimHorizontalAccuracy];
    [d synchronize];
}

NSString *settings_location_sim_target_summary(NSUserDefaults *d)
{
    double lat = [d doubleForKey:kSettingsLocationSimLatitude];
    double lon = [d doubleForKey:kSettingsLocationSimLongitude];
    NSInteger altitude = [d integerForKey:kSettingsLocationSimAltitude];
    NSInteger accuracy = [d integerForKey:kSettingsLocationSimHorizontalAccuracy];
    if (accuracy <= 0) accuracy = kLocationSimDefaultAccuracy;
    return [NSString stringWithFormat:@"%.7f, %.7f via %@ (%ldm alt, %ldm acc)",
            lat,
            lon,
            settings_location_sim_host_process(d),
            (long)altitude,
            (long)accuracy];
}

NSString *settings_location_sim_mode_summary(NSUserDefaults *d)
{
    BOOL simulationStarted = [d boolForKey:kSettingsLocationSimStarted];
    NSString *simulation = simulationStarted
        ? @"Mode: Target simulation started"
        : @"Mode: Real location requested";
    NSString *note = simulationStarted ? @"\nUse Restore Real Location to stop it." : @"";
    return [NSString stringWithFormat:@"%@%@\nTarget: %@", simulation, note,
            settings_location_sim_target_summary(d)];
}

NSString *settings_ipadecryptor_target_summary(NSUserDefaults *d)
{
    NSString *bundleID = [d stringForKey:kSettingsIPADecryptorTargetBundleID];
    if (bundleID.length == 0) {
        return @"None selected. Choose an installed app first.";
    }
    return ipadecryptor_display_name_for_bundle(bundleID);
}

NSString *settings_ipadecryptor_app_store_summary(NSUserDefaults *d)
{
    NSString *appID = [d stringForKey:kSettingsIPADecryptorAppStoreID];
    NSString *name = [d stringForKey:kSettingsIPADecryptorAppStoreName];
    NSString *version = [d stringForKey:kSettingsIPADecryptorAppStoreVersion];
    NSString *url = [d stringForKey:kSettingsIPADecryptorAppStoreURL];
    if (appID.length == 0 && url.length == 0) {
        return @"None. Paste an App Store link or numeric app ID.";
    }
    if (name.length > 0) {
        return [NSString stringWithFormat:@"%@%@%@",
                name,
                version.length > 0 ? @" " : @"",
                version.length > 0 ? version : @""];
    }
    return appID.length > 0 ? [NSString stringWithFormat:@"App Store ID %@", appID] : url;
}

BOOL settings_apply_location_sim_from_defaults_locked(NSUserDefaults *d)
{
    NSInteger accuracy = [d integerForKey:kSettingsLocationSimHorizontalAccuracy];
    if (accuracy <= 0) accuracy = kLocationSimDefaultAccuracy;

    NSString *host = settings_location_sim_host_process(d);
    LocationSimConfig config = {
        .latitude = [d doubleForKey:kSettingsLocationSimLatitude],
        .longitude = [d doubleForKey:kSettingsLocationSimLongitude],
        .altitude = (double)[d integerForKey:kSettingsLocationSimAltitude],
        .horizontalAccuracy = (double)accuracy,
        .verticalAccuracy = (double)accuracy,
        .hostProcess = host.UTF8String,
        .launchHost = true,
    };
    return locationsim_apply_static(&config);
}

BOOL settings_stop_location_sim_from_defaults_locked(NSUserDefaults *d)
{
    NSString *host = settings_location_sim_host_process(d);
    return locationsim_stop(host.UTF8String, true);
}

BOOL settings_prime_location_sim_uber_stealth_locked(NSUserDefaults *d,
                                                            BOOL enable,
                                                            BOOL *systemApplyOKOut)
{
    NSInteger accuracy = [d integerForKey:kSettingsLocationSimHorizontalAccuracy];
    if (accuracy <= 0) accuracy = kLocationSimDefaultAccuracy;

    NSString *host = settings_location_sim_host_process(d);
    LocationSimConfig config = {
        .latitude = [d doubleForKey:kSettingsLocationSimLatitude],
        .longitude = [d doubleForKey:kSettingsLocationSimLongitude],
        .altitude = (double)[d integerForKey:kSettingsLocationSimAltitude],
        .horizontalAccuracy = (double)accuracy,
        .verticalAccuracy = (double)accuracy,
        .hostProcess = host.UTF8String,
        .launchHost = true,
    };

    BOOL systemOK = enable
        ? locationsim_apply_strict_hosts(&config)
        : locationsim_stop_strict_hosts(host.UTF8String, true);
    if (systemApplyOKOut) *systemApplyOKOut = systemOK;
    return systemOK;
}

static BOOL settings_key_is_dark_tweak(NSString *key)
{
    return [key isEqualToString:kSettingsDSDisableAppLibrary] ||
           [key isEqualToString:kSettingsDSDisableIconFlyIn] ||
           [key isEqualToString:kSettingsDSZeroWakeAnimation] ||
           [key isEqualToString:kSettingsDSZeroBacklightFade] ||
           [key isEqualToString:kSettingsDSDoubleTapToLock] ||
           [key isEqualToString:kSettingsDSDragCoefficientEnabled] ||
           [key isEqualToString:kSettingsDSDragCoefficientValue];
}

BOOL settings_key_affects_package_state(NSString *key)
{
    return [settings_rc_backed_tweak_keys() containsObject:key];
}

void settings_schedule_live_apply_for_key(NSString *key)
{
    if (settings_cleanup_in_progress()) {
        printf("[SETTINGS] live apply skipped during cleanup for %s\n", key.UTF8String);
        return;
    }

    if (!settings_device_supported()) {
        printf("[SETTINGS] live apply blocked for %s: %s\n",
               key.UTF8String, settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (settings_key_is_location_sim(key)) {
        BOOL locsimStarted = [d boolForKey:kSettingsLocationSimStarted];
        if ([key isEqualToString:kSettingsLocationSimEnabled]) {
            [d setBool:NO forKey:kSettingsLocationSimEnabled];
            [d synchronize];
            settings_notify_package_queue_changed_async();
            return;
        }
        if (!locsimStarted) {
            settings_notify_package_queue_changed_async();
            return;
        }
        if (!settings_location_sim_install_allowed()) {
            log_user("[LOCSIM] Target refresh skipped: Location Simulator is unavailable in this build.\n");
            settings_notify_package_queue_changed_async();
            settings_post_actions_complete_async(NO, @"Location Simulator is unavailable in this build.");
            return;
        }
        if (settings_any_registered_live_loop_running()) {
            log_user("[LOCSIM] Location update deferred: a live SpringBoard tweak is running. Hit Apply Tweaks to serialize the process switch.\n");
            settings_notify_package_queue_changed_async();
            settings_post_actions_complete_async(NO, @"Location refresh deferred while another live tweak is running.");
            return;
        }
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
                log_user("[LOCSIM] Location update deferred: Apply Tweaks is still running.\n");
                settings_post_actions_complete_async(NO, @"Location refresh deferred while Apply Tweaks is running.");
                settings_notify_package_queue_changed_async();
                return;
            }
            @try {
                if (!settings_ensure_kexploit()) {
                    printf("[LOCSIM] live target refresh failed to acquire KRW\n");
                    log_user("[LOCSIM] Target refresh failed: kernel primitives were not acquired. Please try running chain again.\n");
                    settings_post_actions_complete_async(NO, @"Location refresh failed: kernel primitives were not acquired.");
                    settings_notify_package_queue_changed_async();
                    return;
                }
                if (settings_any_registered_live_loop_running()) {
                    log_user("[LOCSIM] Location update deferred: a live SpringBoard tweak started while recovery was running. Hit Apply Tweaks to serialize the process switch.\n");
                    settings_post_actions_complete_async(NO, @"Location refresh deferred while another live tweak is running.");
                    settings_notify_package_queue_changed_async();
                    return;
                }
                @synchronized (settings_rc_lock()) {
                    settings_destroy_springboard_remote_call_locked_internal("switching to Location Simulator", NO);
                    bool ok = settings_apply_location_sim_from_defaults_locked(d);
                    if (ok) {
                        [d setBool:YES forKey:kSettingsLocationSimStarted];
                        [d synchronize];
                    }
                    log_user("%s Location Simulator %s.\n",
                             ok ? "[OK]" : "[WARN]",
                             ok ? "target refreshed" : "did not apply cleanly");
                    settings_post_actions_complete_async(ok,
                        ok ? @"Location target refreshed." : @"Location refresh failed. Check the log.");
                }
                settings_notify_package_queue_changed_async();
            } @finally {
                __sync_lock_release(&g_settings_actions_running);
            }
        });
        return;
    }

    if (settings_key_is_typebanner(key)) {
        if (!settings_typebanner_install_allowed()) {
            if ([d boolForKey:kSettingsTypeBannerEnabled]) {
                [d setBool:NO forKey:kSettingsTypeBannerEnabled];
                [d synchronize];
            }
            g_typebanner_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsTypeBannerEnabled, NO);
            settings_notify_package_queue_changed_async();
            typebanner_forget_remote_state();
            return;
        }
        // TypeBanner owns its own daemon + SpringBoard sessions, but its
        // bootstrap is serialized with the shared RemoteCall lock.
        if ([d boolForKey:kSettingsTypeBannerEnabled]) {
            settings_mark_tweak_applied(kSettingsTypeBannerEnabled, YES);
            settings_notify_package_queue_changed_async();
            settings_start_typebanner_live_loop();
        } else {
            g_typebanner_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsTypeBannerEnabled, NO);
            settings_notify_package_queue_changed_async();
            // Best-effort hide if a session is reachable. The live loop will
            // also hide on its own way out, but doing it here gets the pill
            // off the screen faster after the user toggles off.
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (g_kexploit_done) {
                    @synchronized (settings_rc_lock()) {
                        RemoteCallSession *springboardSession = [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                                                         useMigFilterBypass:NO
                                                                                    firstExceptionTimeoutMS:TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS];
                        if (springboardSession) {
                            @try {
                                typebanner_release_mobilesms_keepalive_in_springboard_remote_session(springboardSession);
                                typebanner_hide_in_springboard_remote_session(springboardSession);
                            } @catch (NSException *e) {
                                printf("[SETTINGS] TypeBanner toggle-off hide exception: %s\n",
                                       e.reason.UTF8String);
                            }
                            [springboardSession destroyRemoteCall];
                        }
                    }
                }
                typebanner_forget_remote_state();
            });
        }
        return;
    }

    if (settings_key_is_notificationisland(key)) {
        if (!settings_notificationisland_install_allowed()) {
            if ([d boolForKey:kSettingsNotificationIslandEnabled]) {
                [d setBool:NO forKey:kSettingsNotificationIslandEnabled];
                [d synchronize];
            }
            g_notificationisland_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsNotificationIslandEnabled, NO);
            settings_notify_package_queue_changed_async();
            notificationisland_forget_remote_state();
            return;
        }
        if ([d boolForKey:kSettingsNotificationIslandEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        ![d boolForKey:kSettingsNotificationIslandEnabled] ||
                        !g_springboard_rc_ready) return;
                    ok = notificationisland_apply_in_session();
                    settings_mark_tweak_applied(kSettingsNotificationIslandEnabled,
                                                ok && [d boolForKey:kSettingsNotificationIslandEnabled]);
                    printf("[SETTINGS] live Notification Island apply result=%d\n", ok);
                }
                if (ok) settings_start_notificationisland_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsNotificationIslandEnabled]) {
            g_notificationisland_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsNotificationIslandEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) notificationisland_stop_in_session();
                    }
                });
            } else {
                notificationisland_forget_remote_state();
            }
        }
        return;
    }

    if (settings_key_is_appswitchergrid(key)) {
        if ([d boolForKey:kSettingsAppSwitcherGridEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        ![d boolForKey:kSettingsAppSwitcherGridEnabled] ||
                        !g_springboard_rc_ready) return;
                    bool ok = appswitchergrid_apply_in_session();
                    settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled,
                                                ok && [d boolForKey:kSettingsAppSwitcherGridEnabled]);
                    printf("[SETTINGS] live App Switcher Grid apply result=%d\n", ok);
                }
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsAppSwitcherGridEnabled]) {
            settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) appswitchergrid_stop_in_session();
                    }
                });
            } else {
                appswitchergrid_forget_remote_state();
            }
        }
        return;
    }

    if (settings_key_is_nsbar(key)) {
        if ([d boolForKey:kSettingsNSBarEnabled] && g_springboard_rc_ready) {
            settings_apply_nsbar_once_async("live settings");
        } else if (![d boolForKey:kSettingsNSBarEnabled]) {
            g_nsbar_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsNSBarEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) nsbar_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_nicebarlite(key)) {
        BOOL forceWeatherRefresh = [key isEqualToString:kSettingsNiceBarLiteCelsius];
        if (forceWeatherRefresh || [key hasPrefix:kSettingsNiceBarLiteSlotKindPrefix]) {
            settings_nicebar_refresh_weather_if_needed(forceWeatherRefresh, nil);
        }
        if ([d boolForKey:kSettingsNiceBarLiteEnabled] && g_springboard_rc_ready) {
            settings_apply_nicebarlite_once_async("live settings");
        } else if (![d boolForKey:kSettingsNiceBarLiteEnabled]) {
            g_nicebarlite_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) nicebarlite_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if ([key isEqualToString:kSettingsLiveWPVideoPath]) {
        settings_notify_package_queue_changed_async();
        return;
    }

    if ([key isEqualToString:kSettingsLiveWPEnabled]) {
        if ([d boolForKey:kSettingsLiveWPEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        ![d boolForKey:kSettingsLiveWPEnabled] ||
                        !g_springboard_rc_ready) return;
                    ok = livewp_apply_in_session();
                    settings_mark_tweak_applied(kSettingsLiveWPEnabled, ok);
                }
                printf("[SETTINGS] live LiveWP apply result=%d\n", ok);
                if (ok) settings_start_livewp_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsLiveWPEnabled]) {
            g_livewp_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsLiveWPEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) livewp_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_gravitylite(key)) {
        if ([d boolForKey:kSettingsGravityLiteEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = settings_app_state_is_foreground()
                        ? settings_arm_gravitylite_for_background_start_locked(d, "live settings")
                        : settings_apply_gravitylite_from_defaults_locked(d);
                    settings_mark_tweak_applied(kSettingsGravityLiteEnabled,
                                                ok && [d boolForKey:kSettingsGravityLiteEnabled]);
                    printf("[SETTINGS] live Gravity Lite apply result=%d\n", ok);
                }
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsGravityLiteEnabled]) {
            __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
            settings_mark_tweak_applied(kSettingsGravityLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) gravitylite_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_axonlite(key)) {
        if ([d boolForKey:kSettingsAxonLiteEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (!settings_axonlite_can_poll_springboard()) {
                    printf("[SETTINGS] live Axon Lite apply skipped: %s\n",
                           settings_axonlite_pause_reason());
                    settings_start_axonlite_live_loop();
                    settings_notify_package_queue_changed_async();
                    return;
                }
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    if (!settings_axonlite_can_poll_springboard()) {
                        printf("[SETTINGS] live Axon Lite apply skipped inside lock: %s\n",
                               settings_axonlite_pause_reason());
                        settings_start_axonlite_live_loop();
                        settings_notify_package_queue_changed_async();
                        return;
                    }
                    bool ok = axonlite_apply_in_session();
                    settings_mark_tweak_applied(kSettingsAxonLiteEnabled,
                                                ok && [d boolForKey:kSettingsAxonLiteEnabled]);
                    printf("[SETTINGS] live Axon Lite apply result=%d\n", ok);
                }
                settings_start_axonlite_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsAxonLiteEnabled]) {
            g_axonlite_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsAxonLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) axonlite_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_statbar(key)) {
        if ([d boolForKey:kSettingsStatBarEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                       [d boolForKey:kSettingsStatBarShowNet],
                                                       [d boolForKey:kSettingsStatBarShowCPU],
                                                       [d boolForKey:kSettingsStatBarShowLabels],
                                                       [d boolForKey:kSettingsStatBarNetworkOnly]);
                    settings_mark_tweak_applied(kSettingsStatBarEnabled,
                                                ok && [d boolForKey:kSettingsStatBarEnabled]);
                    printf("[SETTINGS] live StatBar apply result=%d\n", ok);
                }
                settings_start_statbar_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsStatBarEnabled]) {
            g_statbar_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsStatBarEnabled, NO);
            settings_notify_package_queue_changed_async();
            settings_end_statbar_background_task_async("StatBar disabled");
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) statbar_stop_in_session();
                    }
                });
            }
        }
    }

    if (settings_key_is_rssi(key)) {
        if (!settings_rssi_install_allowed()) {
            if ([d boolForKey:kSettingsRSSIDisplayEnabled]) {
                [d setBool:NO forKey:kSettingsRSSIDisplayEnabled];
                [d synchronize];
            }
            g_rssi_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) rssidisplay_stop_in_session();
                    }
                });
            }
            return;
        }
        if ([d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                           [d boolForKey:kSettingsRSSIDisplayCell]);
                    settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled,
                                                ok && [d boolForKey:kSettingsRSSIDisplayEnabled]);
                    printf("[SETTINGS] live RSSI apply result=%d\n", ok);
                }
                settings_start_rssi_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsRSSIDisplayEnabled]) {
            g_rssi_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) rssidisplay_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_dark_tweak(key)) {
        if (!g_springboard_rc_ready || ![d boolForKey:key]) return;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            @synchronized (settings_rc_lock()) {
                if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                SettingsDarkTweaksResult result = settings_apply_dark_tweaks_from_defaults_locked(d);
                bool ok = settings_dark_tweaks_result_all_ok(result);
                if ([d boolForKey:kSettingsDSDisableAppLibrary])
                    settings_mark_tweak_applied(kSettingsDSDisableAppLibrary, result.disableAppLibrary);
                if ([d boolForKey:kSettingsDSDisableIconFlyIn])
                    settings_mark_tweak_applied(kSettingsDSDisableIconFlyIn, result.disableIconFlyIn);
                if ([d boolForKey:kSettingsDSZeroWakeAnimation])
                    settings_mark_tweak_applied(kSettingsDSZeroWakeAnimation, result.zeroWakeAnimation);
                if ([d boolForKey:kSettingsDSZeroBacklightFade])
                    settings_mark_tweak_applied(kSettingsDSZeroBacklightFade, result.zeroBacklightFade);
                if ([d boolForKey:kSettingsDSDoubleTapToLock])
                    settings_mark_tweak_applied(kSettingsDSDoubleTapToLock, result.doubleTapToLock);
                if ([d boolForKey:kSettingsDSDragCoefficientEnabled])
                    settings_mark_tweak_applied(kSettingsDSDragCoefficientEnabled, result.dragCoefficient);
                printf("[SETTINGS] live DarkSword tweak results appLib=%d flyIn=%d wake=%d backlight=%d dblTap=%d drag=%d all=%d\n",
                       [d boolForKey:kSettingsDSDisableAppLibrary] ? result.disableAppLibrary : -1,
                       [d boolForKey:kSettingsDSDisableIconFlyIn] ? result.disableIconFlyIn : -1,
                       [d boolForKey:kSettingsDSZeroWakeAnimation] ? result.zeroWakeAnimation : -1,
                       [d boolForKey:kSettingsDSZeroBacklightFade] ? result.zeroBacklightFade : -1,
                       [d boolForKey:kSettingsDSDoubleTapToLock] ? result.doubleTapToLock : -1,
                       [d boolForKey:kSettingsDSDragCoefficientEnabled] ? result.dragCoefficient : -1,
                       ok);
            }
            settings_notify_package_queue_changed_async();
        });
        return;
    }

    if (!settings_key_is_sbc(key) || !g_springboard_rc_ready) return;

    uint64_t generation = __sync_add_and_fetch(&g_sbc_live_apply_generation, 1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                   dispatch_get_global_queue(0, 0), ^{
        if (generation != g_sbc_live_apply_generation) return;
        if (settings_cleanup_in_progress()) return;

        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
            bool ok = settings_apply_sbc_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsSBCEnabled,
                                        ok && [d boolForKey:kSettingsSBCEnabled]);
            printf("[SETTINGS] live SBC apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

void settings_register_defaults(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{
        kSettingsAutoRunKexploit:    @NO,
        kSettingsRunSandboxEscape:   @YES,
        kSettingsRunPatchSandboxExt: @NO,
        kSettingsKeepAlive:          @YES,

        kSettingsSBCEnabled:    @NO,
        kSettingsSBCDockIcons:  @(kSBCDefaultDockIcons),
        kSettingsSBCCols:       @(kSBCDefaultCols),
        kSettingsSBCRows:       @(kSBCDefaultRows),
        kSettingsSBCHideLabels: @(kSBCDefaultHideLabels),

        kSettingsPowercuffEnabled: @NO,
        kSettingsPowercuffLevel:   @"nominal",

        kSettingsDSDisableAppLibrary: @NO,
        kSettingsDSDisableIconFlyIn:  @NO,
        kSettingsDSZeroWakeAnimation: @NO,
        kSettingsDSZeroBacklightFade: @NO,
        kSettingsDSDoubleTapToLock:   @NO,

        kSettingsDSDragCoefficientEnabled: @NO,
        kSettingsDSDragCoefficientValue:   @0.5,

        kSettingsLayoutExtrasEnabled:       @NO,
        kSettingsLayoutHomeExtraLeft:       @0,
        kSettingsLayoutHomeExtraRight:      @0,
        kSettingsLayoutHomeExtraTop:        @0,
        kSettingsLayoutHomeExtraBottom:     @0,
        kSettingsLayoutDockExtraHorizontal: @0,
        kSettingsLayoutHomeScalePct:        @100,
        kSettingsLayoutDockScalePct:        @100,

        kSettingsStatBarEnabled: @NO,
        kSettingsStatBarCelsius: @NO,
        kSettingsStatBarShowNet:    @NO,
        kSettingsStatBarShowCPU:    @YES,
        kSettingsStatBarShowLabels: @YES,
        kSettingsStatBarNetworkOnly: @NO,
        kSettingsStatBarRefreshRateSec: @(kStatBarDefaultRefreshRateSec),

        kSettingsNSBarEnabled: @NO,
        kSettingsNSBarPosition: @(NSBarPositionTopLeft),

        kSettingsNiceBarLiteEnabled: @NO,
        kSettingsNiceBarLiteCelsius: @YES,
        kSettingsNiceBarLiteLayoutTopSideInset: @0,
        kSettingsNiceBarLiteLayoutBottomSideInset: @0,
        kSettingsNiceBarLiteLayoutTopY: @0,
        kSettingsNiceBarLiteLayoutBottomY: @0,
        kSettingsNiceBarLiteLayoutCenterX: @0,
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotTopLeft): @(NiceBarLiteContentTimeFormat),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotTopRight): @(NiceBarLiteContentSystem),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotBottomLeft): @(NiceBarLiteContentSystem),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotBottomRight): @(NiceBarLiteContentOff),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotBottomCenter): @(NiceBarLiteContentOff),
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, NiceBarLiteSlotTopRight): @(NiceBarLiteSystemBatteryPercent),
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, NiceBarLiteSlotBottomLeft): @(NiceBarLiteSystemFreeRAM),
        settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, NiceBarLiteSlotTopLeft): @"HH:mm",
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, NiceBarLiteSlotTopRight): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, NiceBarLiteSlotBottomLeft): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotTopLeft): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotTopRight): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotBottomLeft): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotBottomRight): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotBottomCenter): @"en",
        kSettingsNiceBarLiteWeatherCache: @"Weather --",

        kSettingsRSSIDisplayEnabled: @NO,
        kSettingsRSSIDisplayWifi:    @YES,
        kSettingsRSSIDisplayCell:    @YES,

        kSettingsAxonLiteEnabled: @NO,

        kSettingsTypeBannerEnabled: @NO,
        kSettingsNotificationIslandEnabled: @NO,

        kSettingsFastLockXLiteEnabled: @NO,
        kSettingsFastLockXLiteBlockMusic: @NO,
        kSettingsFastLockXLiteBlockFlashlight: @NO,
        kSettingsFastLockXLiteBlockLowPower: @NO,
        kSettingsFastLockXLiteRetryInterval: @0.3,

        kSettingsGravityLiteEnabled: @NO,
        kSettingsGravityLiteDockEnabled: @YES,
        kSettingsGravityLiteMagnitudePct: @100,
        kSettingsGravityLiteBouncePct: @50,
        kSettingsGravityLiteFrictionPct: @50,
        kSettingsGravityLiteResistancePct: @50,
        kSettingsGravityLiteAngularResistancePct: @0,

        kSettingsStageStripEnabled: @NO,

        kSettingsLocationSimEnabled: @NO,
        kSettingsLocationSimLatitude: @(kLocationSimDefaultLatitude),
        kSettingsLocationSimLongitude: @(kLocationSimDefaultLongitude),
        kSettingsLocationSimAltitude: @(kLocationSimDefaultAltitude),
        kSettingsLocationSimHorizontalAccuracy: @(kLocationSimDefaultAccuracy),
        kSettingsLocationSimHostProcess: @"Maps",
        kSettingsLocationSimStarted: @NO,
        kSettingsIPADecryptorTargetBundleID: @"",
        kSettingsIPADecryptorAppStoreInput: @"",
        kSettingsIPADecryptorAppStoreID: @"",
        kSettingsIPADecryptorAppStoreName: @"",
        kSettingsIPADecryptorAppStoreVersion: @"",
        kSettingsIPADecryptorAppStoreURL: @"",
        kSettingsIPADecryptorDownloadedIPAPath: @"",
        kSettingsIPADecryptorDownloadStatus: @"Not started.",

        kSettingsThemerEnabled: @NO,
        kSettingsThemerThemeID: kThemerThemeNone,
        kSettingsThemerCustomThemePath: @"",
        kSettingsThemerCustomThemeName: @"",

        kSettingsSnowBoardLiteEnabled: @NO,
        kSettingsSnowBoardLiteSelectedThemeID: @"",

        kSettingsLiveWPEnabled: @NO,
        kSettingsLiveWPVideoPath: @"",

        kSettingsAppSwitcherGridEnabled: @NO,

        kSettingsExperimentalTweaksEnabled: @NO,

        kSettingsNanoMaxPairing:       @(kNanoDefaultMaxPairing),
        kSettingsNanoMinPairing:       @(kNanoDefaultMinPairing),
        kSettingsNanoMinPairingChipID: @(kNanoDefaultMinPairingChipID),
        kSettingsNanoMinQuickSwitch:   @(kNanoDefaultMinQuickSwitch),
    }];
    if (!cyanide_private_tweaks_available()) {
        BOOL changed = NO;
        NSArray<NSString *> *privateKeys = @[
            kSettingsRSSIDisplayEnabled,
            kSettingsTypeBannerEnabled,
            kSettingsNotificationIslandEnabled,
            kSettingsStageStripEnabled,
        ];
        for (NSString *key in privateKeys) {
            if ([defaults boolForKey:key]) {
                [defaults setBool:NO forKey:key];
                changed = YES;
            }
        }
        if (changed) [defaults synchronize];
    }
    if (!settings_experimental_access_allowed()) {
        if ([defaults boolForKey:kSettingsExperimentalTweaksEnabled]) {
            [defaults setBool:NO forKey:kSettingsExperimentalTweaksEnabled];
        }
        if ([defaults boolForKey:kSettingsRSSIDisplayEnabled]) {
            [defaults setBool:NO forKey:kSettingsRSSIDisplayEnabled];
        }
        if ([defaults boolForKey:kSettingsTypeBannerEnabled]) {
            [defaults setBool:NO forKey:kSettingsTypeBannerEnabled];
        }
        if ([defaults boolForKey:kSettingsNotificationIslandEnabled]) {
            [defaults setBool:NO forKey:kSettingsNotificationIslandEnabled];
        }
        if ([defaults boolForKey:kSettingsStageStripEnabled]) {
            [defaults setBool:NO forKey:kSettingsStageStripEnabled];
        }
        [defaults synchronize];
    } else if (![defaults boolForKey:kSettingsExperimentalTweaksEnabled]) {
        BOOL changed = NO;
        if ([defaults boolForKey:kSettingsRSSIDisplayEnabled]) {
            [defaults setBool:NO forKey:kSettingsRSSIDisplayEnabled];
            changed = YES;
        }
        if ([defaults boolForKey:kSettingsTypeBannerEnabled]) {
            [defaults setBool:NO forKey:kSettingsTypeBannerEnabled];
            changed = YES;
        }
        if ([defaults boolForKey:kSettingsNotificationIslandEnabled]) {
            [defaults setBool:NO forKey:kSettingsNotificationIslandEnabled];
            changed = YES;
        }
        if ([defaults boolForKey:kSettingsStageStripEnabled]) {
            [defaults setBool:NO forKey:kSettingsStageStripEnabled];
            changed = YES;
        }
        if (changed) [defaults synchronize];
    }
    if ([defaults boolForKey:kSettingsThemerEnabled]) {
        [defaults setBool:NO forKey:kSettingsThemerEnabled];
        [defaults synchronize];
    }
    if ([defaults boolForKey:kSettingsSnowBoardLiteEnabled] &&
        !settings_snowboardlite_has_selected_theme()) {
        [defaults setBool:NO forKey:kSettingsSnowBoardLiteEnabled];
        [defaults synchronize];
    }
    settings_install_screen_awake_observers();
}

static void settings_run_actions_internal(BOOL pendingOnly)
{
    if (!settings_device_supported()) {
        NSString *message = settings_unsupported_message();
        printf("[SETTINGS] run blocked: %s\n", message.UTF8String);
        log_user("[RUN] %s\n", message.UTF8String);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                object:[PackageQueue sharedQueue]];
        });
        settings_post_actions_complete_async(NO, message);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
            __sync_lock_test_and_set(&g_settings_actions_rerun_requested, 1);
            printf("[SETTINGS] actions already running; queued one follow-up run\n");
            log_user("[RUN] Already running. Queued one follow-up run for the latest package state.\n");
            return;
        }
        if (!pendingOnly && settings_any_registered_live_loop_running()) {
            settings_request_all_live_loops_stop("Apply Tweaks");
            settings_wait_live_loops_stopped_for_switch("Apply Tweaks");
        }
        log_session_begin();
        cyanide_start_session_uploads();
        BOOL runSucceeded = NO;
        BOOL runHadBlockingFailure = NO;
        NSString *runCompletionMessage = @"Run failed. Check the log for details.";
        BOOL startStageStripControlLoopAfterInstall = NO;
        @try {
            BOOL patchSandboxExt = [d boolForKey:kSettingsRunPatchSandboxExt];
            BOOL runPowercuff = settings_enabled_tweak_should_run(d, kSettingsPowercuffEnabled, pendingOnly);
            BOOL forceSpringBoardRefresh = runPowercuff &&
                                           settings_has_persistent_springboard_remote_call_user();
            BOOL springBoardPendingOnly = pendingOnly && !forceSpringBoardRefresh;
            BOOL statBarEnabled = [d boolForKey:kSettingsStatBarEnabled];
            BOOL nsBarEnabled = [d boolForKey:kSettingsNSBarEnabled];
            BOOL niceBarLiteEnabled = [d boolForKey:kSettingsNiceBarLiteEnabled];
            BOOL rssiEnabled = settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled];
            BOOL axonLiteEnabled = [d boolForKey:kSettingsAxonLiteEnabled];
            BOOL typeBannerEnabled = settings_typebanner_install_allowed() && [d boolForKey:kSettingsTypeBannerEnabled];
            BOOL notificationIslandEnabled = settings_notificationisland_install_allowed() && [d boolForKey:kSettingsNotificationIslandEnabled];
            BOOL appSwitcherGridEnabled = [d boolForKey:kSettingsAppSwitcherGridEnabled];
            BOOL themerEnabled = [d boolForKey:kSettingsThemerEnabled];
            BOOL snowboardLiteEnabled = [d boolForKey:kSettingsSnowBoardLiteEnabled];
            BOOL liveWPEnabled = [d boolForKey:kSettingsLiveWPEnabled];
            BOOL layoutExtrasEnabled = [d boolForKey:kSettingsLayoutExtrasEnabled];
            BOOL stageStripEnabled = settings_stagestrip_install_allowed() && [d boolForKey:kSettingsStageStripEnabled];
            BOOL gravityLiteEnabled = [d boolForKey:kSettingsGravityLiteEnabled];
            BOOL runSBC = settings_enabled_tweak_should_run(d, kSettingsSBCEnabled, springBoardPendingOnly);
            BOOL runDarkTweaks = settings_dark_tweaks_should_run(d, springBoardPendingOnly);
            BOOL runStatBar = settings_enabled_tweak_should_run(d, kSettingsStatBarEnabled, springBoardPendingOnly);
            BOOL runNSBar = settings_enabled_tweak_should_run(d, kSettingsNSBarEnabled, springBoardPendingOnly);
            BOOL runNiceBarLite = settings_enabled_tweak_should_run(d, kSettingsNiceBarLiteEnabled, springBoardPendingOnly);
            BOOL runRSSI = settings_rssi_install_allowed() && settings_enabled_tweak_should_run(d, kSettingsRSSIDisplayEnabled, springBoardPendingOnly);
            BOOL runAxonLite = settings_enabled_tweak_should_run(d, kSettingsAxonLiteEnabled, springBoardPendingOnly);
            BOOL runTypeBanner = settings_typebanner_install_allowed() && settings_enabled_tweak_should_run(d, kSettingsTypeBannerEnabled, springBoardPendingOnly);
            BOOL runNotificationIsland = settings_notificationisland_install_allowed() && settings_enabled_tweak_should_run(d, kSettingsNotificationIslandEnabled, springBoardPendingOnly);
            BOOL runAppSwitcherGrid = settings_enabled_tweak_should_run(d, kSettingsAppSwitcherGridEnabled, springBoardPendingOnly);
            BOOL runThemer = settings_enabled_tweak_should_run(d, kSettingsThemerEnabled, springBoardPendingOnly);
            BOOL runSnowBoardLite = settings_enabled_tweak_should_run(d, kSettingsSnowBoardLiteEnabled, springBoardPendingOnly);
            BOOL runLiveWP = settings_enabled_tweak_should_run(d, kSettingsLiveWPEnabled, springBoardPendingOnly);
            BOOL runLayoutExtras = settings_enabled_tweak_should_run(d, kSettingsLayoutExtrasEnabled, springBoardPendingOnly);
            BOOL runStageStrip = settings_stagestrip_install_allowed() && settings_enabled_tweak_should_run(d, kSettingsStageStripEnabled, springBoardPendingOnly);
            BOOL runGravityLite = settings_enabled_tweak_should_run(d, kSettingsGravityLiteEnabled, springBoardPendingOnly);
            BOOL stagePausesThemerLive = settings_themer_dynamic_updates_blocked_by_stage(d);
            if (stagePausesThemerLive) {
                settings_note_themer_stage_conflict(YES);
            }
            BOOL cleanupDisabledSpringBoardTweaks = settings_disabled_applied_springboard_cleanup_needed(d);
            BOOL needsSpringBoardWork = runSBC || runDarkTweaks || runStatBar || runNSBar || runNiceBarLite || runRSSI || runAxonLite || runGravityLite || runLayoutExtras || runTypeBanner || runNotificationIsland || runAppSwitcherGrid || runThemer || runSnowBoardLite || runLiveWP || runStageStrip || cleanupDisabledSpringBoardTweaks;
            BOOL runSandboxEscape = [d boolForKey:kSettingsRunSandboxEscape] && (!pendingOnly || needsSpringBoardWork);
            // TypeBanner prewarms its hidden SpringBoard window during Apply
            // and reuses the open SpringBoard session for text-only updates.
            BOOL needsSpringBoard = runSandboxEscape || needsSpringBoardWork || forceSpringBoardRefresh;

            BOOL hasRunWork = patchSandboxExt || runPowercuff || needsSpringBoard;
            NSUInteger total = hasRunWork ? 1 : 0;
            if (patchSandboxExt) total++;
            if (runPowercuff) total++;
            if (needsSpringBoard) total++;
            if (runSandboxEscape) total++;
            if (runSBC) total++;
            if (runDarkTweaks) total++;
            if (runLayoutExtras) total++;
            if (runThemer) total++;
            if (runSnowBoardLite) total++;
            if (runLiveWP) total++;
            if (runStatBar) total++;
            if (runNSBar) total++;
            if (runNiceBarLite) total++;
            if (runRSSI) total++;
            if (runAxonLite) total++;
            if (runGravityLite) total++;
            if (runTypeBanner) total++;
            if (runNotificationIsland) total++;
            if (runAppSwitcherGrid) total++;
            if (runStageStrip) total++;
            if (cleanupDisabledSpringBoardTweaks) total++;
            NSUInteger step = 0;
            settings_log_run_context();
            NSMutableArray *enabledTweaks = [NSMutableArray array];
            if (runSBC) [enabledTweaks addObject:@"layout"];
            if (runLayoutExtras) [enabledTweaks addObject:@"extras"];
            if (runStatBar) [enabledTweaks addObject:@"statbar"];
            if (runNSBar) [enabledTweaks addObject:@"nsbar"];
            if (runNiceBarLite) [enabledTweaks addObject:@"nicebar"];
            if (runRSSI) [enabledTweaks addObject:@"rssi"];
            if (runAxonLite) [enabledTweaks addObject:@"axon"];
            if (runNotificationIsland) [enabledTweaks addObject:@"notification-island"];
            if (runAppSwitcherGrid) [enabledTweaks addObject:@"app-switcher-grid"];
            if (runGravityLite) [enabledTweaks addObject:[NSString stringWithFormat:@"gravity(%ld%%)", (long)[d integerForKey:kSettingsGravityLiteMagnitudePct]]];
            if (runPowercuff) [enabledTweaks addObject:[NSString stringWithFormat:@"power(%@)", [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal"]];
            if (runDarkTweaks) [enabledTweaks addObject:@"dark"];
            if (runThemer) [enabledTweaks addObject:@"themer"];
            if (runSnowBoardLite) [enabledTweaks addObject:@"snowboardlite"];
            if (runLiveWP) [enabledTweaks addObject:@"livewp"];
            if (runTypeBanner) [enabledTweaks addObject:@"typebanner"];
            if (runStageStrip) [enabledTweaks addObject:@"stagestrip"];
            if (cleanupDisabledSpringBoardTweaks) [enabledTweaks addObject:@"cleanup"];
            if (forceSpringBoardRefresh) [enabledTweaks addObject:@"springboard-refresh"];
            log_user("[PLAN] %lu stages: %s\n",
                     (unsigned long)total,
                     enabledTweaks.count ? [[enabledTweaks componentsJoinedByString:@", "] UTF8String] : "none");
            cyanide_upload_log_milestone(@"run-plan");

            if (!hasRunWork) {
                if (!statBarEnabled) g_statbar_live_stop_requested = 1;
                if (!nsBarEnabled) g_nsbar_live_stop_requested = 1;
                if (!niceBarLiteEnabled) g_nicebarlite_live_stop_requested = 1;
                if (!rssiEnabled) g_rssi_live_stop_requested = 1;
                if (!axonLiteEnabled) g_axonlite_live_stop_requested = 1;
                if (!typeBannerEnabled) g_typebanner_live_stop_requested = 1;
                if (!notificationIslandEnabled) g_notificationisland_live_stop_requested = 1;
                if (!themerEnabled && !snowboardLiteEnabled) g_themer_live_stop_requested = 1;
                if (!liveWPEnabled) g_livewp_live_stop_requested = 1;
                if (!gravityLiteEnabled) settings_request_gravitylite_stop();
                if (!stageStripEnabled) settings_request_stagestrip_stop();
                log_user("[DONE] No pending runtime changes to apply.\n");
                runSucceeded = YES;
                runCompletionMessage = @"Done. No pending runtime changes to apply.";
                cyanide_upload_log_milestone(@"run-noop");
                return;
            }

            settings_progress(&step, total, "Racing kernel allocator for r/w primitives");
            if (!settings_ensure_kexploit()) {
                log_user("[RUN] Failed: kernel primitives were not acquired. Please try running chain again.\n");
                runCompletionMessage = @"Failed: kernel primitives were not acquired. Please try running chain again.";
                cyanide_upload_log_milestone(@"krw-failed");
                return;
            }
            if (settings_ios_vphone_range() && remote_call_vphone_springboard_bridge_available() && !vphone_krw_ready()) {
                log_user("[OK] vphone SpringBoard bridge armed — injection staged without app-side KRW.\n");
            } else {
                log_user("[OK] Kernel r/w armed — injection staged.\n");
            }
            cyanide_upload_log_milestone(@"krw-ready");

            if (patchSandboxExt) {
                settings_progress(&step, total, "Patching sandbox-extension issue path");
                escape_sbx_demo3();
                log_user("[OK] Sandbox extension issue path patched.\n");
                cyanide_upload_log_milestone(@"sandbox-ext-patched");
            }
            if (runPowercuff) {
                settings_progress(&step, total, "Applying Powercuff via thermalmonitord");
                if (g_springboard_rc_ready || settings_any_registered_live_loop_running()) {
                    settings_request_all_live_loops_stop("Powercuff process switch");
                    settings_wait_live_loops_stopped_for_switch("Powercuff process switch");
                }
                @synchronized (settings_rc_lock()) {
                    // This is only a transient RemoteCall target switch. Do
                    // not run SpringBoard tweak stop paths or clear applied
                    // package state; enabled tweaks are reapplied below.
                    settings_destroy_springboard_remote_call_locked_internal("switching to thermalmonitord", NO);
                    NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal";
                    bool ok = powercuff_apply(lvl.UTF8String);
                    settings_mark_tweak_applied(kSettingsPowercuffEnabled,
                                                ok && [d boolForKey:kSettingsPowercuffEnabled]);
                    log_user("%s Powercuff %s through thermalmonitord.\n",
                             ok ? "[OK]" : "[WARN]",
                             ok ? "applied" : "did not apply cleanly");
                    cyanide_upload_log_milestone(ok ? @"powercuff-applied" : @"powercuff-failed");
                }
            }

            if (needsSpringBoard) {
                @synchronized (settings_rc_lock()) {
                    settings_progress(&step, total, "Opening SpringBoard injection channel");
                    if (!settings_ensure_springboard_remote_call_locked()) {
                        log_user("[RUN] Failed: could not open the SpringBoard control session. Please try installing tweaks again.\n");
                        runCompletionMessage = @"Failed: could not open the SpringBoard control session. Please try installing tweaks again.";
                        cyanide_upload_log_milestone(@"springboard-remote-call-failed");
                        return;
                    }
                    log_user("[OK] SpringBoard channel open.\n");
                    cyanide_upload_log_milestone(@"springboard-remote-call-ready");

                    if (runSandboxEscape && !g_springboard_sandbox_escaped) {
                        settings_progress(&step, total, "Lifting SpringBoard filesystem sandbox");
                        int sbx = escape_sbx_demo2_in_session();
                        g_springboard_sandbox_escaped = (sbx == 0);
                        log_user("%s Filesystem sandbox %s.\n",
                                 sbx == 0 ? "[OK]" : "[WARN]",
                                 sbx == 0 ? "lifted — access granted" : "lift returned a warning");
                        cyanide_upload_log_milestone(sbx == 0 ? @"springboard-sandbox-token-ready" : @"springboard-sandbox-token-warning");
                    } else if (runSandboxEscape) {
                        settings_progress(&step, total, "Reusing sandbox token from prior run");
                        log_user("[OK] Sandbox already lifted — reusing token.\n");
                        cyanide_upload_log_milestone(@"springboard-sandbox-token-reused");
                    }

                    if (cleanupDisabledSpringBoardTweaks) {
                        settings_progress(&step, total, "Stopping disabled SpringBoard tweaks");
                        settings_stop_disabled_applied_springboard_tweaks_locked(d);
                        cyanide_upload_log_milestone(@"disabled-springboard-tweaks-stopped");
                    }

                    if (runTypeBanner) {
                        bool ok = typebanner_prepare_in_springboard_session();
                        log_user("%s TypeBanner overlay window %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "prewarmed" : "did not prewarm");
                        cyanide_upload_log_milestone(ok ? @"typebanner-overlay-prewarmed" : @"typebanner-overlay-prewarm-failed");
                    }

                    if (runSBC) {
                        settings_progress(&step, total, "Applying icon layout caches");
                        bool ok = settings_apply_sbc_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsSBCEnabled,
                                                    ok && [d boolForKey:kSettingsSBCEnabled]);
                        log_user("%s Home screen layout %s; dock=%ld home=%ldx%ld.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "may need a refresh",
                                 (long)[d integerForKey:kSettingsSBCDockIcons],
                                 (long)[d integerForKey:kSettingsSBCCols],
                                 (long)[d integerForKey:kSettingsSBCRows]);
                        cyanide_upload_log_milestone(ok ? @"sbc-applied" : @"sbc-warning");
                    }

                    if (runDarkTweaks) {
                        settings_progress(&step, total, "Applying DarkSword runtime hooks");
                        SettingsDarkTweaksResult result = settings_apply_dark_tweaks_from_defaults_locked(d);
                        bool ok = settings_dark_tweaks_result_all_ok(result);
                        if ([d boolForKey:kSettingsDSDisableAppLibrary])
                            settings_mark_tweak_applied(kSettingsDSDisableAppLibrary, result.disableAppLibrary);
                        if ([d boolForKey:kSettingsDSDisableIconFlyIn])
                            settings_mark_tweak_applied(kSettingsDSDisableIconFlyIn, result.disableIconFlyIn);
                        if ([d boolForKey:kSettingsDSZeroWakeAnimation])
                            settings_mark_tweak_applied(kSettingsDSZeroWakeAnimation, result.zeroWakeAnimation);
                        if ([d boolForKey:kSettingsDSZeroBacklightFade])
                            settings_mark_tweak_applied(kSettingsDSZeroBacklightFade, result.zeroBacklightFade);
                        if ([d boolForKey:kSettingsDSDoubleTapToLock])
                            settings_mark_tweak_applied(kSettingsDSDoubleTapToLock, result.doubleTapToLock);
                        if ([d boolForKey:kSettingsDSDragCoefficientEnabled])
                            settings_mark_tweak_applied(kSettingsDSDragCoefficientEnabled, result.dragCoefficient);
                        printf("[SETTINGS] DarkSword tweak results appLib=%d flyIn=%d wake=%d backlight=%d dblTap=%d drag=%d all=%d\n",
                               [d boolForKey:kSettingsDSDisableAppLibrary] ? result.disableAppLibrary : -1,
                               [d boolForKey:kSettingsDSDisableIconFlyIn] ? result.disableIconFlyIn : -1,
                               [d boolForKey:kSettingsDSZeroWakeAnimation] ? result.zeroWakeAnimation : -1,
                               [d boolForKey:kSettingsDSZeroBacklightFade] ? result.zeroBacklightFade : -1,
                               [d boolForKey:kSettingsDSDoubleTapToLock] ? result.doubleTapToLock : -1,
                               [d boolForKey:kSettingsDSDragCoefficientEnabled] ? result.dragCoefficient : -1,
                               ok);
                        log_user("%s DarkSword hooks %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "may need a refresh");
                        cyanide_upload_log_milestone(ok ? @"darksword-tweaks-applied" : @"darksword-tweaks-warning");
                    }

                    if (runLayoutExtras) {
                        settings_progress(&step, total, "Applying Home Layout Extras");
                        bool ok = settings_apply_layout_extras_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsLayoutExtrasEnabled, ok);
                        printf("[SETTINGS] Layout extras result=%d\n", ok);
                        log_user("%s Home Layout Extras %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"layout-extras-applied" : @"layout-extras-warning");
                    }

                    if (runThemer) {
                        settings_progress(&step, total, "Applying Icon Theme Engine");
                        bool ok = settings_apply_themer_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsThemerEnabled, ok);
                        printf("[SETTINGS] Themer result=%d\n", ok);
                        log_user("%s Icon Theme Engine %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"themer-applied" : @"themer-warning");
                        if (ok) {
                            settings_start_themer_live_loop();
                        }
                    }

                    if (runSnowBoardLite) {
                        settings_progress(&step, total, "Applying SnowBoard Lite theme");
                        bool ok = settings_apply_snowboardlite_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsSnowBoardLiteEnabled,
                                                    ok && [d boolForKey:kSettingsSnowBoardLiteEnabled]);
                        printf("[SETTINGS] SnowBoard Lite result=%d\n", ok);
                        log_user("%s SnowBoard Lite %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "theme applied" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"snowboard-lite-applied" : @"snowboard-lite-warning");
                        if (ok) {
                            settings_start_themer_live_loop();
                        }
                    }

                    if (runGravityLite) {
                        settings_progress(&step, total, "Starting Gravity Lite icon physics");
                        log_user("[GRAVITY] Preparing icon physics state...\n");
                        __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
                        settings_stop_gravity_motion();
                        gravitylite_stop_in_session();
                        GravityLiteConfig glConfig = settings_gravitylite_config_from_defaults(d);
                        bool ok = gravitylite_apply_in_session(glConfig);
                        settings_mark_tweak_applied(kSettingsGravityLiteEnabled,
                                                    ok && [d boolForKey:kSettingsGravityLiteEnabled]);
                        if (ok) {
                            log_user("[GRAVITY] Starting tilt sensor feed...\n");
                            settings_start_gravity_motion(glConfig.magnitude,
                                                          glConfig.explosionForce);
                        }
                        if (ok) {
                            log_user("[OK] Gravity Lite active.\n");
                            cyanide_upload_log_milestone(@"gravity-lite-applied");
                        } else {
                            log_user("[WARN] Gravity Lite did not start cleanly.\n");
                            cyanide_upload_log_milestone(@"gravity-lite-warning");
                            runHadBlockingFailure = YES;
                            runCompletionMessage = @"Gravity Lite did not start cleanly.";
                        }
                    } else if (!gravityLiteEnabled) {
                        __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
                        settings_stop_gravity_motion();
                        gravitylite_stop_in_session();
                    }

                    if (runStatBar) {
                        settings_progress(&step, total, "Starting StatBar overlay and live feed");
                        bool ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                           [d boolForKey:kSettingsStatBarShowNet],
                                                           [d boolForKey:kSettingsStatBarShowCPU],
                                                           [d boolForKey:kSettingsStatBarShowLabels],
                                                           [d boolForKey:kSettingsStatBarNetworkOnly]);
                        settings_mark_tweak_applied(kSettingsStatBarEnabled,
                                                    ok && [d boolForKey:kSettingsStatBarEnabled]);
                        log_user("%s StatBar %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "showing thermal + memory overlay" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"statbar-initial-applied" : @"statbar-initial-failed");
                    }

                    if (runNSBar) {
                        settings_progress(&step, total, "Starting NSBar network speed overlay");
                        bool ok = nsbar_apply_in_session((NSBarPosition)[d integerForKey:kSettingsNSBarPosition]);
                        settings_mark_tweak_applied(kSettingsNSBarEnabled,
                                                    ok && [d boolForKey:kSettingsNSBarEnabled]);
                        printf("[SETTINGS] NSBar result=%d\n", ok);
                        log_user("%s NSBar %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "showing network speed" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"nsbar-initial-applied" : @"nsbar-initial-failed");
                    }

                    if (runNiceBarLite) {
                        settings_progress(&step, total, "Starting NiceBar Lite labels");
                        settings_nicebar_refresh_weather_if_needed(!settings_nicebar_has_resolved_weather(d), nil);
                        bool ok = settings_apply_nicebarlite_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled,
                                                    ok && [d boolForKey:kSettingsNiceBarLiteEnabled]);
                        printf("[SETTINGS] NiceBar Lite result=%d\n", ok);
                        log_user("%s NiceBar Lite %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "labels active" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"nicebar-lite-initial-applied" : @"nicebar-lite-initial-failed");
                    }

                    if (runRSSI) {
                        settings_progress(&step, total, "Starting RSSI dBm signal overlays");
                        bool ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                               [d boolForKey:kSettingsRSSIDisplayCell]);
                        settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled,
                                                    ok && [d boolForKey:kSettingsRSSIDisplayEnabled]);
                        printf("[SETTINGS] RSSI result=%d\n", ok);
                        log_user("%s RSSI %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "showing live signal strength (dBm)" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"rssi-initial-applied" : @"rssi-initial-failed");
                    }

                    if (runLiveWP) {
                        settings_progress(&step, total, "Starting LiveWP video wallpaper");
                        bool ok = livewp_apply_in_session();
                        settings_mark_tweak_applied(kSettingsLiveWPEnabled,
                                                    ok && [d boolForKey:kSettingsLiveWPEnabled]);
                        printf("[SETTINGS] LiveWP result=%d\n", ok);
                        log_user("%s LiveWP %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "video wallpaper active" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"livewp-initial-applied" : @"livewp-initial-failed");
                    }

                    if (runAxonLite) {
                        settings_progress(&step, total, "Starting Axon Lite notification hub");
                        bool ok = false;
                        bool deferred = false;
                        if (settings_axonlite_can_poll_springboard()) {
                            ok = axonlite_apply_in_session();
                            deferred = !ok && !axonlite_initial_cache_ready();
                        } else {
                            deferred = true;
                            printf("[SETTINGS] Axon Lite initial apply skipped: %s\n",
                                   settings_axonlite_pause_reason());
                        }
                        settings_mark_tweak_applied(kSettingsAxonLiteEnabled,
                                                    (ok || deferred) && [d boolForKey:kSettingsAxonLiteEnabled]);
                        printf("[SETTINGS] Axon Lite result=%d deferred=%d\n", ok, deferred);
                        log_user("%s Axon Lite %s.\n",
                                 (ok || deferred) ? "[OK]" : "[WARN]",
                                 ok ? "hub active — watching for notifications" :
                                 (deferred ? "standing by — fires when notifications appear" : "did not start cleanly"));
                        cyanide_upload_log_milestone(ok ? @"axon-lite-initial-applied" :
                                                     (deferred ? @"axon-lite-initial-deferred" : @"axon-lite-initial-failed"));
                    }

                    if (runNotificationIsland) {
                        settings_progress(&step, total, "Starting Notification Island");
                        bool ok = notificationisland_apply_in_session();
                        settings_mark_tweak_applied(kSettingsNotificationIslandEnabled,
                                                    ok && [d boolForKey:kSettingsNotificationIslandEnabled]);
                        printf("[SETTINGS] Notification Island result=%d\n", ok);
                        log_user("%s Notification Island %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "watching incoming banners" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"notification-island-initial-applied" :
                                                         @"notification-island-initial-failed");
                    }

                    if (runAppSwitcherGrid) {
                        settings_progress(&step, total, "Enabling App Switcher Grid");
                        bool ok = appswitchergrid_apply_in_session();
                        settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled,
                                                    ok && [d boolForKey:kSettingsAppSwitcherGridEnabled]);
                        printf("[SETTINGS] App Switcher Grid result=%d\n", ok);
                        log_user("%s App Switcher Grid %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "enabled" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"app-switcher-grid-applied" : @"app-switcher-grid-failed");
                    } else if (!appSwitcherGridEnabled) {
                        appswitchergrid_stop_in_session();
                    }

                    if (runStageStrip) {
                        settings_progress(&step, total, "Installing Dynamic Stage Lite");
                        bool ok = stagestrip_apply_in_session(4);
                        startStageStripControlLoopAfterInstall = ok;
                        settings_mark_tweak_applied(kSettingsStageStripEnabled,
                                                    ok && [d boolForKey:kSettingsStageStripEnabled]);
                        printf("[SETTINGS] Dynamic Stage Lite result=%d\n", ok);
                        log_user("%s Dynamic Stage Lite %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "overlay active" : "did not install cleanly");
                        cyanide_upload_log_milestone(ok ? @"stagestrip-initial-applied" : @"stagestrip-initial-failed");
                    } else if (!stageStripEnabled) {
                        // Uninstall path: tear down the overlay if one survived
                        // from a prior Run. No-op when the strip was never up.
                        stagestrip_stop_in_session();
                    }
                }

                if (runStatBar) {
                    settings_start_statbar_live_loop();
                } else if (!statBarEnabled) {
                    g_statbar_live_stop_requested = 1;
                }
                if (runNSBar) {
                    settings_start_nsbar_live_loop();
                } else if (!nsBarEnabled) {
                    g_nsbar_live_stop_requested = 1;
                }
                if (runNiceBarLite) {
                    settings_start_nicebarlite_live_loop();
                } else if (!niceBarLiteEnabled) {
                    g_nicebarlite_live_stop_requested = 1;
                }
                if (runRSSI) {
                    settings_start_rssi_live_loop();
                } else if (!rssiEnabled) {
                    g_rssi_live_stop_requested = 1;
                }
                if (runLiveWP) {
                    settings_start_livewp_live_loop();
                } else if (!liveWPEnabled) {
                    g_livewp_live_stop_requested = 1;
                }
                if (runAxonLite) {
                    settings_start_axonlite_live_loop();
                } else if (!axonLiteEnabled) {
                    g_axonlite_live_stop_requested = 1;
                }
                if (runNotificationIsland) {
                    settings_start_notificationisland_live_loop();
                } else if (!notificationIslandEnabled) {
                    g_notificationisland_live_stop_requested = 1;
                }
            }

            if (runTypeBanner) {
                settings_progress(&step, total, "Starting TypeBanner daemon poll");
                settings_mark_tweak_applied(kSettingsTypeBannerEnabled, YES);
                log_user("[OK] TypeBanner watching imagent for incoming typing indicators.\n");
                cyanide_upload_log_milestone(@"typebanner-live-starting");
                // Daemon-only detection avoids foregrounding Messages and
                // avoids the MobileSMS synthetic-thread PAC/0x401 crash path.
                printf("[TYPEBANNER] daemon-only: starting live loop without sms launch\n");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)kTypeBannerInitialDaemonSettleUS * NSEC_PER_USEC),
                               dispatch_get_global_queue(0, 0), ^{
                    settings_start_typebanner_live_loop();
                });
            } else if (!typeBannerEnabled) {
                g_typebanner_live_stop_requested = 1;
            }
            if (startStageStripControlLoopAfterInstall) {
                stagestrip_start_control_loop();
            }
            if (runStatBar || runNSBar || runNiceBarLite || runRSSI || runAxonLite || runTypeBanner || runNotificationIsland || runLiveWP || startStageStripControlLoopAfterInstall)
                cyanide_upload_log_milestone(@"live-tweaks-started");

            if (!settings_has_persistent_springboard_remote_call_user()) {
                BOOL closedNonLiveRemoteCall = NO;
                @synchronized (settings_rc_lock()) {
                    if (!settings_has_persistent_springboard_remote_call_user() &&
                        g_springboard_rc_ready) {
                        // Closing the synthetic-call channel does not undo
                        // one-shot SpringBoard patches like SBCustomizer's
                        // icon-label/layout changes. Keep the applied marker
                        // so Installer doesn't immediately re-queue a package
                        // that just finished successfully; SpringBoard restart,
                        // manual cleanup, and respring cleanup still clear it.
                        settings_destroy_springboard_remote_call_locked_internal_ex("non-live run complete",
                                                                                   YES,
                                                                                   YES);
                        closedNonLiveRemoteCall = YES;
                    }
                }
                if (closedNonLiveRemoteCall) {
                    log_user("[OK] SpringBoard channel released — no persistent hooks.\n");
                    cyanide_upload_log_milestone(@"springboard-remote-call-closed");
                }
            }

            if (runHadBlockingFailure) {
                log_user("[RUN] Incomplete: a requested live tweak did not become active.\n");
                cyanide_upload_log_milestone(@"run-incomplete");
                return;
            }

            log_user("[DONE] All tweaks active in-session — live until respring.\n");
            runSucceeded = YES;
            runCompletionMessage = @"Done. All tweaks applied in-session.";
            cyanide_upload_log_milestone(@"run-complete");
        } @finally {
            // Close any legacy uploader state before the final snapshot.
            cyanide_stop_session_uploads();
            BOOL keepLogOpenForLiveTweaks = runSucceeded &&
                (startStageStripControlLoopAfterInstall || settings_any_registered_live_loop_running());
            if (keepLogOpenForLiveTweaks) {
                printf("[LOG] keeping session log open for live tweak events.\n");
            } else {
                log_session_end();
            }
            __sync_lock_release(&g_settings_actions_running);
            settings_reconcile_applied_from_defaults();
            if (__sync_bool_compare_and_swap(&g_settings_actions_rerun_requested, 1, 0)) {
                log_user("[RUN] Applying queued follow-up run.\n");
                settings_run_actions_internal(pendingOnly);
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSDictionary *completionInfo = @{
                    kSettingsActionsDidCompleteSuccessKey: @(runSucceeded),
                    kSettingsActionsDidCompleteMessageKey: runCompletionMessage ?: @""
                };
                [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                    object:[PackageQueue sharedQueue]];
                [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsActionsDidCompleteNotification
                                                                    object:nil
                                                                  userInfo:completionInfo];
                cyanide_upload_log_if_enabled();
            });
        }
    });
}

void settings_run_actions(void)
{
    settings_run_actions_internal(NO);
}

void settings_run_pending_actions(void)
{
    settings_run_actions_internal(YES);
}

// SettingsSection and RootSection enum typedefs are declared in CyanideEngine+Internal.h

// Loads Cyanide/Changelog.plist (generated at build time by
// scripts/gen-changelog.sh from the last N release tags). Each entry is a
// dict with keys "version" (NSString), "date" (ISO yyyy-MM-dd NSString), and
// "changes" (NSArray<NSString *>). Empty array when the plist is missing or
// malformed — the "What's New" section silently hides itself in that case.
NSArray<NSDictionary *> *settings_changelog_entries(void)
{
    static NSArray<NSDictionary *> *entries = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Changelog" ofType:@"plist"];
        NSArray *raw = path ? [NSArray arrayWithContentsOfFile:path] : nil;
        NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
        for (id obj in raw) {
            if (![obj isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *d = (NSDictionary *)obj;
            NSString *version = d[@"version"];
            NSArray *changes = d[@"changes"];
            if (![version isKindOfClass:[NSString class]] || version.length == 0) continue;
            if (![changes isKindOfClass:[NSArray class]] || changes.count == 0) continue;
            [out addObject:d];
        }
        entries = [out copy];
    });
    return entries;
}

// "2026-05-15" -> "May 15". Falls back to the raw string on parse failure.
NSString *settings_pretty_date_for_iso(NSString *iso)
{
    if (!iso.length) return @"";
    static NSDateFormatter *in = nil;
    static NSDateFormatter *out = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        in  = [[NSDateFormatter alloc] init];
        in.dateFormat = @"yyyy-MM-dd";
        in.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        out = [[NSDateFormatter alloc] init];
        out.dateFormat = @"MMM d";
        out.locale = [NSLocale currentLocale];
    });
    NSDate *date = [in dateFromString:iso];
    return date ? [out stringFromDate:date] : iso;
}

// ---------------------------------------------------------------------------
// Utility — safe to call from Swift via the bridging header
// ---------------------------------------------------------------------------

BOOL cyanide_private_tweaks_compiled_in(void) {
    return CYANIDE_PRIVATE_TWEAKS_AVAILABLE != 0;
}

void cyanide_log(const char *msg) {
    log_write(msg);
}
