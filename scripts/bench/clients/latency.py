# What the latency drivers (dev.py, windows.py) share: a Wayland client without libraries, so it runs wherever Python
# does, that captures regions of the output with wlr-screencopy, uinput devices (a keyboard and an absolute pointer)
# that take the kernel's input path like real ones, and the compositor's hyprctl socket. uinput needs root.
#
# A step is timed from the input event to the commit of the first frame that shows the region changed (the compositor
# stamps a copied frame when it commits it), the display shows it at its next refresh. Inputs go out at a random point
# of the frame, as a person's do.
import array
import fcntl
import json
import mmap
import os
import select
import socket
import struct
import time

TIMEOUT = 2.0  # seconds a step may take to show


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


def hyprctl(path, request):
    """The JSON answer of the compositor to a request like j/clients"""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect(path)
        s.sendall(request.encode())
        data = b""
        while chunk := s.recv(1 << 16):
            data += chunk
    return json.loads(data)


def layer_box(path, monitor, namespace):
    """The box of a layer surface (by its namespace) on a monitor, in the output's logical coordinates, or None"""
    levels = hyprctl(path, "j/layers").get(monitor["name"], {}).get("levels", {})
    for layers in levels.values():
        for layer in layers:
            if layer.get("namespace") == namespace:
                return (layer["x"] - monitor["x"], layer["y"] - monitor["y"], layer["w"], layer["h"])
    return None


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
            raise SystemExit(f"latency: protocol error on object {obj}, code {code}: {unstring(p, 8)[0]}")
        if op == 1:
            self.handlers.pop(struct.unpack_from("=I", p)[0], None)

    def dispatch(self, timeout):
        """Handles the events that arrive within timeout seconds, returns whether any did"""
        if not select.select([self.sock], [], [], max(timeout, 0))[0]:
            return False
        chunk = self.sock.recv(1 << 16)
        if not chunk:
            raise SystemExit("latency: the compositor closed the connection")
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
            raise SystemExit("latency: the compositor does not answer")


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
            raise SystemExit("latency: the compositor has no wlr-screencopy")
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
            raise SystemExit(f"latency: no output {output_name}")
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
            raise SystemExit(f"latency: no frame for the region {self.box}")
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

    def follow(self, press, delay, settle=0.0):
        """Calls press after delay seconds and returns the nanoseconds until the first frame that shows the region
        changed and, with settle, until the first frame that shows it as it then stays for settle seconds (the client
        has drawn). None for what did not show within TIMEOUT"""
        before = self.settled()
        # settled() returns right after a commit
        time.sleep(delay)
        f = self.frame()
        slot = self.share(f)
        following = self.frame()
        start = press()
        first = last = None
        shown = before
        deadline = quiet = time.monotonic() + TIMEOUT
        while self.sc.wl.wait(f.done, min(deadline, quiet) - time.monotonic()):
            # the next frame waits for the next commit before this one is looked at
            g, f = f, following
            gslot, slot = slot, self.share(f)
            g.destroy()
            following = self.frame()
            pixels = None if g.failed else self.pixels(gslot)
            if pixels is None or pixels == shown:
                continue
            shown = pixels
            last = g.stamp - start
            if first is None:
                first = last
                if not settle:
                    break
            quiet = time.monotonic() + settle
        f.destroy()
        following.destroy()
        return first, last

    def until_changed(self, press, delay):
        """Calls press after delay seconds and returns the nanoseconds until a frame shows the region changed, None on
        a timeout"""
        return self.follow(press, delay)[0]


# ---- input devices

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_SETUP, UI_ABS_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x401C5504, 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_X, ABS_Y, ABS_MAX = 0, 1, 65535
BTN_LEFT, BTN_RIGHT = 0x110, 0x111
KEYS = {"esc": 1, "enter": 28, "ctrl": 29, "shift": 42, "alt": 56, "space": 57, "super": 125}
KEYS.update({"up": 103, "left": 105, "right": 106, "down": 108})
KEYS.update({str(d): 2 + (d - 1) % 10 for d in range(10)})
for row, first in (("qwertyuiop", 16), ("asdfghjkl", 30), ("zxcvbnm", 44)):
    KEYS.update({c: first + i for i, c in enumerate(row)})


class Device:
    """A uinput device. libinput and the compositor take a moment to pick it up"""

    def __init__(self, name, product, events, keys, axes=()):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        for ev in events:
            fcntl.ioctl(self.fd, UI_SET_EVBIT, ev)
        for code in keys:
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
        for code in axes:
            fcntl.ioctl(self.fd, UI_SET_ABSBIT, code)
        fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("=4H80sI", 0x06, 0x4859, product, 1, name.encode(), 0))
        for code in axes:  # value, minimum, maximum, fuzz, flat, resolution
            fcntl.ioctl(self.fd, UI_ABS_SETUP, struct.pack("=H2x6i", code, 0, 0, ABS_MAX, 0, 0, 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(1.5)

    def emit(self, *events):
        """Writes events (type, code, value) and a report"""
        os.write(self.fd, b"".join(struct.pack("=qqHHi", 0, 0, *e) for e in events + ((EV_SYN, 0, 0),)))

    def close(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


class Keyboard(Device):
    def __init__(self):
        super().__init__("hypoland-bench keyboard", 0x504F, (EV_KEY,), set(KEYS.values()))
        # the first key makes it the seat's keyboard
        self.key(KEYS["shift"], 1)
        self.key(KEYS["shift"], 0)
        time.sleep(0.5)

    def key(self, code, value):
        self.emit((EV_KEY, code, value))

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


class Pointer(Device):
    """An absolute pointer, like a virtual machine's tablet: the compositor maps it onto the box around all monitors
    (CPointerManager::warpAbsolute()), so a position in its logical coordinates is reached exactly, without the
    acceleration of a mouse"""

    def __init__(self, monitors):
        boxes = []
        for m in monitors:
            w, h = (m["height"], m["width"]) if m.get("transform", 0) % 2 else (m["width"], m["height"])
            boxes.append((m["x"], m["y"], m["x"] + w / m["scale"], m["y"] + h / m["scale"]))
        self.x0, self.y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
        self.w, self.h = max(b[2] for b in boxes) - self.x0, max(b[3] for b in boxes) - self.y0
        super().__init__("hypoland-bench pointer", 0x5050, (EV_KEY, EV_ABS), (BTN_LEFT, BTN_RIGHT), (ABS_X, ABS_Y))

    def move(self, x, y):
        """Moves to a position in the compositor's logical coordinates and returns when it went out"""
        ax = round((x - self.x0) / self.w * (ABS_MAX + 1))
        ay = round((y - self.y0) / self.h * (ABS_MAX + 1))
        start = now()
        self.emit((EV_ABS, ABS_X, min(max(ax, 0), ABS_MAX)), (EV_ABS, ABS_Y, min(max(ay, 0), ABS_MAX)))
        return start

    def button(self, code, value):
        self.emit((EV_KEY, code, value))


def chord_of(c):
    return {" ": "space", "\n": "enter"}.get(c, f"shift+{c.lower()}" if c.isupper() else c)
