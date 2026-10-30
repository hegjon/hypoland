#include <unistd.h>
#include <cmath>
#include <chrono>
#include <filesystem>
#include <format>
#include <thread>
#include <hyprutils/os/Process.hpp>
#include <hyprutils/memory/WeakPtr.hpp>
#include <hyprutils/string/VarList2.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>

#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include "../shared.hpp"
#include "tests.hpp"
#include "../clients/build.hpp"

using namespace Hyprutils::Utils;

/// Spawns a foot and creates a file and returns its name. The removal of the file triggers
/// activation of the spawned foot window.
///
/// On failure, returns an empty string, possibly leaving a temporary file.
// A window that requests activation (focus) once the file this returns is removed: hyprtester's `activate`
// client (clients/activate.cpp), which asks for an xdg-activation token with the serial of its keyboard focus.
// kitty's remote control did it before; foot's urgency bell sends no serial, which the compositor rejects.
static std::string spawnActivatingWindow(const std::string& class_ = "activating") {
    // `XXXXXX` is what `mkstemp` expects to find in the string
    std::string tmpFilename = (std::filesystem::temp_directory_path() / "XXXXXX").string();
    int         fd          = mkstemp(tmpFilename.data());

    if (fd < 0) {
        NLog::red("Error: could not create tmp file: errno {}", errno);
        return "";
    }

    (void)close(fd);

    const auto COUNT_BEFORE = Tests::windowCount();
    auto       client = Hyprutils::Memory::makeUnique<Hyprutils::OS::CProcess>(binaryDir + "/activate", std::vector<std::string>{"--app-id", class_, "--trigger", tmpFilename});
    client->addEnv("WAYLAND_DISPLAY", WLDISPLAY);
    client->runAsync();

    for (int i = 0; i < 50 && Tests::windowCount() == COUNT_BEFORE; ++i) {
        if (!Tests::processAlive(client->pid())) {
            NLog::red("Error: the activate client died");
            return "";
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    if (Tests::windowCount() == COUNT_BEFORE) {
        NLog::red("Error: the activate client opened no window");
        return "";
    }

    return tmpFilename;
}

// /activewindow once it reports this size in two reads 200 ms apart (a client's commit can change a floating
// window's size after a resize), or the last read after 3 s
static std::string waitForSettledActiveWindowSize(const std::string& size) {
    const auto  WANTED = std::format("size: {}", size);
    std::string str;
    for (int i = 0; i < 15; ++i) {
        str = getFromSocket("/activewindow");
        if (str.contains(WANTED)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            str = getFromSocket("/activewindow");
            if (str.contains(WANTED))
                return str;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    return str;
}

static std::string getWindowAddress(const std::string& winInfo) {
    auto pos  = winInfo.find("Window ");
    auto pos2 = winInfo.find(" -> ");
    if (pos == std::string::npos || pos2 == std::string::npos) {
        NLog::log("{}Wrong window info", Colors::RED);
        return "Wrong window info";
    }
    return winInfo.substr(pos + 7, pos2 - pos - 7);
}

TEST_CASE(swapWindow) {
    // test on workspace "swapwindow"
    NLog::log("{}Switching to workspace \"swapwindow\"", Colors::YELLOW);
    getFromSocket("/dispatch hl.dsp.focus({ workspace = 'name:swapwindow' })");

    SPAWN_FOOT("foot_A");
    SPAWN_FOOT("foot_B");

    NLog::log("{}Expecting 2 windows", Colors::YELLOW);
    ASSERT(Tests::windowCount(), 2);

    // Test swapwindow by direction
    {
        getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })");
        auto pos = std::format("at: {}", Tests::getAttribute(getFromSocket("/activewindow"), "at"));
        NLog::log("{}Testing foot_A {}, swapwindow with direction 'r'", Colors::YELLOW, pos);

        OK(getFromSocket("/dispatch hl.dsp.window.swap({ direction = 'right' })"));
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })"));

        EXPECT_CONTAINS(getFromSocket("/activewindow"), std::format("{}", pos));
    }

    // Test swapwindow by class
    {
        getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })");
        auto pos = std::format("at: {}", Tests::getAttribute(getFromSocket("/activewindow"), "at"));
        NLog::log("{}Testing foot_A {}, swapwindow with class:foot_B", Colors::YELLOW, pos);

        OK(getFromSocket("/dispatch hl.dsp.window.swap({ target = 'class:foot_B' })"));
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })"));

        EXPECT_CONTAINS(getFromSocket("/activewindow"), std::format("{}", pos));
    }

    // Test swapwindow by address
    {
        getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })");
        auto addr = getWindowAddress(getFromSocket("/activewindow"));
        getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })");
        auto pos = std::format("at: {}", Tests::getAttribute(getFromSocket("/activewindow"), "at"));
        NLog::log("{}Testing foot_A {}, swapwindow with address:0x{}(foot_B)", Colors::YELLOW, pos, addr);

        OK(getFromSocket(std::format("/dispatch hl.dsp.window.swap({{ target = 'address:0x{}' }})", addr)));
        OK(getFromSocket(std::format("/dispatch hl.dsp.focus({{ window = 'address:0x{}' }})", addr)));

        EXPECT_CONTAINS(getFromSocket("/activewindow"), std::format("{}", pos));
    }

    NLog::log("{}Testing swapwindow with fullscreen. Expecting to fail", Colors::YELLOW);
    {
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));

        auto str = getFromSocket("/dispatch hl.dsp.window.swap({ direction = 'left' })");
        EXPECT_CONTAINS(str, "Can't swap fullscreen window");

        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));
    }

    NLog::log("{}Testing swapwindow with different workspace", Colors::YELLOW);
    {
        getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })");
        auto addr = getWindowAddress(getFromSocket("/activewindow"));
        auto ws   = std::format("workspace: {}", Tests::getAttribute(getFromSocket("/activewindow"), "workspace"));
        NLog::log("{}Sending address:0x{}(foot_B) to workspace \"swapwindow2\"", Colors::YELLOW, addr);

        OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = 'name:swapwindow2', follow = false })"));
        OK(getFromSocket(std::format("/dispatch hl.dsp.window.swap({{ target = 'address:0x{}' }})", addr)));
        getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })");
        EXPECT_CONTAINS(getFromSocket("/activewindow"), std::format("{}", ws));
    }
}

TEST_CASE(windowGroupRules) {
    OK(getFromSocket("/eval hl.config({ general = { border_size = 8 } })"));
    OK(getFromSocket("/eval hl.workspace_rule({ workspace = 'w[tv1]', border_size = 0 })"));
    OK(getFromSocket("/eval hl.workspace_rule({ workspace = 'f[1]', border_size = 0 })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { workspace = 'w[tv1]' }, border_size = 0 })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { workspace = 'f[1]' }, border_size = 0 })"));

    SPAWN_FOOT("foot_A");

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "0");
    }

    SPAWN_FOOT("foot_B");

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "8");
    }

    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
    OK(getFromSocket("/dispatch hl.dsp.group.toggle()"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.move({ into_group = 'left' })"));

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "0");
    }

    OK(getFromSocket("/dispatch hl.dsp.group.next()"));

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "0");
    }

    SPAWN_FOOT("foot_C");

    OK(getFromSocket("/dispatch hl.dsp.window.move({ out_of_group = 'right' })"));

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "8");
    }
}

static bool isActiveWindow(const std::string& class_, char fullscreen = '0', bool log = true) {
    std::string activeWin     = getFromSocket("/activewindow");
    auto        winClass      = Tests::getAttribute(activeWin, "class");
    auto        winFullscreen = Tests::getAttribute(activeWin, "fullscreen").back();
    if (winClass == class_ && winFullscreen == fullscreen)
        return true;
    else {
        if (log)
            NLog::log("{}Wrong active window: expected class {} fullscreen '{}', found class {}, fullscreen '{}'", Colors::RED, class_, fullscreen, winClass, winFullscreen);
        return false;
    }
}

static bool waitForActiveWindow(const std::string& class_, char fullscreen = '0', bool logLastCheck = true, int maxTries = 50) {
    int cnt = 0;
    while (!isActiveWindow(class_, fullscreen, false)) {
        ++cnt;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (cnt > maxTries) {
            return isActiveWindow(class_, fullscreen, logLastCheck);
        }
    }
    return true;
}

