//
//  SettingsViewController.m
//  Cyanide
//

#import "SettingsViewController.h"
#import "CyanideEngine.h"
#import "CyanideEngine+Internal.h"
#import "Cyanide-Swift.h"
#import "installer/PackageQueueConstants.h"
#import "PatreonAuth.h"
#import "UpdateChecker.h"
#import "SBLArchiveExtractor.h"
#import "NiceBarSettingsSupport.h"
#import "LogTextView.h"
#import "tweaks/livewp.h"
#import "tweaks/snowboardlite.h"
#import "tweaks/themer.h"
#import "tweaks/statbar.h"
#import "tweaks/nsbar.h"
#import "tweaks/axonlite.h"
#import "tweaks/powercuff.h"
#import "tweaks/sbcustomizer.h"
#import "tweaks/nano_registry.h"
#import "tweaks/appswitchergrid.h"
#import "tweaks/darksword_ota.h"
#import "tweaks/killallapps.h"
#import "tweaks/private_compat.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/persistence.h"
#import "DSKeepAlive.h"
#import "TaskRop/RemoteCall.h"
#import "kexploit/kutils.h"
#import <WebKit/WebKit.h>
#import <MessageUI/MessageUI.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <notify.h>
#import <math.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <stdlib.h>

@interface SettingsViewController () <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, strong) UISegmentedControl *powercuffSegmented;
@property (nonatomic, assign) BOOL pendingManualActionsReload;
@property (nonatomic, assign) BOOL detailMode;
@property (nonatomic, assign) NSInteger underlyingSection;
@property (nonatomic, copy)   NSString *bundleTitle;
@property (nonatomic, assign) BOOL changelogExpanded;
@property (nonatomic, copy)   NSString *pendingThemeImportMode;
- (void)forceDisableFastLockXLiteForExperimentalGateWithDefaults:(NSUserDefaults *)defaults;
@end

// Singleton delegate so MFMailCompose's host VC doesn't need to conform. Lives
// for the app's lifetime — a single instance handles every dismissal across
// every entry point (Settings → Contact, Installer → Contact button, etc.).
@interface _CyanideMailDelegate : NSObject <MFMailComposeViewControllerDelegate>
@end
@implementation _CyanideMailDelegate
- (void)mailComposeController:(MFMailComposeViewController *)c
          didFinishWithResult:(MFMailComposeResult)r error:(NSError *)e
{
    (void)r; (void)e;
    [c dismissViewControllerAnimated:YES completion:nil];
}
@end
static _CyanideMailDelegate *_cyanide_mail_delegate(void) {
    static _CyanideMailDelegate *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[_CyanideMailDelegate alloc] init]; });
    return d;
}

@interface ThemerFormatGuideViewController : UITableViewController
@end

@implementation ThemerFormatGuideViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Theme Format";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 2 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0: return @"Folder Theme";
        case 1: return @"Plist Theme";
        case 2: return @"Files";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        return @"Only icons with matching bundle IDs change. Missing apps keep their stock icon.";
    }
    if (section == 1) {
        return @"Use a binary plist when you want one portable file instead of a folder of PNGs.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"guide"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"guide"];
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"PNG Files";
        cell.detailTextLabel.text =
            @"Make a folder containing PNG files named by app bundle ID:\n"
             "com.apple.mobilesafari.png\n"
             "com.apple.MobileSMS.png\n"
             "com.apple.mobiletimer.png";
    } else if (indexPath.section == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"Bundle ID → PNG Data";
        cell.detailTextLabel.text =
            @"Make a dictionary plist. Each key is a bundle ID. Each value is raw PNG data. "
             "Cyanide imports the plist and copies it into Documents/Themes.";
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Share Sample Theme Plist";
            cell.detailTextLabel.text = @"Exports a small binary plist template with example bundle IDs.";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Share iOS 6 Theme Plist";
            cell.detailTextLabel.text = @"Exports the iOS 6 Theme plist. Icons by zagnut531/iOS-6-Icons.";
        } else {
            cell.textLabel.text = @"Share App Info.plist";
            cell.detailTextLabel.text = @"Exports Cyanide's bundled Info.plist for reference.";
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (NSData *)sampleIconPNGWithText:(NSString *)text color:(UIColor *)color
{
    CGSize size = CGSizeMake(120.0, 120.0);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size
                                                                               format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:27.0] addClip];
        [color setFill];
        UIRectFill(rect);

        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:48.0 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: UIColor.whiteColor,
        };
        CGSize textSize = [text sizeWithAttributes:attrs];
        CGRect textRect = CGRectMake((size.width - textSize.width) / 2.0,
                                     (size.height - textSize.height) / 2.0,
                                     textSize.width,
                                     textSize.height);
        [text drawInRect:textRect withAttributes:attrs];
    }];
    return UIImagePNGRepresentation(image);
}

- (NSURL *)writeSamplePlist:(NSError **)error
{
    NSData *safari = [self sampleIconPNGWithText:@"S"
                                           color:[UIColor colorWithRed:0.05 green:0.45 blue:0.95 alpha:1.0]];
    NSData *sms = [self sampleIconPNGWithText:@"M"
                                        color:[UIColor colorWithRed:0.10 green:0.65 blue:0.25 alpha:1.0]];
    NSDictionary *plist = @{
        @"com.apple.mobilesafari": safari ?: [NSData data],
        @"com.apple.MobileSMS": sms ?: [NSData data],
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data) return nil;

    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"CyanideThemeTemplate.plist"]];
    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
    return url;
}

- (NSURL *)copyBuiltInIOS6Plist:(NSError **)error
{
    NSString *src = [[NSBundle mainBundle] pathForResource:@"Themes-iOS6" ofType:@"plist"];
    if (!src) {
        if (error) {
            *error = [NSError errorWithDomain:@"CyanideThemerGuide"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bundled iOS 6 plist was not found."}];
        }
        return nil;
    }

    NSURL *dst = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"Cyanide-iOS6-Theme.plist"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:dst.path]) {
        [fm removeItemAtURL:dst error:nil];
    }
    if (![fm copyItemAtURL:[NSURL fileURLWithPath:src] toURL:dst error:error]) return nil;
    return dst;
}

- (NSURL *)copyAppInfoPlist:(NSError **)error
{
    NSString *src = [[NSBundle mainBundle] pathForResource:@"Info" ofType:@"plist"];
    if (!src) {
        if (error) {
            *error = [NSError errorWithDomain:@"CyanideThemerGuide"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bundled Info.plist was not found."}];
        }
        return nil;
    }

    NSURL *dst = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"Cyanide-Info.plist"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:dst.path]) {
        [fm removeItemAtURL:dst error:nil];
    }
    if (![fm copyItemAtURL:[NSURL fileURLWithPath:src] toURL:dst error:error]) return nil;
    return dst;
}

- (void)dismissGuide
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareURL:(NSURL *)url sourceView:(UIView *)sourceView
{
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                                                     applicationActivities:nil];
    UIView *anchor = sourceView ?: self.view;
    vc.popoverPresentationController.sourceView = anchor;
    vc.popoverPresentationController.sourceRect = anchor.bounds;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)showExportError:(NSError *)error
{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Export Failed"
                                                                message:error.localizedDescription ?: @"Could not write the plist."
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;

    NSError *error = nil;
    NSURL *url = nil;
    if (indexPath.row == 0) {
        url = [self writeSamplePlist:&error];
    } else if (indexPath.row == 1) {
        url = [self copyBuiltInIOS6Plist:&error];
    } else {
        url = [self copyAppInfoPlist:&error];
    }
    if (!url) {
        [self showExportError:error];
        return;
    }

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [self shareURL:url sourceView:cell.contentView ?: tableView];
}

@end

@implementation SettingsViewController

+ (BOOL)liveWPHasSelectedVideo
{
    NSString *path = livewp_absolute_path();
    if (path.length == 0) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    // Calling [super initWithCoder:] (not initWithStyle:) so UIViewController's
    // unarchiving runs: that's what wires up the parentViewController and
    // navigationController relationships established by the storyboard's
    // rootViewController segue. Going through initWithStyle leaves nav nil.
    if ((self = [super initWithCoder:coder])) {
        _underlyingSection = NSIntegerMax;
    }
    return self;
}

- (instancetype)initWithUnderlyingSection:(NSInteger)underlyingSection
                              bundleTitle:(NSString *)bundleTitle
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _detailMode = YES;
        _underlyingSection = underlyingSection;
        _bundleTitle = [bundleTitle copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.detailMode ? (self.bundleTitle ?: @"Settings") : @"Settings";
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAlways;
    self.tableView.rowHeight                      = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight             = 44.0;
    self.tableView.sectionHeaderHeight            = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight   = 20.0;
    self.tableView.sectionFooterHeight            = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight   = 10.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"stepper"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"slider"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"segmented"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"action"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"button"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"warning"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"bundle"];
    [self installInstallerReturnButtonIfNeeded];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(remoteCallStateDidChange:)
                                                 name:kSettingsRemoteCallStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cleanupStateDidChange:)
                                                 name:kSettingsCleanupStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(patreonStatusDidChange:)
                                                 name:kCyanidePatreonStatusDidChangeNotification
                                               object:nil];

    // Best-effort background refresh of cached patron status when settings
    // opens. A cancelled / expired pledge silently flips the gate off here.
    if (!self.detailMode && cyanide_patreon_is_linked()) {
        cyanide_patreon_refresh(nil);
    }

    // Always-visible Respring button in the nav bar (top-right) so the user
    // doesn't have to scroll down to the Clean Up section to respring.
    // Mirrors the same flow used by the Clean Up alert: prepare → present the
    // existing WKWebView-based respring payload.
    if (!self.detailMode) {
        UIImage *icon = [UIImage systemImageNamed:@"arrow.clockwise.circle"];
        UIBarButtonItem *respringItem = [[UIBarButtonItem alloc] initWithImage:icon
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(navRespringTapped)];
        respringItem.accessibilityLabel = @"Respring";
        self.navigationItem.rightBarButtonItem = respringItem;
    }
}

- (void)navRespringTapped
{
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Respring?"
                         message:@"SpringBoard will restart. Any unsaved live state will be reset."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *_) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
                printf("[SETTINGS] nav respring blocked: actions already running\n");
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
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                settings_show_respring_overlay(strongSelf);
            });
        });
    }]];
    settings_present_controller(ac, self);
}

- (void)cleanupStateDidChange:(NSNotification *)note
{
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)installInstallerReturnButtonIfNeeded
{
    if (!self.installerReturnPackageName) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    UIImage *chevron = [UIImage systemImageNamed:@"chevron.backward" withConfiguration:cfg];
    [btn setImage:chevron forState:UIControlStateNormal];
    [btn setTitle:[@" " stringByAppendingString:self.installerReturnPackageName] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    btn.tintColor = self.view.tintColor;
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
    [btn addTarget:self action:@selector(returnToInstaller) forControlEvents:UIControlEventTouchUpInside];
    [btn sizeToFit];

    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:btn];
    self.navigationItem.leftBarButtonItem = backItem;
    self.navigationItem.hidesBackButton = YES;
}

- (void)returnToInstaller
{
    UITabBarController *tab = self.tabBarController;
    UINavigationController *settingsNav = self.navigationController;
    NSUInteger installerIdx = NSNotFound;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        UIViewController *vc = tab.viewControllers[i];
        if ([vc.tabBarItem.title isEqualToString:@"Installer"]) {
            installerIdx = i;
            break;
        }
    }
    [settingsNav popToRootViewControllerAnimated:NO];
    if (installerIdx != NSNotFound) {
        tab.selectedIndex = installerIdx;
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadManualActions];

    // The NanoRegistry plist lives behind a sandbox wall on-device. Keep the
    // detail panel passive; the explicit "Load Current" button performs the
    // privileged KRW/sandbox setup before reading it.
    if (self.detailMode && self.underlyingSection == SectionNanoRegistry) {
        if (self.isViewLoaded) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self presentPowercuffNominalNoticeIfNeeded];
    if (!self.pendingManualActionsReload) return;
    self.pendingManualActionsReload = NO;
    [self reloadManualActions];
}

- (void)presentPowercuffNominalNoticeIfNeeded
{
    if (!self.detailMode || self.underlyingSection != SectionPowercuff) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d boolForKey:kSettingsPowercuffNominalNoticeShown]) return;

    NSString *level = [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal";
    BOOL alreadyNominal = [level isEqualToString:@"nominal"];
    NSString *message = @"Powercuff now defaults to Nominal.\n\nLight, Moderate, and Heavy intentionally underclock the CPU. That means lag or slower app launches can happen, especially on older devices. The lag means Powercuff is working, but those levels may be too slow for comfortable day-to-day use.\n\nUse Nominal for daily use, then raise it only when you want stronger throttling.";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Powercuff Level"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    if (!alreadyNominal) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Use Nominal"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:@"nominal" forKey:kSettingsPowercuffLevel];
            [defaults setBool:YES forKey:kSettingsPowercuffNominalNoticeShown];
            [defaults synchronize];
            [weakSelf.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:alreadyNominal ? @"OK" : @"Keep Current"
                                             style:UIAlertActionStyleCancel
                                           handler:^(UIAlertAction *_) {
        [d setBool:YES forKey:kSettingsPowercuffNominalNoticeShown];
        [d synchronize];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)remoteCallStateDidChange:(NSNotification *)notification
{
    [self reloadManualActions];
}

- (void)reloadManualActions
{
    if (!self.isViewLoaded) return;
    if (self.detailMode) return;
    if (!self.tableView.window) {
        self.pendingManualActionsReload = YES;
        return;
    }

    // Returning from Patreon OAuth can change the Patreon root section row
    // count (unlinked: 2, linked patron: 3, linked non-patron: 4) before the
    // status notification's full reload runs. A targeted Quick Actions
    // reload during that window makes UITableView validate the now-stale
    // Patreon section and crash with an invalid row-count assertion.
    if ([self.tableView numberOfSections] > RootSectionPatreon) {
        NSInteger visiblePatreonRows = [self.tableView numberOfRowsInSection:RootSectionPatreon];
        NSInteger desiredPatreonRows = [self tableView:self.tableView
                                numberOfRowsInSection:RootSectionPatreon];
        if (visiblePatreonRows != desiredPatreonRows) {
            [self.tableView reloadData];
            return;
        }
    }

    NSIndexSet *sections = [NSIndexSet indexSetWithIndex:RootSectionActions];
    [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
}

- (UITableViewCell *)buildWarningCell:(UITableViewCell *)cell
{
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle.fill"]];
    icon.tintColor = UIColor.systemOrangeColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Cyanide is a limited tweak environment. Session tweaks reset on reboot, while a few packages intentionally modify local system files and may persist until restored. Backups are best-effort only. Use these tools only where you have permission, understand the legal and service-rule impact, and accept the risk. Live tweaks like StatBar and Axon Lite stop if you force-quit Cyanide. A progress log opens while changes apply; tap Hide to dismiss.";
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:icon];
    [cell.contentView addSubview:label];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor   constraintEqualToAnchor:m.leadingAnchor],
        [icon.centerYAnchor   constraintEqualToAnchor:label.centerYAnchor],
        [icon.widthAnchor     constraintEqualToConstant:22],
        [icon.heightAnchor    constraintEqualToConstant:22],
        [label.leadingAnchor  constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [label.topAnchor      constraintEqualToAnchor:m.topAnchor constant:4],
        [label.bottomAnchor   constraintEqualToAnchor:m.bottomAnchor constant:-4],
    ]];
    return cell;
}

#pragma mark - Row models

- (NSArray<NSDictionary *> *)launchRows
{
    return @[
        @{ @"key": kSettingsAutoRunKexploit,    @"title": @"Auto-run kexploit on launch" },
        @{ @"key": kSettingsRunSandboxEscape,   @"title": @"Sandbox escape (escape_sbx_demo2)" },
        @{ @"key": kSettingsKeepAlive,          @"title": @"Keep app alive in background",
           @"subtitle": @"Required for app-driven live tweaks to persist while minimized, including StatBar receiving fresh live data." },
    ];
}

// The master enable / install-equivalent rows have been removed from each
// tweak's row list — install/uninstall is handled by the Installer tab's
// Install button. Settings only shows configuration knobs.

- (NSArray<NSDictionary *> *)sbcRows
{
    return @[
        @{ @"kind": @"stepper", @"key": kSettingsSBCDockIcons,  @"title": @"Dock icons", @"min": @4, @"max": @7, @"default": @(kSBCDefaultDockIcons) },
        @{ @"kind": @"stepper", @"key": kSettingsSBCCols,       @"title": @"Home columns", @"min": @3, @"max": @7, @"default": @(kSBCDefaultCols) },
        @{ @"kind": @"stepper", @"key": kSettingsSBCRows,       @"title": @"Home rows", @"min": @4, @"max": @8, @"default": @(kSBCDefaultRows) },
        @{ @"kind": @"toggle",  @"key": kSettingsSBCHideLabels, @"title": @"Hide icon labels" },
        @{ @"kind": @"button",  @"title": @"Reset to Defaults" },
    ];
}

- (NSArray<NSDictionary *> *)powercuffRows
{
    return @[
        @{ @"kind": @"segmented", @"key": kSettingsPowercuffLevel,   @"title": @"Level" },
    ];
}

- (NSArray<NSDictionary *> *)otaRows
{
    return @[
        @{ @"kind": @"button", @"title": @"Disable OTA Updates" },
        @{ @"kind": @"button", @"title": @"Enable OTA Updates" },
    ];
}

- (NSArray<NSDictionary *> *)nanoRegistryRows
{
    return @[
        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMaxPairing,
           @"title": @"watchOS Pairing Limit",
           @"subtitle": @"Highest watchOS pairing generation this iPhone will accept. 99 raises the phone-side ceiling for newer watchOS releases.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMaxPairing) },

        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMinPairing,
           @"title": @"Setup Protocol Floor",
           @"subtitle": @"Lowest pairing setup generation this iPhone will accept. Keep this at 23 so generation-23 setup messages are not rejected.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMinPairing) },

        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMinPairingChipID,
           @"title": @"Legacy Chip Floor",
           @"subtitle": @"Leave this alone unless you are trying to pair an old S-chip watch, such as a Series 3.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMinPairingChipID) },

        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMinQuickSwitch,
           @"title": @"Multi-Watch Switching",
           @"subtitle": @"Leave this alone unless switching between multiple older paired watches is not working.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMinQuickSwitch) },

        @{ @"kind": @"button",
           @"title": @"Load Saved Override",
           @"action": @"nano-load" },

        @{ @"kind": @"button",
           @"title": @"Use watchOS Range 99/23/10/6",
           @"action": @"nano-preset-newer" },

        @{ @"kind": @"button",
           @"title": @"Apply Pairing Override",
           @"action": @"nano-apply" },

        @{ @"kind": @"button",
           @"title": @"Remove Override",
           @"action": @"nano-clear",
           @"destructive": @YES },
    ];
}

- (NSArray<NSDictionary *> *)darkSwordTweakRows
{
    return @[];
}

- (NSArray<NSDictionary *> *)dragCoefficientRows
{
    return @[
        @{ @"kind": @"number",
           @"key": kSettingsDSDragCoefficientValue,
           @"title": @"Coefficient",
           @"subtitle": @"1.00 = default, 0.50 = 2× faster, 0.25 = 4× faster. Minimum is 0.01.",
           @"min": @0.01, @"max": @2.0, @"step": @0.01,
           @"precision": @2, @"default": @0.5 },
    ];
}

- (NSArray<NSDictionary *> *)layoutExtrasRows
{
    return @[
        @{ @"kind": @"number", @"key": kSettingsLayoutHomeExtraLeft,
           @"title": @"Home extra left",   @"min": @0,  @"max": @300, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"number", @"key": kSettingsLayoutHomeExtraRight,
           @"title": @"Home extra right",  @"min": @0,  @"max": @300, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"number", @"key": kSettingsLayoutHomeExtraTop,
           @"title": @"Home extra top",    @"min": @0,  @"max": @400, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"number", @"key": kSettingsLayoutHomeExtraBottom,
           @"title": @"Home extra bottom", @"min": @0,  @"max": @400, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"number", @"key": kSettingsLayoutDockExtraHorizontal,
           @"title": @"Dock extra horizontal", @"min": @0,  @"max": @200, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"number", @"key": kSettingsLayoutHomeScalePct,
           @"title": @"Home icon scale",   @"min": @25, @"max": @250, @"step": @1, @"unit": @"%", @"default": @100 },
        @{ @"kind": @"number", @"key": kSettingsLayoutDockScalePct,
           @"title": @"Dock icon scale",   @"min": @25, @"max": @250, @"step": @1, @"unit": @"%", @"default": @100 },
    ];
}

- (NSArray<NSDictionary *> *)statbarRows
{
    return @[
        @{ @"kind": @"toggle", @"key": kSettingsStatBarCelsius,     @"title": @"Celsius" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowCPU,     @"title": @"Show CPU %" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowLabels,  @"title": @"Show CPU / RAM labels" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowNet,     @"title": @"Show network speed" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarNetworkOnly, @"title": @"Network speed only" },
        @{ @"kind": @"slider", @"key": kSettingsStatBarRefreshRateSec,
           @"title": @"Refresh rate", @"min": @(kStatBarDefaultRefreshRateSec), @"max": @30, @"step": @1,
           @"unit": @"s", @"default": @(kStatBarDefaultRefreshRateSec) },
    ];
}

- (NSArray<NSDictionary *> *)nsbarRows
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return @[
        @{ @"kind": @"info",
           @"title": @"Position",
           @"subtitle": settings_nsbar_position_name([d integerForKey:kSettingsNSBarPosition]) },
        @{ @"kind": @"button",
           @"title": @"Choose Position…",
           @"action": @"nsbar-position" },
    ];
}

- (NSArray<NSDictionary *> *)nicebarLiteRows
{
    return @[
        @{ @"kind": @"nicebar-grid" },
        @{ @"kind": @"info",
           @"title": @"Layout",
           @"subtitle": @"Top and bottom rows move separately. Changes update live while NiceBar Lite is running." },
        @{ @"kind": @"slider", @"key": kSettingsNiceBarLiteLayoutTopSideInset,
           @"title": @"Top side inset", @"min": @(-80), @"max": @80, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsNiceBarLiteLayoutBottomSideInset,
           @"title": @"Bottom side inset", @"min": @(-80), @"max": @80, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsNiceBarLiteLayoutTopY,
           @"title": @"Top Y offset", @"min": @(-40), @"max": @80, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsNiceBarLiteLayoutBottomY,
           @"title": @"Bottom Y offset", @"min": @(-40), @"max": @80, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsNiceBarLiteLayoutCenterX,
           @"title": @"Center X offset", @"min": @(-120), @"max": @120, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"toggle", @"key": kSettingsNiceBarLiteCelsius, @"title": @"Use Celsius" },
        @{ @"kind": @"button", @"title": @"Traffic History", @"action": @"nicebar-traffic-history" },
        @{ @"kind": @"button",
           @"title": @"Apply Now",
           @"action": @"nicebar-apply" },
    ];
}

- (NSArray<NSDictionary *> *)rssiRows
{
    return @[
        @{ @"kind": @"toggle", @"key": kSettingsRSSIDisplayWifi, @"title": @"WiFi (bar count)" },
        @{ @"kind": @"toggle", @"key": kSettingsRSSIDisplayCell, @"title": @"Cellular (dBm)" },
    ];
}

- (NSArray<NSDictionary *> *)axonLiteRows
{
    return @[];
}

- (NSArray<NSDictionary *> *)typebannerRows
{
    return @[
        @{ @"kind": @"button",
           @"title": @"Test: Poll Daemon & Show Banner",
           @"subtitle": @"Runs the live imagent detection path once. Banner shows the result; the [TYPEBANNER] log lines explain what was/wasn't found.",
           @"action": @"typebanner-test" },
    ];
}

