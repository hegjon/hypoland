// A window drawn in dmabufs, for the direct scanout tests: GBM buffers on the compositor's main device (its dmabuf feedback),
// linear so the client fills them on the CPU, one new buffer a frame callback, the whole buffer damaged.
//
//   dmabuf-fullscreen [--format xrgb8888|xrgb2101010|argb8888] [--shrink N] [--transform N]
//
// argb8888 buffers are opaque all the same, and the surface says so with an opaque region.
// --shrink draws the buffer N pixels narrower and lower than the window's size, --transform sets the buffer transform. Commands on
// stdin, one a line: fullscreen, unfullscreen, frames (prints the frame callbacks it got so far), exit. Prints "started" once its
// first buffer is committed.

#include <algorithm>
#include <array>
#include <cstring>
#include <fcntl.h>
#include <format>
#include <print>
#include <ranges>
#include <span>
#include <string>
#include <sys/poll.h>
#include <unistd.h>
#include <vector>

#include <gbm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>

#include <wayland-client.h>
#include <wayland.hpp>
#include <xdg-shell.hpp>
#include <linux-dmabuf-v1.hpp>

#include <hyprutils/memory/SharedPtr.hpp>

using namespace Hyprutils::Memory;

struct SBuffer {
    gbm_bo*                    bo = nullptr;
    CSharedPointer<CCWlBuffer> buffer;
    bool                       busy = false;
};

struct SState {
    wl_display*                                display = nullptr;
    CSharedPointer<CCWlRegistry>               registry;
    CSharedPointer<CCWlCompositor>             compositor;
    CSharedPointer<CCXdgWmBase>                xdgWm;
    CSharedPointer<CCZwpLinuxDmabufV1>         dmabuf;
    CSharedPointer<CCZwpLinuxDmabufFeedbackV1> feedback;

    dev_t                                      mainDevice    = 0;
    bool                                       hasMainDevice = false;
    int                                        drmFd         = -1;
    gbm_device*                                gbm           = nullptr;

    uint32_t                                   format    = DRM_FORMAT_XRGB8888;
    int                                        shrink    = 0;
    int                                        transform = 0;

    CSharedPointer<CCWlSurface>                surf;
    CSharedPointer<CCXdgSurface>               xdgSurf;
    CSharedPointer<CCXdgToplevel>              toplevel;
    CSharedPointer<CCWlCallback>               frameCallback;
    int                                        width = 640, height = 480; // the window's size
    int                                        pendingWidth = 0, pendingHeight = 0;

    std::array<SBuffer, 3>                     buffers;
    int                                        bufferWidth = 0, bufferHeight = 0;
    size_t                                     frames  = 0;
    uint32_t                                   drawn   = 0;
    bool                                       started = false;
    bool                                       waiting = false; // a frame is due but every buffer is busy
};

static bool shouldExit = false;

template <typename... Args>
static void clientLog(std::format_string<Args...> fmt, Args&&... args) {
    std::println("{}", std::format(fmt, std::forward<Args>(args)...));
    std::fflush(stdout);
}

static bool bindGlobals(SState& s) {
    s.registry = makeShared<CCWlRegistry>((wl_proxy*)wl_display_get_registry(s.display));

    s.registry->setGlobal([&](CCWlRegistry* r, uint32_t id, const char* iface, uint32_t version) {
        const std::string n = iface;
        if (n == "wl_compositor")
            s.compositor = makeShared<CCWlCompositor>((wl_proxy*)wl_registry_bind((wl_registry*)r->resource(), id, &wl_compositor_interface, 4));
        else if (n == "xdg_wm_base")
            s.xdgWm = makeShared<CCXdgWmBase>((wl_proxy*)wl_registry_bind((wl_registry*)r->resource(), id, &xdg_wm_base_interface, 1));
        else if (n == "zwp_linux_dmabuf_v1" && version >= 4)
            s.dmabuf = makeShared<CCZwpLinuxDmabufV1>((wl_proxy*)wl_registry_bind((wl_registry*)r->resource(), id, &zwp_linux_dmabuf_v1_interface, 4));
    });
    s.registry->setGlobalRemove([](CCWlRegistry*, uint32_t) {});
    wl_display_roundtrip(s.display);

    return s.compositor && s.xdgWm && s.dmabuf;
}

// the render node of the compositor's main device
static bool openDevice(SState& s) {
    s.feedback = makeShared<CCZwpLinuxDmabufFeedbackV1>(s.dmabuf->sendGetDefaultFeedback());
    s.feedback->setMainDevice([&](CCZwpLinuxDmabufFeedbackV1*, wl_array* device) {
        if (device->size != sizeof(dev_t))
            return;
        std::memcpy(&s.mainDevice, device->data, sizeof(dev_t));
        s.hasMainDevice = true;
    });
    wl_display_roundtrip(s.display);

    if (!s.hasMainDevice)
        return false;

    drmDevicePtr device = nullptr;
    if (drmGetDeviceFromDevId(s.mainDevice, 0, &device) != 0)
        return false;

    if (device->available_nodes & (1 << DRM_NODE_RENDER))
        s.drmFd = open(device->nodes[DRM_NODE_RENDER], O_RDWR | O_CLOEXEC);
    drmFreeDevice(&device);

    if (s.drmFd < 0)
        return false;

    s.gbm = gbm_create_device(s.drmFd);
    return s.gbm;
}

