#include "GLTexture.hpp"
#include "../../helpers/GLES2Compat.hpp"
#include "../Renderer.hpp"
#include "../../Compositor.hpp"
#include "../../helpers/Format.hpp"
#include "../../helpers/math/Math.hpp"
#include "../../helpers/env/Env.hpp"
#include "../Texture.hpp"
#include <cstring>
#include <cstdlib>
#include <print>
#include <string_view>
#include <utility>
#include <drm_fourcc.h>
#include <aquamarine/allocator/DRMDumb.hpp>
#include <hyprgraphics/egl/Egl.hpp>
#include <hyprutils/os/FileDescriptor.hpp>

using namespace Hyprgraphics::Egl;
using namespace Render::GL;

CGLTexture::CGLTexture(bool opaque) {
    m_opaque = opaque;
}

// HYPOLAND_SHM_TEXTURE=linear backs synchronous textures with linear dumb buffers (see the header); linear-gl uploads
// into them through GL as Mesa does, a glTexSubImage2D per rectangle, instead of copying the rows, for comparing the two.
// HYPOLAND_SHM_TEXTURE: unset takes the driver's default, "linear" on iris, crocus, r600 and freedreno (measured on all
// of them, 2026-10-28/29), off elsewhere; "0" or "off" switches it off, "linear" on, "linear-gl" keeps Mesa's upload into
// the buffer.
static std::string_view shmTextureSwitch() {
    static const std::string S = [] {
        const char* v = std::getenv("HYPOLAND_SHM_TEXTURE");
        if (v && *v)
            return std::string{v};
        const auto& DRIVER = g_pHyprOpenGL->m_eglDriverName;
        return std::string{DRIVER == "iris" || DRIVER == "crocus" || DRIVER == "r600" || DRIVER == "msm" ? "linear" : ""};
    }();
    return S;
}

static bool shmTexturesEnabled() {
    return shmTextureSwitch().starts_with("linear");
}

static bool shmTextureUploadsThroughGL() {
    return shmTextureSwitch().ends_with("-gl");
}

// Gives the texture texID a linear dumb buffer of the size of this texture as its storage. Always ARGB8888: the uploads
// come as GL_BGRA_EXT whatever the client's format of the two it is used for, and the shader ignores the alpha of an
// RGBX texture. False when the switch is unset or it fails.
bool CGLTexture::backWithBuffer(GLuint texID, uint32_t drmFormat, SP<Aquamarine::IBuffer>& buffer, void*& image) {
    if (!shmTexturesEnabled() || !g_pHyprOpenGL->m_proc.glEGLImageTargetTexture2DOES)
        return false;
    if (drmFormat != DRM_FORMAT_ARGB8888 && drmFormat != DRM_FORMAT_XRGB8888)
        return false;

    const auto ALLOCATOR = g_pHyprOpenGL->dumbAllocatorForTextures();
    if (!ALLOCATOR) {
        static bool once = true;
        if (once)
            std::println(stderr, "shm texture: no dumb buffer allocator, textures stay Mesa's");
        once = false;
        return false;
    }

    buffer = ALLOCATOR->acquire(Aquamarine::SAllocatorBufferParams{.size = m_size, .format = DRM_FORMAT_ARGB8888}, nullptr);
    if (!buffer || !buffer->good()) {
        static bool once = true;
        if (once)
            std::println(stderr, "shm texture: no dumb buffer for {}x{}", sc<int>(m_size.x), sc<int>(m_size.y));
        once = false;
        buffer.reset();
        return false;
    }

    auto attrs     = buffer->dmabuf();
    attrs.modifier = DRM_FORMAT_MOD_LINEAR;
    image          = g_pHyprOpenGL->createEGLImage(attrs);
    if (image == EGL_NO_IMAGE_KHR) {
        std::println(stderr, "shm texture: EGL import of the dumb buffer failed");
        image = nullptr;
        buffer.reset();
        return false;
    }

    static bool said = false;
    if (!said)
        std::println(stderr, "shm texture: linear dumb buffers as texture storage");
    said = true;
    GLCALL(glBindTexture(m_target, texID));
    GLCALL(g_pHyprOpenGL->m_proc.glEGLImageTargetTexture2DOES(m_target, image));
    return true;
}

