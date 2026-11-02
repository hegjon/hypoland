#pragma once

#include "Monitor.hpp"
#include "../render/SyncFDManager.hpp"

#include <chrono>
#include <optional>
#include <vector>

struct SSurfaceState;
class CEventLoopTimer;

namespace Monitor {
    class CMonitorFrameScheduler {
      public:
        using hrc = std::chrono::high_resolution_clock;

        CMonitorFrameScheduler(PHLMONITOR m);
        ~CMonitorFrameScheduler();

        CMonitorFrameScheduler(const CMonitorFrameScheduler&)            = delete;
        CMonitorFrameScheduler(CMonitorFrameScheduler&&)                 = delete;
        CMonitorFrameScheduler& operator=(const CMonitorFrameScheduler&) = delete;
        CMonitorFrameScheduler& operator=(CMonitorFrameScheduler&&)      = delete;

        void                    onSyncFired();
        void                    onPresented();
        void                    onFrame();
        // a client's buffer the GPU finished, which a held frame may wait for
        void onClientFence();

      private:
        bool canRender();
        void onFinishRender();
        bool newSchedulingEnabled();
        bool holdForClients(PHLMONITOR monitor, const Time::steady_tp& now);

        // a frame held while clients' buffers on this monitor are still drawn by the GPU (HYPOLAND_FENCE_HOLD)
        std::vector<WP<SSurfaceState>> m_heldFor;
        std::optional<Time::steady_tp> m_holdStart;
        std::optional<Time::steady_tp> m_holdEnd;
        SP<CEventLoopTimer>            m_holdTimer;

        bool                           m_renderAtFrame = true;
        bool                           m_pendingThird  = false;
        hrc::time_point                m_lastRenderBegun;

        PHLMONITORREF                  m_monitor;

        UP<Render::ISyncFDManager>     m_sync;

        WP<CMonitorFrameScheduler>     m_self;

        friend class CMonitor;
    };
}
