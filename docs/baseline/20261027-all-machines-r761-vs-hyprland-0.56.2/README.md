# Hypoland vs Hyprland 0.56.2 on all eight machines, overnight 2026-10-27 to 28

The regression baseline: every workload of `scripts/bench/measure.sh` on every test machine, Hypoland against
Hyprland 0.56.2, 37 to 41 fresh sessions of each per machine, alternating through the night. Compare a later build
with `<machine>/hypoland/values.txt` to see whether it got slower, and with `<machine>/hyprland/values.txt` to see
where it stands against Hyprland 0.56.2.

## Setup

- Hypoland: `hypoland 0.2.0.r761.gcef04782e-1`, the Arch package built from the branch `bench-package` at
  `cef04782e`. Its compositor is the code of master `233be977b`: the branch adds only the `hypoland-bench` package,
  and master's commits after that base at the time (`5c4a2f007`, `999785e13`) change hyprtester only. The Galaxy
  Book built its own package on the machine from the branch's next commit, `r762.g7acef3d`, the same code.
  `hypoland-bench` of the same version was installed alongside; the run itself used a copy of `scripts/bench`.
- Hyprland: the Arch packages `hyprland 0.56.2-4` and `omarchy-hyprland-titlebars 0.2.2-2` (the aarch64 ones on
  the Galaxy Book). On the X200 Hyprland 0.56.2 does not start on its own (GM45 has GLES 2 only), so it runs with
  Omarchy's GLES 3 override (omacom/omarchy#14764, the files in `/root/ab/pr` there) and its clients get the
  override's Mesa variables (`MESA_GLES_VERSION_OVERRIDE=3.0`, `MESA_GLSL_VERSION_OVERRIDE=300`).
- Both run Omarchy's own config through SDDM and uwsm, as an Omarchy user gets them, Omarchy on the `omarchy-dev`
  channel. `packages.txt` lists the packages the clients come from on every machine (Mesa 26.2.5, GTK 3.24.52,
  GTK 4.24.1, Qt 6.12.0, foot 1.28.0, Alacritty 0.17.0, Quickshell 0.3.2, Xwayland 24.1.14; kernel 7.2.8-10-omarchy,
  the Galaxy Book 7.3.0-3-omarchy).
- The runner is `abnight.sh`, run as root on each machine, detached (`start.sh` copies it, `scripts/bench` and the
  packages to `/root/abnight` and starts it). A block is one compositor: its package installed with `pacman -U`,
  SDDM restarted for a fresh session (the Quickshell logs in `/run/user` removed first), 60 s after the shell is up
  `measure.sh --rounds 1`: every workload, 12 s each, the `performance` governor, memory 60 s after the compositor's
  start and 10 s after the last workload. A round is one block of each, the order alternating per round, and a
  round starts only while one more fits before the end. The system timers and Omarchy's update checks are stopped
  for the run.
- Started 16:44 on 2026-10-27 (the Galaxy Book 16:45, the Mac mini 16:47), the last block ended between 07:15 and
  07:28 on 2026-10-28 (the end was set to 07:30). Blocks per compositor: X200 37, T550 40, XPS 39, lianli 40,
  Chromebook 37, T460s 40, Galaxy Book 41, Mac mini 41. Every block is complete, no value is invalid and none was
  left out. The machines were back on Hypoland at the end.

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
`~/Work/machines/MACHINES.md` on the desktop.

## Files

- `table.txt`: compositor CPU, session CPU, frames on the screen and latency medians per workload and machine,
  Hyprland 0.56.2 -> Hypoland (`python3 table.py <run>`).