- (NSArray<NSDictionary *> *)notificationIslandRows
{
    return @[
        @{ @"kind": @"button",
           @"title": @"Show Sample Island",
           @"subtitle": @"Starts the same ActivityKit route used for captured incoming notification banners.",
           @"action": @"notificationisland-sample" },
    ];
}

- (NSArray<NSDictionary *> *)gravityLiteRows
{
    return @[
        @{ @"kind": @"toggle",
           @"key": kSettingsGravityLiteDockEnabled,
           @"title": @"Include Dock" },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteMagnitudePct,
           @"title": @"Gravity strength",
           @"min": @25,
           @"max": @300,
           @"step": @5,
           @"unit": @"%",
           @"default": @100 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteBouncePct,
           @"title": @"Bounce",
           @"min": @0,
           @"max": @100,
           @"step": @5,
           @"unit": @"%",
           @"default": @50 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteFrictionPct,
           @"title": @"Friction",
           @"min": @0,
           @"max": @100,
           @"step": @5,
           @"unit": @"%",
           @"default": @50 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteResistancePct,
           @"title": @"Resistance",
           @"min": @0,
           @"max": @200,
           @"step": @5,
           @"unit": @"%",
           @"default": @50 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteAngularResistancePct,
           @"title": @"Spin resistance",
           @"min": @0,
           @"max": @200,
           @"step": @5,
           @"unit": @"%",
           @"default": @0 },
        @{ @"kind": @"button",
           @"title": @"Explosion Pulse",
           @"action": @"gravitylite-explosion" },
        @{ @"kind": @"button",
           @"title": @"Restore Icon Layout",
           @"action": @"gravitylite-restore",
           @"destructive": @YES },
    ];
}

- (NSArray<NSDictionary *> *)locationSimRows
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return @[
        @{ @"kind": @"info",
           @"title": @"Mode",
           @"subtitle": settings_location_sim_mode_summary(d) },

        @{ @"kind": @"button",
           @"title": @"Set Exact Coordinates…",
           @"action": @"locsim-set-exact" },

        @{ @"kind": @"button",
           @"title": @"Major Cities…",
           @"action": @"locsim-major-cities" },

        @{ @"kind": @"button",
           @"title": @"Simulate Rockaway Test Point",
           @"action": @"locsim-preset-rockaway" },

        @{ @"kind": @"slider",
           @"key": kSettingsLocationSimAltitude,
           @"title": @"Altitude",
           @"min": @(-100),
           @"max": @1000,
           @"step": @1,
           @"unit": @"m",
           @"default": @(kLocationSimDefaultAltitude) },

        @{ @"kind": @"slider",
           @"key": kSettingsLocationSimHorizontalAccuracy,
           @"title": @"Accuracy",
           @"min": @1,
           @"max": @100,
           @"step": @1,
           @"unit": @"m",
           @"default": @(kLocationSimDefaultAccuracy) },

        @{ @"kind": @"button",
           @"title": @"Simulate Current Target",
           @"action": @"locsim-apply" },

        @{ @"kind": @"button",
           @"title": @"Restore Real Location",
           @"subtitle": @"Reset can take a few minutes. If location still looks simulated, reboot and wait a little longer.",
           @"action": @"locsim-stop",
           @"destructive": @YES },
    ];
}

- (NSArray<NSDictionary *> *)ipaDecryptorRows
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *bundleID = [d stringForKey:kSettingsIPADecryptorTargetBundleID] ?: @"";
    NSString *appStoreInput = [d stringForKey:kSettingsIPADecryptorAppStoreInput] ?: @"";
    NSString *downloadedPath = [d stringForKey:kSettingsIPADecryptorDownloadedIPAPath] ?: @"";
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:@[
        @{ @"kind": @"info",
           @"title": @"App Store Account",
           @"subtitle": ipadecryptor_app_store_account_summary() },
        @{ @"kind": @"button",
           @"title": ipadecryptor_has_app_store_account()
                ? @"Sign In Again…"
                : @"Sign In to App Store…",
           @"subtitle": @"Required before Cyanide can request an authenticated IPA download ticket. 2FA is requested after Apple asks for it.",
           @"action": @"ipadec-signin" },
        @{ @"kind": @"info",
           @"title": @"Selected App",
           @"subtitle": settings_ipadecryptor_target_summary(d) },
        @{ @"kind": @"info",
           @"title": @"App Store Link",
           @"subtitle": settings_ipadecryptor_app_store_summary(d) },
        @{ @"kind": @"info",
           @"title": @"Download Status",
           @"subtitle": [d stringForKey:kSettingsIPADecryptorDownloadStatus] ?: @"Not started." },
        @{ @"kind": @"info",
           @"title": @"Output Folder",
           @"subtitle": ipadecryptor_default_output_directory().length > 0
                ? ipadecryptor_default_output_directory()
                : @"Cyanide Documents/DecryptedIPAs" },
        @{ @"kind": @"button",
           @"title": @"Choose Installed App…",
           @"action": @"ipadec-choose" },
        @{ @"kind": @"button",
           @"title": @"Paste App Store Link & Download…",
           @"subtitle": @"Resolves the link, then starts the IPA download path.",
           @"action": @"ipadec-paste-link" },
    ]];
    if (appStoreInput.length > 0) {
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Download IPA from App Store",
                           @"subtitle": @"Requests an authenticated download ticket, then fetches the encrypted IPA to Documents.",
                           @"action": @"ipadec-download" }];
    }
    if (ipadecryptor_has_app_store_account()) {
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Clear Saved App Store Token",
                           @"action": @"ipadec-clear-account",
                           @"destructive": @YES }];
    }
    if (downloadedPath.length > 0) {
        [rows addObject:@{ @"kind": @"info",
                           @"title": @"Downloaded IPA",
                           @"subtitle": downloadedPath }];
    }
    if (bundleID.length > 0) {
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Probe Target",
                           @"subtitle": @"Reads the app bundle and reports the main Mach-O FairPlay encryption command.",
                           @"action": @"ipadec-probe" }];
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Start Decrypt",
                           @"subtitle": @"Runs the in-dev pipeline. Dump and IPA writer stages are still being wired.",
                           @"action": @"ipadec-start" }];
    }
    return rows;
}

- (NSArray<NSDictionary *> *)themerRows
{
    BOOL hasSelection = settings_themer_has_selected_theme();
    NSString *selected = settings_themer_selected_theme_display_name();
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:@[
        @{ @"kind": @"info",
           @"title": @"Selected Theme",
           @"subtitle": hasSelection ? selected : @"None selected. Pick a theme before running the icon theme engine." },

        @{ @"kind": @"button",
           @"title": [selected isEqualToString:@"iOS 6 Theme"]
                ? @"iOS 6 Theme ✓" : @"Use iOS 6 Theme",
           @"action": @"themer-select-ios6" },

        @{ @"kind": @"button",
           @"title": @"Import Custom Theme…",
           @"action": @"themer-import" },

        @{ @"kind": @"button",
           @"title": @"Theme Format Guide",
           @"action": @"themer-guide" },
    ]];
    if (hasSelection) {
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Clear Selected Theme",
                           @"action": @"themer-clear",
                           @"destructive": @YES }];
    }
    return rows;
}

- (NSArray<NSDictionary *> *)snowboardLiteRows
{
    BOOL hasSelection = settings_snowboardlite_has_selected_theme();
    NSString *selected = settings_snowboardlite_selected_theme_display_name();
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:@[
        @{ @"kind": @"info",
           @"title": @"Selected Theme",
           @"subtitle": hasSelection ? selected : @"None selected. Pick or import a theme before running SnowBoard Lite." },
        @{ @"kind": @"button",
           @"title": [selected isEqualToString:@"iOS 6 Theme"] ? @"iOS 6 Theme ✓" : @"Use iOS 6 Theme",
           @"action": @"sbl-select-ios6" },
        @{ @"kind": @"button",
           @"title": @"Import Theme Folder…",
           @"action": @"sbl-import-folder" },
        @{ @"kind": @"button",
           @"title": @"Import Theme Archive (ZIP/DEB)…",
           @"action": @"sbl-import-archive" },
    ]];
    if (hasSelection) {
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Clear Selected Theme",
                           @"action": @"sbl-clear",
                           @"destructive": @YES }];
    }
    return rows;
}

- (NSArray<NSDictionary *> *)liveWPRows
{
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:@[
        @{ @"kind": @"info",
           @"title": @"Selected Video",
           @"subtitle": settings_livewp_video_detail() },
        @{ @"kind": @"button",
           @"title": @"Choose Video…",
           @"action": @"livewp-select-video" },
    ]];
    if ([[NSUserDefaults standardUserDefaults] stringForKey:kSettingsLiveWPVideoPath].length > 0) {
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Clear Selected Video",
                           @"action": @"livewp-clear",
                           @"destructive": @YES }];
    }
    return rows;
}

- (NSArray<NSDictionary *> *)appSwitcherGridRows
{
    BOOL applied = settings_tweak_is_applied(kSettingsAppSwitcherGridEnabled);
    return @[
        @{ @"kind": @"info",
           @"title": applied ? @"Current Style: Grid" : @"Current Style: Stock",
           @"subtitle": @"This is a runtime SpringBoard method patch. It does not write system files; respring restores the stock app switcher." },
        @{ @"kind": @"info",
           @"title": @"Session note",
           @"subtitle": @"If you respring after Hide Home Bar, run App Switcher Grid again because respring resets this live SpringBoard patch." },
        @{ @"kind": @"button",
           @"title": @"Restore Stock Switcher",
           @"subtitle": @"Restores the original switcher style in the active SpringBoard session when available.",
           @"action": @"appswitchergrid-restore",
           @"destructive": @YES },
    ];
}

- (NSArray<NSDictionary *> *)fastLockXLiteRows
{
    return @[
        @{ @"kind": @"info",
           @"title": @"FastLockX Lite",
           @"subtitle": @"Always On keeps the Face ID retry pulse and unlock request armed in SpringBoard until Disable, Clean Up, or respring." },
        @{ @"kind": @"button",
           @"title": @"Enable Always On",
           @"subtitle": @"Keeps pickup-to-unlock armed after Cyanide closes.",
           @"action": @"fastlockx-enable" },
        @{ @"kind": @"button",
           @"title": @"Disable",
           @"subtitle": @"Stops the SpringBoard timers.",
           @"action": @"fastlockx-disable" },
        @{ @"kind": @"number",
           @"key": kSettingsFastLockXLiteRetryInterval,
           @"title": @"Retry interval",
           @"subtitle": @"Always On uses this as the off→on pulse gap. Default 0.3s.",
           @"min": @0.1, @"max": @2.0, @"step": @0.1, @"unit": @"s", @"precision": @1, @"default": @0.3 },
        @{ @"key": kSettingsFastLockXLiteBlockMusic,
           @"title": @"Block if media is active — In progress",
           @"subtitle": @"In progress — not wired yet. This blocker is disabled for now.",
           @"disabled": @YES },
        @{ @"key": kSettingsFastLockXLiteBlockFlashlight,
           @"title": @"Block if flashlight is on — In progress",
           @"subtitle": @"In progress — not wired yet. This blocker is disabled for now.",
           @"disabled": @YES },
        @{ @"key": kSettingsFastLockXLiteBlockLowPower,
           @"title": @"Block in Low Power Mode — In progress",
           @"subtitle": @"In progress — not wired yet. This blocker is disabled for now.",
           @"disabled": @YES },
    ];
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)settingsSummaryForSection:(NSInteger)section
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSMutableArray *out = [NSMutableArray array];
    if (section == SectionSBC) {
        [out addObject:@{@"title": @"Dock icons",       @"value": [@([d integerForKey:kSettingsSBCDockIcons])  stringValue]}];
        [out addObject:@{@"title": @"Home columns",     @"value": [@([d integerForKey:kSettingsSBCCols])        stringValue]}];
        [out addObject:@{@"title": @"Home rows",        @"value": [@([d integerForKey:kSettingsSBCRows])        stringValue]}];
        [out addObject:@{@"title": @"Hide icon labels", @"value": [d boolForKey:kSettingsSBCHideLabels] ? @"On" : @"Off"}];
    } else if (section == SectionLayoutExtras) {
        [out addObject:@{@"title": @"Home extra L/R",   @"value": [NSString stringWithFormat:@"%ld/%ld",
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraLeft],
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraRight]]}];
        [out addObject:@{@"title": @"Home extra T/B",   @"value": [NSString stringWithFormat:@"%ld/%ld",
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraTop],
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraBottom]]}];
        [out addObject:@{@"title": @"Dock extra H",     @"value": [@([d integerForKey:kSettingsLayoutDockExtraHorizontal]) stringValue]}];
        [out addObject:@{@"title": @"Home scale %",     @"value": [@([d integerForKey:kSettingsLayoutHomeScalePct]) stringValue]}];
        [out addObject:@{@"title": @"Dock scale %",     @"value": [@([d integerForKey:kSettingsLayoutDockScalePct]) stringValue]}];
    } else if (section == SectionStatBar) {
        [out addObject:@{@"title": @"Celsius",             @"value": [d boolForKey:kSettingsStatBarCelsius]    ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Show CPU %",          @"value": [d boolForKey:kSettingsStatBarShowCPU]    ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Show CPU/RAM labels", @"value": [d boolForKey:kSettingsStatBarShowLabels] ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Show net speed",      @"value": [d boolForKey:kSettingsStatBarShowNet]    ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Network speed only",  @"value": [d boolForKey:kSettingsStatBarNetworkOnly] ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Refresh rate",        @"value": [NSString stringWithFormat:@"%lds",
                                                                       (long)[d integerForKey:kSettingsStatBarRefreshRateSec]]}];
    } else if (section == SectionNSBar) {
        [out addObject:@{@"title": @"Position", @"value": settings_nsbar_position_name([d integerForKey:kSettingsNSBarPosition])}];
    } else if (section == SectionNiceBarLite) {
        for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
            NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
            [out addObject:@{@"title": settings_nicebar_slot_name(i),
                             @"value": settings_nicebar_kind_name(kind)}];
        }
    } else if (section == SectionRSSI) {
        [out addObject:@{@"title": @"WiFi (bar count)", @"value": [d boolForKey:kSettingsRSSIDisplayWifi] ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Cellular (dBm)",   @"value": [d boolForKey:kSettingsRSSIDisplayCell] ? @"On" : @"Off"}];
    } else if (section == SectionAppSwitcherGrid) {
        [out addObject:@{@"title": @"Switcher style",
                         @"value": settings_tweak_is_applied(kSettingsAppSwitcherGridEnabled) ? @"Grid" : @"Stock"}];
    } else if (section == SectionFastLockXLite) {
        BOOL alwaysOnIntent = [d boolForKey:kSettingsFastLockXLiteEnabled];
        BOOL alwaysOnApplied = settings_tweak_is_applied(kSettingsFastLockXLiteEnabled);
        [out addObject:@{@"title": @"Always On",
                         @"value": alwaysOnApplied ? @"Enabled" : (alwaysOnIntent ? @"Unknown" : @"Off")}];
        [out addObject:@{@"title": @"Retry interval",
                         @"value": [NSString stringWithFormat:@"%.1fs", settings_fastlockx_lite_retry_interval(d)]}];
        [out addObject:@{@"title": @"Blockers",
                         @"value": @"In progress"}];
    } else if (section == SectionPowercuff) {
        NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal";
        [out addObject:@{@"title": @"Level", @"value": lvl}];
    } else if (section == SectionDragCoefficient) {
        double v = settings_drag_coefficient_value(d);
        [out addObject:@{@"title": @"Coefficient", @"value": [NSString stringWithFormat:@"%.2f", v]}];
    } else if (section == SectionNanoRegistry) {
        [out addObject:@{@"title": @"watchOS limit",      @"value": [@([d integerForKey:kSettingsNanoMaxPairing])       stringValue]}];
        [out addObject:@{@"title": @"Setup floor",        @"value": [@([d integerForKey:kSettingsNanoMinPairing])       stringValue]}];
        [out addObject:@{@"title": @"Legacy chip floor",  @"value": [@([d integerForKey:kSettingsNanoMinPairingChipID]) stringValue]}];
        [out addObject:@{@"title": @"Multi-watch switch", @"value": [@([d integerForKey:kSettingsNanoMinQuickSwitch])   stringValue]}];
    } else if (section == SectionThemer) {
        [out addObject:@{@"title": @"Theme", @"value": settings_themer_selected_theme_display_name()}];
    } else if (section == SectionSnowBoardLite) {
        [out addObject:@{@"title": @"Theme", @"value": settings_snowboardlite_selected_theme_display_name()}];
    } else if (section == SectionLiveWP) {
        [out addObject:@{@"title": @"Video", @"value": settings_livewp_video_detail()}];
    } else if (section == SectionLocationSim) {
        [out addObject:@{@"title": @"Target", @"value": settings_location_sim_target_summary(d)}];
    } else if (section == SectionIPADecryptor) {
        [out addObject:@{@"title": @"Target", @"value": settings_ipadecryptor_target_summary(d)}];
        [out addObject:@{@"title": @"App Store", @"value": settings_ipadecryptor_app_store_summary(d)}];
    } else if (section == SectionGravityLite) {
        [out addObject:@{@"title": @"Dock",         @"value": [d boolForKey:kSettingsGravityLiteDockEnabled] ? @"Included" : @"Home only"}];
        [out addObject:@{@"title": @"Strength",     @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteMagnitudePct]]}];
        [out addObject:@{@"title": @"Bounce",       @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteBouncePct]]}];
        [out addObject:@{@"title": @"Friction",     @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteFrictionPct]]}];
        [out addObject:@{@"title": @"Resistance",   @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteResistancePct]]}];
        [out addObject:@{@"title": @"Spin resist.", @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteAngularResistancePct]]}];
    }
    return out;
}

- (NSArray<NSDictionary *> *)rowsForSection:(NSInteger)s
{
    switch (s) {
        case SectionLaunch:    return self.launchRows;
        case SectionSBC:       return self.sbcRows;
        case SectionDarkSwordTweaks: return self.darkSwordTweakRows;
        case SectionDragCoefficient: return self.dragCoefficientRows;
        case SectionLayoutExtras: return self.layoutExtrasRows;
        case SectionOTA:       return self.otaRows;
        case SectionNanoRegistry: return self.nanoRegistryRows;
        case SectionThemer:  return self.themerRows;
        case SectionPowercuff: return self.powercuffRows;
        case SectionStatBar:   return self.statbarRows;
        case SectionNSBar:     return self.nsbarRows;
        case SectionNiceBarLite: return self.nicebarLiteRows;
        case SectionRSSI:      return self.rssiRows;
        case SectionAxonLite:  return self.axonLiteRows;
        case SectionTypeBanner: return self.typebannerRows;
        case SectionNotificationIsland: return self.notificationIslandRows;
        case SectionAppSwitcherGrid: return self.appSwitcherGridRows;
        case SectionFastLockXLite: return settings_fastlockx_lite_install_allowed() ? self.fastLockXLiteRows : @[];
        case SectionGravityLite: return self.gravityLiteRows;
        case SectionLocationSim: return self.locationSimRows;
        case SectionIPADecryptor: return self.ipaDecryptorRows;
        case SectionSnowBoardLite: return self.snowboardLiteRows;
        case SectionLiveWP: return self.liveWPRows;
        default: return @[];
    }
}

#pragma mark - Bundle rows (root mode)

// Bundles whose underlying section has zero configuration rows are filtered
// out — install/uninstall is the only operation those tweaks expose, and
// that's already in the Installer tab.

- (NSArray<NSDictionary *> *)allTweakBundleRows
{
    return @[
        @{ @"title": @"Launch Options",     @"icon": @"bolt.fill",                          @"color": [UIColor systemRedColor],    @"section": @(SectionLaunch) },
        @{ @"title": @"SBCustomizer",       @"icon": @"square.grid.3x3.fill",                @"color": [UIColor systemBlueColor],   @"section": @(SectionSBC) },
        @{ @"title": @"StatBar",            @"icon": @"thermometer.medium",                  @"color": [UIColor systemRedColor],    @"section": @(SectionStatBar) },
        @{ @"title": @"NSBar",              @"icon": @"network",                             @"color": [UIColor systemBlueColor],   @"section": @(SectionNSBar) },
        @{ @"title": @"NiceBar Lite",       @"icon": @"textformat.size",                     @"color": [UIColor systemTealColor],   @"section": @(SectionNiceBarLite) },
#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
        @{ @"title": @"Signal Display",     @"icon": @"antenna.radiowaves.left.and.right",   @"color": [UIColor systemBlueColor],   @"section": @(SectionRSSI), @"indev": @YES },
#endif
        @{ @"title": @"Axon Lite",          @"icon": @"bell.badge.fill",                     @"color": [UIColor systemRedColor],    @"section": @(SectionAxonLite) },
#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
        @{ @"title": @"TypeBanner",         @"icon": @"ellipsis.bubble.fill",                @"color": [UIColor systemTealColor],   @"section": @(SectionTypeBanner), @"indev": @YES },
        @{ @"title": @"Notification Island", @"icon": @"bell.and.waves.left.and.right.fill",  @"color": [UIColor systemOrangeColor], @"section": @(SectionNotificationIsland), @"indev": @YES },
        @{ @"title": @"IPA Decryptor",      @"icon": @"lock.open.fill",                      @"color": [UIColor systemPurpleColor], @"section": @(SectionIPADecryptor), @"indev": @YES },
        @{ @"title": @"FastLockX Lite",     @"icon": @"lock.open.fill",                      @"color": [UIColor systemGreenColor],  @"section": @(SectionFastLockXLite), @"experimental": @YES },
#endif
        @{ @"title": @"Gravity Lite",       @"icon": @"arrow.down.circle.fill",              @"color": [UIColor systemGreenColor],  @"section": @(SectionGravityLite) },
        @{ @"title": @"App Switcher Grid",  @"icon": @"square.grid.2x2.fill",                @"color": [UIColor systemOrangeColor], @"section": @(SectionAppSwitcherGrid) },
        @{ @"title": @"Location Simulator", @"icon": @"location.fill",                       @"color": [UIColor systemGreenColor],  @"section": @(SectionLocationSim) },
        @{ @"title": @"SnowBoard Lite",     @"icon": @"square.stack.3d.up.fill",             @"color": [UIColor systemCyanColor],   @"section": @(SectionSnowBoardLite) },
        @{ @"title": @"LiveWP",             @"icon": @"play.rectangle.fill",                 @"color": [UIColor systemPurpleColor], @"section": @(SectionLiveWP) },
        @{ @"title": @"Powercuff",          @"icon": @"bolt.slash.fill",                     @"color": [UIColor systemOrangeColor], @"section": @(SectionPowercuff) },
        @{ @"title": @"SpringBoard Tweaks", @"icon": @"apps.iphone",                         @"color": [UIColor systemIndigoColor], @"section": @(SectionDarkSwordTweaks) },
        @{ @"title": @"Drag Coefficient",   @"icon": @"dial.medium.fill",                    @"color": [UIColor systemIndigoColor], @"section": @(SectionDragCoefficient) },
        @{ @"title": @"Home Layout Extras", @"icon": @"square.dashed.inset.filled",          @"color": [UIColor systemPurpleColor], @"section": @(SectionLayoutExtras) },
    ];
}

- (NSArray<NSDictionary *> *)allSystemBundleRows
{
    return @[
        @{ @"title": @"OTA Updates",       @"icon": @"icloud.slash.fill",    @"color": [UIColor systemGrayColor],   @"section": @(SectionOTA) },
        @{ @"title": @"Watch Pairing",     @"icon": @"applewatch.radiowaves.left.and.right", @"color": [UIColor systemPurpleColor], @"section": @(SectionNanoRegistry) },
    ];
}