static void destroyBuffers(SState& s) {
    for (auto& b : s.buffers) {
        if (b.buffer)
            b.buffer->sendDestroy();
        b.buffer.reset();
        if (b.bo)
            gbm_bo_destroy(b.bo);
        b.bo   = nullptr;
        b.busy = false;
    }
}

// one solid colour per buffer, so every frame differs from the one before
static bool fill(SState& s, gbm_bo* bo, size_t index) {
    uint32_t stride = 0;
    void*    data   = nullptr;
    void*    map    = gbm_bo_map(bo, 0, 0, s.bufferWidth, s.bufferHeight, GBM_BO_TRANSFER_WRITE, &stride, &data);
    if (!map)
        return false;

    static constexpr std::array<uint32_t, 3> COLORS8  = {0xFFFF00FF, 0xFF00FFFF, 0xFFFFFF00};
    static constexpr std::array<uint32_t, 3> COLORS10 = {0xFFF003FF, 0xC00FFFFF, 0xFFFFFC00};
    const uint32_t                           COLOR    = (s.format == DRM_FORMAT_XRGB2101010 ? COLORS10 : COLORS8)[index % 3];

    for (int y = 0; y < s.bufferHeight; ++y) {
        auto row = std::span<uint32_t>((uint32_t*)((uint8_t*)map + (size_t)y * stride), s.bufferWidth);
        std::ranges::fill(row, COLOR);
    }

    gbm_bo_unmap(bo, data);
    return true;
}

static bool makeBuffers(SState& s, int width, int height) {
    destroyBuffers(s);
    s.bufferWidth  = std::max(1, width - s.shrink);
    s.bufferHeight = std::max(1, height - s.shrink);

    for (size_t i = 0; i < s.buffers.size(); ++i) {
        auto& b = s.buffers[i];
        b.bo    = gbm_bo_create(s.gbm, s.bufferWidth, s.bufferHeight, s.format, GBM_BO_USE_RENDERING | GBM_BO_USE_LINEAR);
        if (!b.bo || !fill(s, b.bo, i))
            return false;

        const int      FD       = gbm_bo_get_fd(b.bo);
        const uint64_t MODIFIER = gbm_bo_get_modifier(b.bo);
        if (FD < 0)
            return false;

        auto params = makeShared<CCZwpLinuxBufferParamsV1>(s.dmabuf->sendCreateParams());
        params->sendAdd(FD, 0, gbm_bo_get_offset(b.bo, 0), gbm_bo_get_stride(b.bo), MODIFIER >> 32, MODIFIER & 0xFFFFFFFF);
        b.buffer = makeShared<CCWlBuffer>(params->sendCreateImmed(s.bufferWidth, s.bufferHeight, s.format, (zwpLinuxBufferParamsV1Flags)0));
        params->sendDestroy();
        close(FD);

        if (!b.buffer || !b.buffer->resource())
            return false;

        b.buffer->setRelease([&b](CCWlBuffer*) { b.busy = false; });
    }

    if (s.format == DRM_FORMAT_ARGB8888) {
        auto region = makeShared<CCWlRegion>(s.compositor->sendCreateRegion());
        region->sendAdd(0, 0, s.bufferWidth, s.bufferHeight);
        s.surf->sendSetOpaqueRegion(region.get());
        region->sendDestroy();
    }

    return true;
}

static void requestFrame(SState& s);

// attaches the next free buffer; a frame callback or a release of a buffer calls it again
static void draw(SState& s) {
    SBuffer* next = nullptr;
    for (size_t i = 0; i < s.buffers.size(); ++i) {
        auto& b = s.buffers[(s.drawn + i) % s.buffers.size()];
        if (b.busy || !b.buffer)
            continue;
        next = &b;
        break;
    }

    if (!next) {
        s.waiting = true;
        return;
    }

    s.waiting  = false;
    next->busy = true;
    s.drawn++;
    s.surf->sendAttach(next->buffer.get(), 0, 0);
    s.surf->sendDamageBuffer(0, 0, s.bufferWidth, s.bufferHeight);
    requestFrame(s);
    s.surf->sendCommit();
}

static void requestFrame(SState& s) {
    s.frameCallback = makeShared<CCWlCallback>(s.surf->sendFrame());
    s.frameCallback->setDone([&s](CCWlCallback*, uint32_t) {
        s.frames++;
        draw(s);
    });
}

