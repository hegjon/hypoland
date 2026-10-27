#include "tests.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include <chrono>
#include <format>
#include <thread>
#include <hyprutils/os/Process.hpp>
#include <hyprutils/memory/WeakPtr.hpp>
#include "../shared.hpp"

using namespace Hyprutils::OS;
using namespace Hyprutils::Memory;

#define UP CUniquePointer
#define SP CSharedPointer

const static auto SLEEP_DURATIONS = std::array{1, 10};

TEST_CASE(processSpawning) {
    for (const auto duration : SLEEP_DURATIONS) {
        // Note: POSIX sleep does not support fractional seconds, so
        // can't sleep for less than 1 second.
        OK(getFromSocket(std::format("/dispatch hl.dsp.exec_cmd('sleep {}')", duration)));

        // Ensure that sleep is our child: the one under the compositor under test, not any sleep on the machine.
        // The compositor forks /bin/sh -c, which takes a moment to become sleep.
        std::string sleepPidS;
        for (int i = 0; i < 20 && sleepPidS.empty(); ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            sleepPidS = Tests::execAndGet(std::format("pgrep -x sleep -P {}", HYPRLAND_PID));
        }
        pid_t sleepPid;
        try {
            sleepPid = std::stoull(sleepPidS);
        } catch (...) {
            NLog::log("{}Sleep was not spawned or several sleeps are running: pgrep returned '{}'", Colors::RED, sleepPidS);
            continue;
        }

        const std::string sleepParentComm = Tests::execAndGet(std::format("cat \"/proc/$(ps -o ppid:1= -p {})/comm\"", sleepPidS));
        // the compositor's binary is hypoland, so that is its comm
        NLog::log("{}Expecting that sleep's parent is hypoland", Colors::YELLOW);
        EXPECT_CONTAINS(sleepParentComm, "hypoland");

        std::this_thread::sleep_for(std::chrono::seconds(duration));

        // Ensure that sleep did not become a zombie
        EXPECT(Tests::processAlive(sleepPid), false);

        // Test succeeded
        return;
    }

    FAIL_TEST_SILENT();
}