- (NSArray<NSDictionary *> *)filterBundles:(NSArray<NSDictionary *> *)bundles
{
    BOOL experimentalOn = settings_experimental_tweaks_enabled();
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *bundle in bundles) {
        if ([bundle[@"indev"] boolValue]) continue;
        if ([bundle[@"experimental"] boolValue] && !experimentalOn) continue;
        NSInteger sec = [bundle[@"section"] integerValue];
        if ([self rowsForSection:sec].count > 0) {
            [out addObject:bundle];
        }
    }
    return out;
}

- (NSArray<NSDictionary *> *)inDevBundleRows
{
    BOOL experimentalOn = settings_experimental_tweaks_enabled();
    if (!experimentalOn) return @[];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *bundle in [self allTweakBundleRows]) {
        if (![bundle[@"indev"] boolValue]) continue;
        NSInteger sec = [bundle[@"section"] integerValue];
        if ([self rowsForSection:sec].count > 0) {
            [out addObject:bundle];
        }
    }
    return out;
}

- (NSArray<NSDictionary *> *)tweakBundleRows
{
    return [self filterBundles:[self allTweakBundleRows]];
}

- (NSArray<NSDictionary *> *)systemBundleRows
{
    return [self filterBundles:[self allSystemBundleRows]];
}

- (NSArray<NSDictionary *> *)bundleRowsForRootSection:(RootSection)section
{
    if (section == RootSectionTweakBundles)  return self.tweakBundleRows;
    if (section == RootSectionInDev)        return self.inDevBundleRows;
    if (section == RootSectionSystemBundles) return self.systemBundleRows;
    return @[];
}

#pragma mark - Table data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.detailMode ? 1 : RootSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.detailMode) {
        return (NSInteger)[self rowsForSection:self.underlyingSection].count;
    }
    switch ((RootSection)section) {
        case RootSectionChangelog: {
            NSInteger n = (NSInteger)settings_changelog_entries().count;
            if (n == 0) return 0;
            return self.changelogExpanded ? n + 2 : 1;
        }
        case RootSectionActions:        return 4;
        case RootSectionTweakBundles:   return (NSInteger)self.tweakBundleRows.count;
        case RootSectionInDev:         return (NSInteger)self.inDevBundleRows.count;
        case RootSectionSystemBundles:  return (NSInteger)self.systemBundleRows.count;
        case RootSectionPatreon: {
            // Unlinked users get two rows: "Link" (for people who already have
            // a Patreon account) and "New to Patreon? Sign Up" (jumps to the
            // creator page so they can join in Safari first). Without the
            // sign-up affordance, a first-time user has no obvious way to
            // discover that they need a Patreon account to begin with.
            if (!cyanide_patreon_is_linked()) return 2;
            // Linked-but-not-pledging gets an extra "Join Member Tier" row
            // so users have an obvious in-app path to upgrade.
            return cyanide_is_patron() ? 3 : 4;
        }
        case RootSectionExperimental:   return 1;
        case RootSectionAbout:          return 6;
        case RootSectionWarning:        return 0;
        case RootSectionCount:          return 0;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.detailMode) return nil;
    switch ((RootSection)section) {
        case RootSectionChangelog:      return self.changelogExpanded ? @"What's New" : nil;
        case RootSectionActions:        return @"Quick Actions";
        case RootSectionTweakBundles:   return self.tweakBundleRows.count   > 0 ? @"Tweaks" : nil;
        case RootSectionInDev:         return self.inDevBundleRows.count   > 0 ? @"In Development" : nil;
        case RootSectionSystemBundles:  return self.systemBundleRows.count  > 0 ? @"System" : nil;
        case RootSectionPatreon:        return @"Patreon";
        case RootSectionExperimental:   return @"Experimental";
        case RootSectionAbout:          return @"About";
        default:                        return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (!self.detailMode) {
        if ((RootSection)section == RootSectionExperimental) {
            if (!settings_experimental_access_allowed()) {
                return @"Early-access for Member tier Patreon supporters.";
            }
            return nil;
        }
        if ((RootSection)section == RootSectionPatreon) {
            if (!cyanide_patreon_is_linked()) {
                return @"Cyanide is free. Patreon supporters get early access "
                       @"to experimental tweaks. Auth happens in-app.";
            }
            NSDate *last = cyanide_patreon_last_refresh_date();
            if (last) {
                NSDateFormatter *df = [[NSDateFormatter alloc] init];
                df.dateStyle = NSDateFormatterMediumStyle;
                df.timeStyle = NSDateFormatterShortStyle;
                return [NSString stringWithFormat:@"Last checked %@", [df stringFromDate:last]];
            }
            return nil;
        }
        return nil;
    }
    NSInteger s = self.underlyingSection;
    if (s == SectionLaunch) {
        return @"kexploit_opa334 runs once per app lifetime. Keep Alive applies only while Cyanide is minimized; an App Switcher kill still terminates the process.";
    }
    if (s == SectionSBC) {
        return [NSString stringWithFormat:@"Stock iOS defaults: dock %ld, columns %ld, rows %ld.",
                (long)kSBCDefaultDockIcons, (long)kSBCDefaultCols, (long)kSBCDefaultRows];
    }
    if (s == SectionDarkSwordTweaks) {
        return @"Imported from DarkSword-Tweaks. These are SpringBoard runtime patches; turning one off only skips future applies.";
    }
    if (s == SectionDragCoefficient) {
        return @"Overrides _UIAnimationDragCoefficient in SpringBoard. Type the raw coefficient: 1.00 = stock, 0.50 = 2× faster, 0.25 = 4× faster, minimum 0.01. Imported from kolbicz/DarkSword-Tweaks.";
    }
    if (s == SectionLayoutExtras) {
        NSInteger major = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        if (major >= 26) {
            return [NSString stringWithFormat:
                @"Adds extra padding and per-icon scaling on top of the stock home/dock layout.\n\n"
                @"Running on iOS %ld: the upstream config-mutation path doesn't exist (AMUIInfographIconListLayout has no mutable configuration), so the iOS 26 path instead walks the live SBIconListView/SBIconView hierarchy and adjusts frames + iconImageInfo directly. One-shot at Run; iOS 26 may re-fit on a subsequent layout pass (rotation, page swipe).",
                (long)major];
        }
        return @"Adds extra padding and per-icon scaling on top of the stock home/dock layout. Defaults are zero padding and 100% scale (no change). Toggle Enable on and hit Run to apply; values aren't persisted across respring.";
    }
    if (s == SectionOTA) {
        return @"Edits launchd disabled.plist. A reboot or userspace restart is required for changes to take effect.";
    }
    if (s == SectionNanoRegistry) {
        return @"Changes the watchOS pairing range saved on this iPhone.\n\n"
               @"Most people should tap Use watchOS Range 99/23/10/6, then Apply Pairing Override. "
               @"These are pairing protocol generations, not Apple Watch model numbers. "
               @"99 raises the watchOS pairing ceiling. 23 keeps the generation-23 setup protocol accepted. "
               @"10 and 6 leave the legacy chip and multi-watch floors at their normal values.\n\n"
               @"Apple Watch Ultra 3 cannot pair on iOS versions below 26 at this time.\n\n"
               @"Respring or reboot after applying before you try to pair.";
    }
    if (s == SectionPowercuff) {
        return @"Underclocks the CPU/GPU via thermalmonitord by simulating thermal pressure. Nominal is the daily-use default. Light, Moderate, and Heavy intentionally underclock the CPU more and can make the device feel laggy, especially on older hardware.";
    }
    if (s == SectionStatBar) {
        return @"Live overlay. When enabled, StatBar keeps a SpringBoard RemoteCall session open. Refresh rate controls live updates while the screen is awake; StatBar pauses while the screen is locked or asleep.";
    }
    if (s == SectionNSBar) {
        return @"Network speed overlay ported from d1y/cyanide-ios. When enabled, NSBar keeps a SpringBoard RemoteCall session open and refreshes roughly once per second.";
    }
    if (s == SectionNiceBarLite) {
        return @"Tap a box to choose what it shows. NiceBar Lite places plain text in the configured status-bar slots around the notch or Dynamic Island, including the bottom center position. Weather is fetched from your current location through Open-Meteo and follows the Celsius toggle.";
    }
    if (s == SectionRSSI) {
        return @"Adds a UILabel as a sibling of each STUI signal view (no new UIWindow), refreshed every second. Cellular shows live RSRP dBm (sign implicit). WiFi shows the bar count (0-4); the wifid XPC dBm path crashed SpringBoard in prior tests.";
    }
    if (s == SectionAxonLite) {
        return @"RemoteCall-only Axon port. It uses a live app-side loop rather than substrate hooks, so it lasts for the active Cyanide SpringBoard session.";
    }
    if (s == SectionTypeBanner) {
        return @"Partial TypeMillennium port. Detection runs against imagent using original-thread RemoteCall probes, while SpringBoard renders a prewarmed banner window.";
    }
    if (s == SectionNotificationIsland) {
        return @"Experimental Dynamic Island notification route. Cyanide polls SpringBoard's active banner request through the shared RemoteCall session, then mirrors it through the app's ActivityKit Live Activity.";
    }
    if (s == SectionAppSwitcherGrid) {
        return @"Runtime patch. It changes SpringBoard's app switcher style in memory, writes no system files, and a respring restores stock. Unsupported builds may glitch the app switcher or crash SpringBoard.";
    }
    if (s == SectionGravityLite) {
        return @"RemoteCall-only core port of Julio Verne's Gravity. Run applies UIDynamicAnimator gravity, collision, bounce, friction, optional dock physics, and accelerometer steering to SpringBoard icon snapshots. It can restore the icon layout or fire a manual explosion pulse while the SpringBoard session is active.\n\nNot included in this core port: Activator/Home-button hooks, drag gestures, automatic shake effects, and preference-daemon notifications.";
    }
    if (s == SectionLocationSim) {
        return @"Beta CoreLocation simulation. Requires Apple Maps installed and set up — Maps is the RemoteCall host process that drives the simulation.\n\nThis is a manual tool, not an installable package. Use Simulate Current Target to start; use Restore Real Location to stop simulation and return CoreLocation to the device's real providers. Each run opens the activity log and marks completion when the request returns.\n\nNot all apps respect the simulated location. Apps that use their own location validation or additional signals may ignore it.\n\nCredits: kolbicz for the RemoteCall/CLSimulationManager GPS spoofer prototype, and ezzuldinSt's LSpoof for picker/route references.\n\nWarning: this can affect more than maps. Location-tied system behavior, including time zone and date/time handling, may behave unexpectedly. Only use this if you know what you're doing.";
    }
    if (s == SectionIPADecryptor) {
        return @"In-development local IPA decryptor. Current build discovers installed user apps, resolves pasted App Store links to bundle IDs, signs in for an App Store download token, and fetches the encrypted IPA to Documents. The fetched IPA still needs SINF/iTunesMetadata patching plus the KRW dump/rebuild stage before it becomes a decrypted IPA.";
    }
    if (s == SectionThemer) {
        return @"Legacy icon theme engine settings.\n\n"
               @"Pick a theme before running the icon theme engine.\n\n"
               @"Compatibility: when Dynamic Stage Lite is enabled, live icon repair is paused to avoid SpringBoard resprings. The selected theme still applies once.\n\n"
               @"Custom themes can be a folder of PNG files named by bundle ID, such as com.apple.mobilesafari.png, or a binary plist mapping bundle IDs to PNG data. Import copies the theme into Cyanide's Documents/Themes folder. Theme Format Guide includes examples and plist exports.";
    }
    if (s == SectionSnowBoardLite) {
        return @"SnowBoard/IconBundles importer ported from d1y/cyanide-ios. Folder imports are copied into Cyanide's Documents/SnowBoardLite library and applied through the existing icon replacement pipeline.\n\nThe import copies theme assets into Cyanide's local storage so the original theme in Files is not changed.\n\nCompatibility: when Dynamic Stage Lite is enabled, live icon repair is paused to avoid SpringBoard resprings. The selected theme still applies once.";
    }
    if (s == SectionLiveWP) {
        return @"Video wallpaper ported from d1y/cyanide-ios. Select an MP4, MOV, or M4V; Cyanide copies it into Documents/LiveWP and plays it in SpringBoard while the RemoteCall session stays alive.";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (!self.detailMode) {
        if ((RootSection)section == RootSectionWarning) return CGFLOAT_MIN;
        if ((RootSection)section == RootSectionChangelog     && settings_changelog_entries().count == 0) return CGFLOAT_MIN;
        if ((RootSection)section == RootSectionTweakBundles  && self.tweakBundleRows.count  == 0) return CGFLOAT_MIN;
        if ((RootSection)section == RootSectionInDev        && self.inDevBundleRows.count  == 0) return CGFLOAT_MIN;
        if ((RootSection)section == RootSectionSystemBundles && self.systemBundleRows.count == 0) return CGFLOAT_MIN;
    }
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if ([self tableView:tableView titleForFooterInSection:section].length > 0)
        return UITableViewAutomaticDimension;
    return 6.0;
}

#pragma mark - Icon badge

+ (UIImage *)iconBadgeWithSymbol:(NSString *)symbol color:(UIColor *)color size:(CGFloat)size
{
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat radius = size * (7.0 / 29.0);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:radius];
        [color setFill];
        [path fill];

        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.58 weight:UIImageSymbolWeightSemibold];
        UIImage *symbolImage = [UIImage systemImageNamed:symbol withConfiguration:cfg];
        if (symbolImage) {
            UIImage *whiteIcon = [symbolImage imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            CGFloat x = (size - whiteIcon.size.width) / 2.0;
            CGFloat y = (size - whiteIcon.size.height) / 2.0;
            [whiteIcon drawAtPoint:CGPointMake(x, y)];
        }
    }];
}

#pragma mark - Cells

- (UITableViewCell *)buildBundleCellWithRow:(NSDictionary *)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bundle"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bundle"];
    }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:row[@"icon"] color:row[@"color"] size:29.0];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)buildInDevCellWithRow:(NSDictionary *)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"indev"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"indev"];
    }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:row[@"icon"] color:[UIColor systemGrayColor] size:29.0];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.tertiaryLabelColor;
    cell.detailTextLabel.text = @"In Development";
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.detailTextLabel.textColor = UIColor.tertiaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.userInteractionEnabled = NO;
    return cell;
}

- (UITableViewCell *)buildChangelogCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    NSArray<NSDictionary *> *entries = settings_changelog_entries();
    NSDictionary *entry = (row >= 0 && row < (NSInteger)entries.count) ? entries[row] : nil;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"changelog-entry"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"changelog-entry"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    cell.textLabel.text = nil;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    NSString *version = entry[@"version"] ?: @"";
    NSString *date    = settings_pretty_date_for_iso(entry[@"date"]);

    // Version pill
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.text = [NSString stringWithFormat:@" v%@ ", version];
    versionLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    versionLabel.textColor = UIColor.systemBlueColor;
    versionLabel.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.12];
    versionLabel.layer.cornerRadius = 4.0;
    versionLabel.layer.masksToBounds = YES;
    versionLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *dateLabel = [[UILabel alloc] init];
    dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    dateLabel.text = date;
    dateLabel.font = [UIFont systemFontOfSize:13.0];
    dateLabel.textColor = UIColor.tertiaryLabelColor;

    // Build bullet list with hanging indent
    NSArray *changes = entry[@"changes"];
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:changes.count];
    for (id c in changes) {
        if (![c isKindOfClass:[NSString class]]) continue;
        [lines addObject:(NSString *)c];
    }

    NSMutableParagraphStyle *bulletStyle = [[NSMutableParagraphStyle alloc] init];
    bulletStyle.headIndent = 14.0;
    bulletStyle.firstLineHeadIndent = 0.0;
    bulletStyle.paragraphSpacing = 4.0;
    bulletStyle.lineBreakMode = NSLineBreakByWordWrapping;

    NSDictionary *bulletAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: bulletStyle,
    };
    NSDictionary *dotAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: UIColor.tertiaryLabelColor,
        NSParagraphStyleAttributeName: bulletStyle,
    };

    NSMutableAttributedString *body = [[NSMutableAttributedString alloc] init];
    for (NSUInteger i = 0; i < lines.count; i++) {
        if (i > 0) [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"›  " attributes:dotAttrs]];
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:lines[i] attributes:bulletAttrs]];
    }

    UILabel *bodyLabel = [[UILabel alloc] init];
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bodyLabel.attributedText = body;
    bodyLabel.numberOfLines = 0;

    [cell.contentView addSubview:versionLabel];
    [cell.contentView addSubview:dateLabel];
    [cell.contentView addSubview:bodyLabel];

    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [versionLabel.leadingAnchor  constraintEqualToAnchor:m.leadingAnchor],
        [versionLabel.topAnchor      constraintEqualToAnchor:m.topAnchor],
        [dateLabel.leadingAnchor     constraintEqualToAnchor:versionLabel.trailingAnchor constant:8],
        [dateLabel.centerYAnchor     constraintEqualToAnchor:versionLabel.centerYAnchor],
        [bodyLabel.leadingAnchor     constraintEqualToAnchor:m.leadingAnchor],
        [bodyLabel.trailingAnchor    constraintEqualToAnchor:m.trailingAnchor],
        [bodyLabel.topAnchor         constraintEqualToAnchor:versionLabel.bottomAnchor constant:8],
        [bodyLabel.bottomAnchor      constraintEqualToAnchor:m.bottomAnchor],
    ]];

    return cell;
}

- (UITableViewCell *)buildChangelogFooterCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"changelog-footer"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"changelog-footer"];
    }
    cell.imageView.image = nil;
    cell.textLabel.text = @"See all releases on GitHub";
    cell.textLabel.font = [UIFont systemFontOfSize:15.0];
    cell.textLabel.textColor = self.view.tintColor;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)buildChangelogCollapsedCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"changelog-collapsed"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"changelog-collapsed"];
    }
    NSArray<NSDictionary *> *entries = settings_changelog_entries();
    NSDictionary *first = entries.firstObject;
    NSString *version = first[@"version"] ?: @"";
    NSInteger count = 0;
    for (id c in first[@"changes"]) { if ([c isKindOfClass:[NSString class]]) count++; }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"sparkles" color:UIColor.systemYellowColor size:29.0];
    cell.textLabel.text = [NSString stringWithFormat:@"What's New in v%@", version];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld change%@", (long)count, count == 1 ? @"" : @"s"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)buildChangelogCollapseCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"changelog-collapse"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"changelog-collapse"];
    }
    cell.imageView.image = nil;
    cell.textLabel.text = @"Show Less";
    cell.textLabel.font = [UIFont systemFontOfSize:15.0];
    cell.textLabel.textColor = self.view.tintColor;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)openReleasesPage
{
    NSURL *url = [NSURL URLWithString:@"https://github.com/zeroxjf/cyanide/releases"];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (UITableViewCell *)buildDocsCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"docs"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"docs"];
    }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"book.closed.fill" color:UIColor.systemPurpleColor size:29.0];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.text = @"Tweak SDK";
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = @"How to write Cyanide tweaks";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)buildAboutCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"about"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"about"];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = nil;

    switch (row) {
        case 0:
            cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"at" color:UIColor.systemBlueColor size:29.0];
            cell.textLabel.text = @"Twitter";
            cell.detailTextLabel.text = @"@zeroxjf";
            break;
        case 1:
            cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"book.closed.fill" color:UIColor.systemPurpleColor size:29.0];
            cell.textLabel.text = @"Tweak SDK";
            break;
        case 2:
            cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"app.fill" color:UIColor.systemTealColor size:29.0];
            cell.textLabel.text = @"App Icon";
            cell.detailTextLabel.text = [[self currentAppIconStyle] isEqualToString:@"classic"] ? @"Classic" : @"Modern";
            break;
        case 3:
            cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"doc.text.magnifyingglass" color:UIColor.systemGrayColor size:29.0];
            cell.textLabel.text = @"View Log";
            break;
        case 4:
            cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"square.and.arrow.up" color:UIColor.systemGreenColor size:29.0];
            cell.textLabel.text = @"Share Log";
            break;
        default:
            cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"icloud.and.arrow.up" color:UIColor.systemIndigoColor size:29.0];
            cell.textLabel.text = @"Auto-Upload Logs";
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsLogUploadEnabled];
            [sw addTarget:self action:@selector(logUploadSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            break;
    }
    return cell;
}

- (void)logUploadSwitchChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:kSettingsLogUploadEnabled];
}

- (void)reloadThemerSectionAndQueue
{
    settings_mark_tweak_applied(kSettingsThemerEnabled, NO);
    settings_notify_package_queue_changed_async();
    if (self.detailMode && self.underlyingSection == SectionThemer) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView reloadData];
    }
}

- (void)selectBuiltInIOS6Theme
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeBuiltinIOS6 forKey:kSettingsThemerThemeID];
    [d synchronize];
    log_user("[THEMER] Selected iOS 6 Theme.\n");
    [self reloadThemerSectionAndQueue];
}

- (void)clearSelectedTheme
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeNone forKey:kSettingsThemerThemeID];
    [d setObject:@"" forKey:kSettingsThemerCustomThemePath];
    [d setObject:@"" forKey:kSettingsThemerCustomThemeName];
    if ([d boolForKey:kSettingsThemerEnabled]) {
        [d setBool:NO forKey:kSettingsThemerEnabled];
        g_themer_live_stop_requested = 1;
    }
    [d synchronize];
    log_user("[THEMER] Cleared selected theme; the icon theme engine is no longer pending activation.\n");
    [self reloadThemerSectionAndQueue];
}

- (void)presentThemerFormatGuide
{
    ThemerFormatGuideViewController *vc =
        [[ThemerFormatGuideViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    vc.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:vc
                                                      action:@selector(dismissGuide)];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)presentThemerImporter
{
    UIAlertController *hint = [UIAlertController
        alertControllerWithTitle:@"Import Theme Folder"
                         message:@"Navigate into your theme folder so you can see the PNG files inside, then tap Open in the top-right corner to import the folder."
                  preferredStyle:UIAlertControllerStyleAlert];
    [hint addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder, UTTypePropertyList]];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        self.pendingThemeImportMode = @"themer";
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [hint addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:hint animated:YES completion:nil];
}

