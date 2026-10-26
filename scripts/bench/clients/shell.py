# Omarchy's shell driven as a person does and timed until the screen shows its reaction, with the parts in latency.py
# and sessionbus.py next to it: the menu by a uinput keyboard (root), a notification over the session bus (as the
# user, whose bus refuses root).
#
# shell.py --socket PATH [--menu N] [--search N] [--select N] [--toast N]
# PATH is the compositor's hyprctl socket. In this order:
#   --menu    N opens and closes of the menu: SUPER+SPACE until a strip at the left of the focused monitor changes
#             (the menu's scrim darkens the whole screen, its card sits in the middle, clear of the strip), a second
#             later Escape until the strip changes again (the scrim is gone)
#   --search  with the menu open, N letters typed into its search line until the rows of the card change, each
#             cleared with Escape before the next; a last Escape closes the menu
#   --select  with the menu open and its selection moved into the middle rows, N presses of Down and Up in turns until
#             the middle rows change (the selected row moves); Escape closes the menu
#   --toast   N notifications sent over the session bus (what notify-send does) until the top of the shell's
#             notification column changes, each closed again through the bus
# Prints "latency <kind> <ms>" or "latency <kind> timeout" for every step: open, close, search, select, toast.
import argparse
import os
import random
import sys
import time

# python3 -I leaves the script's directory out of the path
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from latency import Keyboard, Region, Screencopy, Wayland, hyprctl, layer_box  # noqa: E402
from sessionbus import SessionBus  # noqa: E402

LINGER = 1.0  # seconds the menu stays open
ANIMATION = 0.7  # seconds until Omarchy's border animation (539 ms) of the window that gets the focus back has ended
GONE = 1.2  # seconds until a closed notification has faded and the column settled


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    for a in ("menu", "search", "select", "toast"):
        ap.add_argument("--" + a, type=int, default=0)
    args = ap.parse_args()

    monitor = next(m for m in hyprctl(args.socket, "j/monitors") if m["focused"])
    frame = 1 / (monitor.get("refreshRate") or 60)
    w, h = (monitor["height"], monitor["width"]) if monitor.get("transform", 0) % 2 else (monitor["width"], monitor["height"])
    w, h = int(w / monitor["scale"]), int(h / monitor["scale"])

    wl = Wayland()
    sc = Screencopy(wl, monitor["name"])
    # a strip at the left of the screen, half way down: under the scrim, clear of the card, the bar, the dock and the
    # notification column, and inside the window that is open
    strip = Region(sc, (24, h // 2 - h // 12, max(w // 6, 32), max(h // 6, 16)))
    # the rows of the menu's card, which is centered: below its search line, which blinks its cursor
    rows = Region(sc, (w // 2 - w // 8, h // 2, max(w // 4, 32), max(h // 8, 16)))
    # the middle rows of the card, around the middle of the screen, where the selection is moved for --select
    middle = Region(sc, (w // 2 - w // 8, 3 * h // 8, max(w // 4, 32), max(h // 4, 16)))
    rng = random.Random(1)
    kb = Keyboard() if args.menu or args.search else None

    def report(kind, ns):
        print(f"latency {kind} {'timeout' if ns is None else f'{ns / 1e6:.1f}'}", flush=True)

    def open_menu():
        return strip.until_changed(lambda: kb.chord("super+space"), rng.uniform(0, frame))

    def menu(n):
        for _ in range(n):
            report("open", open_menu())
            time.sleep(LINGER)
            report("close", strip.until_changed(lambda: kb.chord("esc"), rng.uniform(0, frame)))
            time.sleep(ANIMATION)

    def search(n):
        if open_menu() is None:
            print("shell.py: the menu did not open for the search", flush=True)
            return
        time.sleep(LINGER)
        for i in range(n):
            letter = "tsane"[i % 5]
            report("search", rows.until_changed(lambda: kb.chord(letter), rng.uniform(0, frame)))
            time.sleep(0.5)
            kb.chord("esc")  # clears the search line
            time.sleep(0.5)
        kb.chord("esc")
        time.sleep(ANIMATION)

    def select(n):
        if open_menu() is None:
            print("shell.py: the menu did not open for the selection", flush=True)
            return
        time.sleep(LINGER)
        for _ in range(5):
            kb.chord("down")
            time.sleep(0.15)
        time.sleep(0.5)
        for i in range(n):
            key = "down" if i % 2 == 0 else "up"
            report("select", middle.until_changed(lambda: kb.chord(key), rng.uniform(0, frame)))
            time.sleep(0.5)
        kb.chord("esc")
        time.sleep(ANIMATION)

    def toast(n):
        box = layer_box(args.socket, monitor, "omarchy-notifications")
        if not box:
            print("shell.py: the shell has no notification layer on this monitor", flush=True)
            return
        x, y, bw, bh = box
        top = Region(sc, (x, y, bw, min(bh, 200)))
        bus = SessionBus()
        try:
            for i in range(n):
                sent = []

                def press():
                    serial, stamp = bus.notify("hypoland-bench", f"Notification {i + 1}", "The quick brown fox jumps over the lazy dog")
                    sent.append(serial)
                    return stamp

                report("toast", top.until_changed(press, rng.uniform(0, frame)))
                bus.close_notification(bus.notification_id(sent[0]))
                time.sleep(GONE)
        finally:
            bus.close()

    try:
        print("latency phase", flush=True)
        if args.menu:
            menu(args.menu)
        if args.search:
            search(args.search)
        if args.select:
            select(args.select)
        if args.toast:
            toast(args.toast)
    finally:
        if kb:
            kb.close()


main()
