// Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).

#include "nicebarlite_traffic_counter.h"

#include <string.h>

static uint64_t nbl_saturating_add_u64(uint64_t lhs, uint64_t rhs)
{
    if (UINT64_MAX - lhs < rhs) return UINT64_MAX;
    return lhs + rhs;
}

void nbl_traffic_counter_reset(NBLTrafficCounterState *state)
{
    if (!state) return;
    memset(state, 0, sizeof(*state));
}

void nbl_traffic_counter_seed_accumulated(NBLTrafficCounterState *state,
                                          uint64_t accumulated)
{
    if (!state) return;
    state->accumulated = accumulated;
}

NBLTrafficCounterEvent nbl_traffic_counter_sample(NBLTrafficCounterState *state,
                                                  uint64_t totalIn,
                                                  uint64_t totalOut,
                                                  uint64_t *accumulatedOut)
{
    if (!state) return NBLTrafficCounterEventInvalid;

    if (!state->hasSample) {
        state->hasSample = true;
        state->lastIn = totalIn;
        state->lastOut = totalOut;
        if (accumulatedOut) *accumulatedOut = state->accumulated;
        return NBLTrafficCounterEventStarted;
    }

    if (totalIn < state->lastIn || totalOut < state->lastOut) {
        state->lastIn = totalIn;
        state->lastOut = totalOut;
        if (accumulatedOut) *accumulatedOut = state->accumulated;
        return NBLTrafficCounterEventSourceReset;
    }

    uint64_t delta = nbl_saturating_add_u64(totalIn - state->lastIn,
                                            totalOut - state->lastOut);
    state->lastIn = totalIn;
    state->lastOut = totalOut;
    if (delta == 0) {
        if (accumulatedOut) *accumulatedOut = state->accumulated;
        return NBLTrafficCounterEventNoChange;
    }

    state->accumulated = nbl_saturating_add_u64(state->accumulated, delta);
    if (accumulatedOut) *accumulatedOut = state->accumulated;
    return NBLTrafficCounterEventDelta;
}

bool nbl_traffic_counter_value(const NBLTrafficCounterState *state,
                               uint64_t *accumulatedOut)
{
    if (!state || !state->hasSample || !accumulatedOut) return false;
    *accumulatedOut = state->accumulated;
    return true;
}
