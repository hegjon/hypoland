#pragma once

#include "../helpers/time/Time.hpp"

#include <cstdint>
#include <string>

namespace Monitor {

    // The choice of render:direct_scanout auto for one fullscreen window. Scanning a window out saves the compositor drawing
    // it, but which way shows more is not known beforehand: a GM45 composites Xonotic at 27 frames a second on the screen and
    // shows 48 scanned out, while a client that draws faster than the monitor refreshes runs short of buffers on the plane
    // (KMS holds the one on the screen and the one waiting for the flip) and draws slower than composited (Xonotic on a 120 Hz
    // Galaxy Book: 121 instead of 135 fps, the screen the same). So both ways are measured, by the frames that reach the screen
    // first and the frames the client draws second, and the better one is kept; the other is tried again now and then, less
    // often each time, and at once when the screen starts to show it at another rate (a game's loading screen, then its play).
    // The compositor's own CPU time is measured with them: a client that outruns the screen on the plane polls the compositor
    // for a free buffer with round trips (Mesa's EGL, while KMS holds two of its four buffers and the newest waits for its GPU
    // work), thousands a second, and the plane has to show clearly more to be worth that (Xonotic's lowest effects on the XPS:
    // 59 instead of 53 frames on the screen in a heavy scene, at 3.6 instead of 1.7 ms of the compositor's CPU a frame).
    // No clock or Wayland object here: the monitor feeds it the times, so the unit tests can.
    class CScanoutAuto {
      public:
        // a new candidate, or none
        void reset();
        // a new buffer of the candidate became current
        void onBuffer(const Time::steady_tp& time);
        // a frame of the monitor shows a buffer of the candidate it did not show before
        void onShown(const Time::steady_tp& time);
        // the plane refused the candidate's buffer (KMS's test failed)
        void onRefused(const Time::steady_tp& time);
        // steps the choice for a frame at NOW: SCANNEDOUT says whether the candidate is on the screen's plane now, CPU is the
        // compositor's CPU time so far. Returns whether it is to be scanned out
        bool update(const Time::steady_tp& now, double refreshHz, bool scannedOut, Time::steady_dur cpu);
        bool wantsScanout() const;
        // whether the candidate is to be offered the scanout formats: all but a window that measured better composited, since a
        // client may read them only when it starts, and taking them back from one the plane refused cost mpv a third of its
        // frames composited on a T550 (30 against 20 fps); and a window that was on the plane by choice for a while keeps them,
        // as does one that got them back once, and one composited for a moment keeps them too, since every change of formats
        // makes a Vulkan client rebuild its swapchain
        bool wantsScanoutFormats() const;
        // the phase and the rates, for HYPOLAND_SCANOUT_DEBUG
        std::string describe() const;

      private:
        enum class ePhase : uint8_t {
            MEASURE_COMPOSITED,
            MEASURE_SCANOUT,
            COMPOSITED,
            SCANOUT,
        };

        // frames a second the client drew and the screen showed of it, and the compositor's CPU time per frame shown, in seconds
        struct SRates {
            double drawn = 0;
            double shown = 0;
            double cost  = 0;
        };

        struct SCount {
            Time::steady_tp first, last;
            size_t          count = 0;

            void            add(const Time::steady_tp& time);
            double          rate() const;
        };

        void enter(ePhase phase, const Time::steady_tp& now);
        // counting starts at FROM
        void                      startWindow(const Time::steady_tp& from);
        bool                      windowDone() const;
        SRates                    windowRates(const Time::steady_tp& now, Time::steady_dur cpu) const;
        void                      backOff(const Time::steady_tp& now);
        bool                      scanoutIsBetter(double refreshHz) const;

        ePhase                    m_phase = ePhase::MEASURE_COMPOSITED;
        Time::steady_tp           m_scanoutStart;    // MEASURE_SCANOUT: when the candidate first was on the plane
        Time::steady_tp           m_scanoutSince;    // SCANOUT: since when
        Time::steady_tp           m_compositedSince; // COMPOSITED: since when
        Time::steady_tp           m_retry;           // when the other way is measured again
        Time::steady_tp::duration m_backoff = {};
        SRates                    m_composited, m_scannedOut; // measured last
        bool                      m_started                  = false;
        bool                      m_refused                  = false; // MEASURE_SCANOUT: the plane refused a buffer since the window started
        bool                      m_measuredBetterComposited = false; // COMPOSITED: by a measurement, not a refusal
        bool                      m_pollsOnThePlane          = false; // the last measurement on the plane cost more than it showed
        bool                      m_formatsKept              = false; // on the plane by choice for KEEP_FORMATS: the formats stay
        bool                      m_formats                  = true;  // offered (the fullscreen handlers offer them first)
        int                       m_formatChanges            = 0;

        Time::steady_tp           m_windowFrom;
        SCount                    m_drawn, m_shown;
        // the compositor's CPU time at the window's start, the first step at or after m_windowFrom
        Time::steady_tp  m_cpuFrom;
        Time::steady_dur m_cpuAtFrom  = {};
        bool             m_cpuStarted = false;
    };
}