/// Tests behavior of a window being focused when on that window's workspace
/// another fullscreen window exists.
TEST_CASE(windowFocusOnFullscreenConflict) {
    SPAWN_FOOT("foot_A");
    SPAWN_FOOT("foot_B");

    OK(getFromSocket("/eval hl.config({ misc = { focus_on_activate = true } })"));

    // Unfullscreen on conflict
    {
        OK(getFromSocket("/eval hl.config({ misc = { on_focus_under_fullscreen = 2 } })"));

        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);

        // Dispatch-focus the same window
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);

        // Dispatch-focus a different window
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })"));
        EXPECT(isActiveWindow("foot_B", '0'), true);

        // Make a window that will request focus
        const std::string removeToActivate = spawnActivatingWindow();
        if (removeToActivate.empty())
            FAIL_TEST("Could not spawn activating");
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);
        std::filesystem::remove(removeToActivate);
        EXPECT(waitForActiveWindow("activating", '0'), true);
        OK(getFromSocket("/dispatch hl.dsp.window.kill()"));
        Tests::waitUntilWindowsN(2);
    }

    // Take over on conflict
    {
        OK(getFromSocket("/eval hl.config({ misc = { on_focus_under_fullscreen = 1 } })"));

        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);

        // Dispatch-focus the same window
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);

        // Dispatch-focus a different window
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })"));
        EXPECT(isActiveWindow("foot_B", '2'), true);
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = 'set' })"));

        // Make a window that will request focus
        const std::string removeToActivate = spawnActivatingWindow();
        if (removeToActivate.empty())
            FAIL_TEST("Could not spawn activating");
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);
        std::filesystem::remove(removeToActivate);
        EXPECT(waitForActiveWindow("activating", '2'), true);
        OK(getFromSocket("/dispatch hl.dsp.window.kill()"));
        Tests::waitUntilWindowsN(2);
    }

    // Keep the old focus on conflict
    {
        OK(getFromSocket("/eval hl.config({ misc = { on_focus_under_fullscreen = 0 } })"));

        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);

        // Dispatch-focus the same window
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);

        // Make a window that will request focus - the setting is treated normally
        const std::string removeToActivate = spawnActivatingWindow();
        if (removeToActivate.empty())
            FAIL_TEST("Could not spawn activating");
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
        EXPECT(isActiveWindow("foot_A", '2'), true);
        std::filesystem::remove(removeToActivate);
        EXPECT(waitForActiveWindow("foot_A", '2'), true);
    }
}

TEST_CASE(focusFloatingOrTilingUnderFullscreen) {
    OK(getFromSocket("/eval hl.config({ misc = { focus_on_activate = true } })"));
    OK(getFromSocket("/eval hl.config({ misc = { on_focus_under_fullscreen = 2 } })"));

    SPAWN_FOOT("foot_a");
    SPAWN_FOOT("foot_b");

    ASSERT(isActiveWindow("foot_b", '0'), true);
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'set' })"));

    // Test 1: focus floating from fullscreen tiled

    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_a' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
    ASSERT(isActiveWindow("foot_a", '2'), true);

    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'floating' })"));
    std::string active = getFromSocket("/activewindow");
    EXPECT_CONTAINS(Tests::getAttribute(active, "class"), "foot_b");
    std::string foot_a = getFromSocket("/clients");
    // Assuming clients appear in the same order that they connected in
    foot_a = foot_a.substr(0, foot_a.size() - active.size());
    ASSERT_COUNT_STRING(foot_a, "class:", 1); // Check that the cut is right
    EXPECT(Tests::getAttribute(foot_a, "class") == "foot_a", true);
    // Remains fullscreen, since we just focused a floating window over it
    EXPECT(Tests::getAttribute(foot_a, "fullscreen") == "2", true);
    EXPECT(Tests::getAttribute(foot_a, "fullscreenClient") == "2", true);

    // Test 2: focus tiled from fullscreen floating

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'tiled' })"));
    active = getFromSocket("/activewindow");
    EXPECT_CONTAINS(Tests::getAttribute(active, "class"), "foot_a");
    std::string foot_b = getFromSocket("/clients");
    // Assuming clients appear in the same order that they connected in
    foot_b = foot_b.substr(active.size());
    ASSERT_COUNT_STRING(foot_b, "class:", 1); // Check that the cut is right
    EXPECT(Tests::getAttribute(foot_b, "class") == "foot_b", true);
    // Exited fullscreen, since we switched focus to a window under it
    EXPECT(Tests::getAttribute(foot_b, "fullscreen") == "0", true);
    EXPECT(Tests::getAttribute(foot_b, "fullscreen") == "0", true);
}

TEST_CASE(windowMaximizeSize) {
    SPAWN_FOOT("foot_A");

    // check foot properties. Maximizing shouldnt change its size
    {
        auto str = getFromSocket("/clients");
        EXPECT(str.contains("at: 22,22"), true);
        EXPECT(str.contains("size: 1876,1036"), true);
        EXPECT(str.contains("fullscreen: 0"), true);
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'maximized' })"));

    {
        auto str = getFromSocket("/clients");
        EXPECT(str.contains("at: 22,22"), true);
        EXPECT(str.contains("size: 1876,1036"), true);
        EXPECT(str.contains("fullscreen: 1"), true);
    }
}

TEST_CASE(groupFallbackFocus) {
    SPAWN_FOOT("foot_A");

    OK(getFromSocket("/dispatch hl.dsp.group.toggle()"));

    SPAWN_FOOT("foot_B");
    SPAWN_FOOT("foot_C");
    SPAWN_FOOT("foot_D");

    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("class: foot_D"), true);
    }

    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_D' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.kill()"));

    Tests::waitUntilWindowsN(3);

    // Focus must return to the last focus, in this case B.
    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("class: foot_B"), true);
    }
}

TEST_CASE(initialFloatSize) {
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot' }, float = true })"));
    OK(getFromSocket("/eval hl.config({ input = { float_switch_override_focus = 0 } })"));

    // foot is asked for 640x400, kitty's default size the test was written for (foot's own is 700x500)
    SPAWN_FOOT("foot", {"--window-size-pixels=640x400"});

    {
        auto str = getFromSocket("/clients");
        EXPECT(str.contains("size: 640,400"), true);
    }

    OK(getFromSocket("/reload"));

    Tests::killAllWindows();

    OK(getFromSocket("/dispatch hl.dsp.exec_cmd('foot --window-size-pixels=640x400', { float = true })"));

    Tests::waitUntilWindowsN(1);

    {
        auto str = getFromSocket("/clients");
        EXPECT(str.contains("size: 640,400"), true);
        EXPECT(str.contains("floating: 1"), true);
    }
}

/// Tests that the `focus_on_activate` effect of window rules always overrides
/// the `misc:focus_on_activate` variable.
TEST_CASE(windowRuleFocusOnActivate) {
    SPAWN_FOOT("foot_default");

    // Do not focus anyone automatically
    // TODO: this looks like a bug: the following line should not be commented out
    ///////////OK(getFromSocket("/eval hl.window_rule({ match = { class = '.*' }, no_initial_focus = true })"));

    // `focus_on_activate off` takes over
    {
        OK(getFromSocket("/eval hl.config({ misc = { focus_on_activate = true } })"));
        OK(getFromSocket("/eval hl.window_rule({ match = { class = 'antifocus' }, focus_on_activate = false })"));

        const std::string removeToActivate = spawnActivatingWindow("antifocus");
        if (removeToActivate.empty()) {
            FAIL_TEST("Could not spawn antifocus");
        }
        ASSERT(waitForActiveWindow("antifocus"), true);
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_default' })"));
        ASSERT(isActiveWindow("foot_default"), true);

        std::filesystem::remove(removeToActivate);
        // The focus should NOT transition, since the window rule explicitly forbids that
        ASSERT(waitForActiveWindow("antifocus", '0', false), false);
    }

    // `focus_on_activate on` takes over
    {
        OK(getFromSocket("/eval hl.config({ misc = { focus_on_activate = false } })"));
        OK(getFromSocket("/eval hl.window_rule({ match = { class = 'superfocus' }, focus_on_activate = true })"));

        const std::string removeToActivate = spawnActivatingWindow("superfocus");
        if (removeToActivate.empty()) {
            FAIL_TEST("Could not spawn superfocus");
        }
        ASSERT(waitForActiveWindow("superfocus"), true);
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_default' })"));
        ASSERT(isActiveWindow("foot_default"), true);

        std::filesystem::remove(removeToActivate);
        // Now that we requested activation, the focus SHOULD transition to superfocus, according to the window rule
        ASSERT(waitForActiveWindow("superfocus"), true);
    }
}

// tests if a pinned window contains the valid workspace after change
TEST_CASE(pinnedWorkspacesValid) {
    getFromSocket("/dispatch hl.dsp.focus({ workspace = '1337' })");

    SPAWN_FOOT("foot");

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'set', window = 'class:foot' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.pin({ action = 'toggle', window = 'class:foot' })"));

    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("workspace: 1337"), true);
        EXPECT(str.contains("pinned: 1"), true);
    }

    getFromSocket("/dispatch hl.dsp.focus({ workspace = '1338' })");

    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("workspace: 1338"), true);
        EXPECT(str.contains("pinned: 1"), true);
    }

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'unset', window = 'class:foot' })"));

    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("workspace: 1338"), true);
        EXPECT(str.contains("pinned: 0"), true);
    }
}

