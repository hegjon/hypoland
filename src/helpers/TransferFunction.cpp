#include "TransferFunction.hpp"
#include "../config/ConfigValue.hpp"
#include "../event/EventBus.hpp"
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

eTF NTransferFunction::fromConfig() {
    static auto PSDREOTF = CConfigValue<Config::STRING>("render:cm_sdr_eotf");
    static auto sdrEOTF  = NTransferFunction::fromString(*PSDREOTF);
    static auto P        = Event::bus()->m_events.config.reloaded.listen([]() { sdrEOTF = NTransferFunction::fromString(*PSDREOTF); });

    return sdrEOTF;
}

int NTransferFunction::shaderTF() {
    // CM_TRANSFER_FUNCTION_GAMMA22 and CM_TRANSFER_FUNCTION_SRGB in src/render/shaders/glsl/constants.h
    constexpr int SHADER_GAMMA22 = 2;
    constexpr int SHADER_SRGB    = 9;

    switch (fromConfig()) {
        case TF_AUTO:
        case TF_GAMMA22:
        case TF_FORCED_GAMMA22: return SHADER_GAMMA22;
        default: return SHADER_SRGB;
    }
}
