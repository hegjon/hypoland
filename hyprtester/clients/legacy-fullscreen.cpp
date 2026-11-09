// An X11 window the way a game makes itself fullscreen without the window manager (GravityMark): no decorations asked for in
// _MOTIF_WM_HINTS, a fixed size at a given place, and no _NET_WM_STATE_FULLSCREEN; override-redirect if asked. It stays
// until it is killed or its connection ends.
// Usage: legacy-fullscreen X Y WIDTH HEIGHT CLASS [--override-redirect] [--decorated]
#include <xcb/xcb.h>

#include <array>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <print>
#include <string>
#include <string_view>

using CXCBReply = std::unique_ptr<xcb_intern_atom_reply_t, decltype(&std::free)>;
using CXCBEvent = std::unique_ptr<xcb_generic_event_t, decltype(&std::free)>;

static xcb_atom_t atom(xcb_connection_t* conn, std::string_view name) {
    const CXCBReply REPLY{xcb_intern_atom_reply(conn, xcb_intern_atom(conn, 0, name.size(), name.data()), nullptr), &std::free};
    return REPLY ? REPLY->atom : xcb_atom_t{XCB_ATOM_NONE};
}

int main(int argc, char** argv) {
    if (argc < 6) {
        std::println(stderr, "usage: legacy-fullscreen X Y WIDTH HEIGHT CLASS [--override-redirect] [--decorated]");
        return 2;
    }

    const int16_t     X = std::stoi(argv[1]), Y = std::stoi(argv[2]);
    const uint16_t    W = std::stoi(argv[3]), H = std::stoi(argv[4]);
    const std::string CLASS            = argv[5];
    bool              overrideRedirect = false, decorated = false;
    for (int i = 6; i < argc; ++i) {
        overrideRedirect |= std::string_view{argv[i]} == "--override-redirect";
        decorated |= std::string_view{argv[i]} == "--decorated";
    }

    auto* conn = xcb_connect(nullptr, nullptr);
    if (xcb_connection_has_error(conn)) {
        std::println(stderr, "legacy-fullscreen: no X server");
        return 1;
    }

    const auto*                   SCREEN = xcb_setup_roots_iterator(xcb_get_setup(conn)).data;
    const auto                    WINDOW = xcb_generate_id(conn);
    const std::array<uint32_t, 2> VALUES = {SCREEN->black_pixel, overrideRedirect ? 1U : 0U};
    xcb_create_window(conn, XCB_COPY_FROM_PARENT, WINDOW, SCREEN->root, X, Y, W, H, 0, XCB_WINDOW_CLASS_INPUT_OUTPUT, SCREEN->root_visual,
                      XCB_CW_BACK_PIXEL | XCB_CW_OVERRIDE_REDIRECT, VALUES.data());

    // WM_CLASS is instance and class, each ended by a NUL
    const std::string WMCLASS = CLASS + '\0' + CLASS + '\0';
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, WINDOW, XCB_ATOM_WM_CLASS, XCB_ATOM_STRING, 8, WMCLASS.size(), WMCLASS.data());
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, WINDOW, XCB_ATOM_WM_NAME, XCB_ATOM_STRING, 8, CLASS.size(), CLASS.data());

    // WM_NORMAL_HINTS as GravityMark sets them: the program's position and a fixed size (flags P_POSITION | P_MIN_SIZE | P_MAX_SIZE)
    std::array<uint32_t, 18> sizeHints = {};
    sizeHints[0]                       = 4 | 16 | 32;
    sizeHints[5] = sizeHints[7] = W;
    sizeHints[6] = sizeHints[8] = H;
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, WINDOW, XCB_ATOM_WM_NORMAL_HINTS, XCB_ATOM_WM_SIZE_HINTS, 32, sizeHints.size(), sizeHints.data());

    if (!decorated) {
        // flags: the decorations field counts (2); decorations: none
        const std::array<uint32_t, 5> MOTIF = {2, 0, 0, 0, 0};
        const auto                    ATOM  = atom(conn, "_MOTIF_WM_HINTS");
        xcb_change_property(conn, XCB_PROP_MODE_REPLACE, WINDOW, ATOM, ATOM, 32, MOTIF.size(), MOTIF.data());
    }

    xcb_map_window(conn, WINDOW);
    xcb_flush(conn);

    while (const CXCBEvent EVENT{xcb_wait_for_event(conn), &std::free}) {
        ;
    }

    xcb_disconnect(conn);
    return 0;
}
