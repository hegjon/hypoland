# AGENTS.md

Instructions for coding agents working on Hypoland. `CLAUDE.md` imports this file.

# Hypoland

Hypoland is a fork of Hyprland that targets old GPUs limited to **OpenGL ES 2.0 / OpenGL 2.1**
(Intel Gen4/Gen4.5: GMA X3100 / 965GM, GMA 4500MHD / GM45). Upstream Hyprland requires GLES 3.x.
Hypoland's renderer and shaders are GLES 2.0 / GLSL ES 1.00 only; that port is done and runs on the X200.

## Hardware

- **Dev machine:** this desktop. All editing and compiling happens here.
- **Test machines:** a ThinkPad X200 (GM45 / GMA 4500MHD, Mesa `crocus`, GLES 2 only: stock Hyprland fails to
  start on it), the main target, and since October 2026 a ThinkPad T550 (Intel HD 5500, `iris`) and an HP EliteBook
  8560p (Radeon HD 6470M, `r600`), both with GLES 3. They run Omarchy on the Hypoland package through SDDM and
  are reached over ssh by an alias (`x200`, `t550`, `elitebook`, also as `root@`). The EliteBook is retired since
  2026-10-27: its GPU locked up twice under the overnight A/B of 2026-10-26 (22:10 and 22:15, stock Hyprland's
  `resize`), and since then the driver's first ring test fails on every boot (`ring 0 test failed
  (scratch(0x8504)=0xCAFEDEAD)`, `disabling GPU acceleration`), after a cold start without battery and with
  `radeon.dpm=0 radeon.pcie_gen2=0` too, and the BIOS screens show vertical stripes. Its BIOS has no setting for the
  Intel GPU, so the screen only runs through the Radeon. lianli below is the r600 machine since then.
  A Dell XPS 13 9343 (Intel HD 5500, `iris`, 3200x1800 at scale 2) joined on 2026-10-23 as `xps` (also as `root@xps`)
  and runs the Hypoland package since that evening.
  A Samsung Galaxy Book4 Edge (Snapdragon X Elite, aarch64, Adreno X1-85 with `freedreno`, 2880x1800 at scale 2)
  joined the same day as `galaxybook` (also as `root@galaxybook`) and runs Hypoland since 2026-10-24, built on the machine (the PKGBUILD builds for aarch64 too).
  A desktop with an AMD A8-6600K APU (Radeon HD 8570D, `r600`, legacy modesetting like the EliteBook) joined on
  2026-10-24 as `lianli` (also as `root@lianli`) and runs the Hypoland package since then, on HDMI
  to the desktop's monitor (1920x1200).
  A Dell Chromebook 11 3120 (Celeron N2840, Bay Trail graphics with Mesa `crocus` like the X200 but GLES 3.0, 4 GB
  RAM, a 16 GB eMMC, 1366x768, wifi only, MrChromebox UEFI firmware) joined on 2026-10-25 as `chromebook` (also as
  `root@chromebook`) and runs the Hypoland package since then: the low end of the machines with GLES 3.
  A Lenovo ThinkPad T460s (Core i7-6600U, Intel HD 520 with Mesa `iris`, the only Skylake: its scanout buffers are
  render compressed, 20 GB RAM, 1920x1080 at scale 1.5, the only fractional scale) joined on 2026-10-26 as `t460s`
  (also as `root@t460s`) and runs the Hypoland package since then.
  Their hardware, addresses, logins and update steps are in `~/Work/machines/MACHINES.md`, a private file in no git
  repository, shared with the other projects that use the machines (it was `MACHINES.md` in this repository until
  2026-10-27, which is a link to it now, in `.git/info/exclude`). Read it before working on a machine, and keep machine
  details there, not here.
  Every test machine sends its journal and its kernel log (netconsole) to the desktop, so a machine that dies
  leaves its last words there: when adding a machine, run `scripts/machines/forward-logs.sh machine <desktop address>
  <ssh host>` (it says where the logs end up). The scripts for the test machines (the soak, the energy meter, the log
  forwarding, kmsgrab) are in `scripts/machines/`, which was `scripts/x200/` until 2026-10-25.

## Repository

- Repo lives in `/home/jonny/Work/hypoland`. The default branch is `master`.
- Remotes: `origin` = github.com/hegjon/hypoland (the user's fork, renamed from hegjon/Hyprland to hegjon/Hypoland
  and on 2026-09-28 to lower case),
  `upstream` = hyprwm/Hyprland, `aquamarine` = github.com/hegjon/aquamarine.
- History: `master` is based on the user's commit `5fafec87` on upstream main (v0.56.0+141, formerly the branch
  `gles2-legacy-renderer`),
  which added a GLES2 path chosen at runtime. Hypoland has since removed the GLES3 path and the runtime switch,
  so `m_legacyGLES` and `GLES2ShaderCompat` no longer exist.
- `master` is pushed to `origin`, is the default branch on GitHub and is the only branch there. The 34 branches
  the fork had before (copies of upstream branches, `main`, `gles2-legacy-renderer`) were deleted on 2026-09-27;
  their names and commits are listed in `docs/baseline/removed-branches.txt`.
  Commit and push only when the user asks.
- The web page hypoland.org is `web/`, served by a Cloudflare Pages project connected to this repository. Cloudflare
  deploys it from `master` by itself (no build command, output directory `web`, watch path `web/*`); there is no
  workflow for it. It was on GitHub Pages until 2026-10-10.
  Both pages share `web/style.css`. `web/header.svg`, `web/icon.svg` and `web/favicon.png` are copies of the logo
  in `assets/logo/`: after regenerating the logo run `scripts/web/update-logo.sh`, which copies them and renders
  the link preview image `web/og.png` (1200x630) from `scripts/web/og.html` with `scripts/web/og.sh`.
- `CHANGELOG.md` lists Hypoland's changes per release. Add user-visible changes and measured speedups to
  "Unreleased" with the commit that makes them, and move them under the version when releasing.
- Release with `scripts/release.sh <version>` (`--dry-run` first): it checks master and CI, updates `VERSION`,
  `CHANGELOG.md` and this file, commits and tags, builds the Arch package, writes the release notes from the
  changelog and, after asking, pushes and publishes the GitHub release with the package. The release workflow
  attaches the source tarball.
- aquamarine is embedded: `subprojects/aquamarine` is a squashed `git subtree` of
  `hegjon/aquamarine` branch `gles2-support` (remote `aquamarine`). It is built as a static library by
  `cmake/aquamarine.cmake`, not by its own CMakeLists.txt. Its generated `wl_*_interface` symbols are
  weakened with objcopy because the compositor defines the same tables. Update with
  `git subtree pull --prefix=subprojects/aquamarine aquamarine gles2-support --squash`.
- Rename status: binaries are `hypoland` and `start-hypoland`, with `start-hyprland` installed as a symlink.
  All binaries and commands are lower case (decided by the user on 2026-09-28, the binary was `Hypoland` before,
  so the process name is `hypoland` now: `pkill -x hypoland`). "Hypoland" stays capitalized as a name in text.
  The `Hyprland` and `hyprland` symlinks were removed on 2026-09-28 by decision of the user. CMake target names, the session file name `hyprland.desktop`
  (Omarchy's session runs `uwsm start ... hyprland.desktop`) and the `hyprctl version` text are intentionally
  unchanged. The files in `systemd/` are `hypoland-session.target` (the compositor starts it,
  `hyprland-session.target` is installed as an alias) and `hypoland-uwsm.desktop`.
  The man page is `hypoland(1)` (`docs/hypoland.1.rst`, built with `make man`, needs pandoc).
  `hyprctl(1)` keeps its name.
- Versions (decided by the user on 2026-09-28): `VERSION` is the version of Hypoland (0.2.0, the package
  version), `VERSION_HYPRLAND` the Hyprland version it is based on (0.56.0). `HYPRLAND_VERSION` stays the Hyprland
  version, because tools and configs compare it with Hyprland releases: the first line of `hyprctl version`, the
  JSON `version`, `hl.version()`, the update news / donation logic and the package's `provides=hyprland=`.
  `HYPOLAND_VERSION` shows up as an extra line `Hypoland 0.2.0, based on Hyprland 0.56.0` and as the JSON field
  `hypolandVersion`. Bump `VERSION_HYPRLAND` when merging a new upstream release.
- GLES3 code is removed, the renderer is GLES2 only (no runtime switch):
  - Include `src/render/gl/GLES2.hpp` instead of any GLES header. It poisons every GLES3 entry point, so
    using one is a compile error. VAO calls go through `GL_OES_vertex_array_object`, loaded with `eglGetProcAddress`.
  - Shaders in `src/render/shaders/glsl` are native GLSL ES 1.00 (`#version 100`). There is no runtime translator.
    Color management, tonemapping, ICC, mirror and motion blur code is gone from the shaders; `color.glsl` keeps
    only the sRGB / gamma 2.2 transfer functions that gradients need.
  - Blur variants ripple, water, fluid_jar, prism and acrylic are removed and fall back to dual Kawase.
  - The embedded aquamarine is patched in-tree the same way (GLES2 context and ES 1.00 shaders only). It also
    creates its DRM renderer for the primary GPU only when a secondary GPU needs it.
  - Framebuffers have one color attachment. The stencil is a `GL_STENCIL_INDEX8` renderbuffer per framebuffer
    (GLES2 has no packed depth/stencil texture); blur needs it for `ignore_alpha`.
  - Removed as dead code: the color management render paths and protocol (`wp_color_manager_v1` is not
    advertised), the ICC 3D LUT, FP16 work buffers, the mirror texture (second color attachment), motion blur and
    `hyprpm/`. Their config options are still registered and ignored.
  - Kept: the image description types in `src/helpers/cm/` and the KMS side in `Monitor.cpp` /
    `handleFullscreenSettings()` (HDR metadata, CTM, wide gamut). They are inert, because every output is forced
    to sRGB in `applyMonitorRuleSoft()`. ICC profiles still apply their VCGT gamma ramps through KMS.
- The config is Lua in this Hyprland version (`~/.config/hypr/hyprland.lua`, Omarchy uses it). With a Lua config
  `hyprctl keyword` answers `unknown request`; use `hyprctl eval "hl.config({...})"`.
- Both machines have identical hypr* library versions (hyprutils 0.14.2, hyprlang 0.6.8, hyprcursor 0.1.13,
  hyprgraphics 0.5.1), so a desktop build links cleanly on the X200. Keep them in sync. The system aquamarine
  is not used.
- Removed on 2026-09-28: Tracy (submodule and the `USE_TRACY` build options), glaze (the only real use was in
  `start-hypoland`) and Nix support (`flake.nix`, `nix/`, the Nix workflows, nixGL in `start-hypoland`, the `nix`
  flag of `hyprctl version`). `start-hypoland` still accepts `--no-nixgl` and `--force-nixgl` and ignores them.
  A build downloads nothing any more. The Nix files of the embedded aquamarine are left alone, they are part of
  the subtree.
- Logo: the pixel potato in `assets/logo/` (icon `hypoland.svg` with PNG exports, and the pre-2000 style banner
  `header.svg` used by the README: bitmap lettering whose O is a pixel potato hanging below the baseline, since
  hypo- means "under"), generated with `scripts/logo/retro.py scripts/logo/potato-mask.txt assets/logo`.
  `web/` has copies of the icon and banner (`scripts/web/update-logo.sh`). The smooth potato logos were removed
  on 2026-09-28 by decision of the user. The README shows two X200 screenshots from `assets/screenshots/` (real, unmodified program output).
  The Hyprland banner and screenshots were removed from `assets/`, the Hyprland wallpapers `wall0-2.png` and the
  wallpaper code on 2026-09-28
  (`misc:force_default_wallpaper` is a no-op). The screens shown when the lock screen app dies
  (`assets/install/lockdead*.png`) are generated from the banner with `scripts/logo/lockdead.py`.
  `assets/hyprland-portals.conf` keeps its name, xdg-desktop-portal finds it through `XDG_CURRENT_DESKTOP=Hyprland`.
- Baseline failure of stock Hyprland 0.56.2 is saved in `docs/baseline/stock-hyprland-0.56.2-crash.txt`:
  `eglCreateContext failed with both GLES 3.2 and GLES 3.0` (EGL_BAD_MATCH), then an assert in
  `CHyprOpenGLImpl::CHyprOpenGLImpl()`. Aquamarine's own `CDRMRenderer` also wants GLES 3, but that is
  only needed for multi-GPU and its failure is non-fatal.
- Comparisons with stock Hyprland 0.56.2 (2026-10-22, Omarchy config, medians of 3 alternating rounds, raw data and
  scripts included): `docs/baseline/x200-vs-stock-hyprland-0.56.2-pr14764/` (started on the X200 with Omarchy's
  GLES 3 override, omacom/omarchy#14764) and `docs/baseline/t550-vs-stock-hyprland-0.56.2/`. Hypoland uses
  25-64% less compositor CPU under load on the X200, 10-55% on the T550, and about 60% less Pss on both, with
  the same frames.

## Hard constraints

- Renderer: GLES 2.0 only. Shaders in GLSL ES 1.00. No instancing, integer textures, MRT, or GLES 3 features.
- Build for baseline `x86-64`. Never use `-march=native` (the desktop CPU is far newer than the X200's).
- License: Hyprland is BSD-3. Keep upstream copyright notices and LICENSE. Don't use Hyprland's logo or imply endorsement.

## Compatibility requirements (do not break)

Rename only the binary and branding. When renaming, do NOT touch:
- Config path: `$XDG_CONFIG_HOME/hypr/hyprland.lua` (this Hyprland version is configured in Lua) and `--config`.
- IPC sockets: `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock` and `.socket2.sock`.
- The `HYPRLAND_INSTANCE_SIGNATURE` env var, IPC command names, JSON output format, and event names.
- `XDG_CURRENT_DESKTOP=Hyprland` (needed by xdg-desktop-portal-hyprland and app detection).
- Hyprland Wayland protocols used by Quickshell (Omarchy's shell): focus grab, global shortcuts, toplevel export.
- Omarchy's titlebar plugin interface, which Hypoland implements itself (`src/render/decorations/TitleBars.*`,
  `CHyprTitleBarDecoration.*`): the `plugin:hyprbars:*` options with the plugin's names and defaults (`enabled` is
  false), `hl.plugin.hyprbars.add_button({ bg_color, fg_color, size, icon, action })`, the `hyprbars:no_bar`,
  `hyprbars:bar_color` and `hyprbars:title_color` window rule effects, `%WINDOW%` in commands, and
  `hl.plugin.load("/usr/lib/omarchy-hyprland-titlebars/titlebars.so")` without a warning. The package installs a text
  file at that path: Omarchy turns titlebars on only when it exists.

Removed features must stay **registered as no-op config options** (warn once, never error), so existing
configs such as Omarchy's load without the red error bar. Setting a removed option at runtime must return `ok`
(`hyprctl eval "hl.config({...})"`; `hyprctl keyword` is answered with `unknown request` by upstream when the
config is Lua, which is not something Hypoland changed).

Ship `hyprctl` built from this fork so versions match. The Arch package should declare
`provides=('hyprland')` and `conflicts=('hyprland')`.

## Features to remove or default off

Remove/rewrite (GPU heavy): color management / HDR pipeline, screen shaders, per-window offscreen rendering
where avoidable. Done so far: color management is removed from the renderer, the shaders and the protocols.
Screen shaders and shadows (default off) are still in the code; screen shaders written for Hyprland are
GLSL ES 3.00 and do not compile here.

Keep: blur (dual Kawase and the GLES2-capable variants), default off. Decided by the user on 2026-09-27 after
measuring it on the X200: about 1% extra compositor CPU and 57-60 fps. Do not remove it.

Optional, default off: animations (keep short slides only, no fades), animated/gradient borders,
rounded corners (radius 0 must skip the shader path), dim inactive, inactive opacity, fractional scaling.

CPU/RAM: drop the plugin system and hyprpm; default to XCursor over hyprcursor SVG; keep Xwayland optional.
Window opacity of 0.98 or more is drawn as 1.0 (`Desktop::View::opaqueAlpha()`, decided by the user on 2026-09-29):
Omarchy gives every window 0.985 active and 0.96 inactive, which lets 1.5% / 4% of the background through (1-2
colour steps on a dark theme) but makes every window blended and unable to hide anything behind it.
Done so far for Xwayland: it starts when the first X11 client connects to its socket (`DISPLAY` is set at startup as
before), not with the compositor. It costs 150 ms of CPU and 31 MiB Pss (19 MiB private) on the X200. In an Omarchy
session it still starts a few seconds after login: fcitx5's XIM / xcb addons connect, and `xdg-settings` runs
`xprop -root` because xdg-utils does not know `XDG_CURRENT_DESKTOP=Hyprland`. The benchmark's X11 workloads and
checks wait until it answers (`xwayland_up()` in `scripts/bench/lib/workloads.sh`, `xprop -root`, 2 s more after a
fresh start), so its start is never in a measurement (stock Hyprland starts it with the compositor); one that does
not answer within 20 s makes the workload invalid and the check fail. After Xwayland dies, Hypoland does not start
another (killed with SIGKILL on the T550 on 2026-10-26; it ignored SIGTERM): X11 clients get no answer until the
next session. Upstream at the fork base has no restart either. The lazy start could listen on the socket again.
Done so far: hyprpm is removed and hyprcursor is off by default. The plugin system is removed (2026-09-27): plugins
must be built against the exact Hyprland source they load into and most draw with GLES3 era renderer code, so
keeping up was not worth it. `hl.plugin.load()` warns once and does nothing, `hl.get_loaded_plugins()` is empty,
`hyprctl plugin list` answers `no plugins loaded` / `[]`, `plugin load` / `unload` fail, and `hyprctl version`
still prints the ABI hash. No symbols are exported, udis86 is gone and no headers or `hyprland.pc` are installed.
The binary shrank from 21.3 to 18.5 MB. hyprtester lost the test plugin that injected input, so the tests that
needed it (keybinds, gestures, drag, snap and the input clients) are removed.

Keep (they help): damage tracking, direct scanout, hardware cursor planes.

Prefer compile-time flags (e.g. `-DNO_ANIMATIONS`) so removed code isn't built.

## Testing workflow

1. Build and test with `scripts/deploy.sh <host>...` (e.g. `scripts/deploy.sh x200`). It builds the Arch package
   from the working tree (`makepkg`, which keeps its build directory, so only changes are compiled), installs it
   on the machines as root (the versions before stay in `/var/cache/pacman/pkg`, go back with `pacman -U`),
   restarts SDDM, which logs in again, and checks the new session with `scripts/bench/measure.sh --mode check`:
   config errors, removed options answering `ok`, a test window drawn in a screenshot and in the buffer the screen
   scans out (`hypoland-kmsgrab`, root and one monitor), a GPU client, an X11 client through Xwayland, Chromium,
   GTK 3 (also through Xwayland), GTK 4, Qt Quick and Qt Quick software windows (drawn, and getting at least
   20 fps, see the toolkit workloads below), GL and shader errors in the compositor's log, crash reports and core
   dumps. A machine without a monitor gets a headless output for the checks. It prints PASS / FAIL per machine;
   logs and screenshots are in
   `test-results/deploy-*`. `--no-install` only checks the running session (the aarch64 Galaxy Book builds its own
   package, see `~/Work/machines/MACHINES.md`). Prefer it over improvising SSH commands. A deploy replaces the
   Hypoland the machine runs, so say which build went where (`pacman -Q hypoland`).
2. A compositor started over SSH can't take the display. The machines run the installed package through SDDM;
   `ssh root@<host> systemctl restart sddm` gives a new session. Do not reboot for recovery, see the pitfalls below.
3. Over SSH, with `XDG_RUNTIME_DIR=/run/user/<uid>` set:
   - control: `hyprctl`
   - screenshots: `grim`, then `scp` back and inspect the image
   - clients: `foot`, `weston-simple-egl`, `glmark2-es2-wayland`
   - resources: `pidstat`, `ps -o rss` (`intel_gpu_top` is unreliable on Gen4)
   - logs: the compositor's stderr in the user journal (`journalctl --user -u wayland-wm@hyprland.desktop.service`),
     `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` (mostly empty, Omarchy disables logs), crash reports in
     `~/.cache/hyprland/`, and every machine's journal and kernel log on the desktop (Hardware above)
4. Fast local checks: run nested on the desktop with `LIBGL_ALWAYS_SOFTWARE=1 MESA_GLES_VERSION_OVERRIDE=2.0`.
   This is NOT a faithful GM45 test (llvmpipe allows extra features); the X200 is the final judge.
5. Quickshell (Omarchy's shell) works on the X200 with GPU rendering. Waybar is installed as a simpler
   layer-shell client for isolating problems.

## Testing pitfalls (learned the hard way)

- **Never reboot the X200** (no `sudo reboot`, no `systemctl reboot`) unless the user is present and says so: the
  disk is encrypted and the password must be typed at boot. The same holds for every test machine. For a GPU hang,
  restart SDDM instead and report it.
- The tty1 test loop (`scripts/x200/run-loop.sh` and `setup-root.sh`, a build in `~/hypoland` restarted on exit)
  and `test-x200.sh` were removed on 2026-10-24 by decision of the user: every machine runs the package through
  SDDM, and `scripts/deploy.sh` installs and checks it. The loop's hook is gone from the X200's `~/.bash_profile`
  too (the file before is `~/.bash_profile.before-loop-removal`); `~/hypoland` on the X200 still holds the last
  test build and `loop.log`, nothing uses them.
- llvmpipe accepts GLSL that real GLES2 rejects (e.g. a leftover `in` declaration). A shader change is only
  verified once `scripts/deploy.sh x200` passes: it finds `Failed to link shader` in the compositor's log and
  checks that the screenshots show the window.
- Embedded shader sources (`src/render/shaders/*.inc`) are generated at configure time, so re-run cmake
  configure after editing a shader. `makepkg`, and with it `scripts/deploy.sh`, configures on every build.
- Screenshots need frames. With the panel off (DPMS, idle) nothing renders: `grim` blocks or shows stale content.
  The same applies to nested runs on the desktop when its monitor is off or the nested window is not visible.
- Wrap every remote `hyprctl` / `grim` in `timeout`.
- Omarchy's shell starts a fullscreen screensaver (terminal with class `org.omarchy.screensaver`) after 150 s
  without input and locks the session after 300 s (`~/.config/omarchy/shell.json`, `idle`). Nothing types on
  the X200 during tests, so any run longer than 2.5 minutes after a compositor start can end up measuring the
  screensaver or a lock screen. Keep profiling runs short after a restart, check `hyprctl clients` for the
  screensaver class and `solitaryBlockedBy` for `LOCK` (`-j`, `session lock` in the text output), and look at
  `journalctl --user | grep "omarchy idle"`. `~/.local/state/omarchy/toggles/screensaver-off` only stops the
  screensaver; the lock needs `~/.local/state/omarchy/indicators/stay-awake` (`omarchy-toggle-idle stay-awake`).
  The lock screen can only be left with the password; `systemctl restart sddm` as root gives a fresh session.

## Status

The first milestone is reached: the GLES2-only build runs the full Omarchy session on the X200 (Quickshell bar,
wallpaper, notifications, windows, Xwayland, Chromium). `./test-x200.sh` (now `scripts/deploy.sh`) passed
(2026-09-27, with the test loop), including a check that the window is really drawn (the test terminal fills
itself with magenta and the screenshot is checked for it).

Measured on the X200 on 2026-09-27 (1280x800, Omarchy config; later numbers further down supersede these):
- idle compositor CPU 0%, RSS about 100 MiB (about 73 MiB of it are file mappings, mostly Mesa and LLVM)
- `weston-simple-egl` 60 fps, compositor 8-9% CPU; blur on costs about 1% more
- 4 windows with rounding, shadows, blur, opacity, dim and animations: 58-60 fps, compositor 12% CPU
- `glmark2-es2-wayland` score 127; glxgears through Xwayland 30 fps
- Chromium falls back to software rendering (it refuses GPUs without ES 3, see `~/Work/chromium/`); compositor 25%
  CPU uploading its shm frames

Findings worth keeping:
- `quirks:skip_non_kms_dmabuf_formats` must default to false. Gen4 primary planes have no alpha formats, so with
  the upstream default no client gets an EGL config with alpha and Quickshell's fullscreen overlay turns black.
- Omarchy 4 locks with its Quickshell shell, `hyprlock` / `hypridle` are not installed.
- Defaults changed: blur, shadows, animations, the splash text (`misc:disable_splash_rendering` is true, the option
  still works) and hyprcursor off; the logo background is gone (`misc:disable_hyprland_logo` is a no-op); hyprpm is
  removed. The config written for new users (`example/hyprland.lua`, embedded in the binary) keeps the same
  defaults: effects and rounding off, a single-color border.
- Removed on 2026-09-28 so Hypoland does not speak for Hyprland: the welcome app, update news and donation popup
  (`WelcomeManager`, `VersionKeeperManager`, `DonationNagManager`; `ecosystem:no_update_news` and
  `ecosystem:no_donation_nag` are no-ops), upstream's GitHub funding, issue / discussion / PR templates and the
  vouch, close-issues, labeler and translation workflows. User-facing text, translations, help texts and the
  example config say Hypoland. Kept for compatibility: the seat name `Hyprland`, the X11 WM name `Hyprland :D`,
  the first line of `hyprctl version`, event names like `hyprland.start` and debug log lines.
- Packaging: `packaging/arch/PKGBUILD` builds from the working tree (`makepkg -f`).

Titlebars (2026-10-24): Omarchy's floating workspaces get their titlebars from its omarchy-hyprland-titlebars plugin
(a hyprbars fork, source and licenses in `LICENSE.titlebars`), which Hypoland cannot load. They are built in with the
plugin's interface (see the compatibility requirements):
- `TitleBars::CState` attaches a `CHyprTitleBarDecoration` to windows only while `plugin:hyprbars:enabled` is set,
  so without titlebars no window carries one. Visibility (enabled, `workspace_tag`, floating, rules) is checked on
  rule updates, config reloads and every drawn frame of the window, and a hidden bar takes no space.
- Drawn with the rect and texture pass elements, no stencil: a rounded window gets rounded top corners on the bar and
  the corners under the bar filled. The title is the desktop entry's Name for the window class (`src/helpers/AppNames.*`),
  looked up when the class or title changes, and redrawn while resizing only when it no longer fits or was cut short.
- Input goes through `onInputOnDeco`, so the press never reaches the client. A drag starts with the first motion and
  first catches up with it; a maximized window comes back to its size held at the pressed spot of the bar. The release
  ends it in `CKeybindManager::onMouseEvent`. The border resize band and its cursor run above a titlebar
  (`TitleBars::visibleHeight()` in `InputManager`); the plugin only handled the click there.
- Unlike the plugin: a window with `decorate` off gets no titlebar (the plugin reserved the space and drew nothing),
  and there is no touch dragging (hyprbars' touch drag floated, pinned and then tiled the window).
- Omarchy's layout toggle reloads the config every time a workspace starts floating, because `hyprctl plugin list`
  never lists hyprbars here. That reload is what sets the titlebars up.
- Tested on lianli (r600) and the X200 (crocus) with Omarchy's toggle and a virtual pointer: title, hover, exact drag,
  double click maximizes, dragging a maximized window out, resizing above the bar, minimize and close buttons,
  back to tiled gives the space back. Idle compositor CPU with a titled window on the X200: 0.1%.

Tools:
- `HYPOLAND_PROFILE_PASS=1` times every render pass element on the GPU (glFinish) and prints per-type totals to
  stderr every 120 frames, which goes to the journal (`journalctl --user -u wayland-wm@hyprland.desktop.service`).
  The variable has to reach the session environment (e.g. `~/.config/uwsm/env`, then restart SDDM). It slows
  rendering down, remove it afterwards.
- `debug:overlay` works and shows frame and render times.
- `scripts/machines/kmsgrab.c` (installed on the X200 as root: `/usr/local/bin/hypoland-kmsgrab out.ppm`) saves the buffer
  the display scans out. Use it to check what really reaches the screen: a `grim` screenshot counts as screen
  sharing, which makes the compositor use the work buffer copy path instead of direct rendering. The read takes
  about 80 ms and the compositor draws into that buffer again a few frames later, so an animating client can
  show up half drawn in the capture; freeze it (`pkill -STOP`) for exact results. It imports every plane of the
  framebuffer (since 2026-10-26): the T460s scans out Skylake's render compressed `I915_FORMAT_MOD_Y_TILED_CCS`, whose
  control surface is a second plane, and Mesa resolves it when the buffer is mapped. With the screen off (DPMS) there
  is nothing to read: "no scanout buffer found".
- `./bench.sh <label>` measures a change on the normal build: memory 60 s after the start and after the
  workloads, CPU time of its workloads (`--help` lists them), three rounds, into
  `test-results/bench-<time>-<label>/values.txt`.
  `./bench.sh --compare <dir> <dir>` prints the difference. It runs with the `performance` governor, so its CPU
  numbers are lower than the ones below (GPU client 3.7% instead of 7-10%). The brief for unattended optimization
  runs is `docs/overnight-ram-cpu.md`.
  CPU time (since 2026-10-26, asked for by the user: work moved from the compositor into a client must show in a
  sum), all in percent of one CPU over the workload's window: `cpu.<workload>.percent` is the compositor alone, the
  scheduler's time of all its threads, comparable with every earlier run. `clients_percent` is the workload's
  clients with every process they start, also those that ended: `measure.sh` starts each client in a transient scope
  of `hypolandbench.slice` under the user's systemd manager (`systemd-run --user --scope`) and reads the slice's
  `cpu.stat`. `total_percent` is the user's whole session, `user@<uid>.service`: the compositor, Xwayland and the
  shell (uwsm runs all three in `wayland-wm@hyprland.desktop.service`, so they cannot be told apart by cgroup), the
  clients and the session's services. `machine_percent` is every CPU's busy time from `/proc/stat`, with the kernel
  threads (the GPU driver's work no process is charged for), interrupts and the benchmark itself. For
  `gtk3-x11-scroll` the session is about 30% on the T550 against 5.5% compositor and 4.3% client: the X11 path's work
  is in Xwayland. Clients that run as fast as they can make their sum a measure of throughput, not of cost:
  `terminal-scroll`'s `ls` loop (133% clients on the T550) and `alacritty-scroll` print more when the terminal takes
  their output faster. Before 2026-10-26 the clients ran in root's ssh session (`user-0.slice`), which the CPU
  controller weighs against the user's slice; now they share the user's slice with the compositor, as programs
  started from the desktop do in `app.slice`. `systemd-run` expands `$` in the command it runs like `ExecStart=`
  does, so it runs with `--expand-environment=no` (a client's `$$` came out as `$` and nothing stopped them).
  `fps.<workload>.screen` (since 2026-10-26) is the frames the compositor put on the screen per second over the same
  window: its page flips, counted as the flip events DRM delivers to it (`perf stat -a -e
  drm:drm_vblank_event_delivered`, root; the same tracepoint on i915, radeon and msm). Idle reads 0.0 and
  `gpu-client` 60.1 on the X200. Read a sum of CPU time with it: a compositor that shows more frames makes its
  clients draw more. `fps.<workload>` without `.screen` stays the client's own frame rate.
- `bench.sh` and `profile.sh` are not tied to the X200 (they were `bench-x200.sh` and `profile-x200.sh` until
  2026-09-28). `--host <ssh host>` or `--host local` picks the machine, `--login` the ssh login (root by default,
  without root the governor is left alone), `--no-deploy` measures the compositor that is running,
  `--workloads a,b` picks workloads and `--client name=command` measures any client as one more workload.
  The work on the machine under test is `scripts/bench/measure.sh`. It takes the compositor (`hypoland`, then
  `Hypoland` of older builds, then `Hyprland`), its user, prefix, instance and Wayland socket from the running
  process and its `hyprland.lock`, starts clients with the environment of the compositor, skips workloads whose
  client is not installed and only touches the Omarchy idle flags where Omarchy is installed. Since 2026-10-25
  evening it is split: `measure.sh` parses the options and runs the mode, its parts are in `scripts/bench/lib/`
  (`session.sh`, `meters.sh`, `setup.sh`, which runs when sourced, `measuring.sh`, `workloads.sh`, `check.sh`) and
  the programs it starts as clients are files in `scripts/bench/clients/`, which editors and linters can read
  (`python3 -m py_compile`, `luac -p`). `scripts/bench/target.sh` holds the ssh part for `bench.sh`, `profile.sh`
  and `scripts/deploy.sh`: it sends the whole `scripts/bench` directory as a tar stream on stdin and runs it from
  a temporary directory, which it removes afterwards, so the machine needs no copy of the repository. Build,
  install and restart go through `scripts/deploy.sh`, whose checks have to pass (`--no-build` installs the
  package that was built last).
- Toolkit workloads (added 2026-10-25): `measure.sh` brings its own GTK client (`scripts/bench/clients/toolkit.py`,
  Python with `python-gobject`) and Qt Quick client (`toolkit.qml`, `qml6`) and starts them, so the machines need
  nothing beyond Omarchy. Both show the same long text
  and print their renderer and frame rate (`fps.*`, the frames the compositor let them draw): `gtk3-scroll`,
  `gtk4-scroll`, `qt-quick-scroll` and `qt-software-scroll` (Qt Quick's software backend, shm like Qt Widgets)
  scroll it, a full window of damage per frame; `gtk3-x11-scroll` is the GTK 3 one through Xwayland;
  `gtk4-spinner` has only a spinner moving, `qt-software-sprites` 60 small squares (many small damage regions);
  `video-window` is the `video` clip in a tiled window instead of fullscreen. They port the useful ideas of
  Phoronix's gtkperf, x11perf, qmlbench and video-cpu-usage (the user decided against running Phoronix tests).
  GTK 2 is not in Arch any more. `idle-windows` opens three foot windows that print for 4 s and then sit idle, and
  reports the GPU memory they add without the purgeable part (`mem.idle-windows.gpu_added_kB`). Only meaningful as
  the only workload of a fresh session (`--workloads idle-windows`): buffers an earlier workload left are freed in
  the meantime. radeon reports no memory in fdinfo, 0 there. Its windows and those of `workspace-switch` and
  `resize` also measure switching between them, see below. `dev` (suggested by the user) is a developer's screen
  in Alacritty: nvim (`--clean`, LazyVim would set itself up first) on a C file of 210000 lines on the left half, a
  console on the right, below it a log of 200 lines a second with a burst of 400 lines every 10 s, which never has
  the focus. The files and a git repository are generated, the same everywhere. A uinput keyboard (root only) drives
  it, the same input path as a real one, in two phases on the same windows. Load, `cpu.dev.*`: every 3 s the focus
  moves (SUPER+Left, SUPER+Right, Omarchy's binds) between the editor, which scrolls a line 40 times a second and
  jumps every 2 s while it has the focus, and the console, which gets a command typed into it, every other time a
  `git diff` of 9000 lines paged through ten times a second, in between `ls`, `git status` or a `git show` of 3000
  lines. Latency, `latency.dev.<kind>_ms` (median) and `_p90_ms`: the editor stops scrolling by itself, and every
  key is followed until the first frame that shows it, `focus` (SUPER+Left into the editor and SUPER+Right back),
  `scroll` (Ctrl-D, Ctrl-U), `jump` (`<line>G`) and `type` (a command typed into the cleared console). The frames
  come from wlr-screencopy of a small region (the border above the window, or its text) until it changes. Keys go
  down at a random point of the frame, as a person's do: pressed right after a commit, as at first, every key had
  the same phase and the 90th percentile hardly differed from the median. The driver is
  `scripts/bench/clients/dev.py`, a Python script without libraries, so it runs on every machine, with the parts it
  shares with `windows.py` (Wayland, screencopy, the uinput keyboard and pointer, the hyprctl socket) in
  `latency.py`; the generator of the files, the editor's movements, the console's shell and the log are the `dev-*`
  files next to it. The drivers run as root from the directory `target.sh` unpacked, not from the user's. The time
  ends at the commit of that frame (the compositor stamps a copied frame when it commits it), the display shows it
  at its next refresh. On a screen where nothing else draws the compositor commits right after the key, so there
  the time is its own work (about 2 ms on the T550); in `dev` the log keeps every frame busy and a key waits for
  the next one.
  Every workload with several windows measures switching between them the same way after its CPU time
  (`scripts/bench/clients/windows.py`, root only): `focus` moves the focus to a neighbouring window with SUPER+arrow,
  in a direction picked at random among those that have one, until the border of the window that had it changes
  (`workspace-switch`, `idle-windows`, `resize`); `workspace-switch` also has `workspace`, SUPER+2 and SUPER+1, until
  the middle of a window changes, and `bar` (added 2026-10-26), the same keys until the first quarter of Omarchy's bar
  changes: its workspace widget, redrawn by the shell after the compositor's event (T550: 15.6 ms against 1.7 ms
  for the window). The driver waits 0.7 s after every step for Omarchy's border animation (539 ms)
  to end. `resize` (added 2026-10-26) puts foot (shm) and Alacritty (GL) side by side, both full of one long line of
  numbers that wraps at the window's edge, and drags the split between them with SUPER and the right button
  (Omarchy's resize bind) by a uinput absolute pointer, 125 motions a second like a mouse, for the CPU time
  (`cpu.resize.*`): every motion has both clients draw at a new size. Then single motions of the same drag,
  `latency.resize.resize_ms` until the first frame that shows them (the compositor moved the windows) and
  `redrawn_ms` until the first frame that shows the region across the split as it then stays for 0.5 s (both clients
  drew at their new size). The text has to reach the split: with the short lines of `ls -la` a client's redraw
  changed no pixel there on wide screens, and `redrawn` was the compositor's first frame. foot runs with
  `resize-delay-ms=0`: by default it waits 100 ms after the last resize before it reflows its text, which made
  `redrawn` 108 ms on every step. A/B against stock Hyprland 0.56.2 (2026-10-26, 4 to 5 alternating rounds on all
  seven machines): on the T550, the XPS and the Galaxy Book stock shows a switch or a resize about a frame later
  (focus 7.1 / 16.3 / 3.7 ms against 1.8 / 2.0 / 1.4, `redrawn` 5 to 15 ms longer), on the X200, the EliteBook, lianli
  and the Chromebook the two are the same. `cpu.resize` is the same or up to 2 points lower, except on the X200
  (16.8% stock with the GLES 3 override, 21.5% Hypoland). `resize-foot`, not in the default list, is the same with
  foot on both sides: shm buffers only, which no GL driver or Mesa variable touches. On the X200 (rounds 2 to 4 of
  2026-10-26) it shows the same gap as `resize`, so it is not Alacritty under stock's GLES 3 override: compositor
  23% / 31%, clients 75% / 110%, session 98% / 141% (stock / Hypoland). It is the frames: during the drag the X200
  shows 40 frames a second under stock and 60 under Hypoland (`fps.resize.screen`, 4 rounds of each, 2026-10-26), and
  every frame has both clients draw at a new size. Per frame on the screen Hypoland's compositor costs 13% less
  (`resize` 0.36 / 0.41 points per frame a second, `resize-foot` 0.52 / 0.59), the whole session the same (`resize`
  +4%, `resize-foot` -6%). `gtk3-scroll` in the same run: stock 30 fps on the screen and the client, Hypoland 59,
  with the session 33% cheaper per frame.
  Omarchy's shell (added 2026-10-26, both skipped where `omarchy-shell shell ping` does not answer): `notifications`
  has notify-send deliver a notification a second from four senders, low urgency (5 s each), over an idle foot window,
  so about five cards stand in the shell's column at the right of the screen, one sliding in and one going every
  second; they end up in the shell's history, the cards are dismissed afterwards. Then `latency.notifications.toast_ms`:
  one notification at a time sent over the session bus by `scripts/bench/clients/shell.py` run as the user (the
  bus refuses root; `sessionbus.py` next to it marshals the D-Bus call by hand, so no library is needed) until the
  top of the shell's notification column changes, each closed through the bus again. `menu` toggles Omarchy's menu
  (SUPER+SPACE) every second over the same window, through the global shortcut the shell registers (`hyprctl
  globalshortcuts`): a fullscreen overlay layer with a half transparent scrim and a card in the middle, which takes
  the keyboard focus. Then `latency.menu.open_ms` from SUPER+SPACE by the uinput keyboard until the scrim shows in a
  strip at the left of the screen, `close_ms` from Escape until it is gone, `search_ms` from a letter typed into
  the open menu's search line until the rows of its card change, and `select_ms` from Down or Up until the selected
  row, moved into the middle rows first, shows moved (`scripts/bench/clients/shell.py`). The shell's own
  CPU time is in `cpu.*.total_percent` (the session), not in the compositor's. Measured 2026-10-26
  (one round of 12 s on a fresh session, `performance` governor; compositor / whole session, latency medians):

  | | X200 | T550 |
  |---|---|---|
  | notifications | 3.4% / 17.3% | 2.7% / 11.2% |
  | menu | 2.0% / 88% | 1.3% / 61% |
  | menu open / close | 427 / 36 ms | 178 / 10 ms |
  | menu search | | 85 ms |
  | menu select | | 5 ms |
  | toast | | 23 ms |

  Opening the menu is the shell's work: it maps a fresh fullscreen surface and fills the card every time, which
  costs the X200 both cores for most of a second and the T550 0.6 cores, and the scrim shows after 0.26 to 0.61 s
  there. Closing is an unmap, a frame or two. The A/B of 2026-10-26 had `close` two to three frames slower than
  stock on the X200 and the Chromebook (31.5 against 6.3 ms), one frame on r600: the layer's map and unmap simulate
  a mouse move (upstream #16455, cherry-picked as c56c3db8d, not in 0.56.2), that showed the cursor Omarchy hides on
  key presses, Escape hid it again, and the frame for that repainted the whole screen (two screen buffers, the
  benchmark's last frame was a full one) while the pending screencopy's readback blocked the compositor for about
  24 ms and the shell's unmap waited. Fixed 2026-10-27: a simulated move keeps a cursor hidden
  (`CInputManager::m_simulatedMovement`, checked by the renderer's mouse move listener). X200 close 5.6 ms, the rest
  unchanged. Found with perf tracepoints (the shell's and the compositor's socket calls, the atomic commits, the
  vblanks, `-k CLOCK_MONOTONIC`, so the driver's stamps line up) and stderr prints in the renderer.
  Screencopy takes the compositor off direct rendering while it captures, which is why the CPU time is measured in
  the load phase only. It refuses to run on a locked session, whose password field would get the keys: on
  2026-10-25 a run typed six commands into the X200's lock screen (six failed logins for `faillock`, which locks
  the account at 10; reset with `faillock --user a --reset`). Before 2026-10-25 evening the developer's screen was
  lighter (`dev-log` / `dev-diff`, a 20000 line file paged through four times a second, a log of 20 lines a
  second, driven with `hyprctl`), its numbers below are not comparable. `measure.sh` dismisses Omarchy's
  notifications when it starts: one left on the screen is drawn over the windows in every frame. `--env NAME=VALUE`
  gives the clients a variable, as a session's `hl.env` gives the programs it starts (the Mesa overrides of the
  GLES 3 override for stock Hyprland on the X200). Zed (GPU, Vulkan) is a candidate for a later editor, it cannot
  run on the X200. Measured 2026-10-25 (compositor CPU, `performance` governor):

  | | X200 | T550 | XPS (scale 2) |
  |---|---|---|---|
  | terminal-scroll (foot) | 9.9% | 11.4% | 23.4% |
  | gtk3-scroll | 19.3% | 19.8% | 23.3% (42 fps) |
  | gtk4-scroll | 11.0% (cairo) | 4.4% (Vulkan) | 5.6% (Vulkan) |
  | qt-quick-scroll | 3.8% (47 fps) | 4.1% | 5.3% |
  | qt-software-scroll | 9.4% | 13.8% | 12.5% |
  | gtk3-x11-scroll | 3.6% | 5.4% | 6.8% |
  | gtk4-spinner | 4.0% | 4.2% | 5.0% |
  | qt-software-sprites | 58.8% (37 fps) | 13.4% | 29.7% |
  | video-window | 3.1% | 2.6% | 2.8% |

  - GTK 4 finds neither GLES 3 nor Vulkan on the X200 and draws with cairo into shm buffers. Qt Quick draws with
    GLES 2 there, but scrolls at 47 fps where its software backend makes 60.
  - `qt-software-sprites` cost the X200 six times the full-window scroll: Mesa 38% of the compositor's samples,
    pixman 17%, libc 26%. Every draw is repeated per damage rectangle and `CGLTexture::uploadRegion()` made one
    `glTexSubImage2D` per rectangle, and the double buffered update adds the damage of the update before, which
    pixman splits into bands of many small rectangles. Fixed on 2026-10-25 for crocus
    (`CHyprOpenGLImpl::coalesceDamage()`, `Math::coalesceRegion()`): above 8 rectangles the frame damage and the
    upload are merged into horizontal strips, or their bounding box. X200: 59.1% -> 31.7% CPU, the client 36.5 ->
    55.1 fps, every other workload unchanged. Not on other drivers: on the XPS (iris, 3200x1800) merging cost
    30.2% -> 36.3%, the bounding box of the squares is the whole window, 21 MB per frame; without it the XPS is
    unchanged. The lighter `dev-log` / `dev-diff` on the XPS: 2.5% / 1.2%, the same before and after. A/B on all
    six machines (2026-10-25, 15 workloads, 3 rounds each): only the X200 changes.
  - The rest of it was pixman: 97% of its samples came from the `wl_surface.damage` / `damage_buffer` requests, each
    unioned into the pending region on arrival (`addSafeDamage()`), the square of the number of rectangles. They are
    collected and made into the region once at commit now (`flushDamage()`, `pixman_region32_init_rects()`), the
    same region. `qt-software-sprites`: X200 31.6% -> 19.4% (59.9 fps), XPS 29.6% -> 24.2%, T550 and Galaxy Book
    unchanged within noise; X200 `gtk3-scroll` and `gtk4-scroll` 0.5 to 1 point lower. `gpu-client` on the Galaxy
    Book varies by 1.5 points between runs (rounds 3.5 to 5.8%), do not read a change there.
  - GTK 3 costs the X200 about twice what GTK 4 does (19.2% / 11.0%, both cairo into shm) because GTK 3 damages the
    whole window on every frame, GTK 4 only the text column that changes (`WAYLAND_DEBUG`: 1576x850 against
    about 470x850). The client's doing, not the compositor's. GTK 3 also sends `set_window_geometry` with every
    commit, the window ignores an unchanged one.
  - The border damage while windows animate (`CHyprBorderDecoration::damageEntire()`, region math per tick) is
    still 4.2% of the compositor's time in workspace switching on the EliteBook, about 0.35 points of CPU.
  - `dev` on r725 (2026-10-25, 3 rounds; latency median / 90th percentile in ms, 12 focus changes, 18 scrolls,
    12 jumps and 39 typed keys per round, no timeouts):

    | | CPU | focus | scroll | jump | type |
    |---|---|---|---|---|---|
    | X200 | 5.2% | 6.3 / 15.9 | 63.8 / 73.6 | 42.1 / 50.6 | 7.4 / 16.2 |
    | T550 | 4.1% | 11.0 / 21.8 | 26.5 / 37.3 | 15.7 / 29.7 | 8.2 / 18.0 |
    | XPS (3200x1800) | 4.9% | 9.6 / 20.0 | 34.4 / 56.4 | 21.3 / 36.8 | 12.0 / 18.2 |
    | EliteBook | 4.1% | 12.2 / 18.3 | 25.4 / 36.3 | 16.4 / 35.6 | 9.3 / 17.7 |
    | lianli | 4.3% | 8.1 / 20.5 | 26.7 / 36.3 | 17.2 / 29.5 | 9.1 / 18.2 |
    | Galaxy Book (120 Hz) | 5.5% | 8.9 / 13.0 | 16.4 / 19.0 | 13.0 / 17.9 | 7.3 / 10.2 |

    What the compositor alone does (`focus`) and a key echoed by the shell (`type`) take under a frame at the median
    everywhere. Scrolling is nvim and Alacritty redrawing the editor: about one and a half frames at 60 Hz, two on
    the XPS and the Galaxy Book, almost four on the X200 (64 ms). The compositor's CPU time is about the same on
    every machine, the clients make the difference.
- `./bench.sh --energy <label>` measures energy instead of speed (added 2026-09-28, after omacom/ttfx#46): the
  power the machine draws under each workload, net of an idle baseline taken before and after it (`power.*.net_W`,
  `energy.*.net_J`, with the drift of the baseline as `pm_W`), the idle session itself (`power.baseline.W`) and
  the instructions and cycles of the compositor from `perf stat` (`perf.*.Minstructions`, within about 1% from
  run to run, the steadiest figure to compare builds by). The governor is left alone, energy depends on it.
  The meter is RAPL where the CPU has it (the desktop: AMD package counter, root only) and otherwise the battery's
  discharge rate, which covers the whole machine including the screen and reads only on battery. The X200 has no
  RAPL, so it has to run unplugged: its battery showed 26%, 7.3 V (design 11.1 V) and `Not charging` on the
  charger, check it before trusting it with a run. The run stops below `--min-battery` (30%) and when the charger
  is plugged in, since a flat battery means a reboot and the disk password. `--meter none` only counts
  instructions and cycles and works on the charger. Tested with fake meters only so far (`--power-supply`,
  `--powercap`); the 0.3 W noise floor of `--compare` for power is a guess until real runs.
- `HYPOLAND_NO_DIRECT_RENDER=1` makes every frame go through the work buffer, for comparing the two paths.

Performance (X200, `HYPOLAND_PROFILE_PASS`, GPU time per frame, 4 windows plus a 60 fps client):

| | before 2026-09-27 evening | now |
|---|---|---|
| full-screen redraw | 19.1 ms (pass 14.3 + clear 1.4 + copy 3.4) | 14.4 ms |
| small updates | 3.4 ms (pass 1.7 + clear 1.4 + copy 0.3) | 1.7 ms |

- Every frame used to clear the whole 1280x800 work buffer (1.4 ms, Gen4 has no fast clear). Now only the damage
  is cleared: the pass paints the background over its damage anyway (`clearRegionAfterInvalidation()`).
- Frames are drawn straight into the screen buffer when nothing needs the work buffer (no zoom, no rotated output,
  no screen shader, no mirror or screen sharing), `CHyprOpenGLImpl::canRenderDirectly()`. That removes the copy
  from the work buffer to the screen. Screen buffers are imported twice: as a renderbuffer to render into and as a
  texture to sample from (blur), with a stencil renderbuffer. The screen buffer holds the frame from bufferAge
  frames ago and the damage covers everything since, so blur samples correct pixels outside the damage.
- Fill rate is the limit: one fullscreen 1280x800 blended surface costs about 3.3 ms.
- Borders cost about 0.4 ms per window on a full redraw, they are already limited to the border ring.
- Omarchy gives every window an opacity rule (`default-opacity` tag), so no window occludes the wallpaper.
  With opaque windows the occlusion pass skips what is underneath.
- Quickshell's notification layer is a transparent overlay layer that is blended over every damaged area under it. It
  was fullscreen when this was found; the Omarchy 4 of 2026-10-26 keeps it as a column at the right of the screen
  (465x800 on the X200) and has the dock as another, a strip of 245 px at the bottom (`hyprctl layers`).
- The wallpaper counts as opaque (`CSurfacePassElement::isBackdrop()`, 2026-09-29): the lowest surface of the
  background layer, when it covers the monitor and has no fade or blur. Omarchy's wallpaper is a Quickshell window
  with `color: "transparent"`, so its buffer has alpha and no opaque region, and the pass painted
  `misc:background_color` under it on every redraw (1.0 ms of a full-screen redraw) and blended it. It is drawn
  without blending now and hides the clear. Transparent pixels of a wallpaper show over black instead of over
  `misc:background_color`. A full tile with a window at opacity 0.9: 6.89 -> 5.78 ms GPU time per frame; opaque
  windows (2.95 ms) hide the wallpaper anyway. Measured with i915 request tracing, not `HYPOLAND_PROFILE_PASS`.

CPU profile: run `./profile.sh`. It installs the package with `hypoland-debug` (makepkg builds with frame
pointers, Arch's default flags, so the package needs no profiling build; the debug package has the symbols),
switches the Omarchy screensaver and idle lock off, records five workloads with `perf` as root, prints the report
to `test-results/profile-*/profile.txt` and removes the debug package. Use `--keep` to leave it installed;
`perf report` on the saved data only resolves symbols while it is. Until 2026-10-24 it used a separate build
without the package's hardening flags (`-D_GLIBCXX_ASSERTIONS`, `_FORTIFY_SOURCE=3`, stack clash and CET
protection), so older profiles are not exactly comparable.
Findings:
- Idle desktop: 0.1% CPU.
- GPU client at 60 fps, 10% CPU: `renderMonitor` 76% of it. `endRender` 52% (of which `CEGLSync::create` 25%,
  this is where the driver flushes and submits the batch, and `CDRMOutput::commitState` 11% with the atomic commit
  8%), `CRenderPass::render` 19%. Clock reads 3%, DRM property re-reads in aquamarine 4%.
- shm client redrawing a large window (Chromium), 26% CPU: `CGLTexture::update` 71%. About 38% of all samples
  are the kernel allocating, clearing and cache-flushing pages for a new GPU buffer on every upload
  (`shmem_alloc_and_add_folio`, `drm_clflush_sg`), about 23% is the `memcpy`.
- Terminal scrolling fast (foot, shm), 15% CPU: `CGLTexture::update` 74%, the same upload cost as Chromium.
- Workspace switching with three windows and animations, 15% CPU: only 30% is `renderMonitor`. Clock reads are
  17% (`read_hpet` 12%), the rest is spread over animation ticks, layout and damage. Fixed on 2026-09-29, see below.
- Hypoland's own code is flat, no function has more than about 1% self time.
- The X200 uses the HPET clocksource (the TSC is marked unstable), so every clock read is a slow syscall.
- Fixed: uploading into a shm texture the GPU still reads from made crocus allocate, clear and cache-flush a
  staging buffer every time (2.4x the cost of the upload, measured with a standalone benchmark). Synchronous
  textures are now double buffered (`CGLTexture::update()`): the update goes into the texture that was shown one
  update ago, plus the damage it missed. Chromium 26.8% -> 12.8% CPU, fast terminal scrolling 14.8% -> 11.3%.
- Fixed: the event loop read the clock once per timer when rescheduling and when timers fire; it reads it once
  per pass now. Workspace switching 14.9% -> 12.7%.
- Checked on 2026-09-27, not worth optimizing:
  - The shm upload (`glTexSubImage2D`, crocus copies through a GTT mapping) runs at the memory bus limit:
    1.64 ms for a full 1280x800 frame with glibc memcpy. SSE2 non-temporal stores are the same through the GTT,
    `rep movsb` is slower, and the best case (own WC mapped linear buffer) is 1.45 ms. Hand-written copies or
    inline assembly would not help.
  - `CEGLSync::create` is where Mesa's threaded context runs the whole frame (draws and batch submit). A frame
    with one 60 fps client was 2 draws and 16 ioctls, all needed except the mode re-read, which is fixed
    (13 ioctls now, see below).

Memory (X200, idle Omarchy session 60 s after start, `heaptrack` and `/proc/<pid>/smaps`):
- Fixed: aquamarine created a second EGL context for the primary GPU, which is only needed when a secondary GPU
  blits (`CDRMBackend::primaryRenderer()` now creates it on demand). It cost heap and a Mesa driver thread.
- Fixed: shaders were preprocessed with glslang, only to resolve `#include`. `CShaderLoader` expands includes
  itself now and leaves `#define` / `#if` to the driver, so libglslang (2.5 MiB, private to the compositor) is no
  longer loaded.
