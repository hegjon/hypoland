#include <output/ScanoutAuto.hpp>

#include <gtest/gtest.h>

#include <algorithm>
#include <print>
#include <cstdlib>
#include <string>

using namespace std::chrono_literals;

static Time::steady_tp::duration seconds(double s) {
    return std::chrono::duration_cast<Time::steady_tp::duration>(std::chrono::duration<double>(s));
}

// One way of showing the simulated client: the frames it draws a second, and the most the screen shows of them a second.
struct SWay {
    double drawn = 60;
    double shown = 60;
};

// A simulated fullscreen client on a monitor that refreshes at REFRESH and asks for a choice every refresh. ACCEPTS says
// whether the plane takes its buffers, and only after ACCEPTSAFTER of them in the scanout formats (a client changing); it is
// offered them from the start, as the fullscreen handlers do, unless STARTSWITHOUT.
struct SSim {
    double refresh       = 60;
    SWay   composited    = {};
    SWay   scannedOut    = {};
    bool   accepts       = true;
    size_t acceptsAfter  = 0;
    bool   startsWithout = false;
    // for this long after the client changes ways the screen shows only half of what it shows after (formats changing)
    double                switchCost = 0;

    Monitor::CScanoutAuto choice;
    Time::steady_tp       now        = Time::steady_tp{} + 1000s;
    Time::steady_tp       nextBuffer = now, nextShown = now;
    bool                  onPlane    = false;
    Time::steady_tp       switched   = now;
    bool                  offered    = true; // the client has the scanout formats
    size_t                sinceOffer = 1000; // its buffers since
    std::string           traced;

    // runs for SECS and returns the share of the refreshes in the last LAST seconds that were scanned out
    double run(double secs, double last) {
        const auto END    = now + seconds(secs);
        const auto FROM   = END - seconds(last);
        const auto FRAME  = seconds(1.0 / refresh);
        size_t     frames = 0, out = 0;
        while (now < END) {
            const auto NEXT = now + FRAME;
            const auto WAY  = onPlane ? scannedOut : composited;
            while (nextBuffer < NEXT) {
                choice.onBuffer(nextBuffer);
                sinceOffer += offered;
                nextBuffer += seconds(1.0 / WAY.drawn);
            }
            if (nextShown < NEXT) {
                choice.onShown(nextShown);
                const double SHOWN = std::min({WAY.drawn, WAY.shown, refresh}) / (now - switched < seconds(switchCost) ? 2 : 1);
                nextShown          = std::max(nextShown + seconds(1.0 / SHOWN), now);
            }
            now = NEXT;
            if (startsWithout) {
                startsWithout = false;
                sinceOffer    = 0;
            }
            const bool WANTS = choice.update(now, refresh, onPlane);
            if (choice.wantsScanoutFormats() != offered) {
                offered    = choice.wantsScanoutFormats();
                sinceOffer = 0;
            }
            const bool ACCEPTED   = accepts && offered && sinceOffer >= acceptsAfter;
            const bool WASONPLANE = onPlane;
            if (WANTS && !ACCEPTED)
                choice.onRefused(now);
            onPlane = WANTS && ACCEPTED;
            if (onPlane != WASONPLANE)
                switched = now;
            if (getenv("SIMTRACE") && choice.describe() != traced) {
                traced = choice.describe();
                std::println("{:.2f} {}", std::chrono::duration<double>(now.time_since_epoch()).count() - 1000, traced);
            }
            if (now >= FROM) {
                ++frames;
                out += onPlane;
            }
        }
        return frames ? static_cast<double>(out) / frames : 0;
    }
};

// Xonotic on a 120 Hz Galaxy Book: 135 fps composited, held to 121 scanned out, the screen about the same. It is composited
// but for the measurements
TEST(ScanoutAuto, clientHeldDownOnThePlaneIsComposited) {
    SSim sim{.refresh = 120, .composited = {135, 115}, .scannedOut = {121, 110}};
    EXPECT_LT(sim.run(600, 590), 0.02);
}

// Xonotic's lowest effects on a 120 Hz Galaxy Book: shown at every refresh composited while drawing 700 fps, it is never
// measured scanned out, which would cost it frames
TEST(ScanoutAuto, clientShownAtEveryRefreshIsNotTriedOnThePlane) {
    SSim sim{.refresh = 120, .composited = {700, 118}, .scannedOut = {513, 117}};
    EXPECT_EQ(sim.run(600, 600), 0);
}

// the same Galaxy Book showing the game at 113 composited, a few frames short of every refresh, and 120 scanned out: about
// every refresh either way, so the game's own frames decide
TEST(ScanoutAuto, aFewFramesMoreNearTheRefreshRateAreNoGain) {
    SSim sim{.refresh = 120, .composited = {700, 113}, .scannedOut = {513, 120}};
    EXPECT_LT(sim.run(600, 590), 0.02);
}

// Xonotic at its lowest effects on a T550: 170 fps composited, 131 scanned out, 60 on the screen either way
TEST(ScanoutAuto, clientFasterCompositedIsComposited) {
    SSim sim{.refresh = 60, .composited = {170, 60}, .scannedOut = {131, 60}};
    EXPECT_LT(sim.run(600, 590), 0.02);
}

// the X200 at Xonotic's lowest effects: the game draws 77 to 80 fps either way, but the GM45 composites only 27 of them
// a second and shows 48 scanned out
TEST(ScanoutAuto, moreFramesOnTheScreenScannedOutIsScannedOut) {
    SSim sim{.refresh = 60, .composited = {77, 27}, .scannedOut = {80, 48}};
    EXPECT_GT(sim.run(600, 590), 0.98);
}

