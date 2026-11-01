#include "tests.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include <hyprutils/os/Process.hpp>
#include <hyprutils/memory/WeakPtr.hpp>
#include "../shared.hpp"

using namespace Hyprutils::OS;
using namespace Hyprutils::Memory;

#define UP CUniquePointer
#define SP CSharedPointer

// Uncomment once test vm can run hyprland-dialog
// static void testAnrDialogs() {
//     NLog::log("{}Testing ANR dialogs", Colors::YELLOW);
//
//     OK(getFromSocket("/eval hl.config({ misc = { enable_anr_dialog = true } })"));
//     OK(getFromSocket("/eval hl.config({ misc = { anr_missed_pings = 1 } })"));
//
//     NLog::log("{}ANR dialog: regular workspaces", Colors::YELLOW);
//     {
//         OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '2' })"));
//
//         auto foot = Tests::spawnFoot("bad_foot");
//
//         if (!foot) {
//             ret = 1;
//             return;
//         }
//
//         {
//             auto str = getFromSocket("/activewindow");
//             ASSERT_CONTAINS(str, "workspace: 2");
//         }
//
//         OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));
//
//         ::kill(foot->pid(), SIGSTOP);
//         Tests::waitUntilWindowsN(2);
//
//         {
//             auto str = getFromSocket("/activeworkspace");
//             ASSERT_CONTAINS(str, "windows: 0");
//         }
//
//         {
//             OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:hyprland-dialog' })"))
//             auto str = getFromSocket("/activewindow");
//             ASSERT_CONTAINS(str, "workspace: 2");
//         }
//     }
//
//     Tests::killAllWindows();
//
//     NLog::log("{}ANR dialog: named workspaces", Colors::YELLOW);
//     {
//         OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 'name:yummy' })"));
//
//         auto foot = Tests::spawnFoot("bad_foot");
//
//         if (!foot) {
//             ret = 1;
//             return;
//         }
//
//         {
//             auto str = getFromSocket("/activewindow");
//             ASSERT_CONTAINS(str, "yummy");
//         }
//
//         OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));
//
//         ::kill(foot->pid(), SIGSTOP);
//         Tests::waitUntilWindowsN(2);
//
//         {
//             auto str = getFromSocket("/activeworkspace");
//             ASSERT_CONTAINS(str, "windows: 0");
//         }
//
//         {
//             OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:hyprland-dialog' })"))
//             auto str = getFromSocket("/activewindow");
//             ASSERT_CONTAINS(str, "yummy");
//         }
//     }
//
//     Tests::killAllWindows();
//
//     NLog::log("{}ANR dialog: special workspaces", Colors::YELLOW);
//     {
//         OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 'special:apple' })"));
//
//         auto foot = Tests::spawnFoot("bad_foot");
//
//         if (!foot) {
//             ret = 1;
//             return;
//         }
//
//         {
//             auto str = getFromSocket("/activewindow");
//             ASSERT_CONTAINS(str, "special:apple");
//         }
//
//         OK(getFromSocket("/dispatch hl.dsp.workspace.toggle_special('apple')"));
//         OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = '1' })"));
//
//         ::kill(foot->pid(), SIGSTOP);
//         Tests::waitUntilWindowsN(2);
//
//         {
//             auto str = getFromSocket("/activeworkspace");
//             ASSERT_CONTAINS(str, "windows: 0");
//         }
//
//         {
//             OK(getFromSocket("/dispatch hl.dsp.focus({ window = 'class:hyprland-dialog' })"))
//             auto str = getFromSocket("/activewindow");
//             ASSERT_CONTAINS(str, "special:apple");
//         }
//     }
//
//     OK(getFromSocket("/reload"));
//     Tests::killAllWindows();
// }

// TODO: decompose this into multiple test cases
TEST_CASE(misc) {
    NLog::log("{}Testing close_special_on_empty", Colors::YELLOW);

    OK(getFromSocket("/eval hl.config({ misc = { close_special_on_empty = false } })"));
    OK(getFromSocket("/dispatch hl.dsp.focus({ workspace = 'special:test' })"));

    SPAWN_FOOT("a");

    {
        auto str = getFromSocket("/monitors");
        ASSERT_CONTAINS(str, "special workspace: -");
    }

    Tests::killAllWindows();

    {
        auto str = getFromSocket("/monitors");
        ASSERT_CONTAINS(str, "special workspace: -");
    }

    SPAWN_FOOT("a");

    OK(getFromSocket("/eval hl.config({ misc = { close_special_on_empty = true } })"));

    Tests::killAllWindows();

    {
        auto str = getFromSocket("/monitors");
        ASSERT_NOT_CONTAINS(str, "special workspace: -");
    }
}

TEST_CASE(processesThatDieEarlyAreReaped) {
    // Ensure that the process autostarted in the config does not
    // become a zombie even if it terminates very quickly. Only the compositor's own children: any command line on the
    // machine with "sleep 0" in it (a script's "sleep 0.25") matched before
    ASSERT(Tests::execAndGet(std::format("ps -o stat=,comm= --ppid {} | awk '$1 ~ /^Z/ && $2 == \"sleep\"'", HYPRLAND_PID)).empty(), true);
}

TEST_CASE(xwaylandComesBackAfterItDies) {
    // an Xwayland that dies takes its windows along, and the next X11 client starts another one; with the compositor
    // holding copies of Xwayland's ends of its sockets neither happened
    getFromSocket("/dispatch hl.dsp.exec_cmd('xeyes')");
    Tests::waitUntilWindowsN(1);
    ASSERT(Tests::windowCount(), 1);

    const auto XWAYLAND = Tests::execAndGet(std::format("pgrep -P {} -x Xwayland | head -1", HYPRLAND_PID));
    ASSERT(XWAYLAND.empty(), false);
    Tests::execAndGet(std::format("kill -KILL {}", XWAYLAND));

    Tests::waitUntilWindowsN(0);
    ASSERT(Tests::windowCount(), 0);

    getFromSocket("/dispatch hl.dsp.exec_cmd('xeyes')");
    Tests::waitUntilWindowsN(1);
    ASSERT(Tests::windowCount(), 1);
    EXPECT_CONTAINS(getFromSocket("/clients"), "xwayland: 1");
    EXPECT(Tests::execAndGet(std::format("pgrep -P {} -x Xwayland | head -1", HYPRLAND_PID)) != XWAYLAND, true);

    Tests::killAllWindows();
    ASSERT(Tests::windowCount(), 0);
}