- Both together: RSS 113.6 -> 100.1 MiB, anonymous 38.0 -> 27.2 MiB, PSS 73.8 -> 60.1 MiB, one thread less,
  compositor CPU with `weston-simple-egl` unchanged (7.3%).
- What is left: about 17 MiB heap, of which about 7 MiB is Mesa compiler state created with the first shader and
  1.7 MiB the GL context. libLLVM shows 19 MiB RSS but only 6 MiB PSS, the pages are shared with Quickshell and
  Xwayland and come from loading the library (`DRAW_USE_LLVM=0` changes nothing). The Hypoland binary is about
  14 MiB of clean file pages.
- The "started without start-hypoland" notification loads fontconfig and pango (about 1.5 MiB heap) when the test
  loop starts `hypoland` directly; a start through `start-hypoland` (the SDDM session) does not.

Overnight run 2026-09-28 (journal in `test-results/overnight/journal.md`), measured with `./bench.sh`
(`performance` governor), before -> after:

| | before | after |
|---|---|---|
| Pss / Rss / anonymous, 60 s after the start | 62.2 / 102.5 / 29.2 MiB | 55.2 / 95.8 / 22.1 MiB |
| GPU memory, 60 s after a plain restart | 73.5 MiB | 52.0 MiB |
| GPU client at 60 fps | 3.69% | 3.17% |
| terminal scrolling | 10.56% | 10.13% |
| Chromium over shm | 11.01% | 10.20% |
| workspace switching | 8.97% | 8.62% |

