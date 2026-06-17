//
//  CyanideEngine+Internal.h
//  Cyanide
//
//  Internal symbols shared between CyanideEngine.m and SettingsViewController.m.
//  Import ONLY from Objective-C implementation files — never from Swift,
//  public headers, or the bridging header.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "tweaks/nicebarlite.h"
#import "tweaks/gravitylite.h"
#import "tweaks/darksword_drag.h"
#import "tweaks/hide_home_bar.h"
#import "tweaks/darksword_tweaks.h"
#import "tweaks/private_compat.h"

// ---------------------------------------------------------------------------
// Internal NSString constants (defined in CyanideEngine.m, used by UI layer)
// ---------------------------------------------------------------------------
extern NSString * const kCyanideLastKnownIsPatron;
extern NSString * const kSettingsCleanupStateDidChangeNotification;
extern NSString * const kSettingsFastLockXLiteBlockFlashlight;
extern NSString * const kSettingsFastLockXLiteBlockLowPower;
extern NSString * const kSettingsFastLockXLiteBlockMusic;
extern NSString * const kSettingsFastLockXLiteEnabled;
extern NSString * const kSettingsFastLockXLiteRetryInterval;
extern NSString * const kSettingsHideHomeBarMaterialKitBootTime;
extern NSString * const kSettingsIPADecryptorAppStoreID;
extern NSString * const kSettingsIPADecryptorAppStoreInput;
extern NSString * const kSettingsIPADecryptorAppStoreName;
extern NSString * const kSettingsIPADecryptorAppStoreURL;
extern NSString * const kSettingsIPADecryptorAppStoreVersion;
extern NSString * const kSettingsIPADecryptorDownloadStatus;
extern NSString * const kSettingsIPADecryptorDownloadedIPAPath;
extern NSString * const kSettingsIPADecryptorTargetBundleID;
extern NSString * const kSettingsLocationSimStarted;
extern NSString * const kSettingsNiceBarLiteCelsius;
extern NSString * const kSettingsNiceBarLiteLayoutBottomSideInset;
extern NSString * const kSettingsNiceBarLiteLayoutBottomY;
extern NSString * const kSettingsNiceBarLiteLayoutCenterX;
extern NSString * const kSettingsNiceBarLiteLayoutTopSideInset;
extern NSString * const kSettingsNiceBarLiteLayoutTopY;
extern NSString * const kSettingsNiceBarLiteSlotKindPrefix;
extern NSString * const kSettingsNiceBarLiteSlotSystemLanguagePrefix;
extern NSString * const kSettingsNiceBarLiteSlotSystemPrefix;
extern NSString * const kSettingsNiceBarLiteSlotTextPrefix;
extern NSString * const kSettingsNiceBarLiteSlotTimePrefix;
extern NSString * const kSettingsNiceBarLiteSlotWeatherLanguagePrefix;
extern NSString * const kSettingsNiceBarLiteWeatherCache;
extern NSString * const kSettingsPowercuffNominalNoticeShown;
extern NSString * const kSettingsRemoteCallStateDidChangeNotification;
extern NSString * const kThemerThemeBuiltinIOS6;
extern NSString * const kThemerThemeCustom;
extern NSString * const kThemerThemeNone;

// ---------------------------------------------------------------------------
// Internal integer constants (defined in CyanideEngine.m, used by UI layer)
// ---------------------------------------------------------------------------
extern const NSInteger kLocationSimDefaultAccuracy;
extern const NSInteger kLocationSimDefaultAltitude;
extern const NSInteger kNanoDefaultMaxPairing;
extern const NSInteger kNanoDefaultMinPairing;
extern const NSInteger kNanoDefaultMinPairingChipID;
extern const NSInteger kNanoDefaultMinQuickSwitch;
extern const NSInteger kNanoPresetNewerMaxPairing;
extern const NSInteger kNanoPresetNewerMinPairing;
extern const NSInteger kNanoPresetNewerMinPairingChipID;
extern const NSInteger kNanoPresetNewerMinQuickSwitch;
extern const NSInteger kNanoUIRowMax;
extern const NSInteger kNanoUIRowMin;
extern const NSInteger kSBCDefaultCols;
extern const NSInteger kSBCDefaultDockIcons;
extern const NSInteger kSBCDefaultRows;
extern const int kSettingsSpringBoardRCFirstExceptionTimeoutMS;
extern const NSInteger kStatBarDefaultRefreshRateSec;

// ---------------------------------------------------------------------------
// Section enum typedefs are now defined in CyanideEngine.h (public).
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Internal globals (defined in CyanideEngine.m, accessed by UI layer)
// ---------------------------------------------------------------------------
extern volatile int g_settings_actions_running;
extern volatile int g_settings_respring_cleanup_running;
extern volatile int g_settings_cleanup_running;
extern volatile int g_springboard_rc_ready;
extern BOOL g_kexploit_done;
extern volatile int g_themer_live_stop_requested;
extern volatile int g_livewp_live_stop_requested;
extern volatile int g_gravitylite_background_armed;
extern volatile int g_typebanner_live_running;
extern volatile int g_typebanner_live_stop_requested;

