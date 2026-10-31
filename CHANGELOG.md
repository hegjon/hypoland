# Changelog

Changes of Hypoland. Hyprland's own changes are in its [releases](https://github.com/hyprwm/Hyprland/releases);
Hypoland 0.2.0 is based on Hyprland 0.56.0. Numbers are measured on a ThinkPad X200 (Core 2 Duo P8400,
GMA 4500MHD, 1280x800) running Omarchy 4.

## Unreleased

### Faster

- Closing a window no longer repaints the whole screen while it fades out: only where the fading window is drawn. On a
  Dell XPS 13 (3200x1800) the GPU is busy 50 instead of 73 ms over the second after a window closes.
- Animations show their first step in the first frame. A frame reaches the screen at the next vblank, up to a refresh
  after it is drawn, but animations took their values for the moment it was drawn, in whole milliseconds, so a frame
  drawn right after something began to animate showed the start: a focus change among many windows showed the new
  border colour a frame later whenever the compositor answered within about 2 ms. Values are now taken for the vblank
  the frame is shown at. A focus change among 10 to 40 floating terminals shows in 1.8 to 2.7 ms instead of 13 to 14 on
  a ThinkPad T550 and 2.1 to 2.8 instead of 10 to 18 on a Dell XPS 13, and Omarchy's terminal has opened 19 and 31 ms
  sooner there.
- Many small terminals that print cost much less CPU on the X200. foot scrolls by showing a new buffer further on in its
  memory for every line, and the compositor set every new buffer up to be read in place, which costs more than copying
  a small window. A small window that keeps sending new buffers is copied now; a large one, or one that reuses its
  buffers, is still read in place. With 10, 20 and 40 terminals printing, the compositor takes 1.4, 2.0 and 3.2 ms a
  frame instead of 2.5, 3.4 and 5.4 on the X200 (stock Hyprland 0.57.0: 1.9, 2.3 and 3.4), a fifth less on a Dell
  Chromebook 11 and a Mac mini 2014 with 40.
- Closed windows give their memory back: the heap was only trimmed after uploads, which windows read in place never
  make. It is trimmed a few seconds after the last closed window now, 1.5 MB less memory at the end of a benchmark run.

