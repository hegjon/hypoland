#pragma once

#include "../defines.hpp"

namespace NInit {
    bool isSudo();
    void lowerAmbientCaps();
    void gainRealTime();

    // the event loop goes round once more, for the realtime guard (gainRealTime())
    void loopRound();
};