// ---------------------------------------------------------------------------
// Crossing-function prototypes (defined in CyanideEngine.m, called by UI)
// ---------------------------------------------------------------------------
NSArray<NSDictionary *> *settings_changelog_entries(void);
NSArray<NSString *> *powercuff_levels(void);
NSDictionary<NSString *, NSData *> *settings_themer_load_plist_theme(NSString *plistPath);
NSString *settings_app_build_string(void);
NSString *settings_app_version_string(void);
BOOL settings_apply_location_sim_from_defaults_locked(NSUserDefaults *d);
bool settings_apply_nicebarlite_from_defaults_locked(NSUserDefaults *d);
BOOL settings_cleanup_in_progress(void);
void settings_destroy_springboard_remote_call_locked_internal(const char *reason, BOOL notifyState);
double settings_drag_coefficient_value(NSUserDefaults *d);
BOOL settings_ensure_kexploit(void);
BOOL settings_ensure_kexploit_recovery_only(void);
BOOL settings_ensure_springboard_remote_call_locked(void);
BOOL settings_experimental_access_allowed(void);
BOOL settings_experimental_tweaks_enabled(void);
FastLockXLiteConfig settings_fastlockx_lite_config_from_defaults(NSUserDefaults *d, BOOL pulse, BOOL unlock);
BOOL settings_fastlockx_lite_install_allowed(void);
double settings_fastlockx_lite_retry_interval(NSUserDefaults *d);
GravityLiteConfig settings_gravitylite_config_from_defaults(NSUserDefaults *d);
NSString *settings_ipadecryptor_app_store_summary(NSUserDefaults *d);
NSString *settings_ipadecryptor_target_summary(NSUserDefaults *d);
BOOL settings_key_affects_package_state(NSString *key);
BOOL settings_key_is_location_sim(NSString *key);
NSString *settings_livewp_video_detail(void);
BOOL settings_location_sim_coordinates_valid(double latitude, double longitude);
BOOL settings_location_sim_install_allowed(void);
BOOL settings_location_sim_is_active(NSUserDefaults *d);
NSString *settings_location_sim_mode_summary(NSUserDefaults *d);
BOOL settings_location_sim_parse_coordinate_fields(NSString *latitudeText, NSString *longitudeText, double *latitudeOut, double *longitudeOut);
void settings_location_sim_set_rockaway_defaults(NSUserDefaults *d);
void settings_location_sim_set_target(NSUserDefaults *d, double latitude, double longitude);
NSString *settings_location_sim_target_summary(NSUserDefaults *d);
void settings_mark_tweak_applied(NSString *key, BOOL applied);
void settings_nano_load_from_plist_into_defaults(BOOL logResult);
BOOL settings_nano_load_override_enabled(void);
void settings_nano_set_defaults_values(NSInteger maxV, NSInteger minV, NSInteger minChipV, NSInteger minQuickV);
BOOL settings_nicebar_has_weather_slots(NSUserDefaults *d);
NSString *settings_nicebar_key(NSString *prefix, NSInteger slot);
NSString *settings_nicebar_kind_name(NSInteger kind);
void settings_nicebar_refresh_weather_if_needed(BOOL force, void (^completion)(BOOL ok, NSString *text));
NSString *settings_nicebar_slot_name(NSInteger slot);
void settings_nicebar_store_weather_result(NSUserDefaults *d, NSNumber *temp, NSNumber *code, NSString *fallbackText, BOOL fetched);
NSString *settings_nicebar_system_name(NSInteger item);
void settings_nicebar_update_weather_slot_texts(NSUserDefaults *d);
NSString *settings_nicebar_weather_text_for_slot(NSUserDefaults *d, NSInteger slot);
BOOL settings_notificationisland_install_allowed(void);
void settings_notify_cleanup_state_changed(void);
void settings_notify_package_queue_changed_async(void);
NSString *settings_nsbar_position_name(NSInteger position);
double settings_number_row_current_value(NSDictionary *row, NSUserDefaults *d);
double settings_number_row_normalized_value(NSDictionary *row, double value);
NSString *settings_number_row_value_string(NSDictionary *row, double value, BOOL includeUnit);
void settings_post_actions_complete_async(BOOL success, NSString *message);
void settings_prepare_for_respring_sync(void);
void settings_present_controller(UIViewController *controller, UIViewController *fallback);
NSString *settings_pretty_date_for_iso(NSString *iso);
BOOL settings_prime_location_sim_uber_stealth_locked(NSUserDefaults *d, BOOL enable, BOOL *systemApplyOKOut);
void settings_queue_terminal_kexploit_cleanup(const char *reason);
NSObject *settings_rc_lock(void);
void settings_release_actions_lock(void);
void settings_reset_sbc_defaults(void);
void settings_run_nano_apply_action(void);
void settings_run_nano_clear_action(void);
void settings_run_nano_probe_action(void);
void settings_run_nano_seed_action(void);
void settings_run_nano_steer_action(void);
void settings_run_ota_action(BOOL disable);
void settings_schedule_live_apply_for_key(NSString *key);
void settings_show_respring_overlay(UIViewController *fallback);
void settings_start_livewp_live_loop(void);
void settings_start_nicebarlite_live_loop(void);
void settings_start_notificationisland_live_loop(void);
void settings_start_typebanner_live_loop(void);
void settings_stop_gravity_motion(void);
BOOL settings_stop_location_sim_from_defaults_locked(NSUserDefaults *d);
NSString *settings_themer_documents_theme_root(void);
NSString *settings_themer_imported_plist_path(void);
NSString *settings_themer_imported_theme_dir(void);
BOOL settings_try_claim_actions_lock(const char *owner, const char *busyMessage);
NSString *settings_unsupported_message(void);
