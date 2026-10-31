# Hypoland vs Hyprland 0.57.0 on eight machines, overnight 2026-10-30 to 31

The regression baseline against Hyprland 0.57.0: every workload of `scripts/bench/measure.sh` on every test machine,
Hypoland r871 against stock Hyprland 0.57.0-2, 10 to 12 fresh sessions of each per machine, alternating through the
night. Compare a later build with `<machine>/hypoland/values.txt` to see whether it got slower, and with
`<machine>/hyprland/values.txt` to see where it stands against Hyprland 0.57.0. It follows the 0.56.2 baseline of three
nights before, `../20261027-all-machines-r761-vs-hyprland-0.56.2/`, made the same way.

## Setup

- Hypoland: `hypoland 0.2.0.r871.g9189141d0-1`, the Arch package built from master `9189141d0`: the partial port of
  Hyprland 0.57.0 (`de57aacad`, it reads 0.57.0 configs without errors) and the zero-copy flush fix of that evening
  (`23261a25c`). The Galaxy Book built its own package on the machine from the same commit
  (`0.2.0.r871.g9189141-1`). The run used a copy of `scripts/bench` at `e1e69b926`, which added the `launch` and
  `many-windows` workloads to the default list.
- Hyprland: the Arch packages `hyprland 0.57.0-2` and `omarchy-hyprland-titlebars 0.3.0-2` from Omarchy's repository
  (the aarch64 ones on the Galaxy Book), installed from each machine's pacman cache for every Hyprland block.
- Hyprland 0.57.0 runs with `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`, required from Omarchy's
  `envs.lua` for its blocks only). With its default `true` it came up broken on the T550 (Broadwell, `iris`) under
  Omarchy r7438: no wallpaper, half of the bar, and EGL clients that ask for alpha get no config (`weston-simple-egl`:
  `init_egl: Assertion 'ret && n >= 1' failed`), so the GPU client measured 0 fps and the launch workload saw no change
  on the screen. Hyprland 0.56.2 did not do this. Hypoland defaults to `false` (Gen 4 planes have no alpha formats), so
  with the quirk both sides offer clients the same formats.
