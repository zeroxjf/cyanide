//
//  snowboardlite.m
//  Cyanide
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#import "snowboardlite.h"
#import "themer.h"
#import "../LogTextView.h"
#import "../SettingsViewController.h"
#import "../map_app.h"

NSString * const kSnowBoardLiteThemeBuiltinIOS6 = @"builtin-ios6";

static NSString *sbl_builtin_ios6_path(void)
{
    return [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Themes-iOS6.plist"];
}

static NSDictionary<NSString *, NSData *> *sbl_load_plist_theme(NSString *plistPath)
{
    NSError *err = nil;
    NSData *raw = [NSData dataWithContentsOfFile:plistPath options:0 error:&err];
    if (!raw) {
        printf("[SBL] resolve: failed to read plist err=%s\n",
               err.localizedDescription.UTF8String ?: "?");
        return nil;
    }
    id parsed = [NSPropertyListSerialization
        propertyListWithData:raw
                     options:NSPropertyListImmutable
                      format:NULL
                       error:&err];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        printf("[SBL] resolve: plist parse failed err=%s\n",
               err.localizedDescription.UTF8String ?: "?");
        return nil;
    }

    NSMutableDictionary<NSString *, NSData *> *out = [NSMutableDictionary dictionary];
    NSDictionary *dict = (NSDictionary *)parsed;
    for (id key in dict) {
        id value = dict[key];
        if (![key isKindOfClass:NSString.class] ||
            ![value isKindOfClass:NSData.class] ||
            [(NSData *)value length] == 0) {
            continue;
        }
        out[key] = value;
    }

    printf("[SBL] resolve: loaded plist theme entries=%lu size=%lu path=%s\n",
           (unsigned long)out.count,
           (unsigned long)raw.length,
           plistPath.UTF8String);
    return out;
}

static NSString *settings_sbl_root_dir(void)
{
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count == 0) return nil;
    return [docs.firstObject stringByAppendingPathComponent:@"SnowBoardLite"];
}

static NSString *settings_sbl_themes_dir(void)
{
    NSString *root = settings_sbl_root_dir();
    return root ? [root stringByAppendingPathComponent:@"Themes"] : nil;
}

static NSString *settings_sbl_manifest_path(void)
{
    NSString *root = settings_sbl_root_dir();
    return root ? [root stringByAppendingPathComponent:@"Manifest.plist"] : nil;
}

NSArray<NSDictionary *> *settings_sbl_load_manifest(void)
{
    NSString *path = settings_sbl_manifest_path();
    NSArray *raw = path ? [NSArray arrayWithContentsOfFile:path] : nil;
    if (![raw isKindOfClass:NSArray.class]) return @[];

    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id obj in raw) {
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *d = obj;
        NSString *themeID = d[@"id"];
        NSString *name = d[@"name"];
        NSString *iconsPath = d[@"iconsPath"];
        if (![themeID isKindOfClass:NSString.class] || themeID.length == 0) continue;
        if (![name isKindOfClass:NSString.class] || name.length == 0) continue;
        if (![iconsPath isKindOfClass:NSString.class] || iconsPath.length == 0) continue;
        [out addObject:d];
    }
    return out;
}

BOOL settings_sbl_save_manifest(NSArray<NSDictionary *> *themes)
{
    NSString *root = settings_sbl_root_dir();
    NSString *path = settings_sbl_manifest_path();
    if (!root || !path) return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]) {
        return NO;
    }
    return [themes writeToFile:path atomically:YES];
}

NSDictionary *settings_sbl_selected_theme(void)
{
    NSString *selected = [NSUserDefaults.standardUserDefaults
        stringForKey:kSettingsSnowBoardLiteSelectedThemeID];
    if (selected.length == 0) return nil;
    if ([selected isEqualToString:kSnowBoardLiteThemeBuiltinIOS6]) return nil;
    for (NSDictionary *theme in settings_sbl_load_manifest()) {
        if ([theme[@"id"] isEqualToString:selected]) return theme;
    }
    return nil;
}

BOOL settings_sbl_selected_builtin_ios6(void)
{
    NSString *selected = [NSUserDefaults.standardUserDefaults
        stringForKey:kSettingsSnowBoardLiteSelectedThemeID];
    return [selected isEqualToString:kSnowBoardLiteThemeBuiltinIOS6];
}

