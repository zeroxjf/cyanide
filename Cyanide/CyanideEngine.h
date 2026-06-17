//
//  CyanideEngine.h
//  Cyanide
//
//  Public interface for the Cyanide orchestrator layer.
//  Imported by SettingsViewController.h, the Swift bridging header,
//  and any ObjC file that needs settings keys or engine functions.
//
//  IMPORTANT: Do NOT import LogTextView.h or any header that transitively
//  pulls in the printf-override macro — it breaks Swift compilation.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

extern NSString * const kSettingsAutoRunKexploit;
extern NSString * const kSettingsRunSandboxEscape;
extern NSString * const kSettingsRunPatchSandboxExt;
extern NSString * const kSettingsKeepAlive;

extern NSString * const kSettingsSBCEnabled;
extern NSString * const kSettingsSBCDockIcons;
extern NSString * const kSettingsSBCCols;
extern NSString * const kSettingsSBCRows;
extern NSString * const kSettingsSBCHideLabels;

extern NSString * const kSettingsPowercuffEnabled;
extern NSString * const kSettingsPowercuffLevel;

extern NSString * const kSettingsDSDisableAppLibrary;
extern NSString * const kSettingsDSDisableIconFlyIn;
extern NSString * const kSettingsDSZeroWakeAnimation;
extern NSString * const kSettingsDSZeroBacklightFade;
extern NSString * const kSettingsDSDoubleTapToLock;

extern NSString * const kSettingsDSDragCoefficientEnabled;
extern NSString * const kSettingsDSDragCoefficientValue;

extern NSString * const kSettingsLayoutExtrasEnabled;
extern NSString * const kSettingsLayoutHomeExtraLeft;
extern NSString * const kSettingsLayoutHomeExtraRight;
extern NSString * const kSettingsLayoutHomeExtraTop;
extern NSString * const kSettingsLayoutHomeExtraBottom;
extern NSString * const kSettingsLayoutDockExtraHorizontal;
extern NSString * const kSettingsLayoutHomeScalePct;
extern NSString * const kSettingsLayoutDockScalePct;

extern NSString * const kSettingsStatBarEnabled;
extern NSString * const kSettingsStatBarCelsius;
extern NSString * const kSettingsStatBarShowNet;
extern NSString * const kSettingsStatBarShowCPU;
extern NSString * const kSettingsStatBarShowLabels;
extern NSString * const kSettingsStatBarNetworkOnly;
extern NSString * const kSettingsStatBarRefreshRateSec;

extern NSString * const kSettingsNSBarEnabled;
extern NSString * const kSettingsNSBarPosition;

extern NSString * const kSettingsNiceBarLiteEnabled;

extern NSString * const kSettingsRSSIDisplayEnabled;
extern NSString * const kSettingsRSSIDisplayWifi;
extern NSString * const kSettingsRSSIDisplayCell;

extern NSString * const kSettingsAxonLiteEnabled;

extern NSString * const kSettingsTypeBannerEnabled;
extern NSString * const kSettingsNotificationIslandEnabled;
extern NSString * const kSettingsAppSwitcherGridEnabled;

extern NSString * const kSettingsGravityLiteEnabled;
extern NSString * const kSettingsGravityLiteDockEnabled;
extern NSString * const kSettingsGravityLiteMagnitudePct;
extern NSString * const kSettingsGravityLiteBouncePct;
extern NSString * const kSettingsGravityLiteFrictionPct;
extern NSString * const kSettingsGravityLiteResistancePct;
extern NSString * const kSettingsGravityLiteAngularResistancePct;

extern NSString * const kSettingsStageStripEnabled;

extern NSString * const kSettingsLocationSimEnabled;
extern NSString * const kSettingsLocationSimLatitude;
extern NSString * const kSettingsLocationSimLongitude;
extern NSString * const kSettingsLocationSimAltitude;
extern NSString * const kSettingsLocationSimHorizontalAccuracy;
extern NSString * const kSettingsLocationSimHostProcess;

