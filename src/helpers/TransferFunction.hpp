#pragma once

#include <cstdint>
#include <string>

namespace NTransferFunction {
    enum eTF : uint8_t {
        TF_DEFAULT        = 0,
        TF_AUTO           = 1,
        TF_SRGB           = 2,
        TF_GAMMA22        = 3,
        TF_FORCED_GAMMA22 = 4,
    };

    eTF         fromString(const std::string tfName);
    std::string toString(eTF tf);

    // render:cm_sdr_eotf
    eTF fromConfig();

    // the transfer function the aurora and haze blur variants decode and encode the work buffer with, a
    // CM_TRANSFER_FUNCTION_* of the shaders' constants.h: gamma 2.2 for auto and gamma22, sRGB otherwise
    int shaderTF();
}
