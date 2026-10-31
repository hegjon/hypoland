#pragma once

#include "Fadeout.hpp"

namespace Desktop {
    class CWindowFadeout final : public IFadeout {
      public:
        static SP<CWindowFadeout>     create(PHLWINDOW window, SP<Render::IFramebuffer> snapshot, float sourceAlpha);

        virtual PHLMONITORREF         monitor() const override;
        virtual eFadeoutPlane         plane() const override;
        virtual int                   zIndex() const override;
        virtual CBox                  renderBox() const override;
        virtual float                 alpha() const override;
        virtual bool                  done() const override;
        virtual SFadeoutRenderEffects effects() const override;

        // damages where the fade draws the window now and where it drew it last, see m_contentBox
        void damage();

      private:
        CWindowFadeout() = default;

        CBox              drawnBox() const;

        PHLMONITORREF     m_monitor;
        eFadeoutPlane     m_plane  = FADEOUT_PLANE_WINDOW_TILED;
        int               m_zIndex = 0;
        Vector2D          m_sourcePos;
        Vector2D          m_sourceSize;
        PHLANIMVAR<float> m_alpha;

        bool              m_blur          = false;
        bool              m_blurXray      = false;
        int               m_rounding      = 0;
        float             m_roundingPower = 2.F;

        // where the snapshot holds the window (its frame and decorations, surfaces and popups) in the monitor's pixels,
        // empty when the fade needs the whole monitor (blur, a dim around it)
        CBox m_contentBox;
        CBox m_lastDamage;
    };
}