- (void)presentSnowBoardLiteFolderImporter
{
    UIAlertController *hint = [UIAlertController
        alertControllerWithTitle:@"Import Theme Folder"
                         message:@"Navigate into your theme folder so you can see IconBundles inside, then tap Open.\n\nIf tapping Open does nothing, your signing tool may need \"Match provisioning identifier\" enabled, or you can use Import Theme Archive instead."
                  preferredStyle:UIAlertControllerStyleAlert];
    [hint addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        self.pendingThemeImportMode = @"snowboardlite";
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [hint addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:hint animated:YES completion:nil];
}

- (void)presentSnowBoardLiteArchiveImporter
{
    UIAlertController *hint = [UIAlertController
        alertControllerWithTitle:@"Import Theme Archive"
                         message:@"Pick a ZIP or DEB file that contains an IconBundles directory. Cyanide extracts and imports a local copy."
                  preferredStyle:UIAlertControllerStyleAlert];
    [hint addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSArray<UTType *> *types = @[
            UTTypeZIP,
            [UTType typeWithFilenameExtension:@"deb"] ?: UTTypeData,
        ];
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        self.pendingThemeImportMode = @"snowboardlite";
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [hint addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:hint animated:YES completion:nil];
}

- (void)presentLiveWPVideoPicker
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Choose Video"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Photos"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        [self presentLiveWPPhotosPicker];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Files"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        [self presentLiveWPDocumentPicker];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = self.view;
        pop.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        pop.permittedArrowDirections = 0;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentLiveWPPhotosPicker
{
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 1;
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (NSArray<UTType *> *)liveWPVideoDocumentTypes
{
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    NSArray<NSString *> *extensions = @[@"mp4", @"mov", @"m4v"];
    for (NSString *ext in extensions) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type) [types addObject:type];
    }
    [types addObject:UTTypeMovie];
    [types addObject:UTTypeAudiovisualContent];
    return types;
}

- (void)presentLiveWPDocumentPicker
{
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:[self liveWPVideoDocumentTypes] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    self.pendingThemeImportMode = @"livewp";
    [self presentViewController:picker animated:YES completion:nil];
}

- (BOOL)importLiveWPVideoAtURL:(NSURL *)url error:(NSError **)error
{
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length == 0) return NO;
    NSString *liveDir = [docs stringByAppendingPathComponent:@"LiveWP"];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:liveDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"mov";
    NSSet<NSString *> *allowed = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v"]];
    if (![allowed containsObject:ext]) {
        if (error) {
            *error = [NSError errorWithDomain:@"LiveWP"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Choose an MP4, MOV, or M4V video."}];
        }
        return NO;
    }

    NSString *base = url.URLByDeletingPathExtension.lastPathComponent;
    if (base.length == 0) base = @"LiveWP";
    NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSString *safeBase = [[base componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"-"];
    if (safeBase.length == 0) safeBase = @"LiveWP";
    NSString *fileName = [NSString stringWithFormat:@"%@-%llu.%@",
                          safeBase,
                          (unsigned long long)(NSDate.date.timeIntervalSince1970 * 1000.0),
                          ext];
    NSString *dest = [liveDir stringByAppendingPathComponent:fileName];
    if (![fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:error]) {
        return NO;
    }

    NSString *relative = [@"LiveWP" stringByAppendingPathComponent:fileName];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:relative forKey:kSettingsLiveWPVideoPath];
    [d synchronize];
    log_user("[LIVEWP] Selected video: %s\n", fileName.UTF8String);
    return YES;
}

- (void)finishLiveWPVideoImportAndSwapIfRunning
{
    [self reloadSectionOrAll:SectionLiveWP];

    BOOL applied = settings_tweak_is_applied(kSettingsLiveWPEnabled);
    log_user("[LIVEWP] import: applied=%d rc_ready=%d\n", applied, g_springboard_rc_ready);
    if (!applied || !g_springboard_rc_ready) {
        settings_notify_package_queue_changed_async();
        return;
    }

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        bool ok = false;
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
            NSString *path = livewp_absolute_path();
            log_user("[LIVEWP] import: swap path=%s\n", path ? path.UTF8String : "(nil)");
            if (path.length > 0) {
                ok = livewp_swap_video_in_session(path);
                settings_mark_tweak_applied(kSettingsLiveWPEnabled, ok);
            }
        }
        log_user("%s LiveWP video swap %s.\n",
                 ok ? "[OK]" : "[WARN]",
                 ok ? "completed" : "did not complete");
        if (ok) settings_start_livewp_live_loop();
        settings_notify_package_queue_changed_async();
    });
}

- (NSString *)liveWPPreferredTypeIdentifierForProvider:(NSItemProvider *)provider
{
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (UTType *type in [self liveWPVideoDocumentTypes]) {
        if (type.identifier.length > 0) [identifiers addObject:type.identifier];
    }
    [identifiers addObjectsFromArray:@[
        @"public.mpeg-4",
        @"com.apple.m4v-video",
        @"com.apple.quicktime-movie",
        @"public.movie",
        @"public.audiovisual-content",
    ]];
    for (NSString *identifier in identifiers) {
        if ([provider hasItemConformingToTypeIdentifier:identifier]) return identifier;
    }
    return nil;
}

- (void)finishLiveWPVideoImportFromURL:(NSURL *)url
                           displayName:(NSString *)displayName
{
    NSError *err = nil;
    BOOL ok = [self importLiveWPVideoAtURL:url error:&err];
    BOOL liveReady = settings_tweak_is_applied(kSettingsLiveWPEnabled) && g_springboard_rc_ready;
    NSString *name = displayName.length ? displayName : (url.lastPathComponent ?: @"Video");
    NSString *successMessage = liveReady
        ? [NSString stringWithFormat:@"%@ was imported and will swap into the running LiveWP session.", name]
        : [NSString stringWithFormat:@"%@ is ready. Toggle LiveWP on and tap Run to apply.", name];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!ok) {
            NSString *msg = err.localizedDescription ?: @"The selected video could not be imported.";
            UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Import Failed"
                                                                         message:msg
                                                                  preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ac animated:YES completion:nil];
            return;
        }
        [self finishLiveWPVideoImportAndSwapIfRunning];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Video Selected"
                                                                     message:successMessage
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
    });
}

- (void)picker:(PHPickerViewController *)picker
didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;
    NSString *identifier = [self liveWPPreferredTypeIdentifierForProvider:provider];
    if (identifier.length == 0) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Import Failed"
                                                                     message:@"Choose an MP4, MOV, or M4V video."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSString *displayName = provider.suggestedName ?: @"Video";
    [provider loadFileRepresentationForTypeIdentifier:identifier
                                    completionHandler:^(NSURL *url, NSError *error) {
        if (!url || error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *msg = error.localizedDescription ?: @"The selected video could not be opened.";
                UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Import Failed"
                                                                             message:msg
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:ac animated:YES completion:nil];
            });
            return;
        }
        [self finishLiveWPVideoImportFromURL:url displayName:displayName];
    }];
}

- (BOOL)importThemerFolderAtURL:(NSURL *)url error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *target = settings_themer_imported_theme_dir();
    NSString *root = settings_themer_documents_theme_root();
    if (!target || !root) return NO;

    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;

    NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:url
                                includingPropertiesForKeys:nil
                                                   options:0
                                                     error:error];
    if (!files) return NO;

    NSMutableArray<NSURL *> *pngs = [NSMutableArray array];
    for (NSURL *file in files) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"png"]) {
            [pngs addObject:file];
        }
    }
    if (pngs.count == 0) return NO;

    [fm removeItemAtPath:target error:nil];
    [fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;
    [fm removeItemAtPath:settings_themer_imported_plist_path() error:nil];

    for (NSURL *png in pngs) {
        NSString *dst = [target stringByAppendingPathComponent:png.lastPathComponent];
        if (![fm copyItemAtURL:png toURL:[NSURL fileURLWithPath:dst] error:error]) {
            return NO;
        }
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeCustom forKey:kSettingsThemerThemeID];
    [d setObject:target forKey:kSettingsThemerCustomThemePath];
    [d setObject:url.lastPathComponent.length ? url.lastPathComponent : @"Imported Theme"
          forKey:kSettingsThemerCustomThemeName];
    [d synchronize];
    log_user("[THEMER] Imported custom folder theme: %lu PNG file(s).\n",
             (unsigned long)pngs.count);
    return YES;
}

- (BOOL)importThemerPlistAtURL:(NSURL *)url error:(NSError **)error
{
    NSDictionary *dict = settings_themer_load_plist_theme(url.path);
    if (dict.count == 0) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = settings_themer_documents_theme_root();
    NSString *target = settings_themer_imported_plist_path();
    if (!root || !target) return NO;
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;
    [fm removeItemAtPath:target error:nil];
    [fm removeItemAtPath:settings_themer_imported_theme_dir() error:nil];
    if (![fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:target] error:error]) {
        return NO;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeCustom forKey:kSettingsThemerThemeID];
    [d setObject:target forKey:kSettingsThemerCustomThemePath];
    [d setObject:url.lastPathComponent.length ? url.lastPathComponent : @"Imported Theme"
          forKey:kSettingsThemerCustomThemeName];
    [d synchronize];
    log_user("[THEMER] Imported custom plist theme: %lu icon entries.\n",
             (unsigned long)dict.count);
    return YES;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSString *mode = self.pendingThemeImportMode ?: @"themer";
    self.pendingThemeImportMode = nil;

    BOOL scoped = [url startAccessingSecurityScopedResource];
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir];
    printf("[IMPORT] url=%s scoped=%d exists=%d isDir=%d mode=%s\n",
           url.path.UTF8String, scoped, exists, isDir, mode.UTF8String);
    if (!exists) {
        if (scoped) [url stopAccessingSecurityScopedResource];
        log_user("[IMPORT] Cannot access selected file. Try a different location or file provider.\n");
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Import Failed"
                              message:@"The selected item could not be accessed. Try picking from a different location or file provider."
                       preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        BOOL ok = NO;
        NSString *successTitle = @"Theme Imported";
        NSString *successMessage = nil;

        if ([mode isEqualToString:@"livewp"]) {
            ok = [self importLiveWPVideoAtURL:url error:&err];
            successTitle = @"Video Selected";
            BOOL liveReady = settings_tweak_is_applied(kSettingsLiveWPEnabled) && g_springboard_rc_ready;
            successMessage = liveReady
                ? [NSString stringWithFormat:@"%@ was imported and will swap into the running LiveWP session.",
                                             url.lastPathComponent ?: @"Video"]
                : [NSString stringWithFormat:@"%@ is ready. Toggle LiveWP on and tap Run to apply.",
                                             url.lastPathComponent ?: @"Video"];
        } else if ([mode isEqualToString:@"snowboardlite"]) {
            if (isDir) {
                ok = settings_sbl_import_folder_theme(url, &err);
            } else {
                NSString *tmpRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"SnowBoardLite-%@", NSUUID.UUID.UUIDString]];
                ok = SBLExtractArchiveToDirectory(url, tmpRoot, &err);
                if (ok) {
                    NSString *displayName = url.URLByDeletingPathExtension.lastPathComponent ?: @"Imported Theme";
                    ok = settings_sbl_import_folder_theme_named([NSURL fileURLWithPath:tmpRoot],
                                                               displayName,
                                                               @"archive",
                                                               &err);
                }
                [[NSFileManager defaultManager] removeItemAtPath:tmpRoot error:nil];
            }
            successTitle = @"SnowBoard Theme Imported";
            NSString *name = settings_snowboardlite_selected_theme_display_name();
            successMessage = [NSString stringWithFormat:@"\"%@\" is now selected. Toggle SnowBoard Lite on and tap Run to apply.", name];
        } else {
            ok = isDir ? [self importThemerFolderAtURL:url error:&err]
                       : [self importThemerPlistAtURL:url error:&err];
            NSString *name = settings_themer_selected_theme_display_name();
            successMessage = [NSString stringWithFormat:@"\"%@\" is now selected. Toggle SnowBoard Lite on and tap Run to apply.", name];
        }
        if (scoped) [url stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                NSString *msg = err.localizedDescription ?: @"The selected item could not be imported.";
                UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Import Failed"
                                                                             message:msg
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:ac animated:YES completion:nil];
                return;
            }
            if ([mode isEqualToString:@"snowboardlite"]) {
                settings_mark_tweak_applied(kSettingsSnowBoardLiteEnabled, NO);
                settings_notify_package_queue_changed_async();
                if (self.detailMode && self.underlyingSection == SectionSnowBoardLite) {
                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
                } else {
                    [self.tableView reloadData];
                }
            } else if ([mode isEqualToString:@"livewp"]) {
                [self finishLiveWPVideoImportAndSwapIfRunning];
            } else {
                [self reloadThemerSectionAndQueue];
            }
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:successTitle
                                 message:successMessage
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ac animated:YES completion:nil];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    (void)controller;
    self.pendingThemeImportMode = nil;
}

- (void)reloadSectionOrAll:(NSInteger)section
{
    if (self.detailMode && self.underlyingSection == section) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView reloadData];
    }
}

- (void)presentNSBarPositionPicker
{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"NSBar Position"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *positions = @[
        @(NSBarPositionTopLeft),
        @(NSBarPositionBottomLeft),
        @(NSBarPositionTopRight),
        @(NSBarPositionBottomRight),
        @(NSBarPositionCenter),
    ];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSNumber *number in positions) {
        NSInteger pos = number.integerValue;
        NSString *title = settings_nsbar_position_name(pos);
        if (pos == [d integerForKey:kSettingsNSBarPosition]) {
            title = [title stringByAppendingString:@" ✓"];
        }
        [ac addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [d setInteger:pos forKey:kSettingsNSBarPosition];
            [d synchronize];
            settings_schedule_live_apply_for_key(kSettingsNSBarPosition);
            [self reloadSectionOrAll:SectionNSBar];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    settings_present_controller(ac, self);
}

- (NSString *)nicebarSubtitleForSlot:(NSInteger)slot
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    switch ((NiceBarLiteContentKind)kind) {
        case NiceBarLiteContentCustomText: {
            NSString *text = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, slot)] ?: @"";
            return text.length ? text : @"Text";
        }
        case NiceBarLiteContentSystem: {
            NSInteger item = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot)];
            if (item == NiceBarLiteSystemThermalState) {
                NSString *language = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, slot)] ?: @"en";
                return [NSString stringWithFormat:@"%@ · %@",
                        settings_nicebar_system_name(item),
                        CyanideNiceBarSystemLanguageName(language)];
            }
            return settings_nicebar_system_name(item);
        }
        case NiceBarLiteContentTimeFormat: {
            NSString *format = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot)] ?: @"HH:mm";
            return CyanideNiceBarTimeFormatName(format);
        }
        case NiceBarLiteContentWeather: {
            NSString *text = settings_nicebar_weather_text_for_slot(d, slot);
            return text.length ? text : @"Weather --";
        }
        case NiceBarLiteContentOff:
            return @"Hidden";
    }
    return @"Hidden";
}

- (UIButton *)nicebarSlotButton:(NSInteger)slot
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = slot;
    button.layer.cornerRadius = 10;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = UIColor.separatorColor.CGColor;
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.78;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 8, 10, 8);
    [button addTarget:self action:@selector(nicebarSlotButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    NSString *title = [NSString stringWithFormat:@"%@\n%@\n%@",
                       settings_nicebar_slot_name(slot),
                       settings_nicebar_kind_name(kind),
                       [self nicebarSubtitleForSlot:slot]];
    [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", settings_nicebar_slot_name(slot), [self nicebarSubtitleForSlot:slot]];
    return button;
}

- (UITableViewCell *)buildNiceBarGridCellInTableView:(UITableView *)tableView
                                           indexPath:(NSIndexPath *)indexPath
{
    (void)indexPath;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"nicebar-grid"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"nicebar-grid"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    for (UIView *view in [cell.contentView.subviews copy]) [view removeFromSuperview];

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self nicebarSlotButton:NiceBarLiteSlotTopLeft],
        [self nicebarSlotButton:NiceBarLiteSlotTopRight],
    ]];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.spacing = 10;
    top.distribution = UIStackViewDistributionFillEqually;

    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self nicebarSlotButton:NiceBarLiteSlotBottomLeft],
        [self nicebarSlotButton:NiceBarLiteSlotBottomCenter],
        [self nicebarSlotButton:NiceBarLiteSlotBottomRight],
    ]];
    bottom.axis = UILayoutConstraintAxisHorizontal;
    bottom.spacing = 10;
    bottom.distribution = UIStackViewDistributionFillEqually;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, bottom]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.distribution = UIStackViewDistributionFillEqually;
    [cell.contentView addSubview:stack];

    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [top.heightAnchor constraintEqualToConstant:84],
        [bottom.heightAnchor constraintEqualToConstant:84],
        [stack.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:m.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:m.bottomAnchor],
    ]];
    return cell;
}

- (void)presentNiceBarTextEditorForSlot:(NSInteger)slot
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *key = settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, slot);
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ Text", settings_nicebar_slot_name(slot)]
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Cyanide";
        field.text = [d stringForKey:key] ?: @"";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *value = ac.textFields.firstObject.text ?: @"";
        [d setInteger:NiceBarLiteContentCustomText forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
        [d setObject:value forKey:key];
        [d synchronize];
        settings_schedule_live_apply_for_key(key);
        [self reloadSectionOrAll:SectionNiceBarLite];
    }]];
    settings_present_controller(ac, self);
}

- (void)nicebarSetTimeFormat:(NSString *)format forSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setInteger:NiceBarLiteContentTimeFormat forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    [d setObject:format.length ? format : @"HH:mm" forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot)];
    [d synchronize];
    settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot));
    [self reloadSectionOrAll:SectionNiceBarLite];
}

- (void)nicebarSetKind:(NSInteger)kind forSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setInteger:kind forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    [d synchronize];
    settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot));
    [self reloadSectionOrAll:SectionNiceBarLite];
}

- (void)presentNiceBarDateTimePickerForSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *selectedFormat = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot)] ?: @"HH:mm";
    __weak typeof(self) weakSelf = self;
    CyanideNiceBarTimePresetPickerViewController *picker =
        [[CyanideNiceBarTimePresetPickerViewController alloc] initWithSlotTitle:[NSString stringWithFormat:@"%@ Date / Time", settings_nicebar_slot_name(slot)]
                                                                 selectedFormat:selectedFormat
                                                                      selection:^(NSString *format) {
        [weakSelf nicebarSetTimeFormat:format forSlot:slot];
    }];
    if (self.navigationController) {
        [self.navigationController pushViewController:picker animated:YES];
    } else {
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
    }
}

- (void)refreshNiceBarWeatherForce:(BOOL)force
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (!settings_nicebar_has_weather_slots(d)) return;
    NSString *cached = [d stringForKey:kSettingsNiceBarLiteWeatherCache] ?: @"";
    if (!cached.length || force) {
        settings_nicebar_store_weather_result(d, nil, nil, @"Weather...", NO);
        [self reloadSectionOrAll:SectionNiceBarLite];
    }

    __weak typeof(self) weakSelf = self;
    settings_nicebar_refresh_weather_if_needed(force, ^(BOOL ok, NSString *text) {
        (void)ok;
        (void)text;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf reloadSectionOrAll:SectionNiceBarLite];
        });
    });
}

- (void)nicebarSetWeatherLanguage:(NSString *)language forSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *resolved = [language isEqualToString:@"zh"] ? @"zh" : @"en";
    [d setInteger:NiceBarLiteContentWeather forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    [d setObject:resolved forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, slot)];
    settings_nicebar_update_weather_slot_texts(d);
    [d synchronize];
    settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, slot));
    [self reloadSectionOrAll:SectionNiceBarLite];
    [self refreshNiceBarWeatherForce:YES];
}

- (void)presentNiceBarWeatherLanguagePickerForSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ Weather", settings_nicebar_slot_name(slot)]
                                                                   message:@"Choose the weather display language."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"English" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self nicebarSetWeatherLanguage:@"en" forSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"中文" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self nicebarSetWeatherLanguage:@"zh" forSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    settings_present_controller(sheet, self);
}

- (void)presentNiceBarSystemPickerForSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSInteger selectedItem = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot)];
    NSString *selectedLanguage = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, slot)] ?: @"en";
    __weak typeof(self) weakSelf = self;
    CyanideNiceBarSystemItemPickerViewController *picker =
        [[CyanideNiceBarSystemItemPickerViewController alloc] initWithSlotTitle:[NSString stringWithFormat:@"%@ System Item", settings_nicebar_slot_name(slot)]
                                                                   selectedItem:selectedItem
                                                               selectedLanguage:selectedLanguage
                                                                      selection:^(NSInteger item, NSString *language) {
        NSUserDefaults *innerDefaults = NSUserDefaults.standardUserDefaults;
        [innerDefaults setInteger:NiceBarLiteContentSystem forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
        [innerDefaults setInteger:item forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot)];
        [innerDefaults setObject:language.length ? language : @"en"
                          forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, slot)];
        [innerDefaults synchronize];
        settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot));
        [weakSelf reloadSectionOrAll:SectionNiceBarLite];
    }];
    if (self.navigationController) {
        [self.navigationController pushViewController:picker animated:YES];
    } else {
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
    }
}

- (void)presentNiceBarSlotEditor:(NSInteger)slot
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:settings_nicebar_slot_name(slot)
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    [ac addAction:[UIAlertAction actionWithTitle:@"Off" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [d setInteger:NiceBarLiteContentOff forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
        [d synchronize];
        settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot));
        [self reloadSectionOrAll:SectionNiceBarLite];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Custom Text" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self presentNiceBarTextEditorForSlot:slot];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"System Item" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self presentNiceBarSystemPickerForSlot:slot];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Date / Time" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self presentNiceBarDateTimePickerForSlot:slot];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Weather" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self presentNiceBarWeatherLanguagePickerForSlot:slot];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    settings_present_controller(ac, self);
}

- (void)nicebarSlotButtonTapped:(UIButton *)sender
{
    NSInteger slot = sender.tag;
    if (slot >= 0 && slot < NiceBarLiteSlotCount) {
        [self presentNiceBarSlotEditor:slot];
    }
}

- (void)selectSnowBoardLiteIOS6Theme
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:kSnowBoardLiteThemeBuiltinIOS6 forKey:kSettingsSnowBoardLiteSelectedThemeID];
    [d synchronize];
    settings_mark_tweak_applied(kSettingsSnowBoardLiteEnabled, NO);
    settings_notify_package_queue_changed_async();
    [self reloadSectionOrAll:SectionSnowBoardLite];
}

- (void)clearSnowBoardLiteTheme
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:@"" forKey:kSettingsSnowBoardLiteSelectedThemeID];
    if ([d boolForKey:kSettingsSnowBoardLiteEnabled]) {
        [d setBool:NO forKey:kSettingsSnowBoardLiteEnabled];
        g_themer_live_stop_requested = 1;
    }
    [d synchronize];
    settings_mark_tweak_applied(kSettingsSnowBoardLiteEnabled, NO);
    settings_notify_package_queue_changed_async();
    [self reloadSectionOrAll:SectionSnowBoardLite];
}

- (void)clearLiveWPVideo
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:@"" forKey:kSettingsLiveWPVideoPath];
    if ([d boolForKey:kSettingsLiveWPEnabled]) {
        [d setBool:NO forKey:kSettingsLiveWPEnabled];
        g_livewp_live_stop_requested = 1;
    }
    [d synchronize];
    settings_schedule_live_apply_for_key(kSettingsLiveWPEnabled);
    [self reloadSectionOrAll:SectionLiveWP];
}

// "Classic" alternate icon is registered in Info.plist with CFBundleIconFiles
// pointing to Cyanide-Classic@{2,3}x.png at the bundle root. Modern is the
// asset-catalog primary, selected by passing nil to setAlternateIconName:.
+ (UIImage *)appIconPreviewForStyle:(NSString *)style
{
    NSString *name = [style isEqualToString:@"classic"] ? @"preview-classic" : @"preview-modern";
    UIImage *raw = [UIImage imageNamed:name];
    if (!raw) return nil;
    // Render with iOS home-screen corner radius (≈22% of side) so the thumb
    // matches what users see on SpringBoard. 52pt fits in the default subtitle
    // cell row height without forcing layout overrides.
    CGFloat side = 52.0;
    CGFloat radius = side * 0.22;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side)
                                                      cornerRadius:radius];
        [p addClip];
        [raw drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

- (NSString *)currentAppIconStyle
{
    NSString *alt = [UIApplication sharedApplication].alternateIconName;
    return [alt isEqualToString:@"Classic"] ? @"classic" : @"modern";
}

- (UITableViewCell *)buildAppIconCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"appicon"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"appicon"];
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    NSString *style = (row == 0) ? @"modern" : @"classic";
    cell.imageView.image = [SettingsViewController appIconPreviewForStyle:style];

    if (row == 0) {
        cell.textLabel.text = @"Modern";
        cell.detailTextLabel.text = @"Default — refreshed v2 mark.";
    } else {
        cell.textLabel.text = @"Classic";
        cell.detailTextLabel.text = @"Original release artwork.";
    }

    BOOL selected = [[self currentAppIconStyle] isEqualToString:style];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)selectAppIconAtRow:(NSInteger)row inTableView:(UITableView *)tableView
{
    NSString *style = (row == 0) ? @"modern" : @"classic";
    if ([[self currentAppIconStyle] isEqualToString:style]) return;

    if (![UIApplication sharedApplication].supportsAlternateIcons) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Can't Change Icon"
                             message:@"This iOS build doesn't expose alternate icon switching."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSString *altName = [style isEqualToString:@"classic"] ? @"Classic" : nil;
    [[UIApplication sharedApplication] setAlternateIconName:altName completionHandler:^(NSError * _Nullable error) {
        if (error) {
            printf("[SETTINGS] app icon switch to '%s' failed: %s\n",
                   style.UTF8String,
                   error.localizedDescription.UTF8String);
        } else {
            printf("[SETTINGS] app icon switched to %s\n", style.UTF8String);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexSet *idx = [NSIndexSet indexSetWithIndex:RootSectionAbout];
            [tableView reloadSections:idx withRowAnimation:UITableViewRowAnimationNone];
        });
    }];
}

