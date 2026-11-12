#include "TransferFunction.hpp"
#include <string>
#include <unordered_map>
#include <hyprlang.hpp>

using namespace NTransferFunction;

static std::unordered_map<std::string, eTF> const table = {{"default", TF_DEFAULT}, {"0", TF_DEFAULT},       {"auto", TF_AUTO}, {"srgb", TF_SRGB},
                                                           {"3", TF_SRGB},          {"gamma22", TF_GAMMA22}, {"1", TF_GAMMA22}, {"gamma22force", TF_FORCED_GAMMA22},
                                                           {"2", TF_FORCED_GAMMA22}};

eTF                                               NTransferFunction::fromString(const std::string tfName) {
    auto it = table.find(tfName);
    if (it == table.end())
        return TF_DEFAULT;
    return it->second;
}

std::string NTransferFunction::toString(eTF tf) {
    for (const auto& [key, value] : table) {
        if (value == tf)
            return key;
    }
    return "";
}
