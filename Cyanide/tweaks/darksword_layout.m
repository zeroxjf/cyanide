//
//  darksword_layout.m
//  Verbatim port of kolbicz/DarkSword-Tweaks dock_and_home_spacing.m and
//  dock_and_homescreen_scaling.m, retargeted to our remote_objc / RemoteCall
//  helpers. The session is assumed already open (we're called under
//  settings_rc_lock with g_springboard_rc_ready=1), so init/destroy bookends
//  from the original sources are dropped.
//

#import "darksword_layout.h"
#import "remote_objc.h"
#import "sb_walk.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdint.h>
#import <string.h>
#import <unistd.h>

// Two SpringBoard shapes ship in this binary:
//   iOS 18  — the upstream kolbicz path: SBIconController.iconManager
//             (an SBIconManager), .listLayoutProvider, .relayout +
//             layoutIconListsWithAnimationType:forceRelayout: as the apply
//             trigger.
//   iOS 26+ — Apple moved the home-screen object graph into the
//             SpringBoardHome framework. The icon manager class is now
//             SBHIconManager and its _listLayoutProvider ivar is nil-by-
//             default; layoutIconListsWithAnimationType:forceRelayout:
//             still exists but invoking it from RemoteCall crashes
//             SpringBoard (likely an internal state precondition that's
//             only true mid-run-loop). The iOS 26 path instead pulls the
//             provider from -[SBIconController listLayoutProvider] (which
//             redirects to ambientListLayoutProvider) and trusts the
//             setNeedsRelayout: + next CADisplayLink tick to pick up the
//             new layoutConfiguration values.
static int ds_layout_ios_major(void)
{
    static int cached = 0;
    if (cached) return cached;
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    cached = (int)v.majorVersion;
    return cached;
}

// Two ports now live in this file:
//   < iOS 26 — upstream kolbicz config-mutation path
//   ≥ iOS 26 — bypass the (now-immutable) layout configuration entirely.
//     Walk live SBIconListView instances and adjust them directly: setFrame:
//     for spacing, setIconImageInfo: on each SBIconView for scaling.
//     setIconImageInfo: still exists on iOS 26's SBIconView, and
//     SBIconListView.setFrame: is a regular UIView setter.
static bool darksword_layout_supported_on_current_ios(void)
{
    (void)0;
    return true; // both branches now handled
}

typedef struct {
    double top;
    double left;
    double bottom;
    double right;
} RC_UIEdgeInsets;

typedef struct {
    double x;
    double y;
    double width;
    double height;
} RC_CGRect;

static void r_send_rect_main_local(uint64_t obj, const char *selName,
                                   double x, double y, double w, double h)
{
    if (!r_is_objc_ptr(obj)) return;
    RC_CGRect rect = { x, y, w, h };
    r_msg2_main_raw(obj, selName,
                    &rect, sizeof(rect),
                    NULL, 0, NULL, 0, NULL, 0);
}

typedef struct {
    double width;
    double height;
    double scale;
    double cornerRadius;
} RC_SBIconImageInfo;

static uint64_t rc_safe_msg(uint64_t obj, const char *selname,
                            uint64_t a, uint64_t b, uint64_t c, uint64_t d)
{
    if (!obj) return 0;
    uint64_t sel = r_sel(selname);
    uint64_t rs  = r_sel("respondsToSelector:");
    if (!sel || !rs) return 0;
    if (!r_msg(obj, rs, sel, 0, 0, 0)) return 0;
    return r_msg(obj, sel, a, b, c, d);
}

