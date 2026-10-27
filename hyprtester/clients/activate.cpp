// A window that asks to be activated: it maps an xdg toplevel with the given app id, keeps the serial of its
// keyboard focus, and once the trigger file is removed requests an xdg-activation token with that serial and
// activates itself. The focus tests use it for a client that requests focus; kitty's remote control did that
// before (`kitten @ focus-window`), foot's urgency bell sends no serial, which the compositor rejects.
//
//   activate --app-id ID --trigger FILE [--debug]

#include <print>
#include <poll.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#include <wayland-client.h>
#include <wayland.hpp>
#include <xdg-shell.hpp>
#include <xdg-activation-v1.hpp>

#include <hyprutils/memory/SharedPtr.hpp>
#include <hyprutils/math/Vector2D.hpp>

#include <string>
#include <utility>

using Hyprutils::Math::Vector2D;
using namespace Hyprutils::Memory;

struct SWlState {
    wl_display*                  display = nullptr;
    CSharedPointer<CCWlRegistry> registry;

    // protocols
    CSharedPointer<CCWlCompositor>         wlCompositor;
    CSharedPointer<CCWlSeat>               wlSeat;
    CSharedPointer<CCWlShm>                wlShm;
    CSharedPointer<CCXdgWmBase>            xdgShell;
    CSharedPointer<CCXdgActivationV1>      activation;
    CSharedPointer<CCXdgActivationTokenV1> token;

    // shm/buffer stuff
    CSharedPointer<CCWlShmPool> shmPool;
    CSharedPointer<CCWlBuffer>  shmBuf;
    int                         shmFd            = -1;
    bool                        xrgb8888_support = false;

    // surface/toplevel stuff
    CSharedPointer<CCWlSurface>   surf;
    CSharedPointer<CCXdgSurface>  xdgSurf;
    CSharedPointer<CCXdgToplevel> xdgToplevel;
    Vector2D                      geom = {640, 400};

    // input: the serial of the last keyboard enter (what the compositor validates a token by), pointer as fallback
    CSharedPointer<CCWlKeyboard> keyboard;
    CSharedPointer<CCWlPointer>  pointer;
    uint32_t                     keyboardSerial = 0;
    uint32_t                     pointerSerial  = 0;
};

static bool        debug, shouldExit, started, requested;
static std::string appId, trigger;

template <typename... Args>
//NOLINTNEXTLINE
static void clientLog(std::format_string<Args...> fmt, Args&&... args) {
    std::string text = std::format(fmt, std::forward<Args>(args)...);
    std::println("{}", text);
    std::fflush(stdout);
}

template <typename... Args>
//NOLINTNEXTLINE
static void debugLog(std::format_string<Args...> fmt, Args&&... args) {
    if (!debug)
        return;
    std::string text = std::format(fmt, std::forward<Args>(args)...);
    std::println("{}", text);
    std::fflush(stdout);
}

static bool bindRegistry(SWlState& state) {
    state.registry = makeShared<CCWlRegistry>((wl_proxy*)wl_display_get_registry(state.display));

    state.registry->setGlobal([&](CCWlRegistry* r, uint32_t id, const char* name, uint32_t version) {
        const std::string NAME = name;
        debugLog("  > global {} (version {}) id {}", name, version, id);
        if (NAME == "wl_compositor")
            state.wlCompositor = makeShared<CCWlCompositor>((wl_proxy*)wl_registry_bind((wl_registry*)state.registry->resource(), id, &wl_compositor_interface, 6));
        else if (NAME == "wl_shm")
            state.wlShm = makeShared<CCWlShm>((wl_proxy*)wl_registry_bind((wl_registry*)state.registry->resource(), id, &wl_shm_interface, 1));
        else if (NAME == "wl_seat")
            state.wlSeat = makeShared<CCWlSeat>((wl_proxy*)wl_registry_bind((wl_registry*)state.registry->resource(), id, &wl_seat_interface, 9));
        else if (NAME == "xdg_wm_base")
            state.xdgShell = makeShared<CCXdgWmBase>((wl_proxy*)wl_registry_bind((wl_registry*)state.registry->resource(), id, &xdg_wm_base_interface, 1));
        else if (NAME == "xdg_activation_v1")
            state.activation = makeShared<CCXdgActivationV1>((wl_proxy*)wl_registry_bind((wl_registry*)state.registry->resource(), id, &xdg_activation_v1_interface, 1));
    });
    state.registry->setGlobalRemove([](CCWlRegistry* r, uint32_t id) { debugLog("Global {} removed", id); });

    wl_display_roundtrip(state.display);

    if (!state.wlCompositor || !state.wlShm || !state.wlSeat || !state.xdgShell || !state.activation) {
        clientLog("Failed to get protocols from the compositor");
        return false;
    }

    return true;
}

