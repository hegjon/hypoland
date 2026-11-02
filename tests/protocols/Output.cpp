#include <protocols/core/Output.hpp>
#include <protocols/core/Compositor.hpp>
#include <protocols/PresentationTime.hpp>
#include <protocols/SessionLock.hpp>
#include <Compositor.hpp>
#include <animation/AnimationManager.hpp>
#include <config/ConfigValue.hpp>
#include <config/lua/ConfigManager.hpp>
#include <config/shared/animation/AnimationTree.hpp>
#include <config/shared/inotify/ConfigWatcher.hpp>
#include <config/supplementary/jeremy/Jeremy.hpp>
#include <event/EventBus.hpp>
#include <managers/eventLoop/EventLoopManager.hpp>
#include <output/Monitor.hpp>
#include <render/Renderer.hpp>

#include <gtest/gtest.h>
#include <hyprutils/os/FileDescriptor.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>

#include <array>
#include <cerrno>
#include <cstring>
#include <initializer_list>
#include <memory>
#include <utility>
#include <vector>
#include <sys/socket.h>

using namespace Hyprutils::OS;

struct SOutputTestEvent {
    uint32_t              objectID = 0;
    uint32_t              opcode   = 0;
    std::vector<uint32_t> payload;

    bool                  operator==(const SOutputTestEvent&) const = default;
};

class COutputTestOutput : public Aquamarine::IOutput {
  public:
    bool commit() override {
        ADD_FAILURE() << "Unexpected output commit";
        return false;
    }
    bool test() override {
        ADD_FAILURE() << "Unexpected output test";
        return false;
    }
    SP<Aquamarine::IBackendImplementation> getBackend() override {
        return nullptr;
    }
    std::vector<SDRMFormat> getRenderFormats() override {
        return {};
    }
    bool pendingPageFlip() override {
        return false;
    }
    bool pendingIdleFrame() override {
        return false;
    }
};

// Exercise real wl_output bindings and requests on an isolated Wayland server.
class COutputTest : public ::testing::Test {
  protected:
    void                                                       SetUp() override;
    void                                                       TearDown() override;
    PHLMONITOR                                                 makeMonitor();
    SP<CWLOutputProtocol>                                      makeProtocol(PHLMONITOR monitor);
    void                                                       removeAndExpireMonitor();
    void                                                       bindOutput();
    void                                                       readOutputEvents(std::vector<SOutputTestEvent>& events);
    void                                                       releaseOutput();
    void                                                       disconnectClient();

    std::unique_ptr<wl_display, decltype(&wl_display_destroy)> m_display{nullptr, wl_display_destroy};
    CFileDescriptor                                            m_socket;
    wl_client*                                                 m_client = nullptr; // Owned by m_display.
    PHLMONITOR                                                 m_monitor;
    SP<CWLOutputProtocol>                                      m_protocol;
    WP<CWLOutputResource>                                      m_resource;

  private:
    bool                                 m_installedGlobals = false;
    UP<CCompositor>                      m_previousCompositor;
    UP<CWLCompositorProtocol>            m_previousCompositorProtocol;
    UP<CEventLoopManager>                m_previousEventLoop;
    UP<Render::IHyprRenderer>            m_previousRenderer;
    UP<Event::CEventBus>                 m_previousEventBus;
    UP<Config::IConfigManager>           m_previousConfig;
    UP<Config::CConfigWatcher>           m_previousWatcher;
    UP<Animation::CHyprAnimationManager> m_previousAnimations;
    UP<Config::CAnimationTreeController> m_previousTree;
    decltype(PROTO::outputs)             m_previousOutputs;
    decltype(PROTO::defunctOutputs)      m_previousDefunctOutputs;
};

