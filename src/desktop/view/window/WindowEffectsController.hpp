#pragma once

#include <optional>

#include "../../../render/transformer/Transformer.hpp"

namespace Render {
    class CWindowTransformerList;
}

namespace Desktop::View {
    class CWindow;

    class CWindowEffectsController {
      public:
        explicit CWindowEffectsController(CWindow& window);
        ~CWindowEffectsController();

        CWindowEffectsController(const CWindowEffectsController&)                            = delete;
        CWindowEffectsController(CWindowEffectsController&&)                                 = delete;
        CWindowEffectsController&                 operator=(const CWindowEffectsController&) = delete;
        CWindowEffectsController&                 operator=(CWindowEffectsController&&)      = delete;

        void                                      reset();

        bool                                      hasActiveTransformers() const;
        bool                                      blocksDirectScanout() const;
        CBox                                      transformedExtents(const CBox& currentBox) const;
        CBox                                      transformBoxForDamage(const CBox& currentBox) const;
        void                                      preWindowRender(CSurfacePassElement::SRenderData* renderData) const;
        const UP<Render::CWindowTransformerList>& transformers() const;

      private:
        CWindow&                           m_window;
        UP<Render::CWindowTransformerList> m_transformers;
    };
}