static bool createShm(SWlState& state, Vector2D geom) {
    if (!state.xrgb8888_support)
        return false;

    const size_t STRIDE = geom.x * 4;
    const size_t SIZE   = geom.y * STRIDE;

    const auto   NAME = std::format("/wl-shm-activate-{}", getpid());
    state.shmFd       = shm_open(NAME.c_str(), O_RDWR | O_CREAT | O_EXCL, 0600);
    if (state.shmFd < 0)
        return false;

    if (shm_unlink(NAME.c_str()) < 0 || ftruncate(state.shmFd, SIZE) < 0) {
        close(state.shmFd);
        return false;
    }

    state.shmPool = makeShared<CCWlShmPool>(state.wlShm->sendCreatePool(state.shmFd, SIZE));
    if (!state.shmPool->resource())
        return false;

    state.shmBuf = makeShared<CCWlBuffer>(state.shmPool->sendCreateBuffer(0, geom.x, geom.y, STRIDE, WL_SHM_FORMAT_XRGB8888));
    return !!state.shmBuf->resource();
}

static bool setupToplevel(SWlState& state) {
    state.wlShm->setFormat([&](CCWlShm* p, uint32_t format) {
        if (format == WL_SHM_FORMAT_XRGB8888)
            state.xrgb8888_support = true;
    });

    state.xdgShell->setPing([&](CCXdgWmBase* p, uint32_t serial) { state.xdgShell->sendPong(serial); });

    state.surf = makeShared<CCWlSurface>(state.wlCompositor->sendCreateSurface());
    if (!state.surf->resource())
        return false;

    state.xdgSurf = makeShared<CCXdgSurface>(state.xdgShell->sendGetXdgSurface(state.surf->resource()));
    if (!state.xdgSurf->resource())
        return false;

    state.xdgToplevel = makeShared<CCXdgToplevel>(state.xdgSurf->sendGetToplevel());
    if (!state.xdgToplevel->resource())
        return false;

    state.xdgToplevel->setClose([&](CCXdgToplevel* p) { shouldExit = true; });

    state.xdgToplevel->setConfigure([&](CCXdgToplevel* p, int32_t w, int32_t h, wl_array* arr) {
        if (!state.shmBuf && !createShm(state, state.geom)) {
            clientLog("Failed to create a buffer");
            exit(-1);
        }
    });

    state.xdgSurf->setConfigure([&](CCXdgSurface* p, uint32_t serial) {
        state.xdgSurf->sendSetWindowGeometry(0, 0, state.geom.x, state.geom.y);
        state.surf->sendAttach(state.shmBuf.get(), 0, 0);
        state.surf->sendCommit();

        state.xdgSurf->sendAckConfigure(serial);

        if (!started) {
            started = true;
            clientLog("started");
        }
    });

    state.xdgToplevel->sendSetTitle(appId.c_str());
    state.xdgToplevel->sendSetAppId(appId.c_str());

    state.surf->sendAttach(nullptr, 0, 0);
    state.surf->sendCommit();

    return true;
}

