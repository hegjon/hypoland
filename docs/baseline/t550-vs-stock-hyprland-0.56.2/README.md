# Hypoland vs stock Hyprland 0.56.2 on a ThinkPad T550

Measured on 2026-10-22. The T550 has GLES 3, so stock Hyprland runs on it without any override. This shows what
Hypoland's changes cost or save on hardware both compositors support.

## Setup

- ThinkPad T550: Core i5-5300U (2 cores / 4 threads), Intel HD Graphics 5500, Mesa 26.2.5 `iris`, 1920x1080,
  16 GB, kernel 7.2.8-10-omarchy, Omarchy on the `omarchy-dev` channel.
- Hypoland: the Arch package built from master `ab7d84a4c` (`hypoland 0.2.0.r709.gab7d84a4c-1`).
- Hyprland: the Arch packages `hyprland 0.56.2-4` and `omarchy-hyprland-titlebars 0.2.2-2`.
- Both run Omarchy's own config through SDDM and uwsm, as an Omarchy user gets them.
- `abpr.sh` alternates the two packages for 3 rounds. `use.sh` installs one and restarts the SDDM session.
  Each workload runs `scripts/bench/measure.sh --mode bench --seconds 20 --settle 60` with the `performance`
  governor, and `perf stat -a -e drm:drm_vblank_event_delivered` counts the page flips.
- The raw output is in `raw.txt`. The figures below are medians over the 3 rounds.

## Compositor CPU (one core = 100%)

| Workload | Hypoland | Hyprland | Hypoland vs Hyprland |
|---|---|---|---|
| idle | 0.02% | 0.01% | |
| `weston-simple-egl` at 60 fps | 3.22% | 4.27% | -25% |
| foot scrolling fast | 12.05% | 13.37% | -10% |
| Chromium, full window (GPU rendered on this machine) | 3.68% | 4.62% | -20% |
| workspace switching with animations | 3.04% | 6.80% | -55% |

Frames are the same: the GPU client ran at 60.3 fps under both. Page flips per 20 s workload were:

| Workload | Hypoland | Hyprland |
|---|---|---|
| idle | 13 | 13 |
| GPU client | 1478 | 1478 |
| terminal scrolling | 1287 | 1303 |
| Chromium | 2630 | 2629 |
| workspace switching | 1436 | 1436 |

## Compositor memory

| | Hypoland | Hyprland |
|---|---|---|
| Pss, 60 s after the start | 43.6 MiB | 114.7 MiB |
| Rss | 76.2 MiB | 150.2 MiB |
| anonymous | 17.3 MiB | 83.3 MiB (70 MiB of it transparent huge pages) |
| heap | 9.4 MiB | 65.8 MiB |
| GPU buffers (`drm-total-system0`), 60 s after the start | 96.5 MiB | 170.7 MiB |
| GPU buffers after the workloads | 129.5 MiB | 189.2 MiB |
| threads | 10 | 12 |

## Caveats

- Both compositors read the same Omarchy config, but Hypoland draws some of it differently. Windows with an
  opacity of 0.98 or more are drawn opaque, so Omarchy's 0.985 active opacity is not blended under Hypoland.
- Hypoland disables transparent huge pages for the compositor process. Most of Hyprland's extra anonymous
  memory comes from them.
- The X200 comparison against stock Hyprland with omacom/omarchy#14764 (the GLES 3 override for GM45) was
  posted on that PR: https://github.com/omacom/omarchy/pull/14764#issuecomment-6346779464
