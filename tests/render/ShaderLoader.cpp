#include <render/ShaderLoader.hpp>

#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>

using namespace Render;

static const std::array<std::string, SH_FRAG_LAST> FRAGS = {
    "quad.frag",         "passthru.frag",   "rgbamatte.frag", "ext.frag",    "blur1.frag",  "blur2.frag",       "blurprepare.frag", "blurfinish.frag",
    "shadow.frag",       "inner_glow.frag", "surface.frag",   "border.frag", "glitch.frag", "frostfinish.frag", "dropsfinish.frag", "heatshimmerfinish.frag",
    "aurorafinish.frag", "hazefinish.frag", "alphamax.frag",
};

class CShaderLoaderTest : public testing::Test {
  protected:
    void SetUp() override {
        m_dir = std::filesystem::temp_directory_path() / std::format("hypoland-shaderloader-{}", testing::UnitTest::GetInstance()->current_test_info()->name());
        std::filesystem::create_directories(m_dir);
    }

    void TearDown() override {
        std::filesystem::remove_all(m_dir);
    }

    void write(const std::string& name, const std::string& content) {
        std::ofstream(m_dir / name) << content;
    }

    std::filesystem::path m_dir;
};

TEST_F(CShaderLoaderTest, ExpandsNestedIncludes) {
    write("defines.h", "#define USE_TINT 0\n");
    write("outer.glsl", "#ifndef ALLOW_INCLUDES\n#extension GL_ARB_shading_language_include : enable\n#endif\n#include \"inner.glsl\"\nfloat outer;\n");
    write("inner.glsl", "float inner;\n");
    write("quad.frag",
          "#version 100\n#define ALLOW_INCLUDES\n#extension GL_ARB_shading_language_include : enable\n#include \"defines.h\"\n  #include \"outer.glsl\"\nvoid main() {}\n");

    CShaderLoader loader({"defines.h", "outer.glsl", "inner.glsl"}, FRAGS, m_dir.string());

    EXPECT_EQ(loader.process("quad.frag"),
              "#version 100\n#define ALLOW_INCLUDES\n#define USE_TINT 0\n#ifndef ALLOW_INCLUDES\n#endif\nfloat inner;\nfloat outer;\nvoid main() {}\n");
}

TEST_F(CShaderLoaderTest, VariantReplacesDefines) {
    write("defines.h", "#define USE_TINT 0\n");
    write("quad.frag", "#version 100\n#include \"defines.h\"\n#if USE_TINT\nfloat tint;\n#endif\n");

    CShaderLoader loader({"defines.h"}, FRAGS, m_dir.string());
    const auto    source = loader.getVariantSource(SH_FRAG_QUAD, {.features = SH_FEAT_TINT});

    EXPECT_NE(source.find("#define USE_TINT 1\n"), std::string::npos);
    EXPECT_EQ(source.find("#define USE_TINT 0\n"), std::string::npos);
    EXPECT_NE(source.find("#if USE_TINT\nfloat tint;\n#endif\n"), std::string::npos);
}

TEST_F(CShaderLoaderTest, DropsMissingAndRecursiveIncludes) {
    write("self.glsl", "float self;\n#include \"self.glsl\"\n");
    write("quad.frag", "#version 100\n#include \"missing.glsl\"\n#include \"self.glsl\"\n");

    CShaderLoader loader({"self.glsl"}, FRAGS, m_dir.string());
    const auto    source = loader.process("quad.frag");

    EXPECT_EQ(source.find("#include"), std::string::npos);
    EXPECT_TRUE(source.starts_with("#version 100\nfloat self;\n"));
}
