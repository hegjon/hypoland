#!/usr/bin/env python3
# render.py --socket PATH --out DIR [--grab grim|kmsgrab] : checks that the screen shows what it should, root (it
# freezes the shell while it looks, and the screen's own buffer is read with hypoland-kmsgrab).
#
# Two shm windows of its own on an empty workspace, drawn with patterns of 7x7 blocks it knows pixel by pixel, go
# through what the compositor's shortcuts touch: a whole buffer, small damaged rectangles in turn (the damage merging
# on crocus and r600, the shm textures double buffered), a new buffer further on in the memory pool with only its
# changes damaged (as foot does, read in place or copied), a window with transparent parts floating over another, moved
# and closed (its fade-out). At every step:
#   pixels      the focused window shows exactly what it drew (an integer scale only, inside its rounding and border)
#   repaint     the screen as the step left it is what a full repaint of the same scene shows: the clients and the shell
#               are frozen, the screen is read, the workspace is switched away and back (the whole monitor is drawn
#               again), and read again. A pixel that differs was left stale or drawn wrong by the incremental frames.
# Prints "PASS  ..." / "FAIL  ..." lines like the session check, the screens that differ into DIR.
import argparse
import fcntl
import json
import mmap
import os
import random
import signal
import socket
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from latency import Wayland, hyprctl, i32, string, u32, unstring  # noqa: E402

ARGB, XRGB = 0, 1
BLOCK = 7


def request(path, req):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect(path)
        s.sendall(req.encode())
        data = b""
        while chunk := s.recv(1 << 16):
            data += chunk
    return data.decode(errors="replace").strip()


def color(seed, bx, by):
    """A block's color: opaque, and neighbours differ in every channel"""
    h = (seed * 2654435761 + bx * 40503 + by * 9973) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    return 0xFF000000 | (h & 0xFFFFFF)


