//
//  livewp.m
//  LiveWP (Live Wallpaper) implementation
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//
//  策略：一个 AVPlayer 驱动两个 AVPlayerLayer，
//  分别插到 SBHomeScreenWindow 和 SBCoverSheetWindow 的 layer index 0。
//

#import "livewp.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <stdio.h>
#import <time.h>
#import <unistd.h>

// ============================================================================
// MARK: - Global State
// ============================================================================

static uint64_t g_livewp_player = 0;
static uint64_t g_livewp_home_layer = 0;       // 主屏幕的 AVPlayerLayer
static uint64_t g_livewp_lock_layer = 0;       // 锁屏的 AVPlayerLayer
static uint64_t g_livewp_player_item = 0;
static uint64_t g_livewp_looper = 0;
static uint64_t g_livewp_home_window = 0;
static uint64_t g_livewp_lock_window = 0;
static bool g_livewp_configured = false;
static bool g_livewp_paused = false;

// Manually flip to true when collecting detailed LiveWP timing logs.
static const bool kLiveWPDebugLogging = false;

typedef struct { double x, y, w, h; } LiveWPRect;

#define LIVEWP_DEBUG_LOG(fmt, ...) do { \
    if (kLiveWPDebugLogging) log_user(fmt, ##__VA_ARGS__); \
} while (0)

static uint64_t livewp_now_us(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ((uint64_t)ts.tv_sec * 1000000ULL) + ((uint64_t)ts.tv_nsec / 1000ULL);
}

static unsigned long long livewp_elapsed_ms_since(uint64_t startUs)
{
    if (startUs == 0) return 0;
    uint64_t nowUs = livewp_now_us();
    if (nowUs <= startUs) return 0;
    return (unsigned long long)((nowUs - startUs + 500ULL) / 1000ULL);
}

static bool livewp_is_kind_of_class_fast(uint64_t obj, uint64_t cls)
{
    if (!r_is_objc_ptr(obj) || !r_is_objc_ptr(cls)) return false;

    uint64_t cur = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    for (int depth = 0; r_is_objc_ptr(cur) && depth < 16; depth++) {
        if (cur == cls) return true;
        cur = r_dlsym_call(R_TIMEOUT, "class_getSuperclass", cur, 0, 0, 0, 0, 0, 0, 0);
    }
    return false;
}

// ============================================================================
// MARK: - Keys
// ============================================================================

NSString * const kLiveWPEnabled = @"LiveWPEnabled";
NSString * const kLiveWPVideoPath = @"LiveWPVideoPath";

// ============================================================================
// MARK: - Forward Declarations
// ============================================================================

static bool livewp_create_player(NSString *videoPath);
static bool livewp_attach_and_play(void);
static void livewp_cleanup(void);

// ============================================================================
// MARK: - Public Interface
// ============================================================================

// 从相对路径拼接为绝对路径（兼容旧版绝对路径）
NSString *livewp_absolute_path(void) {
    NSString *rel = [[NSUserDefaults standardUserDefaults] stringForKey:kLiveWPVideoPath];
    if (!rel || rel.length == 0) return nil;
    if ([rel hasPrefix:@"/"]) return rel;
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByAppendingPathComponent:rel];
}