static std::string recordWindowStateUpdates() {
    return getFromSocket(R"(/eval do
        local state = { events = {}, subscriptions = {} }
        _G.hyprtester_window_state = state
        state.subscriptions.open = hl.on('window.open', function(window)
            if window.class == 'hyprtester_window_state' then state.window = window end
        end)
        state.subscriptions.update = hl.on('window.update_state', function(window, delta)
            if window.class ~= 'hyprtester_window_state' then return end
            local valid = type(window) == 'userdata' and window == state.window and type(delta) == 'table'
            if valid then
                for key, value in pairs(delta) do
                    valid = valid and (key == 'float' or key == 'pin') and type(value) == 'boolean'
                end
            end
            if not valid then
                table.insert(state.events, 'invalid')
                return
            end
            table.insert(state.events, tostring(delta.float) .. ':' .. tostring(delta.pin))
        end)
    end)");
}

static std::string windowStateUpdates() {
    // IPC round-trips let idle notifications drain, including when no event is expected.
    Tests::sync();
    return getFromSocket("/repl table.concat(_G.hyprtester_window_state.events, ',')");
}

static void cleanupWindowStateUpdates() {
    getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_state
        if state then
            for _, subscription in pairs(state.subscriptions) do subscription:remove() end
            if state.rule then state.rule:set_enabled(false) end
        end
        _G.hyprtester_window_state = nil
    end)");
    Tests::killAllWindows();
}

TEST_CASE(luaWindowUpdateStateDeltas) {
    CScopeGuard cleanup(cleanupWindowStateUpdates);
    OK(recordWindowStateUpdates());
    SPAWN_FOOT("hyprtester_window_state");
    SPAWN_FOOT("hyprtester_window_state_other");

    OK(getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_state
        assert(state.window == hl.get_window('class:^hyprtester_window_state$'))
        assert(not state.window.floating and not state.window.pinned)
        state.other = hl.get_window('class:^hyprtester_window_state_other$')
        assert(state.other and state.other ~= state.window)
    end)"));
    ASSERT(windowStateUpdates(), "");

    // Ignore another window's update, and target our window independently of focus.
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'enable', window = _G.hyprtester_window_state.other })"));
    ASSERT(windowStateUpdates(), "");
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'toggle', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:nil");

    OK(getFromSocket("/dispatch hl.dsp.window.pin({ action = 'enable', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true");
    OK(getFromSocket("/dispatch hl.dsp.window.pin({ action = 'disable', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true,nil:false");

    // Setting the existing values must not report an empty delta.
    OK(getFromSocket(R"(/eval do
        local window = _G.hyprtester_window_state.window
        assert(hl.dispatch(hl.dsp.window.float({ action = 'enable', window = window })).ok)
        assert(hl.dispatch(hl.dsp.window.pin({ action = 'disable', window = window })).ok)
    end)"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true,nil:false");

    OK(getFromSocket("/dispatch hl.dsp.window.pin({ action = 'enable', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true,nil:false,nil:true");
    // Tiling a pinned window reports both false values in one notification.
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'toggle', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true,nil:false,nil:true,false:false");

    // Only float differs from the last report: pin changes and reverts before idle.
    OK(getFromSocket(R"(/eval do
        local window = _G.hyprtester_window_state.window
        assert(hl.dispatch(hl.dsp.window.float({ action = 'toggle', window = window })).ok)
        assert(hl.dispatch(hl.dsp.window.pin({ action = 'enable', window = window })).ok)
        assert(hl.dispatch(hl.dsp.window.pin({ action = 'disable', window = window })).ok)
    end)"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true,nil:false,nil:true,false:false,true:nil");

    // Both properties change and revert in a single eval: no notification at all.
    OK(getFromSocket(R"(/eval do
        local window = _G.hyprtester_window_state.window
        assert(hl.dispatch(hl.dsp.window.float({ action = 'toggle', window = window })).ok)
        assert(hl.dispatch(hl.dsp.window.float({ action = 'toggle', window = window })).ok)
        assert(hl.dispatch(hl.dsp.window.pin({ action = 'enable', window = window })).ok)
        assert(hl.dispatch(hl.dsp.window.pin({ action = 'disable', window = window })).ok)
    end)"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true,nil:false,nil:true,false:false,true:nil");

    // A reverted float change must be absent while a final pin change is retained.
    OK(getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_state
        assert(hl.dispatch(hl.dsp.window.float({ action = 'toggle', window = state.window })).ok)
        assert(hl.dispatch(hl.dsp.window.float({ action = 'toggle', window = state.window })).ok)
        assert(hl.dispatch(hl.dsp.window.pin({ action = 'enable', window = state.window })).ok)
        assert(hl.dispatch(hl.dsp.window.float({ action = 'toggle', window = state.other })).ok)
    end)"));
    ASSERT(windowStateUpdates(), "true:nil,nil:true,nil:false,nil:true,false:false,true:nil,nil:true");
}

TEST_CASE(luaWindowUpdateStateCallbackMutation) {
    CScopeGuard cleanup(cleanupWindowStateUpdates);
    OK(recordWindowStateUpdates());
    SPAWN_FOOT("hyprtester_window_state");

    OK(getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_state
        assert(not state.window.floating and not state.window.pinned)
        state.callback_order = {}
        state.mutated = false
        state.subscriptions.change_on_update = hl.on('window.update_state', function(window, delta)
            if window ~= state.window then return end
            table.insert(state.callback_order, 'enter:' .. tostring(delta.float))
            if delta.float == true and not state.mutated then
                state.mutated = true
                state.change_result = hl.dispatch(hl.dsp.window.float({ action = 'disable', window = window })).ok
            end
            table.insert(state.callback_order, 'leave:' .. tostring(delta.float))
        end)
    end)"));
    ASSERT(windowStateUpdates(), "");

    // The callback's reversion must compare against the just-delivered true baseline.
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'enable', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:nil,false:nil");

    // Callback errors are swallowed: check successful dispatch and nonrecursive delivery externally.
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.change_result"), "true");
    ASSERT(getFromSocket("/repl table.concat(_G.hyprtester_window_state.callback_order, ',')"), "enter:true,leave:true,enter:false,leave:false");
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.window.floating"), "false");
}

TEST_CASE(luaWindowUpdateStateFullscreenPin) {
    CScopeGuard cleanup(cleanupWindowStateUpdates);
    OK(recordWindowStateUpdates());
    OK(getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_state
        state.allow_pin_fullscreen = hl.get_config('binds:allow_pin_fullscreen')
        assert(type(state.allow_pin_fullscreen) == 'boolean')
    end)"));
    CScopeGuard restoreConfig([this] { EXPECT_OK(getFromSocket("/eval hl.config({ binds = { allow_pin_fullscreen = _G.hyprtester_window_state.allow_pin_fullscreen } })")); });
    OK(getFromSocket("/eval hl.config({ binds = { allow_pin_fullscreen = true } })"));

    SPAWN_FOOT("hyprtester_window_state");
    OK(getFromSocket(R"(/eval do
        local window = _G.hyprtester_window_state.window
        assert(hl.dispatch(hl.dsp.window.float({ action = 'enable', window = window })).ok)
        assert(hl.dispatch(hl.dsp.window.pin({ action = 'enable', window = window })).ok)
    end)"));
    ASSERT(windowStateUpdates(), "true:true");

    // Fullscreen implicitly clears and restores pin without changing float.
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:true,nil:false");
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.window.fullscreen"), "2");

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'unset', window = _G.hyprtester_window_state.window })"));
    ASSERT(windowStateUpdates(), "true:true,nil:false,nil:true");
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.window.fullscreen"), "0");
}

TEST_CASE(luaWindowUpdateStateLifecycle) {
    CScopeGuard cleanup(cleanupWindowStateUpdates);
    OK(recordWindowStateUpdates());
    OK(getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_state
        state.rule = hl.window_rule({ match = { class = '^hyprtester_window_state$' }, float = true, pin = true })
        state.closed = 0
        state.subscriptions.close = hl.on('window.close', function(window)
            if window ~= state.window then return end
            state.closed = state.closed + 1
            state.close_result = hl.dispatch(hl.dsp.window.pin({ action = 'toggle', window = window })).ok
        end)
    end)"));

    // Initial rule-applied float/pin state is a baseline, not an update.
    SPAWN_FOOT("hyprtester_window_state");
    OK(getFromSocket("/eval local window = _G.hyprtester_window_state.window; assert(window.floating and window.pinned)"));
    ASSERT(windowStateUpdates(), "");

    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = _G.hyprtester_window_state.window })"));
    Tests::waitUntilWindowsN(0);
    ASSERT(Tests::windowCount(), 0);
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.closed"), "1");
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.close_result"), "true");
    ASSERT(windowStateUpdates(), "");

    // The baseline must already exist when a window.open subscriber changes state.
    OK(getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_state
        state.subscriptions.change_on_open = hl.on('window.open', function(window)
            if window.class ~= 'hyprtester_window_state' then return end
            state.open_result = hl.dispatch(hl.dsp.window.pin({ action = 'disable', window = window })).ok
        end)
    end)"));
    SPAWN_FOOT("hyprtester_window_state");
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.open_result"), "true");
    ASSERT(windowStateUpdates(), "nil:false");

    // Even a mutation from window.close must not queue another update.
    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = _G.hyprtester_window_state.window })"));
    Tests::waitUntilWindowsN(0);
    ASSERT(Tests::windowCount(), 0);
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.closed"), "2");
    ASSERT(getFromSocket("/repl _G.hyprtester_window_state.close_result"), "true");
    ASSERT(windowStateUpdates(), "nil:false");
}

