#pragma once

// Helpers for rendering with OpenGL ES 2.0, the only GL version Hypoland uses.
//
// Intel gen4 / gen4.5 / gen5 (GMA X3100 through GM45 to Ironlake) top out at
// OpenGL ES 2.0 under Mesa's crocus driver.

#include "../render/gl/GLES2.hpp"

#include <string>

namespace Hyprgraphics::Egl {
    struct SPixelFormat;
}

namespace NGLES2Compat {
    // The GL format/type triple to hand glTexImage2D for a pixel format.
    struct SGLFormat {
        int  internalFormat = 0;
        int  format         = 0;
        int  type           = 0;
        bool usable         = true; // false: not expressible in GLES2 (half-float and 10-bit formats)
    };

    // There is no texture swizzle in GLES2, so a BGRA-ordered 8888 format is
    // uploaded as GL_BGRA_EXT (EXT_texture_format_BGRA8888, which Mesa exposes
    // on crocus) rather than as RGBA plus a sampling swizzle. Sized internal
    // formats and half-float render targets do not exist either.
    SGLFormat glFormatFor(const Hyprgraphics::Egl::SPixelFormat* fmt);

    // glGetString(GL_VERSION) of the current context
    std::string contextVersion();

    // Verifies GL_OES_vertex_array_object on the current context. Mesa exposes
    // it on every gallium driver including crocus. Returns false if the driver
    // lacks it, in which case the renderer cannot run.
    bool checkVertexArrayObjectExt();
}
