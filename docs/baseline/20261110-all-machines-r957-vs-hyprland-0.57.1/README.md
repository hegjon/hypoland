# Hypoland r957 vs Hyprland 0.57.1 on eleven machines, 2026-11-10 to 11

Hypoland master r957 (`29b9f86a9`, after 0.3.0: the measured direct scanout, frame damage merged on every driver, 10-bit
buffers on the plane) against stock Hyprland 0.57.1-2: every workload of `scripts/bench/measure.sh` with the games and
ElectroBench, on every test machine, 8 to 10 fresh sessions of each per machine (macmini-intel 5 to 6, see the caveats),
alternating from 23:09 on 2026-11-10 to 07:30 on 2026-11-11 (macmini-m1 from 23:38). The lab page (`web/lab.html`,
`scripts/web/lab.py`) and the terminals page take their numbers from here. Compare a later build with
`<machine>/hypoland/values.txt` to see whether it got slower, and with `<machine>/hyprland/values.txt` to see where it
stands against Hyprland 0.57.1. It follows `../20261103-all-machines-0.3.0-vs-hyprland-0.57.0/`, made the same way, and
adds macmini-m1 (Apple M1, asahi).

## Setup

- Hypoland: `hypoland 0.3.0.r957.g29b9f86a9-1`, built on the desktop from master `29b9f86a9`; the Galaxy Book and
  macmini-m1 ran their own aarch64 builds of the same commit (`r957.g29b9f86`). The benchmark is `scripts/bench` of that
  commit with ElectroBench's workloads (committed after it as `28c9a4b37`).
- Hyprland: `hyprland 0.57.1-2` and `omarchy-hyprland-titlebars 0.3.0-4` from Omarchy's edge repository, installed from
  each machine's pacman cache for every Hyprland block.
- As in the baselines before: Hyprland runs with `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`,
  Hypoland's default and 0.57.1's), and on the X200 with Omarchy's GLES 3 override (omacom/omarchy#14764, `pr/`).