TEST_CASE(windowruleWorkspaceEmpty) {
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot_A' }, workspace = 'empty' })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot_B' }, workspace = 'emptyn' })"));

    getFromSocket("/dispatch hl.dsp.focus({ workspace = '3' })");

    SPAWN_FOOT("foot");

    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("workspace: 3"), true);
    }

    SPAWN_FOOT("foot_A");

    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("workspace: 1"), true);
    }

    getFromSocket("/dispatch hl.dsp.focus({ workspace = '3' })");
    SPAWN_FOOT("foot_B");
    {
        auto str = getFromSocket("/activewindow");
        EXPECT(str.contains("workspace: 4"), true);
    }
}

TEST_CASE(contentWindowRules) {
    // kill me PLEASE

    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot_content_string' }, content = 'game' })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot_content_numbers' }, content = '3' })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { content = 'game' }, border_size = 10 })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { content = '3' }, opacity = '0.5' })"));

#define TEST_PROPS()                                                                                                                                                               \
    EXPECT_CONTAINS(getFromSocket("/getprop active border_size"), "10");                                                                                                           \
    EXPECT_CONTAINS(getFromSocket("/getprop active opacity"), "0.5");

    SPAWN_FOOT("foot_content_string");
    waitForActiveWindow("foot_content_string");
    TEST_PROPS();

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);

    SPAWN_FOOT("foot_content_numbers");
    waitForActiveWindow("foot_content_numbers");
    TEST_PROPS();

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);

#undef TEST_PROPS
}

TEST_CASE(issue14038) {
    SPAWN_FOOT("foot_14038");

    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = 'special:a', follow = false, window = 'class:foot_14038' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'toggle', window = 'class:foot_14038' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.pin({ action = 'toggle', window = 'class:foot_14038' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'toggle', window = 'class:foot_14038' })"));

    // this should not crash hyprland. If we are alive, we good.
}

TEST_CASE(issue14134) {
    OK(getFromSocket("/output create headless HEADLESS-4"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ monitor = 'HEADLESS-4' })"));

    SPAWN_FOOT("foot_14134");

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'toggle', window = 'class:foot_14134' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.pin({ action = 'toggle', window = 'class:foot_14134' })"));

    OK(getFromSocket("/eval hl.monitor({ output = 'HEADLESS-4', disabled = true })"));

    // will return error, should not be OK.
    getFromSocket("/dispatch hl.dsp.window.pin({ action = 'toggle', window = 'class:foot_14134' })");

    OK(getFromSocket("/reload"));
    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);
    OK(getFromSocket("/output remove HEADLESS-4"));
}

TEST_CASE(specialFloatRecenters) {
    SPAWN_FOOT("foot_special_float_recenter");

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'set', window = 'class:foot_special_float_recenter' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.resize({ x = 10, y = 10, window = 'class:foot_special_float_recenter' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = 'special:recenter', follow = false, window = 'class:foot_special_float_recenter' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.move({ x = 50000, y = 50000, window = 'class:foot_special_float_recenter' })"));

    OK(getFromSocket("/dispatch hl.dsp.workspace.toggle_special('recenter')"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_special_float_recenter' })"));

    const auto active = getFromSocket("/activewindow");
    EXPECT_CONTAINS(active, "class: foot_special_float_recenter");
    EXPECT_CONTAINS(active, "size: 10,10");
    EXPECT_CONTAINS(active, "at: 955,535");

    OK(getFromSocket("/dispatch hl.dsp.workspace.toggle_special('recenter')"));
    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);
}

TEST_CASE(exactWindowSelectors) {
    SPAWN_FOOT("foot_A");
    SPAWN_FOOT("foot_B");

    getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_B' })");
    auto target    = getFromSocket("/activewindow");
    auto addr      = getWindowAddress(target);
    auto pid       = Tests::getAttribute(target, "pid");
    auto stable_id = Tests::getAttribute(target, "stableID");

    getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })");
    // Focus window by address
    OK(getFromSocket(std::format("/dispatch hl.dsp.focus({{ window = 'address:0x{}' }})", addr)));
    EXPECT_CONTAINS(getFromSocket("/activewindow"), "class: foot_B");

    getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })");
    // Focus window by PID
    OK(getFromSocket(std::format("/dispatch hl.dsp.focus({{ window = 'pid:{}' }})", pid)));
    EXPECT_CONTAINS(getFromSocket("/activewindow"), "class: foot_B");

    getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })");
    // Focus window by stable ID
    OK(getFromSocket(std::format("/dispatch hl.dsp.focus({{ window = 'stableid:{}' }})", stable_id)));
    EXPECT_CONTAINS(getFromSocket("/activewindow"), "class: foot_B");
}

