// A game's fullscreen without the window manager, through Xwayland (xwayland:legacy_fullscreen): an X11 window that asks for no
// decorations (_MOTIF_WM_HINTS) and is exactly the size of a monitor at its origin becomes fullscreen when it maps, also when it is
// override-redirect as GravityMark's is; with decorations, smaller, or with the option off it stays a window
#include <chrono>
#include <cmath>
#include <cstdio>
#include <format>
#include <thread>

#include "tests.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include "../shared.hpp"
#include "../clients/build.hpp"

// the focused monitor's logical box as "X Y W H", from /monitors (X11 coordinates are logical without force_zero_scaling)
static std::string focusedMonitorBox() {
    const auto MONITORS = getFromSocket("/monitors");
    size_t     start    = 0;
    while ((start = MONITORS.find("Monitor ", start)) != std::string::npos) {
        const auto END   = MONITORS.find("Monitor ", start + 1);
        const auto BLOCK = MONITORS.substr(start, END == std::string::npos ? std::string::npos : END - start);
        start            = END;
        if (!BLOCK.contains("focused: yes"))
            continue;

        int        w = 0, h = 0, x = 0, y = 0;
        double     refresh = 0, scale = 1;
        const auto MODE = BLOCK.substr(BLOCK.find('\n') + 1);
        if (std::sscanf(MODE.c_str(), " %dx%d@%lf at %dx%d", &w, &h, &refresh, &x, &y) != 5) // NOLINT
            return "";
        if (const auto POS = BLOCK.find("scale: "); POS != std::string::npos)
            scale = std::stod(BLOCK.substr(POS + 7));
        return std::format("{} {} {} {}", x, y, std::lround(w / scale), std::lround(h / scale));
    }
    return "";
}

// maps the client and returns its window's /clients block, or "" when no window of the class showed up within 5 s
static std::string mapLegacyWindow(const std::string& box, const std::string& class_, const std::string& flags) {
    getFromSocket(std::format("/dispatch hl.dsp.exec_cmd('{}/legacy-fullscreen {} {} {}')", binaryDir, box, class_, flags));
    for (int i = 0; i < 50; ++i) {
        const auto CLIENTS = getFromSocket("/clients");
        if (const auto POS = CLIENTS.find("class: " + class_); POS != std::string::npos) {
            std::this_thread::sleep_for(std::chrono::milliseconds(300));
            const auto NOW   = getFromSocket("/clients");
            const auto BEGIN = NOW.rfind("Window ", NOW.find("class: " + class_));
            const auto END   = NOW.find("Window ", BEGIN + 1);
            return NOW.substr(BEGIN, END == std::string::npos ? std::string::npos : END - BEGIN);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    return "";
}

static void killLegacyWindows() {
    // the client's own command line only: a looser pattern matched a shell that had the word in its command
    Tests::execAndGet(std::format("pkill -f '^{}/legacy-fullscreen '", binaryDir));
    for (int i = 0; i < 30 && getFromSocket("/clients").contains("class: legacyfs"); ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
}

TEST_CASE(legacyFullscreen) {
    const auto BOX = focusedMonitorBox();
    ASSERT(BOX.empty(), false);
    NLog::log("{}Monitor box {}", Colors::YELLOW, BOX);

    int x = 0, y = 0, w = 0, h = 0;
    ASSERT(std::sscanf(BOX.c_str(), "%d %d %d %d", &x, &y, &w, &h), 4); // NOLINT
    const auto SMALLER = std::format("{} {} {} {}", x, y, w / 2, h / 2);

    NLog::log("{}An undecorated override-redirect window the size of the monitor maps fullscreen", Colors::YELLOW);
    auto window = mapLegacyWindow(BOX, "legacyfs-or", "--override-redirect");
    ASSERT(window.empty(), false);
    EXPECT_CONTAINS(window, "fullscreen: 2");
    killLegacyWindows();

    NLog::log("{}So does a managed one", Colors::YELLOW);
    window = mapLegacyWindow(BOX, "legacyfs-managed", "");
    ASSERT(window.empty(), false);
    EXPECT_CONTAINS(window, "fullscreen: 2");
    killLegacyWindows();

    NLog::log("{}A decorated one stays a window", Colors::YELLOW);
    window = mapLegacyWindow(BOX, "legacyfs-decorated", "--decorated");
    ASSERT(window.empty(), false);
    EXPECT_CONTAINS(window, "fullscreen: 0");
    killLegacyWindows();

    NLog::log("{}So does a smaller undecorated one", Colors::YELLOW);
    window = mapLegacyWindow(SMALLER, "legacyfs-small", "--override-redirect");
    ASSERT(window.empty(), false);
    EXPECT_CONTAINS(window, "fullscreen: 0");
    killLegacyWindows();

    NLog::log("{}With xwayland:legacy_fullscreen off it stays a window", Colors::YELLOW);
    OK(getFromSocket("/eval hl.config({ xwayland = { legacy_fullscreen = false } })"));
    window = mapLegacyWindow(BOX, "legacyfs-off", "--override-redirect");
    ASSERT(window.empty(), false);
    EXPECT_CONTAINS(window, "fullscreen: 0");
    killLegacyWindows();
    OK(getFromSocket("/eval hl.config({ xwayland = { legacy_fullscreen = true } })"));
}