- (void)showAppIconPicker
{
    if (![UIApplication sharedApplication].supportsAlternateIcons) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Can't Change Icon"
                             message:@"This iOS build doesn't expose alternate icon switching."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }
    NSString *current = [self currentAppIconStyle];
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"App Icon"
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *modernTitle = [current isEqualToString:@"modern"] ? @"Modern ✓" : @"Modern";
    NSString *classicTitle = [current isEqualToString:@"classic"] ? @"Classic ✓" : @"Classic";
    [ac addAction:[UIAlertAction actionWithTitle:modernTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self selectAppIconAtRow:0 inTableView:self.tableView];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:classicTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self selectAppIconAtRow:1 inTableView:self.tableView];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
    [self presentViewController:ac animated:YES completion:nil];
}

+ (UIImage *)experimentalDangerChip
{
    static UIImage *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *text = @"DANGER";
        UIFont *font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: UIColor.whiteColor,
            NSKernAttributeName: @(0.4),
        };
        CGSize ts = [text sizeWithAttributes:attrs];
        CGFloat padH = 6.5;
        CGFloat padV = 2.5;
        CGSize size = CGSizeMake(ceil(ts.width) + padH * 2.0,
                                 ceil(ts.height) + padV * 2.0);
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
        cached = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                          cornerRadius:size.height / 2.0];
            [UIColor.systemRedColor setFill];
            [p fill];
            [text drawAtPoint:CGPointMake(padH, padV) withAttributes:attrs];
        }];
    });
    return cached;
}

- (UITableViewCell *)buildExperimentalCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"experimental"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"experimental"];
        cell.detailTextLabel.numberOfLines = 0;
    }
    BOOL on = settings_experimental_tweaks_enabled();

    UIColor *iconColor = on ? UIColor.systemRedColor
                            : [UIColor.systemRedColor colorWithAlphaComponent:0.55];
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"flask.fill"
                                                                  color:iconColor
                                                                   size:29.0];

    NSMutableAttributedString *title = [[NSMutableAttributedString alloc]
        initWithString:@"Experimental Tweaks  "
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:17.0],
                          NSForegroundColorAttributeName: UIColor.labelColor }];
    NSTextAttachment *att = [[NSTextAttachment alloc] init];
    UIImage *chip = [SettingsViewController experimentalDangerChip];
    att.image = chip;
    att.bounds = CGRectMake(0, -2.0, chip.size.width, chip.size.height);
    [title appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
    cell.textLabel.attributedText = title;

#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
    cell.detailTextLabel.text = on
        ? @"Active — Signal Readouts, TypeBanner, Notification Island, FastLockX Lite, Dynamic Stage Lite."
        : @"Signal Readouts, TypeBanner, Notification Island, FastLockX Lite, Dynamic Stage Lite.";
#else
    cell.detailTextLabel.text = on
        ? @"Active — no private experimental tweaks in this build."
        : @"No private experimental tweaks in this build.";
#endif
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.detailTextLabel.textColor = on
        ? [UIColor.systemRedColor colorWithAlphaComponent:0.9]
        : UIColor.secondaryLabelColor;

    cell.backgroundColor = on
        ? [UIColor.systemRedColor colorWithAlphaComponent:0.10]
        : nil;

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = UIColor.systemRedColor;
    sw.on = on;
    [sw addTarget:self action:@selector(experimentalSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)experimentalSwitchChanged:(UISwitch *)sw
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL enabling = sw.isOn;

    if (enabling) {
        if (!settings_experimental_access_allowed()) {
            sw.on = NO;
            [d setBool:NO forKey:kSettingsExperimentalTweaksEnabled];
            [self reloadAfterExperimentalChange];
            return;
        }
        // Hard confirm before flipping master on. If the user cancels, revert
        // the switch and stop here.
        sw.on = NO;
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Enable Experimental Tweaks?"
                             message:@"These tweaks are unfinished and may cause crashes, layout glitches, or battery drain. Only enable if you're actively testing."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Enable Anyway"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_) {
            [d setBool:YES forKey:kSettingsExperimentalTweaksEnabled];
            sw.on = YES;
            printf("[SETTINGS] experimental tweaks enabled\n");
            [self reloadAfterExperimentalChange];
        }]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    [d setBool:NO forKey:kSettingsExperimentalTweaksEnabled];
    printf("[SETTINGS] experimental tweaks disabled; disabling gated package states\n");

    // Force-disable every experimental-gated package.
    if ([d boolForKey:kSettingsTypeBannerEnabled]) {
        [d setBool:NO forKey:kSettingsTypeBannerEnabled];
        settings_mark_tweak_applied(kSettingsTypeBannerEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsTypeBannerEnabled);
    }
    if ([d boolForKey:kSettingsNotificationIslandEnabled]) {
        [d setBool:NO forKey:kSettingsNotificationIslandEnabled];
        settings_mark_tweak_applied(kSettingsNotificationIslandEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsNotificationIslandEnabled);
    }
    if ([d boolForKey:kSettingsRSSIDisplayEnabled]) {
        [d setBool:NO forKey:kSettingsRSSIDisplayEnabled];
        settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsRSSIDisplayEnabled);
    }
    if ([d boolForKey:kSettingsStageStripEnabled]) {
        [d setBool:NO forKey:kSettingsStageStripEnabled];
        settings_mark_tweak_applied(kSettingsStageStripEnabled, NO);
        settings_notify_package_queue_changed_async();
    }
    [self forceDisableFastLockXLiteForExperimentalGateWithDefaults:d];
    [self reloadAfterExperimentalChange];
}

- (void)forceDisableFastLockXLiteForExperimentalGateWithDefaults:(NSUserDefaults *)d
{
    BOOL shouldStop = [d boolForKey:kSettingsFastLockXLiteEnabled] ||
                      settings_tweak_is_applied(kSettingsFastLockXLiteEnabled);
    if (!shouldStop) return;

    [d setBool:NO forKey:kSettingsFastLockXLiteEnabled];
    [d synchronize];
    settings_notify_package_queue_changed_async();

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL actionLockAcquired = settings_try_claim_actions_lock("FastLockX Lite cleanup",
                                                                 "[FLX] FastLockX Lite cleanup deferred: another action is running.");
        if (!actionLockAcquired) return;
        @try {
            bool stopped = false;
            if (settings_ensure_kexploit()) {
                @synchronized (settings_rc_lock()) {
                    if (!g_springboard_rc_ready) {
                        settings_ensure_springboard_remote_call_locked();
                    }
                    if (g_springboard_rc_ready) {
                        stopped = fastlockx_lite_disable_always_on_in_session();
                    }
                }
            }
            if (!stopped) {
                fastlockx_lite_forget_remote_state();
                log_user("[FLX] Experimental gate disabled; Always On will also stop on respring if timers were unreachable.\n");
            }
            settings_mark_tweak_applied(kSettingsFastLockXLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
        } @finally {
            settings_release_actions_lock();
        }
    });
}

- (void)reloadAfterExperimentalChange
{
    // Tweak bundle list visibility depends on the experimental flag, and the
    // installer's package list is filtered by it too — refresh both.
    [self.tableView reloadData];
    [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                        object:[PackageQueue sharedQueue]];
}

#pragma mark - Patreon

// Drops any experimental-gated package state if the user is no longer a patron.
- (void)teardownExperimentalIfNoLongerPatron
{
    if (settings_experimental_access_allowed()) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsExperimentalTweaksEnabled]) return;

    printf("[PATREON] patron status lost; force-disabling experimental tweaks\n");
    [d setBool:NO forKey:kSettingsExperimentalTweaksEnabled];
    if ([d boolForKey:kSettingsTypeBannerEnabled]) {
        [d setBool:NO forKey:kSettingsTypeBannerEnabled];
        settings_mark_tweak_applied(kSettingsTypeBannerEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsTypeBannerEnabled);
    }
    if ([d boolForKey:kSettingsNotificationIslandEnabled]) {
        [d setBool:NO forKey:kSettingsNotificationIslandEnabled];
        settings_mark_tweak_applied(kSettingsNotificationIslandEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsNotificationIslandEnabled);
    }
    if ([d boolForKey:kSettingsRSSIDisplayEnabled]) {
        [d setBool:NO forKey:kSettingsRSSIDisplayEnabled];
        settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsRSSIDisplayEnabled);
    }
    if ([d boolForKey:kSettingsStageStripEnabled]) {
        [d setBool:NO forKey:kSettingsStageStripEnabled];
        settings_mark_tweak_applied(kSettingsStageStripEnabled, NO);
        settings_notify_package_queue_changed_async();
    }
    [self forceDisableFastLockXLiteForExperimentalGateWithDefaults:d];
}

- (void)patreonStatusDidChange:(NSNotification *)note
{
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        BOOL nowPatron = settings_experimental_access_allowed();
        BOOL wasPatron = [d boolForKey:kCyanideLastKnownIsPatron];
        BOOL haveLastKnown = ([d objectForKey:kCyanideLastKnownIsPatron] != nil);
        if (nowPatron && (!wasPatron || !haveLastKnown)) {
            if (![d boolForKey:kSettingsExperimentalTweaksEnabled]) {
                [d setBool:YES forKey:kSettingsExperimentalTweaksEnabled];
            }
        }
        [d setBool:nowPatron forKey:kCyanideLastKnownIsPatron];

        [self teardownExperimentalIfNoLongerPatron];
        if (!self.isViewLoaded || self.detailMode) return;
        // Row count for Patreon changes between unlinked/linked states, so a
        // full reloadData is simpler than animating diffs.
        [self.tableView reloadData];
    });
}

- (UITableViewCell *)buildPatreonCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    BOOL linked = cyanide_patreon_is_linked();
    UIColor *patreonOrange = [UIColor colorWithRed:0.94 green:0.31 blue:0.20 alpha:1.0];

    if (!linked) {
        // Row 0: link an existing Patreon account (OAuth flow in-app).
        // Row 1: new-to-Patreon sign-up affordance (opens patreon.com/zeroxjf).
        if (row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"patreon-link"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"patreon-link"];
                cell.detailTextLabel.numberOfLines = 0;
            }
            cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"heart.fill"
                                                                          color:patreonOrange
                                                                           size:29.0];
            cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
            cell.textLabel.textColor = patreonOrange;
            cell.textLabel.text = @"Link Patreon Account";
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
            cell.detailTextLabel.text = nil;
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
        // row == 1: explicit "don't have one yet?" entry point.
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"patreon-signup"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"patreon-signup"];
            cell.detailTextLabel.numberOfLines = 0;
        }
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"person.crop.circle.badge.plus"
                                                                      color:patreonOrange
                                                                       size:29.0];
        cell.textLabel.font = [UIFont systemFontOfSize:17.0];
        cell.textLabel.textColor = patreonOrange;
        cell.textLabel.text = @"New to Patreon? Sign Up";
        cell.textLabel.textAlignment = NSTextAlignmentLeft;
        cell.detailTextLabel.text = @"Join at patreon.com/zeroxjf, then come back and Link.";
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    BOOL isPatron = cyanide_is_patron();

    if (row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"patreon-status"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"patreon-status"];
            cell.detailTextLabel.numberOfLines = 0;
        }
        UIColor *iconColor = isPatron ? patreonOrange : [patreonOrange colorWithAlphaComponent:0.45];
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"heart.fill"
                                                                      color:iconColor
                                                                       size:29.0];
        cell.textLabel.font = [UIFont systemFontOfSize:17.0];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.text = cyanide_patreon_display_name() ?: @"Linked";

        NSString *tier = cyanide_patreon_tier_title();
        NSInteger cents = cyanide_patreon_pledge_cents();
        NSString *detail;
        if (isPatron) {
            if (cents <= 0) {
                // Synthetic tiers like "Creator" carry no dollar amount —
                // showing "$0/month" beside them reads as a bug.
                detail = tier.length > 0 ? tier : @"Active supporter";
            } else {
                NSString *amount = (cents % 100 == 0)
                    ? [NSString stringWithFormat:@"$%ld/month", (long)(cents / 100)]
                    : [NSString stringWithFormat:@"$%.2f/month", cents / 100.0];
                detail = tier.length > 0
                    ? [NSString stringWithFormat:@"%@ • %@", tier, amount]
                    : amount;
            }
        } else {
            detail = @"Free user — join Member tier to unlock.";
        }
        cell.detailTextLabel.text = detail;
        cell.detailTextLabel.textColor = isPatron ? patreonOrange : UIColor.secondaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    // Action rows. Free-supporter layout inserts a "Join Member Tier" row
    // between the identity row and Refresh/Sign Out, so the indices shift.
    NSInteger joinRow    = isPatron ? -1 : 1;
    NSInteger refreshRow = isPatron ?  1 : 2;
    NSInteger signoutRow = isPatron ?  2 : 3;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"patreon-action"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"patreon-action"];
    }
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    if (row == joinRow) {
        cell.textLabel.text = @"Join Member Tier on Patreon";
        cell.textLabel.textColor = patreonOrange;
        cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    } else if (row == refreshRow) {
        cell.textLabel.text = @"Refresh Patron Status";
        cell.textLabel.textColor = self.view.tintColor;
    } else if (row == signoutRow) {
        cell.textLabel.text = @"Sign Out of Patreon";
        cell.textLabel.textColor = UIColor.systemRedColor;
    }
    return cell;
}

- (UITableViewCell *)buildExperimentalLockedCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"experimental-locked"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"experimental-locked"];
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"lock.fill"
                                                                  color:UIColor.systemGrayColor
                                                                   size:29.0];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.text = @"Experimental Tweaks";
    if (cyanide_patreon_is_linked()) {
        cell.detailTextLabel.text = @"Linked as free user — tap to upgrade to Member tier.";
    } else {
        cell.detailTextLabel.text = @"Member tier on Patreon required. Tap to link or sign up.";
    }
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.backgroundColor = nil;
    return cell;
}

- (void)handlePatreonTapAtRow:(NSInteger)row
{
    BOOL linked = cyanide_patreon_is_linked();

    if (!linked) {
        // Row 0 = "Link Patreon Account" → in-app OAuth.
        // Row 1 = "New to Patreon? Sign Up" → opens patreon.com/zeroxjf in Safari.
        if (row == 1) {
            [[UIApplication sharedApplication] openURL:cyanide_patreon_join_url()
                                               options:@{}
                                     completionHandler:nil];
            return;
        }
        cyanide_patreon_authenticate(self, ^(BOOL ok, NSError *err) {
            if (ok) {
                printf("[PATREON] linked successfully; is_patron=%d experimental_access=%d\n",
                       (int)cyanide_is_patron(), (int)settings_experimental_access_allowed());
                [self patreonStatusDidChange:nil];
                return;
            }
            if ([err.domain isEqualToString:@"CyanidePatreon"] && err.code == NSUserCancelledError) return;
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Couldn't Link Patreon"
                                 message:err.localizedDescription ?: @"Unknown error."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ac animated:YES completion:nil];
        });
        return;
    }

    if (row == 0) return;  // identity row, non-interactive

    BOOL isPatron = cyanide_is_patron();
    NSInteger joinRow    = isPatron ? -1 : 1;
    NSInteger refreshRow = isPatron ?  1 : 2;
    NSInteger signoutRow = isPatron ?  2 : 3;

    if (row == joinRow) {
        [[UIApplication sharedApplication] openURL:cyanide_patreon_join_url() options:@{} completionHandler:nil];
        return;
    }

    if (row == refreshRow) {
        cyanide_patreon_refresh(^(BOOL ok, NSError *err) {
            if (ok) {
                [self patreonStatusDidChange:nil];
                return;
            }
            printf("[PATREON] refresh failed: %s\n", err.localizedDescription.UTF8String ?: "unknown");
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Couldn't Refresh"
                                 message:err.localizedDescription ?: @"Unknown error."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ac animated:YES completion:nil];
        });
        return;
    }

    if (row == signoutRow) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Sign Out of Patreon?"
                             message:@"Removes the linked account from this device. Supporter-only features will lock until you link again."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Sign Out"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_) {
            cyanide_patreon_sign_out();
        }]];
        [self presentViewController:ac animated:YES completion:nil];
    }
}

- (void)openTwitter
{
    NSURL *url = [NSURL URLWithString:@"https://twitter.com/zeroxjf"];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)openViewLog
{
    NSString *logPath = log_most_recent_session_path();
    NSString *text;
    if (!logPath) {
        text = @"No log yet. Run a chain at least once.";
    } else {
        NSError *err = nil;
        text = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&err];
        if (!text) text = [NSString stringWithFormat:@"Failed to read log: %@", err.localizedDescription];
    }

    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"Log";
    vc.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    tv.textColor = UIColor.labelColor;
    tv.backgroundColor = UIColor.systemGroupedBackgroundColor;
    tv.text = text;
    [vc.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor      constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [tv.bottomAnchor   constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor],
        [tv.leadingAnchor  constraintEqualToAnchor:vc.view.leadingAnchor constant:16.0],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-16.0],
    ]];

    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openShareLog
{
    NSString *logPath = log_most_recent_session_path();
    if (!logPath.length) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"No Log Yet"
                                                                     message:@"Run a chain once, then come back to share the latest diagnostic log."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSURL *logURL = [NSURL fileURLWithPath:logPath];
    NSString *appVersion = settings_app_version_string();
    NSString *iosVersion = [UIDevice currentDevice].systemVersion ?: @"unknown";
    struct utsname info; uname(&info);
    NSString *machine = [NSString stringWithUTF8String:info.machine] ?: @"unknown";
    NSString *summary = [NSString stringWithFormat:@"Cyanide diagnostic log\nCyanide %@ · iOS %@ · %@",
                         appVersion, iosVersion, machine];

    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[summary, logURL]
                                                                     applicationActivities:nil];
    UIPopoverPresentationController *popover = vc.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                        CGRectGetMidY(self.view.bounds),
                                        1.0,
                                        1.0);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:vc animated:YES completion:nil];
}

// Contact owner (zeroxjf) with the diagnostic log inline in the body. Build
// info sits between the user's typing area at the top and the log dump
// below, so the user just types above the signature and hits send.
- (void)openContactEmail
{
    cyanide_present_contact(self);
}

