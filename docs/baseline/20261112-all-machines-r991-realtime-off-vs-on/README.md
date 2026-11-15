# Hypoland r991, realtime off against on, on eleven machines, 2026-11-12 to 13

Hypoland master r991 (`e5a1c2d8e`) alone, no stock Hyprland: every workload of `scripts/bench/measure.sh` with the
games, ElectroBench and the file managers, on every test machine, in blocks that alternate between `HYPRLAND_NO_RT=1`
(`nort`: no realtime scheduling, what Omarchy sets) and `HYPRLAND_NO_RT=0` (`rt`: realtime with the guard thread), the
order reversed every other round, 8 to 12 fresh sessions of each per machine, from 21:10 on 2026-11-12 to between 06:35
and 07:15 on 2026-11-13.

The web pages (`scripts/web/labdata.py`: lab, terminals, games, file managers) took Hypoland's numbers from here from
2026-11-13 to 15 (since then both compositors' from `../20261114-all-machines-r992-vs-hyprland-0.57.2/`), the `nort` sessions (on the Galaxy Book the `rt` ones: its Omarchy 4.5 does not set `HYPRLAND_NO_RT`, so
Hyprland ran with realtime there), against Hyprland's from the night before,
`../20261111-all-machines-r966-vs-hyprland-0.57.1/`. Nothing was updated between the two nights but Folio (0.1.1, 0.2.0
on aarch64, to 0.4.0 at 11:04 on 2026-11-12), so the pages kept Folio on the night before, and the Mac mini 2014, which
ran on a headless output then and on its monitor here, was left out.

## Setup

- Hypoland: `hypoland 0.3.0.r991.ge5a1c2d8e-1` built on the desktop; the Galaxy Book and macmini-m1 built their own
  aarch64 package of the same commit (`r991.ge5a1c2d`).
- As the night before: Omarchy-dev r7677 (the Galaxy Book Omarchy 4.5.0-3), Mesa 26.2.6 (macmini-m1 mesa-aurora
  26.3.0), kernel 7.2.15-2. The Mac mini 2014 had its HDMI output (1920x1080 through the KVM).
- The variable went into `~/.config/uwsm/env.d/90-hypoland-rt`, read after Omarchy's own; each block logged the
  compositor's `HYPRLAND_NO_RT` and its main thread's policy (`nort` SCHED_OTHER, `rt` SCHED_RR|SCHED_RESET_ON_FORK).
- The runner is `abrt.sh` (`start.sh` started it), with the timers and Omarchy's update checks stopped, the deploy's
  session check in the first round (`<machine>/nort-check.txt`, `rt-check.txt`), and after every block: whether the
  measured compositor still ran, core dumps (`cores-*.txt`), crash reports and the compositor's realtime lines in the
  journal (`realtime-*.txt`; a line of a block can come from the compositor of the block before, stopped at its start).
  `<machine>/log` is the runner's log. `report.sh` fetched the blocks and wrote `<machine>/<nort|rt>/values.txt`
  (`<key> <median> <min> <max>` over the blocks; with an even count the lower middle value), `raw.txt` (every block's
  values, `@ <block> <key> <value>`) and `bench.txt`, and `report.txt`, `bench.sh --compare nort rt` per machine. The
  block files are not kept here.

## What it shows

Realtime on against off (`report.txt`):

| | workspace switch | menu open | app launch | screen fps, 10 busy windows |
|---|---|---|---|---|
| x200 | -4.1 ms | -4.0 ms | -2.1 ms | -3.9 |
| chromebook | -7.1 | +31 | -6.5 | 0 |
| xps | -0.7 | +45 | +0.8 | 0 |
| samsung-i5 | -0.7 | +27 | +1.1 | -3.8 |
| lianli | -0.9 | +15 | -1.2 | -0.6 |
| t550 | -0.5 | +9.5 | +0.2 | -3.0 |
| macmini-intel | -0.9 | +9.8 | 0 | -3.7 |
| t460s | -0.6 | -5.6 | -1.4 | -2.7 |
| t490, galaxybook | about 0 | about 0 | about -1 | about 0 |

- The compositor's own reactions (focus, workspace switch, closing a window, the bar) are faster with realtime on every
  machine with latencies: by 6.5 ms on average on the Chromebook and 3.2 ms on the X200, half a millisecond on the others.
  Its CPU time per frame is the same.
- Against it: the menu (the launcher starting) opens 10 to 45 ms later on six machines, in nearly every round, and with
  10 windows keeping the CPU busy 3 to 4 frames a second fewer reach the screen on five: the clients get less CPU next to
  a realtime compositor.
- The guard dropped realtime once or twice in some `rt` blocks (most often on the Galaxy Book, the Mac mini 2014 and the
  T550; on the T550 when GravityMark went fullscreen) and restored it 2 s later every time; rtkit never killed the
  compositor.

Session checks (first round, both variants): 103 passed on the X200, lianli, the Chromebook, macmini-intel and macmini-m1,
76 or 77 with the render checks skipped at fractional scale on the T550, T460s, T490 and samsung-i5; the XPS and the
Galaxy Book (scale 2) failed `render fullscreen smaller rectangles`: the centring of a small fullscreen surface
(`e5a1c2d8e`) put it half a logical pixel in, which its integer damage cut off. Fixed on `wip/rt-fixes` (r992, the offset
on whole logical pixels), 105 of 105 on both machines on 2026-11-13.

Crashes: no compositor died. GravityMark crashed in Mesa in every block on the machines that run it (the same with stock
Hyprland the nights before), Xwayland aborted at a few session ends (it resets after its last client and cannot reach the
compositor that is going away; seen since at least 2026-11-06), hyprland-dialog at session ends on the X200 (stock too),
Yamagi Quake II once on quit writing its config, SuperTuxKart once on a corrupted heap.

Against r966 of the night before (`hypoland/values.txt` there against `nort/values.txt` here): memory lower on every
machine (Pss and Rss, the binary smaller after the dead code and effects removal), the rest about the same.