static void rc_force_manager_relayout(uint64_t mgr, uint64_t clsInv)
{
    if (!mgr || !clsInv) return;

    uint64_t selSig     = r_sel("methodSignatureForSelector:");
    uint64_t selWithSig = r_sel("invocationWithMethodSignature:");
    uint64_t selSetTgt  = r_sel("setTarget:");
    uint64_t selSetSel  = r_sel("setSelector:");
    uint64_t selSetArg  = r_sel("setArgument:atIndex:");
    uint64_t selInvoke  = r_sel("invoke");
    uint64_t selPerform = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t selResponds = r_sel("respondsToSelector:");

    // setNeedsRelayout:YES — safe on both iOS 18 (SBIconManager) and iOS 26+
    // (SBHIconManager). Just an ivar setter on both.
    {
        uint64_t selSNR = r_sel("setNeedsRelayout:");
        uint64_t sig = r_msg(mgr, selSig, selSNR, 0, 0, 0);
        if (sig) {
            uint64_t inv = r_msg(clsInv, selWithSig, sig, 0, 0, 0);
            if (inv) {
                r_msg(inv, selSetTgt, mgr, 0, 0, 0);
                r_msg(inv, selSetSel, selSNR, 0, 0, 0);
                uint64_t one = do_remote_call_stable(R_TIMEOUT, "calloc", 1, 8, 0, 0, 0, 0, 0, 0);
                if (one) {
                    uint8_t yes = 1;
                    remote_write(one, &yes, 1);
                    r_msg(inv, selSetArg, one, 2, 0, 0);
                    r_msg(inv, selPerform, selInvoke, 0, 1, 0);
                    r_free(one);
                }
            }
        }
    }

    // -relayout: only iOS 18's SBIconManager exposes this. iOS 26's
    // SBHIconManager doesn't.
    if (ds_layout_ios_major() < 26) {
        uint64_t selR = r_sel("relayout");
        if (r_msg(mgr, selResponds, selR, 0, 0, 0)) {
            r_msg(mgr, selPerform, selR, 0, 1, 0);
        }
    }

    // -layoutIconListsWithAnimationType:forceRelayout: — iOS 18 only.
    // On iOS 26+ the selector still exists but invoking it from RemoteCall
    // tore down SpringBoard in testing (likely an internal precondition
    // around UIUpdateScheduler). Skip; setNeedsRelayout:YES above plus the
    // next natural display refresh picks up the new layoutConfiguration.
    if (ds_layout_ios_major() < 26) {
        uint64_t selLI = r_sel("layoutIconListsWithAnimationType:forceRelayout:");
        if (r_msg(mgr, selResponds, selLI, 0, 0, 0)) {
            uint64_t sig = r_msg(mgr, selSig, selLI, 0, 0, 0);
            if (sig) {
                uint64_t inv = r_msg(clsInv, selWithSig, sig, 0, 0, 0);
                if (inv) {
                    r_msg(inv, selSetTgt, mgr, 0, 0, 0);
                    r_msg(inv, selSetSel, selLI, 0, 0, 0);
                    uint64_t typeMem  = do_remote_call_stable(R_TIMEOUT, "calloc", 1, 8, 0, 0, 0, 0, 0, 0);
                    uint64_t forceMem = do_remote_call_stable(R_TIMEOUT, "calloc", 1, 8, 0, 0, 0, 0, 0, 0);
                    if (forceMem) {
                        uint8_t yes = 1;
                        remote_write(forceMem, &yes, 1);
                    }
                    if (typeMem)  r_msg(inv, selSetArg, typeMem,  2, 0, 0);
                    if (forceMem) r_msg(inv, selSetArg, forceMem, 3, 0, 0);
                    r_msg(inv, selPerform, selInvoke, 0, 1, 0);
                    if (typeMem)  r_free(typeMem);
                    if (forceMem) r_free(forceMem);
                }
            }
        }
    }
}

static uint64_t rc_list_layout_provider(uint64_t ctrl, uint64_t mgr)
{
    // iOS 26+: SBIconController vends an "ambient" provider directly. The
    // SBHIconManager's _listLayoutProvider ivar is nil-by-default.
    // iOS 18: the provider lives on the icon manager (upstream path).
    if (ds_layout_ios_major() >= 26) {
        if (ctrl) {
            uint64_t prov = r_msg(ctrl, r_sel("listLayoutProvider"), 0, 0, 0, 0);
            if (prov) return prov;
        }
    }
    if (!mgr) return 0;
    return r_msg(mgr, r_sel("listLayoutProvider"), 0, 0, 0, 0);
}

static uint64_t rc_root_layout_config(uint64_t ctrl, uint64_t mgr)
{
    uint64_t prov = rc_list_layout_provider(ctrl, mgr);
    if (!prov) return 0;
    uint64_t cfstr = r_cfstr("SBIconLocationRoot");
    if (!cfstr) return 0;
    uint64_t layout = r_msg(prov, r_sel("layoutForIconLocation:"), cfstr, 0, 0, 0);
    if (!layout) return 0;
    return r_msg(layout, r_sel("layoutConfiguration"), 0, 0, 0, 0);
}

static bool rc_set_insets_on(uint64_t cfg, uint64_t clsInv,
                             const RC_UIEdgeInsets *insets)
{
    if (!cfg || !clsInv) return false;
    uint64_t selSetInsets = r_sel("setPortraitLayoutInsets:");
    uint64_t selSig       = r_sel("methodSignatureForSelector:");
    uint64_t selWithSig   = r_sel("invocationWithMethodSignature:");
    uint64_t selSetTgt    = r_sel("setTarget:");
    uint64_t selSetSel    = r_sel("setSelector:");
    uint64_t selSetArg    = r_sel("setArgument:atIndex:");
    uint64_t selInvoke    = r_sel("invoke");
    uint64_t selPerform   = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");

    uint64_t sig = r_msg(cfg, selSig, selSetInsets, 0, 0, 0);
    if (!sig) return false;
    uint64_t inv = r_msg(clsInv, selWithSig, sig, 0, 0, 0);
    if (!inv) return false;
    r_msg(inv, selSetTgt, cfg, 0, 0, 0);
    r_msg(inv, selSetSel, selSetInsets, 0, 0, 0);

    uint64_t mem = do_remote_call_stable(R_TIMEOUT, "calloc", 1, 32, 0, 0, 0, 0, 0, 0);
    if (!mem) return false;
    if (!remote_write(mem, insets, sizeof(*insets))) { r_free(mem); return false; }
    r_msg(inv, selSetArg, mem, 2, 0, 0);
    r_msg(inv, selPerform, selInvoke, 0, 1, 0);
    r_free(mem);
    return true;
}

