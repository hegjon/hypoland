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
  An Apple Mac mini Late 2014 (Core i5-4260U, Intel HD Graphics 5000, Haswell GT3 with Mesa `crocus` like the X200
  and the Chromebook, 4 GB RAM, no battery, RAPL, 1920x1200 over HDMI on the desktop's monitor) joined on 2026-10-27 as
  `macmini-intel` (also as `root@macmini-intel`) and runs the Hypoland package since 16:36 that day, with
  `hypoland-bench` from the branch `bench-package`.
  Their hardware, addresses, logins and update steps are in `~/Work/infrastructure/MACHINES.md`, a private file in a local git
  repository without a remote (since 2026-10-30), shared with the other projects that use the machines (it was `MACHINES.md` in this repository until
  2026-10-27, which is a link to it now, in `.git/info/exclude`; the folder was `~/Work/machines` until 2026-10-30). The network
  (the lab router `hypolab`, the wifi networks, the subnets and their names) is `NETWORK.md` next to it, linked here the same
  way. Read them before working on a machine, and keep machine and network details there, not here.
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
  Commit and push only when the user asks. From 2026-10-27 to 11-02 `scripts/deploy.sh` committed the pkgver makepkg
  wrote into `packaging/arch/PKGBUILD` after every deploy; before 0.3.0 the user had those commits dropped from the
  history (the history since v0.2.0 rewritten and force-pushed on 2026-11-02) and the deploy stopped making them.
- The web page hypoland.org is `web/`, served by a Cloudflare Pages project connected to this repository. Cloudflare
  deploys it from `master` by itself (no build command, output directory `web`, watch path `web/*`); there is no
  workflow for it. It was on GitHub Pages until 2026-10-10.
  `web/lab.html` and `web/terminals.html` are generated by `scripts/web/lab.py` and `scripts/web/terminals.py` from the
  night named in `scripts/web/labdata.py` (with the machines' facts): run both after a new baseline. Since 2026-11-15 both
  compositors' numbers come from one baseline of alternating sessions again,
  `docs/baseline/20261114-all-machines-r992-vs-hyprland-0.57.2/` (master r992 against Hyprland 0.57.2-2 on twelve
  machines, the P14s and the Mac mini 2014 on its monitor among them; hp-amd is in the hardware table without numbers).
  From 2026-11-13 to 15 (the user: "Use old numbers for Hyprland") Hypoland's came from
  `docs/baseline/20261112-all-machines-r991-realtime-off-vs-on/` and Hyprland's from the night before,
  `docs/baseline/20261111-all-machines-r966-vs-hyprland-0.57.1/`; `HYPOLAND_RUN` and `HYPOLAND_BLOCKS` in `labdata.py`
  still allow such a pair.
  `web/games.html` (since 2026-11-11) is `scripts/web/games.py`: every game from the same night (since 2026-11-13; before,
  SuperTuxKart, Yamagi Quake II and vkmark came from the short run `docs/baseline/20261111-games-r964-vs-hyprland-0.57.1/`);
  run it with the other two.
  `web/files.html` (since 2026-11-12) is `scripts/web/files.py`: Nautilus, Flea and Folio (`*-scroll`, `nautilus`, `flea`,
  `folio`), Flea and Folio from the same night, Nautilus from `docs/baseline/20261111-all-machines-r966-vs-hyprland-0.57.1/`
  (`NAUTILUS_RUN`, the last night with Nautilus on the machines: Omarchy's update of 2026-11-13 removed it); run it with
  the others.
  `web/energy.html` (since 2026-11-12, asked for by the user) is `scripts/web/energy.py`: the CPU package's power (RAPL),
  the energy above the idle session per frame on the screen, and the whole machine (psys) on the T460s and
  T490, from the energy run of 2026-11-12 (`ENERGY_RUN`, `docs/baseline/20261112-energy-r972-vs-hyprland-0.57.1/` once
  it ends; `test-results/energy-20261112/` has the runner). Named energy, not battery: watts on AC, not battery hours.
  Not linked from the other pages or the sitemap yet, by decision of the user; `ENERGY_PRELIMINARY=1` marks a run still
  going and adds `noindex`.
  The pages share `web/style.css`. `web/header.svg`, `web/icon.svg` and `web/favicon.png` are copies of the logo
  in `assets/logo/`: after regenerating the logo run `scripts/web/update-logo.sh`, which copies them and renders
  the link preview image `web/og.png` (1200x630) from `scripts/web/og.html` with `scripts/web/og.sh`.
- Hyprland 0.57.0 (released 2026-10-28) is partly ported, on master since 2026-10-30 (prepared on the branch
  `port/0.57.0-r2`, worktree `~/Work/hypoland-port`): the 28 picks of the earlier `port/0.57.0` replayed, 18 more upstream
  commits with their test-only conflicts settled, a fixup, and the rest of 0.57.0's config surface written on Hypoland's
  own code, so that a 0.57.0 config (its `example/hyprland.lua`, Omarchy's edge config) loads with no config error: the
  `layers` category (`layers_hog_keyboard_focus`, `allow_new_top_layers_over_existing_fullscreen`; the `misc:` one keeps
  working), `decoration:blur:proportional` (on the GLES 2 blend), `input:swallow_focus_click`, `input:tablet:enabled`,
  `binds:client_requested_fs_uses_layout_handler`, `render:async_commit` (accepted and ignored: it needs aquamarine
  0.15), `binds:workspace_back_and_forth` and `scrolling:follow_focus` as 0/1/2 with the old booleans still accepted,
  `hl.get_devices()`, `hl.dsp.reload_config()`, the `no_glow` rule, a workspace's `addressable_name`, a monitor's `mode`
  and `hardware_details`, and the events `window.update_state`, `window.minimize`, `workspace.created_early` and
  `config.unload`. `docs/port-0.57.0.md` lists every upstream commit with its decision (cherry-pick, by
  hand, ignore, later): about 110 wait behind the workspace refactor (e9e2f64cc, 163 files), which with aquamarine 0.15
  is the real remaining port. The 2026-10-27 baseline compares against Hyprland 0.56.2, the 2026-10-30 one against 0.57.0,
  and so does the 2026-11-03 one, the released 0.3.0, which the lab page took its numbers from from 2026-11-04 to 11-11 (then the 2026-11-10 one, r957 against 0.57.1, and since 2026-11-13 r991 of 2026-11-12 against 0.57.1 of the night before). A config is tested headless as hyprtester starts the compositor
  (`HYPRLAND_HEADLESS_ONLY=1 ./build/hypoland --config <file>`, then `hyprctl configerrors`).
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
- Versions (decided by the user on 2026-09-28): `VERSION` is the version of Hypoland (0.3.0, the package
  version), `VERSION_HYPRLAND` the Hyprland version it is based on (0.57.2 since 2026-11-16, decided by the user after the
  fixes of 0.57.1 and 0.57.2 were merged, `docs/port-0.57.2.md`; 0.57.0 from 2026-11-02, decided before 0.3.0 with the
  0.57.0 port partial; 0.56.0 before). `HYPRLAND_VERSION` stays the Hyprland
  version, because tools and configs compare it with Hyprland releases: the first line of `hyprctl version`, the
  JSON `version`, `hl.version()`, the update news / donation logic and the package's `provides=hyprland=`.
  `HYPOLAND_VERSION` shows up as an extra line `Hypoland 0.3.0, based on Hyprland 0.57.2` and as the JSON field
  `hypolandVersion`. Bump `VERSION_HYPRLAND` when merging a new upstream release.
- GLES3 code is removed, the renderer is GLES2 only (no runtime switch):
  - Include `src/render/gl/GLES2.hpp` instead of any GLES header. It poisons every GLES3 entry point, so
    using one is a compile error. VAO calls go through `GL_OES_vertex_array_object`, loaded with `eglGetProcAddress`.
  - Shaders in `src/render/shaders/glsl` are native GLSL ES 1.00 (`#version 100`). There is no runtime translator.
    Color management, tonemapping, ICC, mirror and motion blur code is gone from the shaders; `color.glsl` keeps
    only the sRGB / gamma 2.2 transfer functions that gradients need.
  - Blur is dual Kawase only (`CDualKawaseBlurProvider`). The variants ripple, water, fluid_jar, prism and acrylic
    were never ported; frost, drops, heat_shimmer, aurora and haze were removed on 2026-11-12 with their shaders and
    the blur material layer. `decoration:blur:variant` keeps its names and values and is ignored.
  - Drop shadows, inner glow and wobble (with its mesh, `renderTextureMesh()` and the motion tracking that fed it) were
    removed on 2026-11-12. `decoration:shadow:*`, `decoration:glow:*` and `decoration:wobble:*` stay registered and
    are ignored; the `no_shadow`, `no_glow` and `no_wobble` window rules (and the workspace rule's `no_shadow`) are
    still parsed, stored and read back by `getprop`, and change nothing. Turning on a removed feature's `enabled` (or a
    blur variant) warns once in the log (`warnIgnoredOptions()` in `src/config/lua/ConfigManager.cpp`). The window
    transformer framework that drew a window offscreen for wobble went with it (2026-11-12: `src/render/transformer/`,
    `CTransformedWindowPassElement`, `CWindowEffectsController`, the blur alpha matte of `surface.frag`): a window's
    surfaces and decorations are always drawn straight into the frame's pass.
  - The embedded aquamarine is patched in-tree the same way (GLES2 context and ES 1.00 shaders only). It also
    creates its DRM renderer for the primary GPU only when a secondary GPU needs it.
  - Framebuffers have one color attachment. The stencil is a `GL_STENCIL_INDEX8` renderbuffer per framebuffer
    (GLES2 has no packed depth/stencil texture); blur needs it for `ignore_alpha`.
  - `bitdepth = 10` in a monitor rule is ignored with a warning (2026-10-27): GLES2 has no colour-renderable 10-bit
    texture format, and an output whose planes took XRGB2101010 (headless outputs, Intel from Broadwell on) crashed
    the compositor on its first frame with an incomplete framebuffer. `IHyprRenderer::canRenderToFormat()` says what
    a framebuffer can be allocated in; `CMonitor::applyMonitorRule()` asks it before trying the 10-bit formats.
  - Removed as dead code: the color management render paths and protocol (`wp_color_manager_v1` is not
    advertised), the ICC 3D LUT, FP16 work buffers, the mirror texture (second color attachment), motion blur and
    `hyprpm/`. Their config options are still registered and ignored.
  - Removed on 2026-11-12, inert since every output was forced to sRGB: the image description types
    (`src/helpers/cm/`) on monitors, framebuffers and textures, the monitor's HDR, wide gamut, luminance and SDR state,
    and the KMS side of it (HDR metadata, the wide colour gamut flag, and the colour conversion CTM of a fullscreen
    window in `handleFullscreenSettings()`, which sets the content type and the CTM control protocol's matrix only
    now). Kept: the CTM control protocol (hyprsunset's night light) and an ICC profile's VCGT gamma ramps through KMS
    (`src/helpers/ICC.*`, lcms2 reads the profile, `CMonitor::updateVCGTRamps()`). The monitor rule's `cm`, `sdr*`,
    luminance and `supports_*` fields are parsed and ignored (a non-sRGB `cm` warns); `hyprctl monitors` shows
    `colorManagementPreset: srgb` and the rule's sdr values, Lua's monitor `cm` is `srgb`. `render:cm_sdr_eotf` is
    ignored since the aurora and haze blur variants, which read it, were removed (2026-11-12). The embedded
    aquamarine keeps its HDR and colour properties, unused.
- The config is Lua in this Hyprland version (`~/.config/hypr/hyprland.lua`, Omarchy uses it). With a Lua config
  `hyprctl keyword` answers `unknown request`; use `hyprctl eval "hl.config({...})"`.
- The desktop and the machines have the same hypr* library versions, those of Arch's Hyprland 0.57.0 (hyprutils
  0.14.3, hyprlang 0.6.8, hyprgraphics 0.6.0, hyprwire 0.3.1, and hyprland-protocols 0.8.0 to
  build, a package as in 0.57.0 since 2026-11-03, the submodule before), so a desktop build links cleanly on every
  machine. Keep them in sync: hyprgraphics 0.6.0 (2026-11-03) changed its soname (`libhyprgraphics.so.4` -> `.so.5`),
  and a Hypoland built before it does not start after an Omarchy update brings it, nor one built after it on a machine
  without it. The PKGBUILD and CMake require hyprgraphics 0.6.0, hyprutils 0.14.3 and hyprland-protocols 0.8.0 at least.
  The system aquamarine is not used.
- Removed on 2026-09-28: Tracy (submodule and the `USE_TRACY` build options), glaze (the only real use was in
  `start-hypoland`) and Nix support (`flake.nix`, `nix/`, the Nix workflows, nixGL in `start-hypoland`, the `nix`
  flag of `hyprctl version`). The `--no-nixgl` and `--force-nixgl` options of `start-hypoland` were removed on
  2026-10-27 (it ignores options it does not know, as upstream's does).
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
- Comparisons with stock Hyprland are in `docs/notes/baselines.md`: every baseline and A/B night with what Hypoland
  was ahead and behind in. The regression baseline is `docs/baseline/20261027-all-machines-r761-vs-hyprland-0.56.2/`
  (its README says how to compare a build against it), the newest one
  `docs/baseline/20261114-all-machines-r992-vs-hyprland-0.57.2/` (r992 against Hyprland 0.57.2-2 on twelve machines),
  which the web pages take their numbers from since 2026-11-15 (from 2026-11-13 Hyprland's from the r966 one of 2026-11-11
  and Hypoland's from r991's night after it; the r957 one of 2026-11-10 before). In short: less compositor CPU a frame in
  nearly every workload, 40 to 57 MiB Pss at the start against 115 to 145, every session check passed. Open against
  stock: a toast half a frame late on some Intel machines, the Galaxy Book's menu, Velocitty on the T490 (27.5 against
  32 fps), many-windows frames on the T550 and the Mac mini 2014, lianli's workspace switch (7 ms in half the sessions
  since r992's night, 2 under stock), and a GPU hang of Hypoland's context on the X200 (2026-11-12, crocus aborts in
  `glFlush()`).
  Stock Hyprland 0.56.2 does not start on the X200 (`docs/baseline/stock-hyprland-0.56.2-crash.txt`).

## Hard constraints

- Renderer: GLES 2.0 only. Shaders in GLSL ES 1.00. No instancing, integer textures, MRT, or GLES 3 features.
- Build for baseline `x86-64`. Never use `-march=native` (the desktop CPU is far newer than the X200's).
- License: Hyprland is BSD-3. Keep upstream copyright notices and LICENSE. Don't use Hyprland's logo or imply endorsement.
  "Hyprland" and its logo are EU-registered trademarks of Hyprland Development (policy of 2026-11-11,
  https://hypr.land/trademark-usage/): naming Hyprland to say what Hypoland is or is compared with is fine, but never
  as part of a product name or a tagline that reads as a Hyprland edition ("A fork of Hyprland for ...", not
  "Hyprland for ..."; changed on the site and its link preview on 2026-11-12).

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
where avoidable. Done so far: color management is removed from the renderer, the shaders and the protocols, and the
screen shaders (2026-11-12): `decoration:screen_shader` is accepted and ignored (Hyprland's are GLSL ES 3.00 and never
compiled here), the final pass through a work buffer is gone, and `debug:manual_crash` counts down and aborts without
its glitch shader. Shadows, inner glow, wobble and the blur variants were removed on 2026-11-12 (options accepted and
ignored).

Keep: blur (dual Kawase), default off. Decided by the user on 2026-09-27 after
measuring it on the X200: about 1% extra compositor CPU and 57-60 fps. Do not remove it.

Optional, default off: animations (keep short slides only, no fades), animated/gradient borders,
rounded corners (radius 0 must skip the shader path), dim inactive, inactive opacity, fractional scaling.

CPU/RAM: drop the plugin system and hyprpm; XCursor only, no hyprcursor SVG; keep Xwayland optional.
Window opacity of 0.98 or more is drawn as 1.0 (`Desktop::View::opaqueAlpha()`, decided by the user on 2026-09-29):
Omarchy gives every window 0.985 active and 0.96 inactive, which lets 1.5% / 4% of the background through (1-2
colour steps on a dark theme) but makes every window blended and unable to hide anything behind it.
Done so far for Xwayland: it starts when the first X11 client connects to its socket (`DISPLAY` is set at startup as
before), not with the compositor. It costs 150 ms of CPU and 31 MiB Pss (19 MiB private) on the X200. In an Omarchy
session it still starts a few seconds after login: fcitx5's XIM / xcb addons connect, and `xdg-settings` runs
`xprop -root` because xdg-utils does not know `XDG_CURRENT_DESKTOP=Hyprland`. The benchmark's X11 workloads and
checks wait until it answers (`xwayland_up()` in `scripts/bench/lib/workloads.sh`, `xprop -root`, 2 s more after a
fresh start), so its start is never in a measurement (stock Hyprland starts it with the compositor); one that does
not answer within 20 s makes the workload invalid and the check fail. After Xwayland dies, its windows go and the next
X11 client starts another one (since 2026-11-01, hyprtester's `xwaylandComesBackAfterItDies`). Until then the compositor
kept its copies of Xwayland's ends of the two socket pairs after the fork, so neither connection ended: the X11 windows
stayed, the window manager's restart on the hangup (`CXWM::onEvent()`) never ran, X11 clients got no answer until the
next session (the T550 on 2026-10-26, Xwayland killed with SIGKILL), and the window manager's writes, ANR pings among
them, went into a socket nobody read until `xcb_flush()` blocked the compositor for good: stock Hyprland 0.57.0 on the
X200 on 2026-11-01, after Xwayland aborted on a GPU hang in glamor (`Server.cpp` in upstream main is the same).
Done so far: hyprpm and hyprcursor are removed. Cursors are XCursor themes only (2026-11-12): libhyprcursor is not
linked, `cursor:enable_hyprcursor` is accepted and ignored (a warning in the log once), and `hyprctl version` /
`systeminfo` list no hyprcursor version (the JSON fields `buildHyprcursor` / `systemHyprcursor` stay, empty, so the
JSON keeps its form; the ABI hash lost its `_hc_` part). Configs keep exporting `HYPRCURSOR_SIZE` for clients that draw hyprcursor themes themselves;
the compositor never set it and no longer reads it. The plugin system is removed (2026-09-27): plugins
must be built against the exact Hyprland source they load into and most draw with GLES3 era renderer code, so
keeping up was not worth it. `hl.plugin.load()` warns once and does nothing, `hl.get_loaded_plugins()` is empty,
`hyprctl plugin list` answers `no plugins loaded` / `[]`, `plugin load` / `unload` fail, and `hyprctl version`
still prints the ABI hash. No symbols are exported, udis86 is gone and no headers or `hyprland.pc` are installed.
The binary shrank from 21.3 to 18.5 MB. hyprtester lost the test plugin that injected input, so the tests that
needed it (keybinds, gestures, drag, snap and the input clients) are removed.

Keep (they help): damage tracking, direct scanout, hardware cursor planes.

Prefer compile-time flags (e.g. `-DNO_ANIMATIONS`) so removed code isn't built.

## Testing workflow

1. Build and test with `scripts/deploy.sh <host>...` (e.g. `scripts/deploy.sh x200`). It builds the Arch packages
   from the working tree (`makepkg`, which keeps its build directory, so only changes are compiled): `hypoland` and
   `hypoland-bench`, the benchmark, the checks and the soak scripts of `scripts/bench` and `scripts/machines`
   installed as `hypoland-measure`, `hypoland-soak`, `hypoland-soak-ab`, `hypoland-energy-meter` and
   `hypoland-kmsgrab` (`/usr/lib/hypoland-bench`, the workloads' clients are optional dependencies). It installs both
   on the machines as root (the versions before stay in `/var/cache/pacman/pkg`, go back with `pacman -U`),
   restarts SDDM, which logs in again, and checks the new session with `scripts/bench/measure.sh --mode check`:
   config errors, removed options answering `ok`, a test window drawn in a screenshot and in the buffer the screen
   scans out (`hypoland-kmsgrab`, root and one monitor), a GPU client, an X11 client through Xwayland, Chromium,
   GTK 3 (also through Xwayland), GTK 4, Qt Quick and Qt Quick software windows (drawn, and getting at least
   20 fps, see the toolkit workloads below), a Tk window through Xwayland with a menu and a dialog (see `tk-canvas`
   below), the render checks (below), GL and shader errors in the compositor's log, crash reports and core dumps. A machine without a monitor gets a headless output for the checks. A passing check ends
   with one more SDDM restart, and the checked compositor must not dump core on its way out (since 2026-10-31: lianli's
   compositor had crashed at most session ends from 2026-10-30, unseen). It prints PASS / FAIL per machine;
   logs and screenshots are in
   `test-results/deploy-*`. `--no-install` only checks the running session (the aarch64 Galaxy Book builds its own
   package, see `~/Work/infrastructure/MACHINES.md`). Prefer it over improvising SSH commands. A deploy replaces the
   Hypoland the machine runs, so say which build went where (`pacman -Q hypoland`). makepkg writes the version it
   built into the PKGBUILD; the deploy puts the committed pkgver line back afterwards and notes the packages it built
   in `packaging/arch/.last-build`, which `--no-build` installs. The version counts the commits, so builds of one commit
   share it: build uncommitted work from a wip commit in a git worktree to give it a version of its own.
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
6. `make test` builds `build/` in Debug and runs hyprtester against it, nested in the desktop's session with headless
   outputs (CI runs only the unit tests). Since 2026-10-27 the tests open foot windows, Omarchy's terminal (kitty
   before, which Omarchy does not install): `Tests::spawnFoot()` passes the class with `--app-id`. Layer-shell bars
   come from Quickshell, `hyprtester/clients/layer.qml` run with `qs -p`, with namespace, edge, layer and size in the
   environment (`Tests::spawnLayer()`, kitty's panel before). The swallow tests, which start one terminal from inside
   another, feed each terminal's shell through a FIFO in `/tmp` (kitty's remote control before). A window that
   asks for focus is `hyprtester/clients/activate.cpp`, an xdg-activation client of the tester (foot's urgency
   bell sends no serial, which the compositor rejects). Some tests need xeyes. One test:
   `./build/hyprtester/hyprtester -c hyprtester/test.lua -b ./build/hypoland <names>`.
   All 176 pass on the desktop (2026-10-27; xeyes, `xorg-xeyes`, is installed there since then for the windows
   test). Four needed fixing that day, none for foot: upstream tests that depend on the ones before
   (surfaceScaleTransform read its client before the scale events the special workspace of
   fullscreenWithExplicitMonitor delays; floatingWindowHiding inherited `scrolling.follow_focus = false` from
   TestFsingGroupedWindows, and read the focused fullscreen window's visibility before the layout's next
   recalculation applied the fullscreen fade, which only showed up late in a full run, so it waits for it now), a
   test cherry-picked from after the base (silentMove expected the "workspace 1 (1)" text of upstream's workspace
   refactor, 0.56.2 prints "workspace ID 1 (1)"), and processSpawning, which took any `sleep` on the machine (it
   looks under the compositor's pid now, `HYPRLAND_PID`, and waits for `sh -c` to become `sleep`). The contains
   macro evaluates its argument twice, so the value it prints on a failure can be newer than the one it checked.
   The unit tests CI runs are `./build/hyprland_gtests` (427 on 2026-10-30, built by the same Debug tree); `make test` does not
   run them. A new fragment shader has to be added to the list in `tests/render/ShaderLoader.cpp` as well, or the list's last
   entry is empty and the loader reads a directory (the three shader loader tests failed in CI from 2026-10-29 to 30 for
   that). CI's Code Style job uses Arch's current clang-format, so a clang upgrade can make it fail on untouched files
   (23.1.4 on 2026-10-27, eleven files realigned on 2026-10-30): run `.github/workflows/clang-format-check.sh . llvm
   '^subprojects$' ''` with `GITHUB_WORKSPACE=$PWD` and format what it names among the tracked files.

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
- Defaults changed: blur, shadows (removed since 2026-11-12), animations, the splash text (`misc:disable_splash_rendering` is true, the option
  still works) off and hyprcursor removed (XCursor only); the logo background is gone (`misc:disable_hyprland_logo`
  is a no-op); hyprpm is removed. The config written for new users (`example/hyprland.lua`, embedded in the binary) keeps the same
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
- `scripts/machines/kmsgrab.c` (`hypoland-kmsgrab out.ppm`, root; built into the `hypoland-bench` package since
  2026-10-27, by hand into `/usr/local/bin` on the machines before, which comes first in the path) saves the buffer
  the display scans out. Use it to check what really reaches the screen: a `grim` screenshot counts as screen
  sharing, which makes the compositor use the work buffer copy path instead of direct rendering. The read takes
  about 80 ms and the compositor draws into that buffer again a few frames later, so an animating client can
  show up half drawn in the capture; freeze it (`pkill -STOP`) for exact results. It imports every plane of the
  framebuffer (since 2026-10-26): the T460s scans out Skylake's render compressed `I915_FORMAT_MOD_Y_TILED_CCS`, whose
  control surface is a second plane, and Mesa resolves it when the buffer is mapped. With the screen off (DPMS) there
  is nothing to read: "no scanout buffer found".
- `./bench.sh <label>` measures a build on a machine (`--host`, `--workloads a,b`, `--no-deploy`, `--energy`, `--help`
  lists the workloads) into `test-results/bench-<time>-<label>/values.txt`: memory, the compositor's CPU time and its
  milliseconds per frame on the screen, the clients', the session's, frames, GPU busy time and latencies.
  Every value of every round is also in `results.om` there, OpenMetrics labelled with machine, compositor, version,
  run and round (since 2026-11-16, asked for by the user; a night's `report.sh` writes one per compositor, and every
  result before was converted; never committed, `.gitignore`'s `result*` keeps them out of `docs/baseline/` too).
  `scripts/bench/openmetrics.py` writes and reads it (`values FILE` prints `values.txt` from it).
  `./bench.sh --compare <dir> <dir>` prints the difference. The work on the machine is `scripts/bench/measure.sh`
  (`hypoland-measure` from the `hypoland-bench` package) with its parts in `scripts/bench/lib/` and its clients in
  `scripts/bench/clients/`. What every workload does, how its numbers are to be read and their first results:
  `docs/notes/benchmark.md`.
- The render checks (`scripts/bench/clients/render.py`, part of the session check) draw windows whose pixels they know
  and compare the screen with a full repaint after every step. `scripts/bench/render-nested.sh [--scale S]
  [--transform T] [--config extra.lua]...` runs them against the tree's build nested on the desktop in about two
  minutes, `scripts/bench/render-matrix.sh [--quick]` over effects, scales and transforms. Their steps and the bugs
  they found: `docs/notes/render-checks.md`.
- Switches in the compositor's environment (`~/.config/uwsm/env`, then restart SDDM), all for comparing paths on a
  machine. How each path works and what it measured: `docs/notes/renderer.md`.
  - `HYPOLAND_NO_DIRECT_RENDER=1`: every frame through the work buffer.
  - `HYPOLAND_SHM_TEXTURE=0|linear`: the dumb buffer behind a shm texture and the compositor's row copy (on for iris,
    crocus, r600 and freedreno).
  - `HYPOLAND_SHM_ZEROCOPY=0|force|flush`: a shm pool's pages sampled in place through udmabuf, with the cache
    write-back on GM45 and Bay Trail.
  - `HYPOLAND_SINGLE_TEXTURE=1|0`: one shm texture updated in place instead of two (the default on asahi).
  - Removed on 2026-11-12, their questions answered: `linear-gl`, `HYPOLAND_SHM_TEXTURE_DEVICE`, `HYPOLAND_NO_COALESCE`,
    `HYPOLAND_COALESCE_FRAME`, `HYPOLAND_COALESCE_RECT_COST`, `HYPOLAND_COALESCE_DEBUG`, `HYPOLAND_NO_BATCH_RECTS` and
    `HYPOLAND_BATCH_MIN_RECTS`. A frame's damage is merged on every driver, uploads on crocus and r600
    (`coalesceUploads()`), and an element with 4 or more damage rectangles is drawn in one call.
  - `HYPOLAND_ALPHA_BOUNDS=0|debug|noclip|noskip`: layers clipped to the box of their pixels that are not clear
    (Omarchy's full-size bar window).
  - `HYPOLAND_NO_RT_GUARD=1`: realtime without the guard thread (`HYPRLAND_NO_RT=1`, which Omarchy sets, keeps
    realtime off).
  - `HYPOLAND_SCANOUT_DEBUG=1`: every change of the measured direct scanout's choice.
- Fullscreen games: `xwayland:legacy_fullscreen` and `render:direct_scanout = auto`, which measures a fullscreen
  window on the plane and composited and keeps the better (`CScanoutAuto` in `src/output/ScanoutAuto.*`, unit tests in
  `tests/output/ScanoutAuto.cpp`, hyprtester's `directScanout*`): `docs/notes/direct-scanout.md`.
- Also in `docs/notes/renderer.md`: the keymap sharing for fcitx5's focus changes, animations computed for the next
  vblank, realtime and its guard, the fence experiment that was taken out, and a closing window's fade.

Profile guided builds (2026-11-16): `scripts/pgo/pgo.sh train DIR HOST...` and `build DIR` make a package with GCC's
profile feedback and the training's function order, 4 to 6.5% less compositor CPU a frame and 3.3 MiB less code in
memory in the night of 2026-11-15; the deploy's and the release's packages stay plain. See `docs/notes/performance.md`.

Performance and memory: `docs/notes/performance.md` has the GPU time per frame on the X200, the CPU profiles
(`./profile.sh` installs the package with `hypoland-debug`, records five workloads with `perf` and prints the report to
`test-results/profile-*/profile.txt`), the memory breakdown and the overnight runs of 2026-09-28 and 29, with what was
checked and found not worth doing. The X200 uses the HPET clocksource, so every clock read is a system call; fill rate
is its limit (a fullscreen blended surface costs about 3.3 ms); the binary's code is the largest Pss item.

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
  `~/Work/infrastructure/MACHINES.md`.
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

Nothing is left of the plan above: the screen shaders, its last item, were removed on 2026-11-12.

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
