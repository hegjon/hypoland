#include "TexPassElement.hpp"
#include "../Renderer.hpp"

CTexPassElement::CTexPassElement(const SRenderData& data) : m_data(data) {
    ;
}

CTexPassElement::CTexPassElement(CTexPassElement::SRenderData&& data) : m_data(std::move(data)) {
    ;
}

bool CTexPassElement::needsLiveBlur() {
    return usesLiveBlur();
}

bool CTexPassElement::needsPrecomputeBlur() {
    return m_data.blur && !usesLiveBlur();
}

bool CTexPassElement::usesLiveBlur() {
    if (m_usesLiveBlur.has_value())
        return *m_usesLiveBlur;

    m_usesLiveBlur =
        m_data.blur && (m_data.blockBlurOptimization.value_or(false) || !g_pHyprRenderer->shouldUseNewBlurOptimizations(m_data.currentLS.lock(), m_data.blurOwner.lock()));
    return *m_usesLiveBlur;
}

std::optional<CBox> CTexPassElement::boundingBox() {
    return m_data.box.copy().scale(1.F / g_pHyprRenderer->m_renderData.pMonitor->m_scale).round();
}

CRegion CTexPassElement::opaqueRegion() {
    return {}; // TODO:
}

void CTexPassElement::discard() {
    ;
}
