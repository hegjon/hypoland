#include "MonitorResources.hpp"
#include "../managers/screenshare/ScreenshareManager.hpp"
#include "../helpers/cm/ColorManagement.hpp"
#include "../render/Renderer.hpp"
#include "../managers/eventLoop/EventLoopManager.hpp"
#include "../managers/eventLoop/EventLoopTimer.hpp"
#include <algorithm>
#include <cstdint>
#include <format>

using namespace Monitor;
using namespace NColorManagement;

static const int          MAX_WORK_BUFFERS             = 8;
static const int          MAX_UNUSED_SECONDS           = 5;
static constexpr uint64_t MAX_SIZED_WORK_BUFFER_PIXELS = 64ULL * 1024ULL * 1024ULL;

CMonitorResources::CMonitorResources(WP<CMonitor> monitor, DRMFormat format, Vector2D size, NColorManagement::PImageDescription imageDescription) :
    m_stencilTex(g_pHyprRenderer->createStencilTexture(size.x, size.y)), m_blurFB(g_pHyprRenderer->createFB(std::format("Monitor {} blur FB", monitor->m_name))),
    m_monitor(monitor), m_drmFormat(format), m_size(size), m_imageDescription(imageDescription) {
    initFB(m_blurFB);
    monitor->m_blurFBDirty = true;
}

CMonitorResources::~CMonitorResources() {
    if (m_cleanupTimer && g_pEventLoopManager)
        g_pEventLoopManager->removeTimer(m_cleanupTimer);
}

// Work buffers used to be dropped only when the next one was asked for. A monitor that renders directly
// never asks again, and kept the buffers of its first frames for good: 5 MiB each at 1280x800.
void CMonitorResources::scheduleCleanup() {
    if (!g_pEventLoopManager)
        return;

    if (!m_cleanupTimer) {
        m_cleanupTimer = makeShared<CEventLoopTimer>(std::nullopt, [this](SP<CEventLoopTimer> self, void* data) { releaseUnusedWorkBuffers(); }, nullptr);
        g_pEventLoopManager->addTimer(m_cleanupTimer);
    }

    if (!m_cleanupTimer->armed())
        m_cleanupTimer->updateTimeout(std::chrono::seconds(MAX_UNUSED_SECONDS + 1));
}

void CMonitorResources::releaseUnusedWorkBuffers() {
    const auto UNUSED = [](const auto& res) { return res.buffer.strongRef() < 2 && res.lastUsed.getSeconds() >= MAX_UNUSED_SECONDS; };

    std::erase_if(m_workBuffers, UNUSED);
    std::erase_if(m_sizedWorkBuffers, UNUSED);

    if (!m_workBuffers.empty() || !m_sizedWorkBuffers.empty())
        m_cleanupTimer->updateTimeout(std::chrono::seconds(MAX_UNUSED_SECONDS + 1));
}

void CMonitorResources::initFB(SP<Render::IFramebuffer> fb) {
    fb->addStencil(m_stencilTex);
    fb->alloc(m_size.x, m_size.y, m_drmFormat);
    fb->setImageDescription(m_imageDescription);
}

void CMonitorResources::setImageDescription(NColorManagement::PImageDescription imageDescription) {
    if (m_imageDescription == imageDescription)
        return;
    m_imageDescription = imageDescription;
    m_blurFB->setImageDescription(imageDescription);
    for (const auto& res : m_workBuffers)
        res.buffer->setImageDescription(imageDescription);
    for (const auto& res : m_sizedWorkBuffers)
        res.buffer->setImageDescription(imageDescription);
    if (m_monitorMirrorFB)
        m_monitorMirrorFB->setImageDescription(getMirrorTexImageDescription());
    invalidateMirrorFB();
}

