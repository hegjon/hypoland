#include "WindowEffectsController.hpp"

#include "Window.hpp"
#include "../../../render/Renderer.hpp"
#include "../../../render/transformer/TransformerList.hpp"
#include "../../../output/Monitor.hpp"

using namespace Desktop::View;

CWindowEffectsController::CWindowEffectsController(CWindow& window) : m_window(window), m_transformers(makeUnique<Render::CWindowTransformerList>()) {
    ;
}

CWindowEffectsController::~CWindowEffectsController() = default;

void CWindowEffectsController::reset() {
    m_transformers->removeInactive();
}

bool CWindowEffectsController::hasActiveTransformers() const {
    return !m_transformers->empty();
}

bool CWindowEffectsController::blocksDirectScanout() const {
    return m_transformers->blocksDirectScanout();
}

CBox CWindowEffectsController::transformedExtents(const CBox& currentBox) const {
    return m_transformers->transformedExtents(currentBox);
}

CBox CWindowEffectsController::transformBoxForDamage(const CBox& currentBox) const {
    return m_transformers->transformBoxForDamage(currentBox);
}

void CWindowEffectsController::preWindowRender(CSurfacePassElement::SRenderData* renderData) const {
    m_transformers->preWindowRender(renderData);
}

const UP<Render::CWindowTransformerList>& CWindowEffectsController::transformers() const {
    return m_transformers;
}
