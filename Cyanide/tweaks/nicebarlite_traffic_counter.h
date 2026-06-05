// Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).

#ifndef nicebarlite_traffic_counter_h
#define nicebarlite_traffic_counter_h

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    NBLTrafficCounterEventInvalid = -1,
    NBLTrafficCounterEventStarted = 0,
    NBLTrafficCounterEventDelta = 1,
    NBLTrafficCounterEventNoChange = 2,
    NBLTrafficCounterEventSourceReset = 3,
} NBLTrafficCounterEvent;

typedef struct {
    bool hasSample;
    uint64_t lastIn;
    uint64_t lastOut;
    uint64_t accumulated;
} NBLTrafficCounterState;

void nbl_traffic_counter_reset(NBLTrafficCounterState *state);
void nbl_traffic_counter_seed_accumulated(NBLTrafficCounterState *state,
                                          uint64_t accumulated);
NBLTrafficCounterEvent nbl_traffic_counter_sample(NBLTrafficCounterState *state,
                                                  uint64_t totalIn,
                                                  uint64_t totalOut,
                                                  uint64_t *accumulatedOut);
bool nbl_traffic_counter_value(const NBLTrafficCounterState *state,
                               uint64_t *accumulatedOut);

#endif
