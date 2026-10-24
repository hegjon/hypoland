# Changelog

Changes of Hypoland. Hyprland's own changes are in its [releases](https://github.com/hyprwm/Hyprland/releases);
Hypoland 0.2.0 is based on Hyprland 0.56.0. Numbers are measured on a ThinkPad X200 (Core 2 Duo P8400,
GMA 4500MHD, 1280x800) running Omarchy 4.

## Unreleased

### Added

- Titlebars for Omarchy's floating workspaces. Omarchy draws them with a plugin of its own, which Hypoland cannot
  load, so they are built in with the plugin's interface: the `plugin:hyprbars:*` options, `hl.plugin.hyprbars.add_button()`
  and the `hyprbars:*` window rule effects. Omarchy's config turns them on as it does with the plugin: the app's name or
  the title, buttons to close, maximize and minimize, dragging by the bar, double click to maximize, and dragging a
  maximized window back to its size. Off unless a config enables them (`plugin:hyprbars:enabled`).

### Fixed

- The compositor no longer aborts after a GPU hang in its own drawing. It asked for a GL context that is lost for good
  after a GPU reset, so every later draw failed and the next framebuffer check aborted. Mesa now replaces the hung
  context and the compositor goes on. The X200 hangs now and then while an X11 program draws fullscreen; a 10 hour
  test ended in a crash after 7.7 hours, and 15 forced GPU resets with the fix left the session running.
- Half drawn frames on Intel GPUs from Broadwell on (Mesa `iris`), seen as flicker on a 3200x1800 Dell XPS 13. To
  save a fence per frame, frames on Intel were handed to the display after a `glFlush()`, but iris submits that flush
  on its own thread, so the display could show a frame before the GPU had drawn it. Only crocus (Gen4 to Haswell,
  the X200) still skips the fence.

## 0.2.0 - 2026-10-21

### Faster

- Animations tick once per frame. Every frame already ticks right before it draws, but a timer also ticked every
  millisecond while something animated, up to 16 times per frame at 60 Hz. Workspace switching with animations:
  compositor CPU 14.2% -> 6.1%, the same number of frames.
- The animation tick reads the clock once instead of four times. Without a usable TSC every clock read is a system
  call and a slow HPET read.
- Windows with an opacity of 0.98 or more are drawn fully opaque. The difference cannot be seen, and an opaque
  window is not blended and hides what is behind it. Omarchy gives every active window 0.985.
- The wallpaper is drawn as opaque and the background color is no longer painted under it: the lowest surface of
  the background layer, when it covers the whole monitor without fade or blur. 6.89 -> 5.78 ms of GPU time per
  frame with a window at an opacity of 0.9.
- Faster start of the compositor: it answers IPC about 1 s sooner (1.8-2.1 -> 0.7 s after exec) and uses about 20%
  less CPU in its first seconds.
  - aquamarine no longer probes display connectors the kernel knows are disconnected. Each probe waited for a DDC
    timeout of about 160 ms, twice per connector.
  - Keyboards with the same rules share one keymap instead of compiling their own (5 keyboards on the X200).
  - The "screen share denied" text is rendered when it is first needed, so pango and fontconfig are not loaded at
    every start (about 130 ms of CPU and a thread).
  - XCursor shapes are loaded when they are first used instead of the whole theme.
- Xwayland starts when the first X11 program connects instead of together with the compositor. `DISPLAY` is set
  from the start as before. An unused Xwayland costs 150 ms of CPU and 31 MiB. In an Omarchy session fcitx5 and
  xdg-settings still start it a few seconds after login.

### Changed

- Transparent pixels of a wallpaper show over black instead of over `misc:background_color`.
- The config written for new users (`example/hyprland.lua`) matches Hypoland's defaults: blur, shadows, animations
  and rounded corners are off and the active border is a single color instead of a gradient.
- The Arch package provides and conflicts with `omarchy-hyprland-titlebars`, a Hyprland plugin that needs
  `hyprland=0.56.2` and stopped Omarchy updates. Hypoland has no plugins; Omarchy shows no titlebars without it.
- The Arch package lists `wf-recorder` as an optional dependency: gpu-screen-recorder does not start on GLES 2
  hardware, and Omarchy records with `wf-recorder` instead when it is installed.

### Fixed

- Security and crash fixes from upstream Hyprland: an overflow in the X11 WM hints, new input grabs while the
  session is locked, crashes with a bell on a null surface, screen sharing on a removed monitor and Lua errors that
  are not strings, a leaked input capture fd and permission state kept after a client is gone.
