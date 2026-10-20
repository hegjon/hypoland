# Changelog

Changes of Hypoland. Hyprland's own changes are in its [releases](https://github.com/hyprwm/Hyprland/releases);
Hypoland 0.1.0 is based on Hyprland 0.56.0. Numbers are measured on a ThinkPad X200 (Core 2 Duo P8400,
GMA 4500MHD, 1280x800) running Omarchy 4.

## Unreleased

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
- The Arch package provides and conflicts with `omarchy-hyprland-titlebars`, a Hyprland plugin that needs
  `hyprland=0.56.2` and stopped Omarchy updates. Hypoland has no plugins; Omarchy shows no titlebars without it.
- The Arch package lists `wf-recorder` as an optional dependency: gpu-screen-recorder does not start on GLES 2
  hardware, and Omarchy records with `wf-recorder` instead when it is installed.

### Fixed

- Security and crash fixes from upstream Hyprland: an overflow in the X11 WM hints, new input grabs while the
  session is locked, crashes with a bell on a null surface, screen sharing on a removed monitor and Lua errors that
  are not strings, a leaked input capture fd and permission state kept after a client is gone.
- Other fixes from upstream Hyprland: screen recording could keep direct scanout blocked, blur lost xray while a
  window faded out, the cursor image did not follow a cursor theme change, X11 floating windows at 0,0 were
  misplaced, X11 modal windows and urgency hints, primary selection with data control and old wlr clients,
  `groupbar:disable_when_only`, tag rules that stopped matching, silent moves away from the focused window and
  the scrolling layout's scroll inhibitor. `input:scroll_factor` goes up to 100 and spring curves take `damping`
  (`dampening` still works).

### Other

- The release workflow attaches the source tarball to Hypoland's own releases.
- The web page's FAQ says why these changes are not part of Hyprland.
- The web page's FAQ says that Hyprland plugins do not work and which protocols input tools can use instead.

## 0.1.0 - 2026-09-28

The first release: Hyprland 0.56.0 for GPUs that only support OpenGL ES 2.0 / OpenGL 2.1.

- The renderer and all shaders run on OpenGL ES 2.0 / GLSL ES 1.00, the embedded aquamarine as well.
- Drop-in for Hyprland: the same `hyprland.lua` config, `hyprctl`, IPC sockets, JSON output, event names and
  `XDG_CURRENT_DESKTOP=Hyprland`. Options of removed features are accepted and ignored.
- Removed: color management and HDR, the ICC 3D LUT, motion blur, the plugin system and hyprpm, the blur variants
  ripple, water, fluid_jar, prism and acrylic (they fall back to dual Kawase), the welcome app, update news and
  donation popup.
- Off by default: blur, shadows, animations and hyprcursor. `quirks:skip_non_kms_dmabuf_formats` defaults to off.
- Frames are drawn straight into the scanout buffer when nothing needs the work buffer, only the damage is cleared,
  and shm textures are double buffered (Chromium's compositor CPU 26.8% -> 12.8%).
- Less memory: no second EGL context for the primary GPU, no glslang, the shader compiler is released after use,
  fewer and smaller GPU buffers.
- The binaries are `hypoland` and `start-hypoland`, `start-hyprland` is a symlink. `hyprctl version` adds
  `Hypoland 0.1.0, based on Hyprland 0.56.0`.