- A focus change under Omarchy's input method no longer compiles and writes out the keyboard layout again. fcitx5
  grabs the keyboard and recreates its virtual keyboard with the keymap it got back on every focus change, and the
  compositor compiled that 100 kB of text, wrote it twice in two formats into four shared-memory files, copied it once
  more for the grab, and compared the whole text against a copy kept per client keyboard. The text and files are now
  made once per compiled keymap and shared, a virtual keyboard whose text matches reuses the keymap, and the key handler
  asks the shortcuts-inhibit protocol once per key instead of once per bind. The `activelayout` event is only sent when
  a keyboard's layout changes: it came twice per focus change, and Omarchy's bar runs `hyprctl -j devices` for each. A
  focus change shows 0.1 to 0.4 ms sooner at idle (Dell Chromebook 11 6.3 -> 5.9 ms, Mac mini 2014 2.3 -> 2.1) and 1 to
  3 ms sooner while the editor and log of the `dev` workload draw (Chromebook 12.7 -> 9.6, Mac mini 5.6 -> 4.0, ThinkPad
  T550 4.4 -> 3.5), with 3 to 7% less compositor CPU there, 0.6 to 1.4 points less CPU for the whole session (the
  bar's `hyprctl` runs), and about 1 MB less memory at the end of a run.
- A panel, dock or notification layer that is mostly transparent no longer costs the GPU its whole area on every
  frame under it: once it has not changed for a moment the compositor finds where its pixels are and draws only that
  part. Omarchy's shell keeps its bar's window across the whole screen, and its dock and notification column mapped
  while empty, which cost the X200 more GPU time per frame than the window under them: a full-window frame went
  from 8.4 to 3.4 ms of GPU time there (`HYPOLAND_ALPHA_BOUNDS=0` turns it off).
  The search for those pixels runs between frames in small pieces, so the first thing done after a panel changed does not
  wait for it: Omarchy's menu closes 2.6 ms sooner on the X200 and a notification shows 6 ms sooner.
- Terminals and Qt programs that draw on the CPU are shown without a copy on Intel GPUs without a last-level cache too
  (GM45, Bay Trail): the compositor writes their changed cache lines back itself instead of copying the window. A Qt
  window scrolling on a Dell Chromebook 11 took 13% of a CPU, now 4%; a scrolling terminal 5% instead of 7%.
- Windows that change in many small places at once cost much less CPU on Intel GPUs up to Haswell (Mesa `crocus`):
  every draw and every upload of a shm window was repeated per damage rectangle, and there a call costs far more than
  the pixels in it. The damage is merged into a few strips now. 60 small squares moving in a Qt window took 59% of
  the X200's CPU, now 32%, and the window got 55 instead of 37 fps. Other GPUs keep the exact rectangles: on a
  3200x1800 screen merging would copy the whole window instead of the squares.
- A surface's damage rectangles are made into a region once per commit instead of one at a time as they arrive,
  which cost the square of their number: Qt Quick's software backend sends one per changed item. The same 60
  squares: 32% -> 19% on the X200 (59% before both changes, and 60 instead of 37 fps), 30% -> 24% on a Dell XPS 13.
- A window that stopped changing gives back the second texture its updates go into (shm windows, such as foot, GTK 3
  and Qt Widgets programs), after one or two seconds. Three terminals that printed something and then sat idle add
  8 instead of 16 MiB of GPU memory on a ThinkPad T550, 24 instead of 48 MiB on a Dell XPS 13 at 3200x1800 and 6
  instead of 8 MiB on the X200. On integrated graphics that is system memory.
- A cursor that a key press hid (Omarchy sets `cursor.hide_on_key_press`) stays hidden when a layer or a popup maps
  or unmaps. That simulates a mouse move to update the pointer focus, which showed the cursor again, and the next key
  hid it with a frame that repainted everything the other screen buffer missed. A screen recorder, or the benchmark's
  screencopy, waiting for that frame blocked the compositor in the copy while the shell's reply waited: Omarchy's menu
  was gone 31 ms after Escape on the X200, now 6 ms, the same as stock Hyprland.
- Freed memory stays with the compositor for a few seconds instead of going back to the kernel at once. Mesa
  uploads a shm window into an idle texture through a temporary of the window's size that it allocates and frees per
  upload on Intel GPUs from Gen 5 on (`crocus`, `iris`), and the kernel faulted and cleared it in again for every
  frame: two thirds of the compositor's time under a scrolling Qt software window on a Bay Trail Chromebook, 46% of
  its CPU against 18% for stock Hyprland. Now 16%, and 29% instead of 54% for GTK 3. The heap is trimmed once no
  upload has come for five seconds, and a second after a shm window closes that was larger than any still updating,
  so idle memory is as before.
- Uploads and draws are merged into a few strips on `r600` too, as on `crocus`: there every rectangle of a shm
  upload is a staging texture and a blit. 60 small squares moving in a Qt window took 82% of an A8-6600K's CPU
  (48% for stock Hyprland), now 26%.
- The compositor reads the clock once per frame instead of eight times: the presentation time is converted without
  reading it, and the frame scheduler shares its one read with the render, the animation tick and the timers. On
  the X200, where every read is a system call (HPET clocksource), a GPU client at 60 fps costs 2.82% instead of
  2.88% of the CPU, video and workspace switching 2% less too.
- Windows drawn by the CPU (shm: terminals such as foot, GTK 3, Qt Widgets, Qt Quick's software backend, Chromium
  without a GPU) cost the compositor a third to a half less on Intel GPUs, Radeon r600 and the Adreno X1: their textures live in linear
  buffers the compositor fills itself instead of Mesa tiling every update on the CPU. Scrolling GTK 3 on a ThinkPad T550
  19.7% -> 13.0%, on a Mac mini 2014 28% -> 11%; 60 moving squares in a Qt software window on a Radeon HD 8570D 26% ->
  7%, on the X200 19.6% -> 11.1%.
- Clients whose shared memory pools are sealed against shrinking (foot, Qt) are drawn straight from their own memory,
  with no copy at all, on Intel GPUs with an LLC and on Radeon: a fast-scrolling foot costs the compositor 4% of a core
  instead of 16% on a Dell XPS 13 and 2.6% instead of 12% on the Radeon desktop, a scrolling Qt software window 3.7%
  instead of 10.2% on a ThinkPad T550, resizing a terminal next to a GL window 21% instead of 34% on the XPS. Not on the X200 or Bay Trail, whose GPUs do not see what the CPU wrote until the caches
  are flushed. `HYPOLAND_SHM_TEXTURE=0` and `HYPOLAND_SHM_ZEROCOPY=0` in the session environment switch the two off.
- 1.6 MiB less memory at idle: the linker drops code nothing refers to (the binary 15.0 -> 13.6 MB), the keyboard layout
  is compiled once instead of twice per config reload, and the table of monitor makers is built into the binary instead
  of into the heap at startup (X200: 44.7 -> 43.1 MiB Pss).

### Added

- Render checks in the session check of `hypoland-bench`: windows of the check's own, drawn pixel by pixel, through
  whole buffers, small updates, new buffers, a transparent dialog, a move and a close; every step has to show exactly
  what was drawn and match a full repaint of the same scene, read from the buffer the screen scans out.
- Configs written for Hyprland 0.57.0 load without errors: the `layers` category, `decoration:blur:proportional`,
  `input:swallow_focus_click`, `input:tablet:enabled`, `binds:client_requested_fs_uses_layout_handler`,
  `render:async_commit` (accepted, not available), `binds:workspace_back_and_forth` and `scrolling:follow_focus` with
  their new 0/1/2 values, `hl.get_devices()`, `hl.dsp.reload_config()`, the `no_glow` window rule, a workspace's
  `addressable_name`, a monitor's `mode` and `hardware_details`, and the events `window.update_state`,
  `window.minimize`, `workspace.created_early` and `config.unload`. Most of it is 0.57.0's own code; 49 of its commits
  are in, the rest is listed with a decision in `docs/port-0.57.0.md`.
- `hypoland-bench`, a second package of the same build: the benchmark and the session checks (`hypoland-measure`),
  the soak runs (`hypoland-soak`, `hypoland-soak-ab`, `hypoland-energy-meter`) and `hypoland-kmsgrab`, so the test
  machines carry them at the version of the compositor instead of copies in home directories. The workloads'
  clients are optional dependencies; a workload whose client is missing is skipped, as before.

- Titlebars for Omarchy's floating workspaces. Omarchy draws them with a plugin of its own, which Hypoland cannot
  load, so they are built in with the plugin's interface: the `plugin:hyprbars:*` options, `hl.plugin.hyprbars.add_button()`
  and the `hyprbars:*` window rule effects. Omarchy's config turns them on as it does with the plugin: the app's name or
  the title, buttons to close, maximize and minimize, dragging by the bar, double click to maximize, and dragging a
  maximized window back to its size. Off unless a config enables them (`plugin:hyprbars:enabled`).
- `ghostty-scroll`, the benchmark's terminal scrolling in Ghostty (a GTK 4 window drawn by Ghostty's own OpenGL
  renderer, which needs OpenGL 3.3, so not on the X200), and `kitty-scroll`, the same in kitty (OpenGL 3.3 too), next to
  foot's `terminal-scroll` and `alacritty-scroll`.