bool livewp_apply_in_session(void)
{
    uint32_t oldSettleUS = r_settle_us(0);
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] start configured=%d paused=%d\n",
                     g_livewp_configured ? 1 : 0, g_livewp_paused ? 1 : 0);
    bool ok = false;

    NSString *videoPath = livewp_absolute_path();
    if (!videoPath || videoPath.length == 0) {
        log_user("[LIVEWP] No video path configured.\n");
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] end ok=0 reason=no-path total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] path=%s\n", videoPath.UTF8String);

    if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        log_user("[LIVEWP] Video file not found: %s\n", videoPath.UTF8String);
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] end ok=0 reason=file-missing total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }

    if (g_livewp_configured) {
        uint64_t stopStartUs = livewp_now_us();
        livewp_stop_in_session();
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] old-player-stop elapsed=%llums\n",
                         livewp_elapsed_ms_since(stopStartUs));
        usleep(100000);
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] settle-sleep elapsed=100ms\n");
    }

    uint64_t createStartUs = livewp_now_us();
    bool created = livewp_create_player(videoPath);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] create-player ok=%d elapsed=%llums\n",
                     created ? 1 : 0, livewp_elapsed_ms_since(createStartUs));
    if (!created) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] end ok=0 reason=create-player total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }

    uint64_t attachStartUs = livewp_now_us();
    bool attached = livewp_attach_and_play();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] attach-and-play ok=%d elapsed=%llums\n",
                     attached ? 1 : 0, livewp_elapsed_ms_since(attachStartUs));
    if (!attached) {
        livewp_cleanup();
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] end ok=0 reason=attach total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }

    g_livewp_configured = true;
    g_livewp_paused = false;
    log_user("[LIVEWP] OK: playing.\n");
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][apply] end ok=1 total=%llums player=0x%llx homeLayer=0x%llx lockLayer=0x%llx\n",
                     livewp_elapsed_ms_since(startUs), g_livewp_player,
                     g_livewp_home_layer, g_livewp_lock_layer);
    ok = true;

out:
    r_settle_us(oldSettleUS);
    return ok;
}

bool livewp_stop_in_session(void)
{
    uint32_t oldSettleUS = r_settle_us(0);
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][stop] start configured=%d player=0x%llx homeLayer=0x%llx lockLayer=0x%llx\n",
                     g_livewp_configured ? 1 : 0, g_livewp_player,
                     g_livewp_home_layer, g_livewp_lock_layer);
    if (!g_livewp_configured) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][stop] end ok=1 reason=not-configured total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        r_settle_us(oldSettleUS);
        return true;
    }

    if (r_is_objc_ptr(g_livewp_player))
        r_msg2_main(g_livewp_player, "pause", 0, 0, 0, 0);

    if (r_is_objc_ptr(g_livewp_home_layer))
        r_msg2_main(g_livewp_home_layer, "removeFromSuperlayer", 0, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_lock_layer))
        r_msg2_main(g_livewp_lock_layer, "removeFromSuperlayer", 0, 0, 0, 0);

    livewp_cleanup();
    g_livewp_configured = false;
    g_livewp_paused = false;
    log_user("[LIVEWP] stopped.\n");
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][stop] end ok=1 total=%llums\n",
                     livewp_elapsed_ms_since(startUs));
    r_settle_us(oldSettleUS);
    return true;
}

bool livewp_repair_in_session(void)
{
    uint32_t oldSettleUS = r_settle_us(0);
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][repair] start configured=%d paused=%d\n",
                     g_livewp_configured ? 1 : 0, g_livewp_paused ? 1 : 0);
    if (!g_livewp_configured) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][repair] end ok=0 reason=not-configured total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        r_settle_us(oldSettleUS);
        return false;
    }
    if (g_livewp_paused) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][repair] end ok=1 reason=paused total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        r_settle_us(oldSettleUS);
        return true;
    }
    bool ok = livewp_attach_and_play();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][repair] end ok=%d total=%llums\n",
                     ok ? 1 : 0, livewp_elapsed_ms_since(startUs));
    r_settle_us(oldSettleUS);
    return ok;
}

bool livewp_pause_in_session(void)
{
    uint32_t oldSettleUS = r_settle_us(0);
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][pause] start configured=%d paused=%d\n",
                     g_livewp_configured ? 1 : 0, g_livewp_paused ? 1 : 0);
    if (!g_livewp_configured) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][pause] end ok=1 reason=not-configured total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        r_settle_us(oldSettleUS);
        return true;
    }

    if (r_is_objc_ptr(g_livewp_player))
        r_msg2_main(g_livewp_player, "pause", 0, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_home_layer))
        r_msg2_main(g_livewp_home_layer, "setHidden:", 1, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_lock_layer))
        r_msg2_main(g_livewp_lock_layer, "setHidden:", 1, 0, 0, 0);

    if (!g_livewp_paused) {
        log_user("[LIVEWP] paused while screen is asleep.\n");
    }
    g_livewp_paused = true;
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][pause] end ok=1 total=%llums\n",
                     livewp_elapsed_ms_since(startUs));
    r_settle_us(oldSettleUS);
    return true;
}

