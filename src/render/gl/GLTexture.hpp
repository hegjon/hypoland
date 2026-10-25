#pragma once

#include "../Texture.hpp"
#include <aquamarine/buffer/Buffer.hpp>
#include <hyprutils/math/Misc.hpp>

namespace Render::GL {

    class CGLTexture : public ITexture {
      public:
        using ITexture::ITexture;

        CGLTexture(CGLTexture&)        = delete;
        CGLTexture(CGLTexture&&)       = delete;
        CGLTexture(const CGLTexture&&) = delete;
        CGLTexture(const CGLTexture&)  = delete;

        CGLTexture(bool opaque = false);
        CGLTexture(uint32_t drmFormat, uint8_t* pixels, uint32_t stride, const Vector2D& size, bool keepDataCopy = false, bool opaque = false);
        CGLTexture(const Aquamarine::SDMABUFAttrs&, void* image, bool opaque = false);
        ~CGLTexture();

        void allocate(const Vector2D& size, uint32_t drmFormat = 0) override;
        void update(uint32_t drmFormat, uint8_t* pixels, uint32_t stride, const CRegion& damage) override;
        void bind() override;
        void unbind() override;
        void setTexParameter(GLenum pname, GLint param) override;
        bool ok() override;
        bool isDMA() override;

        // frees the second texture when there was no update since the last call, see
        // CHyprOpenGLImpl::trackBackTexture(). Returns whether it did
        bool releaseIdleBackTexture();

      private:
        void* m_eglImage = nullptr;

        // Synchronous (shm) textures are double buffered, see update(). m_backTexID is the texture that is not
        // shown, m_backStaleDamage what it is missing compared to the shown one.
        GLuint  m_backTexID = 0;
        CRegion m_backStaleDamage;
        bool    m_backUsed = false;

        enum eTextureParam : uint8_t {
            TEXTURE_PAR_WRAP_S = 0,
            TEXTURE_PAR_WRAP_T,
            TEXTURE_PAR_MAG_FILTER,
            TEXTURE_PAR_MIN_FILTER,
            TEXTURE_PAR_LAST,
        };

        GLenum                                             m_target = GL_TEXTURE_2D;

        constexpr std::optional<size_t>                    getCacheStateIndex(GLenum pname);
        void                                               uploadRegion(GLenum format, GLenum type, uint8_t* pixels, const CRegion& region);

        std::array<std::optional<GLint>, TEXTURE_PAR_LAST> m_cachedStates;
        std::array<std::optional<GLint>, TEXTURE_PAR_LAST> m_backCachedStates;
    };
}