// TODO: decompose this into multiple test cases
TEST_CASE(windows) {
    // test on workspace "window"
    OK(getFromSocket("/dispatch hl.dsp.focus({ monitor = 'HEADLESS-2' })"));
    NLog::log("{}Switching to workspace `window`", Colors::YELLOW);
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 'name:window' })"));

    SPAWN_FOOT("foot_A");

    // check foot properties. One foot should take the entire screen, as this is smart gaps
    NLog::log("{}Expecting foot_A to take up the whole screen", Colors::YELLOW);
    {
        auto str = getFromSocket("/clients");
        EXPECT(str.contains("at: 0,0"), true);
        EXPECT(str.contains("size: 1920,1080"), true);
        EXPECT(str.contains("fullscreen: 0"), true);
    }

    NLog::log("{}Testing window split ratios", Colors::YELLOW);
    {
        const double INITIAL_RATIO = 1.25;
        const int    GAPSIN        = 5;
        const int    GAPSOUT       = 20;
        const int    BORDERSIZE    = 2;
        const int    BORDERS       = BORDERSIZE * 2;
        const int    MONITOR_W     = 1920;
        const int    MONITOR_H     = 1080;

        const float  totalAvailableHeight   = MONITOR_H - (GAPSOUT * 2);
        const int    HEIGHT                 = std::floor(totalAvailableHeight) - BORDERS;
        const float  availableWidthForSplit = MONITOR_W - (GAPSOUT * 2) - GAPSIN;

        auto         calculateFinalWidth = [&](double boxWidth, bool isLeftWindow) {
            double gapLeft  = isLeftWindow ? GAPSOUT : GAPSIN;
            double gapRight = isLeftWindow ? GAPSIN : GAPSOUT;
            return std::floor(boxWidth - gapLeft - gapRight - BORDERS);
        };

        double       geomBoxWidthA_R1 = (availableWidthForSplit * INITIAL_RATIO / 2.0) + GAPSOUT + (GAPSIN / 2.0);
        double       geomBoxWidthB_R1 = MONITOR_W - geomBoxWidthA_R1;
        const int    WIDTH1           = calculateFinalWidth(geomBoxWidthB_R1, false);

        const double INVERTED_RATIO   = 0.75;
        double       geomBoxWidthA_R2 = (availableWidthForSplit * INVERTED_RATIO / 2.0) + GAPSOUT + (GAPSIN / 2.0);
        double       geomBoxWidthB_R2 = MONITOR_W - geomBoxWidthA_R2;
        const int    WIDTH2           = calculateFinalWidth(geomBoxWidthB_R2, false);
        const int    WIDTH_A_FINAL    = calculateFinalWidth(geomBoxWidthA_R2, true);

        OK(getFromSocket("/eval hl.config({ dwindle = { default_split_ratio = 1.25 } })"));

        SPAWN_FOOT("foot_B");

        NLog::log("{}Expecting foot_B size: {},{}", Colors::YELLOW, WIDTH1, HEIGHT);
        EXPECT_CONTAINS(getFromSocket("/activewindow"), std::format("size: {},{}", WIDTH1, HEIGHT));

        OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'activewindow' })"));
        Tests::waitUntilWindowsN(1);

        NLog::log("{}Inverting the split ratio", Colors::YELLOW);
        OK(getFromSocket("/eval hl.config({ dwindle = { default_split_ratio = 0.75 } })"));

        SPAWN_FOOT("foot_B");

        try {
            NLog::log("{}Expecting foot_B size: {},{}", Colors::YELLOW, WIDTH2, HEIGHT);

            {
                auto data = getFromSocket("/activewindow");
                data      = data.substr(data.find("size:") + 5);
                data      = data.substr(0, data.find('\n'));

                Hyprutils::String::CVarList2 sizes(std::move(data), 0, ',');

                EXPECT_MAX_DELTA(std::stoi(std::string{sizes[0]}), WIDTH2, 2);
                EXPECT_MAX_DELTA(std::stoi(std::string{sizes[1]}), HEIGHT, 2);
            }

            OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_A' })"));
            NLog::log("{}Expecting foot_A size: {},{}", Colors::YELLOW, WIDTH_A_FINAL, HEIGHT);

            {
                auto data = getFromSocket("/activewindow");
                data      = data.substr(data.find("size:") + 5);
                data      = data.substr(0, data.find('\n'));

                Hyprutils::String::CVarList2 sizes(std::move(data), 0, ',');

                EXPECT_MAX_DELTA(std::stoi(std::string{sizes[0]}), WIDTH_A_FINAL, 2);
                EXPECT_MAX_DELTA(std::stoi(std::string{sizes[1]}), HEIGHT, 2);
            }

        } catch (...) { FAIL_TEST("Exception thrown"); }

        OK(getFromSocket("/eval hl.config({ dwindle = { default_split_ratio = 1 } })"));
    }

    // open xeyes
    NLog::log("{}Spawning xeyes", Colors::YELLOW);
    getFromSocket("/dispatch hl.dsp.exec_cmd('xeyes')");

    NLog::log("{}Keep checking if xeyes spawned", Colors::YELLOW);
    Tests::waitUntilWindowsN(3);

    NLog::log("{}Expecting 3 windows", Colors::YELLOW);
    ASSERT(Tests::windowCount(), 3);

    NLog::log("{}Checking props of xeyes", Colors::YELLOW);
    // check some window props of xeyes, try to float it
    {
        auto str = getFromSocket("/clients");
        EXPECT_NOT_CONTAINS(str, "floating: 1");
        getFromSocket("/dispatch hl.dsp.window.float({ action = 'set', window = 'class:XEyes' })");
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        str = getFromSocket("/clients");
        EXPECT_CONTAINS(str, "floating: 1");
    }

    // kill all
    NLog::log("{}Killing all windows", Colors::YELLOW);
    Tests::killAllWindows();

    NLog::log("{}Expecting 0 windows", Colors::YELLOW);
    ASSERT(Tests::windowCount(), 0);

    getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })");

    NLog::log("{}Testing spawning a floating window over a fullscreen window", Colors::YELLOW);
    {
        SPAWN_FOOT("foot_A");
        OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set' })"));
        ASSERT(Tests::windowCount(), 1);

        OK(getFromSocket("/dispatch hl.dsp.exec_cmd('foot', { float = true })"));
        Tests::waitUntilWindowsN(2);

        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:^foot$' })"));
        const auto focused1 = getFromSocket("/activewindow");
        EXPECT_CONTAINS(focused1, "class: foot\n");

        OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'activewindow' })"));
        Tests::waitUntilWindowsN(1);

        // The old window should be focused again
        const auto focused2 = getFromSocket("/activewindow");
        EXPECT_CONTAINS(focused2, "class: foot_A\n");

        NLog::log("{}Killing all windows", Colors::YELLOW);
        Tests::killAllWindows();
    }

    NLog::log("{}Testing minsize/maxsize rules for tiled windows", Colors::YELLOW);
    {
        // Enable the config for testing, test max/minsize for tiled windows and centering
        OK(getFromSocket("/eval hl.config({ misc = { size_limits_tiled = 1 } })"));
        OK(getFromSocket("/eval hl.window_rule({ name = 'foot-max-rule', match = { class = 'foot_maxsize' } })"));
        OK(getFromSocket("/eval hl.window_rule({ name = 'foot-max-rule', max_size = '1500 500' })"));
        OK(getFromSocket("r/eval hl.window_rule({ name = 'foot-max-rule', min_size = '1200 500' })"));
        SPAWN_FOOT("foot_maxsize");

        auto dwindle = getFromSocket("/activewindow");
        EXPECT_CONTAINS(dwindle, "size: 1500,500");
        EXPECT_CONTAINS(dwindle, "at: 210,290");

        // Fuck this test, it's fucking stupid - vax
        // if (!spawnFoot("foot_maxsize"))
        //     return false;
        // EXPECT_CONTAINS(getFromSocket("/activewindow"), "size: 1200,500");

        Tests::killAllWindows();
        ASSERT(Tests::windowCount(), 0);

        OK(getFromSocket("r/eval hl.config({ general = { layout = 'master' } })"));

        SPAWN_FOOT("foot_maxsize");

        auto master = getFromSocket("/activewindow");
        EXPECT_CONTAINS(master, "size: 1500,500");
        EXPECT_CONTAINS(master, "at: 210,290");

        SPAWN_FOOT("foot_maxsize");

        // FIXME: I can't be arsed.
        OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_maxsize' })"));
        //        EXPECT_CONTAINS(getFromSocket("/activewindow"), "size: 1200,500")

        NLog::log("{}Reloading config", Colors::YELLOW);
        OK(getFromSocket("/reload"));
        Tests::killAllWindows();
        ASSERT(Tests::windowCount(), 0);
    }

    NLog::log("{}Testing minsize/maxsize rules", Colors::YELLOW);
    {
        // Disable size limits tiled and check if props are working and not getting skipped
        OK(getFromSocket("/eval hl.config({ misc = { size_limits_tiled = 0 } })"));
        OK(getFromSocket("/eval hl.window_rule({ name = 'foot-max-rule', match = { class = 'foot_maxsize' } })"));
        OK(getFromSocket("/eval hl.window_rule({ name = 'foot-max-rule', max_size = '1500 500' })"));
        OK(getFromSocket("r/eval hl.window_rule({ name = 'foot-max-rule', min_size = '1200 500' })"));
        SPAWN_FOOT("foot_maxsize");

        {
            auto res = getFromSocket("/getprop active max_size");
            EXPECT_CONTAINS(res, "1500");
            EXPECT_CONTAINS(res, "500");
        }

        {
            auto res = getFromSocket("/getprop active min_size");
            EXPECT_CONTAINS(res, "1200");
            EXPECT_CONTAINS(res, "500");
        }

        NLog::log("{}Reloading config", Colors::YELLOW);
        OK(getFromSocket("/reload"));
        Tests::killAllWindows();
        ASSERT(Tests::windowCount(), 0);
    }

    {
        // Set float
        OK(getFromSocket("/eval hl.window_rule({ name = 'foot-max-rule', match = { class = 'foot_maxsize' } })"));
        OK(getFromSocket("/eval hl.window_rule({ name = 'foot-max-rule', max_size = '1200 500' })"));
        OK(getFromSocket("r/eval hl.window_rule({ name = 'foot-max-rule', min_size = '1200 500' })"));
        OK(getFromSocket("r/eval hl.window_rule({ name = 'foot-max-rule', float = true })"));
        SPAWN_FOOT("foot_maxsize");

        {
            auto res = getFromSocket("/getprop active max_size");
            EXPECT_CONTAINS(res, "1200");
            EXPECT_CONTAINS(res, "500");
        }

        {
            auto res = getFromSocket("/getprop active min_size");
            EXPECT_CONTAINS(res, "1200");
            EXPECT_CONTAINS(res, "500");
        }

        {
            auto res = getFromSocket("/activewindow");
            EXPECT_CONTAINS(res, "size: 1200,500");
        }

        NLog::log("{}Reloading config", Colors::YELLOW);
        OK(getFromSocket("/reload"));
        Tests::killAllWindows();
        ASSERT(Tests::windowCount(), 0);
    }

    NLog::log("{}Testing window rules", Colors::YELLOW);
    SPAWN_FOOT("wr_foot");
    {
        auto      str  = getFromSocket("/activewindow");
        const int SIZE = 200;
        EXPECT_CONTAINS(str, "floating: 1");
        EXPECT_CONTAINS(str, std::format("size: {},{}", SIZE, SIZE));
        EXPECT_NOT_CONTAINS(str, "pinned: 1");
    }

    OK(getFromSocket("/eval hl.window_rule({ name = 'wr-foot-stuff', opacity = '0.5 0.5 override' })"));

    {
        auto str = getFromSocket("/getprop active opacity");
        EXPECT_CONTAINS(str, "0.5");
    }

    OK(getFromSocket("/eval hl.window_rule({ name = 'special-magic-foot', match = { class = 'magic_foot' } })"));
    OK(getFromSocket("/eval hl.window_rule({ name = 'special-magic-foot', workspace = 'special:magic' })"));

    SPAWN_FOOT("magic_foot");

    {
        auto str = getFromSocket("/activewindow");
        EXPECT_CONTAINS(str, "special:magic");
        EXPECT_NOT_CONTAINS(str, "workspace: 9");
    }

    if (auto str = getFromSocket("/monitors"); str.contains("magic)")) {
        OK(getFromSocket("/dispatch hl.dsp.workspace.toggle_special('magic')"));
    }

    Tests::killAllWindows();

    OK(getFromSocket("/eval hl.window_rule({ name = 'border-magic-foot', match = { class = 'border_foot' } })"));
    OK(getFromSocket("/eval hl.window_rule({ name = 'border-magic-foot', border_color = 'rgba(c6ff00ff) rgba(ff0000ee) 45deg' })"));

    SPAWN_FOOT("border_foot");

    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:border_foot' })"));

    {
        auto str = getFromSocket("/getprop active active_border_color");
        EXPECT_CONTAINS(str, "ffc6ff00");
        EXPECT_CONTAINS(str, "eeff0000");
        EXPECT_CONTAINS(str, "45deg");
    }

    Tests::killAllWindows();

    SPAWN_FOOT("tag_foot");

    {
        auto str = getFromSocket("/activewindow");
        EXPECT_CONTAINS(str, "floating: 1");
    }

    OK(getFromSocket("/reload"));
    Tests::killAllWindows();

    // test rules that overlap effects but don't overlap props
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'overlap_foot' }, border_size = 0 })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { fullscreen = false }, border_size = 10 })"));

    SPAWN_FOOT("overlap_foot");

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "10");
    }

    OK(getFromSocket("/reload"));
    Tests::killAllWindows();

    // test persistent_size between floating window launches
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'persistent_size_foot' }, persistent_size = true, float = true })"));

    SPAWN_FOOT("persistent_size_foot");

    OK(getFromSocket("/dispatch hl.dsp.window.resize({ x = 600, y = 400 })"));

    {
        // foot may still have a frame at its own size in flight, which the floating window takes for a moment:
        // a window closed in that moment stores that size. Wait until it has settled at the new one.
        auto str = waitForSettledActiveWindowSize("600,400");
        EXPECT_CONTAINS(str, "size: 600,400");
        EXPECT_CONTAINS(str, "floating: 1");
    }

    Tests::killAllWindows();

    SPAWN_FOOT("persistent_size_foot");

    {
        auto str = waitForSettledActiveWindowSize("600,400");
        EXPECT_CONTAINS(str, "size: 600,400");
        EXPECT_CONTAINS(str, "floating: 1");
    }

    OK(getFromSocket("/reload"));
    Tests::killAllWindows();

    OK(getFromSocket("/eval hl.config({ general = { border_size = 0 } })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { float = true }, border_size = 10 })"));

    SPAWN_FOOT("border_foot");

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "0");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'toggle' })"));

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "10");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'toggle' })"));

    {
        auto str = getFromSocket("/getprop active border_size");
        EXPECT_CONTAINS(str, "0");
    }

    OK(getFromSocket("/reload"));
    Tests::killAllWindows();

    // test expression rules
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'expr_foot' }, float = true, size = {'monitor_w * 0.5', 'monitor_h * 0.5'}, "
                     "min_size = {'monitor_w * 0.25', 'monitor_h * 0.25'}, max_size = {'monitor_w * 0.75', 'monitor_h * 0.75'}, "
                     "move = {'20 + (monitor_w * 0.1)', 'monitor_h * 0.5'} })"));

    SPAWN_FOOT("expr_foot");

    {
        auto str = getFromSocket("/activewindow");
        EXPECT_CONTAINS(str, "floating: 1");
        EXPECT_CONTAINS(str, "at: 212,540");
        EXPECT_CONTAINS(str, "size: 960,540");

        auto min = getFromSocket("/getprop active min_size");
        EXPECT_CONTAINS(min, "480");
        EXPECT_CONTAINS(min, "270");

        auto max = getFromSocket("/getprop active max_size");
        EXPECT_CONTAINS(max, "1440");
        EXPECT_CONTAINS(max, "810");
    }

    OK(getFromSocket("/reload"));
    Tests::killAllWindows();
}