- Every machine was updated with `omarchy update` and rebooted on 2026-11-10 (x86: `omarchy-dev 4.0.0.r7677`, kernel
  `7.2.15-2-omarchy`; the Galaxy Book Omarchy 4.5.0-3, kernel `7.3.0-46-omarchy`; macmini-m1 Asahi `7.2.11`, Mesa
  `mesa-aurora 26.3.0`). `packages.txt` lists them per machine. Omarchy-dev r7677 exports `HYPRLAND_NO_RT=1`
  (hyprwm/Hyprland#16648), so both compositors ran without realtime scheduling on the x86 machines and the M1; the Galaxy
  Book's stable Omarchy does not set it.
- The runner is `abnight.sh` (`start.sh` starts it; macmini-m1 with `HOSTS=macmini-m1 M1_PKG=...`): a block is one
  compositor installed with `pacman -U`, a fresh SDDM session, the `startup` workload, then `measure.sh --rounds 1` of the
  rest; a round is one block of each, the order alternating per round. In the first round each block also ran the
  deploy check (`<machine>/hypoland-check.txt`, `hyprland-check.txt`). `<machine>/log` is the runner's log.
- `report.sh` fetched the blocks and wrote `<machine>/<compositor>/values.txt` (`<key> <median> <min> <max>` over the
  blocks; with an even count the lower middle value), `raw.txt` (every block's values, `@ <block> <key> <value>`; the
  startup workload's as `@ startup`) and `bench.txt`; `table.py` wrote `table.txt`. The block files are not kept here.

## What it shows

`table.txt` has every workload. Compositor CPU per frame on the screen (where frames are counted, else in percent),
counting only differences whose ranges do not overlap:

| | cheaper | same | dearer | median Hypoland / Hyprland |
|---|---|---|---|---|
| X200 | 23 | 4 | 4 (not comparable, below) | 0.74 |
| T550 | 37 | 3 | 0 | 0.62 |
| XPS | 39 | 1 | 0 | 0.60 |
| lianli | 27 | 6 | 5 | 0.87 |
| Chromebook | 34 | 3 | 0 | 0.73 |
| T460s | 38 | 3 | 0 | 0.66 |
| samsung-i5 | 37 | 1 | 0 | 0.60 |
| T490 | 35 | 6 | 0 | 0.67 |
| Galaxy Book | 15 | 26 | 1 | 0.83 |
| macmini-intel (headless) | 41 | 1 | 0 | 0.48 |
| macmini-m1 | 25 | 9 | 1 | 0.77 |

- Memory: 40 to 49 MiB Pss at the start against 115 to 146, 49 to 63 with 40 windows open against 116 to 156; anonymous
  memory 15 to 23 MiB against 83 to 114; GPU memory lower on every machine that reports it.
- Startup: IPC answers 1.15 to 2.9 times sooner (the X200 0.9 against 2.7 s), the first frame sooner everywhere, the
  compositor's CPU in the first 20 s 47 to 82% of stock's.
- Latency: a focus change, a workspace switch and a resize step are shown 1.3 to 2.7 ms after the key on the iris
  machines, samsung-i5 and macmini-intel against 3.6 to 15 ms; on the X200, the Chromebook, lianli, the Galaxy Book and
  the M1 within about a millisecond of stock (lianli's resize step 1.9 against 1.2 ms, the M1's workspace switch 1.3
  against 0.6). Omarchy's terminal is
  open and drawn 40 to 240 ms sooner, the menu closes in 2.5 to 23 ms against 7 to 39.
- Games: Xonotic shows the same (within 1%) or more frames on the screen under Hypoland everywhere, the X200 at low 52.7 against 24.8 a second on
  the screen, samsung-i5 at ultimate 17.5 against 9.8.
- Behind Hyprland 0.57.1, ranges that do not overlap:
  - macmini-m1 `qt-software-sprites`: 80.3 against 70.2% at 38.9 against 54.6 client fps. asahi pays per texture upload
    call, mostly in the kernel, and Hypoland's second shm texture doubles the calls; one texture there since
    `679f22ba2` (64% at 57 fps, `test-results/m1sprites-20261111/` on the desktop).
  - The Galaxy Book's `menu`: 6.65 against 4.30 ms a frame, as in every baseline.
  - The T490's `velocitty-scroll`: 28.4 against 34.1 frames a second on the screen with the client's CPU the same, only
    there (the T550, XPS, X200 and Chromebook the same or more). Not zero copy; open.
  - lianli's ElectroBench lines, ocean and pool: 0.05 to 0.08 ms a frame more.
  - Not costs: the T550's `many-windows-10` shows 29 against 49 frames at a third of stock's CPU (0.57.1 draws every
    window's commit as a frame of its own); `workspace-switch` 1.3 to 1.7 fewer frames on six machines (the animation
    ends a frame sooner, as in the 0.3.0 baseline); the toast, a few ms later on the T550, T460s, T490 and M1, as in every
    night (overlapping); `launch.closed`, foot's contents fading out, which stock drops at once.
- The deploy check in the first round: Hypoland passed every check on ten machines (66 to 98); stock failed 1 to 7 (the
  Galaxy Book 52, the M1 39). macmini-m1 failed 31 render steps under Hypoland and more under stock: the software cursor moved into the picture by Omarchy's
  `warp_on_change_workspace`, not a damage bug (the render checks hold the warp since `c8c87f613`).

## Caveats

- macmini-intel had no monitor that night (its HDMI went to a KVM): its blocks until 01:17 ran without any output and are
  left out (`macmini-intel.skip`); later sessions got a 1920x1080 headless output from a helper script. Its numbers are
  headless: no page flips, so no frames on the screen and no ms per frame. The lab page leaves it out of this night.
- macmini-m1 counts no page flips (apple-drm has no `drm_vblank_event_delivered`): its frames on the screen read 0.0
  under both.
- No Hypoland compositor dumped core. Stock Hyprland aborted twice on the X200 (an assert in `CHyprOpenGLImpl::begin`
  after GPU hangs, 03:20 and 04:19): those blocks are left out (`x200.skip`). All five GPU hangs of the X200 were in stock
  blocks. Other cores: GravityMark's OpenGL renderer (T550, XPS, Galaxy Book, under both), Nautilus and python3 (GTK 4)
  in every stock block on the X200 (the GLES 3 override), Nautilus in every block on the M1, Xwayland at session teardown
  (X200 and samsung-i5 under Hypoland, the Chromebook under stock).
- The X200's GTK 4 and Nautilus rows are about 0 under stock: those clients crash under the GLES 3 override.
- Ghostty and kitty need OpenGL 3.3: not on the X200; Ghostty measures 0 on the Chromebook and samsung-i5 under both.
  macmini-m1 has neither Xonotic nor GravityMark.
