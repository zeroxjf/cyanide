//
//  snowboardlite.h
//  Cyanide
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#ifndef snowboardlite_h
#define snowboardlite_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdbool.h>

extern NSString * const kSnowBoardLiteThemeBuiltinIOS6;

NSArray<NSDictionary *> *settings_sbl_load_manifest(void);
BOOL settings_sbl_save_manifest(NSArray<NSDictionary *> *themes);
NSDictionary *settings_sbl_selected_theme(void);
BOOL settings_sbl_selected_builtin_ios6(void);
NSString *settings_sbl_resolved_icons_path_for_theme(NSDictionary *theme);
NSArray<UIImage *> *settings_sbl_preview_images_for_theme(NSDictionary *theme,
                                                          BOOL builtIn,
                                                          NSUInteger limit);
BOOL settings_sbl_import_folder_theme_named(NSURL *url,
                                            NSString *displayName,
                                            NSString *sourceType,
                                            NSError **error);
BOOL settings_sbl_import_folder_theme(NSURL *url, NSError **error);
bool settings_apply_snowboardlite_from_defaults_locked(NSUserDefaults *d);

BOOL settings_snowboardlite_has_selected_theme(void);
NSString *settings_snowboardlite_selected_theme_display_name(void);

#endif /* snowboardlite_h */