TEST_CASE(cycle_nextTiled) {
    // If the user specifically requests a tiled window, give them a tiled window

    for (const auto& win : {"a", "b", "c", "d"}) {
        SPAWN_FOOT(win);
    }

    // float the class:a window
    OK(getFromSocket("/dispatch hl.dsp.window.float({action = 'enable', window = 'class:a'})"));
    // float the class:c window
    OK(getFromSocket("/dispatch hl.dsp.window.float({action = 'enable', window = 'class:c'})"));
    // float the class:d window
    OK(getFromSocket("/dispatch hl.dsp.window.float({action = 'enable', window = 'class:d'})"));

    // establish focus history
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:a'})")); // floating
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:b'})")); // tiled  <-- What we want to focus on
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:c'})")); // floating
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:d'})")); // floating

    // request a tiled window
    OK(getFromSocket("/dispatch hl.dsp.window.cycle_next({ next = true, tiled = true, floating = false})"));

    ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: b");
}

TEST_CASE(cycle_nextFloating) {
    // If the user specifically requests a floating window, give them a floating window

    for (const auto& win : {"a", "b", "c", "d"}) {
        SPAWN_FOOT(win);
    }

    // float the class:b window
    OK(getFromSocket("/dispatch hl.dsp.window.float({action = 'enable', window = 'class:b'})"));

    // establish focus history
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:a'})")); // tiled
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:b'})")); // floating  <-- What we want to focus on
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:c'})")); // tiled
    OK(getFromSocket("/dispatch hl.dsp.focus({window = 'class:d'})")); // tiled

    // request a floating window
    OK(getFromSocket("/dispatch hl.dsp.window.cycle_next({ next = true, tiled = false, floating = true})"));

    ASSERT_CONTAINS(getFromSocket("/activewindow"), "class: b");
}

TEST_CASE(discussion14233) {
    // toggling fullscreen should not mess up workspace state on a 2 window workspace
    // with smart gaps

    OK(getFromSocket(R"#(/eval hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
hl.window_rule({
    name  = "no-gaps-wtv1",
    match = { float = false, workspace = "w[tv1]" },
    border_size = 0,
    rounding    = 0,
})
hl.window_rule({
    name  = "no-gaps-f1",
    match = { float = false, workspace = "f[1]" },
    border_size = 0,
    rounding    = 0,
})
)#"));

    SPAWN_FOOT("a");

    // just make sure smart gaps work
    {
        auto str = getFromSocket("/clients");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "at: 0,0");
    }

    SPAWN_FOOT("a");

    {
        auto str = getFromSocket("/clients");
        ASSERT_COUNT_STRING(str, "size: 931,1036", 2);
        ASSERT_CONTAINS(str, "at: 22,22");
        ASSERT_CONTAINS(str, "at: 967,22");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));

    {
        auto str = getFromSocket("/clients");
        ASSERT_COUNT_STRING(str, "size: 931,1036", 2);
        ASSERT_CONTAINS(str, "at: 22,22");
        ASSERT_CONTAINS(str, "at: 967,22");
    }
}

TEST_CASE(execRulesWorkspaceOverride) {
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot_exec_override' }, workspace = '2' })"));

    OK(getFromSocket("/dispatch hl.dsp.exec_cmd('[workspace 3] foot --class foot_exec_override')"));

    Tests::waitUntilWindowsN(1);

    auto str = getFromSocket("/activewindow");
    EXPECT_CONTAINS(str, "class: foot_exec_override");
    EXPECT_CONTAINS(str, "workspace: 3");

    Tests::killAllWindows();
}

TEST_CASE(execRulesTagMutation) {
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot_tag_mutate' }, workspace = '2' })"));
    OK(getFromSocket("/eval hl.window_rule({ match = { class = 'foot_tag_mutate' }, tag = 'test_tag' })"));

    OK(getFromSocket("/dispatch hl.dsp.exec_cmd('[workspace 3] foot --class foot_tag_mutate')"));

    Tests::waitUntilWindowsN(1);

    auto str = getFromSocket("/activewindow");
    EXPECT_CONTAINS(str, "class: foot_tag_mutate");
    EXPECT_CONTAINS(str, "workspace: 3");

    Tests::killAllWindows();
}