bool livewp_resume_in_session(void)
{
    uint32_t oldSettleUS = r_settle_us(0);
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][resume] start configured=%d paused=%d\n",
                     g_livewp_configured ? 1 : 0, g_livewp_paused ? 1 : 0);
    if (!g_livewp_configured) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][resume] end ok=0 reason=not-configured total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        r_settle_us(oldSettleUS);
        return false;
    }

    bool wasPaused = g_livewp_paused;
    g_livewp_paused = false;
    if (r_is_objc_ptr(g_livewp_home_layer))
        r_msg2_main(g_livewp_home_layer, "setHidden:", 0, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_lock_layer))
        r_msg2_main(g_livewp_lock_layer, "setHidden:", 0, 0, 0, 0);

    bool ok = livewp_attach_and_play();
    if (wasPaused) {
        log_user("[LIVEWP] resumed after screen wake result=%d.\n", ok);
    }
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][resume] end ok=%d wasPaused=%d total=%llums\n",
                     ok ? 1 : 0, wasPaused ? 1 : 0, livewp_elapsed_ms_since(startUs));
    r_settle_us(oldSettleUS);
    return ok;
}

// 热替换视频：复用旧 player 实例，只替换 playerItem 和 looper
// 所有 AVFoundation 对象都在 SpringBoard 进程里通过 RemoteCall 创建
bool livewp_swap_video_in_session(NSString *videoPath)
{
    uint32_t oldSettleUS = r_settle_us(0);
    uint64_t startUs = livewp_now_us();
    bool ok = false;
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][swap] start configured=%d player=0x%llx path=%s\n",
                     g_livewp_configured ? 1 : 0, g_livewp_player,
                     videoPath ? videoPath.UTF8String : "(null)");
    if (!g_livewp_configured || !r_is_objc_ptr(g_livewp_player)) {
        log_user("[LIVEWP] swap: not configured\n");
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][swap] end ok=0 reason=not-configured total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }

    uint64_t pathStr = r_nsstr_retained(videoPath.UTF8String);
    if (!r_is_objc_ptr(pathStr)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][swap] end ok=0 reason=path-string total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }
    uint64_t url = r_msg2_main(r_class("NSURL"), "fileURLWithPath:", pathStr, 0, 0, 0);
    r_msg2(pathStr, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(url)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][swap] end ok=0 reason=url total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }

    // 在 SpringBoard 进程里创建新 AVPlayerItem
    uint64_t newItem = r_msg2_main(r_class("AVPlayerItem"), "playerItemWithURL:", url, 0, 0, 0);
    if (!r_is_objc_ptr(newItem)) {
        log_user("[LIVEWP] swap: failed to create playerItem\n");
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][swap] end ok=0 reason=player-item total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        goto out;
    }

    // replaceCurrentItemWithPlayerItem: — layer 保持不变，只是换了视频源
    r_msg2_main(g_livewp_player, "replaceCurrentItemWithPlayerItem:", newItem, 0, 0, 0);

    // 重建 looper（旧 looper 持有的是旧 item，需要换成新的）
    uint64_t looperCls = r_class("AVPlayerLooper");
    if (r_is_objc_ptr(looperCls)) {
        g_livewp_looper = r_msg2_main(looperCls, "playerLooperWithPlayer:templateItem:",
                                       g_livewp_player, newItem, 0, 0);
    }
    g_livewp_player_item = newItem;

    r_msg2_main(g_livewp_player, "play", 0, 0, 0, 0);
    log_user("[LIVEWP] video swapped OK\n");
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][swap] end ok=1 newItem=0x%llx looper=0x%llx total=%llums\n",
                     newItem, g_livewp_looper, livewp_elapsed_ms_since(startUs));
    ok = true;