// Copies the rows of region from pixels (stride bytes a row, bpp bytes a pixel) into the buffer through its mapping
// instead of a glTexSubImage2D per rectangle: into an imported buffer Mesa has every call ask the kernel whether the
// buffer is busy, wait on it and go through blorp, hundreds of ioctls a frame for a client that damages many small
// rectangles (XPS sprites, 2026-10-28). A 1x1 upload through GL afterwards tells the driver that the texture changed,
// so it invalidates its sampler cache before the next draw as it does for its own uploads. No dma-buf sync calls around
// the copy: the mapping of a dumb buffer is write-combining (i915 maps them so or through the GTT, radeon's are in VRAM),
// so the CPU caches hold nothing of it, and on i915 without an LLC each sync call flushed the whole buffer out of the
// caches, twice per update (X200 gtk3-scroll 18.5 -> 27.7% with them, 2026-10-29). False when the switch keeps the GL
// path or the mapping fails.
bool CGLTexture::copyIntoBuffer(SP<Aquamarine::IBuffer>& buffer, GLenum format, GLenum type, uint8_t* pixels, uint32_t stride, uint32_t bpp, const CRegion& region) {
    if (shmTextureUploadsThroughGL() || region.empty())
        return false;

    auto [dst, dstFormat, dstLen] = buffer->beginDataPtr(0);
    if (!dst) {
        static bool once = true;
        if (once)
            std::println(stderr, "shm texture: the dumb buffer has no mapping, uploading through GL");
        once = false;
        return false;
    }

    const uint32_t DSTSTRIDE = buffer->dmabuf().strides[0];

    region.forEachRect([&](const auto& rect) {
        const size_t BYTES = sc<size_t>(rect.x2 - rect.x1) * bpp;
        for (int32_t y = rect.y1; y < rect.y2; ++y)
            memcpy(dst + sc<size_t>(y) * DSTSTRIDE + sc<size_t>(rect.x1) * bpp, pixels + sc<size_t>(y) * stride + sc<size_t>(rect.x1) * bpp, BYTES);
    });

    buffer->endDataPtr();

    const auto EXT = region.copy().getExtents();
    GLCALL(glPixelStorei(GL_UNPACK_SKIP_PIXELS_EXT, sc<GLint>(EXT.x)));
    GLCALL(glPixelStorei(GL_UNPACK_SKIP_ROWS_EXT, sc<GLint>(EXT.y)));
    GLCALL(glTexSubImage2D(m_target, 0, sc<GLint>(EXT.x), sc<GLint>(EXT.y), 1, 1, format, type, pixels));
    return true;
}

void CGLTexture::dropBuffer(SP<Aquamarine::IBuffer>& buffer, void*& image) {
    if (image)
        g_pHyprOpenGL->m_proc.eglDestroyImageKHR(g_pHyprOpenGL->m_eglDisplay, image);
    image = nullptr;
    buffer.reset();
}

CGLTexture::~CGLTexture() {
    if (!g_pCompositor || g_pCompositor->m_isShuttingDown || !g_pHyprRenderer)
        return;

    g_pHyprOpenGL->makeEGLCurrent();
    if (m_texID) {
        GLCALL(glDeleteTextures(1, &m_texID));
        m_texID = 0;
    }

    if (m_backTexID) {
        g_pHyprOpenGL->untrackBackTexture(this);
        GLCALL(glDeleteTextures(1, &m_backTexID));
        m_backTexID = 0;
    }

    if (m_eglImage)
        g_pHyprOpenGL->m_proc.eglDestroyImageKHR(g_pHyprOpenGL->m_eglDisplay, m_eglImage);
    m_eglImage = nullptr;
    dropBuffer(m_buffer, m_boImage);
    dropBuffer(m_backBuffer, m_backBoImage);
    m_cachedStates.fill(std::nullopt);
}