SP<Render::IFramebuffer> CMonitorResources::getUnusedWorkBuffer() {
    std::erase_if(m_workBuffers, [](const auto& res) { return res.lastUsed.getSeconds() >= MAX_UNUSED_SECONDS; });

    auto found = std::ranges::find_if(m_workBuffers, [](const auto& res) { return res.buffer.strongRef() < 2; });
    if (found != m_workBuffers.end()) {
        found->lastUsed.reset();
        scheduleCleanup();
        return found->buffer;
    }
    if (m_workBuffers.size() >= MAX_WORK_BUFFERS)
        return nullptr;

    auto& res = m_workBuffers.emplace_back(g_pHyprRenderer->createFB(std::format("Monitor {} workbuffer", m_monitor->m_name)));
    initFB(res.buffer);
    res.lastUsed.reset();
    scheduleCleanup();
    return res.buffer;
}

SP<Render::IFramebuffer> CMonitorResources::getUnusedWorkBuffer(const Vector2D& size) {
    RASSERT((size.x > 0 && size.y > 0), "cannot get a workbuffer with negative / zero size! (attempted {}x{})", size.x, size.y);

    std::erase_if(m_sizedWorkBuffers, [](const auto& res) { return res.lastUsed.getSeconds() >= MAX_UNUSED_SECONDS; });

    auto found = std::ranges::find_if(m_sizedWorkBuffers, [&](const auto& res) {
        return res.buffer.strongRef() < 2 && res.buffer->isAllocated() && res.buffer->m_size == size && res.buffer->m_drmFormat == m_drmFormat;
    });
    if (found != m_sizedWorkBuffers.end()) {
        found->lastUsed.reset();
        scheduleCleanup();
        return found->buffer;
    }

    const uint64_t REQUESTEDPIXELS = sc<uint64_t>(size.x) * sc<uint64_t>(size.y);
    if (REQUESTEDPIXELS > MAX_SIZED_WORK_BUFFER_PIXELS)
        return nullptr;

    uint64_t allocatedPixels = 0;
    for (const auto& resource : m_sizedWorkBuffers)
        allocatedPixels += sc<uint64_t>(resource.buffer->m_size.x) * sc<uint64_t>(resource.buffer->m_size.y);

    for (auto resource = m_sizedWorkBuffers.begin(); resource != m_sizedWorkBuffers.end() && allocatedPixels + REQUESTEDPIXELS > MAX_SIZED_WORK_BUFFER_PIXELS;) {
        if (resource->buffer.strongRef() >= 2) {
            ++resource;
            continue;
        }

        allocatedPixels -= sc<uint64_t>(resource->buffer->m_size.x) * sc<uint64_t>(resource->buffer->m_size.y);
        resource = m_sizedWorkBuffers.erase(resource);
    }

    if (allocatedPixels + REQUESTEDPIXELS > MAX_SIZED_WORK_BUFFER_PIXELS)
        return nullptr;

    if (m_sizedWorkBuffers.size() < MAX_WORK_BUFFERS) {
        auto& res = m_sizedWorkBuffers.emplace_back(g_pHyprRenderer->createFB(std::format("Monitor {} sized workbuffer", m_monitor->m_name)));
        if (!res.buffer->alloc(size.x, size.y, m_drmFormat)) {
            m_sizedWorkBuffers.pop_back();
            return nullptr;
        }
        res.buffer->setImageDescription(m_imageDescription);
        res.lastUsed.reset();
        scheduleCleanup();
        return res.buffer;
    }

    found = std::ranges::find_if(m_sizedWorkBuffers, [](const auto& res) { return res.buffer.strongRef() < 2; });
    if (found == m_sizedWorkBuffers.end() || !found->buffer->alloc(size.x, size.y, m_drmFormat))
        return nullptr;

    found->buffer->setImageDescription(m_imageDescription);
    found->lastUsed.reset();
    scheduleCleanup();
    return found->buffer;
}

