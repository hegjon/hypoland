#!/usr/bin/env python3
# render.py --socket PATH --out DIR [--grab grim|kmsgrab] : checks that the screen shows what it should, root (it
# freezes the shell while it looks, and the screen's own buffer is read with hypoland-kmsgrab).
#
# Two shm windows of its own on an empty workspace, drawn with patterns of 7x7 blocks it knows pixel by pixel, go
# through what the compositor's shortcuts touch: a whole buffer, small damaged rectangles in turn (the damage merging
# on crocus and r600, the shm textures double buffered), a new buffer further on in the memory pool with only its
# changes damaged (as foot does, read in place or copied), subsurfaces drawn by themselves and moved (a video player's
# or a toolkit's), subsurfaces magnified, shrunk and cut out by a viewport or turned by a quarter, with small damage
# (the filter reaches past it, the damage is turned and cut with the buffer), a popup opened and closed, a mostly
# transparent overlay layer that changes where it was clear (the alpha bounds clip it), and a window with transparent
# parts floating over another, moved, shrunk and closed (its fade-out), and the first window fullscreen and back. At
# every step:
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
import shutil
import signal
import socket
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from latency import Screencopy, Wayland, hyprctl, i32, layer_box, string, u32, unstring  # noqa: E402

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


class Surface:
    """A wl_surface with an shm pool of three buffer slots; it remembers what each pixel should be"""

    def __init__(self, r, name, fmt=XRGB, scale=None):
        self.r, self.wl, self.name, self.fmt = r, r.wl, name, fmt
        self.scale = r.scale if scale is None else scale
        self.surface = self.wl.new()
        self.wl.send(r.compositor, 0, u32(self.surface))
        if self.scale > 1:
            self.wl.send(self.surface, 8, i32(self.scale))
        self.pool = None
        self.slot = 0
        self.buffer = None
        self.w = self.h = 0
        self.children = []

    def allocate(self, logical, pixels=None):
        """A pool for three buffers of the surface's size in pixels (pixels: a buffer of its own size, scaled by a
        viewport), sealed so the compositor may read it in place"""
        self.release()
        self.w, self.h = pixels or (logical[0] * self.scale, logical[1] * self.scale)
        self.stride = self.w * 4
        self.slotsize = self.stride * self.h
        fd = os.memfd_create(self.name, os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
        os.ftruncate(fd, self.slotsize * 3)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_SHRINK)
        self.mem = mmap.mmap(fd, self.slotsize * 3)
        self.pool = self.wl.new()
        self.wl.send(self.r.shm, 0, u32(self.pool) + i32(self.slotsize * 3), [fd])
        os.close(fd)
        self.want = bytearray(self.slotsize)  # what the surface shows, as B G R A bytes

    def release(self):
        if self.buffer is not None:
            self.wl.send(self.buffer, 0)
        if self.pool is not None:
            self.wl.send(self.pool, 1)
        self.buffer = self.pool = None

    def fill(self, seed, alpha_rows=None, clear_rows=None):
        """The whole surface in blocks of seed; alpha_rows: a band of rows (from, to) drawn half transparent,
        clear_rows: one drawn fully transparent"""
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
        if clear_rows:
            self.want[clear_rows[0] * self.stride : clear_rows[1] * self.stride] = bytes((clear_rows[1] - clear_rows[0]) * self.stride)

    def rect(self, seed, x, y, w, h):
        """A rectangle in pixels filled with one block color of seed"""
        x, y = max(x, 0), max(y, 0)
        w, h = min(w, self.w - x), min(h, self.h - y)
        line = struct.pack("=I", color(seed, x, y)) * w
        for yy in range(y, y + h):
            self.want[yy * self.stride + x * 4 : yy * self.stride + (x + w) * 4] = line
        return (x, y, w, h)

    def commit(self, damage=None, new_slot=False):
        """Copies what the surface should show into a buffer slot, attaches it with damage in buffer pixels (None: all)
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

    def recommit(self):
        """A commit without a buffer or damage: applies the subsurfaces' positions"""
        self.wl.send(self.surface, 6)
        self.wl.roundtrip()

    def composed(self):
        """What the surface shows with its opaque subsurfaces of the same scale on top"""
        img = bytearray(self.want)
        for c in self.children:
            if c.viewport or c.transform or c.fmt != XRGB or c.scale != self.scale:
                continue
            px, py = c.pos[0] * self.scale, c.pos[1] * self.scale
            for y in range(max(0, -py), min(c.h, self.h - py)):
                x0, x1 = max(0, -px), min(c.w, self.w - px)
                if x1 > x0:
                    img[(py + y) * self.stride + (px + x0) * 4 : (py + y) * self.stride + (px + x1) * 4] = c.want[y * c.stride + x0 * 4 : y * c.stride + x1 * 4]
        return img

    def corners(self, radius):
        """The corners of its subsurfaces, which the window's rounding rounds as well (as upstream does): left out"""
        boxes = []
        if radius <= 0:
            return boxes
        for c in self.children:
            px, py = c.pos[0] * self.scale, c.pos[1] * self.scale
            cw = round(c.viewport[0] * self.scale) if c.viewport else c.w * self.scale // c.scale
            ch = round(c.viewport[1] * self.scale) if c.viewport else c.h * self.scale // c.scale
            for x in (px, px + cw - radius):
                for y in (py, py + ch - radius):
                    boxes.append((x, y, radius, radius))
        return boxes

    def destroy_surface(self):
        self.wl.send(self.surface, 0)
        self.release()
        self.wl.roundtrip()


