//
//  darksword_tweaks.m
//

#import "darksword_tweaks.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import <Foundation/Foundation.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>
#import "../LogTextView.h"

static const useconds_t kDSTSettleUS = 50000;

static int ds_ios_major_version(void)
{
    return (int)[[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
}

static uint64_t ds_try_msg0(uint64_t obj, const char *selName)
{
    if (!r_is_objc_ptr(obj) || !r_responds(obj, selName)) return 0;
    return r_msg2(obj, selName, 0, 0, 0, 0);
}

static uint64_t ds_try_msg0_main(uint64_t obj, const char *selName)
{
    if (!r_is_objc_ptr(obj) || !r_responds_main(obj, selName)) return 0;
    return r_msg2_main(obj, selName, 0, 0, 0, 0);
}

static uint64_t ds_object_class(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return 0;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(cls)) return cls;
    return ds_try_msg0(obj, "class");
}

static uint64_t ds_resolve_ivar_target(uint64_t obj, uint64_t cls, const char *name)
{
    if (!r_is_objc_ptr(obj) || !r_is_objc_ptr(cls) || !name) return 0;

    uint64_t nameMem = r_alloc_str(name);
    if (!nameMem) return 0;
    uint64_t ivar = r_dlsym_call(100, "class_getInstanceVariable",
                                 cls, nameMem, 0, 0, 0, 0, 0, 0);
    r_free(nameMem);
    if (!ivar) {
        printf("[DST]   %s: ivar not found\n", name);
        return 0;
    }

    uint64_t offset = r_dlsym_call(100, "ivar_getOffset",
                                   ivar, 0, 0, 0, 0, 0, 0, 0);
    if (!offset) {
        printf("[DST]   %s: offset=0\n", name);
        return 0;
    }
    return obj + offset;
}

static bool ds_poke_pointer_ivar(uint64_t obj, uint64_t cls, const char *name, uint64_t value)
{
    uint64_t target = ds_resolve_ivar_target(obj, cls, name);
    if (!target) return false;
    if (!remote_write(target, &value, sizeof(value))) return false;
    uint64_t readback = remote_read64(target);
    printf("[DST]   %-40s @ 0x%llx -> 0x%llx\n", name, target, readback);
    usleep(kDSTSettleUS);
    return readback == value;
}

static bool ds_set_trailing_controllers(uint64_t obj, uint64_t value, const char *tag)
{
    if (!r_is_objc_ptr(obj)) return false;

    const char *setters[] = {
        "setTrailingCustomViewControllers:",
        "_setTrailingCustomViewControllers:",
    };
    for (size_t i = 0; i < sizeof(setters) / sizeof(setters[0]); i++) {
        if (!r_responds(obj, setters[i])) continue;
        r_msg2_main(obj, setters[i], value, 0, 0, 0);
        printf("[DST:APPLIB] %s via %s\n", tag, setters[i]);
        usleep(kDSTSettleUS);
        return true;
    }

    uint64_t cls = ds_object_class(obj);
    return ds_poke_pointer_ivar(obj, cls, "_trailingCustomViewControllers", value);
}

static bool ds_set_trailing_controller(uint64_t obj, uint64_t value, const char *tag)
{
    if (!r_is_objc_ptr(obj)) return false;

    const char *setters[] = {
        "setTrailingCustomViewController:",
        "_setTrailingCustomViewController:",
    };
    for (size_t i = 0; i < sizeof(setters) / sizeof(setters[0]); i++) {
        if (!r_responds(obj, setters[i])) continue;
        r_msg2_main(obj, setters[i], value, 0, 0, 0);
        printf("[DST:APPLIB] %s via %s\n", tag, setters[i]);
        usleep(kDSTSettleUS);
        return true;
    }

    uint64_t cls = ds_object_class(obj);
    bool ok = ds_poke_pointer_ivar(obj, cls, "_trailingCustomViewController", value);
    if (ok) printf("[DST:APPLIB] %s via _trailingCustomViewController\n", tag);
    return ok;
}

static bool ds_clear_overlay_library_controller(uint64_t mgr)
{
    if (!r_is_objc_ptr(mgr)) return false;

    if (r_responds(mgr, "setOverlayLibraryViewController:")) {
        r_msg2_main(mgr, "setOverlayLibraryViewController:", 0, 0, 0, 0);
        printf("[DST:APPLIB] iconManager via setOverlayLibraryViewController:\n");
        usleep(kDSTSettleUS);
        return true;
    }

    uint64_t cls = ds_object_class(mgr);
    bool ok = ds_poke_pointer_ivar(mgr, cls, "_overlayLibraryViewController", 0);
    if (ok) printf("[DST:APPLIB] iconManager via _overlayLibraryViewController\n");
    return ok;
}

static bool ds_disable_app_library_singular_path(uint64_t mgr,
                                                 uint64_t rootFC,
                                                 uint64_t rootView)
{
    bool trailingOK = false;

    trailingOK |= ds_set_trailing_controller(mgr, 0, "iconManager");
    (void)ds_clear_overlay_library_controller(mgr);
    trailingOK |= ds_set_trailing_controller(rootFC, 0, "rootFolderController");

    uint64_t rootConfig = ds_try_msg0(rootFC, "configuration");
    if (r_is_objc_ptr(rootConfig)) {
        trailingOK |= ds_set_trailing_controller(rootConfig, 0, "rootFolderControllerConfiguration");
    }

    if (r_is_objc_ptr(rootView)) {
        trailingOK |= ds_set_trailing_controller(rootView, 0, "rootFolderView");
    }

    return trailingOK;
}

static bool ds_poke_double_ivar(uint64_t obj, uint64_t cls, const char *name, double value)
{
    uint64_t target = ds_resolve_ivar_target(obj, cls, name);
    if (!target) return false;

    union { double d; uint64_t u; } out = { .d = value };
    if (!remote_write(target, &out.u, sizeof(out.u))) return false;

    union { uint64_t u; double d; } readback = { .u = remote_read64(target) };
    printf("[DST]   %-40s @ 0x%llx -> %f\n", name, target, readback.d);
    usleep(kDSTSettleUS);
    return true;
}

static void ds_main_set_needs_layout(uint64_t view, const char *tag)
{
    if (!r_is_objc_ptr(view)) return;

    if (r_responds_main(view, "setNeedsLayout")) {
        uint64_t sel = r_sel("setNeedsLayout");
        r_perform_main(view, sel, 0, false);
        printf("[DST]   %s setNeedsLayout\n", tag);
    }
}

static void ds_refresh_root_folder_after_app_library_change(uint64_t rootFC, uint64_t rootView)
{
    printf("[DST:APPLIB] marking root folder views dirty\n");

    if (r_is_objc_ptr(rootFC) &&
        r_responds_main(rootFC, "currentIconListView")) {
        uint64_t currentList = r_msg2_main(rootFC, "currentIconListView", 0, 0, 0, 0);
        ds_main_set_needs_layout(currentList, "currentIconListView");
    }

    ds_main_set_needs_layout(rootView, "rootFolderView");

    uint64_t fcView = ds_try_msg0_main(rootFC, "view");
    if (fcView != rootView) {
        ds_main_set_needs_layout(fcView, "rootFolderController.view");
    }
}

bool darksword_tweak_disable_app_library_in_session(void)
{
    printf("[DST:APPLIB] disabling app library\n");

    uint64_t clsIC = r_class("SBIconController");
    uint64_t ctrl = r_is_objc_ptr(clsIC) ? r_msg2_main(clsIC, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t mgr = ds_try_msg0_main(ctrl, "iconManager");
    uint64_t rootFC = ds_try_msg0_main(mgr, "rootFolderController");
    if (!r_is_objc_ptr(rootFC)) {
        printf("[DST:APPLIB] rootFolderController nil\n");
        return false;
    }

    uint64_t rootView = ds_try_msg0_main(rootFC, "rootFolderView");
    if (!r_is_objc_ptr(rootView)) {
        printf("[DST:APPLIB] rootFolderView nil\n");
    }

    bool ok = false;
    if (ds_ios_major_version() == 17) {
        printf("[DST:APPLIB] using iOS 17 singular controller path\n");
        ok = ds_disable_app_library_singular_path(mgr, rootFC, rootView);
        if (ok) {
            ds_refresh_root_folder_after_app_library_change(rootFC, rootView);
            printf("[DST:APPLIB] result=%d\n", ok);
            return ok;
        }
    }

    uint64_t NSArray = r_class("NSArray");
    uint64_t emptyArr = r_is_objc_ptr(NSArray) ? r_msg2(NSArray, "new", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(emptyArr)) {
        emptyArr = r_is_objc_ptr(NSArray) ? r_msg2(NSArray, "array", 0, 0, 0, 0) : 0;
    }
    if (!r_is_objc_ptr(emptyArr)) {
        printf("[DST:APPLIB] empty NSArray failed\n");
        return false;
    }

    ok = false;
    ok |= ds_set_trailing_controllers(rootFC, emptyArr, "rootFolderController");

    if (r_is_objc_ptr(rootView)) {
        ok |= ds_set_trailing_controllers(rootView, emptyArr, "rootFolderView");
    }

    if (!ok && ds_ios_major_version() != 17) {
        printf("[DST:APPLIB] plural path failed; trying singular controller fallback\n");
        ok = ds_disable_app_library_singular_path(mgr, rootFC, rootView);
    }

    if (ok) ds_refresh_root_folder_after_app_library_change(rootFC, rootView);

    printf("[DST:APPLIB] result=%d\n", ok);
    return ok;
}

bool darksword_tweak_disable_icon_fly_in_in_session(void)
{
    printf("[DST:FLYIN] disabling icon fly-in animation\n");

    uint64_t cls = r_class("SBCoverSheetPresentationManager");
    uint64_t mgr = r_is_objc_ptr(cls) ? r_msg2_main(cls, "sharedInstance", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(mgr)) {
        printf("[DST:FLYIN] presentation manager missing\n");
        return false;
    }

    uint64_t mgrCls = ds_object_class(mgr);
    bool ok = true;
    ok &= ds_poke_double_ivar(mgr, mgrCls, "_iconFlyInTension", 1.0e6);
    ok &= ds_poke_double_ivar(mgr, mgrCls, "_iconFlyInFriction", 1.0e6);
    ok &= ds_poke_double_ivar(mgr, mgrCls, "_iconFlyInInteractiveResponseMin", 0.0001);
    ok &= ds_poke_double_ivar(mgr, mgrCls, "_iconFlyInInteractiveResponseMax", 0.0001);
    ok &= ds_poke_double_ivar(mgr, mgrCls, "_iconFlyInInteractiveDampingRatioMin", 1.0);
    ok &= ds_poke_double_ivar(mgr, mgrCls, "_iconFlyInInteractiveDampingRatioMax", 1.0);
    printf("[DST:FLYIN] result=%d\n", ok);
    return ok;
}

bool darksword_tweak_zero_backlight_fade_in_session(void)
{
    printf("[DST:BLF] zeroing backlight fade durations\n");

    uint64_t cls = r_class("SBScreenWakeAnimationController");
    uint64_t ctrl = r_is_objc_ptr(cls) ? r_msg2_main(cls, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t selFetch = r_sel("_animationSettingsForBacklightChangeSource:isWake:");
    if (!r_is_objc_ptr(ctrl) || !selFetch) {
        printf("[DST:BLF] wake animation controller missing\n");
        return false;
    }

    uint64_t seen[16] = {0};
    int seenCount = 0;
    uint64_t settingsCls = 0;
    uint64_t ivarOffset = 0;
    int poked = 0;

    for (int src = 0; src <= 3; src++) {
        for (int isWake = 0; isWake <= 1; isWake++) {
            uint64_t settings = r_msg_main(ctrl, selFetch, (uint64_t)src, (uint64_t)isWake, 0, 0);
            usleep(kDSTSettleUS);
            if (!r_is_objc_ptr(settings)) continue;

            bool dup = false;
            for (int i = 0; i < seenCount; i++) {
                if (seen[i] == settings) { dup = true; break; }
            }
            if (dup) continue;
            if (seenCount < 16) seen[seenCount++] = settings;

            if (!ivarOffset) {
                settingsCls = ds_object_class(settings);
                uint64_t nameMem = r_alloc_str("_backlightFadeDuration");
                uint64_t ivar = nameMem ? r_dlsym_call(100, "class_getInstanceVariable",
                                                       settingsCls, nameMem, 0, 0, 0, 0, 0, 0) : 0;
                r_free(nameMem);
                if (!ivar) {
                    printf("[DST:BLF] _backlightFadeDuration ivar missing\n");
                    return false;
                }
                ivarOffset = r_dlsym_call(100, "ivar_getOffset", ivar, 0, 0, 0, 0, 0, 0, 0);
                if (!ivarOffset) return false;
                printf("[DST:BLF] _backlightFadeDuration offset=0x%llx\n", ivarOffset);
            }

            union { double d; uint64_t u; } zero = { .d = 0.0 };
            uint64_t target = settings + ivarOffset;
            if (remote_write(target, &zero.u, sizeof(zero.u))) {
                printf("[DST:BLF]   settings=0x%llx -> 0\n", settings);
                poked++;
            }
        }
    }

    printf("[DST:BLF] poked=%d seen=%d\n", poked, seenCount);
    return poked > 0;
}

bool darksword_tweak_zero_wake_animation_in_session(void)
{
    printf("[DST:WAKE] zeroing wake animation\n");

    uint64_t cls = r_class("SBScreenWakeAnimationController");
    uint64_t ctrl = r_is_objc_ptr(cls) ? r_msg2_main(cls, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t selFetch = r_sel("_animationSettingsForBacklightChangeSource:isWake:");
    if (!r_is_objc_ptr(ctrl) || !selFetch) {
        printf("[DST:WAKE] wake animation controller missing\n");
        return false;
    }

    uint64_t outer = r_msg_main(ctrl, selFetch, 0, 1, 0, 0);
    if (!r_is_objc_ptr(outer)) {
        printf("[DST:WAKE] outer settings nil\n");
        return false;
    }

    uint64_t outerCls = ds_object_class(outer);
    bool ok = true;
    ok &= ds_poke_double_ivar(outer, outerCls, "_backlightFadeDuration", 0.0);
    ok &= ds_poke_double_ivar(outer, outerCls, "_speedMultiplierForWake", 1000.0);
    ok &= ds_poke_double_ivar(outer, outerCls, "_speedMultiplierForLiftToWake", 1000.0);

    uint64_t target = ds_resolve_ivar_target(outer, outerCls, "_contentWakeSettings");
    uint64_t content = target ? remote_read64(target) : 0;
    if (!r_is_objc_ptr(content)) {
        printf("[DST:WAKE] _contentWakeSettings nil\n");
        return ok;
    }

    uint64_t contentCls = ds_object_class(content);
    ok &= ds_poke_double_ivar(content, contentCls, "_duration", 0.0);
    ok &= ds_poke_double_ivar(content, contentCls, "_speed", 1000.0);
    ok &= ds_poke_double_ivar(content, contentCls, "_delay", 0.0);
    printf("[DST:WAKE] result=%d\n", ok);
    return ok;
}

// outcome codes returned by ds_install_double_tap_on_view so callers can
// summarise per-iteration results without each call printing its own line.
typedef enum { DTLockOutcomeFailed = 0, DTLockOutcomeInstalled, DTLockOutcomeAlreadyInstalled } DTLockOutcome;

static DTLockOutcome ds_install_double_tap_on_view(uint64_t view, uint64_t sb, uint64_t selLock, uint64_t assocKey, const char *tag, bool verbose)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(sb) || !selLock || !assocKey) return DTLockOutcomeFailed;

    uint64_t existing = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                     view, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(existing)) {
        if (verbose) printf("[DST:LOCK] %s already installed\n", tag);
        return DTLockOutcomeAlreadyInstalled;
    }

    uint64_t clsGR = r_class("UITapGestureRecognizer");
    uint64_t gr = r_is_objc_ptr(clsGR) ? r_msg2(clsGR, "alloc", 0, 0, 0, 0) : 0;
    gr = r_is_objc_ptr(gr) ? r_msg2(gr, "initWithTarget:action:", sb, selLock, 0, 0) : 0;
    if (!r_is_objc_ptr(gr)) {
        printf("[DST:LOCK] %s recognizer allocation failed\n", tag);
        return DTLockOutcomeFailed;
    }

    r_msg2(gr, "setNumberOfTapsRequired:", 2, 0, 0, 0);
    if (r_responds(gr, "setCancelsTouchesInView:"))
        r_msg2(gr, "setCancelsTouchesInView:", 0, 0, 0, 0);

    r_msg2_main(view, "addGestureRecognizer:", gr, 0, 0, 0);
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 view, assocKey, gr, 1, 0, 0, 0, 0);
    if (verbose) printf("[DST:LOCK] installed on %s view=0x%llx\n", tag, view);
    return DTLockOutcomeInstalled;
}

