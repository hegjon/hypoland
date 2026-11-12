#pragma once

#include "Provider.hpp"

namespace Render::GL {
    class CHyprOpenGLImpl;

    class CDualKawaseBlurProvider : public IGLBlurProvider {
      public:
        explicit CDualKawaseBlurProvider(CHyprOpenGLImpl& impl);

        void expandDamage(CRegion& damage, float multiplier = 1.F) const override;

      protected:
        SP<CGLFramebuffer> blurGL(SP<CGLFramebuffer> source, float strength, const CRegion& originalDamage) override;

      private:
        float            damageRadius() const;

        CHyprOpenGLImpl& m_impl;
    };

    float dualKawaseDamageRadius(int64_t size, int64_t passes);
}
