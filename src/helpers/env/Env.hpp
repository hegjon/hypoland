#pragma once

#include <optional>
#include <string>

namespace Env {
    bool                       envEnabled(const char* env);
    std::optional<std::string> get(const char* env); // the variable's value, nothing when it is not set
    bool                       isTrace();
}
