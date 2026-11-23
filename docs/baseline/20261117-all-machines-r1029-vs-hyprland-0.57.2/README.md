# Hypoland r1029 vs Hyprland 0.57.2 on eleven machines, 2026-11-17 to 18

Hypoland master r1029 (`5078f26de`) against stock Hyprland 0.57.2-2: every workload of `scripts/bench/measure.sh` with the
games, ElectroBench and the file managers, on eleven test machines, 9 to 16 fresh sessions of each per machine, alternating
from 21:03 on 2026-11-17 to 09:00 on 2026-11-18. It was made the same way as `../20261114-all-machines-r992-vs-hyprland-0.57.2/`.
The lab, terminals, games and file manager pages (`scripts/web/labdata.py`) take their numbers from here since
2026-11-21; the Galaxy Book and the Mac mini 2014, which this night did not have, keep the 11-14 night's (`FALLBACK`
there). Compare a later build with `<machine>/hypoland/values.txt` to see whether it got slower, and with
`<machine>/hyprland/values.txt` to see where it stands against Hyprland 0.57.2.

The night of 2026-11-18 to 19 (r1030) ran a PGO build, about 4 to 6 % less compositor CPU; the released packages are
plain builds, so this plain r1029 night is the one the pages show.

## Setup

- Hypoland: `hypoland 0.3.0.r1029.g5078f26de-1`, a plain build of master `5078f26de`; the Mac mini M1 built its own
  aarch64 package of the same commit (`r1029.g5078f26`).
- Hyprland: `hyprland 0.57.2-2` and `omarchy-hyprland-titlebars 0.4.0-1` from each machine's pacman cache, with
  `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`) and on the X200 Omarchy's GLES 3 override
  (omacom/omarchy#14764, `pr/`).
- Omarchy-dev r7840 (`HYPRLAND_NO_RT=1`: both compositors without realtime scheduling), Mesa 26.2.7.
- The file managers: Flea 0.4.2-2 (no window on the X200, not installed on the Mac mini M1), Folio commit `2e2a716`
  (omacom/folio#79, after 0.5.0) built on every machine into `/opt/folio/<commit>/`, which scrolls the list to the
  cursor on Down (Omarchy's 0.4.0 of the 11-14 night did not).
- Left out: the Galaxy Book (reinstalled as stock Omarchy on 11-17) and the Mac mini 2014 (sshd off). The HP laptop
  (`hp-amd`) ran without GravityMark (`hp-amd-workloads.txt`): its amdgpu ring timeout under it on 11-14 and 11-16
  needed a power cycle.
- The runner is `abnight.sh` (`start.sh` starts it), with the deploy check in the first round
  (`<machine>/hypoland-check.txt`, `hyprland-check.txt`); `<machine>/log` is the runner's log. `report.sh` fetched the
  blocks and wrote `<machine>/<compositor>/values.txt` (`<key> <median> <min> <max>` over the blocks), `raw.txt` (every
  block's values, `@ <block> <key> <value>`), `bench.txt` and `results.om`; `table.py` wrote `table.txt`, `compare.py`
  `compare.txt` (against the night of 11-16, r1025). The block files are not kept here.

## What it shows

`summary.txt` is the morning's report. In short: blocks (Hypoland / stock) x200 15/15, t550 11/11, xps 10/10, lianli
13/13, chromebook 9/9, t460s 10/10, t490 10/10, samsung-i5 11/11, macmini-m1 13/13, hp-amd 15/15, p14s 13/13; no machine
stopped, no GPU hang, no compositor core dump, Hypoland passed every session check. r1029 is r1025 within each machine's
night-to-night noise. Hypoland against stock: compositor CPU 0.57 to 0.87 of stock's, CPU per frame 0.55 to 0.83,
latencies 0.28 to 0.95, Pss at the start 0.34 to 0.44 (40 to 57 MiB against 115 to 129), fps equal or higher (X200
1.13).