static bool rc_set_icon_info_on(uint64_t cfg, uint64_t clsInv,
                                const RC_SBIconImageInfo *info)
{
    if (!cfg || !clsInv) return false;
    uint64_t selSetIconInfo = r_sel("setIconImageInfo:");
    uint64_t selSig         = r_sel("methodSignatureForSelector:");
    uint64_t selWithSig     = r_sel("invocationWithMethodSignature:");
    uint64_t selSetTgt      = r_sel("setTarget:");
    uint64_t selSetSel      = r_sel("setSelector:");
    uint64_t selSetArg      = r_sel("setArgument:atIndex:");
    uint64_t selInvoke      = r_sel("invoke");
    uint64_t selPerform     = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");

    uint64_t sig = r_msg(cfg, selSig, selSetIconInfo, 0, 0, 0);
    if (!sig) return false;
    uint64_t inv = r_msg(clsInv, selWithSig, sig, 0, 0, 0);
    if (!inv) return false;
    r_msg(inv, selSetTgt, cfg, 0, 0, 0);
    r_msg(inv, selSetSel, selSetIconInfo, 0, 0, 0);

    uint64_t mem = do_remote_call_stable(R_TIMEOUT, "calloc", 1, 32, 0, 0, 0, 0, 0, 0);
    if (!mem) return false;
    if (!remote_write(mem, info, sizeof(*info))) { r_free(mem); return false; }
    r_msg(inv, selSetArg, mem, 2, 0, 0);
    r_msg(inv, selPerform, selInvoke, 0, 1, 0);
    r_free(mem);
    return true;
}

// SBApplicationIcon only — widgets/folders assert on forced 60x60.
static void rc_refresh_icon_view(uint64_t iconView, uint64_t clsInv,
                                 const RC_SBIconImageInfo *info)
{
    if (!iconView) return;
    uint64_t appIconCls = r_class("SBApplicationIcon");
    if (!appIconCls) return;
    // UIKit/SpringBoard view access must stay on SpringBoard's main thread.
    // Calling -icon / -subviews from the RemoteCall worker can trip PAC
    // exceptions in UIKit view hierarchy code on iOS 26.
    uint64_t icon = r_responds_main(iconView, "icon")
        ? r_msg2_main(iconView, "icon", 0, 0, 0, 0) : 0;
    if (!icon) return;
    if (!r_msg_main(icon, r_sel("isKindOfClass:"), appIconCls, 0, 0, 0)) return;

    uint64_t selSig     = r_sel("methodSignatureForSelector:");
    uint64_t selWithSig = r_sel("invocationWithMethodSignature:");
    uint64_t selSetTgt  = r_sel("setTarget:");
    uint64_t selSetSel  = r_sel("setSelector:");
    uint64_t selSetArg  = r_sel("setArgument:atIndex:");
    uint64_t selInvoke  = r_sel("invoke");
    uint64_t selPerform = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t selSetInfo = r_sel("setIconImageInfo:");
    uint64_t selUpdate  = r_sel("_updateAfterManualIconImageInfoChangeInvalidatingLayout:");

    uint64_t sig = r_msg(iconView, selSig, selSetInfo, 0, 0, 0);
    if (sig) {
        uint64_t inv = r_msg(clsInv, selWithSig, sig, 0, 0, 0);
        if (inv) {
            r_msg(inv, selSetTgt, iconView, 0, 0, 0);
            r_msg(inv, selSetSel, selSetInfo, 0, 0, 0);
            uint64_t mem = do_remote_call_stable(R_TIMEOUT, "calloc", 1, 32, 0, 0, 0, 0, 0, 0);
            if (mem) {
                remote_write(mem, info, sizeof(*info));
                r_msg(inv, selSetArg, mem, 2, 0, 0);
                r_msg(inv, selPerform, selInvoke, 0, 1, 0);
                r_free(mem);
            }
        }
    }

    uint64_t sigU = r_msg(iconView, selSig, selUpdate, 0, 0, 0);
    if (sigU) {
        uint64_t invU = r_msg(clsInv, selWithSig, sigU, 0, 0, 0);
        if (invU) {
            r_msg(invU, selSetTgt, iconView, 0, 0, 0);
            r_msg(invU, selSetSel, selUpdate, 0, 0, 0);
            uint64_t one = do_remote_call_stable(R_TIMEOUT, "calloc", 1, 8, 0, 0, 0, 0, 0, 0);
            if (one) {
                uint8_t yes = 1;
                remote_write(one, &yes, 1);
                r_msg(invU, selSetArg, one, 2, 0, 0);
                r_msg(invU, selPerform, selInvoke, 0, 1, 0);
                r_free(one);
            }
        }
    }
}

