# Switches between the windows of a workload and resizes them with a uinput keyboard and pointer, and measures how
# long each step takes to show on the screen, with the parts in latency.py next to it. Needs root for /dev/uinput.
#
# windows.py --socket PATH --classes LIST [--drag SECONDS] [--focus N] [--workspace N] [--bar N] [--resize N]
# PATH is the compositor's hyprctl socket, LIST the classes of the windows (comma separated), which are on the
# workspace of the focused monitor. In this order:
#   --drag       the load phase, which prints "load" when it starts: holds SUPER and the right button (Omarchy's
#                resize bind) on the left-most window and moves the pointer left and right for SECONDS, 125 times a
#                second like a mouse; the split between it and the window on its right follows
#   --focus      N moves of the focus to a neighbouring window with SUPER+arrow (Omarchy's binds), in a direction
#                picked at random among those that have one: the time until the border above the window that had
#                the focus changes
#   --workspace  N switches to workspace 2 and back (SUPER+2, SUPER+1): the time until the middle of a window changes
#   --bar        N of the same switches: the time until the first quarter of Omarchy's bar changes, where its workspace
#                widget is, redrawn by the shell after the compositor's event
#   --resize     N steps of the same drag, one pointer motion each: the time until the region across the split
#                changes ("resize", the compositor moved the windows) and until it shows what it then keeps showing
#                ("redrawn", both clients drew at their new size)
# Prints "latency <kind> <ms>" or "latency <kind> timeout" for every step it waits for.
import argparse
import math
import os
import random
import sys
import time

# python3 -I leaves the script's directory out of the path
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from latency import BTN_RIGHT, KEYS, Keyboard, Pointer, Region, Screencopy, Wayland, hyprctl, layer_box  # noqa: E402

ANIMATION = 0.7  # seconds until Omarchy's border animation (539 ms) has ended, before the next step
SETTLE = 0.5  # seconds a region has to stay the same to count as drawn
DRAG_HZ = 125  # the report rate of a mouse


