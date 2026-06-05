//
//  SBLArchiveExtractor.h
//  Cyanide
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SBLExtractArchiveToDirectory(NSURL *url, NSString *destination, NSError **error);

NS_ASSUME_NONNULL_END