static int rc_refresh_list_view(uint64_t listView, uint64_t clsInv,
                                const RC_SBIconImageInfo *info)
{
    if (!listView) return 0;
    uint64_t clsIconView = r_class("SBIconView");
    if (!clsIconView) return 0;

    // Keep UIView hierarchy enumeration on the main thread. A fresh
    // SpringBoard crash report from a SnowBoard/Layout run showed a
    // RemoteCall worker thread faulting in -[UIView subviews] with an
    // arm64e PAC exception.
    uint64_t subs = r_msg_main(listView, r_sel("subviews"), 0, 0, 0, 0);
    if (!subs) return 0;
    uint64_t n = r_msg_main(subs, r_sel("count"), 0, 0, 0, 0);
    if (n > 512) n = 512;

    uint64_t selObjAt = r_sel("objectAtIndex:");
    uint64_t selKind  = r_sel("isKindOfClass:");
    int touched = 0;
    for (uint64_t i = 0; i < n; i++) {
        uint64_t v = r_msg_main(subs, selObjAt, i, 0, 0, 0);
        if (!v) continue;
        if (!r_msg_main(v, selKind, clsIconView, 0, 0, 0)) continue;
        rc_refresh_icon_view(v, clsInv, info);
        touched++;
        usleep(10000);
    }
    return touched;
}

static uint64_t rc_icon_controller(void)
{
    uint64_t cls = r_class("SBIconController");
    if (!cls) return 0;
    return r_msg_main(cls, r_sel("sharedInstance"), 0, 0, 0, 0);
}

static uint64_t rc_icon_manager_for(uint64_t ctrl)
{
    return ctrl ? r_msg_main(ctrl, r_sel("iconManager"), 0, 0, 0, 0) : 0;
}

static uint64_t rc_dock_list_view(uint64_t ctrl, uint64_t mgr)
{
    if (mgr) {
        uint64_t dock = rc_safe_msg(mgr, "dockListView", 0, 0, 0, 0);
        if (dock) return dock;
    }
    return ctrl ? rc_safe_msg(ctrl, "dockListView", 0, 0, 0, 0) : 0;
}

static int ds_layout_refresh_object(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return 0;

    int calls = 0;
    if (r_responds_main(obj, "setNeedsRelayout:")) {
        r_msg2_main(obj, "setNeedsRelayout:", 1, 0, 0, 0);
        calls++;
    }
    if (r_responds_main(obj, "setNeedsLayout")) {
        r_msg2_main(obj, "setNeedsLayout", 0, 0, 0, 0);
        calls++;
    }
    if (r_responds_main(obj, "layoutIfNeeded")) {
        r_msg2_main(obj, "layoutIfNeeded", 0, 0, 0, 0);
        calls++;
    }
    if (r_responds_main(obj, "setNeedsDisplay")) {
        r_msg2_main(obj, "setNeedsDisplay", 0, 0, 0, 0);
        calls++;
    }
    return calls;
}

static void ds_layout_add_unique(uint64_t *items, int *count, int cap, uint64_t item)
{
    if (!items || !count || *count >= cap || !r_is_objc_ptr(item)) return;
    for (int i = 0; i < *count; i++) {
        if (items[i] == item) return;
    }
    items[(*count)++] = item;
}

static int ds_layout_collect_array_lists(uint64_t lists,
                                         uint64_t *out,
                                         int count,
                                         int cap)
{
    if (!r_is_objc_ptr(lists) || !out || count >= cap) return count;

    uint64_t n = r_responds_main(lists, "count")
        ? r_msg2_main(lists, "count", 0, 0, 0, 0) : 0;
    if (n > 64) n = 64;
    for (uint64_t i = 0; i < n && count < cap; i++) {
        uint64_t lv = r_responds_main(lists, "objectAtIndex:")
            ? r_msg2_main(lists, "objectAtIndex:", i, 0, 0, 0) : 0;
        ds_layout_add_unique(out, &count, cap, lv);
    }
    return count;
}

static uint64_t ds_layout_root_folder_controller(uint64_t mgr)
{
    if (!r_is_objc_ptr(mgr)) return 0;
    const char *sels[] = {
        "rootFolderController",
        "_rootFolderController",
        "rootFolderViewController",
        NULL,
    };
    for (int i = 0; sels[i]; i++) {
        if (!r_responds_main(mgr, sels[i])) continue;
        uint64_t root = r_msg2_main(mgr, sels[i], 0, 0, 0, 0);
        if (r_is_objc_ptr(root)) return root;
    }
    return 0;
}