def directions(box, others):
    """The arrow keys that lead from a window to a neighbour"""
    x, y, w, h = box
    found = set()
    for ox, oy, ow, oh in others:
        beside = oy < y + h and y < oy + oh
        above_below = ox < x + w and x < ox + ow
        if beside and ox + ow <= x:
            found.add("left")
        if beside and ox >= x + w:
            found.add("right")
        if above_below and oy + oh <= y:
            found.add("up")
        if above_below and oy >= y + h:
            found.add("down")
    return sorted(found)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    ap.add_argument("--classes", required=True)
    ap.add_argument("--drag", type=float, default=0)
    for a in ("focus", "workspace", "bar", "resize"):
        ap.add_argument("--" + a, type=int, default=0)
    args = ap.parse_args()

    classes = set(args.classes.split(","))
    monitors = hyprctl(args.socket, "j/monitors")
    monitor = next(m for m in monitors if m["focused"])
    workspace = monitor["activeWorkspace"]["id"]
    frame = 1 / (monitor.get("refreshRate") or 60)
    try:
        border = max(int(hyprctl(args.socket, "j/getoption general:border_size")["int"]), 1)
    except (ValueError, KeyError, TypeError):
        border = 2

    def windows():
        """The windows by address, left to right: their boxes in the output's logical coordinates"""
        found = {}
        for c in hyprctl(args.socket, "j/clients"):
            if c["class"] in classes and c["workspace"]["id"] == workspace and c["mapped"] and not c["hidden"]:
                found[c["address"]] = (c["at"][0] - monitor["x"], c["at"][1] - monitor["y"], c["size"][0], c["size"][1])
        return dict(sorted(found.items(), key=lambda item: item[1][:2]))

    wl = Wayland()
    sc = Screencopy(wl, monitor["name"])
    regions = {}

    def region(box):
        if box not in regions:
            regions[box] = Region(sc, box)
        return regions[box]

    def report(kind, ns):
        print(f"latency {kind} {'timeout' if ns is None else f'{ns / 1e6:.1f}'}", flush=True)

    def split():
        """Where to hold the left-most window to drag the split to its right, how far it may go, and the region across
        the split"""
        boxes = list(windows().values())
        if not boxes:
            raise SystemExit("windows.py: no windows of the classes " + args.classes)
        lx, ly, lw, lh = boxes[0]
        right = [b for b in boxes[1:] if b[0] >= lx + lw and b[1] < ly + lh and ly < b[1] + b[3]]
        if not right:
            raise SystemExit("windows.py: a resize needs two windows side by side")
        rx, _, rw, _ = right[0]
        # the region stays clear of the pointer: a cursor drawn into the frames would change it by itself
        hold = (monitor["x"] + lx + lw * 3 // 4, monitor["y"] + ly + lh * 3 // 4)
        left = lx + lw // 2
        return hold, min(lw, rw) // 4, (left, ly + lh // 4, rx + rw // 2 - left, max(lh // 6, 16))

    def grab(hold):
        ptr.move(*hold)
        # the focus follows the pointer, its border animates
        time.sleep(ANIMATION)
        kb.key(KEYS["super"], 1)
        time.sleep(0.02)
        ptr.button(BTN_RIGHT, 1)

    def release():
        ptr.button(BTN_RIGHT, 0)
        kb.key(KEYS["super"], 0)
        time.sleep(ANIMATION)

    def drag(seconds):
        hold, reach, _ = split()
        grab(hold)
        print("load", flush=True)
        try:
            start = time.monotonic()
            while (t := time.monotonic() - start) < seconds:
                ptr.move(hold[0] + reach * math.sin(math.pi * t), hold[1])
                time.sleep(1 / DRAG_HZ)
        finally:
            release()

    def focus(n):
        for _ in range(n):
            boxes = windows()
            active = hyprctl(args.socket, "j/activewindow").get("address")
            if active not in boxes:
                print("windows.py: the focus is not on one of the windows", flush=True)
                return
            keys = directions(boxes[active], [b for a, b in boxes.items() if a != active])
            if not keys:
                print("windows.py: the window with the focus has no neighbour", flush=True)
                return
            x, y, w, h = boxes[active]
            chord = "super+" + rng.choice(keys)
            report("focus", region((x + 8, y - border, w - 16, border)).until_changed(lambda: kb.chord(chord), rng.uniform(0, frame)))
            time.sleep(ANIMATION)

    def switch(n):
        x, y, w, h = next(iter(windows().values()))
        middle = region((x + w // 4, y + h // 3, w // 2, max(h // 6, 16)))
        for i in range(n):
            chord = "super+2" if i % 2 == 0 else "super+1"
            report("workspace", middle.until_changed(lambda: kb.chord(chord), rng.uniform(0, frame)))
            time.sleep(ANIMATION)
        if n % 2:
            kb.chord("super+1")
            time.sleep(ANIMATION)

    def bar(n):
        box = layer_box(args.socket, monitor, "omarchy-bar")
        if not box:
            print("windows.py: the shell has no bar on this monitor", flush=True)
            return
        x, y, w, h = box
        # the bar's window spans the screen since Omarchy r7338 (the strip is at its anchored edge, the rest is clear), so
        # the region is the strip's thickness at most, or the window animation under the clear part changes it first
        strip = region((x, y, w // 4, min(h, 40)) if w >= h else (x, y, min(w, 40), h // 4))
        for i in range(n):
            chord = "super+2" if i % 2 == 0 else "super+1"
            report("bar", strip.until_changed(lambda: kb.chord(chord), rng.uniform(0, frame)))
            time.sleep(ANIMATION)
        if n % 2:
            kb.chord("super+1")
            time.sleep(ANIMATION)

    def resize(n):
        hold, reach, box = split()
        step = max(reach // 3, 16)
        across = region(box)
        grab(hold)
        try:
            for i in range(n):
                x = hold[0] + (step if i % 2 == 0 else 0)
                first, last = across.follow(lambda: ptr.move(x, hold[1]), rng.uniform(0, frame), SETTLE)
                report("resize", first)
                report("redrawn", last)
        finally:
            release()

    kb = Keyboard()
    ptr = Pointer(monitors) if args.drag or args.resize else None
    rng = random.Random(1)
    try:
        if args.drag:
            drag(args.drag)
        print("latency phase", flush=True)
        if args.focus:
            focus(args.focus)
        if args.workspace:
            switch(args.workspace)
        if args.bar:
            bar(args.bar)
        if args.resize:
            resize(args.resize)
    finally:
        kb.close()
        if ptr:
            ptr.close()


main()