### Changed

- `start-hypoland` no longer accepts `--no-nixgl` and `--force-nixgl`, the options of Hyprland's `start-hyprland`
  for Nix, which Hypoland removed. Like any option it does not know, they are ignored.

### Fixed

- Small updates of a window drawn straight from its memory (zero copy: foot, Qt's software windows and other shm
  clients whose memory can be shared with the GPU) could stay off the screen until something else redrew that place. The
  compositor took the update's damage to write the client's caches back and left none for the redraw. Found by the new
  render checks, which drew 96 small rectangles of which the X200 showed about 20.
- At a fractional scale (1.5 on a ThinkPad T550 and a T460s) every small update of a window left a thin rim of its old
  colour around it: a scaled window is filtered, so the pixels just outside the update change too, but they were not
  redrawn. A scaled window's damage now reaches a pixel or two further.
- On the Galaxy Book (freedreno) the edges in a window's contents were drawn a colour step off, and next to a small
  update the old colour could stay mixed in. Windows drawn at their own size now take the nearest pixel of their buffer
  instead of a filtered one, which is exact on every GPU and the cheaper fetch.
- The compositor could be killed in the middle of a session without a trace, and the session started over with every
  window gone. It runs with realtime priority, which rtkit grants only with a limit on how long it may run without a
  pause, and the kernel stops a thread that passes the limit inside a single long system call (in a graphics driver, for
  instance) with SIGKILL before the compositor can give the priority back. A Dell XPS 13 lost 3 of 8 sessions of the
  benchmark that way one morning, and reading 2 GB through `hyprctl eval` did it every time. A thread of its own now
  takes the priority away once the compositor has been busy for 40 ms without a pause, which also stops the kernel's
  count in the middle of such a call, and asks for it again when the compositor rests. The priority itself stays: without
  it a Dell Chromebook 11 shows a workspace switch in 5.8 instead of 2.9 ms, a focus change among 40 windows in 16.5
  instead of 9.7 and a closing window in 21 instead of 15, and the other machines switch 5 to 25% slower.