static int ds_layout_collect_root_lists(uint64_t mgr, uint64_t *out, int cap)
{
    if (!out || cap <= 0) return 0;

    int count = 0;
    uint64_t rootFC = ds_layout_root_folder_controller(mgr);
    if (!r_is_objc_ptr(rootFC)) return 0;

    const char *singleSels[] = {
        "currentIconListView",
        "currentRootIconListView",
        "currentIconList",
        "currentRootIconList",
        NULL,
    };
    for (int i = 0; singleSels[i] && count < cap; i++) {
        if (!r_responds_main(rootFC, singleSels[i])) continue;
        uint64_t lv = r_msg2_main(rootFC, singleSels[i], 0, 0, 0, 0);
        ds_layout_add_unique(out, &count, cap, lv);
    }

    const char *arraySels[] = {
        "visibleIconListViews",
        "iconListViews",
        NULL,
    };
    for (int i = 0; arraySels[i] && count < cap; i++) {
        if (!r_responds_main(rootFC, arraySels[i])) continue;
        uint64_t lists = r_msg2_main(rootFC, arraySels[i], 0, 0, 0, 0);
        count = ds_layout_collect_array_lists(lists, out, count, cap);
    }

    if (r_responds_main(rootFC, "iconListViewCount") &&
        r_responds_main(rootFC, "iconListViewAtIndex:")) {
        uint64_t n = r_msg2_main(rootFC, "iconListViewCount", 0, 0, 0, 0);
        if (n > 64) n = 64;
        for (uint64_t i = 0; i < n && count < cap; i++) {
            uint64_t lv = r_msg2_main(rootFC, "iconListViewAtIndex:", i, 0, 0, 0);
            ds_layout_add_unique(out, &count, cap, lv);
        }
    }

    return count;
}

static int ds_layout_collect_relevant_lists(uint64_t mgr,
                                            uint64_t *out,
                                            int cap)
{
    if (!out || cap <= 0) return 0;

    uint64_t clsListView = r_class("SBIconListView");
    if (!r_is_objc_ptr(clsListView)) return 0;

    int count = 0;
    uint64_t winLists[64] = {0};
    int winCount = sb_collect_views_in_windows(clsListView, winLists, 64);
    for (int i = 0; i < winCount; i++) {
        ds_layout_add_unique(out, &count, cap, winLists[i]);
    }

    uint64_t rootLists[64] = {0};
    int rootCount = ds_layout_collect_root_lists(mgr, rootLists, 64);
    for (int i = 0; i < rootCount; i++) {
        ds_layout_add_unique(out, &count, cap, rootLists[i]);
    }

    if (count == 0 && mgr) {
        uint64_t rootFC = ds_layout_root_folder_controller(mgr);
        if (rootFC) {
            uint64_t rv = r_responds_main(rootFC, "view")
                ? r_msg2_main(rootFC, "view", 0, 0, 0, 0) : 0;
            if (!rv && r_responds_main(rootFC, "rootFolderView")) {
                rv = r_msg2_main(rootFC, "rootFolderView", 0, 0, 0, 0);
            }
            uint64_t fallback[64] = {0};
            int fallbackCount = r_is_objc_ptr(rv)
                ? sb_collect_views(rv, clsListView, fallback, 64) : 0;
            for (int i = 0; i < fallbackCount; i++) {
                ds_layout_add_unique(out, &count, cap, fallback[i]);
            }
        }
    }

    return count;
}

static int ds_layout_refresh_visible_lists(uint64_t mgr, uint64_t dockLV)
{
    enum { LV_CAP = 64 };
    uint64_t lvs[LV_CAP] = {0};
    int nlv = ds_layout_collect_relevant_lists(mgr, lvs, LV_CAP);

    int calls = 0;
    for (int i = 0; i < nlv; i++) {
        uint64_t lv = lvs[i];
        if (!r_is_objc_ptr(lv)) continue;
        calls += ds_layout_refresh_object(lv);
    }
    if (r_is_objc_ptr(dockLV)) {
        calls += ds_layout_refresh_object(dockLV);
    }
    printf("[LAYOUT] visible/root list refresh lists=%d dock=0x%llx calls=%d\n",
           nlv, dockLV, calls);
    return calls;
}

bool darksword_layout_home_spacing_in_session(double exL, double exR, double exT, double exB)
{
    printf("[HSSPACE] ios=%d left=%.2f right=%.2f top=%.2f bottom=%.2f\n",
           ds_layout_ios_major(), exL, exR, exT, exB);
    uint64_t ctrl = rc_icon_controller();
    if (!ctrl) { printf("[HSSPACE] SBIconController nil\n"); return false; }
    uint64_t mgr = rc_icon_manager_for(ctrl);
    uint64_t cfg = rc_root_layout_config(ctrl, mgr);
    if (!cfg) { printf("[HSSPACE] root layoutConfiguration nil\n"); return false; }
    uint64_t clsInv = r_class("NSInvocation");
    if (!clsInv) return false;

    RC_UIEdgeInsets ins = {
        .top    = 60.0  + exT,
        .left   = 27.0  + exL,
        .bottom = 100.0 + exB,
        .right  = 27.0  + exR,
    };
    bool ok = rc_set_insets_on(cfg, clsInv, &ins);
    if (ok) {
        rc_force_manager_relayout(mgr, clsInv);
        ds_layout_refresh_visible_lists(mgr, rc_dock_list_view(ctrl, mgr));
    }
    return ok;
}

