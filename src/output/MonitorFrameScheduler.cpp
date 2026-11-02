#include "MonitorFrameScheduler.hpp"
#include "../config/ConfigValue.hpp"
#include "../Compositor.hpp"
#include "../render/Renderer.hpp"
#include "../managers/eventLoop/EventLoopManager.hpp"
#include "../managers/eventLoop/EventLoopTimer.hpp"
#include "../protocols/core/Compositor.hpp"
#include "../protocols/types/SurfaceStateQueue.hpp"
#include "../helpers/env/Env.hpp"

#include <algorithm>
#include <print>

using namespace Render::GL;
using namespace Monitor;

CMonitorFrameScheduler::CMonitorFrameScheduler(PHLMONITOR m) : m_monitor(m) {
    ;
}

CMonitorFrameScheduler::~CMonitorFrameScheduler() {
    if (m_holdTimer && g_pEventLoopManager)
        g_pEventLoopManager->removeTimer(m_holdTimer);
}

// An experiment, HYPOLAND_FENCE_HOLD=<ms>: a frame is held while a client's commit on this monitor waits for the GPU
// to finish its buffer. Drawn then, the frame queues on the GPU behind that client's work anyway, misses the vblank it
// was drawn for and keeps the one flip that can be pending, so the frame with the client's update waits a refresh for
// it: Omarchy's shell commits a toast with its GPU work running and another surface at once, which was drawn at once,
// and the toast's frame flipped a refresh later than under stock Hyprland. Held, the frame is drawn when the buffers it
// waited for are ready, or after <ms>. HYPOLAND_FENCE_HOLD_DEBUG=1 prints every hold
static Time::steady_dur fenceHoldTime() {
    static const auto HOLD = [] {
        int ms = 0;
        try {
            ms = std::stoi(Env::get("HYPOLAND_FENCE_HOLD").value_or("0"));
        } catch (...) { ms = 0; }
        return std::chrono::duration_cast<Time::steady_dur>(std::chrono::milliseconds(std::max(ms, 0)));
    }();
    return HOLD;
}

bool CMonitorFrameScheduler::holdForClients(PHLMONITOR monitor, const Time::steady_tp& now) {
    static const bool DEBUG = Env::envEnabled("HYPOLAND_FENCE_HOLD_DEBUG");
    const auto        HOLD  = fenceHoldTime();
    if (HOLD.count() <= 0)
        return false;

    if (!m_holdEnd) {
        // a frame without damage (the cursor moved on its plane) has nothing a client's buffer would add
        if (!monitor->m_damage.hasChanged())
            return false;

        // the states on this monitor that wait for their buffers now; later ones do not extend the hold, so a client that
        // always has a frame on the GPU does not hold every frame for the whole time
        m_heldFor.clear();
        PROTO::compositor->forEachSurface([this, &monitor](SP<CWLSurfaceResource> surf) {
            if (!surf || std::ranges::none_of(surf->m_enteredOutputs, [&monitor](const auto& m) { return m.lock() == monitor; }))
                return;
            surf->m_stateQueue.fenceWaits(m_heldFor);
        });
        if (m_heldFor.empty())
            return false;

        m_holdStart = now;
        m_holdEnd   = now + HOLD;
        if (!m_holdTimer) {
            m_holdTimer = makeShared<CEventLoopTimer>(
                std::nullopt,
                [self = m_self](SP<CEventLoopTimer>, void*) {
                    if (const auto MON = self ? self->m_monitor.lock() : nullptr)
                        MON->scheduleFrame();
                },
                nullptr);
            g_pEventLoopManager->addTimer(m_holdTimer);
        }
        m_holdTimer->updateTimeout(HOLD, now);
        return true;
    }

    std::erase_if(m_heldFor, [](const auto& s) { return !CSurfaceStateQueue::waitsForFence(s); });
    if (!m_heldFor.empty() && now < *m_holdEnd)
        return true;

    if (DEBUG)
        std::println(stderr, "fence hold {}: {:.2f} ms, {}", monitor->m_name, std::chrono::duration<double, std::milli>(now - *m_holdStart).count(),
                     m_heldFor.empty() ? "buffers ready" : "timed out");

    m_heldFor.clear();
    m_holdStart.reset();
    m_holdEnd.reset();
    m_holdTimer->updateTimeout(std::nullopt);
    return false;
}

void CMonitorFrameScheduler::onClientFence() {
    if (!m_holdEnd)
        return;

    if (const auto MON = m_monitor.lock())
        MON->scheduleFrame();
}

bool CMonitorFrameScheduler::newSchedulingEnabled() {
    static auto PENABLENEW = CConfigValue<Config::INTEGER>("render:new_render_scheduling");

    return *PENABLENEW && g_pHyprRenderer->explicitSyncSupported() && m_monitor && !m_monitor->m_directScanoutIsActive;
}

