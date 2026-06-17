//
//  sb_walk.m
//  Lifted verbatim from darksword_layout.m's rc_collect_list_views /
//  rc_collect_from_windows so themer.m and any future tweak can share them
//  without duplicating the BFS.
//

#import "sb_walk.h"
#import "remote_objc.h"

static uint64_t sw_safe_msg(uint64_t obj, const char *selname,
                            uint64_t a, uint64_t b, uint64_t c, uint64_t d)
{
    if (!obj) return 0;
    uint64_t sel = r_sel(selname);
    uint64_t rs  = r_sel("respondsToSelector:");
    if (!sel || !rs) return 0;
    if (!r_msg(obj, rs, sel, 0, 0, 0)) return 0;
    return r_msg(obj, sel, a, b, c, d);
}

int sb_collect_views(uint64_t root, uint64_t klass, uint64_t *out, int cap)
{
    if (!root || !klass || cap <= 0) return 0;
    uint64_t selSub  = r_sel("subviews");
    uint64_t selCnt  = r_sel("count");
    uint64_t selObj  = r_sel("objectAtIndex:");
    uint64_t selKind = r_sel("isKindOfClass:");

    enum { QMAX = 4096 };
    static uint64_t q[QMAX];
    int head = 0, tail = 0, found = 0, visited = 0;
    q[tail++] = root;
    while (head < tail && visited < QMAX) {
        uint64_t v = q[head++];
        visited++;
        if (!v) continue;
        if (r_msg(v, selKind, klass, 0, 0, 0)) {
            if (found < cap) out[found++] = v;
            continue;
        }
        uint64_t subs = r_msg(v, selSub, 0, 0, 0, 0);
        if (!subs) continue;
        uint64_t cn = r_msg(subs, selCnt, 0, 0, 0, 0);
        if (cn > 256) cn = 256;
        for (uint64_t i = 0; i < cn && tail < QMAX; i++) {
            uint64_t c = r_msg(subs, selObj, i, 0, 0, 0);
            if (c) q[tail++] = c;
        }
    }
    return found;
}

int sb_collect_views_in_windows(uint64_t klass, uint64_t *out, int cap)
{
    uint64_t clsApp = r_class("UIApplication");
    if (!clsApp) return 0;
    uint64_t app = sw_safe_msg(clsApp, "sharedApplication", 0, 0, 0, 0);
    if (!app) return 0;

    int n = 0;
    uint64_t wins = sw_safe_msg(app, "windows", 0, 0, 0, 0);
    if (wins) {
        uint64_t wc = r_msg(wins, r_sel("count"), 0, 0, 0, 0);
        if (wc > 32) wc = 32;
        for (uint64_t i = 0; i < wc && n < cap; i++) {
            uint64_t w = r_msg(wins, r_sel("objectAtIndex:"), i, 0, 0, 0);
            if (w) n += sb_collect_views(w, klass, out + n, cap - n);
        }
    }
    if (n == 0) {
        uint64_t kw = sw_safe_msg(app, "keyWindow", 0, 0, 0, 0);
        if (kw) n += sb_collect_views(kw, klass, out + n, cap - n);
    }
    return n;
}