static NSString *settings_sbl_existing_icons_path(NSString *path)
{
    BOOL isDir = NO;
    if (path.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] &&
        isDir) {
        return path;
    }
    return nil;
}

NSString *settings_sbl_resolved_icons_path_for_theme(NSDictionary *theme)
{
    NSString *iconsPath = settings_sbl_existing_icons_path(theme[@"iconsPath"]);
    if (iconsPath.length > 0) return iconsPath;

    NSString *themeID = theme[@"id"];
    NSString *root = settings_sbl_themes_dir();
    if (themeID.length == 0 || root.length == 0) return nil;

    NSString *candidate = [[root stringByAppendingPathComponent:themeID]
        stringByAppendingPathComponent:@"Icons"];
    return settings_sbl_existing_icons_path(candidate);
}

static NSArray<NSString *> *settings_sbl_preview_bundle_order(void)
{
    return @[
        @"com.apple.mobilesafari",
        @"com.apple.MobileSMS",
        @"com.apple.mobilemail",
        @"com.apple.mobilephone",
        @"com.apple.Music",
        @"com.apple.AppStore",
        @"com.apple.Preferences",
        @"com.apple.camera",
    ];
}

static void settings_sbl_add_preview_image(NSMutableArray<UIImage *> *out,
                                           UIImage *image,
                                           NSUInteger limit)
{
    if (!image || out.count >= limit) return;
    [out addObject:image];
}

static NSArray<UIImage *> *settings_sbl_builtin_preview_images(NSUInteger limit)
{
    if (limit == 0) return @[];
    static NSArray<UIImage *> *cached = nil;
    if (cached.count >= limit) {
        return [cached subarrayWithRange:NSMakeRange(0, limit)];
    }

    NSDictionary<NSString *, NSData *> *dict = sbl_load_plist_theme(sbl_builtin_ios6_path());
    NSMutableArray<UIImage *> *out = [NSMutableArray arrayWithCapacity:limit];
    NSMutableSet<NSString *> *used = [NSMutableSet set];

    for (NSString *bundleID in settings_sbl_preview_bundle_order()) {
        NSData *data = dict[bundleID];
        UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
        settings_sbl_add_preview_image(out, image, limit);
        if (image) [used addObject:bundleID];
        if (out.count >= limit) {
            cached = [out copy];
            return out;
        }
    }

    NSArray<NSString *> *keys = [dict.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *bundleID in keys) {
        if ([used containsObject:bundleID]) continue;
        NSData *data = dict[bundleID];
        UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
        settings_sbl_add_preview_image(out, image, limit);
        if (out.count >= limit) break;
    }
    cached = [out copy];
    return out;
}

static NSArray<UIImage *> *settings_sbl_folder_preview_images(NSString *iconsPath, NSUInteger limit)
{
    if (limit == 0 || iconsPath.length == 0) return @[];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<UIImage *> *out = [NSMutableArray arrayWithCapacity:limit];
    NSMutableSet<NSString *> *used = [NSMutableSet set];

    for (NSString *bundleID in settings_sbl_preview_bundle_order()) {
        NSString *name = [bundleID stringByAppendingPathExtension:@"png"];
        NSString *path = [iconsPath stringByAppendingPathComponent:name];
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        settings_sbl_add_preview_image(out, image, limit);
        if (image) [used addObject:name.lowercaseString];
        if (out.count >= limit) return out;
    }

    NSArray<NSString *> *files = [[fm contentsOfDirectoryAtPath:iconsPath error:nil]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *file in files) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        if ([used containsObject:file.lowercaseString]) continue;
        UIImage *image = [UIImage imageWithContentsOfFile:[iconsPath stringByAppendingPathComponent:file]];
        settings_sbl_add_preview_image(out, image, limit);
        if (out.count >= limit) break;
    }
    return out;
}

NSArray<UIImage *> *settings_sbl_preview_images_for_theme(NSDictionary *theme,
                                                          BOOL builtIn,
                                                          NSUInteger limit)
{
    if (builtIn) return settings_sbl_builtin_preview_images(limit);
    NSString *iconsPath = settings_sbl_resolved_icons_path_for_theme(theme);
    return settings_sbl_folder_preview_images(iconsPath, limit);
}

