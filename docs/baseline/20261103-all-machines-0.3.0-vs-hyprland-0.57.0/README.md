# Hypoland 0.3.0 vs Hyprland 0.57.0 on ten machines, 2026-11-03 to 04

The released Hypoland 0.3.0 against stock Hyprland 0.57.0-4: every workload of `scripts/bench/measure.sh` on every
test machine, 31 to 37 fresh sessions of each per machine (the Galaxy Book 2, see the caveats), alternating from
12:46 on 2026-11-03 to 07:30 on 2026-11-04. The lab page (`web/lab.html`, `scripts/web/lab.py`) takes its numbers from
here. Compare a later build with `<machine>/hypoland/values.txt` to see whether it got slower, and with
`<machine>/hyprland/values.txt` to see where it stands against Hyprland 0.57.0. It follows
`../20261030-all-machines-r871-vs-hyprland-0.57.0/`, made the same way, and adds samsung-i5 and the T490.

## Setup

- Hypoland: `hypoland 0.3.0-1`, the release's Arch package (tag `v0.3.0`, `a36c8cd9a`, built against hyprgraphics 0.6.0,
  hyprutils 0.14.3 and hyprland-protocols 0.8.0); the Galaxy Book ran the release's aarch64 package built on the machine.
  The benchmark is `scripts/bench` of the same commit.
- Hyprland: `hyprland 0.57.0-4` and `omarchy-hyprland-titlebars 0.3.0-3` from Omarchy's repository (built for
  hyprgraphics 0.6.0; the 0.57.0-2 of the r871 baseline no longer starts with it), installed from each machine's pacman
  cache for every Hyprland block.