- On the X200 Hyprland 0.57.0 does not start on its own (GM45 has GLES 2 only), so it runs with Omarchy's GLES 3
  override (omacom/omarchy#14764, `pr/`) as in the 0.56.2 baseline, and its clients get the override's Mesa variables
  (`MESA_GLES_VERSION_OVERRIDE=3.0`, `MESA_GLSL_VERSION_OVERRIDE=300`).
- Both run Omarchy's own config through SDDM and uwsm, Omarchy `omarchy-dev 4.0.0.r7438` on the `omarchy-dev` channel.
  `packages.txt` lists the packages the clients come from on every machine.
- The runner is `abnight.sh`, run as root on each machine, detached (`start.sh` copies it, `pr/`, `scripts/bench` and
  the package to `/root/abnight` and starts it). A block is one compositor: its package installed with `pacman -U`,
  SDDM restarted for a fresh session (the Quickshell logs in `/run/user` removed first), 60 s after the shell is up
  `measure.sh --rounds 1`: every workload, 12 s each, the `performance` governor, memory 60 s after the compositor's
  start and 10 s after the last workload. A round is one block of each, the order alternating per round, and a round
  starts only while one more fits before the end. In the first round each block also ran the deploy check
  (`measure.sh --mode check`, `ABNIGHT_CHECK=1`): `<machine>/hypoland-check.txt` and `hyprland-check.txt`. The system
  timers and Omarchy's update checks are stopped for the run.
- The opt-in `startup` workload was left out (`ABNIGHT_NO_STARTUP=1`): in the smoke runs before the night its restart
  of SDDM left Hyprland 0.57.0 without a session on the T550 (`no session after the startup measurement`).
- The T490 is not in it: its host keys changed at 22:26 that evening (reinstalled), and it was left untouched.
- Started 23:15 on 2026-10-30, the end was set to 05:30 on 2026-10-31. The machines ended their last block between
  05:05 (the Chromebook, the slowest, 10 blocks of each) and 05:29 (the X200, 11 of each); the others ran 12 of each.

## Machines

| alias | machine | GPU, Mesa driver | screen | CPUs, RAM |
|---|---|---|---|---|
| `x200` | ThinkPad X200 | GMA 4500MHD (GM45, Gen 4.5), `crocus`, GLES 2 only | 1280x800 | 2, 6 GB |
| `t550` | ThinkPad T550 (host name `aa`) | HD Graphics 5500 (Broadwell), `iris` | 1920x1080 | 4, 16 GB |
| `xps` | Dell XPS 13 9343 | HD Graphics 5500 (Broadwell), `iris` | 3200x1800 at scale 2 | 4, 8 GB |
| `lianli` | desktop, AMD A8-6600K | Radeon HD 8570D, `r600` | 1920x1200 | 4, 8 GB |
| `chromebook` | Dell Chromebook 11 3120, Celeron N2840 | Bay Trail, `crocus`, GLES 3.0 | 1366x768 | 2, 4 GB |
| `t460s` | ThinkPad T460s, Core i7-6600U | HD Graphics 520 (Skylake), `iris` | 1920x1080 at scale 1.5 | 4, 20 GB |
| `galaxybook` | Samsung Galaxy Book4 Edge, Snapdragon X Elite, aarch64 | Adreno X1-85, `freedreno` (Vulkan: `turnip`) | 2880x1800 at scale 2, 120 Hz | 12, 16 GB |
| `macmini-intel` | Apple Mac mini Late 2014, Core i5-4260U | HD Graphics 5000 (Haswell GT3), `crocus` | 1920x1200 | 4, 4 GB |

The CPU count is what the kernel sees (threads). The hardware, addresses and rules of the machines are in
`~/Work/infrastructure/MACHINES.md` on the desktop.

## Files

- `table.txt`: compositor CPU, session CPU, frames on the screen and latency medians per workload and machine,
  Hyprland 0.57.0 -> Hypoland (`python3 table.py <run>`).
- `compare.txt`: `bench.sh --compare` per machine, every key, with its `better` / `WORSE` flags (`report.sh`'s
  output).
- `<machine>/hypoland/values.txt` and `<machine>/hyprland/values.txt`: `<key> <median> <min> <max>` over the blocks,
  the format `bench.sh --compare` reads; `bench.txt` next to it is the machine line. `raw.txt` has every value of every
  block (`@ <block> <key> <value>`), for the spread behind a median.
- `<machine>/log`: the runner's log with the time of every block; `<machine>/*-check.txt`: the deploy checks.
- `packages.txt`: `pacman -Q` of the packages the clients come from, on every machine, after the run.
- `abnight.sh`, `start.sh`, `pr/`, `report.sh`, `table.py`: the runner, the script that started it on the machines,
  the files the Hyprland blocks need, the fetch and compare, and the table.

## Checking a build against this baseline

- One machine: `./bench.sh --host <machine> --seconds 12 <label>` on a session that was restarted for it, then
  `./bench.sh --compare docs/baseline/20261030-all-machines-r871-vs-hyprland-0.57.0/<machine>/hypoland
  test-results/bench-<time>-<label>`. The blocks here were each a fresh session measured 60 s after login. One round
  moves within the min and max in `values.txt`, and the whole spread of a row is in `raw.txt`.
- All machines, against Hyprland 0.57.0 as well: `start.sh <run> <until> <package>` with `HOSTS` and `GALAXY_PKG` set
  (see the script; `ABNIGHT_NO_STARTUP=1` as here), then `report.sh <run> <machines>` and `table.py <run>` from the
  directory it fetched into.

## What it shows

Medians over the blocks, Hyprland 0.57.0 -> Hypoland; the whole table is `table.txt`, every value of every block
`raw.txt`.

### Memory

The compositor 60 s after the start and 10 s after the last workload (Pss in MiB) and its GPU buffers
(`drm-total-system0`, imported buffers included; radeon reports none):

| machine | Pss at the start | Pss at the end | GPU buffers at the start | at the end |
|---|---|---|---|---|
| X200 | 113.3 -> 41.3 | 116.0 -> 47.1 | 90.2 -> 64.2 | 90.1 -> 73.6 |
| T550 | 115.7 -> 42.3 | 115.8 -> 47.9 | 174.0 -> 112.6 | 268.7 -> 125.0 |
| XPS | 116.1 -> 42.6 | 116.8 -> 48.8 | 476.4 -> 297.3 | 777.7 -> 329.5 |
| lianli | 114.0 -> 41.4 | 114.8 -> 47.1 | | |
| Chromebook | 113.1 -> 40.4 | 115.1 -> 47.6 | 102.4 -> 85.1 | 124.3 -> 91.1 |
| T460s | 116.1 -> 41.8 | 116.6 -> 47.8 | 174.0 -> 112.7 | 292.5 -> 125.1 |
| Galaxy Book | 149.4 -> 44.2 | 154.3 -> 54.1 | 399.9 -> 334.5 | 1075.1 -> 362.8 |
| Mac mini | 113.2 -> 41.7 | 114.2 -> 46.1 | 209.9 -> 129.4 | 301.6 -> 143.6 |

Anonymous memory is 83 MiB (116 to 120 on the Galaxy Book) against 16 to 18 MiB at the start, the heap 66 MiB against
8 to 10 (most of Hyprland's is transparent huge pages, which Hypoland turns off for the compositor), and Hypoland
runs one to three threads fewer. With 40 windows open Hypoland holds 46 to 52 MiB (64 on the Galaxy Book) against 116 to
124 (162). Hypoland grows by 4 to 7 MiB over a run (10 on the Galaxy Book) where Hyprland 0.57.0 grows by 0 to 3 (5):
its heap is 14 to 15 MiB at the end against 8 to 10 at the start, the memory of the closed windows of `launch` and
`many-windows`, which nothing gave back to the kernel (`malloc_trim` ran only after shm uploads, and zero copy uploads
nothing). A trim a few seconds after the last destroyed surface, measured the next morning (six fresh sessions of
each on the T460s and lianli), takes 1.5 MiB of it back: the heap at the end 14.3 -> 12.8 MiB and 14.6 -> 13.1, anonymous
Pss the same, CPU and latencies unchanged. What stays is held, not free.

### Compositor CPU

Lower in almost every workload on every machine, the largest where clients draw into shm buffers, which Hypoland
samples in place (zero copy) or copies itself where Hyprland 0.57.0 has Mesa tile them (% of a CPU):

- `terminal-scroll` (foot): T550 11.9 -> 2.9, XPS 22.5 -> 3.1, lianli 13.6 -> 2.4, T460s 9.5 -> 2.8, Mac mini 19.7 ->
  3.3, Chromebook 15.3 -> 5.5, X200 14.7 -> 8.9, Galaxy Book 7.6 -> 6.9.
- `qt-software-scroll`: X200 25.8 -> 6.1, T550 18.3 -> 1.8, XPS 34.4 -> 1.9, lianli 11.4 -> 1.9, Chromebook 17.1 ->
  4.1, T460s 13.9 -> 2.1, Mac mini 9.7 -> 2.0; `qt-software-sprites` X200 54.3 -> 6.0 (at 31 -> 60 fps), lianli 62.8
  -> 3.0, Chromebook 61.4 -> 8.0 (29 -> 59 fps), Mac mini 38.9 -> 3.2, XPS 25.5 -> 3.4, Galaxy Book 23.6 -> 13.9.
- `gtk3-scroll`: X200 46.2 -> 16.2, Mac mini 28.9 -> 11.0, Chromebook 29.2 -> 14.3, T550 20.5 -> 12.5, XPS 24.3 ->
  16.0, lianli 28.9 -> 22.8; Chromium's full window (`shm-fullwindow`) X200 20.8 -> 7.8.
- `resize`: T550 20.4 -> 11.0, XPS 33.7 -> 19.9, T460s 19.0 -> 10.2, lianli 19.2 -> 11.8, Mac mini 31.6 -> 12.9,
  Chromebook 31.1 -> 22.5. On the X200 13.6 -> 21.5 at 30 -> 60 fps, 4.5 -> 3.6 ms a frame.
- Workspace switching 1 to 2 points lower everywhere but the Galaxy Book (3.7 -> 4.5), the developer's screen (`dev`)
  1 to 4 points (Chromebook 11.0 -> 7.4), the GPU client 0.7 to 3 points (Chromebook 9.3 -> 6.1, X200 4.2 -> 2.5), the
  menu 0.6 to 5 points except on the Galaxy Book (XPS 6.5 -> 1.5), many windows up to 7 points on the iris, r600 and
  Haswell machines and the Galaxy Book (T550 40 windows 18.4 -> 12.9, XPS 21.2 -> 14.4).
- The session as a whole (compositor, shell, Xwayland, clients) is lower or the same in almost every workload; on the
  X200 it is higher where Hypoland shows more frames (`resize` 72 -> 108, at twice the frames) or costs more itself
  (many windows, below).

### Frames on the screen

On the X200 Hyprland 0.57.0 (with the GLES 3 override) shows fewer frames in most workloads:
Alacritty 36 -> 48, `gtk3-x11-scroll` 23 -> 43, `qt-quick-scroll` 40 -> 57, `qt-software-sprites` 31 -> 60, `resize`
30 -> 60, `tk-canvas` 35 -> 57, workspace switching 16 -> 21, the notifications 23 -> 29. The Chromebook shows the
sprites at 59 instead of 29 and the terminal at 30 instead of 23; the XPS Alacritty at 60 instead of 50, Ghostty at 45
instead of 32, kitty at 52 instead of 41, GTK 3 at 47 instead of 42 and `resize` at 60 instead of 53; the Mac mini
Ghostty at 56 instead of 45 and 10 windows at 44 instead of 35; the Galaxy Book `gtk3-x11-scroll` at 50 instead of 30.
Hyprland 0.57.0 repaints the Galaxy Book's 30 fps fullscreen video 114 times a second (`fps.video.screen`), Hypoland 30.

### Latency

Hypoland opens Omarchy's terminal sooner everywhere (`launch.open`, until the screen first changes: T550 180 -> 127 ms,
XPS 277 -> 140, T460s 169 -> 128, Mac mini 163 -> 140, X200 258 -> 227; drawn and settled, `launch.opened`, 34 to 150 ms
sooner). On the iris machines a focus change, a workspace switch, a resize step, the menu's selection and its search
show one to two frames sooner (T550 / XPS / T460s, ms: focus 6.9 -> 1.6 / 7.0 -> 1.8 / 7.6 -> 1.8, resize step 6.9 ->
1.0 / 13.0 -> 1.2 / 9.6 -> 2.3, menu select 19.7 -> 5.1 / 29.2 -> 7.9 / 15.0 -> 4.0, menu search 124 -> 87 / 144 -> 92
/ 107 -> 72). Hyprland 0.57.0 closes the menu a frame or two later on the crocus and r600 machines (X200 26.8 -> 3.7,
Chromebook 29.7 -> 6.4, Mac mini 16.0 -> 3.2, lianli 15.9 -> 2.7): the cursor its simulated mouse move shows and the
next key hides, likely (upstream #16455 is in 0.57.0, not in 0.56.2; Hypoland fixed what it caused on 2026-10-27); 0.56.2
closed it in 3 to 10 ms there. `resize.redrawn` (both clients drew at the new size) is up to 13 ms sooner except on
the Mac mini.

### Where Hypoland is behind Hyprland 0.57.0

Medians of 10 to 12 blocks; where the blocks of the two do not overlap it says so:

- A focus change among many floating windows (`many-windows-<n>.focus`): T550 3.4 -> 13.7 ms with 10 windows and 4.1 ->
  14.1 with 20, XPS 9.1 -> 16.5 and 9.7 -> 16.2, Mac mini 8.6 -> 12.1 with 20 and 5.3 -> 10.7 with 40, T460s 8.9 ->
  10.4 and 11.4. Nothing is slower: the frame comes too soon. In the morning's variant runs on the T550, XPS and Mac
  mini the same build with `HYPOLAND_SHM_ZEROCOPY=0` and r761 (before zero copy) show 2.4 to 4 ms, with the alpha
  bounds off 7 to 28 ms. A perf timeline on the Galaxy Book (zero copy forced, which reproduced it: 6.9 to 9.6 against
  3.0 to 4.6 ms) has the compositor commit its first frame 1.4 ms after the arrow key with zero copy and 1.7 ms without,
  and every measured step is one of its commits: the first one when it came 2.5 ms or later after the key, the next one
  when it came sooner. Omarchy's border fades with easeOutQuint over 539 ms, and hyprutils' `getCurveStep()` takes the
  time in whole milliseconds when the frame is drawn, so a frame drawn within a millisecond or two of the focus change
  shows the old colour and the change comes with the next frame. Zero copy makes the first frame come sooner (foot's
  commits after the focus change need no copy). Fixed the next morning (2573c7db2): animations take their values for
  the vblank the frame is shown at; 6 to 8 fresh sessions each, a focus change among 10 / 20 / 40 windows XPS 10.2 / 16.8
  / 18.0 -> 2.1 / 2.5 / 2.8 ms, T550 14.4 / 14.4 / 13.4 -> 1.8 / 2.1 / 2.7, Galaxy Book 5.1 / 3.6 / 3.4 -> 2.4 / 2.1 /
  2.0, ahead of Hyprland 0.57.0 on all three. The T550 also shows 20 windows at 42 instead of 56 frames a
  second.
- Many windows on the X200: the compositor costs 7.7 -> 11.2% with 10 windows, 12.8 -> 19.4 with 20 and 20.3 -> 27.1
  with 40 at the same frames, 1.9 -> 2.7, 2.3 -> 3.3 and 3.4 -> 4.7 ms a frame (no block overlapping with 10 and 20).
  The Chromebook, the other machine without an LLC, is ahead with 10 windows, even with 20 and 5% behind with 40
  (5.65 -> 5.95 ms a frame). It is the zero copy itself, not its write-back from the caches: the next morning, the same
  build per frame with 10 / 20 / 40 windows, X200 copied (`HYPOLAND_SHM_ZEROCOPY=0`) 1.4 / 2.1 / 3.2 ms, sampled in place
  3.1 / 3.4 / 5.4, in place without the write-back (`force`) 2.2 / 3.1 / 5.2; Chromebook 2.1 / 3.1 / 4.9, 2.5 / 3.6 /
  5.9 and 2.5 / 3.6 / 5.9 (one to three fresh sessions each). foot scrolls by attaching a new `wl_buffer` further on in
  its pool for every line, and each new buffer was a udmabuf and an EGL import (6967 in two minutes of `many-windows`
  on the Galaxy Book with zero copy forced). The iris and Haswell machines pay it too, less: with 40 windows T550 1.9 ->
  2.25 ms, Mac mini 2.2 -> 2.6, XPS 2.1 -> 2.4 copied against in place. Fixed the next morning (e83a3f5ab): a small
  surface that keeps attaching new buffers is copied (below 1 MiB, 256 kB on radeon), 5 to 8 fresh sessions each, per
  frame with 10 / 20 / 40 windows X200 2.47 / 3.36 / 5.42 -> 1.44 / 1.99 / 3.22 ms (now below Hyprland 0.57.0's 1.91 /
  2.30 / 3.44), Chromebook 2.58 / 3.66 / 5.92 -> 1.96 / 2.88 / 4.82, Mac mini 2.52 -> 2.02 and T460s 2.03 -> 1.81 with
  40, the rest of the benchmark the same.
- A notification's toast: T550 20.7 -> 29.1 ms (8 of 12 blocks at 29 to 30 against 20 to 22), T460s 16.8 -> 21.1; the
  T550 had 22.3 with r761. The XPS, Mac mini, Chromebook and X200 show it as soon or sooner. Seven builds from r761 to
  r871 on the T550 the next morning, one or two fresh sessions each, were all between 19 and 31 ms, a frame apart, without a
  build where it steps; neither zero copy nor the alpha bounds off changes it. Open.
- Closing Omarchy's terminal (`launch.close`): Mac mini 3.7 -> 8.0 ms (Hyprland 0.57.0 bimodal, 3.6 or 8; Hypoland
  always 8), Chromebook 11.0 -> 14.2, X200 8.9 -> 9.6; on the iris machines and the Galaxy Book it closes 3 to 13 ms
  sooner.
- The Chromebook's focus change under the `dev` load, 5.0 -> 7.7 ms (9 of the 10 Hyprland blocks below every Hypoland
  block), while without load (`idle-windows`) it is 4.7 -> 3.7; kitty there shows 15 frames a second instead of 22 (no
  block overlapping; the compositor 4.1 -> 1.9%, kitty the same 113%). Not looked into.