BOOL settings_snowboardlite_has_selected_theme(void)
{
    if (settings_sbl_selected_builtin_ios6()) {
        return [[NSFileManager defaultManager] fileExistsAtPath:sbl_builtin_ios6_path()];
    }
    NSDictionary *theme = settings_sbl_selected_theme();
    return settings_sbl_resolved_icons_path_for_theme(theme).length > 0;
}

NSString *settings_snowboardlite_selected_theme_display_name(void)
{
    if (settings_sbl_selected_builtin_ios6()) return @"iOS 6 Theme";
    NSDictionary *theme = settings_sbl_selected_theme();
    NSString *name = theme[@"name"];
    return name.length > 0 ? name : @"None";
}

static NSArray<NSURL *> *settings_sbl_iconbundles_dirs_in_folder(NSURL *rootURL)
{
    NSMutableArray<NSURL *> *dirs = [NSMutableArray array];
    if ([rootURL.lastPathComponent caseInsensitiveCompare:@"IconBundles"] == NSOrderedSame) {
        [dirs addObject:rootURL];
    }
    NSDirectoryEnumerator<NSURL *> *e =
        [NSFileManager.defaultManager enumeratorAtURL:rootURL
                           includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                              options:0
                                         errorHandler:^BOOL(NSURL *url, NSError *error) {
        printf("[SBL] scan skipped %s err=%s\n",
               url.path.UTF8String, error.localizedDescription.UTF8String);
        return YES;
    }];
    for (NSURL *url in e) {
        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (!isDir.boolValue) continue;
        if ([url.lastPathComponent caseInsensitiveCompare:@"IconBundles"] == NSOrderedSame) {
            [dirs addObject:url];
            [e skipDescendants];
        }
    }
    return dirs;
}

