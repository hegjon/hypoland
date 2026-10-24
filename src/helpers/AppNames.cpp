// Ported from omarchy-hyprland-titlebars, a fork of hyprbars: see LICENSE.titlebars.

#include "AppNames.hpp"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <unordered_set>

namespace fs = std::filesystem;

static std::vector<fs::path> xdgApplicationDirs() {
    std::vector<fs::path> dirs;

    const char*           dataHome = std::getenv("XDG_DATA_HOME");
    const char*           home     = std::getenv("HOME");
    if (dataHome && *dataHome)
        dirs.emplace_back(fs::path(dataHome) / "applications");
    else if (home && *home)
        dirs.emplace_back(fs::path(home) / ".local/share/applications");

    const char*       dataDirs = std::getenv("XDG_DATA_DIRS");
    const std::string list     = dataDirs && *dataDirs ? dataDirs : "/usr/local/share:/usr/share";
    size_t            start    = 0;
    while (start <= list.size()) {
        size_t end = list.find(':', start);
        if (end == std::string::npos)
            end = list.size();
        if (end > start)
            dirs.emplace_back(fs::path(list.substr(start, end - start)) / "applications");
        start = end + 1;
    }

    return dirs;
}

// A directory's time moves when an entry is added, removed or renamed in it
static std::vector<fs::file_time_type> stamps(const std::vector<fs::path>& dirs) {
    std::vector<fs::file_time_type> result;
    for (const auto& dir : dirs) {
        std::error_code ec;
        const auto      time = fs::last_write_time(dir, ec);
        result.push_back(ec ? fs::file_time_type::min() : time);
    }
    return result;
}

static std::string lower(std::string text) {
    std::ranges::transform(text, text.begin(), [](unsigned char c) { return std::tolower(c); });
    return text;
}

CAppNames::CAppNames(std::vector<fs::path> dirs) : m_dirs(dirs.empty() ? xdgApplicationDirs() : std::move(dirs)) {
    ;
}

void CAppNames::load() {
    m_entries.clear();
    m_resolved.clear();

    // earlier directories win, so a user's own entry overrides the system one
    std::unordered_set<std::string> seen;
    for (const auto& dir : m_dirs) {
        std::error_code ec;
        for (const auto& file : fs::directory_iterator(dir, ec)) {
            if (file.path().extension() != ".desktop" || !seen.insert(file.path().filename().string()).second)
                continue;

            SEntry        entry{.id = file.path().stem().string()};
            std::ifstream stream(file.path());
            std::string   line;
            bool          inEntry = false;
            while (std::getline(stream, line)) {
                if (line.starts_with('[')) {
                    inEntry = line == "[Desktop Entry]";
                    continue;
                }
                if (!inEntry)
                    continue;
                if (line.starts_with("Name="))
                    entry.name = line.substr(5);
                else if (line.starts_with("StartupWMClass="))
                    entry.wmClass = line.substr(15);
            }

            if (!entry.name.empty())
                m_entries.push_back(std::move(entry));
        }
    }
}

void CAppNames::refresh() {
    const auto NOW = std::chrono::steady_clock::now();
    if (m_loaded && NOW - m_lastCheck < std::chrono::seconds(2))
        return;

    m_lastCheck = NOW;
    auto times  = stamps(m_dirs);
    if (m_loaded && times == m_stamps)
        return;

    load();
    m_stamps = std::move(times);
    m_loaded = true;
}

std::string CAppNames::nameFor(const std::string& windowClass) {
    if (windowClass.empty())
        return "";

    refresh();

    if (const auto CACHED = m_resolved.find(windowClass); CACHED != m_resolved.end())
        return CACHED->second;

    std::string name;
    if (const auto IT = std::ranges::find_if(m_entries, [&](const auto& e) { return e.wmClass == windowClass; }); IT != m_entries.end())
        name = IT->name;
    else {
        const auto WANTED = lower(windowClass);
        if (const auto IT2 = std::ranges::find_if(m_entries, [&](const auto& e) { return lower(e.id) == WANTED; }); IT2 != m_entries.end())
            name = IT2->name;
    }

    m_resolved[windowClass] = name;
    return name;
}

UP<CAppNames>& AppNames::names() {
    static UP<CAppNames> p = makeUnique<CAppNames>();
    return p;
}