- The Galaxy Book: workspace switching 3.7 -> 4.5% and the menu 1.7 -> 2.3 as against 0.56.2 (its idle clusters, see
  AGENTS.md), Omarchy's bar and the workspace's middle 0.7 to 0.9 ms later on a switch (1 against 2 ms at 120 Hz).
- The XPS opens the menu 307 -> 325 ms (r761: 295), the Mac mini's `resize.redrawn` 24.5 -> 28.5 (the alpha bounds'
  clip, known since 2026-10-29), lianli's `dev.type` 2.3 -> 4.0 (both bimodal between 2 and 5).
- `idle-windows.gpu_added_kB` reads 3.4 -> 10.1 MiB on the T550 and 16.3 -> 33.7 on the XPS, but that counts the three
  foot windows' own buffers, which zero copy imports (shared): the compositor's private GPU memory grows by 2.3 MiB on
  the T550 against 10.7 for Hyprland 0.57.0, 0.4 against 27 on the XPS.

### Hypoland r871 against r761, Hyprland 0.57.0 against 0.56.2

The two baselines three nights apart, each compositor against itself (Omarchy r7316 then, r7438 now, the same
workloads plus `launch` and `many-windows`):

- Hypoland: `terminal-scroll` T550 11.2 -> 2.9, XPS 24.8 -> 3.1, lianli 13.7 -> 2.4, Mac mini 20.8 -> 3.3, Chromebook
  12.9 -> 5.5; `qt-software-sprites` Mac mini 32.5 -> 3.2 (the regression of the 0.56.2 baseline is gone), Galaxy Book
  25.6 -> 13.9, XPS 26.1 -> 3.4; `gtk3-scroll` Mac mini 28.0 -> 11.0, Chromebook 28.9 -> 14.3; `resize` T550 17.6 ->
  11.0, XPS 33.7 -> 19.9, Mac mini 27.5 -> 12.9; the focus change of `idle-windows` X200 4.7 -> 2.1, Chromebook 6.7 ->
  3.7 (the keymap work of 2026-10-30); Pss at the start 0.4 to 3.8 MiB lower everywhere but the Galaxy Book. Worse: the
  T550's toast 22.3 -> 29.1, the XPS's menu 295 -> 325, and Pss at the end 1.2 to 3.4 MiB higher everywhere but the Mac
  mini (the closed windows of the new workloads, above).