TEST_CASE(execRulesDescendantProcess) {
    OK(getFromSocket("/dispatch hl.dsp.exec_cmd('foot --class foot_exec_workspace & wait', { workspace = '2 silent' })"));

    Tests::waitUntilWindowsN(1);

    EXPECT_CONTAINS(getFromSocket("/getprop class:foot_exec_workspace no_focus"), "false");
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_exec_workspace' })"));

    {
        const auto active = getFromSocket("/activewindow");
        EXPECT_CONTAINS(active, "class: foot_exec_workspace");
        EXPECT_CONTAINS(active, "workspace: 2");
    }

    OK(getFromSocket(
        "/dispatch hl.dsp.exec_cmd('[workspace 3; border_size 7] foot --class foot_exec_special & wait', { workspace = 'special:exec_rules silent', no_initial_focus = true, "
        "no_focus = true })"));

    Tests::waitUntilWindowsN(2);

    EXPECT_CONTAINS(getFromSocket("/getprop class:foot_exec_special no_focus"), "true");
    EXPECT_CONTAINS(getFromSocket("/getprop class:foot_exec_special border_size"), "7");

    {
        const auto active = getFromSocket("/activewindow");
        EXPECT_CONTAINS(active, "class: foot_exec_workspace");
        EXPECT_CONTAINS(active, "workspace: 2");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.set_prop({ window = 'class:foot_exec_special', prop = 'no_focus', value = 'false' })"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_exec_special' })"));

    {
        const auto active = getFromSocket("/activewindow");
        EXPECT_CONTAINS(active, "class: foot_exec_special");
        EXPECT_CONTAINS(active, "special:exec_rules");
    }

    Tests::killAllWindows();
}

TEST_CASE(execRulesPendingIsolation) {
    OK(getFromSocket("/eval do hl.exec_cmd('sleep 1 && foot --class foot_exec_first', { workspace = '2 silent' }); "
                     "hl.exec_cmd('sleep 2 && foot --class foot_exec_second', { workspace = 'special:exec_rules_pending silent', no_initial_focus = true, no_focus = true }) end"));

    Tests::waitUntilWindowsN(1);

    EXPECT_CONTAINS(getFromSocket("/getprop class:foot_exec_first no_focus"), "false");
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_exec_first' })"));

    {
        const auto active = getFromSocket("/activewindow");
        EXPECT_CONTAINS(active, "class: foot_exec_first");
        EXPECT_CONTAINS(active, "workspace: 2");
    }

    Tests::waitUntilWindowsN(2);

    EXPECT_CONTAINS(getFromSocket("/getprop class:foot_exec_first no_focus"), "false");
    EXPECT_CONTAINS(getFromSocket("/getprop class:foot_exec_second no_focus"), "true");

    OK(getFromSocket("/dispatch hl.dsp.window.set_prop({ window = 'class:foot_exec_second', prop = 'no_focus', value = 'false' })"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_exec_second' })"));

    {
        const auto active = getFromSocket("/activewindow");
        EXPECT_CONTAINS(active, "class: foot_exec_second");
        EXPECT_CONTAINS(active, "special:exec_rules_pending");
    }

    Tests::killAllWindows();
}

TEST_CASE(pinnedRetainsPositionOnWorkspaceChange) {
    SPAWN_FOOT("a");

    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'enable' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.pin()"));

    {
        auto str = getFromSocket("/clients");
        ASSERT_CONTAINS(str, "pinned: 1");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.move({ x = 1900, y = 1000 })"));

    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '2' })"));

    {
        auto str = getFromSocket("/workspaces");
        ASSERT_CONTAINS(str, "workspace ID 2");
    }

    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));

    {
        auto str = getFromSocket("/workspaces");
        ASSERT_CONTAINS(str, "workspace ID 1");
    }

    {
        auto str = getFromSocket("/clients");
        ASSERT_CONTAINS(str, "pinned: 1");
        ASSERT_CONTAINS(str, "at: 1900,1000");
    }
}

TEST_CASE(monitorrule) {
    if (getFromSocket("/monitors all").contains("HEADLESS-3"))
        OK(getFromSocket("/output remove HEADLESS-3"));

    OK(getFromSocket("/output create headless HEADLESS-3"));
    const auto  MONALL = getFromSocket("/monitors all");
    CScopeGuard guard([&] {
        if (MONALL.contains("HEADLESS-3"))
            OK(getFromSocket("/output remove HEADLESS-3"));
    });

    OK(getFromSocket("/dispatch hl.dsp.focus({ monitor = 'HEADLESS-2' })"));
    OK(getFromSocket("/eval hl.window_rule({ name = 'monitorrule', match = { class = 'monitor_foot' }, monitor = 'HEADLESS-3' })"));

    SPAWN_FOOT("monitor_foot");
    ASSERT(Tests::windowCount(), 1);
    const auto MON_SRC_ID = Tests::getAttribute(getFromSocket("/activewindow"), "monitor");
    ASSERT_CONTAINS(MONALL, std::format("HEADLESS-3 (ID {}", MON_SRC_ID));
    EXPECT_CONTAINS(getFromSocket("/activeworkspace"), "HEADLESS-3");

    Tests::killAllWindows();
    OK(getFromSocket("/reload"));

    OK(getFromSocket("/dispatch hl.dsp.focus({ monitor = 'HEADLESS-2' })"));
    OK(getFromSocket("/eval hl.window_rule({ name = 'monitorrule', match = { class = 'silent_foot' }, monitor = 'HEADLESS-3 silent' })"));

    SPAWN_FOOT("silent_foot");
    const auto SILENT_SRC_ID = Tests::getAttribute(getFromSocket("/clients"), "monitor");
    ASSERT_CONTAINS(MONALL, std::format("HEADLESS-3 (ID {}", SILENT_SRC_ID));
    EXPECT_CONTAINS(getFromSocket("/activeworkspace"), "HEADLESS-2");
}

TEST_CASE(getFullscreenHandler) {

    // Correctly detect the FS handler of a window

    // We will use scrolling as it has a layout handled FS

    // First test that it's obtained properly in a default FS handled layout - dwindle

    OK(getFromSocket("r/eval hl.config({ general = { layout = 'dwindle' } })"));

    // Tiled
    SPAWN_FOOT("cat");

    // FS - check - unFS
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));
    EXPECT(Tests::getAttribute(getFromSocket("/activewindow"), "fullscreenHandler"), "default");
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));

    // Floating

    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'set' })"));

    // FS - check - unFS
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));
    EXPECT(Tests::getAttribute(getFromSocket("/activewindow"), "fullscreenHandler"), "default");
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));

    // switch to scrolling layout

    OK(getFromSocket("r/eval hl.config({ general = { layout = 'scrolling' } })"));

    // Window still floating. There is no layout handled floating FS behaviour

    // FS - check - unFS
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));
    EXPECT(Tests::getAttribute(getFromSocket("/activewindow"), "fullscreenHandler"), "default");
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));

    // tile the window, and explicitly default handle it
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'unset' })"));

    // FS - check - unFS
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ layout_aware = false })"));
    EXPECT(Tests::getAttribute(getFromSocket("/activewindow"), "fullscreenHandler"), "default");
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ layout_aware = false })"));

    // check if layout handler is correctly ontaind

    // FS - check - unFS
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));
    EXPECT(Tests::getAttribute(getFromSocket("/activewindow"), "fullscreenHandler"), "scrolling");
    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen()"));
}

