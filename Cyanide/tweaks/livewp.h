//
//  livewp.h
//  LiveWP (Live Wallpaper): plays a user-selected video as a dynamic wallpaper
//  on the lock screen and home screen via RemoteCall.
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#ifndef livewp_h
#define livewp_h

#import <stdbool.h>
#import <Foundation/Foundation.h>

// 标准 Tweak 入口点
bool livewp_apply_in_session(void);
bool livewp_repair_in_session(void);
bool livewp_pause_in_session(void);
bool livewp_resume_in_session(void);
bool livewp_stop_in_session(void);
void livewp_forget_remote_state(void);
bool livewp_swap_video_in_session(NSString *videoPath);
NSString *livewp_absolute_path(void);

#endif
