# Hypoland r992 vs Hyprland 0.57.2 on twelve machines, 2026-11-14 to 15

Hypoland master r992 (`92942ceba`) against stock Hyprland 0.57.2-2: every workload of `scripts/bench/measure.sh` with the
games, ElectroBench and the file managers, on every test machine, 14 to 22 fresh sessions of each per machine, alternating
from 14:38 on 2026-11-14 to 07:30 on 2026-11-15. It was made the same way as `../20261111-all-machines-r966-vs-hyprland-0.57.1/`.
The lab, terminals, games and file manager pages (`scripts/web/labdata.py`) take their numbers from here since
2026-11-15 (the file manager page Nautilus's from the 11-11 night, the last with Nautilus on the machines). Compare a later
build with `<machine>/hypoland/values.txt` to see whether it got slower, and with `<machine>/hyprland/values.txt` to see
where it stands against Hyprland 0.57.2.

## Setup

- Hypoland: `hypoland 0.3.0.r992.g92942ceba-1`, master `92942ceba`, built from a clean worktree; the Galaxy Book and the
  Mac mini M1 built their own aarch64 packages of the same commit.
- Hyprland: `hyprland 0.57.2-2` and `omarchy-hyprland-titlebars 0.4.0-1` from each machine's pacman cache, with
  `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`) and on the X200 Omarchy's GLES 3 override
  (omacom/omarchy#14764, `pr/`).
- Omarchy-dev r7840 to r7850 (the Galaxy Book Omarchy 4.5.0-3), which exports `HYPRLAND_NO_RT=1`, so both compositors ran
  without realtime scheduling except on the Galaxy Book. Mesa 26.2.7 (the Galaxy Book 26.2.6).
- Omarchy's update of 2026-11-13 removed Nautilus (its workloads skip, except on the Galaxy Book) and with its orphan
  cleanup hyprcursor and tomlplusplus, which stock Hyprland needs; they were installed again as dependencies.
- The file managers: Flea 0.4.2, Folio 0.4.0 (which still does not scroll the list to the cursor, omacom/folio#18). The
  X200 ran without Flea (it opens no window on GM45), the Mac mini M1 has no Flea.
- New: the ThinkPad P14s Gen 2a (`p14s`, Ryzen 7 PRO 5850U, Vega 8 on `radeonsi`, 3840x2160 at scale 2) and the HP
  laptop with an A6-7310 (`hp-amd`, Radeon R4 on `radeonsi`), both joined that day. The Mac mini 2014 ran on its monitor
  (HDMI-A-2), not on a headless output as in the nights before.
- The runner is `abnight.sh` (`start.sh` starts it), with the deploy check in the first round
  (`<machine>/hypoland-check.txt`, `hyprland-check.txt`); `<machine>/log` is the runner's log. `report.sh` fetched the
  blocks and wrote `<machine>/<compositor>/values.txt` (`<key> <median> <min> <max>` over the blocks; with an even count
  the lower middle value), `raw.txt` (every block's values, `@ <block> <key> <value>`) and `bench.txt`; `table.py` wrote
  `table.txt` (its hp-amd column is empty). The block files are not kept here. `cam1.sh` photographed the XPS's screen
  every 30 s through the night (the pictures are not kept here).
- Nothing left out.

## What it shows

hp-amd has no numbers: its GPU hung at 15:16:55 under GravityMark in its first Hypoland block (`amdgpu 0000:00:01.0: ring
gfx timeout ... Process GravityMark.x64`, then a GPU reset), and the machine went silent.

Session checks (first round): Hypoland passed all on the twelve machines. Hyprland failed 4 to 60 (render checks on
every machine; the GTK 4 window did not map on the X200).

Compositor CPU per frame on the screen, workloads at least 10% cheaper / within 10% / at least 10% dearer under Hypoland
(the Mac mini M1's display driver reports no page flips, so it has none):

| x200 | t550 | xps | lianli | chromebook | t460s | t490 | samsung-i5 | galaxybook | macmini-intel | macmini-m1 | p14s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 24/1/0 | 42/1/0 | 43/0/0 | 24/14/0 | 36/2/0 | 43/2/0 | 40/5/0 | 41/1/0 | 37/6/3 | 40/3/0 | - | 32/3/0 |

Dearer: the Galaxy Book's menu (Hypoland 6.86 against Hyprland 4.56 ms, as in the baselines before), Flea scrolling
(0.48 against 0.37) and GTK 3 scrolling (1.05 against 0.93). Pss at the start 40 to 57 MiB against 115 to 145.

Behind Hyprland besides: frames on the screen in many-windows-10 on the T550 (30 against 49 fps) and many-windows-10/20 on
the Mac mini 2014 and the Galaxy Book, Velocitty on the T490 (27.5 against 32.1 fps, as before), a toast later on some
Intel machines. `launch.closed_ms` is 105 to 140 ms under Hypoland against 2 to 25 under Hyprland, as in the r966 night:
Hypoland shows the closing window's fade.

Against r966 (the 11-11 night) most differences moved Hyprland the same way (the Mac mini 2014 on its monitor, Omarchy's
update: the bar after a workspace switch on lianli 2.4 -> 16 ms under both). Hypoland's alone: lianli's
`workspace-switch.workspace_ms` 2.0 -> 7.0 (per block either about 1.8 or 7 to 10; Hyprland 1.9; r991 2.4 on 11-12), not
looked into yet.

Crashes: no compositor crash of Hypoland. Hyprland on the X200 hit a GPU hang at 05:14 and aborted in
`CHyprOpenGLImpl::begin`; the GTK 4 test client crashed with SIGFPE 45 times there, all under Hyprland. GravityMark
segfaulted on the T550, the XPS and the Galaxy Book under both, as in the nights before; one SuperTuxKart race of 14 on the
T460s had a Steady FPS of 0 under Hypoland. Xwayland aborted at session ends (the next block's SDDM restart) under both.