out:
    r_settle_us(oldSettleUS);
    return ok;
}

void livewp_forget_remote_state(void)
{
    g_livewp_player = 0;
    g_livewp_home_layer = 0;
    g_livewp_lock_layer = 0;
    g_livewp_player_item = 0;
    g_livewp_looper = 0;
    g_livewp_home_window = 0;
    g_livewp_lock_window = 0;
    g_livewp_configured = false;
    g_livewp_paused = false;
}

// ============================================================================
// MARK: - Private Helpers
// ============================================================================

static uint64_t livewp_make_layer(uint64_t player)
{
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][make-layer] start player=0x%llx\n", player);
    uint64_t layer = r_msg2_main(r_class("AVPlayerLayer"), "playerLayerWithPlayer:", player, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][make-layer] end ok=0 reason=layer total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return 0;
    }
    uint64_t gravity = r_nsstr_retained("AVLayerVideoGravityResizeAspectFill");
    if (r_is_objc_ptr(gravity)) {
        r_msg2_main(layer, "setVideoGravity:", gravity, 0, 0, 0);
        r_msg2(gravity, "release", 0, 0, 0, 0);
    }
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][make-layer] end ok=1 layer=0x%llx gravityOK=%d total=%llums\n",
                     layer, r_is_objc_ptr(gravity) ? 1 : 0, livewp_elapsed_ms_since(startUs));
    return layer;
}

