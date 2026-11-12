#pragma once

#include <array>
#include <cstdint>
#include <expected>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

// A monitor's ICC profile (the monitor rule's icc) is applied through its VCGT gamma ramps in KMS. The renderer converts no
// colours, so the rest of the profile is not read.
namespace NICC {
    struct SVCGTTable16 {
        uint16_t                             channels  = 0;
        uint16_t                             entries   = 0;
        uint16_t                             entrySize = 0;
        std::array<std::vector<uint16_t>, 3> ch;
    };

    // the profile's VCGT table, nullopt when it has none or readVCGT is false (render:icc_vcgt_enabled), an error when the
    // file is no RGB display profile or its table is malformed
    std::expected<std::optional<SVCGTTable16>, std::string> loadVCGT(const std::filesystem::path& file, bool readVCGT);
}
