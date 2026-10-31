#pragma once

#include "../defines.hpp"

namespace NInit {
    bool isSudo();
    void lowerAmbientCaps();
    void gainRealTime();

    // the event loop goes to sleep in its poll and wakes up from it, for the realtime guard (gainRealTime())
    void loopAsleep();
    void loopAwake();
};