- Hyprland 0.57.0 against 0.56.2: workspace switching costs it half (X200 9.7 -> 3.9, T550 7.0 -> 3.5) because the
  switch shows 20 frames a second under both compositors now (50 to 60 under Omarchy r7316): the environment, not
  Hyprland.
  `gtk3-scroll` on the X200 26.0 -> 46.2 and `qt-software-sprites` on the Mac mini 20.3 -> 38.9, lianli 48.2 -> 62.8 and
  the Chromebook 45.6 -> 61.4 cost it more, the menu closes 10 to 20 ms later on the crocus and r600 machines (above),
  the rest is within a point.

## Caveats

- Blocks that ran short: Hyprland 0.57.0 died five times, killed by a signal without a core dump or a crash report
  (start-hypoland and start-hyprland log `Couldn't waitpid for hyprland: No child processes`, which is how their wait
  loop reports a death by a signal): X200 blocks 1 and 11 at the end of `dev`, XPS 1 and 12 and Chromebook 7 during
  `resize`. Hypoland died the same way once, X200 block 10 at the end of `dev`. The kernel, systemd-oomd and the
  journal say nothing about any of them. Their workloads after that point are `invalid` and left out of the medians
  (the rest of each block counts); X200 Hyprland block 6 lost `resize` and `many-windows` without a restart. A trace of
  the signals sent on the machines runs since the morning of 2026-10-31 to find the sender.
