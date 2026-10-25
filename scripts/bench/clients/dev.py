# Drives the developer's screen with a uinput keyboard, which takes the kernel's input path like a real one, and
# measures how long a key takes to show on the screen. A Wayland client without libraries, so it runs wherever Python
# does. Needs root for /dev/uinput.
#
# dev.py --clients FILE --monitors FILE --editor CLASS --console CLASS --border N --load SECONDS --cycles N --quiet FILE
# FILEs are the JSON of hyprctl clients -j and monitors -j. The console has the focus at the start and the editor is
# left of it.
# The load phase (prints "load" when it starts) moves between the editor, which scrolls by itself while it has the
# focus, and the console, which gets a command typed, every 3 s. The latency phase creates the quiet file, which stops
# the editor's scrolling, and then waits for every key until a small region of the output changes, captured with
# wlr-screencopy: moving to the editor (SUPER+Left), scrolling (Ctrl-D, Ctrl-U), jumping to a line (<line>G), back to
# the console (SUPER+Right) and typing a command. The time is from the key press to the commit of the first frame
# that shows the change (the compositor stamps a copied frame when it commits it), the display shows it at its next
# refresh. Keys go down at a random point of the frame, as a person's do. Prints "latency <kind> <ms>" or
# "latency <kind> timeout" for every key it waits for.
import argparse
import array
import fcntl
import json
import mmap
import os
import random
import select
import socket
import struct
import time

TIMEOUT = 2.0  # seconds a key may take to show


def now():
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC)


def u32(*v):
    return struct.pack(f"={len(v)}I", *v)


def i32(*v):
    return struct.pack(f"={len(v)}i", *v)


def string(s):
    b = s.encode() + b"\0"
    return u32(len(b)) + b + b"\0" * (-len(b) % 4)


def unstring(p, off):
    (n,) = struct.unpack_from("=I", p, off)
    return p[off + 4 : off + 3 + n].decode(), off + 4 + n + (-n % 4)