- Transparent huge pages are off for the compositor (`prctl(PR_SET_THP_DISABLE)` in `main()`), an atfork handler
  gives clients the system default back. The X200 runs with THP `always`.
- Mesa keeps 5.7 MiB of GLSL built-in function tables after the first shader compile.
  `CHyprOpenGLImpl::scheduleShaderCompilerRelease()` calls `glReleaseShaderCompiler()` and `malloc_trim()` 10 s
  after the last compile. Without the trim the memory stays in the heap.
- Frames get no EGL fence on crocus (`CHyprGLRenderer::needsRenderFence()`), i915 has implicit sync. The fence
  is still made for explicit sync clients, screen sharing, multi GPU and other drivers. It was skipped on all of
  i915 until 2026-10-23: iris (Broadwell and later) submits `glFlush()` on Mesa's driver thread, so the commit could
  overtake the batch and the XPS (3200x1800) showed half drawn frames; `GALLIUM_THREAD=0` hid it. The driver name
  comes from `EGL_MESA_query_driver` (`CHyprOpenGLImpl::m_eglDriverName`).
- aquamarine keeps the mode of the CRTC (`SDRMConnector::atomic.currentMode`) instead of reading it on every commit.
  A frame with one 60 fps client is 13 ioctls now, 9 of them are Mesa's buffer cache (`GEM_MADVISE`, `GEM_BUSY`).
