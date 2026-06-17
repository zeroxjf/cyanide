//
//  TabBarMinimizeHelper.m
//  Cyanide
//

#import "TabBarMinimizeHelper.h"

void tab_bar_apply_scroll_minimize(UITabBarController *tab) {
    SEL minSel = NSSelectorFromString(@"setTabBarMinimizeBehavior:");
    if (![tab respondsToSelector:minSel]) return;
    NSMethodSignature *sig = [tab methodSignatureForSelector:minSel];
    if (!sig) return;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = tab;
    inv.selector = minSel;
    NSInteger onScrollDown = 1; // UITabBarMinimizeBehavior.onScrollDown
    [inv setArgument:&onScrollDown atIndex:2];
    [inv invoke];
}