bool darksword_layout_dock_spacing_in_session(double extraHorizontal)
{
    printf("[DOCKSPACE] ios=%d extraH=%.2f\n", ds_layout_ios_major(), extraHorizontal);
    uint64_t ctrl = rc_icon_controller();
    if (!ctrl) return false;
    uint64_t mgr = rc_icon_manager_for(ctrl);
    uint64_t dock = rc_dock_list_view(ctrl, mgr);
    if (!dock) { printf("[DOCKSPACE] dockListView nil\n"); return false; }
    uint64_t dockLayout = rc_safe_msg(dock, "layout", 0, 0, 0, 0);
    uint64_t dockCfg = dockLayout ? rc_safe_msg(dockLayout, "layoutConfiguration", 0, 0, 0, 0) : 0;
    if (!dockCfg) { printf("[DOCKSPACE] dock layoutConfiguration nil\n"); return false; }
    uint64_t clsInv = r_class("NSInvocation");
    if (!clsInv) return false;

    RC_UIEdgeInsets ins = {
        .top    = 0.0,
        .left   = 16.0 + extraHorizontal,
        .bottom = 0.0,
        .right  = 16.0 + extraHorizontal,
    };
    bool ok = rc_set_insets_on(dockCfg, clsInv, &ins);
    if (ok) {
        rc_force_manager_relayout(mgr, clsInv);
        ds_layout_refresh_visible_lists(mgr, dock);
    }
    return ok;
}

bool darksword_layout_home_scale_in_session(double scale)
{
    if (scale <= 0.0 || scale > 2.0) return false;
    printf("[HSSCALE] ios=%d scale=%.2f\n", ds_layout_ios_major(), scale);
    uint64_t ctrl = rc_icon_controller();
    if (!ctrl) return false;
    uint64_t mgr = rc_icon_manager_for(ctrl);
    uint64_t cfg = rc_root_layout_config(ctrl, mgr);
    if (!cfg) return false;
    uint64_t clsInv = r_class("NSInvocation");
    if (!clsInv) return false;

    RC_SBIconImageInfo info = {
        .width        = 60.0 * scale,
        .height       = 60.0 * scale,
        .scale        = 2.0,
        .cornerRadius = 13.5 * scale,
    };
    if (!rc_set_icon_info_on(cfg, clsInv, &info)) return false;

    enum { LV_CAP = 64 };
    uint64_t lvs[LV_CAP];
    int nlv = ds_layout_collect_relevant_lists(mgr, lvs, LV_CAP);
    for (int i = 0; i < nlv; i++) {
        if (rc_safe_msg(lvs[i], "isDock", 0, 0, 0, 0)) continue;
        rc_refresh_list_view(lvs[i], clsInv, &info);
        ds_layout_refresh_object(lvs[i]);
    }
    ds_layout_refresh_visible_lists(mgr, rc_dock_list_view(ctrl, mgr));
    return true;
}

bool darksword_layout_dock_scale_in_session(double scale)
{
    if (scale <= 0.0 || scale > 2.0) return false;
    printf("[DOCKSCALE] ios=%d scale=%.2f\n", ds_layout_ios_major(), scale);
    uint64_t ctrl = rc_icon_controller();
    if (!ctrl) return false;
    uint64_t mgr = rc_icon_manager_for(ctrl);
    uint64_t dock = rc_dock_list_view(ctrl, mgr);
    if (!dock) return false;
    uint64_t dockLayout = rc_safe_msg(dock, "layout", 0, 0, 0, 0);
    uint64_t dockCfg = dockLayout ? rc_safe_msg(dockLayout, "layoutConfiguration", 0, 0, 0, 0) : 0;
    uint64_t clsInv = r_class("NSInvocation");
    if (!clsInv) return false;

    RC_SBIconImageInfo info = {
        .width        = 60.0 * scale,
        .height       = 60.0 * scale,
        .scale        = 2.0,
        .cornerRadius = 13.5 * scale,
    };
    if (dockCfg) rc_set_icon_info_on(dockCfg, clsInv, &info);

    int touched = rc_refresh_list_view(dock, clsInv, &info);
    ds_layout_refresh_object(dock);
    if (touched == 0) {
        enum { LV_CAP = 64 };
        uint64_t lvs[LV_CAP];
        int nlv = ds_layout_collect_relevant_lists(mgr, lvs, LV_CAP);
        for (int i = 0; i < nlv; i++) {
            if (rc_safe_msg(lvs[i], "isDock", 0, 0, 0, 0)) {
                rc_refresh_list_view(lvs[i], clsInv, &info);
                ds_layout_refresh_object(lvs[i]);
            }
        }
    }
    ds_layout_refresh_visible_lists(mgr, dock);
    return true;
}

