#pragma once

#include <string>
#include <optional>
#include "../../helpers/time/Time.hpp"
#include "../../defines.hpp"
#include "WLSurface.hpp"
#include "View.hpp"
#include "../rule/layerRule/LayerRuleApplicator.hpp"
#include "../../helpers/AnimatedVariable.hpp"
#include "../../render/Framebuffer.hpp"
#include "../../macros/Enums.hpp"
#include "types/GeometricMovableAnimated.hpp"
#include "types/AlphaModifiable.hpp"
#include "surfaceTree/PopupOwner.hpp"
#include "animationControllers/LayerSurfaceAnimationController.hpp"

class CLayerShellResource;

namespace Desktop::View {

    enum eLayerAlpha : uint8_t {
        LS_ALPHA_FADE = 0,

        LS_ALPHA_LAST,
    };

    enum class eLayerFlags : uint8_t {
        LAYER_FLAG_NONE             = 0,
        LAYER_FLAG_DEAD             = (1 << 0),
        LAYER_FLAG_ABOVE_FULLSCREEN = (1 << 1),
    };

    using enum eLayerFlags;
    EXPOSE_ENUM_AS_MASK(eLayerFlags, LayerFlags);

    class CLayerSurface : public virtual IView, public virtual CGeometricMovableAnimated, public virtual IAlphaModifiable, public virtual CPopupOwner {
      public:
        static PHLLS create(SP<CLayerShellResource>);
        static PHLLS fromView(SP<IView>);

      private:
        CLayerSurface(SP<CLayerShellResource>);

      public:
        virtual ~CLayerSurface();

        virtual eViewType                                         type() const override;
        virtual bool                                              mapped() const override;
        virtual bool                                              focusAvailable() const override;
        virtual std::optional<CBox>                               logicalBox() const override;
        virtual bool                                              desktopComponent() const override;
        virtual std::optional<CBox>                               surfaceLogicalBox() const override;
        virtual Types::CMultiAVarContainer<float, uint8_t>&       alpha() override;
        virtual const Types::CMultiAVarContainer<float, uint8_t>& alpha() const override;
        virtual std::optional<uint8_t>                            alphaGenericToKey(eAlphaModifiableProp p) override;

        WP<CLayerShellResource>                                   m_layerSurface;
        bool                                                      shouldBlur() const;

        LayerFlags                                                m_flags = LAYER_FLAG_ABOVE_FULLSCREEN;

        // the header providing the enum type cannot be imported here
        int                                     m_keyboardInteractivity = 0;

        uint32_t                                m_layer = 0;

        PHLMONITORREF                           m_monitor;

        UP<Desktop::Rule::CLayerRuleApplicator> m_ruleApplicator;

        PHLLSREF                                m_self;

        CLayerSurfaceAnimationController        m_animationController;

        CBox                                    m_geometry = {0, 0, 0, 0};
        Vector2D                                m_position;
        std::string                             m_namespace = "";
        // The box of the pixels with alpha above zero in the current buffer, in buffer pixels, found by
        // CHyprOpenGLImpl::analyzeLayerAlpha() once the surface stops committing; renderLayer() draws only that part. A
        // commit drops it. The serial tells an analysis of an older buffer from the current one.
        std::optional<CBox>       m_alphaBounds;
        bool                      m_alphaBoundsDirty = false;
        uint32_t                  m_alphaSerial      = 0;
        Time::steady_tp           m_alphaCommitTime;
        std::chrono::milliseconds m_alphaCommitInterval{0}; // between the last two commits with content
        std::chrono::milliseconds alphaSettle() const;      // how long the analysis waits after a commit
        pid_t                     getPID();
        void                      updateSurfaceScaleTransformDetails();

        void                      onDestroy();
        void                      onMap();
        void                      onUnmap();
        void                      onCommit();
        MONITORID                 monitorID();

      private:
        bool m_mapped = false;

        struct {
            CHyprSignalListener destroy;
            CHyprSignalListener map;
            CHyprSignalListener unmap;
            CHyprSignalListener commit;
            CHyprSignalListener newPopup;
        } m_listeners;

        void registerCallbacks();
        void takeKeyboardFocus();

        // fade in/out
        Desktop::Types::CMultiAVarContainer<float, std::underlying_type_t<eLayerAlpha>> m_alpha;

        // For the list lookup
        bool operator==(const CLayerSurface& rhs) const {
            return m_layerSurface == rhs.m_layerSurface && m_monitor == rhs.m_monitor;
        }
    };

    inline bool valid(PHLLS l) {
        return !!l;
    }

    inline bool valid(PHLLSREF l) {
        return !!l;
    }

    inline bool validMapped(const PHLLS& l) {
        if (!valid(l))
            return false;
        return l->mapped();
    }

    inline bool validMapped(const PHLLSREF& l) {
        if (!valid(l))
            return false;
        return l->mapped();
    }

}
