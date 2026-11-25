# Hypoland 0.4.0 vs Hyprland 0.57.2 on fourteen machines, 2026-11-24 to 25

The Hypoland 0.4.0 release against stock Hyprland 0.57.2-2: every workload of `scripts/bench/measure.sh` with the games,
ElectroBench and the file managers, alternating fresh sessions from 16:50 on 2026-11-24 to 09:00 on 2026-11-25, made
the same way as `../20261118-all-machines-r1030-pgo-vs-hyprland-0.57.2/`. Since 2026-11-25 the lab, terminals, games and
file manager pages (`scripts/web/labdata.py`) take their numbers from here, and compare nothing but 0.4.0 against
0.57.2.

Twelve machines are here, 11 to 21 sessions of each compositor:

| machine | Hypoland / Hyprland sessions |
|---|---|
| t550 | 12 / 12 |
| xps | 11 / 11 |
| lianli | 14 / 14 |
| chromebook | 11 / 11 |
| t460s | 11 / 11 |
| t490 | 12 / 12 |
| samsung-i5 | 13 / 13 |
| macmini-m1 | 14 / 14 |
| hp-amd | 21 / 21 |
| macmini-intel | 12 / 12 |
| msi-claw | 19 / 19 |
| galaxybook | 19 / 19 |

The X200 and the Turbo-X ran that night too but hung in a stock Hyprland session (the X200 at 20:12, the Turbo-X at
03:32 out of its 1 GB): their numbers pool the sessions of that night and of 11-25 and are in
`../20261125-x200-turbox-0.4.0-vs-hyprland-0.57.2/` (`FALLBACK` in `labdata.py`). The ThinkPad P14s was left out (the
btrpkg test machine at the time) and has no 0.4.0 numbers.

## Setup

- Hypoland: the v0.4.0 release packages, plain builds (tag v0.4.0, commit 8c78483ff): `hypoland-0.4.0-1-x86_64.pkg.tar.zst`
  (`/usr/bin/hypoland` 12770928 B) and on the Mac mini M1 and the Galaxy Book `hypoland-0.4.0-1-aarch64.pkg.tar.xz`
  (12012544 B). 0.4.0 has the same `src/` as r1029, and measured the same as the r1029 night of 11-17 within noise.
- Hyprland: `hyprland 0.57.2-2` and `omarchy-hyprland-titlebars 0.4.0-1` from each machine's pacman cache, with
  `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`).
- Both without realtime scheduling (`HYPRLAND_NO_RT=1`, as Omarchy runs Hyprland), except on the Galaxy Book.
- Apps: Folio 0.6.1-1 and Flea 0.4.3-1 (Omarchy's packages; the MSI Claw had Folio 0.7.1).
- hp-amd ran `hp-amd-workloads.txt` (no GravityMark: an amdgpu ring timeout there needs a power cycle).
- The Galaxy Book had 10 Omarchy migrations pending, so their notification sat at the top right at the start of every
  session; Hypoland's session check still passed every check there.

## Results

`summary.txt`, `table.txt` and `compare.txt` (0.4.0 against the r1029 and r1030 nights). In short: Hypoland's compositor
CPU 0.58 to 0.89 of stock's, CPU per frame 0.56 to 0.89, latencies 0.25 to 0.98, screen fps equal or higher, memory at
the start 40 to 51 MiB against 115 to 154. Behind stock on the MSI Claw: foot scrolling, dragging a split and Qt software
scrolling cost Hypoland 4 to 7 times the CPU there.

Per machine: `hypoland/` and `hyprland/` (`values.txt`: key, median, min, max over the sessions; `raw.txt`: every
session's values; `bench.txt`; `results.om` is not committed), the round-1 session checks and abnight's log.
