# A GTK 3 or GTK 4 window with a long text: scrolls it at a constant speed, or with "spinner" keeps it still under
# a spinner. Prints the renderer GTK picked and every 5 s its frame rate, the way weston-simple-egl does. With
# "check" it draws on the test color.
import sys

import gi
from gi.repository import GLib

version, mode = sys.argv[1], "".join(sys.argv[2:3])
GTK3 = version == "3.0"
# the app id of the window, set before GTK starts
GLib.set_prgname(f"hypoland-gtk{version[0]}-test")
gi.require_version("Gdk", version)
gi.require_version("Gtk", version)
from gi.repository import Gdk, Gtk

TEXT = "\n".join(f"{i:5}  the quick brown fox jumps over the lazy dog {i * 7919 % 100000:05}" for i in range(1, 2001))
SPEED = 0 if mode == "spinner" else 400  # pixels per second

if mode == "check":
    css = Gtk.CssProvider()
    style = "window, textview, textview text { background: #ff00ff; color: #202020; }"
    if GTK3:
        css.load_from_data(style.encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    else:
        css.load_from_string(style)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)

view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True)
view.get_buffer().set_text(TEXT)
scrolled = Gtk.ScrolledWindow(vexpand=True)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
window = Gtk.Window(title="Hypoland GTK test")
window.set_default_size(1200, 800)
start = last = count = 0


# runs once per frame, frames come with the compositor's frame callbacks
def tick(widget, clock):
    global start, last, count
    now = clock.get_frame_time()
    if not last:
        start = now
        print("renderer:", "cairo" if GTK3 else type(window.get_renderer()).__name__.removesuffix("Renderer").lower(), flush=True)
    else:
        adj = scrolled.get_vadjustment()
        y = adj.get_value() + SPEED * (now - last) / 1e6
        adj.set_value(0 if y >= adj.get_upper() - adj.get_page_size() else y)
        count += 1
        if now - start >= 5e6:
            print(f"{count} frames in 5 seconds: {count * 1e6 / (now - start):.1f} fps", flush=True)
            start, count = now, 0
    last = now
    return True


scrolled.add_tick_callback(tick)
widgets = [scrolled]
if mode == "spinner":
    spinner = Gtk.Spinner()
    spinner.set_size_request(48, 48)
    spinner.start()
    widgets.insert(0, spinner)
if GTK3:
    scrolled.add(view)
    for w in widgets:
        box.pack_start(w, w is scrolled, True, 0)
    window.add(box)
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    Gtk.main()
else:
    loop = GLib.MainLoop()
    scrolled.set_child(view)
    for w in widgets:
        box.append(w)
    window.set_child(box)
    window.connect("close-request", lambda _: loop.quit())
    window.present()
    loop.run()
