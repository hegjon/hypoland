#if !defined(__OpenBSD__)
#include <linux/capability.h>
#include <sys/prctl.h>
#endif

#include "initHelpers.hpp"
#include "../helpers/env/Env.hpp"

#include <atomic>

#ifdef HAS_RTKIT
#include <pthread.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <format>
#include <print>
#include <thread>

#include <sdbus-c++/sdbus-c++.h>
#include <hyprutils/memory/Casts.hpp>
#endif

bool NInit::isSudo() {
    return getuid() != geteuid() || !geteuid();
}

#if !defined(__OpenBSD__)
// NixOS-specific fix to prevent all children from inheriting
// CAP_SYS_NICE due to how the security wrapper works.
void NInit::lowerAmbientCaps() {
    prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_LOWER, CAP_SYS_NICE, 0, 0);
}
#endif

// Asks the kernel directly to put the calling thread on SCHED_RR. Only succeeds if
// the process is privileged to go realtime on its own: CAP_SYS_NICE (e.g. granted via
// setcap or a security wrapper) or a nonzero RLIMIT_RTPRIO (e.g. a "realtime" group
// entry in limits.conf).
static bool trySchedDirect(int prio) {
#ifdef HAS_RTKIT
    // SCHED_RESET_ON_FORK keeps children from inheriting realtime, the same kernel mechanism
    // rtkit's grants use. Raw syscall because not every libc exposes the per-thread Linux
    // semantics of sched_setscheduler (musl returns ENOSYS).
    const struct sched_param param = {.sched_priority = prio};
    return syscall(SYS_sched_setscheduler, gettid(), SCHED_RR | SCHED_RESET_ON_FORK, &param) == 0;
#else
    int                oldPolicy = 0;
    struct sched_param param     = {};

    if (pthread_getschedparam(pthread_self(), &oldPolicy, &param)) {
        Log::logger->log(Log::WARN, "Failed to get old pthread scheduling priority");
        return false;
    }

    param.sched_priority = prio;

    return pthread_setschedparam(pthread_self(), SCHED_RR, &param) == 0;
#endif
}

#ifdef HAS_RTKIT

// the realtime guard waits for the event loop's next round, see guardRealtime()
static std::atomic<bool> s_guardParked{false};

// Cached for the SIGXCPU handler: it must demote the RT thread specifically, but a
// process-directed signal can be delivered to any thread.
static pid_t mainThreadTid = 0;

// whether the main thread runs on SCHED_RR now, for the realtime guard
static std::atomic<bool> s_realtime{false};

// realtime was granted with SCHED_RESET_ON_FORK set (on both paths), keep it as clearing it
// needs CAP_SYS_NICE and the kernel rejects the whole call with EPERM otherwise.
// Async-signal-safe, the SIGXCPU handler calls it.
static bool dropRealtime() {
    const struct sched_param param = {.sched_priority = 0};
    if (syscall(SYS_sched_setscheduler, mainThreadTid, SCHED_OTHER | SCHED_RESET_ON_FORK, &param) != 0)
        return false;
    s_realtime = false;
    return true;
}

// Demotes the main thread back to SCHED_OTHER instead of letting the process die. With a finite
// RLIMIT_RTTIME, an RT thread that overruns the soft limit without making a blocking syscall gets
// SIGXCPU (fatal by default), then SIGKILL at the hard limit. The counter resets every time the
// thread blocks (i.e. every frame), so this only fires on a genuinely runaway compositor.
// Only async-signal-safe calls in here: raw syscalls and write().
static void handleSigxcpu(int /* signo */) {
    const int savedErrno = errno;

    if (dropRealtime()) {
        constexpr char MSG[] = "Realtime budget exceeded (SIGXCPU), dropping realtime scheduling\n";
        std::ignore          = write(STDERR_FILENO, MSG, sizeof(MSG) - 1);
    } else {
        constexpr char MSG[] = "Realtime budget exceeded (SIGXCPU), failed to drop realtime scheduling\n";
        std::ignore          = write(STDERR_FILENO, MSG, sizeof(MSG) - 1);
    }

    errno = savedErrno;
}

