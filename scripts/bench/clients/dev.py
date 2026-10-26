# Drives the developer's screen with a uinput keyboard and measures how long a key takes to show on the screen, with
# the parts in latency.py next to it. Needs root for /dev/uinput.
#
# dev.py --clients FILE --monitors FILE --editor CLASS --console CLASS --border N --load SECONDS --cycles N --quiet FILE
# FILEs are the JSON of hyprctl clients -j and monitors -j. The console has the focus at the start and the editor is
# left of it.
# The load phase (prints "load" when it starts) moves between the editor, which scrolls by itself while it has the
# focus, and the console, which gets a command typed, every 3 s. The latency phase creates the quiet file, which stops
# the editor's scrolling, and then waits for every key until a small region of the output changes, captured with
# wlr-screencopy: moving to the editor (SUPER+Left), scrolling (Ctrl-D, Ctrl-U), jumping to a line (<line>G), back to
# the console (SUPER+Right) and typing a command. Prints "latency <kind> <ms>" or "latency <kind> timeout" for every
# key it waits for.
import argparse
import json
import os
import random
import sys
import time

# python3 -I leaves the script's directory out of the path
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from latency import Keyboard, Region, Screencopy, Wayland, chord_of  # noqa: E402


# letters and spaces only, other characters sit on different keys in different layouts. git diff pages for 2 s
LOAD_COMMANDS = ("ls", "git diff", "git status", "git diff", "git show", "git diff")
COMMANDS = ("git status", "ls", "git log", "git diff")


def main():
    ap = argparse.ArgumentParser()
    for a in ("clients", "monitors", "editor", "console", "quiet"):
        ap.add_argument("--" + a, required=True)
    ap.add_argument("--border", type=int, default=2)
    ap.add_argument("--load", type=float, default=12)
    ap.add_argument("--cycles", type=int, default=6)
    args = ap.parse_args()

    monitor = next(m for m in json.load(open(args.monitors)) if m["focused"])
    frame = 1 / (monitor.get("refreshRate") or 60)
    boxes = {}
    for c in json.load(open(args.clients)):
        if c["class"] in (args.editor, args.console):
            boxes[c["class"]] = (c["at"][0] - monitor["x"], c["at"][1] - monitor["y"], c["size"][0], c["size"][1])
    ex, ey, ew, eh = boxes[args.editor]
    cx, cy, cw, ch = boxes[args.console]
    b = max(args.border, 1)

    wl = Wayland()
    sc = Screencopy(wl, monitor["name"])
    # the border above a window changes color with the focus, the text inside with a key. The console is cleared
    # before a command is typed, which keeps the prompt at the top
    editor_border = Region(sc, (ex + 8, ey - b, ew - 16, b))
    console_border = Region(sc, (cx + 8, cy - b, cw - 16, b))
    editor_text = Region(sc, (ex + ew // 4, ey + eh // 8, ew // 2, eh // 6))
    console_text = Region(sc, (cx + 4, cy + 4, cw - 8, max(ch // 8, 32)))

    kb = Keyboard()
    rng = random.Random(1)

    def typed(text, pause=0.06):
        for c in text:
            kb.chord(chord_of(c))
            time.sleep(pause)

    def probe(kind, region, chord):
        ns = region.until_changed(lambda: kb.chord(chord), rng.uniform(0, frame))
        print(f"latency {kind} {'timeout' if ns is None else f'{ns / 1e6:.1f}'}", flush=True)

    try:
        print("load", flush=True)
        end = time.monotonic() + args.load + 1
        turn = 0
        while time.monotonic() < end:
            kb.chord("super+left")
            time.sleep(3)
            kb.chord("super+right")
            console = time.monotonic()
            time.sleep(0.3)
            typed(LOAD_COMMANDS[turn % len(LOAD_COMMANDS)] + "\n")
            turn += 1
            time.sleep(max(console + 3 - time.monotonic(), 0))

        open(args.quiet, "w").close()
        print("latency phase", flush=True)
        time.sleep(2.5)
        for cycle in range(args.cycles):
            probe("focus", editor_border, "super+left")
            probe("scroll", editor_text, "ctrl+d")
            probe("scroll", editor_text, "ctrl+d")
            probe("scroll", editor_text, "ctrl+u")
            for jump in range(2):
                typed(str(1000 + (2 * cycle + jump) * 7919 * 13 % 150000))
                probe("jump", editor_text, "shift+g")
            probe("focus", console_border, "super+right")
            kb.chord("ctrl+l")
            for c in COMMANDS[cycle % len(COMMANDS)]:
                probe("type", console_text, chord_of(c))
            kb.chord("enter")
            time.sleep(1)
    finally:
        kb.close()


main()