// Public entry point for the Contact flow. Builds the email body (signature
// + inline diagnostic log) and presents MFMailComposeViewController from
// `host` when Mail is set up, else opens a mailto: URL with a truncated log
// tail so third-party mail apps still get useful context.
void cyanide_present_contact(UIViewController *host)
{
    if (!host) return;

    NSString *appVersion = settings_app_version_string();
    NSString *iosVersion = [UIDevice currentDevice].systemVersion ?: @"unknown";
    struct utsname info; uname(&info);
    NSString *machine = [NSString stringWithUTF8String:info.machine];

    // Single-line signature so it reads correctly even in mail clients that
    // collapse newlines from mailto: bodies (Gmail-iOS being the worst offender).
    NSString *signature = [NSString stringWithFormat:@"—— Cyanide %@ · iOS %@ · %@ ——",
                           appVersion, iosVersion, machine];

    NSString *subject = [NSString stringWithFormat:@"Cyanide %@ — Contact", appVersion];

    // CRLF rather than LF so iOS Mail, Gmail, Outlook, and the mailto: URL
    // path all preserve line breaks. Plain LF is fine in MFMailCompose but
    // some third-party clients eat them when the body arrives via mailto:.
    // Log inclusion is intentionally omitted for now — pipeline was unreliable
    // (in-app buffer snapshot wasn't landing in the email). Build/device info
    // still ships in the signature so I can at least see the user's setup.
    NSMutableString *body = [NSMutableString string];
    [body appendString:@"\r\n\r\n\r\n"]; // breathing room at top for the user to type
    [body appendString:signature];
    [body appendString:@"\r\n"];

    if ([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController *vc = [[MFMailComposeViewController alloc] init];
        vc.mailComposeDelegate = _cyanide_mail_delegate();
        [vc setToRecipients:@[@"zeroxjf@gmail.com"]];
        [vc setSubject:subject];
        [vc setMessageBody:body isHTML:NO];
        [host presentViewController:vc animated:YES completion:nil];
        return;
    }

    // Mail not configured — fall back to mailto:. Bodies get URL-encoded so
    // long logs produce long URLs; in practice iOS LaunchServices accepts
    // ~64KB and third-party mail apps still receive the full body. We send
    // the full log regardless and trust the client to handle it.
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *q = [NSString stringWithFormat:@"subject=%@&body=%@",
        [subject stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"",
        [body stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];
    NSURL *url = [NSURL URLWithString:[@"mailto:zeroxjf@gmail.com?" stringByAppendingString:q]];
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }

    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Mail Not Available"
                         message:@"Set up Mail in iOS Settings to send feedback, or DM @zeroxjf on Twitter. View Log in Settings to copy the latest diagnostic log."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [host presentViewController:ac animated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Preserve the table view's actual indexPath for dequeue calls (which
    // expect a path that exists in the current data source). `indexPath`
    // is remapped to the underlying SettingsSection for content lookup.
    NSIndexPath *dequeuePath = indexPath;

    if (!self.detailMode) {
        switch ((RootSection)indexPath.section) {
            case RootSectionWarning:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionWarning];
                break;
            case RootSectionChangelog: {
                if (!self.changelogExpanded) {
                    return [self buildChangelogCollapsedCellInTableView:tableView];
                }
                NSInteger entryCount = (NSInteger)settings_changelog_entries().count;
                if (indexPath.row == entryCount) {
                    return [self buildChangelogFooterCellInTableView:tableView];
                }
                if (indexPath.row > entryCount) {
                    return [self buildChangelogCollapseCellInTableView:tableView];
                }
                return [self buildChangelogCellAtRow:indexPath.row tableView:tableView];
            }
            case RootSectionActions:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionActions];
                break;
            case RootSectionTweakBundles:
                return [self buildBundleCellWithRow:self.tweakBundleRows[indexPath.row] tableView:tableView];
            case RootSectionInDev:
                return [self buildInDevCellWithRow:self.inDevBundleRows[indexPath.row] tableView:tableView];
            case RootSectionSystemBundles:
                return [self buildBundleCellWithRow:self.systemBundleRows[indexPath.row] tableView:tableView];
            case RootSectionPatreon:
                return [self buildPatreonCellAtRow:indexPath.row tableView:tableView];
            case RootSectionExperimental:
                if (!settings_experimental_access_allowed())
                    return [self buildExperimentalLockedCellInTableView:tableView];
                return [self buildExperimentalCellInTableView:tableView];
            case RootSectionAbout:
                return [self buildAboutCellAtRow:indexPath.row tableView:tableView];
            case RootSectionCount:
                return [[UITableViewCell alloc] init];
        }
    } else {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:self.underlyingSection];
    }

    if (indexPath.section == SectionWarning) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"warning" forIndexPath:dequeuePath];
        return [self buildWarningCell:cell];
    }
    if (indexPath.section == SectionActions) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action-compact"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"action-compact"];
            cell.detailTextLabel.numberOfLines = 1;
        }
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.text = nil;

        BOOL supported = settings_device_supported();
        BOOL cleanupEnabled = supported && (g_kexploit_done ||
                                            g_springboard_rc_ready ||
                                            remote_call_has_local_state());
        BOOL anyInstalledOrQueued = NO;
        for (Package *p in [PackageCatalog allPackages]) {
            if (p.isInstalled || p.isQueuedForApply) { anyInstalledOrQueued = YES; break; }
        }
        if (!anyInstalledOrQueued) {
            anyInstalledOrQueued = [[PackageQueue sharedQueue] pendingCount] > 0;
        }

        BOOL rowEnabled = supported;
        NSString *symbol = nil;
        UIColor *color = nil;

        if (indexPath.row == 0) {
            rowEnabled = cleanupEnabled;
            BOOL running = g_settings_cleanup_running;
            symbol = @"xmark.circle.fill";
            color  = UIColor.systemRedColor;
            cell.textLabel.text = running ? @"Cleaning Up…" : @"Clean Up";
            cell.detailTextLabel.text = cleanupEnabled ? nil : @"No active session";
            if (running) {
                UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                spin.color = color;
                [spin startAnimating];
                cell.accessoryView = spin;
            }
        } else if (indexPath.row == 1) {
            BOOL running = g_settings_respring_cleanup_running;
            symbol = @"arrow.clockwise.circle.fill";
            color  = UIColor.systemOrangeColor;
            cell.textLabel.text = running ? @"Preparing…" : @"Respring";
            if (running) {
                UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                spin.color = color;
                [spin startAnimating];
                cell.accessoryView = spin;
            }
        } else if (indexPath.row == 2) {
            rowEnabled = anyInstalledOrQueued;
            symbol = @"trash.fill";
            color  = UIColor.systemRedColor;
            cell.textLabel.text = @"Reset All Packages";
            cell.detailTextLabel.text = anyInstalledOrQueued ? nil : @"Nothing active";
        } else {
            rowEnabled = YES;
            symbol = @"arrow.down.circle.fill";
            color  = UIColor.systemBlueColor;
            cell.textLabel.text = @"Check for Updates";
        }

        UIColor *effectiveColor = rowEnabled ? color : UIColor.tertiaryLabelColor;
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:symbol color:effectiveColor size:29.0];
        cell.textLabel.font = [UIFont systemFontOfSize:17.0];
        cell.textLabel.textColor = rowEnabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        cell.detailTextLabel.textColor = UIColor.tertiaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
        cell.selectionStyle = rowEnabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = rowEnabled;
        return cell;
    }

    NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
    NSString *kind = row[@"kind"] ?: @"toggle";
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL supported = settings_device_supported();

    if ([kind isEqualToString:@"nicebar-grid"]) {
        return [self buildNiceBarGridCellInTableView:tableView indexPath:dequeuePath];
    }

    if ([kind isEqualToString:@"info"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"info"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"info"];
            cell.detailTextLabel.numberOfLines = 0;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = NO;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = row[@"subtitle"];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
        return cell;
    }

    if ([kind isEqualToString:@"button"]) {
        BOOL rowSupported = supported ||
                            indexPath.section == SectionOTA ||
                            indexPath.section == SectionThemer;
        NSString *action = row[@"action"];
        if (indexPath.section == SectionNanoRegistry &&
            [action isEqualToString:@"nano-load"]) {
            rowSupported = settings_nano_load_override_enabled();
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"button" forIndexPath:dequeuePath];
        cell.selectionStyle = rowSupported ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = rowSupported;
        cell.accessoryView = nil;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = rowSupported
            ? ([row[@"destructive"] boolValue] ? UIColor.systemRedColor : self.view.tintColor)
            : UIColor.tertiaryLabelColor;
        return cell;
    }

    if ([kind isEqualToString:@"stepper"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stepper" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
        cell.textLabel.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        NSInteger value = [d integerForKey:row[@"key"]];
        NSString *combined = [NSString stringWithFormat:@"%@: %ld", row[@"title"], (long)value];
        NSString *subtitle = row[@"subtitle"];
        if (subtitle.length > 0) {
            UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];
            config.text = combined;
            config.secondaryText = subtitle;
            config.textToSecondaryTextVerticalPadding = 3;
            config.textProperties.color = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
            config.secondaryTextProperties.color = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
            config.secondaryTextProperties.font = [UIFont systemFontOfSize:12];
            config.secondaryTextProperties.numberOfLines = 0;
            cell.contentConfiguration = config;
        } else {
            cell.contentConfiguration = nil;
            cell.textLabel.text = combined;
        }
        UIStepper *stp = [[UIStepper alloc] init];
        stp.minimumValue = [row[@"min"] doubleValue];
        stp.maximumValue = [row[@"max"] doubleValue];
        stp.stepValue = 1;
        stp.value = (double)value;
        stp.enabled = supported;
        stp.tag = (indexPath.section << 16) | indexPath.row;
        [stp addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stp;
        return cell;
    }

    if ([kind isEqualToString:@"number"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"number"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"number"];
            cell.detailTextLabel.numberOfLines = 0;
        }
        cell.selectionStyle = supported ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = supported;
        cell.accessoryType = supported ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        cell.contentConfiguration = nil;

        double value = settings_number_row_current_value(row, d);
        NSString *valueText = settings_number_row_value_string(row, value, YES);
        cell.textLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"title"], valueText];
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
        cell.textLabel.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        cell.detailTextLabel.text = row[@"subtitle"] ?: @"Tap to enter an exact value.";
        cell.detailTextLabel.textColor = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        return cell;
    }

    if ([kind isEqualToString:@"slider"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slider" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryView = nil;
        for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

        NSInteger minV = [row[@"min"] integerValue];
        NSInteger maxV = [row[@"max"] integerValue];
        NSInteger step = [row[@"step"] integerValue]; if (step <= 0) step = 1;
        NSInteger value = [d integerForKey:row[@"key"]];
        if (value < minV) value = minV;
        if (value > maxV) value = maxV;
        NSString *unit = row[@"unit"] ?: @"";

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.text = row[@"title"];
        title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        title.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;

        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        valueLabel.text = [NSString stringWithFormat:@"%ld%@", (long)value, unit];
        valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
        valueLabel.textColor = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        valueLabel.textAlignment = NSTextAlignmentRight;

        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = (float)minV;
        slider.maximumValue = (float)maxV;
        slider.value = (float)value;
        slider.continuous = YES;
        slider.enabled = supported;
        slider.tag = (indexPath.section << 16) | indexPath.row;
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(sliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        // Stash the value label so sliderChanged: can update it without a full reload.
        objc_setAssociatedObject(slider, "cyanideValueLabel", valueLabel, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(slider, "cyanideUnit", unit, OBJC_ASSOCIATION_RETAIN);
        objc_setAssociatedObject(slider, "cyanideStep", @(step), OBJC_ASSOCIATION_RETAIN);

        [cell.contentView addSubview:title];
        [cell.contentView addSubview:valueLabel];
        [cell.contentView addSubview:slider];

        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor      constraintEqualToAnchor:m.leadingAnchor],
            [title.topAnchor          constraintEqualToAnchor:m.topAnchor],
            [valueLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [valueLabel.centerYAnchor  constraintEqualToAnchor:title.centerYAnchor],
            [valueLabel.leadingAnchor  constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8],
            [slider.leadingAnchor   constraintEqualToAnchor:m.leadingAnchor],
            [slider.trailingAnchor  constraintEqualToAnchor:m.trailingAnchor],
            [slider.topAnchor       constraintEqualToAnchor:title.bottomAnchor constant:4],
            [slider.bottomAnchor    constraintEqualToAnchor:m.bottomAnchor],
        ]];
        return cell;
    }

    if ([kind isEqualToString:@"segmented"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"segmented" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = nil;
        for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:powercuff_levels()];
        seg.translatesAutoresizingMaskIntoConstraints = NO;
        NSString *cur = [d stringForKey:row[@"key"]] ?: @"nominal";
        NSUInteger idx = [powercuff_levels() indexOfObject:cur];
        if (idx == NSNotFound) idx = [powercuff_levels() indexOfObject:@"nominal"];
        seg.selectedSegmentIndex = (NSInteger)idx;
        seg.enabled = supported;
        [seg addTarget:self action:@selector(powercuffSegChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:seg];
        [NSLayoutConstraint activateConstraints:@[
            [seg.leadingAnchor  constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [seg.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [seg.topAnchor      constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.topAnchor],
            [seg.bottomAnchor   constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.bottomAnchor],
        ]];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"toggle" forIndexPath:dequeuePath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL rowEnabled = supported && ![row[@"disabled"] boolValue];
    cell.userInteractionEnabled = rowEnabled;
    NSString *subtitle = row[@"subtitle"];
    if (subtitle.length > 0) {
        UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];
        config.text = row[@"title"];
        config.secondaryText = subtitle;
        config.textToSecondaryTextVerticalPadding = 3;
        config.textProperties.color = rowEnabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        config.secondaryTextProperties.color = rowEnabled ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        config.secondaryTextProperties.font = [UIFont systemFontOfSize:12];
        config.secondaryTextProperties.numberOfLines = 0;
        cell.contentConfiguration = config;
    } else {
        cell.contentConfiguration = nil;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
        cell.textLabel.textColor = rowEnabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    }
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = rowEnabled && [d boolForKey:row[@"key"]];
    sw.enabled = rowEnabled;
    sw.tag = (indexPath.section << 16) | indexPath.row;
    [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

#pragma mark - Actions

- (NSDictionary *)rowForTag:(NSInteger)tag
{
    NSInteger section = (tag >> 16) & 0xFFFF;
    NSInteger row = tag & 0xFFFF;
    return [self rowsForSection:section][row];
}

- (void)presentApplyLogIfRunning
{
    // Skip if a modal is already up (e.g. the user just toggled a different
    // switch and the log is already visible).
    if (self.presentedViewController) return;
    // Skip if there's no live SpringBoard session — the change won't fire any
    // RemoteCall until the user runs the chain, so there's nothing to watch.
    if (!g_springboard_rc_ready) return;

    [self presentActivityLog];
}

- (void)presentActivityLog
{
    [self presentActivityLogWithCompletion:nil];
}

- (void)presentActivityLogWithCompletion:(dispatch_block_t)completion
{
    if (self.presentedViewController) {
        if ([self.presentedViewController isKindOfClass:UIAlertController.class]) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf presentActivityLogWithCompletion:completion];
            });
            return;
        }
        if (completion) completion();
        return;
    }

    InstallProgressViewController *vc = [[InstallProgressViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationAutomatic;
    [self presentViewController:nav animated:YES completion:completion];
}

- (void)toggleChanged:(UISwitch *)sender
{
    if (!settings_device_supported()) {
        sender.on = !sender.isOn;
        printf("[SETTINGS] toggle blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSDictionary *row = [self rowForTag:sender.tag];
    if ([row[@"disabled"] boolValue]) {
        sender.on = !sender.isOn;
        printf("[SETTINGS] toggle blocked: %s is in progress\n", [row[@"key"] UTF8String]);
        return;
    }
    NSString *key = row[@"key"];
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    printf("[SETTINGS] toggle %s=%d\n", key.UTF8String, sender.isOn);
    if ([key isEqualToString:kSettingsKeepAlive]) {
        ds_keepalive_apply_enabled(sender.isOn);
        return;
    }
    if (settings_key_affects_package_state(key)) {
        if (!sender.isOn) settings_mark_tweak_applied(key, NO);
        settings_notify_package_queue_changed_async();
    }
    settings_schedule_live_apply_for_key(key);
    [self presentApplyLogIfRunning];
}

- (void)sliderChanged:(UISlider *)sender
{
    if (!settings_device_supported()) return;
    NSNumber *stepNum = objc_getAssociatedObject(sender, "cyanideStep");
    NSInteger step = stepNum ? [stepNum integerValue] : 1;
    if (step <= 0) step = 1;
    NSInteger value = (NSInteger)llround((double)sender.value / (double)step) * step;
    UILabel *valueLabel = objc_getAssociatedObject(sender, "cyanideValueLabel");
    NSString *unit = objc_getAssociatedObject(sender, "cyanideUnit") ?: @"";
    if (valueLabel) {
        valueLabel.text = [NSString stringWithFormat:@"%ld%@", (long)value, unit];
    }
}

- (void)sliderEnded:(UISlider *)sender
{
    if (!settings_device_supported()) return;
    NSDictionary *row = [self rowForTag:sender.tag];
    if (!row) return;
    NSString *key = row[@"key"];
    NSInteger step = [row[@"step"] integerValue]; if (step <= 0) step = 1;
    NSInteger value = (NSInteger)llround((double)sender.value / (double)step) * step;
    sender.value = (float)value;  // snap thumb to the step grid
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL showLocationLog = settings_key_is_location_sim(key) && settings_location_sim_is_active(d);
    [d setInteger:value forKey:key];
    printf("[SETTINGS] slider %s=%ld\n", key.UTF8String, (long)value);
    if (showLocationLog) {
        [self presentActivityLogWithCompletion:^{
            settings_schedule_live_apply_for_key(key);
        }];
    } else {
        settings_schedule_live_apply_for_key(key);
        [self presentApplyLogIfRunning];
    }
    if (settings_key_is_location_sim(key)) {
        [self.tableView reloadData];
    }
}

- (void)presentNumberEntryForRow:(NSDictionary *)row section:(NSInteger)section
{
    NSString *key = row[@"key"];
    if (key.length == 0) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    double current = settings_number_row_current_value(row, d);
    NSString *minText = settings_number_row_value_string(row, [row[@"min"] doubleValue], YES);
    NSString *maxText = settings_number_row_value_string(row, [row[@"max"] doubleValue], YES);
    NSString *message = [NSString stringWithFormat:@"Enter %@ to %@.%@%@",
                         minText,
                         maxText,
                         [row[@"subtitle"] length] > 0 ? @"\n\n" : @"",
                         row[@"subtitle"] ?: @""];

    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:row[@"title"]
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = settings_number_row_value_string(row, current, NO);
        field.placeholder = settings_number_row_value_string(row, [row[@"default"] doubleValue], NO);
        field.keyboardType = (row[@"precision"] && [row[@"precision"] integerValue] > 0)
            ? UIKeyboardTypeDecimalPad
            : UIKeyboardTypeNumberPad;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        [field selectAll:nil];
    }];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Save"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSString *input = ac.textFields.firstObject.text ?: @"";
        NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *normalizedInput = [trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."];
        NSScanner *scanner = [NSScanner scannerWithString:normalizedInput];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

        double parsed = 0.0;
        BOOL ok = [scanner scanDouble:&parsed];
        [scanner scanCharactersFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet intoString:NULL];
        if (!ok || ![scanner isAtEnd] || !isfinite(parsed)) {
            UIAlertController *err = [UIAlertController
                alertControllerWithTitle:@"Invalid Number"
                                 message:@"Enter a plain number, then try again."
                          preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                           dispatch_get_main_queue(), ^{
                settings_present_controller(err, strongSelf);
            });
            return;
        }

        double value = settings_number_row_normalized_value(row, parsed);
        if ([key isEqualToString:kSettingsDSDragCoefficientValue] ||
            (row[@"precision"] && [row[@"precision"] integerValue] > 0)) {
            [d setDouble:value forKey:key];
        } else {
            [d setInteger:(NSInteger)llround(value) forKey:key];
        }
        [d synchronize];

        NSString *valueText = settings_number_row_value_string(row, value, YES);
        printf("[SETTINGS] number %s=%s\n", key.UTF8String, valueText.UTF8String);
        settings_schedule_live_apply_for_key(key);
        [strongSelf reloadSectionOrAll:section];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            [strongSelf presentApplyLogIfRunning];
        });
    }]];
    settings_present_controller(ac, self);
}

- (void)reloadLocationSimUI
{
    [self.tableView reloadData];
    [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                        object:[PackageQueue sharedQueue]];
}

- (void)reloadIPADecryptorUI
{
    [self reloadSectionOrAll:SectionIPADecryptor];
    [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                        object:[PackageQueue sharedQueue]];
}

- (void)presentIPADecryptorAppPicker
{
    NSArray<NSDictionary<NSString *, NSString *> *> *apps = ipadecryptor_installed_apps();
    if (apps.count == 0) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"No Apps Found"
                             message:@"Cyanide could not list installed user apps yet. Run the chain once, then try again."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        settings_present_controller(ac, self);
        return;
    }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Choose App"
                                                                message:@"Select the installed app to probe/decrypt."
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSUInteger shown = 0;
    for (NSDictionary<NSString *, NSString *> *app in apps) {
        if (shown >= 60) break;
        NSString *bundleID = app[@"bundleID"];
        if (bundleID.length == 0) continue;
        NSString *name = app[@"name"].length > 0 ? app[@"name"] : bundleID;
        NSString *title = name;
        if (![name isEqualToString:bundleID]) {
            title = [NSString stringWithFormat:@"%@ — %@", name, bundleID];
        }
        [ac addAction:[UIAlertAction actionWithTitle:title
                                               style:UIAlertActionStyleDefault
                                             handler:^(__unused UIAlertAction *action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
            [d setObject:bundleID forKey:kSettingsIPADecryptorTargetBundleID];
            [d synchronize];
            log_user("[IPADEC] Selected %s (%s)\n", name.UTF8String, bundleID.UTF8String);
            [strongSelf reloadIPADecryptorUI];
        }]];
        shown++;
    }
    if (apps.count > shown) {
        [ac addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%lu more hidden — refine picker later",
                                                                             (unsigned long)(apps.count - shown)]
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = self.view.bounds;
    settings_present_controller(ac, self);
}

- (void)saveIPADecryptorAppStoreMetadata:(NSDictionary<NSString *, NSString *> *)meta
                                   input:(NSString *)input
{
    if (meta.count == 0) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *bundleID = meta[@"bundleID"] ?: @"";
    [d setObject:input ?: @"" forKey:kSettingsIPADecryptorAppStoreInput];
    [d setObject:meta[@"appStoreID"] ?: @"" forKey:kSettingsIPADecryptorAppStoreID];
    [d setObject:meta[@"name"] ?: @"" forKey:kSettingsIPADecryptorAppStoreName];
    [d setObject:meta[@"version"] ?: @"" forKey:kSettingsIPADecryptorAppStoreVersion];
    [d setObject:meta[@"trackURL"] ?: @"" forKey:kSettingsIPADecryptorAppStoreURL];
    [d setObject:@"" forKey:kSettingsIPADecryptorDownloadedIPAPath];
    [d setObject:@"Resolved App Store metadata. Download not started yet."
          forKey:kSettingsIPADecryptorDownloadStatus];
    if (bundleID.length > 0) {
        [d setObject:bundleID forKey:kSettingsIPADecryptorTargetBundleID];
    }
    [d synchronize];
}

- (void)saveIPADecryptorDownloadStatus:(NSString *)status
                         downloadedIPA:(NSString *)downloadedPath
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:status.length > 0 ? status : @"Download status unavailable."
          forKey:kSettingsIPADecryptorDownloadStatus];
    if (downloadedPath.length > 0) {
        [d setObject:downloadedPath forKey:kSettingsIPADecryptorDownloadedIPAPath];
    }
    [d synchronize];
}

- (void)presentIPADecryptorSignInPrompt
{
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"App Store Sign In"
                         message:@"Sign in with the Apple ID that owns or can download the app. If Apple asks for two-factor authentication, Cyanide will prompt for the code next."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Apple ID email";
        field.keyboardType = UIKeyboardTypeEmailAddress;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Password";
        field.secureTextEntry = YES;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Sign In"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf runIPADecryptorSignInEmail:ac.textFields[0].text
                                      password:ac.textFields[1].text
                                      authCode:nil];
    }]];
    settings_present_controller(ac, self);
}

- (void)presentIPADecryptorTwoFactorPromptForEmail:(NSString *)email
                                          password:(NSString *)password
{
    NSString *trimmedEmail = [email ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *shownEmail = trimmedEmail.length > 0 ? trimmedEmail : @"this Apple ID";
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Two-Factor Code"
                         message:[NSString stringWithFormat:@"Enter the 6-digit code Apple sent for %@.", shownEmail]
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"2FA code";
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.textContentType = UITextContentTypeOneTimeCode;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Verify"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *rawCode = ac.textFields.firstObject.text ?: @"";
        NSMutableString *code = [NSMutableString string];
        NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
        for (NSUInteger i = 0; i < rawCode.length; i++) {
            unichar c = [rawCode characterAtIndex:i];
            if ([digits characterIsMember:c]) [code appendFormat:@"%C", c];
        }
        if (code.length == 0) {
            UIAlertController *retry = [UIAlertController
                alertControllerWithTitle:@"Code Required"
                                 message:@"Enter the 6-digit Apple verification code."
                          preferredStyle:UIAlertControllerStyleAlert];
            [retry addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                [strongSelf presentIPADecryptorTwoFactorPromptForEmail:email password:password];
            }]];
            settings_present_controller(retry, strongSelf);
            return;
        }
        [strongSelf runIPADecryptorSignInEmail:email
                                      password:password
                                      authCode:code];
    }]];
    settings_present_controller(ac, self);
}

- (void)runIPADecryptorSignInEmail:(NSString *)email
                          password:(NSString *)password
                          authCode:(NSString *)authCode
{
    static volatile int sIPADecryptorSignInInFlight = 0;
    if (__sync_lock_test_and_set(&sIPADecryptorSignInInFlight, 1)) {
        log_user("[IPADEC] App Store sign-in already running.\n");
        return;
    }

    NSString *emailCopy = [email copy] ?: @"";
    NSString *passwordCopy = [password copy] ?: @"";
    NSString *authCodeCopy = [authCode copy] ?: @"";
    __weak typeof(self) weakSelf = self;
    log_user("[IPADEC] Signing in to App Store as %s%s\n",
             emailCopy.UTF8String,
             authCodeCopy.length > 0 ? " with 2FA code" : "");
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL actionOK = NO;
        BOOL actionLockAcquired = NO;
        NSString *completionMessage = nil;
        @try {
            actionLockAcquired = settings_try_claim_actions_lock("IPA Decryptor App Store sign-in",
                                                                 "[IPADEC] Another action is already running.");
            if (!actionLockAcquired) {
                completionMessage = @"Sign-in blocked: another action is still running.";
                return;
            }
            NSString *message = nil;
            actionOK = ipadecryptor_login_app_store(emailCopy, passwordCopy, authCodeCopy, &message);
            completionMessage = message ?: (actionOK ? @"App Store sign-in complete." : @"App Store sign-in failed.");
            log_user("[IPADEC] %s\n", completionMessage.UTF8String);
        } @finally {
            if (actionLockAcquired) settings_release_actions_lock();
            __sync_lock_release(&sIPADecryptorSignInInFlight);
            BOOL messageRequestsTwoFactor =
                completionMessage.length > 0 &&
                [completionMessage rangeOfString:@"Two-factor code required"
                                         options:NSCaseInsensitiveSearch].location != NSNotFound;
            BOOL needsTwoFactor = (!actionOK &&
                                   authCodeCopy.length == 0 &&
                                   messageRequestsTwoFactor);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf reloadIPADecryptorUI];
                NSDictionary *info = @{
                    kSettingsActionsDidCompleteSuccessKey: @(actionOK),
                    kSettingsActionsDidCompleteMessageKey: completionMessage ?: @""
                };
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:kSettingsActionsDidCompleteNotification
                                  object:nil
                                userInfo:info];
                if (needsTwoFactor) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                                   dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) laterSelf = weakSelf;
                        [laterSelf presentIPADecryptorTwoFactorPromptForEmail:emailCopy
                                                                      password:passwordCopy];
                    });
                }
            });
        }
    });
}