CGLTexture::CGLTexture(uint32_t drmFormat, uint8_t* pixels, uint32_t stride, const Vector2D& size_, bool keepDataCopy, bool opaque) :
    ITexture(drmFormat, pixels, stride, size_, keepDataCopy, opaque) {

    g_pHyprOpenGL->makeEGLCurrent();

    const auto format = getPixelFormatFromDRM(drmFormat);
    ASSERT(format);

    m_type          = format->withAlpha ? TEXTURE_RGBA : TEXTURE_RGBX;
    m_size          = size_;
    m_isSynchronous = true;
    m_target        = GL_TEXTURE_2D;
    allocate(size_);
    bind();
    setTexParameter(GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    setTexParameter(GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    const auto GLFMT = NGLES2Compat::glFormatFor(format);

    bool       alignmentChanged = false;
    if (format->bytesPerBlock != 4) {
        const GLint alignment = (stride % 4 == 0) ? 4 : 1;
        GLCALL(glPixelStorei(GL_UNPACK_ALIGNMENT, alignment));
        alignmentChanged = true;
    }

    GLCALL(glPixelStorei(GL_UNPACK_ROW_LENGTH_EXT, stride / format->bytesPerBlock));
    GLCALL(glTexImage2D(GL_TEXTURE_2D, 0, GLFMT.internalFormat, size_.x, size_.y, 0, GLFMT.format, GLFMT.type, pixels));
    GLCALL(glPixelStorei(GL_UNPACK_ROW_LENGTH_EXT, 0));
    if (alignmentChanged)
        GLCALL(glPixelStorei(GL_UNPACK_ALIGNMENT, 4));

    unbind();
}

CGLTexture::CGLTexture(const Aquamarine::SDMABUFAttrs& attrs, void* image, bool opaque) {
    m_opaque = opaque;
    if (!g_pHyprOpenGL->m_proc.glEGLImageTargetTexture2DOES) {
        Log::logger->log(Log::ERR, "Cannot create a dmabuf texture: no glEGLImageTargetTexture2DOES");
        return;
    }

    m_opaque = isDrmFormatOpaque(attrs.format);

    // #TODO external only formats should be external as well.
    // also needs a separate color shader.
    /*if (NFormatUtils::isFormatYUV(attrs.format)) {
        m_target = GL_TEXTURE_EXTERNAL_OES;
        m_type   = TEXTURE_EXTERNAL;
    } else {*/
    m_target = GL_TEXTURE_2D;
    m_type   = isDrmFormatOpaque(attrs.format) ? TEXTURE_RGBX : TEXTURE_RGBA;
    //}

    allocate(attrs.size, attrs.format);
    m_eglImage = image;

    bind();
    setTexParameter(GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    setTexParameter(GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    GLCALL(g_pHyprOpenGL->m_proc.glEGLImageTargetTexture2DOES(m_target, image));
    unbind();
}

// Writing to a texture that the GPU still reads from makes the driver (crocus at least) allocate, clear and
// cache-flush a staging buffer for every upload, which costs more than twice the upload itself. So the update
// goes into a second texture that was last shown one update ago and is idle by now, and the two are swapped.
// It pays on iris too: a Qt window scrolling in software took 13.8% of a ThinkPad T550's CPU, 16.3% with one texture.
// The second texture also gets the damage it missed while it was not shown; the client buffer is complete, so
// uploading more than the current damage is always correct. A surface that stops updating gives the second texture
// back after a second or two (CHyprOpenGLImpl::trackBackTexture()).
void CGLTexture::update(uint32_t drmFormat, uint8_t* pixels, uint32_t stride, const CRegion& damage) {
    if (damage.empty())
        return;

    g_pHyprOpenGL->makeEGLCurrent();

    const auto format = getPixelFormatFromDRM(drmFormat);
    ASSERT(format);

    // must use the same format mapping as the constructor, the texture was allocated with it
    const auto GLFMT = NGLES2Compat::glFormatFor(format);

    bool       alignmentChanged = false;
    if (format->bytesPerBlock != 4) {
        const GLint alignment = (stride % 4 == 0) ? 4 : 1;
        GLCALL(glPixelStorei(GL_UNPACK_ALIGNMENT, alignment));
        alignmentChanged = true;
    }

    GLCALL(glPixelStorei(GL_UNPACK_ROW_LENGTH_EXT, stride / format->bytesPerBlock));

    const CRegion DAMAGE = damage.copy().intersect(CBox{{}, m_size});

    // HYPOLAND_SINGLE_TEXTURE=1 updates the shown texture in place, as upstream does, for comparing the two on a machine
    static const bool SINGLE = Env::envEnabled("HYPOLAND_SINGLE_TEXTURE");

    if (SINGLE) {
        static constexpr size_t MAX_UPLOAD_RECTS = 8;
        bind();
        uploadRegion(GLFMT.format, GLFMT.type, pixels, g_pHyprOpenGL->coalesceDamage() ? Math::coalesceRegion(DAMAGE, MAX_UPLOAD_RECTS) : DAMAGE);
        g_pHyprOpenGL->scheduleHeapTrim();
    } else if (!m_backTexID) {
        // first update: the second texture gets the whole buffer
        GLCALL(glGenTextures(1, &m_backTexID));
        GLCALL(glBindTexture(m_target, m_backTexID));
        GLCALL(glTexParameteri(m_target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
        GLCALL(glTexParameteri(m_target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        m_backCachedStates.fill(std::nullopt);
        m_backCachedStates[TEXTURE_PAR_WRAP_S] = GL_CLAMP_TO_EDGE;
        m_backCachedStates[TEXTURE_PAR_WRAP_T] = GL_CLAMP_TO_EDGE;
        if (backWithBuffer(m_backTexID, drmFormat, m_backBuffer, m_backBoImage)) {
            const CRegion ALL{CBox{{}, m_size}};
            if (!copyIntoBuffer(m_backBuffer, GLFMT.format, GLFMT.type, pixels, stride, format->bytesPerBlock, ALL))
                uploadRegion(GLFMT.format, GLFMT.type, pixels, ALL);
        } else
            GLCALL(glTexImage2D(m_target, 0, GLFMT.internalFormat, m_size.x, m_size.y, 0, GLFMT.format, GLFMT.type, pixels));
        g_pHyprOpenGL->trackBackTexture(this);
    } else {
        // a call per rectangle, see CHyprOpenGLImpl::coalesceDamage()
        static constexpr size_t MAX_UPLOAD_RECTS = 8;
        const CRegion           REGION           = DAMAGE.copy().add(m_backStaleDamage);

        GLCALL(glBindTexture(m_target, m_backTexID));
        if (!m_backBuffer && m_buffer && backWithBuffer(m_backTexID, drmFormat, m_backBuffer, m_backBoImage)) {
            // the texture of the constructor, Mesa's storage until now: the new buffer needs everything
            const CRegion ALL{CBox{{}, m_size}};
            if (!copyIntoBuffer(m_backBuffer, GLFMT.format, GLFMT.type, pixels, stride, format->bytesPerBlock, ALL))
                uploadRegion(GLFMT.format, GLFMT.type, pixels, ALL);
        } else if (!(m_backBuffer && copyIntoBuffer(m_backBuffer, GLFMT.format, GLFMT.type, pixels, stride, format->bytesPerBlock, REGION)))
            uploadRegion(GLFMT.format, GLFMT.type, pixels, g_pHyprOpenGL->coalesceDamage() ? Math::coalesceRegion(REGION, MAX_UPLOAD_RECTS) : REGION);
    }

    if (!SINGLE) {
        m_backUsed = true;
        g_pHyprOpenGL->scheduleHeapTrim();

        // the texture that was shown until now misses this update
        std::swap(m_texID, m_backTexID);
        std::swap(m_cachedStates, m_backCachedStates);
        std::swap(m_buffer, m_backBuffer);
        std::swap(m_boImage, m_backBoImage);
        m_backStaleDamage = DAMAGE;
    }

    if (alignmentChanged)
        GLCALL(glPixelStorei(GL_UNPACK_ALIGNMENT, 4));

    GLCALL(glPixelStorei(GL_UNPACK_ROW_LENGTH_EXT, 0));
    GLCALL(glPixelStorei(GL_UNPACK_SKIP_PIXELS_EXT, 0));
    GLCALL(glPixelStorei(GL_UNPACK_SKIP_ROWS_EXT, 0));

    unbind();

    if (m_keepDataCopy) {
        m_dataCopy.resize(stride * m_size.y);
        memcpy(m_dataCopy.data(), pixels, stride * m_size.y);
    }
}

bool CGLTexture::releaseIdleBackTexture() {
    if (std::exchange(m_backUsed, false))
        return false;

    GLCALL(glDeleteTextures(1, &m_backTexID));
    m_backTexID = 0;
    dropBuffer(m_backBuffer, m_backBoImage);
    m_backStaleDamage.clear();
    m_backCachedStates.fill(std::nullopt);
    return true;
}

void CGLTexture::uploadRegion(GLenum format, GLenum type, uint8_t* pixels, const CRegion& region) {
    region.forEachRect([this, format, type, pixels](const auto& rect) {
        GLCALL(glPixelStorei(GL_UNPACK_SKIP_PIXELS_EXT, rect.x1));
        GLCALL(glPixelStorei(GL_UNPACK_SKIP_ROWS_EXT, rect.y1));
        GLCALL(glTexSubImage2D(m_target, 0, rect.x1, rect.y1, rect.x2 - rect.x1, rect.y2 - rect.y1, format, type, pixels));
    });
}

void CGLTexture::allocate(const Vector2D& size, uint32_t drmFormat) {
    if (!m_texID)
        GLCALL(glGenTextures(1, &m_texID));
    m_size      = size;
    m_drmFormat = drmFormat;
}

void CGLTexture::bind() {
    GLCALL(glBindTexture(m_target, m_texID));
}

void CGLTexture::unbind() {
    GLCALL(glBindTexture(m_target, 0));
}

bool CGLTexture::ok() {
    return m_texID > 0;
}

bool CGLTexture::isDMA() {
    return m_eglImage;
}

constexpr std::optional<size_t> CGLTexture::getCacheStateIndex(GLenum pname) {
    switch (pname) {
        case GL_TEXTURE_WRAP_S: return TEXTURE_PAR_WRAP_S;
        case GL_TEXTURE_WRAP_T: return TEXTURE_PAR_WRAP_T;
        case GL_TEXTURE_MAG_FILTER: return TEXTURE_PAR_MAG_FILTER;
        case GL_TEXTURE_MIN_FILTER: return TEXTURE_PAR_MIN_FILTER;
        default: return std::nullopt;
    }
}

void CGLTexture::setTexParameter(GLenum pname, GLint param) {
    const auto cacheIndex = getCacheStateIndex(pname);

    if (!cacheIndex) {
        GLCALL(glTexParameteri(m_target, pname, param));
        return;
    }

    const auto idx = cacheIndex.value();

    if (m_cachedStates[idx] == param)
        return;

    m_cachedStates[idx] = param;
    GLCALL(glTexParameteri(m_target, pname, param));
}