class Window(Surface):
    """An xdg toplevel"""

    def __init__(self, r, app_id, fmt=XRGB, parent=None):
        super().__init__(r, app_id, fmt)
        self.app_id = app_id
        self.configured = None
        self.serial = None
        self.closed = False
        self.xdg = self.wl.new(self.on_xdg)
        self.wl.send(r.wm, 2, u32(self.xdg, self.surface))
        self.top = self.wl.new(self.on_top)
        self.wl.send(self.xdg, 1, u32(self.top))
        self.wl.send(self.top, 3, string(app_id))
        self.wl.send(self.top, 2, string(app_id))
        if parent:
            # a dialog of the other window: it floats from the start, the other one keeps its place and size
            self.wl.send(self.top, 1, u32(parent.top))
        self.wl.send(self.surface, 6)

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
            self.allocate(size)
            self.fill(seed, alpha_rows)
            self.commit()

    def wait_configure(self):
        if not self.wl.wait(lambda: self.serial is not None, 5):
            raise SystemExit(f"render.py: {self.app_id} got no configure")
        self.wl.send(self.xdg, 4, u32(self.serial))
        self.serial = None
        return self.configured or (0, 0)

    def destroy(self):
        self.wl.send(self.top, 0)
        self.wl.send(self.xdg, 0)
        self.destroy_surface()


class Subsurface(Surface):
    """A desynchronized subsurface: its commits show by themselves, its position with the parent's next commit.
    viewport: its buffer scaled to that size in logical pixels"""

    def __init__(self, r, name, parent, pos, viewport=None, transform=0, source=None):
        super().__init__(r, name, XRGB, 1 if viewport else None)
        self.parent, self.viewport, self.transform = parent, viewport, transform
        self.sub = self.wl.new()
        self.wl.send(r.subcompositor, 1, u32(self.sub, self.surface, parent.surface))
        self.wl.send(self.sub, 5)  # set_desync
        if transform:
            self.wl.send(self.surface, 7, i32(transform))  # set_buffer_transform, 1: 90 degrees
        if viewport:
            self.vp = self.wl.new()
            self.wl.send(r.viewporter, 1, u32(self.vp, self.surface))
            self.wl.send(self.vp, 2, i32(*viewport))  # set_destination
            if source:
                self.wl.send(self.vp, 1, i32(*(v * 256 for v in source)))  # set_source, wl_fixed
        self.move(pos)
        parent.children.append(self)

    def move(self, pos):
        self.pos = pos
        self.wl.send(self.sub, 1, i32(*pos))

    def destroy(self):
        """Unmapped at once"""
        self.parent.children.remove(self)
        if self.viewport:
            self.wl.send(self.vp, 0)
        self.wl.send(self.sub, 0)
        self.destroy_surface()


class Popup(Surface):
    """An xdg popup of a window without a grab, its top left corner at anchor (logical pixels of the window), or of a
    layer surface (parent None, layer the Layer) as a bar opens its menus"""

    def __init__(self, r, name, parent, anchor, size, layer=None):
        super().__init__(r, name)
        self.serial = None
        self.placed = None
        self.size = size
        positioner = self.positioner(anchor)
        self.xdg = self.wl.new(self.on_xdg)
        self.wl.send(r.wm, 2, u32(self.xdg, self.surface))
        self.popup = self.wl.new(self.on_popup)
        self.wl.send(self.xdg, 2, u32(self.popup, parent.xdg if parent else 0, positioner))
        if layer:
            self.wl.send(layer.ls, 5, u32(self.popup))  # zwlr_layer_surface_v1.get_popup, before the popup's first commit
        self.wl.send(positioner, 0)
        self.wl.send(self.surface, 6)
        self.ack(name)
        self.allocate(self.placed[2:] if self.placed and self.placed[2] > 0 else size)

    def positioner(self, anchor):
        positioner = self.wl.new()
        self.wl.send(self.r.wm, 1, u32(positioner))
        self.wl.send(positioner, 1, i32(*self.size))  # set_size
        self.wl.send(positioner, 2, i32(anchor[0], anchor[1], 1, 1))  # set_anchor_rect
        self.wl.send(positioner, 3, u32(5))  # set_anchor top_left
        self.wl.send(positioner, 4, u32(8))  # set_gravity bottom_right
        return positioner

    def ack(self, name):
        if not self.wl.wait(lambda: self.serial is not None, 5):
            raise SystemExit(f"render.py: {name} got no configure")
        self.wl.send(self.xdg, 4, u32(self.serial))
        self.serial = None

    def reposition(self, anchor):
        """Moves it as a menu that follows its button does (xdg_popup.reposition, xdg_wm_base 3), the buffer the same"""
        positioner = self.positioner(anchor)
        self.wl.send(self.popup, 2, u32(positioner, 1))
        self.wl.send(positioner, 0)
        self.ack(self.name)
        self.commit([(0, 0, 1, 1)])

    def on_xdg(self, op, p):
        if op == 0:
            (self.serial,) = struct.unpack_from("=I", p)

    def on_popup(self, op, p):
        if op == 0:
            self.placed = struct.unpack_from("=4i", p)  # relative to the window's geometry

    def destroy(self):
        self.wl.send(self.popup, 0)
        self.wl.send(self.xdg, 0)
        self.destroy_surface()