void COutputTest::SetUp() {
    m_display.reset(wl_display_create());
    ASSERT_NE(m_display, nullptr);

    std::array<int, 2> sockets = {
        -1,
        -1,
    };
    ASSERT_EQ(socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets.data()), 0);
    CFileDescriptor serverSocket{sockets[0]};
    m_socket = CFileDescriptor{sockets[1]};
    m_client = wl_client_create(m_display.get(), serverSocket.get());
    ASSERT_NE(m_client, nullptr);
    serverSocket.take(); // wl_client owns the socket now.

    m_previousCompositor         = std::move(g_pCompositor);
    m_previousCompositorProtocol = std::move(PROTO::compositor);
    m_previousEventLoop          = std::move(g_pEventLoopManager);
    m_previousRenderer           = std::move(g_pHyprRenderer);
    m_previousEventBus           = std::move(Event::bus());
    m_previousConfig             = std::move(Config::mgr());
    m_previousWatcher            = std::move(Config::watcher());
    m_previousAnimations         = std::move(Animation::mgr());
    m_previousTree               = std::move(Config::animationTree());
    m_previousOutputs.swap(PROTO::outputs);
    m_previousDefunctOutputs.swap(PROTO::defunctOutputs);
    m_installedGlobals = true;

    Event::bus()                 = makeUnique<Event::CEventBus>();
    g_pCompositor                = makeUnique<CCompositor>(true);
    g_pCompositor->m_wlDisplay   = m_display.get();
    g_pCompositor->m_wlEventLoop = wl_display_get_event_loop(m_display.get());
    // Only construct config defaults; the dummy path is never loaded.
    g_pCompositor->m_explicitConfigPath = "output-test.lua";
    Config::Supplementary::Jeremy::flushCachedCfgPath();
    Config::watcher() = makeUnique<Config::CConfigWatcher>();
    Config::mgr()     = makeUnique<Config::Lua::CConfigManager>();
    CConfigValueBase::flushCaches();
    Animation::mgr()        = makeUnique<Animation::CHyprAnimationManager>();
    Config::animationTree() = makeUnique<Config::CAnimationTreeController>();
    PROTO::compositor       = makeUnique<CWLCompositorProtocol>(&wl_compositor_interface, 6, "wl_compositor");
    ASSERT_NE(PROTO::compositor->getGlobal(), nullptr);

    m_monitor  = makeMonitor();
    m_protocol = makeProtocol(m_monitor);
    ASSERT_NE(m_protocol->getGlobal(), nullptr);
    PROTO::outputs.emplace(m_monitor->m_name, m_protocol);
}

void COutputTest::TearDown() {
    if (m_display)
        wl_display_destroy_clients(m_display.get());
    m_client = nullptr;
    m_socket.reset();
    if (!m_installedGlobals)
        return;

    m_protocol.reset();
    PROTO::outputs.clear();
    PROTO::defunctOutputs.clear();
    PROTO::compositor.reset();
    m_monitor.reset();
    Animation::mgr().reset();
    Config::animationTree().reset();
    Config::mgr().reset();
    Config::watcher().reset();
    g_pCompositor.reset();
    Event::bus().reset();

    PROTO::outputs.swap(m_previousOutputs);
    PROTO::defunctOutputs.swap(m_previousDefunctOutputs);
    PROTO::compositor       = std::move(m_previousCompositorProtocol);
    Animation::mgr()        = std::move(m_previousAnimations);
    Config::animationTree() = std::move(m_previousTree);
    Config::mgr()           = std::move(m_previousConfig);
    Config::watcher()       = std::move(m_previousWatcher);
    if (Config::mgr())
        CConfigValueBase::flushCaches();
    g_pCompositor       = std::move(m_previousCompositor);
    g_pEventLoopManager = std::move(m_previousEventLoop);
    g_pHyprRenderer     = std::move(m_previousRenderer);
    Event::bus()        = std::move(m_previousEventBus);
    Config::Supplementary::Jeremy::flushCachedCfgPath();
}

PHLMONITOR COutputTest::makeMonitor() {
    auto output     = makeShared<COutputTestOutput>();
    output->name    = "output-test";
    auto monitor    = makeShared<Monitor::CMonitor>(output);
    monitor->m_self = monitor;
    return monitor;
}

SP<CWLOutputProtocol> COutputTest::makeProtocol(PHLMONITOR monitor) {
    auto protocol    = makeShared<CWLOutputProtocol>(&wl_output_interface, 4, "wl_output", monitor);
    protocol->m_self = protocol;
    return protocol;
}

void COutputTest::removeAndExpireMonitor() {
    m_protocol->remove();
    m_monitor.reset();
    ASSERT_TRUE(m_protocol->isDefunct());
    ASSERT_TRUE(m_protocol->m_monitor.expired());
}

void COutputTest::bindOutput() {
    m_protocol->bindManager(m_client, nullptr, 4, 2);
    ASSERT_NE(wl_client_get_object(m_client, 2), nullptr);
    m_resource = CWLOutputResource::fromResource(wl_client_get_object(m_client, 2));
    ASSERT_FALSE(m_resource.expired());
    EXPECT_TRUE(m_resource->good());
    EXPECT_EQ(m_resource->client(), m_client);
    EXPECT_EQ(m_resource->m_owner.lock(), m_protocol);
    EXPECT_TRUE(m_protocol->hasBoundResources());
    EXPECT_EQ(m_protocol->outputResourcesFrom(m_client).size(), 1U);
}