- (void)presentIPADecryptorAppStoreLinkPrompt
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"App Store Link"
                         message:@"Paste an App Store URL like https://apps.apple.com/us/app/name/id123456789, or enter the numeric app ID. Cyanide will resolve it, then attempt the IPA download path."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"App Store URL or app ID";
        field.text = [d stringForKey:kSettingsIPADecryptorAppStoreInput] ?: @"";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Resolve"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSString *input = ac.textFields.firstObject.text ?: @"";
        [strongSelf runIPADecryptorResolveAppStoreInput:input];
    }]];
    settings_present_controller(ac, self);
}

- (void)runIPADecryptorResolveAppStoreInput:(NSString *)input
{
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        log_user("[IPADEC] Paste an App Store link first.\n");
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t startAction = ^{
        log_user("[IPADEC] Resolving App Store input: %s\n", trimmed.UTF8String);
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            BOOL actionOK = NO;
            BOOL actionLockAcquired = NO;
            NSString *completionMessage = nil;
            NSDictionary<NSString *, NSString *> *meta = nil;
            BOOL downloadOK = NO;
            NSString *downloadedPath = nil;
            NSString *downloadMessage = nil;
            @try {
                actionLockAcquired = settings_try_claim_actions_lock("IPA Decryptor App Store lookup",
                                                                     "[IPADEC] Another action is already running.");
                if (!actionLockAcquired) {
                    completionMessage = @"App Store lookup blocked: another action is still running.";
                    return;
                }

                NSString *message = nil;
                meta = ipadecryptor_resolve_app_store_input(trimmed, &message);
                actionOK = meta != nil;
                completionMessage = message ?: (actionOK ? @"App Store link resolved." : @"App Store lookup failed.");
                if (meta) {
                    log_user("[IPADEC] Resolved target bundle id: %s\n",
                             (meta[@"bundleID"] ?: @"").UTF8String);
                    log_user("[IPADEC] Starting IPA download path after resolve.\n");
                    downloadOK = ipadecryptor_download_app_store_ipa(trimmed,
                                                                     &downloadedPath,
                                                                     &downloadMessage);
                    if (downloadOK) {
                        completionMessage = downloadMessage ?: @"IPA downloaded.";
                    } else {
                        completionMessage = [NSString stringWithFormat:@"Link resolved. %@",
                                                                       downloadMessage ?: @"IPA download did not start."];
                    }
                }
            } @finally {
                if (actionLockAcquired) settings_release_actions_lock();
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (meta) [strongSelf saveIPADecryptorAppStoreMetadata:meta input:trimmed];
                    if (meta) {
                        [strongSelf saveIPADecryptorDownloadStatus:downloadMessage ?: (downloadOK ? @"IPA downloaded." : @"IPA download did not start.")
                                                     downloadedIPA:downloadOK ? downloadedPath : nil];
                    }
                    [strongSelf reloadIPADecryptorUI];
                    NSDictionary *info = @{
                        kSettingsActionsDidCompleteSuccessKey: @(actionOK && downloadOK),
                        kSettingsActionsDidCompleteMessageKey: completionMessage ?: @""
                    };
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kSettingsActionsDidCompleteNotification
                                      object:nil
                                    userInfo:info];
                });
            }
        });
    };
    [self presentActivityLogWithCompletion:startAction];
}

- (void)runIPADecryptorAction:(NSString *)action
{
    if (action.length == 0) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    BOOL downloadIPA = [action isEqualToString:@"ipadec-download"];
    NSString *bundleID = [d stringForKey:kSettingsIPADecryptorTargetBundleID];
    NSString *appStoreInput = [d stringForKey:kSettingsIPADecryptorAppStoreInput];
    if (!downloadIPA && bundleID.length == 0) {
        log_user("[IPADEC] Select an installed app first.\n");
        return;
    }
    if (downloadIPA && appStoreInput.length == 0) {
        log_user("[IPADEC] Paste an App Store link first.\n");
        return;
    }

    BOOL startDecrypt = [action isEqualToString:@"ipadec-start"];
    BOOL probeOnly = [action isEqualToString:@"ipadec-probe"];
    if (!startDecrypt && !probeOnly && !downloadIPA) return;

    static volatile int sIPADecryptorInFlight = 0;
    if (__sync_lock_test_and_set(&sIPADecryptorInFlight, 1)) {
        log_user("[IPADEC] Another IPA Decryptor action is already running.\n");
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t startAction = ^{
        log_user("[IPADEC] %s %s\n",
                 downloadIPA ? "Downloading App Store IPA for" : (startDecrypt ? "Starting decrypt pipeline for" : "Probing"),
                 downloadIPA ? appStoreInput.UTF8String : bundleID.UTF8String);
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            BOOL actionOK = NO;
            BOOL actionLockAcquired = NO;
            NSString *completionMessage = nil;
            NSString *downloadedPath = nil;
            @try {
                actionLockAcquired = settings_try_claim_actions_lock("IPA Decryptor action",
                                                                     "[IPADEC] Another action is already running.");
                if (!actionLockAcquired) {
                    completionMessage = @"IPA Decryptor blocked: another action is still running.";
                    return;
                }
                if (startDecrypt && !settings_ensure_kexploit()) {
                    log_user("[IPADEC] Failed: kernel primitives not acquired. Please run the chain again.\n");
                    completionMessage = @"IPA Decryptor failed: kernel primitives were not acquired.";
                    return;
                }

                NSString *message = nil;
                if (downloadIPA) {
                    actionOK = ipadecryptor_download_app_store_ipa(appStoreInput,
                                                                   &downloadedPath,
                                                                   &message);
                } else {
                    actionOK = startDecrypt
                        ? ipadecryptor_start_decrypt_installed_app(bundleID, &message)
                        : ipadecryptor_probe_installed_app(bundleID, &message);
                }
                completionMessage = message ?: (actionOK ? @"IPA Decryptor action finished." : @"IPA Decryptor action did not complete.");
            } @finally {
                if (actionLockAcquired) settings_release_actions_lock();
                __sync_lock_release(&sIPADecryptorInFlight);
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (downloadIPA) {
                        [strongSelf saveIPADecryptorDownloadStatus:completionMessage
                                                     downloadedIPA:(actionOK ? downloadedPath : nil)];
                    }
                    [strongSelf reloadIPADecryptorUI];
                    NSDictionary *info = @{
                        kSettingsActionsDidCompleteSuccessKey: @(actionOK),
                        kSettingsActionsDidCompleteMessageKey: completionMessage ?: @""
                    };
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kSettingsActionsDidCompleteNotification
                                      object:nil
                                    userInfo:info];
                });
            }
        });
    };
    [self presentActivityLogWithCompletion:startAction];
}

- (void)runGravityLiteAction:(NSString *)action
{
    if (!settings_device_supported()) return;
    BOOL restore = [action isEqualToString:@"gravitylite-restore"];
    BOOL explosion = [action isEqualToString:@"gravitylite-explosion"];
    if (!restore && !explosion) return;

    dispatch_block_t startAction = ^{
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            __block BOOL actionOK = NO;
            BOOL actionLockAcquired = NO;
            NSString *completionMessage = restore
                ? @"Gravity Lite restore failed. Check the log."
                : @"Gravity Lite explosion failed. Check the log.";
            @try {
                actionLockAcquired = settings_try_claim_actions_lock("Gravity Lite action",
                                                                     "[GRAVITY] Another action is already running.");
                if (!actionLockAcquired) {
                    completionMessage = @"Gravity Lite blocked: Apply Tweaks is still running.";
                    return;
                }
                if (!settings_ensure_kexploit()) {
                    log_user("[GRAVITY] Failed: kernel primitives not acquired. Please try running chain again.\n");
                    completionMessage = @"Gravity Lite failed: kernel primitives were not acquired. Please try running chain again.";
                    return;
                }

                @synchronized (settings_rc_lock()) {
                    if (g_springboard_rc_ready) {
                        actionOK = restore
                            ? gravitylite_stop_in_session()
                            : gravitylite_explosion_in_session(settings_gravitylite_config_from_defaults(d).explosionForce);
                    } else {
                        RemoteCallSession *springboardSession =
                            [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                     useMigFilterBypass:NO
                                                firstExceptionTimeoutMS:kSettingsSpringBoardRCFirstExceptionTimeoutMS];
                        if (!springboardSession) {
                            log_user("[GRAVITY] SpringBoard not reachable.\n");
                        } else {
                            remote_call_with_session(springboardSession, ^{
                                actionOK = restore
                                    ? gravitylite_stop_in_session()
                                    : gravitylite_explosion_in_session(settings_gravitylite_config_from_defaults(d).explosionForce);
                            });
                            [springboardSession destroyRemoteCall];
                        }
                    }
                }

                if (restore) {
                    __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
                    settings_stop_gravity_motion();
                    settings_mark_tweak_applied(kSettingsGravityLiteEnabled, NO);
                    completionMessage = actionOK
                        ? @"Gravity Lite restored the icon layout."
                        : @"Gravity Lite restore found no active state.";
                    log_user("%s Gravity Lite restore %s.\n",
                             actionOK ? "[OK]" : "[WARN]",
                             actionOK ? "completed" : "found no active state");
                } else {
                    completionMessage = actionOK
                        ? @"Gravity Lite explosion pulse sent."
                        : @"Gravity Lite explosion found no active state.";
                    log_user("%s Gravity Lite explosion %s.\n",
                             actionOK ? "[OK]" : "[WARN]",
                             actionOK ? "sent" : "found no active state");
                }
            } @finally {
                if (actionLockAcquired) settings_release_actions_lock();
                settings_notify_package_queue_changed_async();
                settings_post_actions_complete_async(actionOK, completionMessage);
            }
        });
    };
    [self presentActivityLogWithCompletion:startAction];
}

- (void)runLocationSimApply:(BOOL)apply
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (apply && !settings_location_sim_install_allowed()) {
        log_user("[LOCSIM] Location Simulator is unavailable in this build.\n");
        return;
    }

    static volatile int sLocSimButtonInFlight = 0;
    if (__sync_lock_test_and_set(&sLocSimButtonInFlight, 1)) {
        log_user("[LOCSIM] A Location Simulator action is already running.\n");
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t startAction = ^{
        log_user("[LOCSIM] %s %s.\n",
                 apply ? "Simulating" : "Restoring",
                 apply ? settings_location_sim_target_summary(d).UTF8String : "real location");
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            BOOL actionOK = NO;
            BOOL actionLockAcquired = NO;
            NSString *completionMessage = apply
                ? @"Location Simulator applied."
                : @"Restore request sent. Real location may take a few minutes.";
            @try {
                actionLockAcquired = settings_try_claim_actions_lock("Location Simulator action",
                                                                     "[LOCSIM] Another action is already running.");
                if (!actionLockAcquired) {
                    completionMessage = @"Location Simulator blocked: Apply Tweaks is still running.";
                    return;
                }
                if (!settings_ensure_kexploit()) {
                    log_user("[LOCSIM] Failed: kernel primitives not acquired. Please try running chain again.\n");
                    completionMessage = @"Location Simulator failed: kernel primitives were not acquired. Please try running chain again.";
                    return;
                }

                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    settings_destroy_springboard_remote_call_locked_internal("switching to Location Simulator", NO);
                    ok = apply
                        ? settings_apply_location_sim_from_defaults_locked(d)
                        : settings_stop_location_sim_from_defaults_locked(d);
                    if (ok) {
                        if (apply) {
                            [d setBool:YES forKey:kSettingsLocationSimStarted];
                        } else {
                            [d setBool:NO forKey:kSettingsLocationSimStarted];
                        }
                        [d synchronize];
                    }
                }
                actionOK = ok;
                completionMessage = apply
                    ? (ok ? @"Location Simulator applied." : @"Location Simulator failed. Check the log.")
                    : (ok ? @"Restore request sent. Real location may take a few minutes." : @"Restore failed. Check the log.");
                log_user("%s Location Simulator %s.\n",
                         ok ? "[OK]" : "[WARN]",
                         apply ? (ok ? "applied" : "did not apply cleanly")
                               : (ok ? "stopped; real location should resume" : "did not stop cleanly"));
            } @finally {
                if (actionLockAcquired) settings_release_actions_lock();
                __sync_lock_release(&sLocSimButtonInFlight);
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    [strongSelf reloadLocationSimUI];
                    NSDictionary *info = @{
                        kSettingsActionsDidCompleteSuccessKey: @(actionOK),
                        kSettingsActionsDidCompleteMessageKey: completionMessage ?: @""
                    };
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kSettingsActionsDidCompleteNotification
                                      object:nil
                                    userInfo:info];
                });
            }
        });
    };
    [self presentActivityLogWithCompletion:startAction];
}

- (void)runLocationSimUberStealth:(BOOL)enable
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (enable && !settings_location_sim_install_allowed()) {
        log_user("[LOCSIM] Location Simulator is unavailable in this build.\n");
        return;
    }

    static volatile int sLocSimUberStealthInFlight = 0;
    if (__sync_lock_test_and_set(&sLocSimUberStealthInFlight, 1)) {
        log_user("[LOCSIM] A Strict App Mode action is already running.\n");
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t startAction = ^{
        log_user("[LOCSIM] %s Strict App Mode for %s.\n",
                 enable ? "Priming" : "Disabling",
                 enable ? settings_location_sim_target_summary(d).UTF8String : "the running process");
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            BOOL actionOK = NO;
            BOOL actionLockAcquired = NO;
            NSString *completionMessage = enable
                ? @"Strict App Mode failed. Check the log."
                : @"Strict App Mode disable failed. Check the log.";
            @try {
                actionLockAcquired = settings_try_claim_actions_lock("Location Simulator strict mode",
                                                                     "[LOCSIM] Another action is already running.");
                if (!actionLockAcquired) {
                    completionMessage = @"Strict App Mode blocked: Apply Tweaks is still running.";
                    return;
                }
                if (!settings_ensure_kexploit()) {
                    log_user("[LOCSIM] Strict App Mode failed: kernel primitives not acquired. Please try running chain again.\n");
                    completionMessage = @"Strict App Mode failed: kernel primitives were not acquired. Please try running chain again.";
                    return;
                }

                BOOL systemOK = NO;
                BOOL stealthOK = NO;
                @synchronized (settings_rc_lock()) {
                    settings_destroy_springboard_remote_call_locked_internal("switching to Location Simulator strict app mode", NO);
                    stealthOK = settings_prime_location_sim_uber_stealth_locked(d, enable, &systemOK);
                    if (enable && systemOK) {
                        [d setBool:YES forKey:kSettingsLocationSimStarted];
                        [d synchronize];
                    }
                }

                actionOK = stealthOK;
                if (enable) {
                    completionMessage = stealthOK
                        ? @"Strict mode host sweep finished. Force quit and reopen strict apps before testing."
                        : @"Strict App Mode failed. Check the log.";
                } else {
                    completionMessage = stealthOK
                        ? @"Strict mode simulation stop request sent."
                        : @"Strict App Mode disable failed. Check the log.";
                }

                log_user("%s Strict App Mode %s (hosts=%s).\n",
                         stealthOK ? "[OK]" : "[WARN]",
                         enable ? "prime finished" : "disable finished",
                         systemOK ? "ok" : "failed");
            } @finally {
                if (actionLockAcquired) settings_release_actions_lock();
                __sync_lock_release(&sLocSimUberStealthInFlight);
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    [strongSelf reloadLocationSimUI];
                    NSDictionary *info = @{
                        kSettingsActionsDidCompleteSuccessKey: @(actionOK),
                        kSettingsActionsDidCompleteMessageKey: completionMessage ?: @""
                    };
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kSettingsActionsDidCompleteNotification
                                      object:nil
                                    userInfo:info];
                });
            }
        });
    };
    [self presentActivityLogWithCompletion:startAction];
}

- (void)setLocationSimTargetLatitude:(double)latitude
                            longitude:(double)longitude
                                 name:(NSString *)name
                        applyIfActive:(BOOL)applyIfActive
{
    if (!settings_location_sim_coordinates_valid(latitude, longitude)) {
        log_user("[LOCSIM] Invalid coordinates: lat=%f lon=%f\n", latitude, longitude);
        return;
    }

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    BOOL wasActive = settings_location_sim_is_active(d);
    settings_location_sim_set_target(d, latitude, longitude);
    log_user("[LOCSIM] Target set to %s: %s\n",
             (name.length > 0 ? name : @"custom").UTF8String,
             settings_location_sim_target_summary(d).UTF8String);
    [self reloadLocationSimUI];
    if (applyIfActive && wasActive) {
        [self runLocationSimApply:YES];
    }
}

- (void)presentLocationSimInvalidCoordinateAlert
{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Invalid Coordinates"
                                                                message:@"Use decimal degrees. Latitude must be between -90 and 90. Longitude must be between -180 and 180."
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    settings_present_controller(ac, self);
}

- (void)presentLocationSimExactCoordinatePrompt
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Exact Coordinates"
                                                                message:@"Enter decimal degrees, or paste a pair like 40.7128, -74.0060."
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Latitude or lat, lon";
        field.text = [NSString stringWithFormat:@"%.8f", [d doubleForKey:kSettingsLocationSimLatitude]];
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Longitude";
        field.text = [NSString stringWithFormat:@"%.8f", [d doubleForKey:kSettingsLocationSimLongitude]];
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    void (^commit)(BOOL) = ^(BOOL simulateNow) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        double latitude = 0.0;
        double longitude = 0.0;
        BOOL ok = settings_location_sim_parse_coordinate_fields(ac.textFields.firstObject.text,
                                                                ac.textFields.lastObject.text,
                                                                &latitude,
                                                                &longitude);
        if (!ok) {
            [strongSelf presentLocationSimInvalidCoordinateAlert];
            return;
        }
        [strongSelf setLocationSimTargetLatitude:latitude
                                       longitude:longitude
                                            name:@"Exact coordinates"
                                   applyIfActive:!simulateNow];
        if (simulateNow) {
            [strongSelf runLocationSimApply:YES];
        }
    };

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Set Target"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        commit(NO);
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Set & Simulate"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        commit(YES);
    }]];
    settings_present_controller(ac, self);
}

- (void)presentLocationSimCityPicker
{
    NSArray<NSDictionary *> *cities = @[
        @{ @"name": @"New York City", @"lat": @40.7128, @"lon": @(-74.0060) },
        @{ @"name": @"Los Angeles", @"lat": @34.0522, @"lon": @(-118.2437) },
        @{ @"name": @"Chicago", @"lat": @41.8781, @"lon": @(-87.6298) },
        @{ @"name": @"Miami", @"lat": @25.7617, @"lon": @(-80.1918) },
        @{ @"name": @"London", @"lat": @51.5074, @"lon": @(-0.1278) },
        @{ @"name": @"Paris", @"lat": @48.8566, @"lon": @2.3522 },
        @{ @"name": @"Tokyo", @"lat": @35.6762, @"lon": @139.6503 },
        @{ @"name": @"Sydney", @"lat": @(-33.8688), @"lon": @151.2093 },
        @{ @"name": @"Dubai", @"lat": @25.2048, @"lon": @55.2708 },
        @{ @"name": @"Singapore", @"lat": @1.3521, @"lon": @103.8198 },
    ];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Major Cities"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *city in cities) {
        NSString *name = city[@"name"];
        [ac addAction:[UIAlertAction actionWithTitle:name
                                               style:UIAlertActionStyleDefault
                                             handler:^(__unused UIAlertAction *action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf setLocationSimTargetLatitude:[city[@"lat"] doubleValue]
                                           longitude:[city[@"lon"] doubleValue]
                                                name:name
                                       applyIfActive:NO];
            [strongSelf runLocationSimApply:YES];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = self.view.bounds;
    settings_present_controller(ac, self);
}

- (void)stepperChanged:(UIStepper *)sender
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] stepper blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSDictionary *row = [self rowForTag:sender.tag];
    NSInteger value = (NSInteger)sender.value;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:row[@"key"]];

    // NanoRegistry steppers are seed values for an explicit Apply button;
    // they don't drive a live SpringBoard RC loop, so skip the auto-apply.
    NSString *key = row[@"key"];
    BOOL isNano = [key isEqualToString:kSettingsNanoMaxPairing]
                || [key isEqualToString:kSettingsNanoMinPairing]
                || [key isEqualToString:kSettingsNanoMinPairingChipID]
                || [key isEqualToString:kSettingsNanoMinQuickSwitch];
    if (!isNano) {
        settings_schedule_live_apply_for_key(key);
        [self presentApplyLogIfRunning];
    }

    UIView *v = sender.superview;
    while (v && ![v isKindOfClass:UITableViewCell.class]) v = v.superview;
    UITableViewCell *cell = (UITableViewCell *)v;
    if (cell) {
        NSString *combined = [NSString stringWithFormat:@"%@: %ld", row[@"title"], (long)value];
        NSString *subtitle = row[@"subtitle"];
        if (subtitle.length > 0 && [cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
            UIListContentConfiguration *config = (UIListContentConfiguration *)[(id<NSCopying>)cell.contentConfiguration copyWithZone:nil];
            config.text = combined;
            cell.contentConfiguration = config;
        } else {
            cell.textLabel.text = combined;
        }
    }
}

