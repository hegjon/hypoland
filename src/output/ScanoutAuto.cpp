#include "ScanoutAuto.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <format>

#include "../helpers/memory/Memory.hpp"

using namespace Monitor;
using namespace std::chrono_literals;

// after a switch the client gets other formats and reallocates, its buffers in flight still come the old way and the plane
// changes its format
constexpr auto SETTLE = 500ms;
// a measurement takes this long and this many buffers: 8 are 8 s for a client at 1 fps
constexpr auto   WINDOW      = 1s;
constexpr size_t MIN_BUFFERS = 8;
// the screen shows more frames one way when it shows this many more; otherwise the client's own rate decides, by as much
constexpr double MARGIN = 0.05;
// a scanned-out window that draws at this share of the refresh rate or more may be held down by the plane
constexpr double NEAR_REFRESH = 0.95;
// shown at this share of the refresh rate or more, a window is shown at about every refresh: a few frames a second more one
// way are no gain there (a Galaxy Book showed Xonotic at 113 to 116 composited and 120 scanned out, which cost the game a
// third of its frames)
constexpr double EVERY_REFRESH = 0.9;
// a window that draws this much faster than the monitor refreshes outruns it
constexpr double OUTRUNS = 1.05;
// the plane costs the compositor this many times its CPU time a frame composited, and this much more, when the client polls
// it for buffers there (the XPS: 3.6 against 1.7 ms; a scanned-out frame costs less than a composited one otherwise)
constexpr double COSTLIER     = 1.5;
constexpr double COSTLIER_MIN = 0.3e-3;
// and then the screen has to show this many more frames of it to be chosen (the X200: 48 against 27; the XPS showed Xonotic
// at 48 composited in a heavy scene and 60 scanned out in a lighter one)
constexpr double WORTH_ITS_COST = 0.3;
// the screen showing a rate this far from the one a choice was made at chooses again at once
constexpr double CHANGED = 0.2;
// the client drawing more than this many times as fast one way as the other is not the plane's doing but another scene
// (a game's loading screen measured composited, its play scanned out): measured again after a moment
constexpr double OTHER_SCENE = 2;
constexpr auto   SOON        = 1s;
// how long and for how many buffers a scanout that does not happen is waited for before the window is kept composited: a
// client takes a buffer or two to change to the scanout formats, which is seconds at a few fps
constexpr auto   NO_SCANOUT         = 1s;
constexpr size_t NO_SCANOUT_BUFFERS = 4;
// a refused buffer counts once this many of the window's buffers came after the settling
constexpr size_t REFUSED_AFTER = 2;
// the first wait before the other way is measured again, doubled every time up to the last
constexpr auto FIRST_BACKOFF = 15s;
constexpr auto LAST_BACKOFF  = 240s;

void           CScanoutAuto::SCount::add(const Time::steady_tp& time) {
    if (count++ == 0)
        first = time;
    last = time;
}

double CScanoutAuto::SCount::rate() const {
    if (count < 2 || last == first)
        return 0;

    // n events are n - 1 intervals
    return (count - 1) / std::chrono::duration<double>(last - first).count();
}

void CScanoutAuto::reset() {
    *this = {};
}

void CScanoutAuto::onBuffer(const Time::steady_tp& time) {
    if (time >= m_windowFrom)
        m_drawn.add(time);
}

void CScanoutAuto::onShown(const Time::steady_tp& time) {
    if (time >= m_windowFrom)
        m_shown.add(time);
}

void CScanoutAuto::onRefused(const Time::steady_tp& time) {
    // a client changing to the scanout formats sends a buffer or two in the old ones first, which is seconds at a few fps
    if (time >= m_windowFrom && m_drawn.count >= REFUSED_AFTER)
        m_refused = true;
}

void CScanoutAuto::startWindow(const Time::steady_tp& from) {
    m_windowFrom = from;
    m_drawn      = {};
    m_shown      = {};
    m_cpuStarted = false;
}

bool CScanoutAuto::windowDone() const {
    return m_drawn.count >= MIN_BUFFERS && m_drawn.last - m_drawn.first >= WINDOW;
}

CScanoutAuto::SRates CScanoutAuto::windowRates(const Time::steady_tp& now, Time::steady_dur cpu) const {
    SRates rates = {.drawn = m_drawn.rate(), .shown = m_shown.rate()};
    if (m_cpuStarted && now > m_cpuFrom && rates.shown > 0)
        rates.cost = std::chrono::duration<double>(cpu - m_cpuAtFrom).count() / std::chrono::duration<double>(now - m_cpuFrom).count() / rates.shown;
    return rates;
}

void CScanoutAuto::enter(ePhase phase, const Time::steady_tp& now) {
    m_phase        = phase;
    m_scanoutStart = {};
    m_refused      = false;
    startWindow(now + SETTLE);
}

void CScanoutAuto::backOff(const Time::steady_tp& now) {
    m_retry   = now + m_backoff;
    m_backoff = std::min<Time::steady_tp::duration>(m_backoff * 2, LAST_BACKOFF);
}

static bool changed(double rate, double chosenAt) {
    return std::abs(rate - chosenAt) > chosenAt * CHANGED;
}

static bool costlier(double cost, double than) {
    return cost > than * COSTLIER && cost > than + COSTLIER_MIN;
}

bool CScanoutAuto::scanoutIsBetter(double refreshHz) const {
    // a plane the compositor pays for has to show clearly more; the client polling it draws no more there
    if (costlier(m_scannedOut.cost, m_composited.cost))
        return m_scannedOut.shown > m_composited.shown * (1 + WORTH_ITS_COST);

    // the frames on the screen first, the client's own frames when the screen shows about as many either way, or about every
    // refresh either way
    if (m_scannedOut.shown < refreshHz * EVERY_REFRESH || m_composited.shown < refreshHz * EVERY_REFRESH) {
        if (m_scannedOut.shown > m_composited.shown * (1 + MARGIN))
            return true;
        if (m_scannedOut.shown < m_composited.shown * (1 - MARGIN))
            return false;
    }
    return m_scannedOut.drawn >= m_composited.drawn * (1 - MARGIN);
}