static bool setupSurface(SState& s) {
    s.xdgWm->setPing([](CCXdgWmBase* p, uint32_t serial) { p->sendPong(serial); });

    s.surf     = makeShared<CCWlSurface>(s.compositor->sendCreateSurface());
    s.xdgSurf  = makeShared<CCXdgSurface>(s.xdgWm->sendGetXdgSurface(s.surf->resource()));
    s.toplevel = makeShared<CCXdgToplevel>(s.xdgSurf->sendGetToplevel());

    if (!s.surf->resource() || !s.xdgSurf->resource() || !s.toplevel->resource())
        return false;

    s.toplevel->setClose([](CCXdgToplevel*) { shouldExit = true; });
    s.toplevel->setConfigure([&s](CCXdgToplevel*, int32_t w, int32_t h, wl_array*) {
        s.pendingWidth  = w;
        s.pendingHeight = h;
    });

    s.xdgSurf->setConfigure([&s](CCXdgSurface* p, uint32_t serial) {
        if (s.pendingWidth > 0 && s.pendingHeight > 0) {
            s.width  = s.pendingWidth;
            s.height = s.pendingHeight;
        }
        p->sendAckConfigure(serial);

        if (s.width - s.shrink != s.bufferWidth || s.height - s.shrink != s.bufferHeight) {
            if (!makeBuffers(s, s.width, s.height)) {
                clientLog("failed to allocate the buffers");
                exit(1);
            }
            s.frameCallback.reset();
            draw(s);
        }

        if (!s.started) {
            s.started = true;
            clientLog("started");
        }
    });

    s.toplevel->sendSetTitle("dmabuf-fullscreen client");
    s.toplevel->sendSetAppId("dmabuf-fullscreen");
    if (s.transform)
        s.surf->sendSetBufferTransform(s.transform);
    s.surf->sendCommit();

    return true;
}

static void handleCmd(SState& s, std::string_view cmd) {
    if (cmd.starts_with("unfullscreen"))
        s.toplevel->sendUnsetFullscreen();
    else if (cmd.starts_with("fullscreen"))
        s.toplevel->sendSetFullscreen(nullptr);
    else if (cmd.starts_with("frames"))
        clientLog("frames {}", s.frames);
    else if (cmd.starts_with("exit"))
        shouldExit = true;
    wl_display_flush(s.display);
}

int main(int argc, char** argv) {
    SState s;

    for (int i = 1; i + 1 < argc; i += 2) {
        const std::string_view ARG = argv[i], VALUE = argv[i + 1];
        if (ARG == "--format")
            s.format = VALUE == "xrgb2101010" ? DRM_FORMAT_XRGB2101010 : VALUE == "argb8888" ? DRM_FORMAT_ARGB8888 : DRM_FORMAT_XRGB8888;
        else if (ARG == "--shrink")
            s.shrink = std::stoi(std::string{VALUE});
        else if (ARG == "--transform")
            s.transform = std::stoi(std::string{VALUE});
    }

    s.display = wl_display_connect(nullptr);
    if (!s.display) {
        clientLog("connect failed");
        return 1;
    }

    if (!bindGlobals(s)) {
        clientLog("failed to bind globals (no zwp_linux_dmabuf_v1 version 4?)");
        return 1;
    }

    if (!openDevice(s)) {
        clientLog("failed to open the compositor's main device");
        return 1;
    }

    if (!setupSurface(s)) {
        clientLog("surface setup failed");
        return 1;
    }

    wl_display_flush(s.display);

    std::array<char, 1024> buf = {};
    std::array<pollfd, 2>  fds = {pollfd{.fd = wl_display_get_fd(s.display), .events = POLLIN}, pollfd{.fd = STDIN_FILENO, .events = POLLIN}};

    while (!shouldExit) {
        wl_display_flush(s.display);
        if (poll(fds.data(), fds.size(), -1) < 0)
            break;

        if (fds[0].revents & (POLLERR | POLLHUP))
            break;

        if (fds[0].revents & POLLIN) {
            if (wl_display_dispatch(s.display) < 0)
                break;
            // a release can come without a frame callback after it
            if (s.waiting)
                draw(s);
        }

        if (fds[1].revents & POLLIN) {
            const ssize_t N = read(STDIN_FILENO, buf.data(), buf.size() - 1);
            if (N <= 0)
                break;
            buf[N] = 0;
            for (const auto& line : std::string_view{buf.data(), (size_t)N} | std::views::split('\n'))
                handleCmd(s, std::string_view{line.begin(), line.end()});
        }
    }

    destroyBuffers(s);
    if (s.gbm)
        gbm_device_destroy(s.gbm);
    if (s.drmFd >= 0)
        close(s.drmFd);
    wl_display_disconnect(s.display);
    return 0;
}
