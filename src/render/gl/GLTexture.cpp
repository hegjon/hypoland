#include "GLTexture.hpp"
#include "../../helpers/GLES2Compat.hpp"
#include "../Renderer.hpp"
#include "../../Compositor.hpp"
#include "../../helpers/Format.hpp"
#include "../../helpers/math/Math.hpp"
#include "../Texture.hpp"
#include <cstring>
#include <utility>
#include <hyprgraphics/egl/Egl.hpp>

using namespace Hyprgraphics::Egl;
using namespace Render::GL;

CGLTexture::CGLTexture(bool opaque) {
    m_opaque = opaque;
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

    if (!m_backTexID) {
        // first update: the second texture gets the whole buffer
        GLCALL(glGenTextures(1, &m_backTexID));
        GLCALL(glBindTexture(m_target, m_backTexID));
        GLCALL(glTexParameteri(m_target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
        GLCALL(glTexParameteri(m_target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        m_backCachedStates.fill(std::nullopt);
        m_backCachedStates[TEXTURE_PAR_WRAP_S] = GL_CLAMP_TO_EDGE;
        m_backCachedStates[TEXTURE_PAR_WRAP_T] = GL_CLAMP_TO_EDGE;
        GLCALL(glTexImage2D(m_target, 0, GLFMT.internalFormat, m_size.x, m_size.y, 0, GLFMT.format, GLFMT.type, pixels));
        g_pHyprOpenGL->trackBackTexture(this);
    } else {
        // a call per rectangle, see CHyprOpenGLImpl::coalesceDamage()
        static constexpr size_t MAX_UPLOAD_RECTS = 8;
        const CRegion           REGION           = DAMAGE.copy().add(m_backStaleDamage);

        GLCALL(glBindTexture(m_target, m_backTexID));
        uploadRegion(GLFMT.format, GLFMT.type, pixels, g_pHyprOpenGL->coalesceDamage() ? Math::coalesceRegion(REGION, MAX_UPLOAD_RECTS) : REGION);
    }

    m_backUsed = true;
    g_pHyprOpenGL->scheduleHeapTrim();

    // the texture that was shown until now misses this update
    std::swap(m_texID, m_backTexID);
    std::swap(m_cachedStates, m_backCachedStates);
    m_backStaleDamage = DAMAGE;

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