// iOS 26: the (now-immutable) AMUIInfographIconListLayout doesn't have a
// layoutConfiguration we can mutate, so we bypass it entirely and just
// adjust the live SBIconListViews and their child SBIconViews directly.
// Effects are one-shot at Run; iOS 26's auto-layout will re-fit on a
// subsequent layout pass (orientation change, page swipe, etc.).
// On iOS 26 the icon GRID is positioned inside each page by the immutable
// AMUIInfographIconListLayout, using static qword tables in AmbientUI's
// __const segment. The SBIconListView itself (the "page" view) is laid
// out by auto-layout to fill the screen, so setFrame: on it has no
// visible effect — the page-internal grid re-centers within whatever
// bounds we set. The reliable iOS 26 lever is per-icon image size via
// -[SBIconView setIconImageInfo:], which DOES still exist and which
// auto-layout respects on the next pass.
//
// To keep the same Settings UI working, we apply a CATransform3D /
// `transform` SCALE to each non-dock list view that incorporates the
// user-set "extra padding" as a scale-down ratio. Effective padding:
// w/h_new = w/h - (left+right) / -(top+bottom). The whole grid shrinks
// inside its bounds, creating visible empty space at the edges. The
// dock gets its own transform driven by dockExH.
static bool darksword_layout_apply_in_session_ios26(double exL, double exR, double exT, double exB,
                                                    double dockExH,
                                                    double homeScale, double dockScale)
{
    printf("[LAYOUT26] home=+L%.1f/R%.1f/T%.1f/B%.1f dock=+H%.1f homeScale=%.2f dockScale=%.2f\n",
           exL, exR, exT, exB, dockExH, homeScale, dockScale);

    uint64_t clsListView = r_class("SBIconListView");
    if (!clsListView) { printf("[LAYOUT26] SBIconListView class missing\n"); return false; }
    uint64_t clsInv = r_class("NSInvocation");

    // Resolve dock list view up front so we can identify it by pointer
    // instead of relying on -[SBIconListView isDock] (which returns NO
    // for everything we tried on iOS 26.0.1).
    uint64_t ctrl = rc_icon_controller();
    uint64_t mgr  = rc_icon_manager_for(ctrl);
    uint64_t dockLV = rc_dock_list_view(ctrl, mgr);
    if (dockLV) printf("[LAYOUT26] dockListView=0x%llx\n", dockLV);

    enum { LV_CAP = 64 };
    uint64_t lvs[LV_CAP];
    int nlv = ds_layout_collect_relevant_lists(mgr, lvs, LV_CAP);
    printf("[LAYOUT26] discovered %d SBIconListView(s)\n", nlv);
    if (nlv == 0) return false;

    bool anyOk = false;

    // Establish the "canonical" home page size — the most common (w,h) among
    // the collected SBIconListViews. Everything that matches this size is
    // treated as a home page; everything else (App Library, Today view,
    // nested grids) is skipped so we don't fight their auto-layout and make
    // icons "disappear".
    int sizeCounts[LV_CAP] = {0};
    double sizeW[LV_CAP] = {0}, sizeH[LV_CAP] = {0};
    int distinctSizes = 0;
    double frameCache[LV_CAP][4];
    bool haveFrameCache[LV_CAP];
    for (int i = 0; i < nlv; i++) {
        haveFrameCache[i] = false;
        if (!lvs[i]) continue;
        haveFrameCache[i] = r_msg2_main_struct_ret(lvs[i], "frame",
                                                    frameCache[i], sizeof(frameCache[i]),
                                                    NULL, 0, NULL, 0, NULL, 0, NULL, 0);
        if (!haveFrameCache[i]) continue;
        double w = frameCache[i][2], h = frameCache[i][3];
        if (lvs[i] == dockLV) continue;     // dock is its own thing
        int found = -1;
        for (int j = 0; j < distinctSizes; j++) {
            if (sizeW[j] == w && sizeH[j] == h) { found = j; break; }
        }
        if (found >= 0) sizeCounts[found]++;
        else if (distinctSizes < LV_CAP) {
            sizeW[distinctSizes] = w;
            sizeH[distinctSizes] = h;
            sizeCounts[distinctSizes] = 1;
            distinctSizes++;
        }
    }
    int bestIdx = -1;
    for (int j = 0; j < distinctSizes; j++) {
        if (bestIdx < 0 || sizeCounts[j] > sizeCounts[bestIdx]) bestIdx = j;
    }
    double homeW = (bestIdx >= 0) ? sizeW[bestIdx] : 0.0;
    double homeH = (bestIdx >= 0) ? sizeH[bestIdx] : 0.0;
    if (bestIdx >= 0) {
        printf("[LAYOUT26] home page size: %.1fx%.1f (matches %d list view(s))\n",
               homeW, homeH, sizeCounts[bestIdx]);
    }

    for (int i = 0; i < nlv; i++) {
        uint64_t lv = lvs[i];
        if (!lv) continue;
        bool isDock = (dockLV != 0 && lv == dockLV);
        if (!isDock) {
            isDock = rc_safe_msg(lv, "isDock", 0, 0, 0, 0) != 0;
        }

        // Skip list views that aren't either the dock or a canonical home
        // page — those are the App Library / Today / nested containers, and
        // transforming them is what was making icons "disappear" earlier.
        if (!isDock && haveFrameCache[i] && bestIdx >= 0) {
            double w = frameCache[i][2], h = frameCache[i][3];
            if (w != homeW || h != homeH) {
                printf("[LAYOUT26]   skip non-page list view {%.1fx%.1f}\n", w, h);
                continue;
            }
        }

        // ---- Page-internal grid scale (visible "spacing" + "scale") ----
        // On iOS 26 we drive BOTH the spacing sliders and the scale sliders
        // through one CGAffineTransform per list view. Why not also call
        // -[SBIconView setIconImageInfo:] like the iOS 18 path? Because on
        // iOS 26 that invalidates the icon's cached image and the dock
        // never gets a follow-up layout pass to refetch it, so dock icons
        // stay blank until next respring. Pure transform avoids the cache
        // invalidation entirely — icons just get drawn smaller.
        double frame[4] = { 0, 0, 0, 0 };
        bool haveFrame = haveFrameCache[i];
        if (haveFrame) memcpy(frame, frameCache[i], sizeof(frame));
        else haveFrame = r_msg2_main_struct_ret(lv, "frame", frame, sizeof(frame),
                                                NULL, 0, NULL, 0, NULL, 0, NULL, 0);
        if (haveFrame) {
            double w = frame[2], h = frame[3];
            double scaleX = 1.0, scaleY = 1.0;
            if (isDock) {
                if (dockExH != 0.0 && w > 0.0) {
                    double avail = w - 2.0 * dockExH;
                    if (avail > 0.0) scaleX = avail / w;
                    scaleY = scaleX;
                }
                if (dockScale > 0.0 && dockScale != 1.0) {
                    scaleX *= dockScale;
                    scaleY *= dockScale;
                }
            } else {
                if (exL + exR != 0.0 && w > 0.0) {
                    double availW = w - (exL + exR);
                    if (availW > 0.0) scaleX = availW / w;
                }
                if (exT + exB != 0.0 && h > 0.0) {
                    double availH = h - (exT + exB);
                    if (availH > 0.0) scaleY = availH / h;
                }
                if (homeScale > 0.0 && homeScale != 1.0) {
                    scaleX *= homeScale;
                    scaleY *= homeScale;
                }
            }
            if (scaleX != 1.0 || scaleY != 1.0) {
                // CGAffineTransform: { a, b, c, d, tx, ty } — 6 doubles, 48 bytes.
                // Pure scale: { sx, 0, 0, sy, 0, 0 }.
                double xf[6] = { scaleX, 0.0, 0.0, scaleY, 0.0, 0.0 };
                r_msg2_main_raw(lv, "setTransform:",
                                xf, sizeof(xf),
                                NULL, 0, NULL, 0, NULL, 0);
                printf("[LAYOUT26]   %s transform scale=(%.3f,%.3f) frameWxH=%.1fx%.1f\n",
                       isDock ? "dock" : "home", scaleX, scaleY, w, h);
                ds_layout_refresh_object(lv);
                anyOk = true;
            } else {
                // Reset to identity in case a prior Run left a transform.
                double identity[6] = { 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 };
                r_msg2_main_raw(lv, "setTransform:",
                                identity, sizeof(identity),
                                NULL, 0, NULL, 0, NULL, 0);
                ds_layout_refresh_object(lv);
                anyOk = true;
            }
        }
    }
    return anyOk;
}

bool darksword_layout_apply_in_session(double exL, double exR, double exT, double exB,
                                       double dockExH, double homeScale, double dockScale)
{
    if (ds_layout_ios_major() >= 26) {
        return darksword_layout_apply_in_session_ios26(exL, exR, exT, exB,
                                                        dockExH, homeScale, dockScale);
    }
    bool ok = true;
    ok &= darksword_layout_home_spacing_in_session(exL, exR, exT, exB);
    ok &= darksword_layout_dock_spacing_in_session(dockExH);
    if (homeScale > 0.0) ok &= darksword_layout_home_scale_in_session(homeScale);
    if (dockScale > 0.0) ok &= darksword_layout_dock_scale_in_session(dockScale);
    return ok;
}