void CMonitorResources::forEachUnusedFB(std::function<void(SP<Render::IFramebuffer>)> callback, bool includeNamed) {
    const auto FOR_EACH_UNUSED = [&](const auto& buffers) {
        for (const auto& res : buffers) {
            if (res.buffer.strongRef() > 1)
                continue;

            callback(res.buffer);
        }
    };
    FOR_EACH_UNUSED(m_workBuffers);
    FOR_EACH_UNUSED(m_sizedWorkBuffers);
    if (includeNamed) {
        if (m_blurFB && m_blurFB->isAllocated() && m_blurFB.strongRef() < 2)
            callback(m_blurFB);
        if (hasMirrorFB() && m_monitorMirrorFB.strongRef() < 2)
            callback(m_monitorMirrorFB);
    }
}

bool CMonitorResources::hasMirrorFB() const {
    return m_monitorMirrorFB && m_monitorMirrorFB->isAllocated();
}

bool CMonitorResources::shouldKeepMirrorFB() const {
    return !m_monitor->m_mirrors.empty() || Screenshare::mgr()->isOutputBeingSSd(m_monitor.lock());
}

void CMonitorResources::releaseMirrorFB() {
    if (m_monitorMirrorFB)
        m_monitorMirrorFB->release();

    invalidateMirrorFB();
}

void CMonitorResources::invalidateMirrorFB() {
    m_mirrorFBValid            = false;
    m_mirrorFBNeedsFullRefresh = true;
    m_mirrorFBStaleDamage.clear();
}

void CMonitorResources::markMirrorFBStale(const CRegion& damage) {
    if (damage.empty() || !hasMirrorFB() || !m_mirrorFBValid)
        return;

    m_mirrorFBStaleDamage.add(damage).intersect(CBox{{}, mirrorFBDamageSize()});
}

void CMonitorResources::markMirrorFBStale() {
    if (!hasMirrorFB() || !m_mirrorFBValid)
        return;

    m_mirrorFBNeedsFullRefresh = true;
    m_mirrorFBStaleDamage.clear();
}

void CMonitorResources::markMirrorFBUpdated() {
    m_mirrorFBValid            = true;
    m_mirrorFBNeedsFullRefresh = false;
    m_mirrorFBStaleDamage.clear();
}

CRegion CMonitorResources::pendingMirrorFBDamage() const {
    const auto DAMAGE_SIZE = mirrorFBDamageSize();
    if (!hasMirrorFB() || !m_mirrorFBValid || m_mirrorFBNeedsFullRefresh)
        return CRegion{0, 0, DAMAGE_SIZE.x, DAMAGE_SIZE.y};

    return m_mirrorFBStaleDamage.copy();
}

SP<Render::IFramebuffer> CMonitorResources::mirrorFB() {
    if (!m_monitorMirrorFB)
        m_monitorMirrorFB = g_pHyprRenderer->createFB(std::format("Monitor {} mirror FB", m_monitor->m_name));

    if (!m_monitorMirrorFB->isAllocated()) {
        // the monitor's format, not the rule's wish: bitdepth 10 can be refused (CMonitor::applyMonitorRule())
        m_monitorMirrorFB->alloc(m_size.x, m_size.y, m_drmFormat);
        m_monitorMirrorFB->setImageDescription(getMirrorTexImageDescription());
    }

    return m_monitorMirrorFB;
}

SP<Render::ITexture> CMonitorResources::getMirrorTexture() {
    return hasMirrorFB() ? mirrorFB()->getTexture() : nullptr;
}

NColorManagement::PImageDescription CMonitorResources::getMirrorTexImageDescription() {
    const auto TF = m_imageDescription->value().transferFunction;
    if (TF == CM_TRANSFER_FUNCTION_GAMMA22 || TF == CM_TRANSFER_FUNCTION_SRGB)
        return m_imageDescription;

    return DEFAULT_SRGB_IMAGE_DESCRIPTION;
}

Vector2D CMonitorResources::mirrorFBDamageSize() const {
    return m_monitor->m_transformedSize;
}