static bool livewp_create_player(NSString *videoPath)
{
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] start path=%s\n", videoPath.UTF8String);

    uint64_t dlopenStartUs = livewp_now_us();
    uint64_t avf = r_alloc_str("/System/Library/Frameworks/AVFoundation.framework/AVFoundation");
    if (avf) { r_dlsym_call(R_TIMEOUT, "dlopen", avf, 2, 0, 0, 0, 0, 0, 0); r_free(avf); }
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] dlopen avfStrOK=%d elapsed=%llums\n",
                     avf ? 1 : 0, livewp_elapsed_ms_since(dlopenStartUs));

    uint64_t urlStartUs = livewp_now_us();
    uint64_t pathStr = r_nsstr_retained(videoPath.UTF8String);
    if (!r_is_objc_ptr(pathStr)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] end ok=0 reason=path-string total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }
    uint64_t url = r_msg2_main(r_class("NSURL"), "fileURLWithPath:", pathStr, 0, 0, 0);
    r_msg2(pathStr, "release", 0, 0, 0, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] url=0x%llx elapsed=%llums\n",
                     url, livewp_elapsed_ms_since(urlStartUs));
    if (!r_is_objc_ptr(url)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] end ok=0 reason=url total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    uint64_t itemStartUs = livewp_now_us();
    uint64_t playerItem = r_msg2_main(r_class("AVPlayerItem"), "playerItemWithURL:", url, 0, 0, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] playerItem=0x%llx elapsed=%llums\n",
                     playerItem, livewp_elapsed_ms_since(itemStartUs));
    if (!r_is_objc_ptr(playerItem)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] end ok=0 reason=player-item total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    uint64_t classStartUs = livewp_now_us();
    uint64_t playerClass = r_class("AVQueuePlayer");
    if (!r_is_objc_ptr(playerClass)) playerClass = r_class("AVPlayer");
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] playerClass=0x%llx elapsed=%llums\n",
                     playerClass, livewp_elapsed_ms_since(classStartUs));
    if (!r_is_objc_ptr(playerClass)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] end ok=0 reason=player-class total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    uint64_t playerStartUs = livewp_now_us();
    uint64_t player = r_msg2_main(playerClass, "playerWithPlayerItem:", playerItem, 0, 0, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] player=0x%llx elapsed=%llums\n",
                     player, livewp_elapsed_ms_since(playerStartUs));
    if (!r_is_objc_ptr(player)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] end ok=0 reason=player total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    uint64_t playerConfigStartUs = livewp_now_us();
    double zero = 0.0;
    r_msg2_main_raw(player, "setVolume:", &zero, sizeof(zero), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main(player, "setPreventsDisplaySleepDuringVideoPlayback:", 0, 0, 0, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] player-config elapsed=%llums\n",
                     livewp_elapsed_ms_since(playerConfigStartUs));

    uint64_t looperStartUs = livewp_now_us();
    uint64_t looperCls = r_class("AVPlayerLooper");
    uint64_t looper = r_is_objc_ptr(looperCls)
        ? r_msg2_main(looperCls, "playerLooperWithPlayer:templateItem:", player, playerItem, 0, 0)
        : 0;
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] looperCls=0x%llx looper=0x%llx elapsed=%llums\n",
                     looperCls, looper, livewp_elapsed_ms_since(looperStartUs));

    // 两个 layer：一个给主屏幕，一个给锁屏
    uint64_t layersStartUs = livewp_now_us();
    uint64_t homeLayer = livewp_make_layer(player);
    uint64_t lockLayer = livewp_make_layer(player);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] layers home=0x%llx lock=0x%llx elapsed=%llums\n",
                     homeLayer, lockLayer, livewp_elapsed_ms_since(layersStartUs));
    if (!r_is_objc_ptr(homeLayer) || !r_is_objc_ptr(lockLayer)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] end ok=0 reason=layers total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    uint64_t audioStartUs = livewp_now_us();
    uint64_t session = r_msg2_main(r_class("AVAudioSession"), "sharedInstance", 0, 0, 0, 0);
    if (r_is_objc_ptr(session)) {
        uint64_t cat = r_nsstr_retained("AVAudioSessionCategoryAmbient");
        if (r_is_objc_ptr(cat)) {
            r_dlsym_call(R_TIMEOUT, "objc_msgSend", session, r_sel("setCategory:withOptions:error:"),
                         cat, (uint64_t)1, (uint64_t)0, 0, 0, 0);
            r_msg2(cat, "release", 0, 0, 0, 0);
        }
    }
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] audio-session=0x%llx elapsed=%llums\n",
                     session, livewp_elapsed_ms_since(audioStartUs));

    g_livewp_player = player;
    g_livewp_player_item = playerItem;
    g_livewp_home_layer = homeLayer;
    g_livewp_lock_layer = lockLayer;
    g_livewp_looper = looper;
    g_livewp_paused = false;
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][create] end ok=1 player=0x%llx item=0x%llx looper=0x%llx total=%llums\n",
                     g_livewp_player, g_livewp_player_item, g_livewp_looper,
                     livewp_elapsed_ms_since(startUs));
    return true;
}

