#include "../../Log.hpp"
#include "../shared.hpp"
#include "tests.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include <format>
#include <hyprutils/os/Process.hpp>
#include <hyprutils/memory/WeakPtr.hpp>

using namespace Hyprutils::OS;
using namespace Hyprutils::Memory;

static bool spawnLayer(const std::string& namespace_, const Tests::SLayerOptions& options = {}) {
    NLog::log("{}Spawning layer {}", Colors::YELLOW, namespace_);
    if (!Tests::spawnLayer(namespace_, options)) {
        NLog::log("{}Error: {} layer did not spawn", Colors::RED, namespace_);
        return false;
    }
    return true;
}

static std::string getLayerLine(const std::string& layers, const std::string& target) {

    auto pos = layers.find(std::format("namespace: {}", target));
    if (pos == std::string::npos)
        return "";

    auto start = layers.rfind('\n', pos);
    start      = (start == std::string::npos) ? 0 : start + 1;

    auto end = layers.find('\n', pos);

    return layers.substr(start, end - start);
}

TEST_CASE(layerVisibilityOnFs) {

    // For default handled fullscreen

    static constexpr const char* LAYER_NAMESPACE = "bar-like-layer";

    ASSERT(spawnLayer(LAYER_NAMESPACE, {.edge = "top", .layer = "top", .size = 48, .keyboardFocus = false}), true);

    SPAWN_FOOT("cat");

    {
        auto str = getLayerLine(getFromSocket("/layers"), LAYER_NAMESPACE);
        EXPECT_CONTAINS(str, "a: 1")
        EXPECT_CONTAINS(getFromSocket("/activewindow"), "fullscreen: 0");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'maximized', action = 'set', window = 'class:cat' })"));

    {

        auto str = getLayerLine(getFromSocket("/layers"), LAYER_NAMESPACE);
        EXPECT_CONTAINS(str, "a: 1")
        EXPECT_CONTAINS(getFromSocket("/activewindow"), "fullscreen: 1");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'maximized', action = 'unset', window = 'class:cat' })"));

    {
        auto str = getLayerLine(getFromSocket("/layers"), LAYER_NAMESPACE);
        EXPECT_CONTAINS(str, "a: 1")
        EXPECT_CONTAINS(getFromSocket("/activewindow"), "fullscreen: 0");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'set', window = 'class:cat' })"));

    {
        auto str = getLayerLine(getFromSocket("/layers"), LAYER_NAMESPACE);
        EXPECT_CONTAINS(str, "a: 0")
        EXPECT_CONTAINS(getFromSocket("/activewindow"), "fullscreen: 2");
    }

    OK(getFromSocket("/dispatch hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'unset', window = 'class:cat' })"));

    {
        auto str = getLayerLine(getFromSocket("/layers"), LAYER_NAMESPACE);
        EXPECT_CONTAINS(str, "a: 1")
        EXPECT_CONTAINS(getFromSocket("/activewindow"), "fullscreen: 0");
    }
}
