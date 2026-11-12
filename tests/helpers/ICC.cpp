#include <helpers/ICC.hpp>
#include <helpers/memory/Memory.hpp>

#include <gtest/gtest.h>
#include <lcms2.h>

#include <cstdint>
#include <filesystem>
#include <format>
#include <vector>

// profiles made with lcms2, with a VCGT tag written raw as display calibration tools write it
class CICCTest : public testing::Test {
  protected:
    void SetUp() override {
        m_dir = std::filesystem::temp_directory_path() / std::format("hypoland-icc-{}", testing::UnitTest::GetInstance()->current_test_info()->name());
        std::filesystem::create_directories(m_dir);
    }

    void TearDown() override {
        std::filesystem::remove_all(m_dir);
    }

    // an sRGB profile, with a VCGT tag of the given raw bytes when they are not empty
    std::filesystem::path rgbProfile(const std::vector<uint8_t>& vcgt) {
        cmsHPROFILE profile = cmsCreate_sRGBProfile();
        if (!vcgt.empty())
            cmsWriteRawTag(profile, VCGT, vcgt.data(), vcgt.size());

        const auto PATH = m_dir / "profile.icc";
        cmsSaveProfileToFile(profile, PATH.c_str());
        cmsCloseProfile(profile);
        return PATH;
    }

    // a VCGT table tag: three channels of 16 bit entries, value(channel, entry), the table at the offset after the
    // tag's 18 byte header (some tools leave two bytes more)
    static std::vector<uint8_t> vcgtTable(uint16_t entries, uint16_t (*value)(int, uint16_t), size_t tableOffset = 18, uint32_t gammaType = 0) {
        std::vector<uint8_t> raw(tableOffset + (3uz * entries * 2), 0);
        const auto           put16 = [&](size_t at, uint16_t v) {
            raw[at]     = v >> 8;
            raw[at + 1] = v & 0xFF;
        };

        raw[0] = 'v';
        raw[1] = 'c';
        raw[2] = 'g';
        raw[3] = 't';
        put16(8, gammaType >> 16);
        put16(10, gammaType & 0xFFFF);
        put16(12, 3);       // channels
        put16(14, entries); // entries
        put16(16, 2);       // entry size

        for (int c = 0; c < 3; ++c) {
            for (uint16_t i = 0; i < entries; ++i) {
                put16(tableOffset + ((c * entries + i) * 2uz), value(c, i));
            }
        }

        return raw;
    }

    static uint16_t ramp(int channel, uint16_t i) {
        // a full ramp in red and green, blue capped at 51000 as a warm calibration would
        return channel == 2 ? i * 200 : i * 257;
    }

    static constexpr cmsTagSignature VCGT = sc<cmsTagSignature>(0x76636774); // 'vcgt'

    std::filesystem::path            m_dir;
};

TEST_F(CICCTest, profileWithoutVCGT) {
    const auto RESULT = NICC::loadVCGT(rgbProfile({}), true);
    ASSERT_TRUE(RESULT.has_value());
    EXPECT_FALSE(RESULT->has_value());
}

TEST_F(CICCTest, vcgtTable) {
    const auto RESULT = NICC::loadVCGT(rgbProfile(vcgtTable(256, ramp)), true);
    ASSERT_TRUE(RESULT.has_value()) << RESULT.error();
    ASSERT_TRUE(RESULT->has_value());

    const auto& TABLE = **RESULT;
    EXPECT_EQ(TABLE.channels, 3);
    EXPECT_EQ(TABLE.entries, 256);
    for (int c = 0; c < 3; ++c) {
        ASSERT_EQ(TABLE.ch[c].size(), 256);
        for (uint16_t i = 0; i < 256; ++i) {
            EXPECT_EQ(TABLE.ch[c][i], ramp(c, i)) << "channel " << c << " entry " << i;
        }
    }
}

TEST_F(CICCTest, vcgtTableTwoBytesFurther) {
    const auto RESULT = NICC::loadVCGT(rgbProfile(vcgtTable(256, ramp, 20)), true);
    ASSERT_TRUE(RESULT.has_value()) << RESULT.error();
    ASSERT_TRUE(RESULT->has_value());
    EXPECT_EQ((**RESULT).ch[0].back(), 65535);
    EXPECT_EQ((**RESULT).ch[2].back(), 51000);
}

TEST_F(CICCTest, vcgtNotRead) {
    // render:icc_vcgt_enabled = false
    const auto RESULT = NICC::loadVCGT(rgbProfile(vcgtTable(256, ramp)), false);
    ASSERT_TRUE(RESULT.has_value());
    EXPECT_FALSE(RESULT->has_value());
}

TEST_F(CICCTest, vcgtFormulaRefused) {
    EXPECT_FALSE(NICC::loadVCGT(rgbProfile(vcgtTable(256, ramp, 18, 1)), true).has_value());
}

TEST_F(CICCTest, vcgtEndingLowRefused) {
    // the last value of a gamma ramp cannot be this dark
    EXPECT_FALSE(NICC::loadVCGT(rgbProfile(vcgtTable(256, [](int, uint16_t i) -> uint16_t { return i; })), true).has_value());
}

TEST_F(CICCTest, grayProfileRefused) {
    cmsToneCurve* curve   = cmsBuildGamma(nullptr, 2.2);
    cmsHPROFILE   profile = cmsCreateGrayProfile(cmsD50_xyY(), curve);
    const auto    PATH    = m_dir / "gray.icc";
    cmsSaveProfileToFile(profile, PATH.c_str());
    cmsCloseProfile(profile);
    cmsFreeToneCurve(curve);

    EXPECT_FALSE(NICC::loadVCGT(PATH, true).has_value());
}

TEST_F(CICCTest, missingFileRefused) {
    EXPECT_FALSE(NICC::loadVCGT(m_dir / "missing.icc", true).has_value());
}
