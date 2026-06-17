//
//  Cyanide-Bridging-Header.h
//  Cyanide
//
//  Swift↔ObjC bridge.
//
//  IMPORTANT: Do NOT import LogTextView.h or any header that includes it
//  (e.g. kexploit_opa334.h) — the printf-override macro breaks Swift.
//

// Settings keys, public orchestrator functions.
#import "CyanideEngine.h"

// SettingsViewController class interface (imports CyanideEngine.h itself).
#import "SettingsViewController.h"

// Patreon account state.
#import "PatreonAuth.h"

// Sparkle-style update checker.
#import "UpdateChecker.h"

// Background keep-alive daemon.
#import "DSKeepAlive.h"


// NiceBar widget settings helpers.
#import "NiceBarSettingsSupport.h"

// Theme archive unpacker.
#import "SBLArchiveExtractor.h"

// Installer notification constants.
#import "installer/PackageQueueConstants.h"

// LogTextView exposed without the printf-macro override.
#import "LogTextViewShim.h"

// ObjC shim for iOS 26+ tab bar minimize behavior (NSInvocation unavailable in Swift).
#import "TabBarMinimizeHelper.h"