class Wayland:
    def __init__(self):
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.last = 1
        self.handlers = {1: self.on_display}
        self.data = b""

    def new(self, handler=None):
        self.last += 1
        self.handlers[self.last] = handler
        return self.last

    def send(self, obj, op, args=b"", fds=None):
        msg = u32(obj, ((8 + len(args)) << 16) | op) + args
        if fds:
            self.sock.sendmsg([msg], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", fds))])
        else:
            self.sock.sendall(msg)

    def on_display(self, op, p):
        if op == 0:
            obj, code = struct.unpack_from("=2I", p)
            raise SystemExit(f"dev.py: protocol error on object {obj}, code {code}: {unstring(p, 8)[0]}")
        if op == 1:
            self.handlers.pop(struct.unpack_from("=I", p)[0], None)

    def dispatch(self, timeout):
        """Handles the events that arrive within timeout seconds, returns whether any did"""
        if not select.select([self.sock], [], [], max(timeout, 0))[0]:
            return False
        chunk = self.sock.recv(1 << 16)
        if not chunk:
            raise SystemExit("dev.py: the compositor closed the connection")
        self.data += chunk
        while len(self.data) >= 8:
            obj, word = struct.unpack_from("=2I", self.data)
            size = word >> 16
            if len(self.data) < size:
                break
            payload, self.data = self.data[8:size], self.data[size:]
            handler = self.handlers.get(obj)
            if handler:
                handler(word & 0xFFFF, payload)
        return True

    def wait(self, cond, timeout):
        """Handles events until cond() holds, returns whether it does"""
        deadline = time.monotonic() + timeout
        while not cond():
            left = deadline - time.monotonic()
            if left <= 0:
                return False
            self.dispatch(left)
        return True

    def roundtrip(self):
        done = []
        self.send(1, 0, u32(self.new(lambda op, p: done.append(op))))
        if not self.wait(lambda: done, 5):
            raise SystemExit("dev.py: the compositor does not answer")


class Screencopy:
    """Captures a region of the output, in the output's logical coordinates"""

    def __init__(self, wl, output_name):
        self.wl = wl
        globs = {}

        def on_global(op, p):
            if op == 0:
                (name,) = struct.unpack_from("=I", p)
                iface, off = unstring(p, 4)
                globs.setdefault(iface, []).append((name, struct.unpack_from("=I", p, off)[0]))

        self.registry = wl.new(on_global)
        wl.send(1, 1, u32(self.registry))
        wl.roundtrip()
        if "zwlr_screencopy_manager_v1" not in globs:
            raise SystemExit("dev.py: the compositor has no wlr-screencopy")
        self.shm = self.bind(globs["wl_shm"][0][0], "wl_shm", 1)
        name, version = globs["zwlr_screencopy_manager_v1"][0]
        self.version = min(version, 3)
        self.manager = self.bind(name, "zwlr_screencopy_manager_v1", self.version)
        names = {}
        for name, version in globs["wl_output"]:
            oid = self.bind(name, "wl_output", min(version, 4))
            # the name event, wl_output version 4
            wl.handlers[oid] = lambda op, p, oid=oid: names.update({oid: unstring(p, 0)[0]}) if op == 4 else None
        wl.roundtrip()
        outputs = [o for o, n in names.items() if n == output_name] or (list(names) if len(globs["wl_output"]) == 1 else [])
        if not outputs:
            raise SystemExit(f"dev.py: no output {output_name}")
        self.output = outputs[0]

    def bind(self, name, iface, version, handler=None):
        oid = self.wl.new(handler)
        self.wl.send(self.registry, 0, u32(name) + string(iface) + u32(version, oid))
        return oid


class Frame:
    def __init__(self, sc, region):
        self.sc = sc
        self.info = None
        self.described = False
        self.stamp = None
        self.failed = False
        self.id = sc.wl.new(self.on_event)
        sc.wl.send(sc.manager, 1, u32(self.id) + i32(0) + u32(sc.output) + i32(*region))

    def on_event(self, op, p):
        if op == 0 and self.info is None:  # buffer: format, width, height, stride
            self.info = struct.unpack_from("=4I", p)
            self.described = self.sc.version < 3
        elif op == 6:  # buffer_done
            self.described = True
        elif op == 2:  # ready
            hi, lo, nsec = struct.unpack_from("=3I", p)
            self.stamp = ((hi << 32) | lo) * 1_000_000_000 + nsec
        elif op == 3:
            self.failed = True

    def done(self):
        return self.stamp is not None or self.failed

    def copy(self, buffer, damage):
        self.sc.wl.send(self.id, 2 if damage else 0, u32(buffer))

    def destroy(self):
        self.sc.wl.send(self.id, 1)


class Region:
    """A region and three shm buffers for it: two for frames in turn, one for the frame the others are compared with"""

    def __init__(self, sc, box):
        self.sc = sc
        self.box = box
        self.buffers = None
        self.turn = 0

    def frame(self):
        f = Frame(self.sc, self.box)
        if not self.sc.wl.wait(lambda: f.described or f.failed, 5) or f.failed or f.info is None:
            raise SystemExit(f"dev.py: no frame for the region {self.box}")
        if self.buffers is None:
            self.allocate(f.info)
        return f

    def allocate(self, info):
        fmt, width, height, stride = info
        self.size = stride * height
        fd = os.memfd_create("hypoland-latency", os.MFD_CLOEXEC)
        os.ftruncate(fd, 3 * self.size)
        self.map = mmap.mmap(fd, 3 * self.size)
        pool = self.sc.wl.new()
        self.sc.wl.send(self.sc.shm, 0, u32(pool) + i32(3 * self.size), fds=[fd])
        os.close(fd)
        self.buffers = []
        for i in range(3):
            self.buffers.append(self.sc.wl.new())
            self.sc.wl.send(pool, 0, u32(self.buffers[-1]) + i32(i * self.size, width, height, stride) + u32(fmt))
        self.sc.wl.send(pool, 1)

    def pixels(self, i):
        return self.map[i * self.size : (i + 1) * self.size]

    def share(self, f):
        """Shares a frame for the next commit, into the buffer that is not being compared"""
        self.turn ^= 1
        f.copy(self.buffers[self.turn], True)
        return self.turn

    def current(self):
        """The region as the next frame shows it, or as it is when nothing draws (a copy without damage draws the
        whole output once)"""
        f = self.frame()
        f.copy(self.buffers[2], True)
        if not self.sc.wl.wait(f.done, 0.1):
            f.destroy()
            f = self.frame()
            f.copy(self.buffers[2], False)
            self.sc.wl.wait(f.done, 2)
        f.destroy()
        return self.pixels(2)

    def settled(self):
        """The region once two frames in a row show the same, an animation may still run after a key"""
        last = self.current()
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline:
            pixels = self.current()
            if pixels == last:
                return pixels
            last = pixels
        return last

    def until_changed(self, press, delay):
        """Presses the keys after delay seconds and returns the nanoseconds until a frame shows the region changed,
        None on a timeout"""
        before = self.settled()
        # settled() returns right after a commit
        time.sleep(delay)
        f = self.frame()
        slot = self.share(f)
        following = self.frame()
        start = press()
        deadline = time.monotonic() + TIMEOUT
        while self.sc.wl.wait(f.done, deadline - time.monotonic()):
            # the next frame waits for the next commit before this one is looked at
            g, f = f, following
            gslot, slot = slot, self.share(f)
            g.destroy()
            if not g.failed and self.pixels(gslot) != before:
                f.destroy()
                return g.stamp - start
            following = self.frame()
        f.destroy()
        following.destroy()
        return None


# ---- keyboard

UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x405C5503, 0x5501, 0x5502
EV_SYN, EV_KEY = 0, 1
KEYS = {"esc": 1, "enter": 28, "ctrl": 29, "shift": 42, "space": 57, "super": 125, "left": 105, "right": 106}
KEYS.update({str(d): 2 + (d - 1) % 10 for d in range(10)})
for row, first in (("qwertyuiop", 16), ("asdfghjkl", 30), ("zxcvbnm", 44)):
    KEYS.update({c: first + i for i, c in enumerate(row)})


class Keyboard:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        for code in set(KEYS.values()):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
        fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("=4H80sI", 0x06, 0x4859, 0x504F, 1, b"hypoland-bench keyboard", 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        # libinput and the compositor pick the device up, and the first key makes it the seat's keyboard
        time.sleep(1.5)
        self.key(KEYS["shift"], 1)
        self.key(KEYS["shift"], 0)
        time.sleep(0.5)

    def key(self, code, value):
        os.write(self.fd, struct.pack("=qqHHi", 0, 0, EV_KEY, code, value) + struct.pack("=qqHHi", 0, 0, EV_SYN, 0, 0))

    def chord(self, chord):
        """Presses a chord like super+left and returns when the last key went down"""
        codes = [KEYS[k] for k in chord.split("+")]
        for code in codes[:-1]:
            self.key(code, 1)
            time.sleep(0.005)
        start = now()
        self.key(codes[-1], 1)
        for code in reversed(codes):
            self.key(code, 0)
        return start

    def close(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def chord_of(c):
    return {" ": "space", "\n": "enter"}.get(c, f"shift+{c.lower()}" if c.isupper() else c)


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