extern NSString * const kSettingsThemerEnabled;
extern NSString * const kSettingsThemerThemeID;
extern NSString * const kSettingsThemerCustomThemePath;
extern NSString * const kSettingsThemerCustomThemeName;

extern NSString * const kSettingsSnowBoardLiteEnabled;
extern NSString * const kSettingsSnowBoardLiteSelectedThemeID;

extern NSString * const kSettingsLiveWPEnabled;
extern NSString * const kSettingsLiveWPVideoPath;

extern NSString * const kSettingsExperimentalTweaksEnabled;

extern NSString * const kSettingsLogUploadEnabled;

extern NSString * const kSettingsNanoMaxPairing;
extern NSString * const kSettingsNanoMinPairing;
extern NSString * const kSettingsNanoMinPairingChipID;
extern NSString * const kSettingsNanoMinQuickSwitch;

extern NSString * const kSettingsActionsDidCompleteNotification;
extern NSString * const kSettingsActionsDidCompleteSuccessKey;
extern NSString * const kSettingsActionsDidCompleteMessageKey;

// ---------------------------------------------------------------------------
// Section enum (used by SettingsViewController and PackageCatalog)
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, SettingsSection) {
    SectionWarning = 0,
    SectionLaunch,
    SectionActions,
    SectionOTA,
    SectionSBC,
    SectionStatBar,
    SectionNSBar,
    SectionNiceBarLite,
    SectionRSSI,
    SectionAxonLite,
    SectionTypeBanner,
    SectionNotificationIsland,
    SectionPowercuff,
    SectionDarkSwordTweaks,
    SectionDragCoefficient,
    SectionLayoutExtras,
    SectionNanoRegistry,
    SectionThemer,
    SectionSnowBoardLite,
    SectionLiveWP,
    SectionLocationSim,
    SectionGravityLite,
    SectionAppSwitcherGrid,
    SectionIPADecryptor,
    SectionFastLockXLite,
    SectionCount,
};

typedef NS_ENUM(NSInteger, RootSection) {
    RootSectionChangelog = 0,
    RootSectionPatreon,
    RootSectionExperimental,
    RootSectionActions,
    RootSectionTweakBundles,
    RootSectionInDev,
    RootSectionSystemBundles,
    RootSectionAbout,
    RootSectionWarning,
    RootSectionCount,
};

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

// YES if the private-tweaks submodule was compiled in (CYANIDE_PRIVATE_TWEAKS_AVAILABLE).
// Named _compiled_in to avoid shadowing the static inline in private_compat.h.
BOOL cyanide_private_tweaks_compiled_in(void);

// Write a message to the in-app log ring buffer (safe to call from Swift;
// does not use the printf-override macro).
void cyanide_log(const char * _Nonnull msg);

// ---------------------------------------------------------------------------
// Settings keys and orchestrator functions
// ---------------------------------------------------------------------------
BOOL settings_tweak_is_applied(NSString *key);
void settings_register_defaults(void);
BOOL settings_device_supported(void);
void cyanide_present_contact(UIViewController *host);
BOOL settings_apply_ota_disabled(BOOL disabled);
BOOL settings_themer_has_selected_theme(void);
NSString *settings_themer_selected_theme_display_name(void);
BOOL settings_snowboardlite_has_selected_theme(void);
NSString *settings_snowboardlite_selected_theme_display_name(void);
BOOL settings_apply_nano_registry_now(BOOL apply);
BOOL settings_apply_call_recording_sound_disabled(BOOL disabled);
BOOL settings_apply_hide_home_bar_hidden(BOOL hidden);
BOOL settings_hide_home_bar_respring_pending(void);
void settings_present_hide_home_bar_respring_prompt(UIViewController *host);
void settings_run_actions(void);
void settings_run_pending_actions(void);
void settings_destroy_springboard_remote_call(void);
void settings_destroy_springboard_remote_call_sync(void);
void settings_best_effort_termination_cleanup(const char *reason);
void settings_application_did_enter_background(void);
void settings_application_will_enter_foreground(void);
void settings_application_did_become_active(void);
