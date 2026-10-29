#include "Env.hpp"

#include <cstdlib>

bool Env::envEnabled(const char* env) {
    const auto ret = getenv(env);
    return ret && ret[0] != '\0' && !(ret[0] == '0' && ret[1] == '\0');
}

bool Env::isTrace() {
    static bool TRACE = envEnabled("HYPRLAND_TRACE");
    return TRACE;
}

std::optional<std::string> Env::get(const char* env) {
    const char* V = std::getenv(env);
    if (!V)
        return std::nullopt;
    return std::string{V};
}