class Layer(Surface):
    """An overlay layer surface with alpha, at margin (top, left) from the monitor's corner, keyboard left alone"""

    def __init__(self, r, name, size, margin):
        super().__init__(r, name, ARGB)
        self.serial = None
        self.ls = self.wl.new(self.on_ls)
        self.wl.send(r.layer_shell, 0, u32(self.ls, self.surface, 0, 3) + string(name))  # get_layer_surface, overlay
        self.wl.send(self.ls, 0, u32(*size))  # set_size
        self.wl.send(self.ls, 1, u32(1 | 4))  # set_anchor top | left
        self.wl.send(self.ls, 2, i32(-1))  # set_exclusive_zone: not moved by the bar's zone
        self.wl.send(self.ls, 3, i32(margin[0], 0, 0, margin[1]))  # set_margin
        self.wl.send(self.surface, 6)
        if not self.wl.wait(lambda: self.serial is not None, 5):
            raise SystemExit(f"render.py: {name} got no configure")
        self.wl.send(self.ls, 6, u32(self.serial))
        self.allocate(size)

    def on_ls(self, op, p):
        if op == 0:
            self.serial, w, h = struct.unpack_from("=3I", p)

    def move(self, margin):
        """Elsewhere on the monitor, the buffer the same"""
        self.wl.send(self.ls, 3, i32(margin[0], 0, 0, margin[1]))
        self.commit([(0, 0, 1, 1)])

    def resize(self, size):
        """Smaller, as the compositor configures it, with a new buffer"""
        self.serial = None
        self.wl.send(self.ls, 0, u32(*size))
        self.wl.send(self.surface, 6)
        if not self.wl.wait(lambda: self.serial is not None, 5):
            raise SystemExit(f"render.py: {self.name} got no configure for its new size")
        self.wl.send(self.ls, 6, u32(self.serial))
        self.allocate(size)

    def destroy(self):
        self.wl.send(self.ls, 7)
        self.destroy_surface()


