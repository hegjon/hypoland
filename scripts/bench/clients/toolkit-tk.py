# The Tk counterpart of toolkit.py and toolkit.qml. Tk draws only through X11 on Linux, so its window always comes
# through Xwayland, drawn with core X11 requests (the text with Xft through XRender). Modes:
#   canvas  a canvas with a text that stays still under 60 small moving squares. The canvas collects what changed into
#           one bounding box and redraws that into a new pixmap, which it copies to the window: with the squares all over
#           it, close to the whole window on every frame. Prints the windowing system and every 5 s its frame rate, the
#           way weston-simple-egl does. An X11 client gets no frame callbacks: it moves the squares 60 times a second by
#           its own timer, and the frame rate is that pace, not what the compositor shows
#   check   the same on the test color
#   menu    the test color without squares, for the check of a menu and a dialog. Prints where the window is once it
#           has stayed there for a second ("window X Y W H", in the root coordinates of X11), then waits. When the file
#           tk-menu appears next to this script it posts a menu (#00ff00) at a fifth of the window and prints "menu X Y W
#           H"; when tk-dialog appears it takes the menu down, opens a dialog (#00ffff) that belongs to the window and
#           prints "dialog W H"
import colorsys
import os
import sys
import time
import tkinter as tk

MODE = "".join(sys.argv[1:2]) or "canvas"
HERE = os.path.dirname(os.path.abspath(__file__))
SQUARES = 0 if MODE == "menu" else 60
SIZE = 24
RATE = 60  # moves of the squares per second
TEXT = "\n".join(f"{i:5}  the quick brown fox jumps over the lazy dog {i * 7919 % 100000:05}" for i in range(1, 61))
TEST, MENU, DIALOG = "#ff00ff", "#00ff00", "#00ffff"

root = tk.Tk(className="hypoland-tk-test")
root.title("Hypoland Tk test")
root.geometry("1200x800")
canvas = tk.Canvas(root, background=TEST if MODE in ("check", "menu") else "#1e1e1e", highlightthickness=0, borderwidth=0)
canvas.pack(fill="both", expand=True)
canvas.create_text(8, 8, anchor="nw", text=TEXT, font=("monospace", 10), fill="#202020" if MODE != "canvas" else "#d0d0d0")


def color(i):
    r, g, b = colorsys.hls_to_rgb(i / SQUARES, 0.5, 0.8)
    return f"#{int(r * 255):02x}{int(g * 255):02x}{int(b * 255):02x}"


squares = [canvas.create_rectangle(0, 0, SIZE, SIZE, fill=color(i), width=0) for i in range(SQUARES)]


# a position going back and forth between 0 and range, as in toolkit.qml
def bounce(p, r):
    m = p % (2 * r)
    return m if m < r else 2 * r - m


t0 = base = start = time.monotonic()
moves = count = 0
started = False


def tick():
    global base, start, moves, count, started
    now = time.monotonic()
    if not started:
        print(f"renderer: {root.tk.call('tk', 'windowingsystem')} (Tk {tk.TkVersion})", flush=True)
        started = True
    t = now - t0
    w, h = max(canvas.winfo_width() - SIZE, 1), max(canvas.winfo_height() - SIZE, 1)
    for i, item in enumerate(squares):
        x = bounce(i * 97 + (80 + i * 37 % 200) * t, w)
        y = bounce(i * 61 + (60 + i * 53 % 200) * t, h)
        canvas.coords(item, x, y, x + SIZE, y + SIZE)
    moves += 1
    count += 1
    if now - start >= 5:
        print(f"{count} frames in 5 seconds: {count / (now - start):.1f} fps", flush=True)
        start, count = now, 0
    # the next move on the 60 Hz grid; one that falls behind by more than a move starts a new grid
    due = base + moves / RATE
    if now > due + 1 / RATE:
        base, moves = now, 0
        due = now + 1 / RATE
    root.after(max(1, round((due - time.monotonic()) * 1000)), tick)


state = "mapping"
geometry = None
since = 0.0
menu = dialog = None


def where(widget):
    return widget.winfo_rootx(), widget.winfo_rooty(), widget.winfo_width(), widget.winfo_height()


# the steps of the menu mode, polled ten times a second
def step():
    global state, geometry, since, menu, dialog
    now = time.monotonic()
    if state == "mapping" and canvas.winfo_viewable():
        # the window manager places and sizes the window after it maps
        g = where(canvas)
        if g != geometry:
            geometry, since = g, now
        elif now - since >= 1:
            print("window %d %d %d %d" % g, flush=True)
            state = "window"
    elif state == "window" and os.path.exists(os.path.join(HERE, "tk-menu")):
        x, y, w, h = geometry
        menu = tk.Menu(root, tearoff=0, background=MENU, foreground="#202020", activebackground=MENU,
                       activeforeground="#202020", borderwidth=0, activeborderwidth=0, relief="flat", font=("sans", 14))
        for label in ("Open", "Save", "Save as", "Print", "Close", "Quit"):
            menu.add_command(label=label)
        menu.post(x + w // 5, y + h // 5)
        state = "menu"
        since = now
    elif state == "menu" and now - since >= 0.5:
        print("menu %d %d %d %d" % where(menu), flush=True)
        state = "posted"
    elif state == "posted" and os.path.exists(os.path.join(HERE, "tk-dialog")):
        menu.unpost()
        dialog = tk.Toplevel(root, background=DIALOG)
        dialog.title("Hypoland Tk dialog")
        dialog.geometry("400x300")
        dialog.transient(root)
        dialog.attributes("-type", "dialog")
        state = "dialog"
    elif state == "dialog" and dialog.winfo_viewable():
        print("dialog %d %d" % (dialog.winfo_width(), dialog.winfo_height()), flush=True)
        state = "done"
    root.after(100, step)


if MODE == "menu":
    root.after(100, step)
else:
    root.after(1, tick)
root.mainloop()
