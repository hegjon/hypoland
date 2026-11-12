#include "ICC.hpp"
#include "../debug/log/Logger.hpp"
#include "memory/Memory.hpp"

#include <hyprutils/utils/ScopeGuard.hpp>
using namespace Hyprutils::Utils;

#include <lcms2.h>

static uint16_t bigEndianU16(const uint8_t* p) {
    return sc<uint16_t>(sc<uint16_t>(p[0]) << 8 | sc<uint16_t>(p[1]));
}

static uint32_t bigEndianU32(const uint8_t* p) {
    return sc<uint32_t>(p[0]) << 24 | sc<uint32_t>(p[1]) << 16 | sc<uint32_t>(p[2]) << 8 | sc<uint32_t>(p[3]);
}

static constexpr cmsTagSignature makeSig(char a, char b, char c, char d) {
    return sc<cmsTagSignature>(sc<uint32_t>(a) << 24 | sc<uint32_t>(b) << 16 | sc<uint32_t>(c) << 8 | sc<uint32_t>(d));
}

static constexpr cmsTagSignature VCGT_SIG = makeSig('v', 'c', 'g', 't');

//

static std::expected<std::optional<NICC::SVCGTTable16>, std::string> readVCGT16(cmsHPROFILE prof) {
    if (!cmsIsTag(prof, VCGT_SIG))
        return std::nullopt;

    cmsUInt32Number n = cmsReadRawTag(prof, VCGT_SIG, nullptr, 0);
    if (n < 8 + 4 + 2 + 2 + 2 + 2) // header + type + table header
        return std::unexpected("Malformed vcgt tag");

    std::vector<uint8_t> raw(n);
    if (cmsReadRawTag(prof, VCGT_SIG, raw.data(), n) != n)
        return std::unexpected("Malformed vcgt tag");

    // raw layout:
    // 0 ... 3: 'vcgt'
    // 4 ... 7: reserved
    // 8 ... 11: gammaType (0 = table)
    uint32_t gammaType = bigEndianU32(raw.data() + 8);
    if (gammaType != 0)
        return std::unexpected("VCGT formula type is not supported by Hypoland");

    NICC::SVCGTTable16 table;
    table.channels  = bigEndianU16(raw.data() + 12);
    table.entries   = bigEndianU16(raw.data() + 14);
    table.entrySize = bigEndianU16(raw.data() + 16);
    // raw+18: reserved u16

    Log::logger->log(Log::DEBUG, "readVCGT16: table has {} channels, {} entries, and entry size of {}", table.channels, table.entries, table.entrySize);

    if (table.channels != 3 || table.entrySize != 2 || table.entries == 0)
        return std::unexpected("invalid vcgt table size");

    size_t tableBytes = sc<size_t>(table.channels) * sc<size_t>(table.entries) * sc<size_t>(table.entrySize);

    // VCGT is a piece of shit and some absolute fucking mongoloid idiots
    // decided it'd be great to have both 18 and 20
    // FUCK YOU
    size_t tableOff = 20;

    auto   readTable = [&] -> void {
        for (int c = 0; c < 3; ++c) {
            table.ch[c].resize(table.entries);
            for (uint16_t i = 0; i < table.entries; ++i) {
                const uint8_t* p = raw.data() + tableOff + sc<ptrdiff_t>((c * table.entries + i) * 2);
                table.ch[c][i]   = bigEndianU16(p); // 0 ... 65535
            }
        }
    };

    if (raw.size() < tableOff + tableBytes) {
        tableOff = 18;

        if (raw.size() < tableOff + tableBytes) {
            Log::logger->log(Log::ERR, "readVCGT16: table is too short, tag is invalid");
            return std::unexpected("table is too short");
        }

        Log::logger->log(Log::DEBUG, "readVCGT16: table is too short, but off = 18 fits. Attempting offset = 18");

        readTable();
    } else {
        readTable();

        // if the table's last entry is suspiciously low, we more than likely read an 18 as a 20.
        if (table.ch[0][table.entries - 1] < 30000) {
            Log::logger->log(Log::DEBUG, "readVCGT16: table is likely offset 18 not 20, re-reading");

            tableOff = 18;

            readTable();
        }
    }

    if (table.ch[0][table.entries - 1] < 30000) {
        Log::logger->log(Log::ERR, "readVCGT16: table is malformed, last value of a gamma ramp can't be {}", table.ch[0][table.entries - 1]);
        return std::unexpected("invalid table values");
    }

    Log::logger->log(Log::DEBUG, "readVCGT16: red channel: [{}, {}, ... {}, {}]", table.ch[0][0], table.ch[0][1], table.ch[0][table.entries - 2], table.ch[0][table.entries - 1]);
    Log::logger->log(Log::DEBUG, "readVCGT16: green channel: [{}, {}, ... {}, {}]", table.ch[1][0], table.ch[1][1], table.ch[1][table.entries - 2], table.ch[1][table.entries - 1]);
    Log::logger->log(Log::DEBUG, "readVCGT16: blue channel: [{}, {}, ... {}, {}]", table.ch[2][0], table.ch[2][1], table.ch[2][table.entries - 2], table.ch[2][table.entries - 1]);

    return table;
}

std::expected<std::optional<NICC::SVCGTTable16>, std::string> NICC::loadVCGT(const std::filesystem::path& file, bool readVCGT) {
    std::error_code ec;
    if (!std::filesystem::exists(file, ec) || ec)
        return std::unexpected("Invalid file");

    cmsHPROFILE prof = cmsOpenProfileFromFile(file.string().c_str(), "r");
    if (!prof)
        return std::unexpected("CMS failed to open icc file");

    CScopeGuard x([&prof] { cmsCloseProfile(prof); });

    // only handle RGB (typical display profiles)
    if (cmsGetColorSpace(prof) != cmsSigRgbData)
        return std::unexpected("Only RGB display profiles are supported");

    if (!readVCGT) {
        Log::logger->log(Log::DEBUG, "Skipping VCGT load, disabled by config");
        return std::nullopt;
    }

    auto vcgt = readVCGT16(prof);
    if (vcgt && !*vcgt)
        Log::logger->log(Log::DEBUG, "ICC profile has no VCGT data");

    return vcgt;
}