- (void)powercuffSegChanged:(UISegmentedControl *)sender
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] powercuff level blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSArray<NSString *> *levels = powercuff_levels();
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)levels.count) return;
    [[NSUserDefaults standardUserDefaults] setObject:levels[sender.selectedSegmentIndex]
                                              forKey:kSettingsPowercuffLevel];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (!self.detailMode) {
        switch ((RootSection)indexPath.section) {
            case RootSectionWarning:
                return;
            case RootSectionChangelog: {
                if (!self.changelogExpanded) {
                    self.changelogExpanded = YES;
                    [tableView reloadSections:[NSIndexSet indexSetWithIndex:RootSectionChangelog]
                             withRowAnimation:UITableViewRowAnimationAutomatic];
                    return;
                }
                NSInteger entryCount = (NSInteger)settings_changelog_entries().count;
                if (indexPath.row == entryCount) {
                    [self openReleasesPage];
                } else if (indexPath.row > entryCount) {
                    self.changelogExpanded = NO;
                    [tableView reloadSections:[NSIndexSet indexSetWithIndex:RootSectionChangelog]
                             withRowAnimation:UITableViewRowAnimationAutomatic];
                }
                return;
            }
            case RootSectionActions:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionActions];
                break;
            case RootSectionInDev:
            case RootSectionTweakBundles:
            case RootSectionSystemBundles: {
                NSArray<NSDictionary *> *bundles = (RootSection)indexPath.section == RootSectionInDev
                    ? self.inDevBundleRows
                    : ((RootSection)indexPath.section == RootSectionTweakBundles
                        ? self.tweakBundleRows
                        : self.systemBundleRows);
                NSDictionary *bundle = bundles[indexPath.row];
                NSInteger underlying = [bundle[@"section"] integerValue];
                NSString *pushTitle = bundle[@"title"];
                SettingsViewController *detail = [[SettingsViewController alloc] initWithUnderlyingSection:underlying
                                                                                              bundleTitle:pushTitle];
                [self.navigationController pushViewController:detail animated:YES];
                return;
            }
            case RootSectionPatreon:
                [self handlePatreonTapAtRow:indexPath.row];
                return;
            case RootSectionExperimental: {
                if (!settings_experimental_access_allowed()) {
                    if (cyanide_patreon_is_linked()) {
                        [[UIApplication sharedApplication] openURL:cyanide_patreon_join_url()
                                                            options:@{}
                                                  completionHandler:nil];
                    } else {
                        UIAlertController *ac = [UIAlertController
                            alertControllerWithTitle:@"Member Tier Required"
                                             message:@"Experimental tweaks are early-access for Member tier supporters on patreon.com/zeroxjf."
                                      preferredStyle:UIAlertControllerStyleAlert];
                        __weak typeof(self) weakSelf = self;
                        [ac addAction:[UIAlertAction actionWithTitle:@"Link Account"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction *a) {
                            (void)a;
                            [weakSelf handlePatreonTapAtRow:0];
                        }]];
                        [ac addAction:[UIAlertAction actionWithTitle:@"Sign Up on Patreon"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction *a) {
                            (void)a;
                            [[UIApplication sharedApplication] openURL:cyanide_patreon_join_url()
                                                               options:@{}
                                                     completionHandler:nil];
                        }]];
                        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                               style:UIAlertActionStyleCancel
                                                             handler:nil]];
                        [self presentViewController:ac animated:YES completion:nil];
                    }
                    return;
                }
                UITableViewCell *expCell = [tableView cellForRowAtIndexPath:indexPath];
                if ([expCell.accessoryView isKindOfClass:[UISwitch class]]) {
                    UISwitch *sw = (UISwitch *)expCell.accessoryView;
                    [sw setOn:!sw.isOn animated:YES];
                    [self experimentalSwitchChanged:sw];
                }
                return;
            }
            case RootSectionAbout: {
                switch (indexPath.row) {
                    case 0: [self openTwitter]; break;
                    case 1: {
                        DocsViewController *docs = [[DocsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
                        [self.navigationController pushViewController:docs animated:YES];
                        break;
                    }
                    case 2: [self showAppIconPicker]; break;
                    case 3: [self openViewLog]; break;
                    case 4: [self openShareLog]; break;
                    // Row 5: Auto-Upload — UISwitch handles it
                }
                return;
            }
            case RootSectionCount:
                return;
        }
    } else {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:self.underlyingSection];
    }

    if (!settings_device_supported() &&
        indexPath.section != SectionWarning &&
        indexPath.section != SectionOTA &&
        indexPath.section != SectionThemer) {
        printf("[SETTINGS] tap blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSArray<NSDictionary *> *rows = [self rowsForSection:indexPath.section];
    if (indexPath.row < (NSInteger)rows.count) {
        NSDictionary *row = rows[indexPath.row];
        if ([row[@"kind"] isEqualToString:@"number"]) {
            [self presentNumberEntryForRow:row section:indexPath.section];
            return;
        }
    }

    if (indexPath.section == SectionActions) {
        if (indexPath.row == 0) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Clean Up?"
                                 message:@"Stops live SpringBoard sessions and closes local KRW state. The next Run will try recovery first."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Clean Up"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                settings_queue_terminal_kexploit_cleanup("manual action");
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 1) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Respring?"
                                 message:@"Are you sure you want to respring? SpringBoard will restart."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            __weak typeof(self) weakSelf = self;
            [ac addAction:[UIAlertAction actionWithTitle:@"Respring"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
                        printf("[SETTINGS] respring blocked: actions already running\n");
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
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) return;
                        settings_show_respring_overlay(strongSelf);
                    });
                });
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 2) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Reset All Packages?"
                                 message:@"Deactivates every package and clears pending changes. Already-applied patches stay until respring or reboot. Per-tweak settings are not affected."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Reset"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                NSUInteger uninstalled = 0;
                for (Package *p in [PackageCatalog allPackages]) {
                    if (p.isInstalled || p.isQueuedForApply) {
                        [p applyCommittedState:NO];
                        uninstalled++;
                    }
                }
                NSInteger cleared = [[PackageQueue sharedQueue] pendingCount];
                [[PackageQueue sharedQueue] clear];
                log_user("[INSTALLER] Reset: deactivated %lu package(s), cleared %ld pending change(s).\n",
                         (unsigned long)uninstalled, (long)cleared);
                [self.tableView reloadData];
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 3) {
            [[UpdateChecker shared] checkForUpdatesManuallyFrom:self];
        }
    }

    if (indexPath.section == SectionOTA) {
        settings_run_ota_action(indexPath.row == 0);
        return;
    }

    if (indexPath.section == SectionNanoRegistry) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];

        if ([action isEqualToString:@"nano-load"]) {
            if (!settings_nano_load_override_enabled()) {
                log_user("[NANO] Load Current Override requires parked KRW recovery; button is disabled until recovery is available.\n");
                return;
            }
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (!settings_try_claim_actions_lock("NanoRegistry load",
                                                     "[NANO] Another action is already running.")) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                      withRowAnimation:UITableViewRowAnimationNone];
                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:kSettingsActionsDidCompleteNotification
                                          object:nil];
                    });
                    return;
                }
                @try {
                    if (!settings_ensure_kexploit_recovery_only()) {
                        log_user("[NANO] Failed: parked KRW recovery was not acquired.\n");
                    } else {
                        settings_nano_load_from_plist_into_defaults(YES);
                    }
                } @finally {
                    settings_release_actions_lock();
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                  withRowAnimation:UITableViewRowAnimationNone];
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kSettingsActionsDidCompleteNotification
                                      object:nil];
                });
            });
        } else if ([action isEqualToString:@"nano-preset-newer"]) {
            settings_nano_set_defaults_values(kNanoPresetNewerMaxPairing,
                                              kNanoPresetNewerMinPairing,
                                              kNanoPresetNewerMinPairingChipID,
                                              kNanoPresetNewerMinQuickSwitch);
            log_user("[NANO] Loaded pairing range 99/23/10/6: max=%ld min=%ld minChip=%ld minQuick=%ld. Hit Apply to write.\n",
                     (long)kNanoPresetNewerMaxPairing,
                     (long)kNanoPresetNewerMinPairing,
                     (long)kNanoPresetNewerMinPairingChipID,
                     (long)kNanoPresetNewerMinQuickSwitch);
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        } else if ([action isEqualToString:@"nano-apply"]) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Apply Pairing Override?"
                                 message:@"Saves these watchOS pairing settings on this iPhone. Respring or reboot afterwards before trying to pair."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                settings_run_nano_apply_action();
            }]];
            settings_present_controller(ac, self);
        } else if ([action isEqualToString:@"nano-probe"]) {
            settings_run_nano_probe_action();
        } else if ([action isEqualToString:@"nano-steer"]) {
            settings_run_nano_steer_action();
        } else if ([action isEqualToString:@"nano-seed"]) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Seed Compatibility Index?"
                                 message:@"Adds this phone's product type to the local NanoRegistry compatibility-index MobileAsset and saves a .cyanide.bak backup beside the original file."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Seed" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                settings_run_nano_seed_action();
            }]];
            settings_present_controller(ac, self);
        } else if ([action isEqualToString:@"nano-clear"]) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Remove Pairing Override?"
                                 message:@"Removes the saved Watch Pairing Override without touching the rest of your watch data. Respring or reboot afterwards."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
                settings_run_nano_clear_action();
            }]];
            settings_present_controller(ac, self);
        }
        return;
    }

    if (indexPath.section == SectionGravityLite) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        [self runGravityLiteAction:row[@"action"]];
        return;
    }

    if (indexPath.section == SectionLocationSim) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

        if ([action isEqualToString:@"locsim-preset-rockaway"]) {
            settings_location_sim_set_rockaway_defaults(d);
            log_user("[LOCSIM] Loaded Rockaway test point: %s\n",
                     settings_location_sim_target_summary(d).UTF8String);
            [self reloadLocationSimUI];
            [self runLocationSimApply:YES];
            return;
        }

        if ([action isEqualToString:@"locsim-set-exact"]) {
            [self presentLocationSimExactCoordinatePrompt];
            return;
        }

        if ([action isEqualToString:@"locsim-major-cities"]) {
            [self presentLocationSimCityPicker];
            return;
        }

        if ([action isEqualToString:@"locsim-apply"] ||
            [action isEqualToString:@"locsim-stop"]) {
            BOOL apply = [action isEqualToString:@"locsim-apply"];
            [self runLocationSimApply:apply];
            return;
        }

        return;
    }

    if (indexPath.section == SectionIPADecryptor) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"ipadec-choose"]) {
            [self presentIPADecryptorAppPicker];
        } else if ([action isEqualToString:@"ipadec-signin"]) {
            [self presentIPADecryptorSignInPrompt];
        } else if ([action isEqualToString:@"ipadec-clear-account"]) {
            ipadecryptor_clear_app_store_account();
            [self saveIPADecryptorDownloadStatus:@"App Store token cleared. Sign in before downloading."
                                   downloadedIPA:nil];
            [self reloadIPADecryptorUI];
        } else if ([action isEqualToString:@"ipadec-paste-link"]) {
            [self presentIPADecryptorAppStoreLinkPrompt];
        } else if ([action isEqualToString:@"ipadec-probe"] ||
                   [action isEqualToString:@"ipadec-start"] ||
                   [action isEqualToString:@"ipadec-download"]) {
            [self runIPADecryptorAction:action];
        }
        return;
    }

    if (indexPath.section == SectionTypeBanner) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"typebanner-test"]) {
            static volatile int sTbTestInFlight = 0;
            if (__sync_lock_test_and_set(&sTbTestInFlight, 1)) {
                log_user("[TYPEBANNER] Test already running — wait for the previous one to finish before tapping again.\n");
                return;
            }
            __weak typeof(self) weakSelf = self;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                BOOL actionLockAcquired = NO;
                @try {
                    actionLockAcquired = settings_try_claim_actions_lock("TypeBanner test",
                                                                         "[TYPEBANNER] Another action is already running.");
                    if (!actionLockAcquired) {
                        return;
                    }
                    if (!settings_ensure_kexploit()) {
                        log_user("[TYPEBANNER] Test failed: kernel primitives not acquired. Please try running chain again.\n");
                        return;
                    }

                    // Pause the live loop while the test runs so the one-shot
                    // diagnostics do not race the periodic banner updater.
                    BOOL liveLoopWasRunning = g_typebanner_live_running != 0;
                    if (liveLoopWasRunning) {
                        g_typebanner_live_stop_requested = 1;
                        int waitMs = 0;
                        while (g_typebanner_live_running && waitMs < 30000) {
                            usleep(100000);
                            waitMs += 100;
                        }
                        if (g_typebanner_live_running) {
                            log_user("[TYPEBANNER] Test aborted: live loop did not yield in 30s.\n");
                            return;
                        }
                    }

                    log_user("[TYPEBANNER] Test: polling imagent for typing indicators…\n");
                    NSString *detected = nil;
                    @synchronized (settings_rc_lock()) {
                        RemoteCallSession *daemonSession = [[RemoteCallSession alloc] initWithProcess:@"imagent"
                                                                                   useMigFilterBypass:NO
                                                                              firstExceptionTimeoutMS:TYPEBANNER_RC_MOBILESMS_FIRST_EXCEPTION_TIMEOUT_MS
                                                                                    originalThreadOnly:YES];
                        if (!daemonSession) {
                            RemoteCallInitFailure failure = remote_call_last_init_failure();
                            uint32_t pid = remote_call_last_init_failure_pid();
                            if (failure == RemoteCallInitFailureProcessMissing) {
                                log_user("[TYPEBANNER] imagent is not running.\n");
                            } else if (failure == RemoteCallInitFailureFirstExceptionTimeout && pid != 0) {
                                log_user("[TYPEBANNER] imagent pid=%u did not answer the original-thread bootstrap this tick.\n",
                                         pid);
                            } else if (pid != 0) {
                                log_user("[TYPEBANNER] imagent RemoteCall init failed: %s (pid=%u)\n",
                                         remote_call_init_failure_description(failure), pid);
                            } else {
                                log_user("[TYPEBANNER] imagent RemoteCall init failed: %s\n",
                                         remote_call_init_failure_description(failure));
                            }
                        } else {
                            @try {
                                detected = typebanner_poll_in_imagent_remote_session(daemonSession);
                            } @catch (NSException *e) {
                                log_user("[TYPEBANNER] imagent poll threw: %s\n", e.reason.UTF8String);
                            }
                            if (detected.length == 0) {
                                log_user("[TYPEBANNER] No daemon typing indicator detected on this poll.\n");
                            }
                            [daemonSession destroyRemoteCall];
                        }
                    }

                    if (detected.length > 0) {
                        log_user("[TYPEBANNER] Detected typing: %s. Showing banner.\n",
                                 detected.UTF8String);
                    } else {
                        log_user("[TYPEBANNER] Showing a one-shot demo banner so you can confirm the SpringBoard render path.\n");
                    }

                    @synchronized (settings_rc_lock()) {
                        RemoteCallSession *springboardSession = [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                                                         useMigFilterBypass:NO
                                                                                    firstExceptionTimeoutMS:TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS];
                        if (!springboardSession) {
                            log_user("[TYPEBANNER] SpringBoard not reachable; cannot show banner.\n");
                        } else {
                            bool ok = false;
                            @try {
                                NSString *label = detected.length > 0 ? detected : @"TypeBanner demo";
                                ok = typebanner_show_in_springboard_remote_session(springboardSession, label);
                            } @catch (NSException *e) {
                                log_user("[TYPEBANNER] SpringBoard show threw: %s\n", e.reason.UTF8String);
                            }
                            log_user("[TYPEBANNER] show=%d. Banner auto-hides in 5s.\n", ok);
                            sleep(5);
                            @try { typebanner_hide_in_springboard_remote_session(springboardSession); } @catch (NSException *e) {}
                            [springboardSession destroyRemoteCall];
                        }
                    }

                    if (liveLoopWasRunning) {
                        log_user("[TYPEBANNER] Resuming live loop.\n");
                        g_typebanner_live_stop_requested = 0;
                        settings_start_typebanner_live_loop();
                    }
                } @finally {
                    if (actionLockAcquired) settings_release_actions_lock();
                    __sync_lock_release(&sTbTestInFlight);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                          withRowAnimation:UITableViewRowAnimationNone];
                    });
                }
            });
        }
        return;
    }

    if (indexPath.section == SectionNotificationIsland) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"notificationisland-sample"]) {
            if (!settings_notificationisland_install_allowed()) {
                log_user("[NISLAND] Notification Island is unavailable in this build or experimental access is off.\n");
                return;
            }
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                BOOL actionLockAcquired = settings_try_claim_actions_lock("Notification Island sample",
                                                                         "[NISLAND] Another action is already running.");
                if (!actionLockAcquired) {
                    return;
                }
                @try {
                    if (!settings_ensure_kexploit()) {
                        log_user("[NISLAND] Sample failed: kernel primitives not acquired. Please try running chain again.\n");
                        return;
                    }
                    bool ok = false;
                    @synchronized (settings_rc_lock()) {
                        if (!settings_ensure_springboard_remote_call_locked()) {
                            log_user("[NISLAND] SpringBoard not reachable; cannot show sample.\n");
                            return;
                        }
                        notificationisland_apply_in_session();
                        ok = notificationisland_show_sample_in_session("Notification Island", "Sample banner route");
                    }
                    log_user("%s Notification Island sample %s.\n",
                             ok ? "[OK]" : "[WARN]",
                             ok ? "started" : "did not start");
                    if (ok) settings_start_notificationisland_live_loop();
                } @finally {
                    settings_release_actions_lock();
                }
            });
        }
        return;
    }

    if (indexPath.section == SectionFastLockXLite) {
        if (!settings_fastlockx_lite_install_allowed()) {
            log_user("[FLX] FastLockX Lite is unavailable in this build or experimental access is off.\n");
            return;
        }
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        BOOL probe = [action isEqualToString:@"fastlockx-probe"];
        BOOL enableAlways = [action isEqualToString:@"fastlockx-enable"];
        BOOL disableAlways = [action isEqualToString:@"fastlockx-disable"];
        BOOL window = [action isEqualToString:@"fastlockx-window"];
        BOOL pulse = [action isEqualToString:@"fastlockx-once"] || window;
        BOOL unlock = [action isEqualToString:@"fastlockx-once"] ||
                      [action isEqualToString:@"fastlockx-unlock"] ||
                      window;
        if (!probe && !enableAlways && !disableAlways && !pulse && !unlock) return;

        [self presentActivityLog];
        UIBackgroundTaskIdentifier bgTask = [[UIApplication sharedApplication]
            beginBackgroundTaskWithName:@"FastLockX Lite"
                      expirationHandler:^{
            log_user("[FLX] Background time expired; stopping FastLockX Lite action.\n");
        }];

        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            BOOL actionLockAcquired = settings_try_claim_actions_lock("FastLockX Lite",
                                                                     "[FLX] Another action is already running.");
            if (!actionLockAcquired) {
                if (bgTask != UIBackgroundTaskInvalid) {
                    [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                }
                return;
            }

            @try {
                if (!settings_ensure_kexploit()) {
                    log_user("[FLX] Failed: kernel primitives not acquired. Run the chain, then try again.\n");
                    return;
                }

                NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
                @synchronized (settings_rc_lock()) {
                    if (!settings_ensure_springboard_remote_call_locked()) {
                        log_user("[FLX] SpringBoard not reachable; cannot send FastLockX Lite request.\n");
                        return;
                    }

                    if (probe) {
                        bool ok = fastlockx_lite_probe_in_session();
                        log_user("%s FastLockX Lite probe %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "found usable primitives" : "did not find enough primitives");
                        return;
                    }

                    if (disableAlways) {
                        bool ok = fastlockx_lite_disable_always_on_in_session();
                        if (ok) {
                            [d setBool:NO forKey:kSettingsFastLockXLiteEnabled];
                            [d synchronize];
                            settings_mark_tweak_applied(kSettingsFastLockXLiteEnabled, NO);
                            settings_notify_package_queue_changed_async();
                        }
                        log_user("%s FastLockX Lite Always On %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "disabled" : "could not be disabled; respring will stop it");
                    } else if (enableAlways) {
                        FastLockXLiteConfig config = settings_fastlockx_lite_config_from_defaults(d, YES, YES);
                        config.diagnosticLogging = NO;
                        bool ok = fastlockx_lite_enable_always_on_in_session(config);
                        [d setBool:ok forKey:kSettingsFastLockXLiteEnabled];
                        [d synchronize];
                        settings_mark_tweak_applied(kSettingsFastLockXLiteEnabled, ok);
                        settings_notify_package_queue_changed_async();
                        log_user("%s FastLockX Lite Always On %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "enabled" : "failed to enable");
                    } else if (window) {
                        NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + 15.0;
                        int tick = 0;
                        log_user("[FLX] 15s auto-unlock window started. Lock the device now and let Face ID authenticate.\n");
                        while ([NSDate timeIntervalSinceReferenceDate] < deadline) {
                            if (settings_cleanup_in_progress()) {
                                log_user("[FLX] Stopping window: cleanup started.\n");
                                break;
                            }
                            FastLockXLiteConfig config = settings_fastlockx_lite_config_from_defaults(d, YES, YES);
                            config.diagnosticLogging = NO;
                            if (tick > 0) {
                                config.blockOnMusic = false;
                                config.blockOnFlashlight = false;
                                config.blockOnLowPowerMode = false;
                            }
                            bool ok = fastlockx_lite_run_in_session(config);
                            tick++;
                            printf("[FLX] window tick=%d ok=%d\n", tick, ok);
                            usleep(300000);
                        }
                        log_user("[FLX] 15s auto-unlock window stopped.\n");
                    } else {
                        FastLockXLiteConfig config = settings_fastlockx_lite_config_from_defaults(d, pulse, unlock);
                        bool ok = fastlockx_lite_run_in_session(config);
                        log_user("%s FastLockX Lite request %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "completed" : "did not complete");
                    }
                }
            } @finally {
                settings_release_actions_lock();
                if (bgTask != UIBackgroundTaskInvalid) {
                    [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    [strongSelf reloadSectionOrAll:SectionFastLockXLite];
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kSettingsActionsDidCompleteNotification
                                      object:nil];
                });
            }
        });
        return;
    }

    if (indexPath.section == SectionAppSwitcherGrid) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"appswitchergrid-restore"]) {
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setBool:NO forKey:kSettingsAppSwitcherGridEnabled];
            [d synchronize];
            settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (!g_springboard_rc_ready) {
                appswitchergrid_forget_remote_state();
                log_user("[ASG] App Switcher Grid disabled. No active SpringBoard session was available; respring restores stock if needed.\n");
                [self reloadSectionOrAll:SectionAppSwitcherGrid];
                return;
            }
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = appswitchergrid_stop_in_session();
                    log_user("%s App Switcher Grid restore %s.\n",
                             ok ? "[OK]" : "[WARN]",
                             ok ? "completed" : "did not find an active patch; respring restores stock");
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self reloadSectionOrAll:SectionAppSwitcherGrid];
                });
            });
        }
        return;
    }

    if (indexPath.section == SectionNSBar) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if ([row[@"action"] isEqualToString:@"nsbar-position"]) {
            [self presentNSBarPositionPicker];
        }
        return;
    }

    if (indexPath.section == SectionNiceBarLite) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"nicebar-traffic-history"]) {
            CyanideNiceBarTrafficHistoryViewController *vc = [[CyanideNiceBarTrafficHistoryViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
            return;
        }
        if ([action isEqualToString:@"nicebar-apply"]) {
            if (!g_springboard_rc_ready) {
                log_user("[NICEBAR] Needs an active SpringBoard session. Hit Run first.\n");
                return;
            }
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setBool:YES forKey:kSettingsNiceBarLiteEnabled];
            [d synchronize];
            log_user("[NICEBAR] Manual apply requested.\n");
            [self refreshNiceBarWeatherForce:YES];
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    ok = settings_apply_nicebarlite_from_defaults_locked(d);
                    settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled, ok);
                }
                log_user("%s NiceBar Lite applied now.\n", ok ? "[OK]" : "[WARN]");
                if (ok) settings_start_nicebarlite_live_loop();
                settings_notify_package_queue_changed_async();
            });
            return;
        }
        if ([action hasPrefix:@"nicebar-slot-"]) {
            NSInteger slot = [[action substringFromIndex:[@"nicebar-slot-" length]] integerValue];
            if (slot >= 0 && slot < NiceBarLiteSlotCount) {
                [self presentNiceBarSlotEditor:slot];
            }
        }
        return;
    }

    if (indexPath.section == SectionSnowBoardLite) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"sbl-select-ios6"]) {
            [self selectSnowBoardLiteIOS6Theme];
        } else if ([action isEqualToString:@"sbl-import-folder"]) {
            [self presentSnowBoardLiteFolderImporter];
        } else if ([action isEqualToString:@"sbl-import-archive"]) {
            [self presentSnowBoardLiteArchiveImporter];
        } else if ([action isEqualToString:@"sbl-clear"]) {
            [self clearSnowBoardLiteTheme];
        }
        return;
    }

    if (indexPath.section == SectionLiveWP) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"livewp-select-video"]) {
            [self presentLiveWPVideoPicker];
        } else if ([action isEqualToString:@"livewp-clear"]) {
            [self clearLiveWPVideo];
        }
        return;
    }

    if (indexPath.section == SectionThemer) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"themer-select-ios6"]) {
            [self selectBuiltInIOS6Theme];
        } else if ([action isEqualToString:@"themer-import"]) {
            [self presentThemerImporter];
        } else if ([action isEqualToString:@"themer-guide"]) {
            [self presentThemerFormatGuide];
        } else if ([action isEqualToString:@"themer-clear"]) {
            [self clearSelectedTheme];
        }
        return;
    }

    if (indexPath.section == SectionSBC) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if ([row[@"kind"] isEqualToString:@"button"]) {
            settings_reset_sbc_defaults();
            // In detail mode, SBC sits at table-view section 0.
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

@end