class Window:
    """An xdg toplevel with an shm pool of three buffer slots; it remembers what each pixel should be"""

    def __init__(self, r, app_id, fmt=XRGB, parent=None):
        self.r, self.wl, self.app_id, self.fmt = r, r.wl, app_id, fmt
        self.configured = None
        self.serial = None
        self.closed = False
        self.frames = 0
        self.surface = self.wl.new()
        self.wl.send(r.compositor, 0, u32(self.surface))
        self.xdg = self.wl.new(self.on_xdg)
        self.wl.send(r.wm, 2, u32(self.xdg, self.surface))
        self.top = self.wl.new(self.on_top)
        self.wl.send(self.xdg, 1, u32(self.top))
        self.wl.send(self.top, 3, string(app_id))
        self.wl.send(self.top, 2, string(app_id))
        if parent:
            # a dialog of the other window: it floats from the start, the other one keeps its place and size
            self.wl.send(self.top, 1, u32(parent.top))
        if r.scale > 1:
            self.wl.send(self.surface, 8, i32(r.scale))
        self.wl.send(self.surface, 6)
        self.size = None
        self.pool = None
        self.slot = 0
        self.buffer = None

    def on_xdg(self, op, p):
        if op == 0:
            (self.serial,) = struct.unpack_from("=I", p)

    def on_top(self, op, p):
        if op == 0:
            self.configured = struct.unpack_from("=2i", p)
        elif op == 1:
            self.closed = True

    def follow(self, seed, alpha_rows=None):
        """Answers a configure that came since: the tiled size comes after the window mapped. Redraws at the new size"""
        self.r.settle(0.4)
        if self.serial is None:
            return
        size = self.wait_configure()
        if size[0] and size[1] and (size[0] * self.r.scale, size[1] * self.r.scale) != (self.w, self.h):
            self.wl.send(self.pool, 1)
            if self.buffer is not None:
                self.wl.send(self.buffer, 0)
            self.buffer = None
            self.allocate(size)
            self.fill(seed, alpha_rows)
            self.commit()

    def wait_configure(self):
        if not self.wl.wait(lambda: self.serial is not None, 5):
            raise SystemExit(f"render.py: {self.app_id} got no configure")
        self.wl.send(self.xdg, 4, u32(self.serial))
        self.serial = None
        return self.configured or (0, 0)

    def allocate(self, logical):
        """A pool for three buffers of the window's size in pixels, sealed so the compositor may read it in place"""
        self.w, self.h = logical[0] * self.r.scale, logical[1] * self.r.scale
        self.stride = self.w * 4
        self.slotsize = self.stride * self.h
        fd = os.memfd_create(self.app_id, os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
        os.ftruncate(fd, self.slotsize * 3)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_SHRINK)
        self.mem = mmap.mmap(fd, self.slotsize * 3)
        self.pool = self.wl.new()
        self.wl.send(self.r.shm, 0, u32(self.pool) + i32(self.slotsize * 3), [fd])
        os.close(fd)
        self.want = bytearray(self.slotsize)  # what the window shows, as B G R A bytes

    def fill(self, seed, alpha_rows=None):
        """The whole window in blocks of seed; alpha_rows: a band of rows (from, to) drawn half transparent"""
        row = bytearray(self.stride)
        for by in range((self.h + BLOCK - 1) // BLOCK):
            for bx in range((self.w + BLOCK - 1) // BLOCK):
                c = color(seed, bx, by)
                row[bx * BLOCK * 4 : min(bx * BLOCK + BLOCK, self.w) * 4] = struct.pack("=I", c) * (min(bx * BLOCK + BLOCK, self.w) - bx * BLOCK)
            for y in range(by * BLOCK, min(by * BLOCK + BLOCK, self.h)):
                self.want[y * self.stride : (y + 1) * self.stride] = row
        if alpha_rows:
            for y in range(*alpha_rows):
                line = bytearray(self.want[y * self.stride : (y + 1) * self.stride])
                line[3::4] = b"\x80" * self.w
                # premultiplied: the color channels at half as well
                for ch in range(3):
                    line[ch::4] = bytes(v >> 1 for v in line[ch::4])
                self.want[y * self.stride : (y + 1) * self.stride] = line

    def rect(self, seed, x, y, w, h):
        """A rectangle in pixels filled with one block color of seed"""
        x, y = max(x, 0), max(y, 0)
        w, h = min(w, self.w - x), min(h, self.h - y)
        line = struct.pack("=I", color(seed, x, y)) * w
        for yy in range(y, y + h):
            self.want[yy * self.stride + x * 4 : yy * self.stride + (x + w) * 4] = line
        return (x, y, w, h)

    def commit(self, damage=None, new_slot=False):
        """Copies what the window should show into a buffer slot, attaches it with damage in buffer pixels (None: all)
        and waits for the frame. new_slot: the next slot of the pool, as foot's new buffer per line"""
        if new_slot or self.buffer is None:
            self.slot = (self.slot + 1) % 3 if self.buffer is not None else 0
            if self.buffer is not None:
                self.wl.send(self.buffer, 0)  # wl_buffer.destroy
            self.buffer = self.wl.new()
            fmt = 0 if self.fmt == ARGB else 1
            self.wl.send(self.pool, 0, u32(self.buffer) + i32(self.slot * self.slotsize, self.w, self.h, self.stride) + u32(fmt))
        off = self.slot * self.slotsize
        self.mem[off : off + self.slotsize] = self.want
        self.wl.send(self.surface, 1, u32(self.buffer) + i32(0, 0))
        for x, y, w, h in damage or [(0, 0, self.w, self.h)]:
            self.wl.send(self.surface, 9, i32(x, y, w, h))
        done = []
        self.wl.send(self.surface, 3, u32(self.wl.new(lambda op, p: done.append(1))))
        self.wl.send(self.surface, 6)
        self.wl.wait(lambda: done, 2)

    def destroy(self):
        self.wl.send(self.top, 0)
        self.wl.send(self.xdg, 0)
        self.wl.send(self.surface, 0)
        if self.buffer is not None:
            self.wl.send(self.buffer, 0)
        self.wl.send(self.pool, 1)
        self.wl.roundtrip()


class Render:
    def __init__(self, args):
        self.args = args
        self.failed = 0
        self.out = args.out
        os.makedirs(self.out, exist_ok=True)
        monitors = hyprctl(args.socket, "j/monitors")
        self.monitor = next(m for m in monitors if m["focused"])
        s = self.monitor["scale"]
        self.scale = int(s) if abs(s - round(s)) < 0.01 else 1
        self.exact = abs(s - round(s)) < 0.01
        self.home = self.monitor["activeWorkspace"]["id"]
        used = {c["workspace"]["id"] for c in hyprctl(args.socket, "j/clients")}
        self.ws = next(w for w in (8, 9, 10, 7, 6) if w not in used and w != self.home)
        self.away = next(w for w in (9, 10, 7, 6, 5) if w not in used and w not in (self.home, self.ws))
        try:
            opt = hyprctl(args.socket, "j/getoption decoration:rounding")
            self.rounding = int(opt.get("int", 0))
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            self.rounding = 10
        self.wl = Wayland()
        globs = {}

        def on_global(op, p):
            if op == 0:
                (name,) = struct.unpack_from("=I", p)
                iface, off = unstring(p, 4)
                globs.setdefault(iface, (name, struct.unpack_from("=I", p, off)[0]))

        self.registry = self.wl.new(on_global)
        self.wl.send(1, 1, u32(self.registry))
        self.wl.roundtrip()
        self.compositor = self.bind(globs, "wl_compositor", 4)
        self.shm = self.bind(globs, "wl_shm", 1)
        self.wm = self.bind(globs, "xdg_wm_base", 1, self.on_wm)
        self.wl.roundtrip()

    def bind(self, globs, iface, version, handler=None):
        name, have = globs[iface]
        oid = self.wl.new(handler)
        self.wl.send(self.registry, 0, u32(name) + string(iface) + u32(min(version, have), oid))
        return oid

    def on_wm(self, op, p):
        if op == 0:  # ping
            self.wl.send(self.wm, 3, p[:4])

    def dispatch(self, lua, legacy):
        if request(self.args.socket, "dispatch " + lua) != "ok":
            request(self.args.socket, "dispatch " + legacy)

    def workspace(self, n):
        self.dispatch(f"hl.dsp.focus({{workspace = {n}}})", f"workspace {n}")

    def client(self, app_id):
        for c in hyprctl(self.args.socket, "j/clients"):
            if c["class"] == app_id and c["mapped"]:
                return c
        return None

    def nearest(self, win):
        """Samples the window with the nearest texel (diagnostic: is a difference the linear filter's?)"""
        addr = (self.client(win.app_id) or {}).get("address")
        if addr:
            self.dispatch(f'hl.dsp.window.set_prop({{prop = "nearest_neighbor", value = "1", window = "address:{addr}"}})',
                          f"setprop address:{addr} nearest_neighbor 1")

    def settle(self, seconds=1.0):
        """Lets animations end, answering pings meanwhile"""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            self.wl.dispatch(end - time.monotonic())

    def grab(self, name):
        """The screen as RGB bytes, width, height"""
        path = os.path.join(self.out, name + ".ppm")
        if self.args.grab == "kmsgrab":
            subprocess.run(["hypoland-kmsgrab", path], check=True, capture_output=True)
        else:
            subprocess.run(["grim", "-o", self.monitor["name"], "-t", "ppm", path], check=True, capture_output=True)
        with open(path, "rb") as f:
            data = f.read()
        # P6 width height maxval, single whitespace before the pixels
        parts, off = [], 0
        while len(parts) < 4:
            while data[off : off + 1].isspace():
                off += 1
            if data[off : off + 1] == b"#":
                off = data.index(b"\n", off) + 1
                continue
            start = off
            while not data[off : off + 1].isspace():
                off += 1
            parts.append(data[start:off])
        w, h = int(parts[1]), int(parts[2])
        return data[off + 1 : off + 1 + w * h * 3], w, h

    def frozen(self):
        """The processes that draw besides us: the shell and every client on the screen"""
        pids = set()
        for name in ("quickshell", "qs", "omarchy-shell"):
            pids.update(int(p) for p in subprocess.run(["pgrep", "-x", name], capture_output=True, text=True).stdout.split())
        return pids

    def check_repaint(self, step):
        """The screen now and after a full repaint of the same scene are the same"""
        pids = self.frozen()
        for p in pids:
            os.kill(p, signal.SIGSTOP)
        try:
            self.settle(0.3)
            a, w, h = self.grab(f"{step}-incremental")
            self.workspace(self.away)
            self.settle(0.4)
            self.workspace(self.ws)
            self.settle(1.2)
            b, _, _ = self.grab(f"{step}-repainted")
        finally:
            for p in pids:
                os.kill(p, signal.SIGCONT)
        if a == b:
            print(f"PASS  render {step}: the screen is what a full repaint shows", flush=True)
            for n in ("incremental", "repainted"):
                os.remove(os.path.join(self.out, f"{step}-{n}.ppm"))
            return
        n, box = 0, [w, h, 0, 0]
        for i in range(0, len(a), 3):
            if a[i : i + 3] != b[i : i + 3]:
                n += 1
                x, y = (i // 3) % w, (i // 3) // w
                box = [min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y)]
        self.failed += 1
        print(f"FAIL  render {step}: {n} pixels differ from a full repaint, in {box[0]},{box[1]} to {box[2]},{box[3]} "
              f"(screens in {self.out})", flush=True)

    def check_pixels(self, step, win, under=None):
        """The focused window shows exactly what it drew, inside its rounding and border. Over the window under, its
        transparent pixels show that one through as premultiplied alpha blends it, to a step"""
        if not self.exact:
            print(f"SKIP  render {step}: pixels need an integer scale ({self.monitor['scale']})", flush=True)
            return
        c = self.client(win.app_id)
        if not c:
            self.failed += 1
            print(f"FAIL  render {step}: {win.app_id} is not mapped", flush=True)
            return
        screen, sw, sh = self.grab(f"{step}-pixels")
        s = self.scale
        x0 = (c["at"][0] - self.monitor["x"]) * s
        y0 = (c["at"][1] - self.monitor["y"]) * s
        if under:
            cu = self.client(under.app_id)
            ux, uy = (cu["at"][0] - self.monitor["x"]) * s, (cu["at"][1] - self.monitor["y"]) * s
        inset = (self.rounding + 2) * s
        bad, worst = 0, None
        for y in range(inset, win.h - inset):
            sy = y0 + y
            if not 0 <= sy < sh:
                continue
            row = win.want[y * win.stride : (y + 1) * win.stride]
            got = screen[(sy * sw + x0 + inset) * 3 : (sy * sw + x0 + win.w - inset) * 3]
            if under and row[3::4] != b"\xff" * win.w:
                for x in range(inset, win.w - inset):
                    b, g, r, a = row[x * 4 : x * 4 + 4]
                    if a == 255:
                        exp = (r, g, b)
                    else:
                        o = (sy - uy) * under.stride + (x0 + x - ux) * 4
                        db, dg, dr = under.want[o : o + 3]
                        exp = tuple(min(255, round(v + d * (255 - a) / 255)) for v, d in ((r, dr), (g, dg), (b, db)))
                    shown = tuple(got[(x - inset) * 3 : (x - inset) * 3 + 3])
                    if max(abs(e - g2) for e, g2 in zip(exp, shown)) > (0 if a == 255 else 1):
                        bad += 1
                        worst = worst or (x, y, exp, shown)
                continue
            rgb = bytearray(win.w * 3)
            rgb[0::3], rgb[1::3], rgb[2::3] = row[2::4], row[1::4], row[0::4]
            exp = bytes(rgb[inset * 3 : (win.w - inset) * 3])
            if got != exp:
                for i in range(0, len(exp), 3):
                    if got[i : i + 3] != exp[i : i + 3]:
                        bad += 1
                        worst = worst or (inset + i // 3, y, tuple(exp[i : i + 3]), tuple(got[i : i + 3]))
        if bad == 0:
            os.remove(os.path.join(self.out, f"{step}-pixels.ppm"))
            print(f"PASS  render {step}: {win.app_id} shows every pixel it drew", flush=True)
        else:
            self.failed += 1
            print(f"FAIL  render {step}: {bad} pixels of {win.app_id} differ from what it drew, first at {worst[0]},{worst[1]}: "
                  f"{worst[2]} shown as {worst[3]}", flush=True)

    def run(self):
        rng = random.Random(7)
        request(self.args.socket, "dismissnotify")  # the compositor's own notifications, drawn over everything
        self.workspace(self.ws)
        # the pointer into the corner, in the outer gap: a cursor drawn into the frame (no cursor plane) is not the windows'
        cx, cy = self.monitor["x"] + int(self.monitor["width"] / self.monitor["scale"]) - 1, self.monitor["y"] + int(self.monitor["height"] / self.monitor["scale"]) - 1
        self.dispatch(f"hl.dsp.cursor.move({{x = {cx}, y = {cy}}})", f"movecursor {cx} {cy}")
        self.settle(0.3)
        a = Window(self, "hypoland-render-a")
        w, h = a.wait_configure()
        a.allocate((w or 640, h or 480))
        a.fill(1)
        a.commit()
        a.follow(1)
        if self.args.nearest:
            self.nearest(a)
        self.settle(1.2)
        self.check_pixels("whole", a)
        self.check_repaint("whole")

        # small rectangles, a few per frame, as a terminal or a toolkit redraws
        for frame in range(24):
            damage = [a.rect(100 + frame * 4 + k, rng.randrange(a.w), rng.randrange(a.h), rng.randrange(8, 160), rng.randrange(8, 90)) for k in range(4)]
            a.commit(damage)
        if self.args.selftest:
            # a change without its damage: the screen keeps the old pixels, which one of the checks has to see
            a.rect(999, a.w // 3, a.h // 3, 64, 64)
            a.commit([(0, 0, 1, 1)])
        self.settle(1.0)
        self.check_pixels("rectangles", a)
        self.check_repaint("rectangles")

        # a new buffer further on in the pool with only its changes damaged, as foot's new buffer per line
        for frame in range(12):
            damage = [a.rect(300 + frame, 0, rng.randrange(a.h), a.w, BLOCK * 2)]
            a.commit(damage, new_slot=True)
        self.settle(1.0)
        self.check_pixels("new buffers", a)
        self.check_repaint("new buffers")

        # a window with a transparent band floating over the other (a dialog of it), moved, then closed
        b = Window(self, "hypoland-render-b", ARGB, parent=a)
        w, h = b.wait_configure()
        b.allocate((w if w and w < 600 else 420, h if h and h < 600 else 300))
        b.fill(2, alpha_rows=(b.h // 3, b.h // 2))
        b.commit()
        b.follow(2, alpha_rows=(b.h // 3, b.h // 2))
        addr = (self.client("hypoland-render-b") or {}).get("address")
        if addr:
            self.dispatch(f'hl.dsp.window.move({{x = {self.monitor["x"] + 200}, y = {self.monitor["y"] + 150}, window = "address:{addr}"}})',
                          f"movewindowpixel exact {self.monitor['x'] + 200} {self.monitor['y'] + 150},address:{addr}")
        if self.args.nearest:
            self.nearest(b)
        self.settle(1.2)
        self.check_pixels("floating", b, under=a)
        self.check_repaint("floating")
        if addr:
            self.dispatch(f'hl.dsp.window.move({{x = {self.monitor["x"] + 237}, y = {self.monitor["y"] + 173}, window = "address:{addr}"}})',
                          f"movewindowpixel exact {self.monitor['x'] + 237} {self.monitor['y'] + 173},address:{addr}")
        self.settle(1.2)
        self.check_repaint("moved")
        b.destroy()
        self.settle(1.5)
        self.check_repaint("closed")

        a.destroy()
        self.settle(0.5)
        self.workspace(self.home)
        return self.failed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--grab", choices=("kmsgrab", "grim"), default="kmsgrab")
    ap.add_argument("--selftest", action="store_true", help="damage one change wrongly, the checks have to fail")
    ap.add_argument("--nearest", action="store_true", help="sample its windows with the nearest texel")
    args = ap.parse_args()
    raise SystemExit(1 if Render(args).run() else 0)


if __name__ == "__main__":
    main()