// 辅助：把 layer 插到指定 window 的 index 0，返回是否已附着成功。
static bool livewp_ensure_layer_in_window(uint64_t layer, uint64_t window, bool *movedOut)
{
    uint64_t startUs = livewp_now_us();
    if (movedOut) *movedOut = false;
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][ensure] start layer=0x%llx window=0x%llx\n", layer, window);
    if (!r_is_objc_ptr(layer) || !r_is_objc_ptr(window)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][ensure] end ok=0 reason=invalid-args layerOK=%d windowOK=%d total=%llums\n",
                         r_is_objc_ptr(layer) ? 1 : 0, r_is_objc_ptr(window) ? 1 : 0,
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    uint64_t winLayerStartUs = livewp_now_us();
    uint64_t winLayer = r_msg2_main(window, "layer", 0, 0, 0, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][ensure] winLayer=0x%llx elapsed=%llums\n",
                     winLayer, livewp_elapsed_ms_since(winLayerStartUs));
    if (!r_is_objc_ptr(winLayer)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][ensure] end ok=0 reason=window-layer total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    LiveWPRect bounds = {0};
    uint64_t frameStartUs = livewp_now_us();
    r_msg2_main_struct_ret(window, "bounds", &bounds, sizeof(bounds),
                           NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(layer, "setFrame:",
                    &bounds, sizeof(bounds), NULL, 0, NULL, 0, NULL, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][ensure] frame x=%.1f y=%.1f w=%.1f h=%.1f elapsed=%llums\n",
                     bounds.x, bounds.y, bounds.w, bounds.h,
                     livewp_elapsed_ms_since(frameStartUs));

    uint64_t insertStartUs = livewp_now_us();
    uint64_t curSuper = r_msg2_main(layer, "superlayer", 0, 0, 0, 0);
    if (curSuper != winLayer) {
        if (r_is_objc_ptr(curSuper))
            r_msg2_main(layer, "removeFromSuperlayer", 0, 0, 0, 0);
        r_msg2_main(winLayer, "insertSublayer:atIndex:", layer, 0, 0, 0);
        if (movedOut) *movedOut = true;
    }
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][ensure] end ok=1 curSuper=0x%llx winLayer=0x%llx moved=%d insertElapsed=%llums total=%llums\n",
                     curSuper, winLayer, (movedOut && *movedOut) ? 1 : 0,
                     livewp_elapsed_ms_since(insertStartUs),
                     livewp_elapsed_ms_since(startUs));
    return true;
}