class Sharing:
    """The screen through wlr-screencopy on render.py's own connection, without a pause. A capture that starts more than
    0.5 s after the last one ended is a new one, for which the compositor repaints the whole monitor, which would hide
    every stale pixel; so a frame is always pending (copy_with_damage, the frames the compositor draws anyway), and the
    pointer moves a pixel in its corner when nothing else draws. The frames are the compositor's work buffer, kept up
    by damage like the screen's buffers, but not those buffers themselves: kmsgrab reads those where it can"""

    CORNER = 64  # the pointer's corner, in pixels, left out of the comparisons

    def __init__(self, r):
        self.r, self.wl = r, r.wl
        self.sc = Screencopy(r.wl, r.monitor["name"])
        self.box = (0, 0, *r.logical)
        self.frame = None
        self.info = None
        self.flags = 0
        self.serial = 0  # frames requested
        self.latest = None  # (serial, raw bytes, flags) of the last frame copied
        self.nudged = 0.0
        self.side = 0
        self.busy = False

    def on_frame(self, f, op, p):
        if op == 0 and f["info"] is None:  # buffer: format, width, height, stride
            f["info"] = struct.unpack_from("=4I", p)
            f["described"] = self.sc.version < 3
        elif op == 6:  # buffer_done
            f["described"] = True
        elif op == 1:
            (f["flags"],) = struct.unpack_from("=I", p)
        elif op == 2:
            f["ready"] = True
        elif op == 3:
            f["failed"] = True

    def request(self):
        f = {"info": None, "described": False, "flags": 0, "ready": False, "failed": False, "serial": self.serial + 1}
        f["id"] = self.wl.new(lambda op, p: self.on_frame(f, op, p))
        self.wl.send(self.sc.manager, 1, u32(f["id"]) + i32(0) + u32(self.sc.output) + i32(*self.box))
        if not self.wl.wait(lambda: f["described"] or f["failed"], 5) or f["failed"] or f["info"] is None:
            raise SystemExit("render.py: the compositor offers no frame to capture")
        if self.info is None:
            self.info = f["info"]
            fmt, w, h, stride = self.info
            fd = os.memfd_create("hypoland-render-capture", os.MFD_CLOEXEC)
            os.ftruncate(fd, stride * h)
            self.map = mmap.mmap(fd, stride * h)
            pool = self.wl.new()
            self.wl.send(self.sc.shm, 0, u32(pool) + i32(stride * h), [fd])
            os.close(fd)
            self.buffer = self.wl.new()
            self.wl.send(pool, 0, u32(self.buffer) + i32(0, w, h, stride) + u32(fmt))
            self.wl.send(pool, 1)
        self.wl.send(f["id"], 2, u32(self.buffer))  # copy_with_damage
        self.serial += 1
        self.frame = f

    def pump(self):
        """From the dispatch loop: keeps a frame pending and something drawing"""
        if self.busy:
            return
        self.busy = True
        try:
            if self.frame and (self.frame["ready"] or self.frame["failed"]):
                if self.frame["ready"]:
                    self.latest = (self.frame["serial"], bytes(self.map), self.frame["flags"])
                self.wl.send(self.frame["id"], 1)
                self.frame = None
            if self.frame is None:
                self.request()
            elif time.monotonic() - self.nudged > 0.15:
                m = self.r.monitor
                self.side ^= 1
                cx = m["x"] + self.r.logical[0] - 1 - self.side
                cy = m["y"] + self.r.logical[1] - 1
                self.r.dispatch(f"hl.dsp.cursor.move({{x = {cx}, y = {cy}}})", f"movecursor {cx} {cy}")
                self.nudged = time.monotonic()
        finally:
            self.busy = False

    def grab(self):
        """The first frame requested after now, as RGB bytes, width, height"""
        after = self.serial + (1 if self.frame else 0)
        if not self.wl.wait(lambda: self.latest and self.latest[0] > after, 5):
            raise SystemExit("render.py: no captured frame within 5 s")
        _, raw, flags = self.latest
        fmt, w, h, stride = self.info
        rows = range(h - 1, -1, -1) if flags & 1 else range(h)  # y_invert
        rgb = bytearray(w * h * 3)
        # wl_shm formats are little endian: XRGB8888 / ARGB8888 are B G R X in memory, XBGR8888 / ABGR8888 R G B X
        order = (0, 1, 2) if fmt in (0x34324258, 0x34324241) else (2, 1, 0)
        for i, y in enumerate(rows):
            line = raw[y * stride : y * stride + w * 4]
            out = i * w * 3
            for c in range(3):
                rgb[out + c : out + w * 3 : 3] = line[order[c] :: 4]
        return bytes(rgb), w, h

    def masked(self, rgb, w, h):
        """The pointer's corner blacked out"""
        out = bytearray(rgb)
        n = self.CORNER * max(self.r.scale, 1)
        for y in range(max(0, h - n), h):
            out[(y * w + w - n) * 3 : (y * w + w) * 3] = bytes(n * 3)
        return bytes(out)

    def stop(self):
        if self.frame:
            self.wl.send(self.frame["id"], 1)
            self.frame = None


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
        # the monitor's size in its own coordinates: a turned monitor's mode is the panel's, across
        size = (self.monitor["width"] / s, self.monitor["height"] / s)
        self.size = size[::-1] if self.monitor["transform"] % 2 else size
        self.logical = (int(self.size[0]), int(self.size[1]))
        # pixels are compared where window and buffer pixels line up, in a frame of the monitor's own coordinates: the
        # compositor turns the frames it hands out, the scanned-out buffer of a turned monitor comes across
        self.exact = abs(s - round(s)) < 0.01 and (self.monitor["transform"] == 0 or args.grab == "screencopy")
        self.home = self.monitor["activeWorkspace"]["id"]
        used = {c["workspace"]["id"] for c in hyprctl(args.socket, "j/clients")}
        self.ws = next(w for w in (8, 9, 10, 7, 6) if w not in used and w != self.home)
        self.away = next(w for w in (9, 10, 7, 6, 5) if w not in used and w not in (self.home, self.ws))
        try:
            opt = hyprctl(args.socket, "j/getoption decoration:rounding")
            self.rounding = int(opt.get("int", 0))
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            self.rounding = 10
        try:  # translucent pixels show the blur of what is under them (Omarchy's Glassy theme), not the window under
            opt = hyprctl(args.socket, "j/getoption decoration:blur:enabled")
            self.under_unknown = bool(opt.get("bool", opt.get("int", 0)))
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            self.under_unknown = False
        try:  # nor the window under as it drew itself when unfocused windows are dimmed or translucent (an opacity of
            # 0.98 or more is drawn as 1)
            dim = hyprctl(args.socket, "j/getoption decoration:dim_inactive")
            opacity = hyprctl(args.socket, "j/getoption decoration:inactive_opacity")
            if dim.get("bool", dim.get("int", 0)) or float(opacity.get("float", 1)) < 0.98:
                self.under_unknown = True
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            pass
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
        self.wm = self.bind(globs, "xdg_wm_base", 3, self.on_wm)
        self.wm_version = min(globs["xdg_wm_base"][1], 3)
        self.subcompositor = self.bind(globs, "wl_subcompositor", 1)
        self.viewporter = self.bind(globs, "wp_viewporter", 1)
        self.layer_shell = self.bind(globs, "zwlr_layer_shell_v1", 1)
        self.wl.roundtrip()
        self.sharing = None
        plain = self.wl.dispatch

        def dispatch(timeout):
            # with a capture running, its frames are kept going between the events
            if not self.sharing:
                return plain(timeout)
            got = plain(min(timeout, 0.05))
            self.sharing.pump()
            return got

        self.wl.dispatch = dispatch

    def bind(self, globs, iface, version, handler=None):
        if iface not in globs:
            return None
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

    def grab(self, name, how=None):
        """The screen as RGB bytes, width, height"""
        path = os.path.join(self.out, name + ".ppm")
        if (how or self.args.grab) == "screencopy":
            rgb, w, h = self.sharing.grab()
            if name.endswith(("-incremental", "-repainted")):
                rgb = self.sharing.masked(rgb, w, h)
            with open(path, "wb") as f:
                f.write(b"P6\n%d %d\n255\n" % (w, h) + rgb)
            return rgb, w, h
        if (how or self.args.grab) == "kmsgrab":
            subprocess.run(["hypoland-kmsgrab", path], check=True, capture_output=True)
            with open(path, "rb") as f:
                data = f.read()
        else:
            # as the session's user, whose compositor it asks (as root the capture can come back black)
            sock = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
            st = os.stat(sock)
            cmd = ["grim", "-o", self.monitor["name"], "-t", "ppm", "-"]
            if os.geteuid() == 0 and st.st_uid != 0:
                import pwd

                cmd = ["runuser", "-u", pwd.getpwuid(st.st_uid).pw_name, "--"] + cmd
            data = subprocess.run(cmd, check=True, capture_output=True).stdout
            with open(path, "wb") as f:
                f.write(data)
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

    def check_repaint(self, step, repaint=None):
        """The screen now and after a full repaint of the same scene are the same. repaint makes the full repaint, a
        workspace switch away and back by default"""
        pids = self.frozen() if self.args.freeze else set()
        for p in pids:
            os.kill(p, signal.SIGSTOP)
        try:
            self.settle(0.3)
            a, w, h = self.grab(f"{step}-incremental")
            if repaint:
                repaint()
            else:
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

    def check_pixels(self, step, win, under=None, how=None):
        """The focused window shows exactly what it drew (its subsurfaces included), inside its rounding and border.
        Over the window under, its transparent pixels show that one through as premultiplied alpha blends it, to a step"""
        if not self.exact:
            print(f"SKIP  render {step}: pixels need an integer scale ({self.monitor['scale']})", flush=True)
            return
        c = self.client(win.app_id)
        if not c:
            self.failed += 1
            print(f"FAIL  render {step}: {win.app_id} is not mapped", flush=True)
            return
        s = self.scale
        x0 = (c["at"][0] - self.monitor["x"]) * s
        y0 = (c["at"][1] - self.monitor["y"]) * s
        if under:
            cu = self.client(under.app_id)
            under = (under.composed(), under.stride, (cu["at"][0] - self.monitor["x"]) * s, (cu["at"][1] - self.monitor["y"]) * s)
        self.check_image(step, win.app_id, win.composed(), win.w, win.h, win.stride, x0, y0, (self.rounding + 2) * s, under,
                         win.corners((self.rounding + 2) * s), how)

    def check_image(self, step, what, want, w, h, stride, x0, y0, inset=0, under=None, skip=(), how=None):
        """The screen shows want (B G R A rows of w x h pixels) at x0, y0 in its pixels, inside inset and outside the
        boxes skip. Opaque pixels exactly; others over under (its pixels, stride and position) as premultiplied alpha
        blends them, to a step"""
        if not self.exact:
            print(f"SKIP  render {step}: pixels need an integer scale ({self.monitor['scale']})", flush=True)
            return
        screen, sw, sh = self.grab(f"{step}-pixels", how)
        if (how or self.args.grab) == "screencopy" and self.sharing:
            # the pointer's corner, where Sharing moves it to keep frames coming: a cursor Omarchy fades out left a
            # step in the corner of a fullscreen window (lianli, 2026-11-01)
            n = Sharing.CORNER * max(self.scale, 1)
            skip = tuple(skip) + ((sw - n - x0, sh - n - y0, n, n),)
        bad, worst = 0, None
        lo, hi = max(inset, -x0), min(w - inset, sw - x0)  # the columns on the screen
        for y in range(inset, h - inset):
            sy = y0 + y
            if not 0 <= sy < sh or lo >= hi:
                continue
            row = want[y * stride : y * stride + w * 4]
            got = screen[(sy * sw + x0 + lo) * 3 : (sy * sw + x0 + hi) * 3]
            if under and row[3::4] != b"\xff" * w:
                uwant, ustride, ux, uy = under
                for x in range(lo, hi):
                    b, g, r, a = row[x * 4 : x * 4 + 4]
                    if a != 255 and self.under_unknown:
                        continue
                    if any(bx <= x < bx + bw and by <= y < by + bh for bx, by, bw, bh in skip):
                        continue
                    if a == 255:
                        exp = (r, g, b)
                    else:
                        ox, oy = x0 + x - ux, sy - uy
                        if not (0 <= ox < ustride // 4 and 0 <= oy < len(uwant) // ustride):
                            continue  # past the window under: what shows there is not known
                        o = oy * ustride + ox * 4
                        db, dg, dr = uwant[o : o + 3]
                        exp = tuple(min(255, round(v + d * (255 - a) / 255)) for v, d in ((r, dr), (g, dg), (b, db)))
                    shown = tuple(got[(x - lo) * 3 : (x - lo) * 3 + 3])
                    if max(abs(e - g2) for e, g2 in zip(exp, shown)) > (0 if a == 255 else 1):
                        bad += 1
                        worst = worst or (x, y, exp, shown)
                continue
            rgb = bytearray(w * 3)
            rgb[0::3], rgb[1::3], rgb[2::3] = row[2::4], row[1::4], row[0::4]
            exp = bytes(rgb[lo * 3 : hi * 3])
            if got != exp:
                for i in range(0, len(exp), 3):
                    if got[i : i + 3] != exp[i : i + 3]:
                        x = lo + i // 3
                        if any(bx <= x < bx + bw and by <= y < by + bh for bx, by, bw, bh in skip):
                            continue
                        bad += 1
                        worst = worst or (x, y, tuple(exp[i : i + 3]), tuple(got[i : i + 3]))
        if bad == 0:
            os.remove(os.path.join(self.out, f"{step}-pixels.ppm"))
            print(f"PASS  render {step}: {what} shows every pixel it drew", flush=True)
        else:
            self.failed += 1
            print(f"FAIL  render {step}: {bad} pixels of {what} differ from what it drew, first at {worst[0]},{worst[1]}: "
                  f"{worst[2]} shown as {worst[3]}", flush=True)

    def choose_grab(self):
        """kmsgrab reads the buffer the screen scans out, except where the CRTC goes on naming the buffer of the last
        modeset after page flips (radeon's legacy modesetting: lianli showed frames from before the window opened); the
        compositor's frames are captured there (Sharing). Not everywhere: a capture draws through the work buffer, whose
        frame can differ from the one scanned out by a step where a layer is clipped (Galaxy Book)"""
        if self.args.grab == "screencopy":
            self.sharing = Sharing(self)
        if self.args.grab != "kmsgrab":
            return
        drivers = set()
        for card in os.listdir("/sys/class/drm"):
            if card.startswith("card") and "-" not in card:
                try:
                    drivers.add(os.path.basename(os.path.realpath(f"/sys/class/drm/{card}/device/driver")))
                except OSError:
                    pass
        if "radeon" in drivers:
            print("INFO  render: radeon's legacy modesetting does not tell which buffer the screen shows, capturing the "
                  "compositor's frames instead", flush=True)
            self.args.grab = "screencopy"
            self.sharing = Sharing(self)

    def subsurfaces(self, a, rng):
        """Subsurfaces over the window: drawn by themselves in small rectangles, moved, one scaled by a viewport, closed"""
        if not self.subcompositor:
            print("SKIP  render subsurfaces: no wl_subcompositor", flush=True)
            return
        sub = Subsurface(self, "render-sub", a, (48, 40))
        sub.allocate((200, 140))
        sub.fill(5)
        sub.commit()
        a.recommit()
        self.settle(1.0)
        self.check_pixels("subsurface", a)
        self.check_repaint("subsurface")
        for frame in range(12):
            sub.commit([sub.rect(500 + frame, rng.randrange(sub.w), rng.randrange(sub.h), rng.randrange(8, 60), rng.randrange(8, 40))])
        sub.move((150, 96))
        a.recommit()
        self.settle(1.0)
        self.check_pixels("subsurface moved", a)
        self.check_repaint("subsurface moved")
        sub.destroy()
        self.settle(1.0)
        self.check_pixels("subsurface closed", a)
        self.check_repaint("subsurface closed")
        if self.viewporter:
            # buffers drawn at 4.6 times and at half their size: the filter reaches past every damaged rectangle, by
            # several pixels where a texel is magnified
            x = min(a.w // self.scale - 340, 400)
            big = Subsurface(self, "render-magnified", a, (x, 40), viewport=(157, 122))
            big.allocate(None, (34, 26))
            small = Subsurface(self, "render-minified", a, (x + 170, 40), viewport=(157, 122))
            small.allocate(None, (301, 233))
            # and one turned by a quarter (a camera's or a phone's video): its damage is turned with it
            turned = Subsurface(self, "render-turned", a, (x, 180), transform=1)
            turned.allocate((90, 140))
            # and one cut out of a larger buffer and stretched (a video's black bars cut off)
            cropped = Subsurface(self, "render-cropped", a, (x + 170, 180), viewport=(157, 122), source=(30, 20, 60, 45))
            cropped.allocate(None, (120, 90))
            for n, v in enumerate((big, small, turned, cropped)):
                v.fill(6 + n)
                v.commit()
            a.recommit()
            self.settle(1.0)
            self.check_repaint("viewport")
            for frame in range(12):
                big.commit([big.rect(600 + frame, rng.randrange(big.w), rng.randrange(big.h), rng.randrange(1, 4), rng.randrange(1, 4))])
                small.commit([small.rect(700 + frame, rng.randrange(small.w), rng.randrange(small.h), rng.randrange(2, 12), rng.randrange(2, 12))])
                turned.commit([turned.rect(750 + frame, rng.randrange(turned.w), rng.randrange(turned.h), rng.randrange(4, 30), rng.randrange(4, 20))])
                cropped.commit([cropped.rect(780 + frame, rng.randrange(20, 100), rng.randrange(10, 75), rng.randrange(2, 10), rng.randrange(2, 10))])
            self.settle(1.0)
            self.check_repaint("viewport rectangles")
            big.destroy()
            small.destroy()
            turned.destroy()
            cropped.destroy()
            self.settle(1.0)
            self.check_pixels("viewports closed", a)
            self.check_repaint("viewports closed")

    def popup(self, a):
        """A popup over the window, opened and closed"""
        p = Popup(self, "render-popup", a, (a.w // self.scale // 2, a.h // self.scale // 3), (180, 120))
        p.fill(7)
        p.commit()
        self.settle(1.2)
        c = self.client(a.app_id)
        if c and p.placed:
            x0 = (c["at"][0] - self.monitor["x"] + p.placed[0]) * self.scale
            y0 = (c["at"][1] - self.monitor["y"] + p.placed[1]) * self.scale
            self.check_image("popup", "the popup", p.want, p.w, p.h, p.stride, x0, y0)
        self.check_repaint("popup")
        if self.wm_version >= 3:
            p.reposition((a.w // self.scale // 3, a.h // self.scale // 2))
            self.settle(1.2)
            self.check_repaint("popup moved")
        p.destroy()
        self.settle(1.2)
        self.check_pixels("popup closed", a)
        self.check_repaint("popup closed")

    def layer(self):
        """An overlay layer, opaque at the top and clear below, left alone until the compositor clipped it to its pixels
        with alpha, then drawn into where it was clear with only that damaged, moved, made smaller and closed"""
        if not self.layer_shell:
            print("SKIP  render layer: no zwlr_layer_shell_v1", flush=True)
            return
        ns = "hypoland-render-layer"
        layer = Layer(self, ns, (400, 240), (100, 100))
        top = layer.h // 3
        layer.fill(8, clear_rows=(top, layer.h))
        layer.commit()
        self.settle(2.6)  # the alpha bounds settle 2 s after a surface's commits
        box = layer_box(self.args.socket, self.monitor, ns)
        if box:
            self.check_image("layer", "the layer", layer.want, layer.w, top, layer.stride, box[0] * self.scale, box[1] * self.scale)
        self.check_repaint("layer")
        rows = (layer.h * 2 // 3, layer.h * 2 // 3 + 24 * self.scale)
        damage = layer.rect(801, 40 * self.scale, rows[0], layer.w - 80 * self.scale, rows[1] - rows[0])
        layer.commit([damage])
        self.check_repaint("layer drawn")
        self.settle(2.6)
        self.check_repaint("layer settled")
        # a popup of the layer while the layer is clipped to its pixels, as Omarchy's bar (a window across the screen)
        # opens a menu: shown whole, also where it reaches past the layer, then closed
        p = Popup(self, "render-layer-popup", None, (40, layer.h // self.scale - 60), (160, 100), layer=layer)
        p.fill(10)
        p.commit()
        self.settle(1.2)
        if box and p.placed:
            x0, y0 = (box[0] + p.placed[0]) * self.scale, (box[1] + p.placed[1]) * self.scale
            self.check_image("layer popup", "the layer's popup", p.want, p.w, p.h, p.stride, x0, y0)
        self.check_repaint("layer popup")
        p.destroy()
        self.settle(1.2)
        self.check_repaint("layer popup closed")
        # moved while clipped, then smaller with a new buffer
        layer.move((160, 220))
        self.settle(1.2)
        self.check_repaint("layer moved")
        layer.resize((260, 150))
        layer.fill(9, clear_rows=(layer.h // 3, layer.h))
        layer.commit()
        self.settle(1.2)
        self.check_repaint("layer shrunk")
        layer.destroy()
        self.settle(1.2)
        self.check_repaint("layer closed")

    def run(self):
        rng = random.Random(7)
        request(self.args.socket, "dismissnotify")  # the compositor's own notifications, drawn over everything
        self.dispatch('hl.dsp.dpms({action = "on"})', "dpms on")  # a screen that is off shows nothing new
        self.workspace(self.ws)
        # the pointer into the corner, in the outer gap: a cursor drawn into the frame (no cursor plane) is not the windows'
        cx, cy = self.monitor["x"] + self.logical[0] - 1, self.monitor["y"] + self.logical[1] - 1
        self.dispatch(f"hl.dsp.cursor.move({{x = {cx}, y = {cy}}})", f"movecursor {cx} {cy}")
        self.settle(0.3)
        self.choose_grab()
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

        # screenshots as a user takes them (grim, a capture of its own each): the second, after the window drew anew and
        # the pointer moved, shows the new picture. On radeon a cursor moved by itself is a commit, which completed a
        # capture with the frame the capture before had left (the screen of the session check's test window)
        if shutil.which("grim"):
            self.check_pixels("screenshot", a, how="grim")
            a.fill(13)
            a.commit()
            self.dispatch(f"hl.dsp.cursor.move({{x = {cx - 2}, y = {cy}}})", f"movecursor {cx - 2} {cy}")
            self.settle(0.3)
            self.check_pixels("screenshot again", a, how="grim")

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

        self.subsurfaces(a, rng)
        self.popup(a)
        self.layer()

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
        # resized by the compositor (with the windows animation): the window draws at its new size, the area it leaves
        # shows what is under it again
        if addr:
            before = (b.w, b.h)
            self.dispatch(f'hl.dsp.window.resize({{x = 360, y = 260, window = "address:{addr}"}})', f"resizewindowpixel exact 360 260,address:{addr}")
            self.settle(0.4)
            if b.serial is not None:
                size = b.wait_configure()
                if size[0] and size[1]:
                    b.allocate(size)
                    b.fill(4, alpha_rows=(b.h // 3, b.h // 2))
                    b.commit()
            self.settle(1.2)
            if (b.w, b.h) == before:
                self.failed += 1
                print(f"FAIL  render resized: the window was not resized ({b.w}x{b.h})", flush=True)
            self.check_pixels("resized", b, under=a)
            self.check_repaint("resized")
        # a new title while shown: a titlebar (render-configs/titlebars.lua) draws its text again
        self.wl.send(b.top, 2, string("hypoland-render-b with a longer title"))
        self.settle(1.0)
        self.check_repaint("retitled")
        # smaller by itself, as a dialog that drops a part: the space it leaves shows the window under again
        b.allocate((b.w // self.scale // 2, b.h // self.scale // 2))
        b.fill(3)
        b.commit()
        self.settle(1.2)
        self.check_repaint("shrunk")
        b.destroy()
        self.settle(1.5)
        self.check_repaint("closed")

        # a group (Omarchy's SUPER+G): the group bar takes a strip off the window, a second window opens into the group,
        # the tabs switch there and back, the second closes while shown (its fade, the bar losing a tab), the group ends
        self.dispatch("hl.dsp.group.toggle()", "togglegroup")
        a.follow(14)
        self.settle(1.2)
        self.check_pixels("grouped", a)
        self.check_repaint("grouped")
        c = Window(self, "hypoland-render-c")
        w, h = c.wait_configure()
        c.allocate((w or a.w // self.scale, h or a.h // self.scale))
        c.fill(15)
        c.commit()
        c.follow(15)
        self.settle(1.2)
        self.check_pixels("group added", c)
        self.check_repaint("group added")
        self.dispatch("hl.dsp.group.next()", "changegroupactive f")
        a.follow(14)
        self.settle(1.2)
        self.check_pixels("group switched", a)
        self.check_repaint("group switched")
        self.dispatch("hl.dsp.group.next()", "changegroupactive f")
        c.follow(15)
        self.settle(1.2)
        self.check_pixels("group switched back", c)
        c.destroy()
        self.settle(1.5)
        a.follow(14)
        self.settle(0.5)
        self.check_pixels("group closed", a)
        self.check_repaint("group closed")
        self.dispatch("hl.dsp.group.toggle()", "togglegroup")
        a.follow(16)
        self.settle(1.2)
        self.check_pixels("ungrouped", a)
        self.check_repaint("ungrouped")

        # Omarchy's scratchpad (SUPER+S): a window put away into a special workspace, which then slides in over the
        # workspace with the dim behind it, is drawn into in small places there, and slides out again. While it is shown
        # the full repaint is the special workspace hidden and shown again: a workspace switch can hide it (Omarchy sets
        # hide_special_on_workspace_change)
        d = Window(self, "hypoland-render-d", parent=a)  # floating, so the dimmed workspace shows around it
        w, h = d.wait_configure()
        d.allocate((w if w and w < 600 else 400, h if h and h < 600 else 300))
        d.fill(17)
        d.commit()
        d.follow(17)
        a.follow(16)
        self.settle(1.0)
        daddr = (self.client(d.app_id) or {}).get("address")
        if daddr:
            self.dispatch(f'hl.dsp.window.move({{workspace = "special:hypoland-render", follow = false, window = "address:{daddr}"}})',
                          f"movetoworkspacesilent special:hypoland-render,address:{daddr}")
            a.follow(16)
            self.settle(1.2)
            self.check_pixels("scratchpad stored", a)
            self.check_repaint("scratchpad stored")

            def toggle():
                self.dispatch('hl.dsp.workspace.toggle_special("hypoland-render")', "togglespecialworkspace hypoland-render")

            def again():
                toggle()
                self.settle(1.0)
                toggle()

            toggle()
            d.follow(17)
            self.settle(1.2)
            self.check_pixels("scratchpad", d)
            self.check_repaint("scratchpad", again)
            for frame in range(12):
                d.commit([d.rect(200 + frame * 4 + k, rng.randrange(d.w), rng.randrange(d.h), rng.randrange(8, 120), rng.randrange(8, 80)) for k in range(4)])
            self.settle(1.0)
            self.check_pixels("scratchpad rectangles", d)
            self.check_repaint("scratchpad rectangles", again)
            toggle()
            self.settle(1.2)
            self.check_pixels("scratchpad hidden", a)
            self.check_repaint("scratchpad hidden")
        d.destroy()
        self.settle(0.5)

        # fullscreen and back: the window draws at the screen's size and at its own again, the screen changes hands twice
        self.dispatch('hl.dsp.window.fullscreen({action = "set"})', "fullscreen 0")
        a.follow(11)
        self.settle(1.2)
        c = self.client(a.app_id) or {}
        if not c.get("fullscreen") or (a.w // self.scale, a.h // self.scale) != (round(self.size[0]), round(self.size[1])):
            self.failed += 1
            print(f"FAIL  render fullscreen: the window did not go fullscreen (state {c.get('fullscreen')}, {a.w}x{a.h})", flush=True)
        self.check_pixels("fullscreen", a)
        self.check_repaint("fullscreen")
        self.dispatch('hl.dsp.window.fullscreen({action = "unset"})', "fullscreen 0")
        a.follow(12)
        self.settle(1.2)
        self.check_pixels("fullscreen left", a)
        self.check_repaint("fullscreen left")

        a.destroy()
        self.settle(0.5)
        if self.sharing:
            self.sharing.stop()
            self.sharing = None
        self.workspace(self.home)
        return self.failed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--grab", choices=("kmsgrab", "screencopy", "grim"), default="kmsgrab",
                    help="kmsgrab: the buffer the screen scans out; screencopy: the compositor's frames, captured without a pause; "
                    "grim: a capture of its own each time, for which the compositor repaints everything (the repaint checks see nothing)")
    ap.add_argument("--selftest", action="store_true", help="damage one change wrongly, the checks have to fail")
    ap.add_argument("--nearest", action="store_true", help="sample its windows with the nearest texel")
    ap.add_argument("--no-freeze", dest="freeze", action="store_false", help="leave the shell running (a nested compositor has none of its own)")
    args = ap.parse_args()
    raise SystemExit(1 if Render(args).run() else 0)


if __name__ == "__main__":
    main()