- The compositor crashed when the session ended while the shell's layers were still on the screen: shutting down
  forgets every layer before its client is gone, and a layer then freed itself in the middle of its own unmap. On an
  A8-6600K desktop with an AMD Radeon HD 8570D the session's end crashed 7 times in 8 before, none in 8 after. Nothing
  showed it, the session was ending anyway, but each left a core dump and skipped the rest of the shutdown.
- A shell panel the compositor leaves out because it is fully transparent (Omarchy's empty notification column, its
  hidden dock) got no frame callbacks while it was left out, so a client that asked for one without drawing anything new
  waited for its next change.
- Old characters flashed up in terminals on the X200 and other Intel GPUs without a last-level cache (GM45, Bay Trail)
  while a line was rewritten in place, as in progress bars. The compositor shows such windows straight from the
  client's memory and writes the changed lines out of the CPU caches first, but only those of the frame itself; foot
  also repaints the previous frame's changes into the buffer it reuses, and those stayed in the caches. Now everything
  changed since the buffer was last shown is written out. In a check that rewrites random lines in foot, 15 of 15 runs
  on the X200 showed stale lines before, none after.
- A monitor rule with `bitdepth = 10` crashed the compositor on an output whose planes take a 10-bit format (Intel
  from Broadwell on, and headless outputs): GLES 2 has no 10-bit framebuffer format, so the first frame hit an
  incomplete framebuffer. The setting is ignored with a warning now and the monitor stays at 8 bit.
- The compositor no longer aborts after a GPU hang in its own drawing. It asked for a GL context that is lost for good
  after a GPU reset, so every later draw failed and the next framebuffer check aborted. Mesa now replaces the hung
  context and the compositor goes on. The X200 hangs now and then while an X11 program draws fullscreen; a 10 hour
  test ended in a crash after 7.7 hours, and 15 forced GPU resets with the fix left the session running.
- Half drawn frames on Intel GPUs from Broadwell on (Mesa `iris`), seen as flicker on a 3200x1800 Dell XPS 13. To
  save a fence per frame, frames on Intel were handed to the display after a `glFlush()`, but iris submits that flush
  on its own thread, so the display could show a frame before the GPU had drawn it. Only crocus (Gen4 to Haswell,
  the X200) still skips the fence.

### Other

- The web page shows the comparison with stock Hyprland 0.56.2, lists the GPUs Hypoland is tested on besides the
  X200, says that older GLES 3 hardware or little memory can be a reason for Hypoland too, and links the releases.

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
