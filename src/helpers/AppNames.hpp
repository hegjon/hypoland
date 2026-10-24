#pragma once

#include <chrono>
#include <filesystem>
#include <string>
#include <unordered_map>
#include <vector>

#include "memory/Memory.hpp"

// The Name of the desktop entry that claims a window class, through its StartupWMClass or else its file name.
// Titlebars show it instead of the window title, which for a web app is often just its domain or the page it is on.
class CAppNames {
  public:
    // Directories with .desktop files, earlier ones win. Without any, $XDG_DATA_HOME/applications and then
    // $XDG_DATA_DIRS/applications are used.
    CAppNames(std::vector<std::filesystem::path> dirs = {});

    // Empty when no entry claims the class. The directories are looked at again at most every 2 s, so an entry
    // added while the compositor runs counts for the next window class asked for.
    std::string nameFor(const std::string& windowClass);

  private:
    struct SEntry {
        std::string id, name, wmClass;
    };

    void                                         refresh();
    void                                         load();

    std::vector<std::filesystem::path>           m_dirs;
    std::vector<SEntry>                          m_entries;
    std::unordered_map<std::string, std::string> m_resolved;
    std::vector<std::filesystem::file_time_type> m_stamps;
    std::chrono::steady_clock::time_point        m_lastCheck;
    bool                                         m_loaded = false;
};

namespace AppNames {
    UP<CAppNames>& names();
}
