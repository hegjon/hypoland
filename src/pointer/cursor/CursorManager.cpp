#include "CursorManager.hpp"
#include "../../Compositor.hpp"
#include "../PointerManager.hpp"
#include "../../xwayland/XWayland.hpp"
#include "../../output/Monitor.hpp"
#include "../../event/EventBus.hpp"
#include "../../state/MonitorState.hpp"

using namespace Pointer;
using namespace Pointer::Cursor;

UP<CCursorManager>& Pointer::Cursor::mgr() {
    static UP<CCursorManager> p = makeUnique<CCursorManager>();
    return p;
}

static int cursorAnimTimer(SP<CEventLoopTimer> self, void* data) {
    const auto cursorMgr = sc<CCursorManager*>(data);
    cursorMgr->tickAnimatedCursor();
    return 1;
}

CCursorBuffer::CCursorBuffer(const uint8_t* pixelData, const Vector2D& size_, const Vector2D& hot_) : m_hotspot(hot_), m_stride(4 * size_.x) {
    size = size_;

    m_data = std::vector<uint8_t>(pixelData, pixelData + (sc<int>(size_.y) * m_stride));
}

Aquamarine::eBufferCapability CCursorBuffer::caps() {
    return Aquamarine::eBufferCapability::BUFFER_CAPABILITY_DATAPTR;
}

Aquamarine::eBufferType CCursorBuffer::type() {
    return Aquamarine::eBufferType::BUFFER_TYPE_SHM;
}

void CCursorBuffer::update(const Hyprutils::Math::CRegion& damage) {
    ;
}

bool CCursorBuffer::isSynchronous() {
    return true;
}

bool CCursorBuffer::good() {
    return true;
}

Aquamarine::SSHMAttrs CCursorBuffer::shm() {
    Aquamarine::SSHMAttrs attrs;
    attrs.success = true;
    attrs.format  = DRM_FORMAT_ARGB8888;
    attrs.size    = size;
    attrs.stride  = m_stride;
    return attrs;
}

std::tuple<uint8_t*, uint32_t, size_t> CCursorBuffer::beginDataPtr(uint32_t flags) {
    return {m_data.data(), DRM_FORMAT_ARGB8888, m_stride};
}

void CCursorBuffer::endDataPtr() {
    ;
}

CCursorManager::CCursorManager() {
    m_xcursor = makeUnique<CXCursorManager>();

    auto const* SIZE = getenv("XCURSOR_SIZE");
    if (SIZE) {
        try {
            m_size = std::stoi(SIZE);
        } catch (...) { Log::logger->log(Log::WARN, "Invalid XCURSOR_SIZE value \"{}\"", SIZE); }
    }

    if (m_size <= 0) {
        Log::logger->log(Log::WARN, "XCURSOR_SIZE size not set, defaulting to size 24");
        m_size = 24;
    }

    m_xcursor->loadTheme(getenv("XCURSOR_THEME") ? getenv("XCURSOR_THEME") : "default", m_size, m_cursorScale);

    m_animationTimer = makeShared<CEventLoopTimer>(std::nullopt, cursorAnimTimer, this);
    g_pEventLoopManager->addTimer(m_animationTimer);

    updateTheme();

    static auto P = Event::bus()->m_events.monitor.layoutChanged.listen([this] { this->updateTheme(); });
}

CCursorManager::~CCursorManager() {
    if (m_animationTimer && g_pEventLoopManager) {
        g_pEventLoopManager->removeTimer(m_animationTimer);
        m_animationTimer.reset();
    }
}

SP<Aquamarine::IBuffer> CCursorManager::getCursorBuffer() {
    return !m_cursorBuffers.empty() ? m_cursorBuffers.back() : nullptr;
}

void CCursorManager::setCursorSurface(SP<Desktop::View::CWLSurface> surf, const Vector2D& hotspot) {
    if (!surf || !surf->resource())
        Pointer::mgr()->resetCursorImage();
    else
        Pointer::mgr()->setCursorSurface(surf, hotspot);

    m_ourBufferConnected = false;
}