// Installs handleSigxcpu. Must happen before the thread can go realtime, and stays installed for
// the lifetime of the process: SIGXCPU is not delivered to well-behaved non-realtime processes.
static bool installSigxcpuHandler() {
    mainThreadTid = gettid();

    struct sigaction action = {};
    sigemptyset(&action.sa_mask);
    action.sa_flags   = SA_RESTART;
    action.sa_handler = handleSigxcpu;

    if (sigaction(SIGXCPU, &action, nullptr)) {
        Log::logger->log(Log::WARN, "Failed to install the SIGXCPU handler: {}, not attempting realtime", strerror(errno));
        return false;
    }

    return true;
}

constexpr const char* RTKIT_SERVICE      = "org.freedesktop.RealtimeKit1";
constexpr const char* RTKIT_OBJECT       = "/org/freedesktop/RealtimeKit1";
constexpr const char* RTKIT_INTERFACE    = "org.freedesktop.RealtimeKit1";
constexpr auto        RTKIT_DBUS_TIMEOUT = std::chrono::seconds(2); // D-Bus defaults to 25s, a wedged rtkit must not stall startup

// Asks rtkit (org.freedesktop.RealtimeKit1 on the system bus) to put the calling thread on
// SCHED_RR. rtkit hands out realtime scheduling to unprivileged processes, mediated by polkit
// (granted to active sessions only). It addresses threads by kernel tid (gettid), not pthread_t,
// and grants SCHED_RR with SCHED_RESET_ON_FORK set, so fork children reset to SCHED_OTHER
// kernel-side.
// quiet when the realtime guard asks again from its own thread, the logger is the main thread's
static bool tryRtkit(pid_t tid, int prio, bool quiet = false) {
    try {
        auto connection = sdbus::createSystemBusConnection();
        auto proxy      = sdbus::createProxy(*connection, sdbus::ServiceName{RTKIT_SERVICE}, sdbus::ObjectPath{RTKIT_OBJECT});

        // read RTTimeUSecMax, the largest RLIMIT_RTTIME rtkit grants under.
        // Also probes rtkit's liveness before touching RLIMIT_RTTIME: lowering
        // the hard limit must not happen unless rtkit is actually there to
        // grant us realtime in exchange
        sdbus::Variant maxVar;
        proxy->callMethod("Get")
            .onInterface("org.freedesktop.DBus.Properties")
            .withTimeout(RTKIT_DBUS_TIMEOUT)
            .withArguments(RTKIT_INTERFACE, "RTTimeUSecMax")
            .storeResultsTo(maxVar);

        const auto maxUs = maxVar.get<int64_t>();
        if (maxUs <= 0) {
            if (!quiet)
                Log::logger->log(Log::DEBUG, "rtkit: no usable RTTimeUSecMax, not requesting realtime");
            return false;
        }

        // rtkit refuses to grant realtime unless the caller has a finite RLIMIT_RTTIME at or
        // below its RTTimeUSecMax. Lowering the hard limit is irreversible without
        // CAP_SYS_RESOURCE and the new limit is inherited by forked children: apps launched from
        // Hyprland that gain realtime through their own privileges will live under this budget
        // too.
        rlimit current = {};
        if (getrlimit(RLIMIT_RTTIME, &current)) {
            if (!quiet)
                Log::logger->log(Log::WARN, "rtkit: failed to get RLIMIT_RTTIME: {}", strerror(errno));
            return false;
        }

        // an unprivileged process cannot raise a finite hard limit, so stay under a pre-existing
        // one (RLIM_INFINITY compares greater than any finite limit). Keep soft below hard: an
        // overrun then raises a catchable SIGXCPU (which our handler turns into a demotion)
        // before the uncatchable SIGKILL at the hard limit.
        const rlim_t hard     = std::min(current.rlim_max, sc<rlim_t>(maxUs));
        const rlimit newLimit = {.rlim_cur = std::min(hard / 4 * 3, current.rlim_cur), .rlim_max = hard};

        if (setrlimit(RLIMIT_RTTIME, &newLimit)) {
            if (!quiet)
                Log::logger->log(Log::WARN, "rtkit: failed to set RLIMIT_RTTIME: {}", strerror(errno));
            return false;
        }

        // fails with a polkit denial for sessions that aren't active locally (e.g. ssh),
        // which is fine because realtime is best-effort. the armed RLIMIT_RTTIME must stay,
        // hard limits cannot be raised back.
        proxy->callMethod("MakeThreadRealtime").onInterface(RTKIT_INTERFACE).withTimeout(RTKIT_DBUS_TIMEOUT).withArguments(sc<uint64_t>(tid), sc<uint32_t>(prio));

        return true;
    } catch (const sdbus::Error& e) {
        if (!quiet)
            Log::logger->log(Log::DEBUG, "rtkit: {}", e.what());
        return false;
    }
}

