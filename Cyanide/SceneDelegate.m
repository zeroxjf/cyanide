//
//  SceneDelegate.m
//  Cyanide
//
//  Created by seo on 3/24/26.
//

#import "SceneDelegate.h"
#import "SettingsViewController.h"
#import "UpdateChecker.h"

@interface SceneDelegate ()
@property (nonatomic, assign) BOOL didSelectInitialTab;

@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UITabBarController *tab = (UITabBarController *)self.window.rootViewController;
    if ([tab isKindOfClass:UITabBarController.class] && tab.viewControllers.count > 1) {
        // iOS 26+: collapse the floating tab bar into a pill while the user
        // scrolls down, expand it back on scroll up. Falls through silently
        // on older OSes since the selector won't be present.
        SEL minSel = NSSelectorFromString(@"setTabBarMinimizeBehavior:");
        if ([tab respondsToSelector:minSel]) {
            NSMethodSignature *sig = [tab methodSignatureForSelector:minSel];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = tab;
            inv.selector = minSel;
            NSInteger onScrollDown = 1; // UITabBarMinimizeBehavior.onScrollDown
            [inv setArgument:&onScrollDown atIndex:2];
            [inv invoke];
        }
    }
}

- (void)selectInitialTabIfNeeded {
    if (self.didSelectInitialTab) return;
    UITabBarController *tab = (UITabBarController *)self.window.rootViewController;
    if (![tab isKindOfClass:UITabBarController.class] || tab.viewControllers.count == 0) return;
    self.didSelectInitialTab = YES;
    tab.selectedIndex = 0; // Installer tab
}


- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)runUpdateCheck {
    UITabBarController *tab = (UITabBarController *)self.window.rootViewController;
    if (![tab isKindOfClass:UITabBarController.class]) return;
    // UpdateChecker walks `presentedViewController` to find the topmost VC and
    // presents from there, so if the Signal prompt is up, the update prompt can
    // still surface independently.
    [[UpdateChecker shared] checkForUpdatesIfNeededFrom:tab];
}

- (void)showSignalGroupNoticeIfNeeded {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *noticeKey = @"cyanide.community.signalGroupNoticeShown";
    if ([ud boolForKey:noticeKey]) return;

    UIViewController *root = self.window.rootViewController;
    if (!root) return;
    NSString *msg = @"I'm creating a Signal group as the main place for Cyanide feedback and support.\n\nUse it to report bugs, request features, share test results, ask setup questions, and get notes about new builds.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Join the Cyanide Signal Group"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Join Signal" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [ud setBool:YES forKey:noticeKey];
        [ud synchronize];
        NSURL *url = [NSURL URLWithString:@"https://t.co/afPR3U04G1"];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Not Now" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        [ud setBool:YES forKey:noticeKey];
        [ud synchronize];
    }]];
    [root presentViewController:alert animated:YES completion:nil];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self selectInitialTabIfNeeded];
    settings_application_did_become_active();
    // Independent paths: Signal group notice (one-time) and update
    // check (every foreground; UpdateChecker enforces a per-process + 24-hour
    // persisted throttle so the API isn't hammered).
    [self showSignalGroupNoticeIfNeeded];
    [self runUpdateCheck];
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    settings_application_will_enter_foreground();
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    settings_application_did_enter_background();
}


@end
