# Opens Omarchy's terminal with its bind (SUPER+RETURN) on the empty workspace of the focused monitor and closes it again
# (SUPER+W), with a uinput keyboard, and measures how long each takes to show in the middle of the screen, with the parts
# in latency.py next to it. Needs root for /dev/uinput.
#
# launch.py --socket PATH [--steps N] [--timeout SECONDS]
# PATH is the compositor's hyprctl socket. A first open and close is not measured (the terminal's files come into the page
# cache), then N of each:
#   open     the key until the first frame that shows the middle of the screen changed (the window, or the first frame
#            of its animation)
#   opened   until the first frame after which the middle stays the same for half a second (the animation has ended and
#            the terminal has drawn)
#   close    SUPER+W until the first frame that shows the middle changed
#   closed   until it shows the wallpaper again and stays so
# Prints "latency <kind> <ms>" or "latency <kind> timeout" for every step, and the class of the terminal.
import argparse
import os
import random
import sys
import time

# python3 -I leaves the script's directory out of the path
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import latency  # noqa: E402
from latency import Keyboard, Region, Screencopy, Wayland, hyprctl  # noqa: E402

ANIMATION = 0.7  # seconds until Omarchy's window animations have ended, before the next step
SETTLE = 0.5  # seconds the region has to stay the same to count as drawn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    ap.add_argument("--steps", type=int, default=8)
    ap.add_argument("--timeout", type=float, default=10)
    args = ap.parse_args()
    # a terminal starts in well under a second on every machine, but the X200 takes longer than the 2 s of a key's step
    latency.TIMEOUT = args.timeout

    monitor = next(m for m in hyprctl(args.socket, "j/monitors") if m["focused"])
    workspace = monitor["activeWorkspace"]["id"]
    frame = 1 / (monitor.get("refreshRate") or 60)
    w, h = monitor["width"] / monitor["scale"], monitor["height"] / monitor["scale"]
    if monitor.get("transform", 0) % 2:
        w, h = h, w

    def windows():
        return [c for c in hyprctl(args.socket, "j/clients") if c["workspace"]["id"] == workspace and c["mapped"]]

    def wait_for(cond, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if cond():
                return True
            time.sleep(0.02)
        return False

    if windows():
        raise SystemExit(f"launch.py: workspace {workspace} is not empty")

    wl = Wayland()
    sc = Screencopy(wl, monitor["name"])
    # below the bar and away from the edges, where the pointer and the shell's layers are
    middle = Region(sc, (int(w / 4), int(h * 0.4), int(w / 2), max(int(h / 6), 16)))
    kb = Keyboard()
    rng = random.Random(1)
    named = []

    def report(kind, ns):
        print(f"latency {kind} {'timeout' if ns is None else f'{ns / 1e6:.1f}'}", flush=True)

    def step(measured):
        first, last = middle.follow(lambda: kb.chord("super+enter"), rng.uniform(0, frame), SETTLE)
        opened = wait_for(windows, args.timeout)
        if measured:
            report("open", first)
            report("opened", last if first is not None else None)
        if not opened:
            print("launch.py: no window opened", flush=True)
            return False
        if not named:
            named.append(windows()[0]["class"])
            print(f"terminal: {named[0]}", flush=True)
        # the shell in the terminal draws its prompt a moment after the window
        time.sleep(ANIMATION)
        first, last = middle.follow(lambda: kb.chord("super+w"), rng.uniform(0, frame), SETTLE)
        closed = wait_for(lambda: not windows(), 5)
        if measured:
            report("close", first)
            report("closed", last if first is not None else None)
        if not closed:
            print("launch.py: the window did not close", flush=True)
            return False
        time.sleep(ANIMATION)
        return True

    try:
        if step(False):
            for _ in range(args.steps):
                if not step(True):
                    break
    finally:
        kb.close()


main()