static bool setupSeat(SWlState& state) {
    state.keyboard = makeShared<CCWlKeyboard>(state.wlSeat->sendGetKeyboard());
    if (!state.keyboard->resource())
        return false;

    state.keyboard->setKeymap([](CCWlKeyboard* k, uint32_t format, int32_t fd, uint32_t size) { close(fd); });
    state.keyboard->setEnter([&](CCWlKeyboard* k, uint32_t serial, wl_proxy* surf, wl_array* keys) {
        debugLog("keyboard enter, serial {}", serial);
        state.keyboardSerial = serial;
    });
    state.keyboard->setLeave([](CCWlKeyboard* k, uint32_t serial, wl_proxy* surf) { debugLog("keyboard leave, serial {}", serial); });

    state.pointer = makeShared<CCWlPointer>(state.wlSeat->sendGetPointer());
    if (!state.pointer->resource())
        return false;

    state.pointer->setEnter([&](CCWlPointer* p, uint32_t serial, wl_proxy* surf, wl_fixed_t x, wl_fixed_t y) {
        debugLog("pointer enter, serial {}", serial);
        state.pointerSerial = serial;
    });

    return true;
}

static void requestActivation(SWlState& state) {
    const uint32_t SERIAL = state.keyboardSerial ? state.keyboardSerial : state.pointerSerial;
    clientLog("requesting activation with serial {}", SERIAL);

    state.token = makeShared<CCXdgActivationTokenV1>(state.activation->sendGetActivationToken());
    if (!state.token->resource()) {
        clientLog("Failed to get an activation token");
        return;
    }

    state.token->setDone([&](CCXdgActivationTokenV1* t, const char* name) {
        debugLog("token {}", name);
        state.activation->sendActivate(name, state.surf->resource());
        state.token->sendDestroy();
        state.token.reset();
        clientLog("activated");
    });

    if (SERIAL)
        state.token->sendSetSerial(SERIAL, state.wlSeat->resource());
    state.token->sendSetSurface(state.surf->resource());
    state.token->sendSetAppId(appId.c_str());
    state.token->sendCommit();
}

int main(int argc, char** argv) {
    for (int i = 1; i < argc; ++i) {
        const std::string ARG = argv[i];
        if (ARG == "--debug")
            debug = true;
        else if (ARG == "--app-id" && i + 1 < argc)
            appId = argv[++i];
        else if (ARG == "--trigger" && i + 1 < argc)
            trigger = argv[++i];
        else {
            clientLog("usage: activate --app-id ID --trigger FILE [--debug]");
            return 1;
        }
    }
    if (appId.empty() || trigger.empty()) {
        clientLog("usage: activate --app-id ID --trigger FILE [--debug]");
        return 1;
    }

    SWlState state;

    // WAYLAND_DISPLAY env should be set to the correct one
    state.display = wl_display_connect(nullptr);
    if (!state.display) {
        clientLog("Failed to connect to wayland display");
        return -1;
    }

    if (!bindRegistry(state) || !setupSeat(state) || !setupToplevel(state))
        return -1;

    struct pollfd fds[1] = {{.fd = wl_display_get_fd(state.display), .events = POLLIN}};
    while (!shouldExit) {
        while (wl_display_prepare_read(state.display) != 0)
            wl_display_dispatch_pending(state.display);
        wl_display_flush(state.display);

        if (poll(fds, 1, 100) < 0) {
            wl_display_cancel_read(state.display);
            break;
        }

        if (fds[0].revents & POLLIN)
            wl_display_read_events(state.display);
        else
            wl_display_cancel_read(state.display);
        wl_display_dispatch_pending(state.display);

        if (started && !requested && access(trigger.c_str(), F_OK) != 0) {
            requested = true;
            requestActivation(state);
        }
    }

    wl_display* display = state.display;
    state               = {};
    wl_display_disconnect(display);
    return 0;
}