- Not merged, by decision of the user (2026-09-28): the build changes. They are the commits `13ee9d36` and
  `4b16588f` on the local branch `overnight/ram-cpu`. The binary is mapped almost completely, so its size is
  memory: `--gc-sections`, `-O2`, and `-Os` for code outside the frame and input paths take the binary from
  18.1 to 13.9 MiB and Pss down by 2.9 MiB without a change in CPU time. `-Os` for everything saves 5 MiB more
  but costs 3 to 9% CPU time, `-Os` for everything except render / helpers / output costs 4% in workspace switching.
- Idle shm windows give their second texture back (2026-10-25, `CHyprOpenGLImpl::trackBackTexture()`): a texture
  that was not updated between two sweeps a second apart frees the one its updates went into. Three foot windows that
  printed and then sat idle, GPU memory without the purgeable part: X200 8 -> 6 MiB, T550 16 -> 8, XPS 48 -> 24,
  Galaxy Book 40 -> 25, no CPU change. A window has a second texture only after two commits at its last size (a
  resize makes a new texture). iris and crocus keep small freed buffers in Mesa's cache and give them back at a later
  free (not counted as purgeable either), larger ones at once.
- Tried and dropped (2026-10-25): shm textures with one texture (as upstream) on every driver but crocus. Slower on
  iris (T550 `qt-software-scroll` 13.8% -> 16.3%), the same on the XPS, a little faster on freedreno (Galaxy Book
  `gtk3-scroll` 15.4% -> 14.5%, sprites 26.3% -> 22.7%, within that machine's spread of about 1.5 points). Double
  buffering stays on all drivers.
- The GPU memory that grows over a benchmark run is Mesa's buffer cache (purgeable) on Intel: what is held changes by
  -8 to +6 MiB. The Galaxy Book holds 23 to 39 MiB more after a run (2880x1800): it comes once, with the first
  `qt-software-sprites` (+45 MiB, no other workload adds any), and further sprites windows add nothing, so a high-water
  mark (a driver cache or a buffer kept once allocated), not a leak. Not narrowed down further.
- Not worth it: the GSettings cursor sync leaves 4 glib threads in the compositor, moving it into a child saves
  0.2 MiB. `malloc_trim` alone finds nothing, the heap is not fragmented. Idle is 3 wakeups per second.
- GPU buffers are system memory on Gen4 and in no process statistic; read them from `/proc/<pid>/fdinfo`
  (`drm-total-system0`), the benchmark reports them as `mem.*.gpu_kB`. The compositor held 100.4 MiB 60 s after the
  start of the benchmark (73.5 MiB after a plain restart), more than its Pss. Now 65 to 74 MiB in the benchmark and
  52.0 MiB after a plain restart (Pss 53.1 MiB, anonymous 20.8 MiB there). The totals vary by up to 8 MiB between runs because
  `test-x200.sh` switched blur on and took a screenshot (blur and mirror framebuffers); `scripts/deploy.sh`, which
  replaced it on 2026-10-24, leaves blur as it was but still takes screenshots.
  - The group bar kept four gradient textures of the size of the monitor (15.6 MiB), also without any window
    group. They are one pixel wide now, the picture is identical.
  - Unused work buffers were only dropped when the next one was requested, which never happens while the monitor
    renders directly. `CMonitorResources` releases them with a timer now (8 MiB).
  - The swapchain has two screen buffers instead of three, three with `render:new_render_scheduling`.
  - A framebuffer that was allocated but never drawn into costs nothing, i915 allocates pages on first use.
    Allocating the blur framebuffer lazily gains nothing.
- The Chromium workload is bimodal, a round is either about 9.0% or about 10.5%. Look at the rounds in `bench.txt`.
- Open: `CHyprBorderDecoration::damageEntire()` was about 7% of the compositor's time while windows animate,
  measured before the tick change of 2026-09-29 below.

Overnight run 2026-09-29 (branch `overnight/startup`, journal in `test-results/overnight-startup/journal.md`),
startup and CPU time with animations. Measured on the X200 with the SDDM session, `schedutil` governor:

| | master 8ae8a37c0 | overnight/startup |
|---|---|---|
| startup: compositor instructions in the first 11 s | 938 M | 783 M |
| startup: compositor CPU in the first 12 s | 730-760 ms | 590-620 ms |
| startup: IPC answers after exec | 0.73-0.82 s | 0.68-0.74 s |
| workspace switching with animations, CPU | 14.2% | 6.1% |
| GPU client at 60 fps, terminal scrolling, Chromium over shm | 6.3 / 10.7 / 11.2% | unchanged |

- Animations ticked every millisecond: after upstream 2b0fd417d the animation timer was re-armed with 1 ms after
  every tick, although every rendered frame ticks right before it draws. The whole tick (all animated variables and
  their damage) ran up to 16 times per 60 Hz frame. Continuous ticking now uses the frame interval of the fastest
  monitor, a requested tick still comes after 1 ms. Same page flips, less than half the CPU.
- Clock reads cost real time, they are not sampling skid as a note of 2026-09-27 assumed: with the HPET
  clocksource every read is a system call and an MMIO read, about 1.2% of the compositor's time per read and tick
  while animating. The tick reads the clock once now. `Time::fromTimespec()` still makes four reads per presented
  frame (about 1% of the GPU client's compositor time) because it does not trust `steady_clock` to be
  `CLOCK_MONOTONIC`, and Mesa's `__crocus_bo_unreference` reads it for every buffer it caches (0.7%).
- Startup, instructions of the main thread: keyboards with the same rules share one keymap (-5%), the "screen
  share denied" text is rendered on first use so pango and fontconfig (about 130 ms of CPU and a thread) are not
  loaded at all (-3%), XCursor shapes are loaded on first use (-6%).
- Startup profile (compositor, about 0.6 s of CPU until IPC): the Mesa driver load in `CGBMAllocator` is 116 ms
  (`dlopen` 72 ms, drirc XML 15 ms, `crocus_screen_create` 12 ms), the first frame about 75 ms of which 44 ms are
  buffer allocations, Omarchy's Lua event handlers 37 ms, `libinput_udev_assign_seat` 51 ms, GSettings sync 23 ms.
  The very first frame takes a work buffer, later ones render directly. The black screen after that is Quickshell
  and Omarchy's login scripts (uwsm, powerprofilesctl, udiskie, hidden-entries, pacman, find on both cores).
- `libgallium` links `libLLVM`, which crocus does not use at runtime; loading it costs 19-27 ms per GL process.
  A crocus-only Mesa without LLVM needs `mesa_clc` at build time (LLVM, `libclc`, `LLVMSPIRVLib`), see the journal.
- Not worth it: `GALLIUM_THREAD=0` for the compositor (-1% on the GPU client only); glFlush waits for Mesa's
  threaded context on every frame anyway (`_tc_sync`).
- Measuring from the desktop: long ssh sessions end early, run measurements detached on the X200. `tl2.sh` (one
  startup timeline with instructions) and `abrun.sh` (A/B of packages with page flips) are in the journal's
  directory, they call `scripts/bench/measure.sh` copied to the X200.

Fixed upstream bugs that showed on this hardware:
- `IHyprRenderer::renderText(STextResourceData&&)` queued the text on the hyprgraphics worker and blocked in
  `await()`. On the slow dual core the wakeup gets lost and the compositor hangs forever (seen with
  `debug:overlay`). Text is now rendered synchronously.

Known issues:
- foot 1.28.0 segfaults on exit when many foot windows close at once (the soak's window churn on the EliteBook,
  2026-10-22, four of 15 windows): `wayl_win_destroy()` destroys the surface and does a roundtrip, during which the
  compositor's `zwp_text_input_v3.enter` for that surface (keyboard focus moved to it as the other windows closed)
  arrives, libwayland turns the destroyed surface into NULL and `ime.c` `enter()` dereferences it. A protocol race
  on any compositor, not a Hypoland bug. Fixed in foot master (`f3226bc`, issue #2467, after 1.28.0), not in Arch
  yet. The core dumps are readable on the desktop with `gdb` and `DEBUGINFOD_URLS=https://debuginfod.archlinux.org`
  (same package versions).
- Not Hypoland's: Arch's Chromium shows stale frames and stalls for seconds on r600 (EliteBook, lianli; crbug
  576728226, the same with stock Hyprland), and renders in software on the X200 (it refuses GPUs without ES 3).
  Chromium numbers of soaks and benchmarks on r600 with Arch's Chromium measure that bug, and it delayed Chromium's
  first frame in the deploy check on lianli by up to 30 s. Patched packages, the patches, the analysis and the
  scripts are in `~/Work/chromium/` on the desktop (its `README.md`); which machine runs which Chromium is in
  `~/Work/machines/MACHINES.md`.
- Open, in the radeon driver or the hardware (2026-10-25): on the EliteBook (r600, HD 6470M) the screen can stand
  still for 17 to 36 s when a Qt Quick software window opens (the deploy check's "Qt Quick (software) window" fails:
  no screenshot, 0 to 7 fps). The compositor is idle in `epoll_wait` and answers IPC; its frame waits on the GPU. The
  radeon tracepoints (`perf record -a -e radeon:radeon_cs -e 'radeon:radeon_fence_*' -e 'radeon:radeon_semaphore_*'`)
  show the graphics ring waiting on a semaphore of a small DMA ring job (24 dwords, Mesa's copies, about 5 a second
  while windows change) that is submitted but only runs at the next DMA submission of any process, often Quickshell's
  clock at the next minute. Stock Hyprland 0.56.2 stalls too, less often: 1 of 18 fresh sessions, Hypoland about 1 in
  4 (r720, r722 and r725 alike), though both submit the same work in the same check (DMA jobs 323 / 332, graphics
  1726 / 1729). Not changed by `R600_DEBUG=nodma`, `HYPOLAND_NO_DIRECT_RENDER`, single buffered shm textures or
  `power_dpm_force_performance_level=high`. Traces and scripts: `test-results/r600-stall-20261025/`. The EliteBook's
  GPU failed on 2026-10-27 (see Hardware), so whether this was an early sign of that is open; lianli is the r600
  machine left to check it on.
- Not a bug: foot 1.28 is never blurred by default. It binds `ext-background-effect-v1` and only sets a blur
  region with `blur=yes` in its `[colors-dark]` section, and `CWindow::shouldBlur()` honours that. Live and
  precomputed blur both work on the X200 for other clients. Do not use foot to judge blur.
- Not Hypoland's: Quickshell spins for the hour the clock repeats at the end of daylight saving time (2026-10-25,
  03:00 to 04:00 EET for the second time). Its `SystemClock` (the bar's clock) truncates the time with
  `QDateTime::setTime()`, which places 03:10 in the first of the two 03:10s, an hour back, so the next tick is due
  -3570 s from now. `QTimer` warns `negative intervals aren't allowed`, fires at once and the clock schedules the
  same again, until 04:00 (reproduced with Qt 6.12). The clock shows the right time, but one core was busy in the
  shell for that hour on every machine with a session (anything measured then is off), and every instance wrote 0.8
  to 3.3 million warnings, 95 to 380 MB, into its log in `/run/user/<uid>/quickshell/by-id/`. That is tmpfs, and
  SDDM restarts do not clear it: by 2026-10-26 evening it was full on three machines, and on lianli a session came up
  without space (`xkbcomp` and the shell's logger failed, and the benchmark's A/B lost three blocks). Remove the
  directories of instances that no longer run (their pids are the links in `by-pid/`).

## Next steps

Work that is left from the plan above:
- Remove screen shaders.

# Code guidelines

Inherited from upstream Hyprland, they apply to Hypoland as well.

## Review guidelines

- Prioritize correctness, lack of regressions, performance, API stability, and code clarity and readability.
- For performance-sensitive paths, flag obvious algorithmic regressions or slow paths.
- For tests, flag missing coverage for changed or new behavior, as long as the testing framework is capable of testing it.
- For config changes (new / removed options) check that the README and this file still describe the defaults.
- Flag silent config breakage: e.g. changing an existing option's behavior. This is not allowed.
- Flag bad config style that breaks this project's style guidelines (further below) and suggest fixes.
- Flag bad code approaches that break this project's core code guidelines (further below) and suggest improvements.

## Style guidelines

- Code must be clang-formatted according to `.clang-format`.
- single-line if and else statements must come without braces. This rule applies only to if / else, not do / while / other.
- Avoid function bodies in headers as much as possible.
- Avoid namespace {} in source files to mark local functions. Prefer `static`.
- Prefer guards in functions and loops: `if (!cond) continue;`
- Prefer forward-declaration in headers to inclusion.
- Leave a stray `,` at the end of brace-enclosed lists to make formatting easier to read.
- Leave a `;` inside empty function bodies for formatting.
- Naming conventions:
 - class: `CMyClass`
 - struct: `SMyStruct`
 - interface: `IMyInterface`
 - class (not struct) member variables: `m_variable`
- Do not use absolute includes from `src/` in headers: instead of `#include "a/b.hpp"` use `#include "../a/b.hpp"` for example. Protocol headers do not require this.

## Core code guidelines

- Stick to good code practices:
 - Avoid complex classes / functions, prefer SRP.
 - Consider using an observer pattern via hyprutils Signals where appropriate.
 - Consider classic OOP patterns where appropriate: Strategy, Singleton, Proxy, etc.
 - Watch out for typical bad practices in code: feature envy, LSP, etc.
 - Use templating and inheritance to clean up code where appropriate.
 - For obtaining singletons, use a `UP<CClass>& myClass();` pattern inside a namespace. This can be implemented in source as making and returning a static ptr.
- Do not, under any circumstance:
 - `using namespace std;`
 - leave uninitialized primitives (int, float, etc)
- Avoid, unless absolutely necessary:
 - the C standard library. Use the C++ STL.
 - `malloc` / `free` / etc
 - C-style pointers. Use SP<> WP<> and UP<> from hyprutils. These are Shared, Weak and Unique pointers respectively. C-style pointers may be used in select scenarios (e.g. destroying fns, where it's impossible to make a mistake) but everywhere else must not be used unless necessary.
 - C-style casts. Use rc<>, sc<>, or cc<> from hyprutils. These are shorthands to equivalent C++ casts.
- Avoid:
 - violating clang-tidy (`.clang-tidy`)
 - manual C-style cleanup: `some_c_thing_new()` and `some_c_thing_free()` can be wrapped.
- Make sure to write tests for code which our Unit (`tests/`) or Integration (`hyprtester/`) tests can test.