BOOL settings_sbl_import_folder_theme_named(NSURL *url,
                                            NSString *displayName,
                                            NSString *sourceType,
                                            NSError **error)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSURL *> *iconDirs = settings_sbl_iconbundles_dirs_in_folder(url);
    if (iconDirs.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SnowBoardLite"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"No IconBundles directory was found in this folder."}];
        }
        return NO;
    }

    NSString *root = settings_sbl_themes_dir();
    if (!root) return NO;
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;

    NSString *baseName = displayName.length ? displayName :
        (url.lastPathComponent.length ? url.lastPathComponent : @"Imported Theme");
    NSString *themeID = [NSString stringWithFormat:@"sbl-%llu",
                         (unsigned long long)(NSDate.date.timeIntervalSince1970 * 1000.0)];
    NSString *themeDir = [root stringByAppendingPathComponent:themeID];
    NSString *iconsDir = [themeDir stringByAppendingPathComponent:@"Icons"];
    [fm removeItemAtPath:themeDir error:nil];
    [fm createDirectoryAtPath:iconsDir withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;

    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray<NSString *> *skippedSamples = [NSMutableArray array];
    NSUInteger discovered = 0;
    NSUInteger imported = 0;
    NSUInteger aliasMapped = 0;
    NSUInteger duplicates = 0;
    NSUInteger skipped = 0;
    for (NSURL *iconDirURL in iconDirs) {
        NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:iconDirURL
                                    includingPropertiesForKeys:nil
                                                       options:0
                                                         error:nil];
        for (NSURL *fileURL in files) {
            if (![fileURL.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
            discovered++;
            BOOL usedAlias = NO;
            NSArray<NSString *> *bundleIDs = CNDMappedIOSBundleIDsForIconName(fileURL.lastPathComponent,
                                                                              &usedAlias);
            if (bundleIDs.count == 0) {
                skipped++;
                if (skippedSamples.count < 8) {
                    [skippedSamples addObject:fileURL.lastPathComponent ?: @"unknown.png"];
                }
                continue;
            }
            NSMutableSet<NSString *> *fileTargets = [NSMutableSet setWithCapacity:bundleIDs.count];
            BOOL copiedAny = NO;
            for (NSString *bundleID in bundleIDs) {
                if (bundleID.length == 0 || [fileTargets containsObject:bundleID]) continue;
                [fileTargets addObject:bundleID];
                if ([seen containsObject:bundleID]) {
                    duplicates++;
                    skipped++;
                    if (skippedSamples.count < 8) {
                        [skippedSamples addObject:[NSString stringWithFormat:@"%@ (duplicate %@)",
                                                   fileURL.lastPathComponent ?: @"unknown.png",
                                                   bundleID]];
                    }
                    continue;
                }
                NSString *dstName = [bundleID stringByAppendingPathExtension:@"png"];
                NSString *dst = [iconsDir stringByAppendingPathComponent:dstName];
                if ([fm copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:dst] error:nil]) {
                    [seen addObject:bundleID];
                    copiedAny = YES;
                    imported++;
                    if (usedAlias) aliasMapped++;
                } else {
                    skipped++;
                    if (skippedSamples.count < 8) {
                        [skippedSamples addObject:[NSString stringWithFormat:@"%@ (copy failed)",
                                                   fileURL.lastPathComponent ?: @"unknown.png"]];
                    }
                }
            }
            if (!copiedAny && fileTargets.count == 0) skipped++;
        }
    }

    if (imported == 0) {
        [fm removeItemAtPath:themeDir error:nil];
        if (error) {
            *error = [NSError errorWithDomain:@"SnowBoardLite"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"IconBundles was found, but no bundle-ID PNG icons could be imported."}];
        }
        return NO;
    }

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm";
    NSDictionary *record = @{
        @"id": themeID,
        @"name": baseName,
        @"sourceType": sourceType.length ? sourceType : @"folder",
        @"sourceName": baseName,
        @"importedAt": [fmt stringFromDate:NSDate.date],
        @"path": themeDir,
        @"iconsPath": iconsDir,
        @"iconCount": @(imported),
        @"discoveredCount": @(discovered),
        @"iconBundlesCount": @(iconDirs.count),
        @"aliasMappedCount": @(aliasMapped),
        @"duplicateCount": @(duplicates),
        @"skippedCount": @(skipped),
        @"skippedSamples": skippedSamples,
    };
    NSMutableArray *manifest = [settings_sbl_load_manifest() mutableCopy];
    [manifest insertObject:record atIndex:0];
    if (!settings_sbl_save_manifest(manifest)) return NO;

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:themeID forKey:kSettingsSnowBoardLiteSelectedThemeID];
    [d synchronize];
    log_user("[SBL] Imported \"%s\": %lu icons from %lu IconBundles folder(s), aliases=%lu skipped=%lu duplicates=%lu.\n",
             baseName.UTF8String,
             (unsigned long)imported,
             (unsigned long)iconDirs.count,
             (unsigned long)aliasMapped,
             (unsigned long)skipped,
             (unsigned long)duplicates);
    if (skippedSamples.count > 0) {
        log_user("[SBL] Skipped sample: %s\n",
                 [skippedSamples componentsJoinedByString:@", "].UTF8String);
    }
    return YES;
}

BOOL settings_sbl_import_folder_theme(NSURL *url, NSError **error)
{
    return settings_sbl_import_folder_theme_named(url, url.lastPathComponent, @"folder", error);
}

bool settings_apply_snowboardlite_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsSnowBoardLiteEnabled]) return false;
    if (settings_sbl_selected_builtin_ios6()) {
        NSString *plistPath = sbl_builtin_ios6_path();
        if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
            log_user("[SBL] Bundled iOS 6 Theme plist is missing.\n");
            return false;
        }
        NSDictionary *dict = sbl_load_plist_theme(plistPath);
        return dict.count > 0 ? themer_apply_data_in_session(dict) : false;
    }
    NSDictionary *theme = settings_sbl_selected_theme();
    NSString *iconsPath = settings_sbl_resolved_icons_path_for_theme(theme);
    if (iconsPath.length == 0) {
        log_user("[SBL] Pick an imported theme before running SnowBoard Lite.\n");
        return false;
    }
    printf("[SBL] applying theme=%s icons=%s\n",
           [theme[@"name"] UTF8String] ?: "?",
           iconsPath.UTF8String);
    return themer_apply_in_session(iconsPath.fileSystemRepresentation);
}
