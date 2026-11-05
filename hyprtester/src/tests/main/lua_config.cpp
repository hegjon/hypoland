#include "tests.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"

#include <chrono>
#include <filesystem>
#include <thread>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <hyprutils/os/File.hpp>

using namespace Hyprutils::Utils;

TEST_CASE(luaRequire) {
    constexpr auto EXPECTED = "absolute:relative:a:b";

    EXPECT(getFromSocket("/repl return _G.hyprtester_lua_require_result"), EXPECTED);

    OK(getFromSocket("/reload"));
    EXPECT(getFromSocket("/repl return _G.hyprtester_lua_require_result"), EXPECTED);
}

TEST_CASE(luaSpecialWorkspaceDeactivationEventNil) {
    constexpr auto SPECIAL_WORKSPACE = "lua_special_active_nil";

    CScopeGuard    guard = {[&]() {
        if (getFromSocket("/monitors").contains(std::format("(special:{})", SPECIAL_WORKSPACE)))
            getFromSocket(std::format("/dispatch hl.dsp.workspace.toggle_special('{}')", SPECIAL_WORKSPACE));

        getFromSocket("/eval do _G.hyprtester_special_active_subscription = nil; _G.hyprtester_special_active_event_count = nil; "
                      "_G.hyprtester_special_active_workspace_type = nil; _G.hyprtester_special_active_monitor_type = nil end");
    }};

    OK(getFromSocket("/eval do _G.hyprtester_special_active_event_count = 0; _G.hyprtester_special_active_subscription = hl.on('workspace.special_active', function(workspace, "
                     "monitor) _G.hyprtester_special_active_event_count = _G.hyprtester_special_active_event_count + 1; _G.hyprtester_special_active_workspace_type = "
                     "type(workspace); _G.hyprtester_special_active_monitor_type = type(monitor) end) end"));

    OK(getFromSocket(std::format("/dispatch hl.dsp.workspace.toggle_special('{}')", SPECIAL_WORKSPACE)));
    ASSERT(getFromSocket("/repl _G.hyprtester_special_active_event_count"), "1");
    ASSERT(getFromSocket("/repl _G.hyprtester_special_active_workspace_type"), "userdata");
    ASSERT(getFromSocket("/repl _G.hyprtester_special_active_monitor_type"), "userdata");

    OK(getFromSocket(std::format("/dispatch hl.dsp.workspace.toggle_special('{}')", SPECIAL_WORKSPACE)));
    ASSERT(getFromSocket("/repl _G.hyprtester_special_active_event_count"), "2");
    ASSERT(getFromSocket("/repl _G.hyprtester_special_active_workspace_type"), "nil");
    ASSERT(getFromSocket("/repl _G.hyprtester_special_active_monitor_type"), "userdata");
}

TEST_CASE(luaEventConfigUnload) {
    std::error_code ec;
    std::filesystem::remove("/tmp/hyprtester-luaEventConfigUnload.txt", ec);
    OK(getFromSocket("/eval luaEventConfigUnload = 'luaEventConfigUnload'; hl.on('config.unload', function() os.execute('echo -n '..tostring(luaEventConfigUnload)..' > "
                     "/tmp/hyprtester-luaEventConfigUnload.txt') end)"));
    OK(getFromSocket("/reload"));
    EXPECT(Hyprutils::File::readFileAsString("/tmp/hyprtester-luaEventConfigUnload.txt").value_or("error"), "luaEventConfigUnload");
    std::filesystem::remove("/tmp/hyprtester-luaEventConfigUnload.txt", ec);
}

TEST_CASE(luaReloadConfig) {
    constexpr auto VAR = "normally_nonexistent_variable";

    OK(getFromSocket(std::format("/eval {} = true", VAR)));
    OK(getFromSocket("/dispatch hl.dsp.reload_config()"));
    EXPECT(getFromSocket(std::format("/repl return {}", VAR)), "nil");
}

static bool waitForRepl(std::string_view expr, std::string_view expected) {
    for (int i = 0; i < 50; ++i) {
        if (getFromSocket(std::format("/repl return {}", expr)) == expected)
            return true;

        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    return false;
}

TEST_CASE(luaWindowDestroyWeakAccess) {
    CScopeGuard guard = {[&]() {
        getFromSocket(R"(/eval do
            local state = _G.hyprtester_window_destroy
            if state and state.subscription then state.subscription:remove() end
            _G.hyprtester_window_destroy = nil
        end)");
    }};

    SPAWN_FOOT("foot_lua_destroy", {"--title", "lua_destroy_title", "-o", "locked-title=yes"});
    OK(getFromSocket(R"(/eval do
        local original = assert(hl.get_window('class:^foot_lua_destroy$'))
        assert(original.class == 'foot_lua_destroy' and original.title == 'lua_destroy_title')
        assert(type(original.address) == 'string' and original.address:match('^0x%x+$'))
        assert(type(original.stable_id) == 'string' and original.stable_id:match('^%x+$'))
        local state = { original = original, count = 0, description = tostring(original), expected = {
            address = original.address, stable_id = original.stable_id, title = original.title, class = original.class,
        } }
        _G.hyprtester_window_destroy = state
        state.subscription = hl.on('window.destroy', function(window)
            state.count = state.count + 1
            state.saved = window
            state.ok, state.error = pcall(function()
                assert(type(window) == 'userdata')
                assert(window == original)
                for field, value in pairs(state.expected) do
                    assert(window[field] == value, field)
                    assert(original[field] == value, field)
                end
                assert(tostring(window) == state.description)
                assert(not tostring(window):find('expired', 1, true))
                for _, field in ipairs({ 'fullscreen', 'fullscreen_client', 'fullscreen_handler', 'inhibiting_idle', 'layout' }) do
                    assert(window[field] == nil, field)
                end
            end)
        end)
    end)"));

    OK(getFromSocket("/dispatch hl.dsp.window.close({ window = 'class:^foot_lua_destroy$' })"));
    ASSERT(waitForRepl("_G.hyprtester_window_destroy.count > 0", "true"), true);
    OK(getFromSocket(R"(/eval do
        local state = _G.hyprtester_window_destroy
        assert(state.count == 1)
        assert(state.ok, state.error)
        assert(state.saved == state.original)
        for field in pairs(state.expected) do
            assert(state.saved[field] == nil, field)
            assert(state.original[field] == nil, field)
        end
        assert(tostring(state.saved) == 'HL.Window(expired)')
        assert(tostring(state.original) == 'HL.Window(expired)')
    end)"));
}
