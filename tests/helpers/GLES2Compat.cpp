#include <helpers/GLES2Compat.hpp>

#include <gtest/gtest.h>

#include <drm_fourcc.h>
#include <hyprgraphics/egl/Egl.hpp>

using namespace Hyprgraphics::Egl;
using namespace NGLES2Compat;

// GLES2 has no colour-renderable 10-bit texture format: a monitor asked for bitdepth 10 has to stay at 8 bit
// (a framebuffer in XRGB2101010 was incomplete and crashed the compositor on an output whose planes took it).
TEST(Helpers, gles2FormatFor10BitIsUnusable) {
    const auto* XRGB = getPixelFormatFromDRM(DRM_FORMAT_XRGB2101010);
    ASSERT_NE(XRGB, nullptr);
    EXPECT_FALSE(glFormatFor(XRGB).usable);

    for (const auto FMT : {DRM_FORMAT_XBGR2101010, DRM_FORMAT_ARGB2101010, DRM_FORMAT_ABGR2101010}) {
        const auto* PFORMAT = getPixelFormatFromDRM(FMT);
        if (!PFORMAT)
            continue;
        EXPECT_FALSE(glFormatFor(PFORMAT).usable) << std::format("drm format 0x{:x}", FMT);
    }
}

TEST(Helpers, gles2FormatFor8BitIsUsable) {
    const auto* XRGB = getPixelFormatFromDRM(DRM_FORMAT_XRGB8888);
    ASSERT_NE(XRGB, nullptr);
    const auto GLFMT = glFormatFor(XRGB);
    EXPECT_TRUE(GLFMT.usable);
    // BGRA-ordered 8888 is uploaded as GL_BGRA_EXT, GLES2 has no sampling swizzle
    EXPECT_EQ(GLFMT.format, GL_BGRA_EXT);
    EXPECT_EQ(GLFMT.internalFormat, GLFMT.format);

    const auto* ABGR = getPixelFormatFromDRM(DRM_FORMAT_ABGR8888);
    ASSERT_NE(ABGR, nullptr);
    EXPECT_TRUE(glFormatFor(ABGR).usable);
    EXPECT_EQ(glFormatFor(ABGR).format, GL_RGBA);
}
