# Hypoland vs stock Hyprland 0.56.2 with omacom/omarchy#14764 on the X200

Measured on 2026-10-22. Stock Hyprland does not start on the GM45 (`stock-hyprland-0.56.2-crash.txt`). Omarchy's
[PR #14764](https://github.com/omacom/omarchy/pull/14764) (head `dd687aab`) makes it start: on Intel Gen4/Gen5
GPUs it sets `MESA_GLES_VERSION_OVERRIDE=3.0` and `MESA_GLSL_VERSION_OVERRIDE=300` through `hl.env` in
`default/hypr/intel-gles2.lua`. With the PR the desktop rendered correctly; this was checked in the buffer that is
scanned out (`hypoland-kmsgrab`), not only in a `grim` screenshot. The results were posted on the PR:
https://github.com/omacom/omarchy/pull/14764#issuecomment-6346779464

## Setup

- ThinkPad X200: Core 2 Duo P8400, GM45 / GMA 4500MHD, Mesa 26.2.5 `crocus`, 1280x800, HPET clocksource,
  kernel 7.2.8-10-omarchy, Omarchy on the `omarchy-dev` channel.
- Hypoland: the Arch package built from master `ab7d84a4c` (`hypoland 0.2.0.r709.gab7d84a4c-1`).
- Hyprland: the Arch packages `hyprland 0.56.2-4` and `omarchy-hyprland-titlebars`, plus the PR's
  `intel-gles2.lua` and `bin/omarchy-hw-intel-gles2` copied into `/usr/share/omarchy` and required from
  `default/hypr/envs.lua` (`use.sh pr`). `use.sh hypoland` removes them again.
- Both run Omarchy's own config through SDDM and uwsm.
- `abpr.sh` alternates the two for 3 rounds. Each workload runs `measure.sh --mode bench --seconds 20 --settle 60`
  with the `performance` governor, and `perf stat -a -e drm:drm_vblank_event_delivered` counts the page flips.
  `measure.sh` is `scripts/bench/measure.sh` with one added line: clients get `CLIENT_ENV`, which `abpr.sh` sets
  to the two Mesa overrides for the PR variant, as the session gives them to clients started from it.
- The raw output is in `raw.txt`, the PR variant is labelled `pr`. The figures below are medians over the
  3 rounds.

## Compositor CPU (one core = 100%)

| Workload | Hypoland | Hyprland + PR | Hypoland vs Hyprland |
|---|---|---|---|
| idle | 0.02% | 0.02% | |
| `weston-simple-egl` at 60 fps | 2.69% | 3.83% | -30% |
| foot scrolling fast | 10.15% | 15.09% | -33% |
| Chromium, full window (software rendered, shm) | 9.85% | 26.64% | -63% |
| workspace switching with animations | 3.72% | 10.28% | -64% |

The GPU client ran at 60.3 fps under both. Page flips per 20 s workload:

| Workload | Hypoland | Hyprland + PR |
|---|---|---|
| idle | 2 | 1 |
| GPU client | 1469 | 1469 |
| terminal scrolling | 821 | 750 |
| Chromium | 2542 | 2538 |
| workspace switching | 1463 | 1427 |

## Compositor memory

| | Hypoland | Hyprland + PR |
|---|---|---|
| Pss, 60 s after the start | 46.0 MiB | 114.0 MiB |
| Rss | 77.5 MiB | 150.9 MiB |
| anonymous | 17.0 MiB | 82.7 MiB (70 MiB of it transparent huge pages) |
| heap | 9.0 MiB | 66.2 MiB |
| GPU buffers (`drm-total-system0`), 60 s after the start | 58.0 MiB | 79.8 MiB |
| GPU buffers after the workloads | 53.9 MiB | 89.7 MiB |
| threads | 10 | 12 |

## Caveats

- The override makes Mesa report GLES 3.0 / GLSL ES 3.00 on hardware that does not fully implement it. The default
  Omarchy desktop rendered correctly; nothing beyond that was checked for rendering errors.
- Both compositors read the same Omarchy config, but Hypoland draws some of it differently. Windows with an
  opacity of 0.98 or more are drawn opaque, so Omarchy's 0.985 active opacity is not blended under Hypoland.
- Hypoland disables transparent huge pages for the compositor process. Most of Hyprland's extra anonymous
  memory comes from them.
- The same comparison without the override on a GPU with GLES 3 is in `../t550-vs-stock-hyprland-0.56.2/`.