TEST_CASE(sendFsWindowToAnotherWorkspace) {

    /*
    If default handled, will be moved as default handled to other workspace.
    If layout handled, will be reFSed using target workspace's layout handled if exists

    FS sizes are the same for all FS handlers so we share them

    */

    // Test Default Handled FS

    // Establish 5 workspaces with layouts
    OK(getFromSocket("/eval hl.workspace_rule({workspace = '1', layout = 'dwindle'})"));
    OK(getFromSocket("/eval hl.workspace_rule({workspace = '2', layout = 'master'})"));
    OK(getFromSocket("/eval hl.workspace_rule({workspace = '3', layout = 'monocle'})"));
    OK(getFromSocket("/eval hl.workspace_rule({workspace = '4', layout = 'scrolling'})"));
    OK(getFromSocket("/eval hl.workspace_rule({workspace = '5', layout = 'scrolling'})"));

    // set gaps_out to a high value and establish a workspace rule to catch cases where maximised gets the wrong work area size
    OK(getFromSocket("/eval hl.config({ general = { gaps_out = 20,}})"));
    OK(getFromSocket("/eval hl.workspace_rule({ workspace = 'f[1]', gaps_out = 0, })"));

    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));

    SPAWN_FOOT("traveller_1");

    // Testing with Tiled window

    /*
    Test with default handled FS window
    */

    // Testing Fullscreen

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'fullscreen'})"));

    // dwindle
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 1");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // master - try with follow = false
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '2', follow = false })"));
    // go to that workspace post move - expect FS window to be in focus
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 2 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 2");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // monocle
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '3' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 3");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // scroll
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // Try with follow = false for scroll since it's default to layout handled and vice versa and should be tested thoroughly

    // monocle
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '3' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 3");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // scroll - try with follow = false
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4', follow = false })"));
    // go to that workspace post move - expect FS window to be in focus
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 4 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // before next test kill the window and make a new one on workspace 1 to get a fresh start

    Tests::killAllWindows();
    Tests::waitUntilWindowsN(0);

    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));
    SPAWN_FOOT("traveller_2");

    // Testing Maximised

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'maximized'})"));

    // dwindle
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 1");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // master - try with follow = false
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '2', follow = false })"));
    // go to that workspace post move - expect FS window to be in focus
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 2 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 2");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // monocle
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '3' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 3");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // scroll
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // Try with follow = false for scroll since it's default to layout handled and vice versa and should be tested thoroughly

    // monocle
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '3' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 3");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // scroll - try with follow = false
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4', follow = false })"));
    // go to that workspace post move - expect FS window to be in focus
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 4 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // Before next test kill the window and make a new one on workspace 1 to get a fresh start

    Tests::killAllWindows();
    Tests::waitUntilWindowsN(0);

    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));
    SPAWN_FOOT("traveller_3");

    /*
    Test Layout Handled FS - Move btw scroll-scroll and scroll-dwindle
    */

    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4' })"));

    // fullscreen

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'fullscreen'})"));

    // scroll
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: scrolling");
    }

    // move to another scrolling workspace
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '5' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 5");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        // both have layout handlers so expected to use that
        ASSERT_CONTAINS(str, "fullscreenHandler: scrolling");
    }

    // dwindle
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '1' })"));
    // go to that workspace post move - expect FS window to be in focus
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 1");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        // No layout handler in dwindle so expect it to fall back to using the only available handler which is default
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // scroll - try with follow = false
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4', follow = false })"));
    // go to that workspace post move - expect FS window to be in focus
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 4 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        // It's not coming from a default handler so expect it to remain as such
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // maximised

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'maximized'})"));

    // scroll
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: scrolling");
    }

    // move to another scrolling workspace
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '5' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 5");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        // both have layout handlers so expected to use that
        ASSERT_CONTAINS(str, "fullscreenHandler: scrolling");
    }

    // dwindle
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '1' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 1");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        // No layout handler in dwindle so expect it to fall back to using the only available handler which is default
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // scroll - try with follow = false
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4', follow = false })"));
    // go to that workspace post move - expect FS window to be in focus
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 4 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        // It's coming from a default handler so expect it to remain as such
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
    }

    // Testing the same things but with floating
    // floating has no layout handled Fs so just test moving a floating FS window around with maximised and fullscreen values changing between every move

    Tests::killAllWindows();
    Tests::waitUntilWindowsN(0);

    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));
    SPAWN_FOOT("traveller_float");
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'set', window = 'class:traveller_float' })"));

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'fullscreen'})"));

    // workspace 1 (dwindle) - fullscreen
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 1");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    // move to workspace 2 (master) - still fullscreen, then toggle to maximized
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '2' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 2");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'maximized'})"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 2");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    // move to workspace 3 (monocle) - still maximized, then toggle to fullscreen
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '3' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 3");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'fullscreen'})"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 3");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    // move to workspace 4 (scrolling) - still fullscreen, then toggle to maximized
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '4' })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'maximized'})"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 4");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    // move to workspace 5 (scrolling) with follow = false - still maximized, then toggle to fullscreen
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '5', follow = false })"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 5 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 2,2");
        ASSERT_CONTAINS(str, "size: 1916,1076");
        ASSERT_CONTAINS(str, "workspace: 5");
        ASSERT_CONTAINS(str, "fullscreen: 1");
        ASSERT_CONTAINS(str, "fullscreenClient: 1");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({mode = 'fullscreen'})"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 5");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }

    // move back to workspace 1 (dwindle) with follow = false - still fullscreen
    OK(getFromSocket("/dispatch hl.dsp.window.move({ workspace = '1', follow = false })"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 1 })"));
    {
        const auto str = getFromSocket("/activewindow");
        ASSERT_CONTAINS(str, "at: 0,0");
        ASSERT_CONTAINS(str, "size: 1920,1080");
        ASSERT_CONTAINS(str, "workspace: 1");
        ASSERT_CONTAINS(str, "fullscreen: 2");
        ASSERT_CONTAINS(str, "fullscreenClient: 2");
        ASSERT_CONTAINS(str, "fullscreenHandler: default");
        ASSERT_CONTAINS(str, "floating: 1");
    }
}

TEST_CASE(floatingForceOnscreen) {
    // Test: move a floating window around
    NLog::log("{}Testing force-onscreen for existing floating windows", Colors::GREEN);
    SPAWN_FOOT("a");
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'on' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.resize({ x = 100, y = 100, relative = false })"));

    // No constraints
    OK(getFromSocket("/eval hl.config({ misc = { float_force_onscreen = 0 }})"));
    OK(getFromSocket("/dispatch hl.dsp.window.move({ x = -110, y = 0, relative = false })"));
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "at: -110,0");

    // Partially onscreen
    OK(getFromSocket("/eval hl.config({ misc = { float_force_onscreen = 1 }})"));
    OK(getFromSocket("/dispatch hl.dsp.window.move({ x = -110, y = 0, relative = false })"));
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "at: -50,0");

    // Fully onscreen
    OK(getFromSocket("/eval hl.config({ misc = { float_force_onscreen = 2 }})"));
    OK(getFromSocket("/dispatch hl.dsp.window.move({ x = -10, y = 0, relative = false })"));
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "at: 2,2");

    OK(getFromSocket("/dispatch hl.dsp.window.kill()"));

    // Test: spawn new floating windows offscreen
    // NOTE: These new-window tests all run with float_force_onscreen = 2.
    // That's intended, and it shouldn't limit where new windows can spawn.
    NLog::log("{}Testing force-onscreen for new floating windows", Colors::GREEN);

    // Helper macro, because spawnFoot() doesn't support executing with rules
#define WAIT_FOR_WINDOW(N)                                                                                                                                                         \
    do {                                                                                                                                                                           \
        std::this_thread::sleep_for(std::chrono::milliseconds(10));                                                                                                                \
        int counter = 0;                                                                                                                                                           \
        while (Tests::windowCount() == N) {                                                                                                                                        \
            counter++;                                                                                                                                                             \
            std::this_thread::sleep_for(std::chrono::milliseconds(100));                                                                                                           \
            if (counter > 50)                                                                                                                                                      \
                break;                                                                                                                                                             \
        }                                                                                                                                                                          \
    } while (0)

    // No constraints
    OK(getFromSocket("/eval hl.config({ misc = { new_float_force_onscreen = 0 }})"));
    OK(getFromSocket("/dispatch hl.dsp.exec_cmd('foot', { float = true, size = {100, 100}, move = {-110, 0} })"));
    WAIT_FOR_WINDOW(0);
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "at: -110,0");
    OK(getFromSocket("/dispatch hl.dsp.window.kill()"));

    // Partially onscreen
    OK(getFromSocket("/eval hl.config({ misc = { new_float_force_onscreen = 1 }})"));
    OK(getFromSocket("/dispatch hl.dsp.exec_cmd('foot', { float = true, size = {100, 100}, move = {-110, 0} })"));
    WAIT_FOR_WINDOW(0);
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "at: -50,0");
    OK(getFromSocket("/dispatch hl.dsp.window.kill()"));

    // Fully onscreen
    OK(getFromSocket("/eval hl.config({ misc = { new_float_force_onscreen = 2 }})"));
    OK(getFromSocket("/dispatch hl.dsp.exec_cmd('foot', { float = true, size = {100, 100}, move = {-10, 0} })"));
    WAIT_FOR_WINDOW(0);
    // NOTE: As we spawn with rules, apparently border_size isn't known yet, so
    // we get placed at (0,0) rather than (2,2)
    ASSERT_CONTAINS(getFromSocket("/activewindow"), "at: 0,0");
    OK(getFromSocket("/dispatch hl.dsp.window.kill()"));

#undef WAIT_FOR_WINDOW
}

TEST_CASE(specialWorkspacePinnedWindowUnmapFallback) {
    // Test: check if focus falls back to the active special workspace when a pinned window is unmapped
    NLog::log("{}Testing special workspace focus fallback on unmap for pinned windows", Colors::GREEN);

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);

    // Open a window in a workspace
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1'})"));
    SPAWN_FOOT("foot_normal");

    // Open another window and convert it to a pinned window
    SPAWN_FOOT("foot_pinned");
    OK(getFromSocket("/dispatch hl.dsp.window.float({ action = 'set', window = 'class:foot_pinned' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.pin({ action = 'set', window = 'class:foot_pinned' })"));

    // Switch to special workspace
    OK(getFromSocket("/dispatch hl.dsp.workspace.toggle_special('fallback')"));

    // Open foot in special workspace
    SPAWN_FOOT("foot_sp_normal");

    Tests::waitUntilWindowsN(3);

    // Kill the pinned window
    OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:foot_pinned' })"));
    OK(getFromSocket("/dispatch hl.dsp.window.kill({ window = 'activewindow' })"));
    Tests::waitUntilWindowsN(2);

    // Check if special workspace is still active
    const auto active = getFromSocket("/activewindow");
    EXPECT_CONTAINS(active, "(special:fallback)");

    OK(getFromSocket("/dispatch hl.dsp.workspace.toggle_special('fallback')"));
    Tests::killAllWindows();
}
