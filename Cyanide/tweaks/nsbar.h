//
//  nsbar.h
//  NSBar: Network Speed Bar - displays real-time network speed in status bar area
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#ifndef nsbar_h
#define nsbar_h

#import <stdbool.h>

typedef enum {
    NSBarPositionTopLeft = 0,
    NSBarPositionBottomLeft = 1,
    NSBarPositionTopRight = 2,
    NSBarPositionBottomRight = 3,
    NSBarPositionCenter = 4
} NSBarPosition;

bool nsbar_apply_in_session(NSBarPosition position);
bool nsbar_stop_in_session(void);
void nsbar_forget_remote_state(void);

#endif