// a GPU-bound game below the refresh rate gains on the plane and is not measured composited again
TEST(ScanoutAuto, gpuBoundClientIsScannedOut) {
    SSim sim{.refresh = 60, .composited = {43.5, 43.5}, .scannedOut = {46.1, 46.1}};
    EXPECT_EQ(sim.run(600, 595), 1);
}

// a client with vsync draws at the refresh rate either way and stays on the plane but for the measurements
TEST(ScanoutAuto, clientAtTheRefreshRateIsScannedOut) {
    SSim sim{.refresh = 60};
    EXPECT_GT(sim.run(600, 590), 0.98);
}

// buffers the plane refuses: composited after a second, tried again later
TEST(ScanoutAuto, refusedBuffersAreComposited) {
    SSim sim{.refresh = 60, .composited = {40, 40}, .scannedOut = {40, 40}, .accepts = false};
    EXPECT_EQ(sim.run(120, 115), 0);
    sim.accepts = true;
    EXPECT_GT(sim.run(600, 300), 0.99);
}

// a client at 1 fps (GravityMark on Intel) is measured too, in seconds instead of a fraction of one
TEST(ScanoutAuto, slowClientIsScannedOut) {
    SSim sim{.refresh = 60, .composited = {1, 1}, .scannedOut = {1, 1}};
    EXPECT_EQ(sim.run(60, 30), 1);
}

// a client at 1 fps that takes two buffers to change to the scanout formats is still scanned out
TEST(ScanoutAuto, slowClientChangingFormatsIsScannedOut) {
    SSim sim{.refresh = 60, .composited = {1, 1}, .scannedOut = {1, 1}, .acceptsAfter = 2, .startsWithout = true};
    EXPECT_EQ(sim.run(90, 30), 1);
}

// a client that keeps the buffers it started with, which the plane refuses (mpv): composited at its first refused buffers
// after the settling, not after a second of them, every one of which KMS tests again
TEST(ScanoutAuto, refusedBuffersEndTheMeasurementAtOnce) {
    SSim sim{.refresh = 60, .composited = {30, 30}, .scannedOut = {30, 30}, .accepts = false};
    EXPECT_EQ(sim.run(4, 0.5), 0);
    EXPECT_FALSE(sim.choice.wantsScanout());
    // and it keeps the formats it was offered: taking them back cost mpv frames
    EXPECT_TRUE(sim.choice.wantsScanoutFormats());
}

// a client measured faster composited gets the regular formats back (with the scanout ones Intel clients draw slower)
TEST(ScanoutAuto, clientBetterCompositedGetsTheRegularFormats) {
    SSim sim{.refresh = 60, .composited = {170, 60}, .scannedOut = {131, 60}};
    sim.run(20, 1);
    EXPECT_FALSE(sim.choice.wantsScanoutFormats());
}

// a game whose loading screen draws a few uneven fps, slower on the plane, and then plays: chosen for again within seconds
// of its play, not after the retry the loading screen's choice set
TEST(ScanoutAuto, gameIsChosenForAgainWhenItsLoadingEnds) {
    SSim sim{.refresh = 60, .composited = {4, 4}, .scannedOut = {2, 2}};
    EXPECT_EQ(sim.run(12, 2), 0);
    sim.composited = {77, 27};
    sim.scannedOut = {80, 48};
    EXPECT_EQ(sim.run(10, 2), 1);
}

// and the other way round: scanned out while loading, composited within seconds of a play that is faster composited
TEST(ScanoutAuto, gameFasterCompositedAfterLoadingIsComposited) {
    SSim sim{.refresh = 120, .composited = {4, 4}, .scannedOut = {4, 4}};
    EXPECT_EQ(sim.run(12, 2), 1);
    sim.composited = {135, 115};
    sim.scannedOut = {121, 110};
    EXPECT_EQ(sim.run(12, 4), 0);
}

// the loading screen measured composited and the play scanned out (Xonotic's lowest effects on a 120 Hz Galaxy Book, 700
// fps composited, 513 scanned out, the screen the same): the two measurements are of other scenes, so it measures again
TEST(ScanoutAuto, measurementsOfOtherScenesAreTakenAgain) {
    SSim sim{.refresh = 120, .composited = {6, 6}, .scannedOut = {6, 6}};
    EXPECT_EQ(sim.run(2.6, 0.1), 1);
    sim.composited = {700, 118};
    sim.scannedOut = {513, 117};
    EXPECT_EQ(sim.run(14, 3), 0);
}

// the screen shows fewer frames for a moment after each switch (the client reallocating): measured after it, so it stays
// composited as without the cost
TEST(ScanoutAuto, framesLostToTheSwitchAreNotMeasured) {
    SSim sim{.refresh = 60, .composited = {170, 60}, .scannedOut = {131, 60}, .switchCost = 0.4};
    EXPECT_LT(sim.run(600, 590), 0.02);
}

// a new candidate starts composited
TEST(ScanoutAuto, resetStartsComposited) {
    SSim sim{.refresh = 60, .composited = {45, 45}, .scannedOut = {46, 46}};
    EXPECT_EQ(sim.run(10, 5), 1);
    sim.choice.reset();
    EXPECT_FALSE(sim.choice.wantsScanout());
}