- `compare.txt`: `bench.sh --compare` per machine, every key, with its `better` / `WORSE` flags
  (`report.sh`'s output).
- `<machine>/hypoland/values.txt` and `<machine>/hyprland/values.txt`: `<key> <median> <min> <max>` over the
  blocks, the format `bench.sh --compare` reads; `bench.txt` next to it is the machine line. `raw.txt` has every
  value of every block (`@ <block> <key> <value>`), for the spread behind a median.
- `<machine>/log`: the runner's log with the time of every block.
- `packages.txt`: `pacman -Q` of the packages the clients come from, on every machine, after the run.
- `abnight.sh`, `start.sh`, `report.sh`, `table.py`: the runner, the script that started it on the machines, the
  fetch and compare, and the table.

## Checking a build against this baseline

- One machine: `./bench.sh --host <machine> --seconds 12 <label>` on a session that was restarted for it, then
  `./bench.sh --compare docs/baseline/20261027-all-machines-r761-vs-hyprland-0.56.2/<machine>/hypoland
  test-results/bench-<time>-<label>`. The blocks here were each a fresh session measured 60 s after login; a session
  that ran a deploy check or other workloads before shows the clients a few points higher (seen on the T550 on
  2026-10-27). One round moves within the min and max in `values.txt`, and the whole spread of a row is in
  `raw.txt`: the Galaxy Book's `gpu-client` varies by 1.5 points between rounds, `gtk3-x11-scroll` there by 30.
- All machines, against Hyprland 0.56.2 as well: `start.sh <run> <until> <package>` with `HOSTS`, `BENCH_PKG`, `GALAXY_PKG`
  and `GALAXY_BENCH_PKG` set (see the script), then `report.sh <run> <machines>` and `table.py <run>` from the
  directory it fetched into.

## What it shows

Medians over the blocks, Hyprland 0.56.2 -> Hypoland; the whole table is `table.txt`.

### Memory

Pss of the compositor (MiB) 60 s after the start and 10 s after the last workload, and its GPU buffers
(`drm-total-system0`; radeon reports none):

| machine | Pss at the start | Pss at the end | GPU buffers at the start | at the end |
|---|---|---|---|---|
| X200 | 112.2 -> 45.1 | 113.2 -> 44.9 | 86.2 -> 64.5 | 91.6 -> 81.5 |
| T550 | 114.0 -> 43.8 | 114.7 -> 46.4 | 171.0 -> 104.6 | 181.9 -> 105.3 |
| XPS | 112.8 -> 43.0 | 114.0 -> 45.8 | 500.4 -> 291.8 | 533.4 -> 334.7 |
| lianli | 113.1 -> 43.2 | 113.9 -> 45.9 | | |
| Chromebook | 113.1 -> 43.4 | 113.9 -> 46.2 | 106.1 -> 82.5 | 112.5 -> 106.0 |
| T460s | 114.5 -> 44.0 | 115.0 -> 46.5 | 182.0 -> 111.7 | 197.0 -> 120.4 |
| Galaxy Book | 144.6 -> 44.2 | 145.4 -> 50.7 | 383.4 -> 276.2 | 452.3 -> 351.9 |
| Mac mini | 113.3 -> 44.1 | 114.5 -> 46.5 | 210.1 -> 128.6 | 222.7 -> 133.3 |

Anonymous memory is 83 MiB (113 on the Galaxy Book) against 17 to 19 MiB: most of Hyprland 0.56.2's is transparent huge
pages, which Hypoland turns off for the compositor. Hypoland runs two threads fewer (one on r600).

### Compositor CPU

- Workspace switching with animations costs about half: X200 9.7 -> 3.8%, T550 7.0 -> 3.5, XPS 9.1 -> 4.4,
  lianli 10.0 -> 3.4, Chromebook 12.8 -> 6.5, T460s 6.5 -> 3.8, Mac mini 7.8 -> 3.3. The Galaxy Book is the
  exception, 3.4 -> 4.5.
- Windows drawn into shm buffers cost a half to a third where the uploads were the limit: `qt-software-scroll`
  X200 26.4 -> 9.3, T550 19.7 -> 13.9, XPS 33.1 -> 12.4, Chromebook 18.2 -> 15.5, T460s 15.6 -> 12.2;
  `qt-software-sprites` X200 53.7 -> 19.9 (at 26 -> 60 fps), XPS 42.8 -> 26.1, lianli 48.2 -> 25.9, Chromebook
  45.6 -> 26.2 (36 -> 51 fps); Chromium full window (`shm-fullwindow`) X200 27.6 -> 10.6, one to two points lower
  elsewhere; `gtk3-scroll` X200 26.0 -> 18.3 (30 -> 56 fps), Chromebook 41.3 -> 28.9; `terminal-scroll` X200
  16.5 -> 10.1.
- The developer's screen (`dev`) is one to three points lower everywhere (XPS 8.0 -> 4.9, Chromebook 11.9 -> 8.8,
  Mac mini 5.8 -> 3.8), the GPU client on the X200 4.0 -> 2.9 and the XPS 6.5 -> 4.0, `resize` on the T550
  20.8 -> 17.6, the T460s 19.0 -> 16.3 and the Mac mini 32.1 -> 27.5, the menu, the notifications, Nautilus and the
  video one to two points lower on most machines.

### Frames on the screen

On the X200 Hyprland 0.56.2 shows 30 frames a second where Hypoland shows 42 to 60: Alacritty 30 -> 42.5, `gtk3-scroll`
30 -> 56, `gtk3-x11-scroll` 21 -> 28, `qt-quick-scroll` 30 -> 40, `qt-software-sprites` 26 -> 60, `resize` 30 -> 60,
`tk-canvas` 29 -> 43, `dev` 34 -> 47. The Chromebook shows the GPU client at 60 instead of 30, the sprites at 51
instead of 36 and the terminal at 28 instead of 22; the XPS Alacritty at 57 instead of 48, `resize` at 59 instead
of 50 and the terminal at 42 instead of 36; lianli `qt-software-scroll` at 60 instead of 43; the Galaxy Book
`gtk3-x11-scroll` at 44 instead of 31. Everything else shows the same frames under both.

### Latency

