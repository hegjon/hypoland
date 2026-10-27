#include "GLES2Compat.hpp"

#include <hyprgraphics/egl/Egl.hpp>
#include <drm_fourcc.h>

#include <string_view>

#include "../debug/log/Logger.hpp"

namespace NGLES2Compat {
    SGLFormat glFormatFor(const Hyprgraphics::Egl::SPixelFormat* fmt) {
        using namespace Hyprgraphics::Egl;

        SGLFormat res{
            .internalFormat = fmt->glInternalFormat ? fmt->glInternalFormat : fmt->glFormat,
            .format         = fmt->glFormat,
            .type           = fmt->glType,
            .usable         = true,
        };

        // Half-float colour buffers cannot be expressed with a GLES2
        // glTexImage2D call; callers must not pick such a format.
        if (fmt->glType == GL_HALF_FLOAT_OES || fmt->drmFormat == DRM_FORMAT_ABGR16161616F || fmt->drmFormat == DRM_FORMAT_XBGR16161616F) {
            res.usable = false;
            return res;
        }

        // 10-bit formats (XRGB2101010 and the like): GLES2 has no colour-renderable 10-bit texture format.
        // glTexImage2D takes the type with EXT_texture_type_2_10_10_10_REV, but a framebuffer with such a
        // texture is incomplete, so a monitor must not be put into 10 bit (CMonitor::applyMonitorRule()).
        if (fmt->glType == GL_UNSIGNED_INT_2_10_10_10_REV_EXT) {
            res.usable = false;
            return res;
        }

        // GLES2 has no sized internal formats: internalformat must equal format.
        res.internalFormat = fmt->glFormat;

        // A BGRA-ordered 8888 format is uploaded as BGRA
        // directly instead, which is both correct and cheaper than sampling.
        //
        // Both BGRA (ARGB8888) and BGR1 (XRGB8888) qualify: the colour channels
        // are in the same order, and BGR1 only differs by forcing alpha to one,
        // which the renderer already handles by marking the texture TEXTURE_RGBX
        // and using the non-RGBA shader variant. Missing BGR1 here left every
        // opaque window sampling its channels reversed.
        const bool BGRA_ORDERED = fmt->swizzle.has_value() && (fmt->swizzle.value() == SWIZZLE_BGRA || fmt->swizzle.value() == SWIZZLE_BGR1);

        // anything else with a swizzle is unrepresentable; colours may be off, but do not error out
        if (BGRA_ORDERED && fmt->glFormat == GL_RGBA && fmt->glType == GL_UNSIGNED_BYTE) {
            res.internalFormat = GL_BGRA_EXT;
            res.format         = GL_BGRA_EXT;
        }

        return res;
    }

    std::string contextVersion() {
        const auto* VERSION = reinterpret_cast<const char*>(glGetString(GL_VERSION));
        return VERSION ? VERSION : "unknown";
    }

    bool checkVertexArrayObjectExt() {
        const auto* EXTENSIONS = reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS));
        if (!EXTENSIONS) {
            Log::logger->log(Log::ERR, "GLES2: could not query GL_EXTENSIONS");
            return false;
        }

        if (!std::string_view{EXTENSIONS}.contains("GL_OES_vertex_array_object")) {
            Log::logger->log(Log::ERR, "GLES2: driver does not advertise GL_OES_vertex_array_object, which the renderer requires");
            return false;
        }

        Log::logger->log(Log::DEBUG, "GLES2: GL_OES_vertex_array_object present");
        return true;
    }
}