// composited at every refresh while it draws faster than that, a window cannot show more frames on the plane and only runs
// short of buffers there (Xonotic's lowest effects on a 120 Hz Galaxy Book: 700 fps composited, 500 scanned out), so it is
// not measured scanned out: the measurement alone cost a tenth of its frames over the benchmark's 12 s
static bool showsAllItCan(const double drawn, const double shown, const double refreshHz) {
    return shown >= refreshHz * EVERY_REFRESH && drawn > refreshHz * OUTRUNS;
}

bool CScanoutAuto::update(const Time::steady_tp& now, double refreshHz, bool scannedOut, Time::steady_dur cpu) {
    if (!m_started) {
        m_started = true;
        m_backoff = FIRST_BACKOFF;
        enter(ePhase::MEASURE_COMPOSITED, now);
    }

    if (!m_cpuStarted && now >= m_windowFrom) {
        m_cpuStarted = true;
        m_cpuFrom    = now;
        m_cpuAtFrom  = cpu;
    }

    switch (m_phase) {
        case ePhase::MEASURE_COMPOSITED: {
            if (!windowDone())
                break;

            m_composited = windowRates(now, cpu);
            // the plane measured at once, not at its retry, unless the client polled it for buffers last time: the polling comes
            // with the client, not with the scene (Xonotic's demo changes scenes every few seconds, and the XPS paid for a
            // measurement on the plane after every one)
            m_measuredBetterComposited = showsAllItCan(m_composited.drawn, m_composited.shown, refreshHz) || (m_pollsOnThePlane && now < m_retry);
            enter(m_measuredBetterComposited ? ePhase::COMPOSITED : ePhase::MEASURE_SCANOUT, now);
            break;
        }
        case ePhase::MEASURE_SCANOUT: {
            // the plane refused its buffers: composited for a while, at once, since every refused frame is tested in KMS again
            if (m_refused) {
                backOff(now);
                enter(ePhase::COMPOSITED, now);
                m_measuredBetterComposited = false;
                break;
            }

            if (m_scanoutStart == Time::steady_tp{}) {
                if (scannedOut) {
                    // counted from when it is on the plane
                    m_scanoutStart = now;
                    startWindow(std::max(m_windowFrom, now + SETTLE));
                } else if (now - m_windowFrom > NO_SCANOUT && m_drawn.count >= NO_SCANOUT_BUFFERS) {
                    // the plane refused it (a format, a size), so it stays composited for a while
                    backOff(now);
                    enter(ePhase::COMPOSITED, now);
                    m_measuredBetterComposited = false;
                }
                break;
            }

            if (!windowDone())
                break;

            m_scannedOut = windowRates(now, cpu);
            if (m_scannedOut.drawn > m_composited.drawn * OTHER_SCENE || m_composited.drawn > m_scannedOut.drawn * OTHER_SCENE)
                m_retry = now + SOON;
            else
                backOff(now);
            m_measuredBetterComposited = !scanoutIsBetter(refreshHz);
            m_pollsOnThePlane          = m_measuredBetterComposited && costlier(m_scannedOut.cost, m_composited.cost);
            enter(m_measuredBetterComposited ? ePhase::COMPOSITED : ePhase::SCANOUT, now);
            break;
        }
        case ePhase::COMPOSITED: {
            if (!windowDone())
                break;

            const auto RATES = windowRates(now, cpu);
            startWindow(now);
            // at another rate it is measured composited first, where it is: the window that saw the change has some of both
            if (changed(RATES.shown, m_composited.shown)) {
                enter(ePhase::MEASURE_COMPOSITED, now);
                break;
            }

            if (now < m_retry || showsAllItCan(RATES.drawn, RATES.shown, refreshHz))
                break;

            m_composited = RATES;
            enter(ePhase::MEASURE_SCANOUT, now);
            break;
        }
        case ePhase::SCANOUT: {
            if (!windowDone())
                break;

            const auto RATES = windowRates(now, cpu);
            startWindow(now);
            // well below the refresh rate it is not short of buffers, and the plane saves the compositor's drawing; one that
            // starts to poll for buffers (a lighter scene) is measured again at once
            if (!costlier(RATES.cost, m_scannedOut.cost) && (RATES.drawn < refreshHz * NEAR_REFRESH || (now < m_retry && !changed(RATES.shown, m_scannedOut.shown))))
                break;

            enter(ePhase::MEASURE_COMPOSITED, now);
            break;
        }
    }

    return wantsScanout();
}

std::string CScanoutAuto::describe() const {
    static constexpr std::array NAMES = {"measuring composited", "measuring scanned out", "composited", "scanned out"};
    return std::format("{}; composited {:.1f} drawn, {:.1f} shown, {:.2f} ms; scanned out {:.1f} drawn, {:.1f} shown, {:.2f} ms", NAMES[sc<size_t>(m_phase)], m_composited.drawn,
                       m_composited.shown, m_composited.cost * 1000, m_scannedOut.drawn, m_scannedOut.shown, m_scannedOut.cost * 1000);
}

bool CScanoutAuto::wantsScanoutFormats() const {
    return m_phase != ePhase::COMPOSITED || !m_measuredBetterComposited;
}

bool CScanoutAuto::wantsScanout() const {
    return m_phase == ePhase::MEASURE_SCANOUT || m_phase == ePhase::SCANOUT;
}