// The realtime guard (2026-10-31). rtkit grants realtime only under RLIMIT_RTTIME, and the kernel compares the time a
// realtime thread ran without sleeping with it when the thread returns to user space: a kernel call that runs from below
// the soft limit past the hard one (200 ms on Arch) gets the compositor SIGKILLed, with no SIGXCPU before it and nothing
// in any log, and the session is gone. That happened in 3 of 8 sessions on a Dell XPS 13 one morning, and a single long
// read through `hyprctl eval` does it every time. This thread polls every 40 ms: when the event loop has not gone round
// since the last poll, it reads the main thread's state, and when that was running at two polls in a row (80 to 120 ms
// in one go) it takes realtime away, which stops the kernel's count also in the middle of such a call. It asks rtkit for
// realtime again when the main thread has slept for a while, and waits on the loop's next round while the main thread
// sleeps in the loop's epoll (not when it sleeps in a round: the same round can go on into a long call). The loop itself
// only counts its rounds: telling the guard when the thread really slept cost a poll() per round,
// and with it and a poll every 20 ms the compositor took 1 to 7% more CPU.
static std::atomic<uint64_t> s_loopRounds{0};

// the main thread's state letter from /proc (R running or runnable, S or D asleep), 0 when it cannot be read
static char threadState(int fd) {
    char       buf[512];
    const auto N = pread(fd, buf, sizeof(buf) - 1, 0);
    if (N <= 0)
        return 0;
    buf[N]            = 0;
    const char* PAREN = strrchr(buf, ')');
    return PAREN && PAREN[1] == ' ' ? PAREN[2] : 0;
}

// whether the main thread sleeps in the event loop's epoll, between rounds, and not somewhere in a round (a GPU fence)
static bool inLoopPoll(int fd) {
    char       buf[128];
    const auto N = pread(fd, buf, sizeof(buf) - 1, 0);
    if (N <= 0)
        return false;
    buf[N]          = 0;
    const long CALL = strtol(buf, nullptr, 10);
#ifdef SYS_epoll_wait
    if (CALL == SYS_epoll_wait)
        return true;
#endif
#ifdef SYS_epoll_pwait2
    if (CALL == SYS_epoll_pwait2)
        return true;
#endif
    return CALL == SYS_epoll_pwait;
}

