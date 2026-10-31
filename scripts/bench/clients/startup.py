# Stops SDDM and starts it again, which logs in again, and follows the start of the new session from the moment its
# compositor process starts: when its IPC socket answers, when it puts its first frame on the screen, when the shell's
# wallpaper and bar layers are there and its startup cover is gone (desktop), and the CPU time the compositor and the
# whole session (uwsm's wayland-wm service: the compositor, the shell, Xwayland) have used after SECONDS. Needs root
# (systemctl, perf).
#
# startup.py --process NAME --runtime DIR [--seconds N] [--timeout N] [--perf FILE]
# Prints "pid <pid>" and "startup <key> <value>", the value "timeout" for what did not happen within --timeout seconds.
# Times are milliseconds after the compositor process started (its start time in /proc, 10 ms steps), on the boot clock;
# exec_ms is the time from SDDM's start until then (its autologin and uwsm), the same for any compositor. The old session
# is gone before SDDM starts again, as the night runner (abnight.sh) does it: a plain `systemctl restart sddm` under
# Hyprland 0.57.0, whose session did not end on SIGTERM in time, had systemd kill SDDM, and the new autologin failed
# while the old session still held the VT ("Failed to take control of /dev/tty1"), leaving SDDM's greeter.
import argparse
import glob
import os
import pwd
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
    users = set()
    for p in old:
        try:
            users.add(pwd.getpwuid(os.stat(f"/proc/{p}").st_uid).pw_name)
        except (OSError, KeyError):
            pass
    subprocess.run(["systemctl", "stop", "sddm"], timeout=args.timeout + 30, check=False)
    if poll(lambda: not (pids(args.process) & old), 20, 0.2) is None:
        print("startup.py: the old compositor was still running 20 s after SDDM stopped", flush=True)
    for user in users:
        subprocess.run(["systemctl", "--user", "-M", f"{user}@", "stop", "graphical-session.target",
                        "graphical-session-pre.target"], timeout=30, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    restart = boot()
    subprocess.run(["systemctl", "start", "sddm"], timeout=args.timeout, check=False)
    # the compositor is the new process of that name that holds an instance lock file (its pid on the first line, the
    # Wayland socket next to it): stock Hyprland 0.57.0 starts a short-lived process of the same name before it
    def instance():
        new = pids(args.process) - old
        for lock in glob.glob(f"{args.runtime}/hypr/*/hyprland.lock"):
            with open(lock) as f:
                first = f.readline().strip()
            if first.isdigit() and int(first) in new:
                return int(first), os.path.join(os.path.dirname(lock), ".socket.sock")
        return None

    found = poll(instance, args.timeout)
    if found is None:
        out("exec_ms", "timeout")
        if perf:
            perf.send_signal(signal.SIGINT)
            perf.wait()
        return
    pid, sock = found
    print(f"pid {pid}", flush=True)
    start = int(stat(pid)[19]) * 1_000_000_000 // TICK
    out("exec_ms", f"{(start - restart) / 1e6:.0f}")

    def since(t):
        return f"{(t - start) / 1e6:.0f}"

    answers = poll(lambda: hyprctl(sock, "j/version") and boot(), args.timeout)
    out("ipc_ms", since(answers) if answers else "timeout")

    # Omarchy's shell (r7438 on) keeps a cover over the screen after the login, an overlay layer with the wallpaper's
    # namespace, until its background is ready: the wallpaper is that namespace on the background level only, and the
    # desktop is there when the cover is gone and the wallpaper and the bar are up, for a second without a cover coming
    seen = {}
    if answers:
        def layers():
            found = set()
            for monitor in hyprctl(sock, "j/layers").values():
                for level, items in monitor.get("levels", {}).items():
                    found.update((str(level), layer.get("namespace")) for layer in items)
            t = boot()
            if ("0", "omarchy-background") in found:
                seen.setdefault("wallpaper", t)
            if any(namespace == "omarchy-bar" for _, namespace in found):
                seen.setdefault("bar", t)
            cover = ("3", "omarchy-background") in found
            if cover:
                seen.setdefault("cover", t)
            if "wallpaper" in seen and "bar" in seen and not cover:
                seen.setdefault("desktop", t)
            else:
                seen.pop("desktop", None)
            return "desktop" in seen and t - seen["desktop"] >= 1_000_000_000

        poll(layers, max(args.timeout - (boot() - start) / 1e9, 1), 0.02)
    for key in ("wallpaper", "bar", "desktop"):
        out(f"{key}_ms", since(seen[key]) if key in seen else "timeout")
    if "cover" in seen:
        out("cover_ms", since(seen["cover"]))

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
