#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <map>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <hyprutils/memory/Casts.hpp>
#include "tests.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include "../shared.hpp"

using namespace Hyprutils::OS;
using namespace Hyprutils::Memory;

// The terminals of these tests run a shell that reads its commands from a FIFO, so the test starts the next
// terminal from inside one at the moment it wants to: a swallower has to be a descendant of the swallowee's
// process. kitty's remote control did that before, foot has none. The FIFO stays open for writing for the life
// of the tester, so the shell never sees its end.
static std::map<std::string, int>& shellFds() {
    static std::map<std::string, int> fds;
    return fds;
}

static std::string fifoPath(const std::string& name) {
    return std::format("/tmp/hyprtester-swallow-{}.fifo", name);
}

static bool makeFifo(const std::string& name) {
    unlink(fifoPath(name).c_str());
    if (mkfifo(fifoPath(name).c_str(), 0600) == 0)
        return true;
    NLog::log("{}Error: could not create {}: {}", Colors::RED, fifoPath(name), strerror(errno));
    return false;
}

static std::string shellCommand(const std::string& name) { // what the terminal runs
    return std::format("exec sh < {}", fifoPath(name));
}

static bool openShell(const std::string& name) { // wait until the terminal's shell reads its FIFO
    if (shellFds().contains(name)) {
        close(shellFds()[name]);
        shellFds().erase(name);
    }

    for (int i = 0; i < 50; i++) {
        // ENXIO until the shell has the FIFO open for reading
        const int FD = open(fifoPath(name).c_str(), O_WRONLY | O_NONBLOCK);
        if (FD >= 0) {
            shellFds()[name] = FD;
            return true;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    NLog::log("{}Error: timed out waiting for the shell of {}", Colors::RED, name);
    return false;
}

static bool sendCommand(const std::string& name, const std::string& cmd) {
    if (!shellFds().contains(name)) {
        NLog::log("{}Error: no shell {}", Colors::RED, name);
        return false;
    }
    const auto LINE = cmd + "\n";
    return write(shellFds()[name], LINE.c_str(), LINE.size()) == sc<ssize_t>(LINE.size());
}

static bool waitForWindows(int n) {
    Tests::waitUntilWindowsN(n);
    return Tests::windowCount() == n;
}

// a terminal with the swallowee's class whose shell takes commands from the FIFO of this name
static CUniquePointer<CProcess> spawnShellFoot(const std::string& name) {
    if (!makeFifo(name))
        return nullptr;
    auto footProc = Tests::spawnFoot("foot_swallowee", {"sh", "-c", shellCommand(name)});
    if (footProc && !openShell(name))
        return nullptr;
    return footProc;
}

// a terminal started from inside the terminal `parent`, with its own shell on a FIFO of its name
static bool spawnSwallower(const std::string& parent, const std::string& name) {
    const auto COUNT_BEFORE = Tests::windowCount();
    if (!makeFifo(name))
        return false;
    if (!sendCommand(parent, std::format("foot --app-id foot_{} sh -c '{}' </dev/null >/dev/null 2>&1 &", name, shellCommand(name))))
        return false;
    if (!waitForWindows(COUNT_BEFORE + 1))
        return false;
    return openShell(name);
}

// a second window of the class of `parent`, started from inside it
static bool spawnSecondWindow(const std::string& parent) {
    const auto COUNT_BEFORE = Tests::windowCount();
    if (!sendCommand(parent, std::format("foot --app-id foot_{} </dev/null >/dev/null 2>&1 &", parent)))
        return false;
    return waitForWindows(COUNT_BEFORE + 1);
}

static int swallowingCount() {
    int notSwallowing = Tests::countOccurrences(getFromSocket("/clients"), "swallowing: 0\n");
    return Tests::windowCount() - notSwallowing;
}

static std::string getActiveWindowID() {
    std::string            activeWindow = getFromSocket("/activewindow");
    std::string::size_type start        = 7; // Length of "Window "
    std::string::size_type end          = activeWindow.find(" ->");
    if (end == std::string::npos) {
        return "error";
    }
    return activeWindow.substr(start, end - start);
}

TEST_CASE(swallow) {
    NLog::log("{}Testing window swallowing", Colors::GREEN);

    // test on workspace "swallow"
    NLog::log("{}Switching to workspace `swallow`", Colors::YELLOW);
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 'name:swallow' })"));

    ASSERT(Tests::windowCount(), 0);

    OK(getFromSocket("/eval hl.config({ misc = { enable_swallow = true } })"));
    OK(getFromSocket("/eval hl.config({ misc = { swallow_regex = '^(foot_swallowee)$' } })"));

    // Initial foot window that will be swallowed
    spawnShellFoot("swallowee");

    ASSERT(Tests::windowCount(), 1);
    ASSERT(swallowingCount(), 0);

    // Get the window ID
    std::string swalloweeID = getActiveWindowID();
    if (swalloweeID == "error") {
        FAIL_TEST("Could not get window ID");
    }
    NLog::log("{}Got swalloweeID: {}", Colors::YELLOW, swalloweeID);

    // Spawn a child process that should swallow the initial foot window
    ASSERT(spawnSwallower("swallowee", "swallower"), true);

    {
        // Verify that the initial window is swallowed
        std::string clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 1);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", swalloweeID), 1);

        std::string workspaces = getFromSocket("/workspaces");
        ASSERT_CONTAINS(workspaces, "windows: 1\n");
    }

    // Un-swallow the initial window
    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));

    {
        // Verify that the initial window is un-swallowed
        std::string clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 1);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", swalloweeID), 1);

        std::string workspaces = getFromSocket("/workspaces");
        ASSERT_CONTAINS(workspaces, "windows: 2\n");
    }

    // Open new window of the swallower foot
    ASSERT(spawnSecondWindow("swallower"), true);

    {
        // Verify that the initial has NOT been re-swallowed
        std::string clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 2);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", swalloweeID), 1);

        std::string workspaces = getFromSocket("/workspaces");
        ASSERT_CONTAINS(workspaces, "windows: 3\n");
    }

    // Re-swallow the initial window
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_swallowee' })"));
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: foot_swallowee");
    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: foot_swallower");

    {
        // Verify that the initial has been re-swallowed
        std::string clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 2);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", swalloweeID), 1);

        std::string workspaces = getFromSocket("/workspaces");
        ASSERT_CONTAINS(workspaces, "windows: 2\n");
    }

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);

    NLog::log("{}Testing chained window swallowing", Colors::GREEN);
    OK(getFromSocket("/eval hl.config({ misc = { swallow_regex = '^(foot_swallowee|foot_chain_middle|foot_chain_removed_middle)$' } })"));

    spawnShellFoot("chain_first");
    const std::string chainFirstID = getActiveWindowID();
    if (chainFirstID == "error")
        FAIL_TEST("Could not get first chain window ID");

    ASSERT(spawnSwallower("chain_first", "chain_middle"), true);
    const std::string chainMiddleID = getActiveWindowID();
    if (chainMiddleID == "error")
        FAIL_TEST("Could not get middle chain window ID");

    ASSERT(spawnSwallower("chain_middle", "chain_last"), true);
    {
        const auto clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 1);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", chainFirstID), 1);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", chainMiddleID), 1);
        ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: foot_chain_last");
        ASSERT_CONTAINS(getFromSocket("/workspaces"), "windows: 1\n");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'class:foot_chain_last' })"));
    Tests::waitUntilWindowsN(2);
    {
        const auto clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 1);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", chainFirstID), 1);
        ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: foot_chain_middle");
        ASSERT_CONTAINS(getFromSocket("/workspaces"), "windows: 1\n");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'class:foot_chain_middle' })"));
    Tests::waitUntilWindowsN(1);
    ASSERT_COUNT_STRING(getFromSocket("/clients"), "swallowing: 0\n", 1);
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: foot_swallowee");
    ASSERT_CONTAINS(getFromSocket("/workspaces"), "windows: 1\n");

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);

    spawnShellFoot("chain_removed_first");
    ASSERT(spawnSwallower("chain_removed_first", "chain_removed_middle"), true);
    ASSERT(spawnSwallower("chain_removed_middle", "chain_removed_last"), true);
    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'class:foot_chain_removed_middle' })"));
    Tests::waitUntilWindowsN(2);
    ASSERT_COUNT_STRING(getFromSocket("/clients"), "swallowing: 0\n", 2);
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: foot_chain_removed_last");
    ASSERT_CONTAINS(getFromSocket("/workspaces"), "windows: 2\n");

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);
    OK(getFromSocket("/eval hl.config({ misc = { swallow_regex = '^(foot_swallowee)$' } })"));

    NLog::log("{}Testing grouped window swallowing", Colors::GREEN);
    OK(getFromSocket("/eval hl.config({ group = { auto_group = true } })"));

    spawnShellFoot("grouped_swallowee");
    const std::string groupedSwalloweeID = getActiveWindowID();
    if (groupedSwalloweeID == "error")
        FAIL_TEST("Could not get grouped swallowee ID");
    OK(getFromSocket("/dispatch hl.dsp.group.toggle()"));
    ASSERT(!!Tests::spawnFoot("swallow_group_peer"), true);
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_swallowee' })"));

    {
        const auto clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "grouped: 0\n", 0);
    }

    ASSERT(spawnSwallower("grouped_swallowee", "grouped_swallower"), true);

    {
        const auto clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "grouped: 0\n", 1);
        ASSERT_COUNT_STRING(clients, std::format("swallowing: {}\n", groupedSwalloweeID), 1);
    }

    // Only internal fullscreen follows the group slot; each endpoint keeps its own client mode.
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 2, client = 1, action = 'set', layout_aware = false })"));
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "fullscreen: 2");
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "fullscreenClient: 1");

    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));
    {
        const auto active = getFromSocket("/activewindow");
        ASSERT_CONTAINS(active, "class: foot_swallowee");
        ASSERT_CONTAINS(active, "fullscreen: 2");
        ASSERT_CONTAINS(active, "fullscreenClient: 0");
    }
    ASSERT_COUNT_STRING(getFromSocket("/clients"), std::format("swallowing: {}\n", groupedSwalloweeID), 1);
    ASSERT_COUNT_STRING(getFromSocket("/clients"), "fullscreenClient: 1\n", 1);

    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));
    {
        const auto active = getFromSocket("/activewindow");
        ASSERT_CONTAINS(active, "class: foot_grouped_swallower");
        ASSERT_CONTAINS(active, "fullscreen: 2");
        ASSERT_CONTAINS(active, "fullscreenClient: 1");
    }

    // Internal-only slot transfers preserve the endpoint's client maximize restoration state.
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 1, client = 1, action = 'set', layout_aware = false })"));
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 2, client = 2, action = 'set', layout_aware = false })"));
    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));
    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 2, client = 2, action = 'set', layout_aware = false })"));
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = 'set', layout_aware = false })"));
    {
        const auto active = getFromSocket("/activewindow");
        ASSERT_CONTAINS(active, "class: foot_grouped_swallower");
        ASSERT_CONTAINS(active, "fullscreen: 0");
        ASSERT_CONTAINS(active, "fullscreenClient: 1");
    }

    // Clear the restored client mode before resetting the state used by the close test.
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = 'set', layout_aware = false })"));
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "fullscreenClient: 0");

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 2, client = 1, action = 'set', layout_aware = false })"));

    // Closing the source restores the swallowee and the default-handled internal fullscreen state.
    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'class:foot_grouped_swallower' })"));
    Tests::waitUntilWindowsN(2);
    ASSERT(Tests::windowCount(), 2);
    {
        const auto clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "grouped: 0\n", 0);
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 2);
    }
    {
        const auto active = getFromSocket("/activewindow");
        ASSERT_CONTAINS(active, "class: foot_swallowee");
        ASSERT_CONTAINS(active, "fullscreen: 2");
        ASSERT_CONTAINS(active, "fullscreenClient: 0");
        ASSERT_CONTAINS(active, "fullscreenHandler: default");
    }

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);

    // Destroying the revealed target restores the source to the group slot and clears both reservations.
    spawnShellFoot("target_first_swallowee");
    OK(getFromSocket("/dispatch hl.dsp.group.toggle()"));
    ASSERT(!!Tests::spawnFoot("target_first_group_peer"), true);
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_swallowee' })"));
    ASSERT(spawnSwallower("target_first_swallowee", "target_first_swallower"), true);
    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));
    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'class:foot_swallowee' })"));
    Tests::waitUntilWindowsN(2);
    ASSERT(Tests::windowCount(), 2);
    {
        const auto clients = getFromSocket("/clients");
        ASSERT_COUNT_STRING(clients, "grouped: 0\n", 0);
        ASSERT_COUNT_STRING(clients, "swallowing: 0\n", 2);
    }

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);

    // Layout-managed fullscreen follows the group slot and survives closing the active swallower too.
    OK(getFromSocket("/eval hl.config({ general = { layout = 'scrolling' } })"));
    spawnShellFoot("layout_swallowee");
    OK(getFromSocket("/dispatch hl.dsp.group.toggle()"));
    ASSERT(!!Tests::spawnFoot("layout_swallow_group_peer"), true);
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_swallowee' })"));
    ASSERT(spawnSwallower("layout_swallowee", "layout_swallower"), true);
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 2, client = 1, action = 'set', layout_aware = true })"));

    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));
    {
        const auto active = getFromSocket("/activewindow");
        ASSERT_CONTAINS(active, "class: foot_swallowee");
        ASSERT_CONTAINS(active, "fullscreen: 2");
        ASSERT_CONTAINS(active, "fullscreenClient: 0");
        ASSERT_CONTAINS(active, "fullscreenHandler: scrolling");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.toggle_swallow()"));
    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'class:foot_layout_swallower' })"));
    Tests::waitUntilWindowsN(2);
    ASSERT(Tests::windowCount(), 2);
    {
        const auto active = getFromSocket("/activewindow");
        ASSERT_CONTAINS(active, "class: foot_swallowee");
        ASSERT_CONTAINS(active, "fullscreen: 2");
        ASSERT_CONTAINS(active, "fullscreenClient: 0");
        ASSERT_CONTAINS(active, "fullscreenHandler: scrolling");
    }

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);
    OK(getFromSocket("/eval hl.config({ general = { layout = 'dwindle' } })"));

    // A locked candidate group must remain intact and must not be swallowed.
    spawnShellFoot("locked_swallowee");
    OK(getFromSocket("/dispatch hl.dsp.group.toggle()"));
    OK(getFromSocket("/dispatch hl.dsp.group.lock_active({ action = 'set' })"));
    ASSERT(spawnSwallower("locked_swallowee", "locked_swallower"), true);
    ASSERT(swallowingCount(), 0);
    ASSERT_COUNT_STRING(getFromSocket("/clients"), "grouped: 0\n", 1);

    OK(getFromSocket("/eval hl.config({ group = { auto_group = false } })"));
    Tests::killAllWindows();
}
