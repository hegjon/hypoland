# Restarts SDDM, which logs in again, and follows the start of the new session from the moment its compositor process
# starts: when its IPC socket answers, when it puts its first frame on the screen, when the shell's wallpaper and bar
# layers are there, and the CPU time the compositor and the whole session (uwsm's wayland-wm service: the compositor, the
# shell, Xwayland) have used after SECONDS. Needs root (systemctl, perf).
#
# startup.py --process NAME --runtime DIR [--seconds N] [--timeout N] [--perf FILE]
# Prints "pid <pid>" and "startup <key> <value>", the value "timeout" for what did not happen within --timeout seconds.
# Times are milliseconds after the compositor process started (its start time in /proc, 10 ms steps), on the boot clock;
# exec_ms is the time from the restart until then (the old session ending, SDDM's autologin, uwsm), the same for any
# compositor.
import argparse
import glob
import os
import shutil
import signal
import subprocess
import sys
import time

# python3 -I leaves the script's directory out of the path
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from latency import hyprctl  # noqa: E402

TICK = os.sysconf("SC_CLK_TCK")
FLIP_EVENT = "drm:drm_vblank_event_delivered"
LAYERS = {"wallpaper": "omarchy-background", "bar": "omarchy-bar"}


def boot():
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME)


def stat(pid):
    """The fields of /proc/<pid>/stat after the command name, so field n of proc(5) is index n - 3"""
    with open(f"/proc/{pid}/stat") as f:
        return f.read().rsplit(")", 1)[1].split()


def pids(name):
    found = set()
    for comm in glob.glob("/proc/[0-9]*/comm"):
        try:
            with open(comm) as f:
                if f.read().strip() == name:
                    found.add(int(comm.split("/")[2]))
        except OSError:
            pass
    return found


def poll(cond, timeout, step=0.01):
    """Calls cond until it returns something, returns that or None after timeout seconds"""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            v = cond()
        except (OSError, ValueError):
            v = None
        if v:
            return v
        time.sleep(step)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--process", required=True)
    ap.add_argument("--runtime", required=True)
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--timeout", type=float, default=60)
    ap.add_argument("--perf", default="")
    args = ap.parse_args()

    def out(key, value):
        print(f"startup {key} {value}", flush=True)

    perf = None
    if args.perf and shutil.which("perf"):
        perf = subprocess.Popen(["perf", "record", "-q", "-a", "-k", "monotonic", "-e", FLIP_EVENT, "-o", args.perf],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)
        if perf.poll() is not None:
            perf = None

    old = pids(args.process)
    restart = boot()
    subprocess.run(["systemctl", "restart", "sddm"], timeout=args.timeout, check=False)
    pid = poll(lambda: min(pids(args.process) - old, default=None), args.timeout)
    if pid is None:
        out("exec_ms", "timeout")
        if perf:
            perf.send_signal(signal.SIGINT)
            perf.wait()
        return
    print(f"pid {pid}", flush=True)
    start = int(stat(pid)[19]) * 1_000_000_000 // TICK
    out("exec_ms", f"{(start - restart) / 1e6:.0f}")

    def since(t):
        return f"{(t - start) / 1e6:.0f}"

    # every instance writes its pid and its Wayland socket into a lock file
    def instance():
        for lock in glob.glob(f"{args.runtime}/hypr/*/hyprland.lock"):
            with open(lock) as f:
                if f.readline().strip() == str(pid):
                    return os.path.join(os.path.dirname(lock), ".socket.sock")
        return None

    sock = poll(instance, args.timeout)
    answers = sock and poll(lambda: hyprctl(sock, "j/version") and boot(), args.timeout)
    out("ipc_ms", since(answers) if answers else "timeout")

    seen = {}
    if answers:
        def layers():
            found = set()
            for monitor in hyprctl(sock, "j/layers").values():
                for level in monitor.get("levels", {}).values():
                    found.update(layer.get("namespace") for layer in level)
            t = boot()
            for key, namespace in LAYERS.items():
                if namespace in found and key not in seen:
                    seen[key] = t
            return len(seen) == len(LAYERS)

        poll(layers, max(args.timeout - (boot() - start) / 1e9, 1), 0.02)
    for key in LAYERS:
        out(f"{key}_ms", since(seen[key]) if key in seen else "timeout")

    # the cost of the start: the compositor's CPU time with its ended threads, and that of uwsm's service, which holds the
    # compositor, the shell and Xwayland
    left = start + int(args.seconds * 1e9) - boot()
    if left > 0:
        time.sleep(left / 1e9)
    try:
        fields = stat(pid)
        out("cpu_ms", f"{(int(fields[11]) + int(fields[12])) * 1000 / TICK:.0f}")
        with open(f"/proc/{pid}/cgroup") as f:
            cgroup = "/sys/fs/cgroup" + f.read().split("::", 1)[1].strip()
        with open(f"{cgroup}/cpu.stat") as f:
            usage = next(int(line.split()[1]) for line in f if line.startswith("usage_usec"))
        out("session_cpu_ms", f"{usage / 1000:.0f}")
    except (OSError, StopIteration, IndexError):
        print("startup.py: the compositor ended before the end of the window", flush=True)

    if perf:
        perf.send_signal(signal.SIGINT)
        perf.wait()
        script = subprocess.run(["perf", "script", "--ns", "-F", "time", "-i", args.perf],
                                capture_output=True, text=True, check=False).stdout
        flips = sorted(int(float(t.strip().rstrip(":")) * 1e9) for t in script.split() if t.strip().rstrip(":"))
        # perf stamps with the monotonic clock (it has no boot clock), which stands still while the machine sleeps
        offset = boot() - time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        flips = [t + offset for t in flips]
        flips = [t for t in flips if start <= t <= start + args.seconds * 1e9]
        out("first_frame_ms", since(flips[0]) if flips else "timeout")
        out("frames", len(flips))


main()
