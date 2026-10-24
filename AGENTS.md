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
  8560p (Radeon HD 6470M, `r600`), both with GLES 3. All three run Omarchy on the Hypoland package through SDDM and
  are reached over ssh by an alias (`x200`, `t550`, `elitebook`, also as `root@`). A Dell XPS 13 9343 (Intel HD
  5500, `iris`, 3200x1800 at scale 2) joined on 2026-10-23 as `xps` (also as `root@xps`)
  and runs the Hypoland package since that evening.
  A Samsung Galaxy Book4 Edge (Snapdragon X Elite, aarch64, Adreno X1-85 with `freedreno`, 2880x1800 at scale 2)
  joined the same day as `galaxybook` (also as `root@galaxybook`) and runs Hypoland since 2026-10-24, built on the machine (the PKGBUILD builds for aarch64 too).
  A desktop with an AMD A8-6600K APU (Radeon HD 8570D, `r600`, legacy modesetting like the EliteBook) joined on
  2026-10-24 as `lianli` (also as `root@lianli`) and runs the Hypoland package since then, on HDMI
  to the desktop's monitor (1920x1200).
  Their hardware, addresses, logins and update steps are in `MACHINES.md`, a private file that is not in git
  (it is in `.git/info/exclude`). Read it before working on a machine, and keep machine details there, not here.

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
`xprop -root` because xdg-utils does not know `XDG_CURRENT_DESKTOP=Hyprland`.
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
   GL and shader errors in the compositor's log, crash reports and core dumps. A machine without a monitor gets a
   headless output for the checks. It prints PASS / FAIL per machine; logs and screenshots are in
   `test-results/deploy-*`. `--no-install` only checks the running session (the aarch64 Galaxy Book builds its own
   package, see `MACHINES.md`). Prefer it over improvising SSH commands. A deploy replaces the Hypoland the
   machine runs, so say which build went where (`pacman -Q hypoland`).
2. A compositor started over SSH can't take the display. The machines run the installed package through SDDM;
   `ssh root@<host> systemctl restart sddm` gives a new session. Do not reboot for recovery, see the pitfalls below.
3. Over SSH, with `XDG_RUNTIME_DIR=/run/user/<uid>` set:
   - control: `hyprctl`
   - screenshots: `grim`, then `scp` back and inspect the image
   - clients: `foot`, `weston-simple-egl`, `glmark2-es2-wayland`
   - resources: `pidstat`, `ps -o rss` (`intel_gpu_top` is unreliable on Gen4)
   - logs: the compositor's stderr in the user journal (`journalctl --user -u wayland-wm@hyprland.desktop.service`),
     `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` (mostly empty, Omarchy disables logs), crash reports in
     `~/.cache/hyprland/`
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
- Chromium falls back to software rendering (it wants GLES3 itself); compositor 25% CPU uploading its shm frames

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

Tools:
- `HYPOLAND_PROFILE_PASS=1` times every render pass element on the GPU (glFinish) and prints per-type totals to
  stderr every 120 frames, which goes to the journal (`journalctl --user -u wayland-wm@hyprland.desktop.service`).
  The variable has to reach the session environment (e.g. `~/.config/uwsm/env`, then restart SDDM). It slows
  rendering down, remove it afterwards.
- `debug:overlay` works and shows frame and render times.
- `scripts/x200/kmsgrab.c` (installed on the X200 as root: `/usr/local/bin/hypoland-kmsgrab out.ppm`) saves the buffer
  the display scans out. Use it to check what really reaches the screen: a `grim` screenshot counts as screen
  sharing, which makes the compositor use the work buffer copy path instead of direct rendering. The read takes
  about 80 ms and the compositor draws into that buffer again a few frames later, so an animating client can
  show up half drawn in the capture; freeze it (`pkill -STOP`) for exact results.
- `./bench.sh <label>` measures a change on the normal build: memory 60 s after the start and after the
  workloads, CPU time of five workloads, three rounds, into `test-results/bench-<time>-<label>/values.txt`.
  `./bench.sh --compare <dir> <dir>` prints the difference. It runs with the `performance` governor, so its CPU
  numbers are lower than the ones below (GPU client 3.7% instead of 7-10%). The brief for unattended optimization
  runs is `docs/overnight-ram-cpu.md`.
- `bench.sh` and `profile.sh` are not tied to the X200 (they were `bench-x200.sh` and `profile-x200.sh` until
  2026-09-28). `--host <ssh host>` or `--host local` picks the machine, `--login` the ssh login (root by default,
  without root the governor is left alone), `--no-deploy` measures the compositor that is running,
  `--workloads a,b` picks workloads and `--client name=command` measures any client as one more workload.
  The work on the machine under test is `scripts/bench/measure.sh`, which is sent over ssh on stdin. It takes the
  compositor (`hypoland`, then `Hypoland` of older builds, then `Hyprland`), its user, prefix, instance and Wayland socket from the running process
  and its `hyprland.lock`, starts clients with the environment of the compositor, skips workloads whose client
  is not installed and only touches the Omarchy idle flags where Omarchy is installed.
  `scripts/bench/target.sh` holds the ssh part. Build, install and restart go through `scripts/deploy.sh`, whose
  checks have to pass (`--no-build` installs the package that was built last).
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
- Quickshell's notification overlay is a transparent fullscreen layer that is blended over every damaged area.
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
- Not a bug, Chromium's: on the EliteBook (r600, no native fence sync) Chromium with GPU compositing shows stale or
  garbage regions after a resize because it commits its dmabuf before its rendering is submitted; diagnosed on
  2026-10-22 with any Hyprland. Script, captures and the Chromium bug report draft: `docs/baseline/elitebook-chromium/`,
  details in `MACHINES.md`.
- Not a bug: foot 1.28 is never blurred by default. It binds `ext-background-effect-v1` and only sets a blur
  region with `blur=yes` in its `[colors-dark]` section, and `CWindow::shouldBlur()` honours that. Live and
  precomputed blur both work on the X200 for other clients. Do not use foot to judge blur.
- Open, not yet compared with stock Hyprland: on lianli (r600) Chromium's first frame in a new window with a fresh
  profile came after 1 s in some runs and only after 15 to 30 s in others (2026-10-24, the Chromium check of
  `scripts/deploy.sh`). Until then its window shows a buffer it has not drawn into: transparent, or old video
  memory such as the last frame of a glxgears that had just closed, also in `grim` screenshots. The EliteBook
  (r600) and the T550 drew within about a second in the same runs. The check waits up to 60 s for the page.

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