static bool ds_remove_double_tap_from_view(uint64_t view, uint64_t assocKey, const char *tag)
{
    if (!r_is_objc_ptr(view) || !assocKey) return false;

    uint64_t existing = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                     view, assocKey, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(existing)) return false;

    r_msg2_main(view, "removeGestureRecognizer:", existing, 0, 0, 0);
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 view, assocKey, 0, 0, 0, 0, 0, 0);
    printf("[DST:LOCK] removed window-level recognizer from %s view=0x%llx\n",
           tag ? tag : "view", view);
    return true;
}

bool darksword_tweak_double_tap_to_lock_in_session(void)
{
    printf("[DST:LOCK] installing double-tap to lock\n");

    uint64_t clsSB = r_class("SpringBoard");
    uint64_t sb = r_is_objc_ptr(clsSB) ? r_msg2(clsSB, "sharedApplication", 0, 0, 0, 0) : 0;
    uint64_t selLock = r_sel("_simulateLockButtonPress");
    uint64_t assocKey = r_sel("darkswordDoubleTapLockGesture");
    if (!r_is_objc_ptr(sb) || !selLock || !assocKey) {
        printf("[DST:LOCK] SpringBoard target missing\n");
        return false;
    }

    bool ok = false;
    uint64_t clsIC = r_class("SBIconController");
    uint64_t ctrl = r_is_objc_ptr(clsIC) ? r_msg2_main(clsIC, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t mgr = ds_try_msg0_main(ctrl, "iconManager");
    uint64_t rootFC = ds_try_msg0_main(mgr, "rootFolderController");
    uint64_t homeView = ds_try_msg0_main(rootFC, "view");
    if (r_is_objc_ptr(homeView)) {
        ok |= (ds_install_double_tap_on_view(homeView, sb, selLock, assocKey, "homescreen", true) != DTLockOutcomeFailed);
    }

    // UIApplication window enumeration is UIKit state; keep it on
    // SpringBoard's main thread to avoid RemoteCall worker view-tree faults.
    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    uint64_t windows = ds_try_msg0_main(app, "windows");
    uint64_t count = ds_try_msg0_main(windows, "count");
    uint64_t limit = count < 20 ? count : 20;
    int installed = 0, alreadyInstalled = 0, failed = 0, skipped = 0;
    for (uint64_t i = 0; i < limit; i++) {
        uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(win) || win == homeView) { skipped++; continue; }

        char tag[32];
        snprintf(tag, sizeof(tag), "window[%llu]", i);
        DTLockOutcome r = ds_install_double_tap_on_view(win, sb, selLock, assocKey, tag, false);
        switch (r) {
            case DTLockOutcomeInstalled:        installed++; ok = true; break;
            case DTLockOutcomeAlreadyInstalled: alreadyInstalled++;     break;
            case DTLockOutcomeFailed:           failed++;               break;
        }
    }
    printf("[DST:LOCK] windows scanned=%llu installed=%d already=%d skipped=%d failed=%d\n",
           limit, installed, alreadyInstalled, skipped, failed);

    printf("[DST:LOCK] result=%d\n", ok);
    return ok;
}

bool darksword_tweaks_apply_in_session(bool disableAppLibrary,
                                       bool disableIconFlyIn,
                                       bool zeroWakeAnimation,
                                       bool zeroBacklightFade,
                                       bool doubleTapToLock)
{
    printf("[DST] apply appLib=%d flyIn=%d wake=%d backlight=%d dblTap=%d\n",
           disableAppLibrary, disableIconFlyIn, zeroWakeAnimation,
           zeroBacklightFade, doubleTapToLock);

    bool any = false;
    bool ok = true;
    if (disableAppLibrary) {
        any = true;
        ok &= darksword_tweak_disable_app_library_in_session();
    }
    if (disableIconFlyIn) {
        any = true;
        ok &= darksword_tweak_disable_icon_fly_in_in_session();
    }
    if (zeroWakeAnimation) {
        any = true;
        ok &= darksword_tweak_zero_wake_animation_in_session();
    }
    if (zeroBacklightFade) {
        any = true;
        ok &= darksword_tweak_zero_backlight_fade_in_session();
    }
    if (doubleTapToLock) {
        any = true;
        ok &= darksword_tweak_double_tap_to_lock_in_session();
    }

    return any ? ok : true;
}
