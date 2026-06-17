//
//  SettingsViewController.h
//  Cyanide
//

#import <UIKit/UIKit.h>
#import "CyanideEngine.h"

@interface SettingsViewController : UITableViewController

// Detail-mode init: renders a single underlying section (one tweak bundle).
// Pass underlyingSection == NSIntegerMax for root-mode (default storyboard path).
- (instancetype)initWithUnderlyingSection:(NSInteger)underlyingSection
                              bundleTitle:(nullable NSString *)bundleTitle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

// When set on a bundle-detail SettingsViewController launched from the
// Installer's "Customize" row, the nav bar shows a left-side back button
// ("← <package name>") that pops Settings to root and switches the user
// back to the Installer tab — so the install action stays one tap away
// after customizing.
@property (nonatomic, copy, nullable) NSString *installerReturnPackageName;

// Current values for each configurable row in a settings section.
// Each entry: @{@"title": <label string>, @"value": <current value string>}.
// Returns empty array when the section has no configurable rows.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)settingsSummaryForSection:(NSInteger)section;
+ (BOOL)liveWPHasSelectedVideo;

@end