On the iris machines and the Galaxy Book Hypoland shows a focus change, a resize step, the menu closing and a menu
selection one to two frames earlier (ms): focus T550 7.0 -> 2.5, XPS 17.0 -> 3.5, T460s 9.2 -> 2.4, Galaxy Book
4.3 -> 1.7; resize T550 8.9 -> 1.1, XPS 20.1 -> 1.4, T460s 9.6 -> 1.2, Galaxy Book 4.3 -> 1.0; menu close T550
10.4 -> 2.8, XPS 13.0 -> 3.3, T460s 10.2 -> 3.0; menu select T550 18.2 -> 5.6, XPS 31.6 -> 8.1, T460s 12.8 -> 4.2,
Galaxy Book 10.9 -> 5.2. The menu opens 20 to 45 ms earlier on the T550, the T460s and the Mac mini, its search
answers 30 to 50 ms earlier on the iris machines, the editor's jump (`dev.jump`) shows 10 to 30 ms earlier on every
x86 machine. On the crocus and r600 machines the two are within a frame of each other.

### Where Hypoland is behind Hyprland 0.56.2

The rows to watch; all of them are medians of 37 to 41 blocks, so the differences are real, not spread:

- `qt-software-sprites` on the Mac mini: 20.3 -> 32.5% compositor CPU at the same 60 fps, every block within half
  a point of its median. The first result of that machine, and the largest regression. Haswell's `crocus` uploads
  through Mesa's tiled-memcpy temporary like Broadwell's `iris`, and Hypoland merges the sprites' damage into strips
  on every `crocus` (`CHyprOpenGLImpl::coalesceDamage()`, decided on the X200, whose Gen 4 maps the texture
  directly, and measured as a gain on the Chromebook before the malloc trim fix of 2026-10-27); whether that is the
  cause is not verified. `qt-software-scroll` (9.4 -> 10.5) and `terminal-scroll` (19.7 -> 20.8) are a point
  higher there as well.
- The Galaxy Book: `qt-software-sprites` 21.5 -> 25.6 (blocks 17 to 24 against 22 to 31), `workspace-switch`
  3.4 -> 4.5, `menu` 1.6 -> 2.3, `gtk3-x11-scroll` 29 -> 34 at 31 -> 44 fps. Its GTK 4 client (Vulkan through
  `turnip`, the same renderer under both) costs 3.5% in every Hyprland 0.56.2 block but 3.5 to 20% under Hypoland, bimodal,
  median 9.4, with the compositor and the frames the same (`cpu.gtk4-scroll.clients_percent`, `gtk4-spinner` the
  same way). Not understood.
- The X200's `resize`: 13.9 -> 20.9% at twice the frames (30 -> 60 fps), cheaper per frame (known since
  2026-10-26). Where Hypoland shows more frames the compositor costs a little more the same way: X200
  `alacritty-scroll`, `gtk3-x11-scroll`, `qt-quick-scroll` and `tk-canvas` 0.3 to 1 point, XPS `gtk3-scroll` +1.6
  and `terminal-scroll` +2.4, lianli `qt-software-scroll` +1.6, the Chromebook's GPU client 4.5 -> 6.6 at 60
  instead of 30 fps.
- Latency: on the three crocus machines a focus change is 0.3 to 1 ms slower (X200 3.6 -> 4.5, Chromebook
  5.8 -> 6.5, Mac mini 2.1 -> 2.4) and the Chromebook's `dev.focus` 7.4 -> 12.8; Omarchy's bar shows a workspace
  change 3 ms later on the T550 (14.0 -> 17.2) and the Galaxy Book (7.1 -> 9.8), 6 and 4 ms earlier on the XPS and
  the T460s; a notification's toast 4 ms later on the X200 (45 -> 49) and the T460s (19 -> 23), 7 ms earlier on the
  XPS.

## Caveats

- X200, Hyprland 0.56.2: GTK 4 did not start under the GLES 3 override (`clients:` empty in every Hyprland 0.56.2 block), so its
  `gtk4-scroll`, `gtk4-spinner` and `nautilus` rows are 0 and say nothing. The override also changes what the
  clients' Mesa reports, so the X200's client figures are not the same client under both.
- The Chromebook's `video` plays at 13.6 fps under both: the decoder, not the compositor.
- `flea` is not installed on the Galaxy Book and the Mac mini, `nautilus` not on the Mac mini, `tk` only on the X200
  and the Galaxy Book; those rows are missing there.
- Both compositors read the same Omarchy config, but Hypoland draws some of it differently: windows with an opacity
  of 0.98 or more are opaque (Omarchy's 0.985 active opacity is not blended), and it turns transparent huge pages off
  for the compositor.
- The earlier, smaller comparisons (2026-10-22, three rounds, five workloads) are
  `../x200-vs-stock-hyprland-0.56.2-pr14764/` and `../t550-vs-stock-hyprland-0.56.2/`.