- More of them: a crash in cursor capture after a monitor is removed, activation tokens with invalid serials are
  rejected (no focus stealing with made-up tokens), dmabuf plane fds are owned through buffer creation (no leaked
  or double-closed fds on bad buffers).
- Other fixes from upstream Hyprland: screen recording could keep direct scanout blocked, blur lost xray while a
  window faded out, the cursor image did not follow a cursor theme change, X11 floating windows at 0,0 were
  misplaced, X11 modal windows and urgency hints, primary selection with data control and old wlr clients,
  `groupbar:disable_when_only`, tag rules that stopped matching, silent moves away from the focused window and
  the scrolling layout's scroll inhibitor. `input:scroll_factor` goes up to 100 and spring curves take `damping`
  (`dampening` still works). Also: X11 clipboards were reflected back to X11, windows were maximized on map,
  keyboard focus stayed with a pointer constraint under an exclusive layer, multi-key binds shadowed each other,
  the cursor lost focus in a few cases, the "move" rule ignored the "size" rule, master layout window drags and the
  scrolling layout's fullscreen position after the work area changed.
- Windows, layers and popups that close while the screen is off (DPMS, e.g. a locked laptop) no longer keep a
  snapshot of the size of the monitor in GPU memory until the screen comes back: 60 windows closed with the screen
  off cost 474 MB on a 1920x1080 ThinkPad T550, now nothing.
- A package built after a build with another prefix (e.g. `/usr/local`) installed a session file that pointed at
  that prefix and did not start: the session file is generated in the build directory now.
- No more "pixman_region32_init_rect: Invalid rectangle passed" in the log when many windows share a workspace:
  a window squeezed below its border and gaps has a negative size, it is skipped before it reaches pixman.
- Screen recording with `wf-recorder` on a monitor with a scale other than 1 made a new capture session for every
  frame and none of them were freed. Sessions of programs that had quit were never freed either. A 7 hour test on
  the ThinkPad T550 (scale 1.5) collected 13,500 sessions; the compositor grew by 21 MiB and its CPU time with a
  60 fps client went from 8% to 27%, as every frame and every timer went through all sessions and their timers.
  Now a recording uses one session and it is freed when the program quits.
- Fixes from upstream aquamarine: input could stop after switching to a text console and back, a use after free
  when an output goes away with a frame pending, stale state on a monitor that is plugged in again, a leaked fd
  of CPU-side buffers and a crash when logging without a backend.

### Other

- The web page's FAQ says why these changes are not part of Hyprland.
- The web page's FAQ says that Hyprland plugins do not work and which protocols input tools can use instead.
- The web page's FAQ says how to record the screen (`wf-recorder`) and why Omarchy's floating workspaces have no
  titlebars.
- The documentation and the help of `hyprctl` and `start-hypoland` are up to date: `hyprctl keyword` is not
  available with a Lua config (use `eval`), plugin requests always fail, the splash text is off by default rather
  than removed.

## 0.1.0 - 2026-09-28

The first release: Hyprland 0.56.0 for GPUs that only support OpenGL ES 2.0 / OpenGL 2.1.

- The renderer and all shaders run on OpenGL ES 2.0 / GLSL ES 1.00, the embedded aquamarine as well.
- Drop-in for Hyprland: the same `hyprland.lua` config, `hyprctl`, IPC sockets, JSON output, event names and
  `XDG_CURRENT_DESKTOP=Hyprland`. Options of removed features are accepted and ignored.
- Removed: color management and HDR, the ICC 3D LUT, motion blur, the plugin system and hyprpm, the blur variants
  ripple, water, fluid_jar, prism and acrylic (they fall back to dual Kawase), the logo background and the default
  wallpapers, the welcome app, update news and donation popup.
- Off by default: blur, shadows, animations, the splash text and hyprcursor. `quirks:skip_non_kms_dmabuf_formats`
  defaults to off.
- Frames are drawn straight into the scanout buffer when nothing needs the work buffer, only the damage is cleared,
  and shm textures are double buffered (Chromium's compositor CPU 26.8% -> 12.8%).
- Less memory: no second EGL context for the primary GPU, no glslang, the shader compiler is released after use,
  fewer and smaller GPU buffers.
- The binaries are `hypoland` and `start-hypoland`, `start-hyprland` is a symlink. `hyprctl version` adds
  `Hypoland 0.1.0, based on Hyprland 0.56.0`.
- The release workflow attaches a source tarball to Hypoland's releases.
