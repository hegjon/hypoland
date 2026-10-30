#include "ShaderLoader.hpp"
#include <format>
#include <hyprutils/memory/Casts.hpp>
#include <hyprutils/memory/UniquePtr.hpp>
#include <hyprutils/string/String.hpp>
#include <hyprutils/path/Path.hpp>
#include "../debug/log/Logger.hpp"
#include "shaders/Shaders.hpp"
#include "../helpers/fs/FsUtils.hpp"
#include "Renderer.hpp"
#include <string>
#include <filesystem>
#include <sstream>

using namespace Render;

CShaderLoader::CShaderLoader(const std::vector<std::string> includes, const std::array<std::string, SH_FRAG_LAST>& frags, const std::string shaderPath) : m_shaderPath(shaderPath) {
    for (const auto& inc : includes) {
        include(inc);
    }

    std::ranges::transform(frags, m_fragFiles.begin(), [&](const auto& filename) { return loadShader(filename); });
}

void CShaderLoader::include(const std::string& filename) {
    m_includes.insert({filename, loadShader(filename)});
}

std::string CShaderLoader::getDefines(const SShaderVariant& variant) {
    static constexpr auto defines = std::to_array<std::pair<std::string_view, ePreparedFragmentShaderFeature>>({
        {"USE_RGBA", SH_FEAT_RGBA},
        {"USE_DISCARD", SH_FEAT_DISCARD},
        {"USE_TINT", SH_FEAT_TINT},
        {"USE_ROUNDING", SH_FEAT_ROUNDING},
        {"USE_BLUR", SH_FEAT_BLUR},
        {"USE_BLUR_ALPHA_MASK", SH_FEAT_BLUR_ALPHA_MASK},
        {"USE_BLUR_MATTE", SH_FEAT_BLUR_MATTE},
        {"USE_BLUR_PROPORTIONAL", SH_FEAT_BLUR_PROPORTIONAL},
    });

    std::string           res;
    res.reserve(351);
    for (const auto& [name, flag] : defines) {
        std::format_to(std::back_inserter(res), "#define {} {}\n", name, (variant.features & flag) != 0 ? '1' : '0');
    }
    return res;
}

// Only #include is resolved here, the driver's preprocessor handles #define and #if itself.
std::string CShaderLoader::processSource(const std::string& source, size_t depth) {
    std::istringstream stream(source);
    std::string        code;
    std::string        line;

    code.reserve(source.length());

    while (std::getline(stream, line)) {
        const auto directive = Hyprutils::String::trim(line);

        // GLES has no include extension, the includes are resolved here instead
        if (directive.starts_with("#extension GL_ARB_shading_language_include"))
            continue;

        if (!directive.starts_with("#include")) {
            code += line;
            code += '\n';
            continue;
        }

        const auto nameStart = directive.find('"');
        const auto nameEnd   = nameStart == std::string::npos ? std::string::npos : directive.find('"', nameStart + 1);
        if (nameEnd == std::string::npos) {
            Log::logger->log(Log::ERR, "Shader: malformed include: {}", directive);
            continue;
        }

        const auto name = directive.substr(nameStart + 1, nameEnd - nameStart - 1);

        if (depth >= MAX_INCLUDE_DEPTH) {
            Log::logger->log(Log::ERR, "Shader: includes nested too deep at {}", name);
            continue;
        }

        if (m_overrideDefines.length() && name == "defines.h")
            code += processSource(m_overrideDefines, depth + 1);
        else if (m_includes.contains(name))
            code += processSource(m_includes.at(name), depth + 1);
        else
            Log::logger->log(Log::ERR, "Shader: include {} not found", name);
    }

    return code;
}

std::string CShaderLoader::process(const std::string& filename) {
    auto source = loadShader(filename);
    return processSource(source);
}

std::string CShaderLoader::process(const std::string& filename, const std::map<std::string, std::string>& defines) {
    m_overrideDefines = "";
    for (const auto& [name, value] : defines) {
        m_overrideDefines += std::format("#define {} {}\n", name, value);
    }
    const auto& res   = process(filename);
    m_overrideDefines = "";
    return res;
}

std::string CShaderLoader::getVariantSource(ePreparedFragmentShader frag, SShaderVariant variant) {
    if (!m_fragVariants[frag].contains(variant)) {
        ASSERT(m_fragFiles[frag].length());
        m_overrideDefines             = getDefines(variant);
        m_fragVariants[frag][variant] = processSource(m_fragFiles[frag]);
        m_overrideDefines             = "";
    }

    return m_fragVariants[frag][variant];
}

const std::map<std::string, std::string>& CShaderLoader::includes() {
    return m_includes;
}

// TODO notify user if bundled shader is newer than ~/.config override
std::string CShaderLoader::loadShader(const std::string& filename) {
    if (m_shaderPath.length()) {
        std::filesystem::path path = m_shaderPath;
        const auto            src  = NFsUtils::readFileAsString(path / filename);
        if (src.has_value())
            return src.value();
    }
    const auto home = Hyprutils::Path::getHome();
    if (home.has_value()) {
        const auto src = NFsUtils::readFileAsString(std::format("{}/hypr/shaders/{}", home.value(), filename));
        if (src.has_value())
            return src.value();
    }
    for (auto& e : ASSET_PATHS) {
        const auto src = NFsUtils::readFileAsString(std::format("{}/hypr/shaders/{}", e, filename));
        if (src.has_value())
            return src.value();
    }

    const auto shader = std::ranges::lower_bound(SHADERS, filename, {}, [](const auto& filenameSource) { return filenameSource.first; });
    if (shader != SHADERS.end() && shader->first == filename)
        return std::string{shader->second};
    throw std::runtime_error(std::format("Couldn't load shader {}", filename));
}
