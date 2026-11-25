# Hypoland r1030 (PGO) vs Hyprland 0.57.2 on twelve machines, 2026-11-18 to 19

Hypoland master r1030 (`154befc6b`) against stock Hyprland 0.57.2-2: every workload of `scripts/bench/measure.sh` with
the games, ElectroBench and the file managers, on twelve test machines, 10 to 16 fresh sessions of each per machine,
alternating from 20:34 on 2026-11-18 to 09:00 on 2026-11-19. It was made the same way as
`../20261117-all-machines-r1029-vs-hyprland-0.57.2/`. The lab, terminals, games and file manager pages
(`scripts/web/labdata.py`) take their numbers from here since 2026-11-24.

**This is a PGO build.** The profile came from `pgo-20261118`, trained on x200, chromebook, lianli, p14s, t460s and xps;
`/usr/bin/hypoland` is 9379 kB against 12471 kB for r1029's plain build. The released packages are plain builds, and PGO
measured 4 to 6 % less compositor CPU and 6 to 7 % less memory at the start than the plain r1029 night
(`../20261117-all-machines-r1029-vs-hyprland-0.57.2/`), with the same fps and equal or a little lower latencies
(`compare.txt`). The pages' notes say the build is PGO; compare a later plain build against
`../20261117-all-machines-r1029-vs-hyprland-0.57.2/`, not against here.

Three machines do not read their numbers from this night (`FALLBACK` in `scripts/web/labdata.py`):

- the Samsung Galaxy Book4 Edge (not in this night at all: reinstalled as stock Omarchy on 11-17) and the Mac mini Late
  2014 (`sshd` off) keep the night of 2026-11-14 to 15 (`20261114-all-machines-r992-vs-hyprland-0.57.2`);
- the ThinkPad P14s Gen 2a keeps the night of 2026-11-17 to 18: its PGO build aborted (`SIGABRT`, `hypoland
  --watchdog-fd 4`) in the video workload about 3 min into **every one** of its 11 Hypoland sessions and restarted in
  safe mode, so every later workload measured a safe-mode session. `p14s/hypoland/` is kept here for the record and is
  not shown anywhere; its stock blocks are fine on their own. Crash reports are on p14s in
  `/home/a/.cache/hyprland/hyprlandCrashReport*.txt`; the debug package of that build is on the desktop, outside the
  repository (`test-results/pgo-20261118/`, which git does not track).

## Setup

- Hypoland: `hypoland 0.3.0.r1030.g154befc6b-1`, a PGO build of master `154befc6b`; the Mac mini M1 built its own
  plain aarch64 package of the same commit (11731 kB, as r1029's plain build; PGO is x86-only).
- Hyprland: `hyprland 0.57.2-2` and `omarchy-hyprland-titlebars 0.4.0-1` from each machine's pacman cache, with
  `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`) and on the X200 Omarchy's GLES 3 override
  (omacom/omarchy#14764, `pr/`).
- Omarchy-dev r7840 (`HYPRLAND_NO_RT=1`: both compositors without realtime scheduling), Mesa 26.2.7, kernel
  7.2.15-2-omarchy — the same system as the 11-17 night, except the two clients below.
- The file managers: this is the first night with Omarchy's **packages** instead of a pinned build — `folio 0.6.1-1`
  (installed on every machine 11-18 18:49, an hour before the night started; `/opt/folio/<commit>/` and its
  `folio.sh` wrapper are gone) and `flea 0.4.3-1` (11-18 17:52). The 11-17 night's Folio was commit `2e2a716` built on
  every machine, the 11-14 night's Omarchy's Folio 0.4.0: their Folio cells do not compare with these directly.
- Left out: the Galaxy Book (reinstalled as stock Omarchy on 11-17). The HP laptop (`hp-amd`) again ran without
  GravityMark (`hp-amd-workloads.txt`): its amdgpu ring timeout under it needed a power cycle on 11-14 and 11-16.
- The runner is `abnight.sh` (`start.sh` starts it), with the deploy check in the first round
  (`<machine>/hypoland-check.txt`, `hyprland-check.txt`); `<machine>/log` is the runner's log. `report.sh` fetched the
  blocks and wrote `<machine>/<compositor>/values.txt` (`<key> <median> <min> <max>` over the blocks), `raw.txt` (every
  block's values, `@ <block> <key> <value>`), `bench.txt` and `results.om`; `table.py` wrote `table.txt`, `compare.py`
  `compare.txt` (against the night of 11-17, r1029 plain). The block files are not kept here.
- `x200.skip` lists the X200 blocks `report.sh` leaves out (see below); the values here were written with it, while the
  morning's `table.txt` and `compare.txt` still include them.

## What it shows

`summary.txt` is the morning's report. In short: blocks (Hypoland / stock) x200 12/12, t550 11/11, xps 10/10, lianli
13/13, chromebook 10/10, t460s 10/10, t490 10/10, samsung-i5 11/11, macmini-m1 13/13, hp-amd 16/16, p14s 11/11,
macmini-intel 11/11. Hypoland against stock: compositor CPU 0.57 to 0.81 of stock's, CPU per frame 0.49 to 0.80,
latencies 0.24 to 0.94, Pss at the start 0.32 to 0.38 (x86), fps equal or higher (X200 1.13).

x200: the i915 GPU hung four times through the night (xonotic-sdl at 00:50 and 01:36, Hyprland itself at 02:13, and the
qt-quick client at 05:28), after 05:28 the reset failed (`failed to set rcs0 head to zero`) and from 06:26 no session
started at all. So its blocks 1 to 11 are the usable ones: `hypoland-12.txt` (killed after 40 min, 4 invalid
workloads), `hypoland-13-startup.txt` (17 values) and `hyprland-8.txt` (5 invalid) are listed in `x200.skip` and left
out, which leaves **11 sessions of each**. The hangs hit both compositors, so not clearly PGO. The machine needed a
reboot (LUKS, no KVM) and its governor was set back from `performance` to `schedutil` by hand.

macmini-m1 is not comparable night to night here: the machine was found at its disk prompt on 11-18 and unlocked at
17:42, so it ran on a fresh boot and stock itself moved (CPU 1.19, latencies 1.40 against the 11-17 night) while
Hypoland measured 0.937.

Core dumps: no Hypoland crash outside p14s. GravityMark `SIGSEGV` on t550 (22) and xps (20) as before; on the X200 25
python3 `SIGFPE` (the GTK 4 client under stock, known), 1 ElectroBench, 1 Xwayland, and the Hyprland and
sddm-greeter-qt6 cores of the GPU hang above; Xwayland at session end (chromebook 2, samsung-i5 3, macmini-intel 2);
SuperTuxKart on hp-amd (3).