- The deploy check in the first round: Hypoland passed on all eight; Hyprland 0.57.0 on six, the XPS with the GPU client
  at 0 fps in that block (later blocks measured it at 60), the X200's ran after the compositor had died.
- X200, Hyprland 0.57.0: GTK 4 does not start under the GLES 3 override (0.56.2 the same), so its `gtk4-scroll`,
  `gtk4-spinner`, `nautilus` and `nautilus-scroll` rows are 0 and say nothing. The override also changes what the
  clients' Mesa reports. Ghostty and kitty need OpenGL 3.3 and are not on the X200; Ghostty does not start on the
  Chromebook under either.
- The Chromebook's `video` plays at 14 fps under both: the decoder.
- `idle-windows.gpu_added_kB` counts imported buffers: under Hypoland's zero copy those are the clients' own memory (see
  above). `mem.*.gpu_private_kB` is the compositor's own.
- `fps.workspace-switch.screen` is about 20 under both compositors where the 0.56.2 baseline had 50 to 60 under both:
  Omarchy r7438 animates the switch differently from r7316. Compare workspace switching only within this baseline.
- Both compositors read the same Omarchy config, but Hypoland draws some of it differently: windows with an opacity
  of 0.98 or more are opaque (Omarchy's 0.985 active opacity is not blended), the shell's transparent layer areas are
  clipped (`HYPOLAND_ALPHA_BOUNDS`), and transparent huge pages are off for the compositor.
- `startup` is not in it (see Setup); hypoland-7d's fixed `startup.py` (72add42a1) measured it the next morning on the
  Galaxy Book, two fresh sessions each, Hyprland 0.57.0 -> Hypoland: IPC 425 -> 262 ms, first frame 223 -> 197, bar 781
  -> 606, desktop 2541 -> 2366, compositor CPU in the first 20 s 920 -> 350 ms, Pss 151 -> 44.9 MiB.