static void guardRealtime(int prio) {
    pthread_setname_np(pthread_self(), "rtguard");

    const int STATFD    = open(std::format("/proc/self/task/{}/stat", mainThreadTid).c_str(), O_RDONLY | O_CLOEXEC);
    const int SYSCALLFD = open(std::format("/proc/self/task/{}/syscall", mainThreadTid).c_str(), O_RDONLY | O_CLOEXEC);
    if (STATFD < 0 || SYSCALLFD < 0)
        return;

    constexpr auto POLL       = std::chrono::milliseconds(40);
    uint64_t       lastRounds = s_loopRounds.load();
    int            busyPolls  = 0; // running in the same round of the loop at polls in a row
    int            idlePolls  = 0; // asleep in the loop's epoll in the same round
    int            demoted    = 0; // polls since realtime was lost
    int            retryPolls = 50;

    for (;;) {
        std::this_thread::sleep_for(POLL);

        const uint64_t ROUNDS = s_loopRounds.load(std::memory_order_relaxed);
        if (ROUNDS != lastRounds) {
            lastRounds = ROUNDS;
            busyPolls = idlePolls = 0;
        } else if (threadState(STATFD) == 'R') {
            busyPolls++;
            idlePolls = 0;
        } else {
            // asleep: the kernel's count starts over. Between rounds the guard can wait for the next one
            busyPolls = 0;
            idlePolls = inLoopPoll(SYSCALLFD) ? idlePolls + 1 : 0;
        }

        if (s_realtime && busyPolls >= 2) {
            if (dropRealtime())
                std::println(stderr, "Realtime: the main thread did not sleep for 80 ms, dropping realtime scheduling");
            busyPolls = 0;
        }

        if (!s_realtime) {
            // back to realtime once the main thread has slept through a few polls, at most every retryPolls polls
            if (++demoted >= retryPolls && idlePolls >= 3) {
                demoted = 0;
                if (tryRtkit(mainThreadTid, prio, true)) {
                    s_realtime = true;
                    retryPolls = 50;
                    std::println(stderr, "Realtime: realtime scheduling again");
                } else
                    retryPolls = std::min(retryPolls * 2, 1500); // rtkit said no: 2 s, 4 s, ... up to a minute
            } else if (idlePolls >= 25) {
                // nothing to watch until the next attempt
                std::this_thread::sleep_for(POLL * std::max(retryPolls - demoted, 0));
                demoted = retryPolls;
            }
            continue;
        }

        // asleep in the loop's epoll: wait for its next round instead of polling (an idle session wakes a few times a second)
        if (idlePolls >= 1) {
            s_guardParked = true;
            s_loopRounds.wait(ROUNDS);
            s_guardParked = false;
            lastRounds    = s_loopRounds.load();
            idlePolls     = 0;
        }
    }
}

#endif

void NInit::loopRound() {
#ifdef HAS_RTKIT
    // sequentially consistent against the guard's store of s_guardParked and its wait, or a round could go unnoticed by a
    // parked guard (an atomic add is a full barrier on x86 anyway)
    s_loopRounds.fetch_add(1);
    if (s_guardParked.load())
        s_loopRounds.notify_one();
#endif
}

// Puts the main thread on SCHED_RR so a busy session cannot starve the compositor of CPU.
// Going realtime directly needs privilege and is tried first, rtkit is the standard
// unprivileged fallback on desktop systems. Best-effort: on failure we just run as SCHED_OTHER.
void NInit::gainRealTime() {
    const int minPrio = sched_get_priority_min(SCHED_RR);
    bool      gained  = false;

#ifdef HAS_RTKIT
    if (!installSigxcpuHandler())
        return;
#endif

    gained = trySchedDirect(minPrio);
    if (gained)
        Log::logger->log(Log::DEBUG, "Gained realtime scheduling directly");

#ifdef HAS_RTKIT
    if (!gained && (gained = tryRtkit(gettid(), minPrio))) {
        Log::logger->log(Log::DEBUG, "Gained realtime scheduling via rtkit");
        s_realtime = true;
        // HYPOLAND_NO_RT_GUARD=1: realtime without the guard, for measuring what the guard costs
        if (!Env::envEnabled("HYPOLAND_NO_RT_GUARD"))
            std::thread(guardRealtime, minPrio).detach();
    }
#endif

    if (!gained) {
        Log::logger->log(Log::WARN, "Failed to gain realtime scheduling");
        return;
    }

#ifndef HAS_RTKIT
    // spawned children must not inherit RT, on Linux the kernel handles this via
    // SCHED_RESET_ON_FORK on both promotion paths
    pthread_atfork(nullptr, nullptr, []() {
        const struct sched_param param = {.sched_priority = 0};
        if (pthread_setschedparam(pthread_self(), SCHED_OTHER, &param))
            Log::logger->log(Log::WARN, "Failed to reset process scheduling strategy");
    });
#endif
}