void COutputTest::readOutputEvents(std::vector<SOutputTestEvent>& events) {
    events.clear();
    wl_client_flush(m_client);
    std::vector<uint8_t>      bytes;
    std::array<uint8_t, 1024> chunk = {};
    while (true) {
        const auto count = recv(m_socket.get(), chunk.data(), chunk.size(), MSG_DONTWAIT);
        if (count < 0 && errno == EINTR)
            continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            break;
        ASSERT_GT(count, 0);
        bytes.insert(bytes.end(), chunk.begin(), chunk.begin() + count);
    }

    for (size_t offset = 0; offset < bytes.size();) {
        std::array<uint32_t, 2> header = {};
        ASSERT_GE(bytes.size() - offset, sizeof(header));
        std::memcpy(header.data(), bytes.data() + offset, sizeof(header));
        const auto size = header[1] >> 16;
        ASSERT_GE(size, sizeof(header));
        ASSERT_EQ(size % sizeof(uint32_t), 0U);
        ASSERT_LE(size, bytes.size() - offset);
        SOutputTestEvent event{
            .objectID = header[0],
            .opcode   = header[1] & 0xFFFFU,
            .payload  = std::vector<uint32_t>((size - sizeof(header)) / sizeof(uint32_t)),
        };
        if (!event.payload.empty())
            std::memcpy(event.payload.data(), bytes.data() + offset + sizeof(header), size - sizeof(header));
        events.emplace_back(std::move(event));
        offset += size;
    }
}

void COutputTest::releaseOutput() {
    // wl_output.release: object 2, eight-byte request, opcode 0 (since v3).
    const std::array<uint32_t, 2> request = {
        2U,
        8U << 16,
    };
    ASSERT_EQ(send(m_socket.get(), request.data(), sizeof(request), MSG_NOSIGNAL), sc<ssize_t>(sizeof(request)));
    ASSERT_EQ(wl_event_loop_dispatch(wl_display_get_event_loop(m_display.get()), 0), 0);
    EXPECT_EQ(wl_client_get_object(m_client, 2), nullptr);
}

void COutputTest::disconnectClient() {
    m_socket.reset();
    ASSERT_EQ(wl_event_loop_dispatch(wl_display_get_event_loop(m_display.get()), 0), 0);
    m_client = nullptr;
}

TEST_F(COutputTest, LateBindAfterMonitorExpiresDrainsOnRelease) {
    ASSERT_NO_FATAL_FAILURE(removeAndExpireMonitor());
    ASSERT_NO_FATAL_FAILURE(bindOutput());

    ASSERT_NO_FATAL_FAILURE(releaseOutput());
    EXPECT_TRUE(m_resource.expired());
    EXPECT_FALSE(m_protocol->hasBoundResources());
    EXPECT_TRUE(m_protocol->outputResourcesFrom(m_client).empty());
    EXPECT_TRUE(PROTO::outputs.empty());
    EXPECT_TRUE(PROTO::defunctOutputs.empty());
}

TEST_F(COutputTest, LateBindAfterMonitorExpiresDrainsOnDisconnect) {
    ASSERT_NO_FATAL_FAILURE(removeAndExpireMonitor());
    ASSERT_NO_FATAL_FAILURE(bindOutput());

    ASSERT_NO_FATAL_FAILURE(disconnectClient());
    EXPECT_TRUE(m_resource.expired());
    EXPECT_FALSE(m_protocol->hasBoundResources());
    EXPECT_TRUE(PROTO::outputs.empty());
    EXPECT_TRUE(PROTO::defunctOutputs.empty());
}

TEST_F(COutputTest, DrainingDefunctOutputPreservesSameNameReplacement) {
    ASSERT_NO_FATAL_FAILURE(removeAndExpireMonitor());
    ASSERT_NO_FATAL_FAILURE(bindOutput());

    m_monitor        = makeMonitor();
    auto replacement = makeProtocol(m_monitor);
    ASSERT_NE(replacement->getGlobal(), nullptr);
    PROTO::defunctOutputs.emplace_back(m_protocol);
    PROTO::outputs.at(m_monitor->m_name) = replacement;

    // Only defunctOutputs owns the old protocol while its last resource drains.
    WP<CWLOutputProtocol> oldProtocol = m_protocol;
    m_protocol.reset();
    ASSERT_FALSE(oldProtocol.expired());
    ASSERT_EQ(PROTO::defunctOutputs.size(), 1U);

    ASSERT_NO_FATAL_FAILURE(releaseOutput());
    EXPECT_TRUE(m_resource.expired());
    EXPECT_TRUE(oldProtocol.expired());
    EXPECT_TRUE(PROTO::defunctOutputs.empty());
    ASSERT_EQ(PROTO::outputs.size(), 1U);
    ASSERT_TRUE(PROTO::outputs.contains(m_monitor->m_name));
    EXPECT_EQ(PROTO::outputs.at(m_monitor->m_name), replacement);
    EXPECT_FALSE(replacement->isDefunct());
}

