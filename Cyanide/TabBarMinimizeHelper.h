//
//  TabBarMinimizeHelper.h
//  Cyanide
//
//  ObjC shim to call setTabBarMinimizeBehavior: (iOS 26+) from Swift,
//  which cannot use NSMethodSignature/NSInvocation.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Applies UITabBarMinimizeBehavior.onScrollDown (value 1) to the given
/// tab bar controller if the selector is available (iOS 26+). No-op on
/// older OSes or if the selector is not present.
void tab_bar_apply_scroll_minimize(UITabBarController *tab);

NS_ASSUME_NONNULL_END