- As in the r871 baseline: Hyprland runs with `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`,
  Hypoland's default), and on the X200 with Omarchy's GLES 3 override (omacom/omarchy#14764, `pr/`), since it does not
  start there otherwise.
- Every machine updated to the desktop's package versions and rebooted at 12:38 that day: kernel `7.2.15-2-omarchy`
  (the Galaxy Book `7.3.0-12-omarchy`), Omarchy `omarchy-dev 4.0.0.r7569`. `packages.txt` lists them per machine.
- The runner is `abnight.sh` (`start.sh` starts it, `ABNIGHT_NO_STARTUP=1`: the `startup` workload left out as before):
  a block is one compositor installed with `pacman -U`, a fresh SDDM session and `measure.sh --rounds 1`; a round is
  one block of each, the order alternating per round. In the first round each block also ran the deploy check
  (`<machine>/hypoland-check.txt`, `hyprland-check.txt`). `<machine>/log` is the runner's log.
- `report.sh` fetched the blocks and wrote `<machine>/<compositor>/values.txt` (`<key> <median> <min> <max>` over the
  blocks; with an even count the lower middle value), `raw.txt` (every block's values, `@ <block> <key> <value>`) and
  `bench.txt`; `table.py .` wrote `table.txt`. The block files themselves are not kept here.
- macmini-m1 (Apple Silicon, joined the lab that morning) is not in it.

## What it shows

`table.txt` has every workload. Compositor CPU per machine, Hyprland 0.57.0 -> Hypoland, a few rows:

| | X200 | T550 | XPS | lianli | Chromebook | T460s | samsung-i5 | T490 | Mac mini |
|---|---|---|---|---|---|---|---|---|---|
| terminal-scroll | 14.4 -> 9.2 | 13.0 -> 3.5 | 22.6 -> 3.7 | 13.8 -> 2.5 | 14.2 -> 5.4 | 9.5 -> 3.1 | 15.9 -> 4.1 | 15.2 -> 4.0 | 19.8 -> 3.6 |
| gtk3-scroll | 26.0 -> 16.8 | 20.9 -> 12.9 | 24.0 -> 16.0 | 28.8 -> 23.0 | 28.9 -> 14.7 | 14.5 -> 13.5 | 29.3 -> 16.7 | 16.2 -> 14.7 | 29.1 -> 11.2 |
| qt-software-sprites | 54.4 -> 9.6 | 14.2 -> 3.7 | 25.6 -> 17.5 | 64.1 -> 5.5 | 61.0 -> 13.0 | 13.2 -> 3.9 | 34.9 -> 5.6 | 14.3 -> 3.3 | 39.0 -> 6.0 |
| dev | 7.4 -> 4.7 | 5.7 -> 3.8 | 6.8 -> 4.4 | 5.6 -> 3.8 | 12.0 -> 7.9 | 5.3 -> 3.6 | 8.7 -> 5.2 | 4.7 -> 3.3 | 5.9 -> 3.5 |
| many-windows-40 | 19.4 -> 16.2 | 19.1 -> 11.5 | 22.5 -> 13.5 | 14.5 -> 13.3 | 33.6 -> 31.0 | 15.2 -> 10.3 | 26.6 -> 17.9 | 13.1 -> 8.7 | 17.2 -> 13.0 |

- Memory: 40 to 43 MiB Pss at the start against 113 to 116 (148 on the Galaxy Book), 46 to 53 at the end against 114
  to 149; anonymous memory 16 to 18 MiB against 83 to 116.
- Latency: the focus change, the workspace switch and a resize step are shown 0.7 to 2.5 ms after the key everywhere
  except the crocus machines (X200 3.4, Chromebook 5.6), where stock is the same or a little slower; on iris stock takes
  8 to 17 ms, on samsung-i5 19. Omarchy's terminal is open and drawn 45 to 190 ms sooner, the menu closes in 2.5 to 9 ms
  against 6 to 38.
- The X200 shows 60 frames a second in GTK 3 scrolling against stock's 30, samsung-i5 47 against 36, the XPS 47
  against 42.
- Behind Hyprland 0.57.0:
  - The toast (`notifications.toast`), as in every night since r761: T550 28.8 against 20.5 ms, T490 28.1 / 20.3,
    samsung-i5 35.7 / 29.5, T460s 22.5 / 19.4, the Galaxy Book 15.7 / 8.5 (see AGENTS.md, open).
  - `launch.closed` (85 to 141 ms against 4 to 25) is foot's contents fading out since 0.3.0, which stock drops at once:
    not comparable.
  - The X200's `resize` (22.0 against 14.2%) shows 60 frames a second against 40, the cost per frame is lower.
  - The X200's GTK 4 rows are 0 under stock: GTK 4 does not start under the GLES 3 override.
  - The Galaxy Book's workspace switch (4.5 against 3.7%, the same in the r871 baseline: cache warmth, see AGENTS.md),
    its `menu` CPU (2.4 / 1.6) and its Chromium window (3.3 / 2.9, a workload that swings from 2.5 to 15% between
    sessions there), from two sessions each.
- The deploy check in the first round: Hypoland passed every check on all ten (98 of 98, or 69 of 69 at scale 1.5
  and where kmsgrab cannot read the screen); Hyprland 0.57.0 failed 2 to 4 on six machines and 31 to 56 on the T550,
  the XPS, the T490 and the Galaxy Book, the render checks' stale pixels that 0.3.0 fixed (CHANGELOG).

## Caveats

- The Galaxy Book's GPU hung at 13:58:57, two seconds after a Chromium start in its third Hypoland block (the kernel
  `msm` GMU hang, the third there after 2026-10-28 and 11-02): the compositor stayed in D state, no session started
  again until the power cycle on 2026-11-04. That block is left out (`galaxybook.skip`), so it has 2 blocks of each.
- No compositor died in any block. Xwayland aborted (SIGABRT) at about the same rate under both on the crocus machines
  (X200 21 Hypoland / 24 Hyprland, Mac mini 19 / 25, samsung-i5 8 / 12, Chromebook 6 / 5), the XPS once under
  Hypoland; on the X200 three Xwayland GPU hangs under Hyprland and one of Omarchy's shell under Hypoland (block 27,
  02:51, Mesa aborted in the shell's swap after the GPU reset; the compositor carried on, the shell restarted).
  The X200's GTK 4 clients (nautilus, python3) dumped core 68 / 69 times under the GLES 3 override.
- Ghostty and kitty need OpenGL 3.3: not on the X200; Ghostty measures 0 on the Chromebook and samsung-i5 under both.