void CCursorManager::setCursorBuffer(SP<CCursorBuffer> buf, const Vector2D& hotspot, const float& scale) {
    m_cursorBuffers.emplace_back(buf);
    Pointer::mgr()->setCursorBuffer(getCursorBuffer(), hotspot, scale);
    if (m_cursorBuffers.size() > 1)
        std::erase_if(m_cursorBuffers, [this](const auto& buf) { return buf.get() == m_cursorBuffers.front().get(); });

    m_ourBufferConnected = true;
}

void CCursorManager::setAnimationTimer(const int& frame, const int& delay) {
    if (delay > 0) {
        // arm
        m_animationTimer->updateTimeout(std::chrono::milliseconds(delay));
    } else {
        // disarm
        m_animationTimer->updateTimeout(std::nullopt);
    }

    m_currentAnimationFrame = frame;
}

void CCursorManager::setCursorFromName(const std::string& name) {
    m_lastCursorName = name;

    float scale = std::ceil(m_cursorScale);

    auto  xcursor = m_xcursor->getShape(name, m_size, m_cursorScale);
    auto& icon    = xcursor->images.front();
    auto  buf     = makeShared<CCursorBuffer>(rc<uint8_t*>(icon.pixels.data()), icon.size, icon.hotspot);
    setCursorBuffer(buf, icon.hotspot / scale, scale);

    m_currentXcursor = xcursor;

    int delay = 0;
    int frame = 0;
    if (m_currentXcursor->images.size() > 1)
        delay = m_currentXcursor->images[frame].delay;

    setAnimationTimer(frame, delay);
}

void CCursorManager::tickAnimatedCursor() {
    if (!m_ourBufferConnected)
        return;

    if (!m_currentXcursor || m_currentXcursor->images.size() <= 1)
        return;

    m_currentAnimationFrame++;

    if (sc<size_t>(m_currentAnimationFrame) >= m_currentXcursor->images.size())
        m_currentAnimationFrame = 0;

    float scale = std::ceil(m_cursorScale);
    auto& icon  = m_currentXcursor->images.at(m_currentAnimationFrame);
    auto  buf   = makeShared<CCursorBuffer>(rc<uint8_t*>(icon.pixels.data()), icon.size, icon.hotspot);
    setCursorBuffer(buf, icon.hotspot / scale, scale);
    setAnimationTimer(m_currentAnimationFrame, m_currentXcursor->images[m_currentAnimationFrame].delay);
}

void CCursorManager::setXWaylandCursor() {
    auto  xcursor = m_xcursor->getShape("left_ptr", m_size, 1);
    auto& icon    = xcursor->images.front();

    g_pXWayland->setCursor(rc<uint8_t*>(icon.pixels.data()), icon.size.x * 4, icon.size, icon.hotspot);
}

void CCursorManager::updateTheme() {
    float highestScale = 1.0;

    for (auto const& m : State::monitorState()->monitors()) {
        if (m->m_scale > highestScale)
            highestScale = m->m_scale;
    }

    m_cursorScale = highestScale;

    for (auto const& m : State::monitorState()->monitors()) {
        m->m_forceFullFrames = 5;
        m->scheduleFrame(Aquamarine::IOutput::AQ_SCHEDULE_CURSOR_SHAPE);
    }
    if (m_ourBufferConnected)
        setCursorFromName(m_lastCursorName);
}

bool CCursorManager::changeTheme(const std::string& name, const int size) {
    m_theme            = name.empty() ? "" : name;
    m_size             = size <= 0 ? 24 : size;
    auto xcursor_theme = getenv("XCURSOR_THEME") ? getenv("XCURSOR_THEME") : "default";

    m_xcursor->loadTheme(m_theme.empty() ? xcursor_theme : m_theme, m_size, m_cursorScale);

    updateTheme();

    return true;
}

void CCursorManager::syncGsettings() {
    m_xcursor->syncGsettings();
}

float CCursorManager::getScaledSize() const {
    return m_size * m_cursorScale;
}
