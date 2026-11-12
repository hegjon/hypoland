#include "../shared.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include "tests.hpp"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <format>
#include <thread>

#include <hyprutils/utils/ScopeGuard.hpp>

using namespace Hyprutils::Utils;

static bool noConfigErrors() {
    const auto ERRORS = getFromSocket("/configerrors");
    return std::ranges::all_of(ERRORS, [](unsigned char c) { return std::isspace(c); });
}

static bool waitForOutput(const char* name, bool present) {
    for (int i = 0; i < 50; ++i) {
        if (getFromSocket("/monitors").contains(name) == present)
            return true;

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    return false;
}

// Screen shaders, the colour management and hyprcursor are removed (2026-11-12): their options stay registered, are
// accepted at runtime and give no config error, so Hyprland configs keep loading
TEST_CASE(removedOptionsAreAccepted) {
    CScopeGuard guard = {[&]() { OK(getFromSocket("/reload")); }};

    OK(getFromSocket("/eval hl.config({ decoration = { screen_shader = '/nonexistent/screen.frag' } })"));
    OK(getFromSocket("/eval hl.config({ cursor = { enable_hyprcursor = true } })"));
    OK(getFromSocket("/eval hl.config({ render = { cm_auto_hdr = 2, non_shader_cm = 1, non_shader_cm_interop = 1, cm_sdr_eotf = 'gamma22' } })"));
    OK(getFromSocket("/eval hl.config({ debug = { damage_tracking = 2 } })"));

    ASSERT(noConfigErrors(), true);
    // still drawing
    ASSERT_CONTAINS(getFromSocket("/version"), "Hyprland");
}

// A monitor rule's cm, sdr and luminance settings are parsed and ignored: every output is sRGB, and hyprctl keeps
// showing them in the same keys
TEST_CASE(monitorColorSettingsAreIgnored) {
    static constexpr const char* TEST_OUTPUT = "HEADLESS-CM";

    getFromSocket(std::format("/output remove {}", TEST_OUTPUT));

    CScopeGuard guard = {[&]() {
        getFromSocket(std::format("/output remove {}", TEST_OUTPUT));
        ASSERT(waitForOutput(TEST_OUTPUT, false), true);
        OK(getFromSocket("/reload"));
    }};

    OK(getFromSocket(std::format("/eval hl.monitor({{ output = '{}', mode = '1280x720@60', position = 'auto-right', scale = '1', cm = 'hdr', sdrbrightness = 1.5, "
                                 "sdrsaturation = 0.8, supports_hdr = 1, supports_wide_color = 1, max_luminance = 1000 }})",
                                 TEST_OUTPUT)));
    OK(getFromSocket(std::format("/output create headless {}", TEST_OUTPUT)));
    ASSERT(waitForOutput(TEST_OUTPUT, true), true);

    ASSERT(noConfigErrors(), true);

    const auto MONITORS = getFromSocket("j/monitors");
    ASSERT_CONTAINS(MONITORS, std::format("\"name\": \"{}\"", TEST_OUTPUT));
    // the output this rule asked HDR of is sRGB, the rule's sdr values are shown as they were
    const auto SELF = MONITORS.substr(MONITORS.find(std::format("\"name\": \"{}\"", TEST_OUTPUT)));
    EXPECT_CONTAINS(SELF, "\"colorManagementPreset\": \"srgb\"");
    EXPECT_CONTAINS(SELF, "\"sdrBrightness\": 1.5");
    EXPECT_CONTAINS(SELF, "\"sdrSaturation\": 0.8");
}

// hyprctl version's JSON keeps its keys, the hyprcursor ones empty
TEST_CASE(versionJsonKeepsHyprcursorKeys) {
    const auto VERSION = getFromSocket("j/version");
    EXPECT_CONTAINS(VERSION, "\"buildHyprcursor\": \"\"");
    EXPECT_CONTAINS(VERSION, "\"systemHyprcursor\": \"\"");
    EXPECT_CONTAINS(VERSION, "\"hypolandVersion\"");
}
