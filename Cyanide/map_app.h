//
//  map_app.h
//  Cyanide
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Maps SnowBoard/IconBundles file names, common aliases, and Android package
// names to iOS bundle identifiers. Returns nil when the name cannot resolve.
NSString *_Nullable CNDMappedIOSBundleIDForIconName(NSString *name,
                                                    BOOL *_Nullable usedAlias);

// Same as above, but returns every target bundle that should receive this icon.
// This is used for compatible clients that intentionally share one source icon.
NSArray<NSString *> *CNDMappedIOSBundleIDsForIconName(NSString *name,
                                                      BOOL *_Nullable usedAlias);

NS_ASSUME_NONNULL_END