void CMonitorFrameScheduler::onSyncFired() {
    const auto PMONITOR = m_monitor.lock();
    if (!PMONITOR || !newSchedulingEnabled())
        return;

    // Sync fired: reset submitted state, set as rendered. Check the last render time. If we are running
    // late, we will instantly render here.

    if (std::chrono::duration_cast<std::chrono::microseconds>(hrc::now() - m_lastRenderBegun).count() / 1000.F < 1000.F / PMONITOR->m_refreshRate) {
        // we are in. Frame is valid. We can just render as normal.
        Log::logger->log(Log::TRACE, "CMonitorFrameScheduler: {} -> onSyncFired, didn't miss.", PMONITOR->m_name);
        m_renderAtFrame = true;
        return;
    }

    Log::logger->log(Log::TRACE, "CMonitorFrameScheduler: {} -> onSyncFired, missed.", PMONITOR->m_name);

    // we are out. The frame is taking too long to render. Begin rendering immediately, but don't commit yet.
    m_pendingThird  = true;
    m_renderAtFrame = false; // block frame rendering, we already scheduled

    m_lastRenderBegun = hrc::now();

    // get a ref to ourselves. renderMonitor can destroy this scheduler if it decides to perform a monitor reload
    // FIXME: this is horrible. "renderMonitor" should not be able to do that.
    auto self = m_self;

    g_pHyprRenderer->renderMonitor(PMONITOR, false);

    if (!self)
        return;

    onFinishRender();
}

void CMonitorFrameScheduler::onPresented() {
    const auto PMONITOR = m_monitor.lock();
    if (!PMONITOR || !newSchedulingEnabled())
        return;

    if (!m_pendingThird)
        return;

    Log::logger->log(Log::TRACE, "CMonitorFrameScheduler: {} -> onPresented, missed, committing pending.", PMONITOR->m_name);

    m_pendingThird = false;

    Log::logger->log(Log::TRACE, "CMonitorFrameScheduler: {} -> onPresented, missed, committing pending at the earliest convenience.", PMONITOR->m_name);

    g_pEventLoopManager->doLater([m = PHLMONITORREF{PMONITOR}] {
        if (!m || !m->m_output)
            return;

        auto ml = m.lock();

        g_pHyprRenderer->commitPendingAndDoExplicitSync(ml); // commit the pending frame. If it didn't fire yet (is not rendered) it doesn't matter. Syncs will wait.

        // schedule a frame: we might have some missed damage, which got cleared due to the above commit.
        // TODO: this is not always necessary, but doesn't hurt in general. We likely won't hit this if nothing's happening anyways.
        if (ml->m_damage.hasChanged())
            ml->scheduleFrame();
    });
}

void CMonitorFrameScheduler::onFrame() {
    const auto PMONITOR = m_monitor.lock();
    if (!PMONITOR || !canRender())
        return;

    PMONITOR->recheckSolitary();

    PMONITOR->m_tearingState.busy = false;

    if (PMONITOR->m_tearingState.activelyTearing && PMONITOR->m_solitaryClient.lock() /* can be invalidated by a recheck */) {

        if (!PMONITOR->m_tearingState.frameScheduledWhileBusy)
            return; // we did not schedule a frame yet to be displayed, but we are tearing. Why render?

        PMONITOR->m_tearingState.nextRenderTorn          = true;
        PMONITOR->m_tearingState.frameScheduledWhileBusy = false;
    }

    if (!newSchedulingEnabled()) {
        // one clock read for the frame: the timer, the animation tick and the render share it
        const auto NOW = Time::steadyNow();
        if (holdForClients(PMONITOR, NOW))
            return;
        PMONITOR->m_lastPresentationTimer.reset(NOW);
        g_pHyprRenderer->renderMonitor(PMONITOR, true, NOW);
        return;
    }

    if (!m_renderAtFrame) {
        Log::logger->log(Log::TRACE, "CMonitorFrameScheduler: {} -> frame event, but m_renderAtFrame = false.", PMONITOR->m_name);
        return;
    }

    Log::logger->log(Log::TRACE, "CMonitorFrameScheduler: {} -> frame event, render = true, rendering normally.", PMONITOR->m_name);

    m_lastRenderBegun = hrc::now();

    // get a ref to ourselves. renderMonitor can destroy this scheduler if it decides to perform a monitor reload
    // FIXME: this is horrible. "renderMonitor" should not be able to do that.
    auto self = m_self;

    g_pHyprRenderer->renderMonitor(PMONITOR);

    if (!self)
        return;

    onFinishRender();
}

void CMonitorFrameScheduler::onFinishRender() {
    m_sync = g_pHyprRenderer->createSyncFDManager(); // this destroys the old sync
    if (!m_sync || !m_sync->isValid()) {
        Log::logger->log(Log::ERR, "CMonitorFrameScheduler: explicit sync failed, falling back to frame events");
        m_sync.reset();
        m_renderAtFrame = true;
        return;
    }

    g_pEventLoopManager->doOnReadable(m_sync->fd().duplicate(), [this, self = m_self] {
        if (!self) // might've gotten destroyed
            return;
        onSyncFired();
    });
}

bool CMonitorFrameScheduler::canRender() {
    if ((g_pCompositor->m_aqBackend->hasSession() && !g_pCompositor->m_aqBackend->session->active) || !g_pCompositor->m_sessionActive) {
        Log::logger->log(Log::WARN, "Attempted to render frame on inactive session!");
        return false; // cannot draw on session inactive (different tty)
    }

    if (!m_monitor->m_enabled)
        return false;

    return true;
}