TEST_F(COutputTest, LockSurfaceRequestedAfterMonitorRemovalIsInertAndDestroyable) {
    auto                                previousLock         = std::move(PROTO::sessionLock);
    auto                                previousPresentation = std::move(PROTO::presentation);
    const Hyprutils::Utils::CScopeGuard restoreProtocols{[&] {
        wl_display_destroy_clients(m_display.get());
        m_client            = nullptr;
        PROTO::sessionLock  = std::move(previousLock);
        PROTO::presentation = std::move(previousPresentation);
    }};
    PROTO::sessionLock  = makeUnique<CSessionLockProtocol>(&ext_session_lock_manager_v1_interface, 1, "ext_session_lock_manager_v1");
    PROTO::presentation = makeUnique<CPresentationProtocol>(&wp_presentation_interface, 2, "wp_presentation");

    CHyprSignalListener newSurface;
    auto                newLock = PROTO::sessionLock->m_events.newLock.listen(
        [&](const auto& lock) { newSurface = lock->m_events.newLockSurface.listen([](const auto&) { ADD_FAILURE() << "Removed output must not get an active lock surface"; }); });
    const auto sendRequest = [&](std::initializer_list<uint32_t> request) {
        const auto size = request.size() * sizeof(uint32_t);
        ASSERT_EQ(send(m_socket.get(), request.begin(), size, MSG_NOSIGNAL), sc<ssize_t>(size));
        ASSERT_EQ(wl_event_loop_dispatch(wl_display_get_event_loop(m_display.get()), 0), 0);
    };

    ASSERT_NO_FATAL_FAILURE(bindOutput());
    std::vector<SOutputTestEvent> events;
    ASSERT_NO_FATAL_FAILURE(readOutputEvents(events));
    PROTO::compositor->bindManager(m_client, nullptr, 6, 3);
    ASSERT_NO_FATAL_FAILURE(sendRequest({3U, 12U << 16, 4U})); // wl_compositor.create_surface(4)
    PROTO::sessionLock->bindManager(m_client, nullptr, 1, 5);
    ASSERT_NE(wl_client_get_object(m_client, 5), nullptr);
    ASSERT_NO_FATAL_FAILURE(sendRequest({5U, (12U << 16) | 1U, 6U})); // ext_session_lock_manager_v1.lock(6)
    ASSERT_NE(wl_client_get_object(m_client, 4), nullptr);
    ASSERT_NE(wl_client_get_object(m_client, 6), nullptr);

    ASSERT_NO_FATAL_FAILURE(removeAndExpireMonitor());
    // get_lock_surface(7, surface 4, output 2) races with output removal.
    ASSERT_NO_FATAL_FAILURE(sendRequest({6U, (20U << 16) | 1U, 7U, 4U, 2U}));
    const auto resource = wl_client_get_object(m_client, 7);
    ASSERT_NE(resource, nullptr);
    EXPECT_STREQ(wl_resource_get_class(resource), "ext_session_lock_surface_v1");
    EXPECT_EQ(wl_resource_get_version(resource), 1);
    ASSERT_NO_FATAL_FAILURE(readOutputEvents(events));
    EXPECT_TRUE(events.empty()); // No configure for the removed output.

    ASSERT_NO_FATAL_FAILURE(sendRequest({7U, 8U << 16})); // ext_session_lock_surface_v1.destroy
    ASSERT_EQ(wl_client_get_object(m_client, 7), nullptr);
    ASSERT_NO_FATAL_FAILURE(sendRequest({1U, 12U << 16, 8U})); // wl_display.sync(8)
    ASSERT_NO_FATAL_FAILURE(readOutputEvents(events));
    std::erase_if(events, [](const auto& event) { return event.objectID == 1 && event.opcode == WL_DISPLAY_DELETE_ID; });
    ASSERT_EQ(events.size(), 1U);
    EXPECT_EQ(events.front().objectID, 8U);
    EXPECT_EQ(events.front().opcode, WL_CALLBACK_DONE);
}
