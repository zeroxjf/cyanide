//
//  LogTextViewShim.h
//  Cyanide
//
//  Thin shim exposing LogTextView to Swift without the printf macro override.
//  Do NOT import LogTextView.h here — that header defines printf() and breaks Swift.
//
#import <UIKit/UIKit.h>

@interface LogTextView : UITextView
@end

// Safe re-declarations of log helpers for Swift (no printf macro override).
void log_set_verbose(BOOL enabled);
void log_user(const char * _Nonnull msg);
