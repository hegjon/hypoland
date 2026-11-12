# Hypoland r964 vs Hyprland 0.57.1, games and 3D benchmarks, 2026-11-11 (two sessions)

A short A/B run, not a full regression baseline: it was planned to last until 2026-11-13 and was stopped by the user after
2.5 hours, so it has **2 fresh sessions of each compositor per machine** (Hypoland 3 on the X200, lianli and macmini-m1).
Every median in `values.txt` over two values is the lower one. The full regression baseline of the same compositor
code is `../20261110-all-machines-r957-vs-hyprland-0.57.1/` (8 to 10 sessions). This directory is kept for the
benchmarks that night did not have: Phoronix's graphics benchmarks of its first Snapdragon X2 Elite article
(SuperTuxKart, Yamagi Quake II, vkmark) and Folio (`folio`). The games page (`web/games.html`, `scripts/web/games.py`)
takes those from here and Xonotic, GravityMark and ElectroBench from the r957 baseline.

## Setup

- Hypoland: `hypoland 0.3.0.r964.g9897075b1-1` (the Galaxy Book and macmini-m1 `r964.g9897075`, built on the machines),
  built from the local branch `wip/long-ab`, commit `9897075b1`: master `70bc22bad` plus the game workloads, which are
  on master now as `4d170f372`. The compositor is master `70bc22bad`, the same as r957 (`29b9f86a9`) but for
  `a31250872` (a monitor connecting during a capture) and `679f22ba2` (one shm texture on asahi).
- Hyprland: `hyprland 0.57.1-2` and `omarchy-hyprland-titlebars 0.3.0-4` from each machine's pacman cache, with
  `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`) and on the X200 Omarchy's GLES 3 override (`pr/`).
- Ten machines: all of the lab but samsung-i5. Omarchy-dev r7677 (the Galaxy Book Omarchy 4.5.0-3), Mesa 26.2.6
  (macmini-m1 mesa-aurora 26.3.0), `packages.txt`. Games: SuperTuxKart 1.5, vkmark 2025.01, Yamagi Quake II 8.10 with
  ref_vk 1.0.2 (`scripts/machines/yquake2.sh`), Xonotic 0.8.6, GravityMark 1.89, Folio 0.1.1 (x86) / 0.2.0 (aarch64).
- macmini-intel had no monitor (its HDMI goes to a KVM): `headless-helper.sh` gave each session a headless output, so
  it has no frames on the screen and no render checks; its game frame rates are a headless output's.
- The X200 ran without `flea` and `flea-scroll`: Flea 0.4.1 needs Vulkan, fails on GM45 and leaves a critical
  notification over the windows for the rest of the session.
- The runner is `abnight.sh` (`start.sh`), as in the baselines before, with `ABNIGHT_CHECK=1` (each compositor's session
  check in the first round: `<machine>/<compositor>-check.txt`). `report.sh` and `table.py` made `values.txt`,
  `raw.txt` and `table.txt` (they read a run directory with the machines one level down).

## Results

Session checks: Hypoland passed all on eight machines; macmini-intel failed 2 on both sides (no scanout to read on the
headless output); macmini-m1 failed one, `render fullscreen left`, 201 pixels in the bottom right corner where the check
parks the pointer (not looked into). Stock failed 1 to 52 render checks. No compositor died.

The compositor's CPU per frame on the screen is lower under Hypoland in 23 to 46 workloads a machine and more than 10%
higher only in the Galaxy Book's menu (as in the r957 baseline), bimodal GTK 3 through Xwayland on the T490 and the
Galaxy Book, the M1's video window and the M1's Yamagi Quake II with Vulkan (below). Pss at the start 39 to 49 MiB
against 115 to 146.

The new benchmarks (Hyprland 0.57.1 > Hypoland):

- Yamagi Quake II, OpenGL 3: the compositor half or less (T550 35.4 > 18.3%), the game's frame rate higher (T550 90.3 >
  100.3, XPS 35.1 > 44.5, T460s 77.5 > 84.8). Vulkan: the compositor a third or less, the game 2 to 4% faster; on
  macmini-m1 the game drew 632 > 1508 fps with the compositor at 4.7 > 34.6% (a client without vsync outrunning the
  display on the plane; the M1 counts no page flips, so what reached the screen is not known).
- vkmark: a higher score on every machine (Galaxy Book 2661 > 3717, Mac mini 2014 439 > 742, Chromebook 332 > 436).
- SuperTuxKart (Vulkan): the compositor about a third, but two problems of Hypoland's measured direct scanout
  (`render:direct_scanout = auto`):
  - The race stalls: its Steady and Mostly stable FPS were 0 in 1 of 2 sessions on the T550 and the XPS and in 2 of 2 on
    the T460s and the Galaxy Book, the race 4 to 9 s longer (T550 42.8 s against 38.9, Galaxy Book 44.2 against 38.1);
    never under stock, never on the T490, the Chromebook or the headless Mac mini. No GPU hang in the kernel logs. Run
    alone afterwards on the T460s, with direct scanout off and then auto set at runtime, it did not stall either way.
    Open.
  - macmini-m1: no result in 3 of 3 sessions, the game aborts with `vkCreateSwapchainKHR failed`. With
    `render:direct_scanout = 0` set at runtime it runs: 263.2 fps, Steady 123, Mostly stable 215 (stock 252.7, 116, 195).
    Open.
- Folio: the compositor about half (T550 3.1 > 1.7%), the X200 shows 13.5 > 17.8 frames a second in `folio` and
  43.6 > 57.8 in `folio-scroll`.