static bool livewp_attach_and_play(void)
{
    uint64_t startUs = livewp_now_us();
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] start paused=%d player=0x%llx cachedHome=0x%llx cachedLock=0x%llx\n",
                     g_livewp_paused ? 1 : 0, g_livewp_player,
                     g_livewp_home_window, g_livewp_lock_window);
    if (g_livewp_paused) {
        if (r_is_objc_ptr(g_livewp_player))
            r_msg2_main(g_livewp_player, "pause", 0, 0, 0, 0);
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] end ok=1 reason=paused total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return true;
    }

    bool homeMoved = false;
    bool lockMoved = false;
    uint64_t cachedStartUs = livewp_now_us();
    bool homeOK = livewp_ensure_layer_in_window(g_livewp_home_layer,
                                                g_livewp_home_window,
                                                &homeMoved);
    bool lockOK = livewp_ensure_layer_in_window(g_livewp_lock_layer,
                                                g_livewp_lock_window,
                                                &lockMoved);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] cached homeOK=%d lockOK=%d homeMoved=%d lockMoved=%d elapsed=%llums\n",
                     homeOK ? 1 : 0, lockOK ? 1 : 0, homeMoved ? 1 : 0,
                     lockMoved ? 1 : 0, livewp_elapsed_ms_since(cachedStartUs));
    if (homeOK || lockOK) {
        uint64_t playStartUs = livewp_now_us();
        r_msg2_main(g_livewp_player, "play", 0, 0, 0, 0);
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] play cached elapsed=%llums\n",
                         livewp_elapsed_ms_since(playStartUs));
        if (homeMoved || lockMoved) {
            LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] repair reused cached windows homeMoved=%d lockMoved=%d\n",
                             homeMoved, lockMoved);
        }
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] end ok=1 path=cached total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return true;
    }

    uint64_t appStartUs = livewp_now_us();
    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] app=0x%llx elapsed=%llums\n",
                     app, livewp_elapsed_ms_since(appStartUs));
    if (!r_is_objc_ptr(app)) {
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] end ok=0 reason=app total=%llums\n",
                         livewp_elapsed_ms_since(startUs));
        return false;
    }

    // 遍历所有 window，找 SBHomeScreenWindow 和 SBCoverSheetWindow
    uint64_t windowsStartUs = livewp_now_us();
    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    uint64_t wCount = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    uint64_t homeWin = 0;
    uint64_t lockWin = 0;
    uint64_t homeScreenViewCls = r_class("SBHomeScreenView");
    uint64_t coverSheetCls = r_class("SBCoverSheetWindow");
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] windows=0x%llx count=%llu homeViewCls=0x%llx coverCls=0x%llx elapsed=%llums\n",
                     windows, wCount, homeScreenViewCls, coverSheetCls,
                     livewp_elapsed_ms_since(windowsStartUs));

    uint64_t scanStartUs = livewp_now_us();
    for (uint64_t i = 0; i < wCount && i < 32; i++) {
        uint64_t w = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(w)) continue;
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] scan window[%llu]=0x%llx\n", i, w);

        // 检查是不是 SBCoverSheetWindow
        if (livewp_is_kind_of_class_fast(w, coverSheetCls)) {
            lockWin = w;
            LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] found lock window[%llu]=0x%llx\n", i, w);
            if (homeWin) break;
            continue;
        }

        // 检查子视图有没有 SBHomeScreenView
        if (!homeWin && r_is_objc_ptr(homeScreenViewCls)) {
            uint64_t subs = r_msg2_main(w, "subviews", 0, 0, 0, 0);
            uint64_t sCount = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
            LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] window[%llu] subviews=0x%llx count=%llu\n",
                             i, subs, sCount);
            for (uint64_t j = 0; j < sCount && j < 4; j++) {
                uint64_t sv = r_msg2_main(subs, "objectAtIndex:", j, 0, 0, 0);
                if (livewp_is_kind_of_class_fast(sv, homeScreenViewCls)) {
                    homeWin = w;
                    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] found home window[%llu]=0x%llx subview[%llu]=0x%llx\n",
                                     i, w, j, sv);
                    if (lockWin) break;
                    break;
                }
            }
        }
    }
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] scan complete home=0x%llx lock=0x%llx elapsed=%llums\n",
                     homeWin, lockWin, livewp_elapsed_ms_since(scanStartUs));

    // 把各自的 layer 插到各自的 window
    if (r_is_objc_ptr(homeWin)) {
        uint64_t homeAttachStartUs = livewp_now_us();
        homeOK = livewp_ensure_layer_in_window(g_livewp_home_layer, homeWin, &homeMoved);
        if (homeOK) g_livewp_home_window = homeWin;
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] home attach ok=%d moved=%d elapsed=%llums\n",
                         homeOK ? 1 : 0, homeMoved ? 1 : 0,
                         livewp_elapsed_ms_since(homeAttachStartUs));
    }
    if (r_is_objc_ptr(lockWin)) {
        uint64_t lockAttachStartUs = livewp_now_us();
        lockOK = livewp_ensure_layer_in_window(g_livewp_lock_layer, lockWin, &lockMoved);
        if (lockOK) g_livewp_lock_window = lockWin;
        LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] lock attach ok=%d moved=%d elapsed=%llums\n",
                         lockOK ? 1 : 0, lockMoved ? 1 : 0,
                         livewp_elapsed_ms_since(lockAttachStartUs));
    }

    uint64_t playStartUs = livewp_now_us();
    r_msg2_main(g_livewp_player, "play", 0, 0, 0, 0);
    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] play scanned elapsed=%llums\n",
                     livewp_elapsed_ms_since(playStartUs));

    LIVEWP_DEBUG_LOG("[LIVEWP][DEBUG][attach] end ok=%d home=0x%llx(%d) lock=0x%llx(%d) wCount=%llu total=%llums\n",
                     (homeOK || lockOK) ? 1 : 0, homeWin, homeMoved,
                     lockWin, lockMoved, wCount, livewp_elapsed_ms_since(startUs));
    return homeOK || lockOK;
}

static void livewp_cleanup(void)
{
    g_livewp_player = 0;
    g_livewp_player_item = 0;
    g_livewp_home_layer = 0;
    g_livewp_lock_layer = 0;
    g_livewp_looper = 0;
    g_livewp_home_window = 0;
    g_livewp_lock_window = 0;
    g_livewp_paused = false;
}
