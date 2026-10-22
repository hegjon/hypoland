#pragma once

#include <hyprutils/os/Process.hpp>
#include <hyprutils/memory/WeakPtr.hpp>
#include <sys/types.h>

//NOLINTNEXTLINE
namespace Tests {
    // a layer-shell surface along one edge of the screen (clients/layer.qml)
    struct SLayerOptions {
        std::string edge          = "top"; // top, bottom, left or right
        std::string layer         = "top"; // background, bottom, top or overlay
        int         size          = 48;    // pixels across the edge
        bool        keyboardFocus = false;
    };

    [[nodiscard("Check whether foot was spawned successfully or use the SPAWN_FOOT macro")]]
    Hyprutils::Memory::CUniquePointer<Hyprutils::OS::CProcess> spawnFoot(const std::string& class_ = "", const std::vector<std::string> args = {});
    [[nodiscard("Check whether the layer was spawned successfully or use the SPAWN_LAYER macro")]]
    Hyprutils::Memory::CUniquePointer<Hyprutils::OS::CProcess> spawnLayer(const std::string& namespace_, const SLayerOptions& options = {});
    bool                                                       processAlive(pid_t pid);
    int                                                        windowCount();
    int                                                        countOccurrences(const std::string& in, const std::string& what);
    void                                                       sync(int rounds = 3);
    bool                                                       killAllWindows();
    void                                                       waitUntilWindowsN(int n);
    int                                                        layerCount();
    bool                                                       killAllLayers();
    std::string                                                execAndGet(const std::string& cmd);
    bool                                                       writeFile(const std::string& name, const std::string& contents);
    /**
     * Extracts the given attribute from Hyprland's response to requests such as `/clients`, `/workspaces`, etc.
     * Automatically appends `: ` to `attr`.
     *
     * For example, `Tests::getAttribute(getFromSocket("/activewindow"), "at")` returns the active window's coordinates, e.g., `"2,32"`
     */
    std::string getAttribute(const std::string& hyprlandResponse, std::string attr);

    /**
    * Extracts window ID from activeWindow output
    */
    std::string getWindowID(const std::string& hyprlandActiveWindowResponse);
};
