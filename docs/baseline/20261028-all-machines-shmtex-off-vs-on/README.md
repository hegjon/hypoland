# HYPOLAND_SHM_TEXTURE off vs on on all eight machines, overnight 2026-10-28 to 29

The night that decided the shm texture path: every workload of `scripts/bench/measure.sh` on every test machine with
the switch off (Mesa's tiled textures, the default until then) against on (`HYPOLAND_SHM_TEXTURE=linear`: a linear
GBM buffer as the texture's storage, the damaged rows copied by the compositor), 30 to 33 fresh sessions of each per
machine, alternating through the night. It showed the gains on every machine and two costs, which the version merged
the next morning removes (dumb buffers of the compositor's own device instead of a GBM device, no sync calls around the
copy: master 44331bd5c, measured in AGENTS.md under Tools). The data here is the GBM version's, not what master ships.

## Setup

- The package `hypoland 0.2.0.r781.gabc3769a2-1` (branch `wip/shm-rowcopy` at `abc3769a2`: master `71c84ac4e`, the
  GBM-backed textures of `344631755`, plus the row copy) with `hypoland-bench` of the same version; the Galaxy Book
  built its own `r781.gabc3769-1` on the machine. Both variants are the same package: `off` has no variable in
  `~a/.config/uwsm/env`, `on` has `export HYPOLAND_SHM_TEXTURE=linear` there, verified in the compositor's environment
  at the start of every block.
- Omarchy's own config through SDDM and uwsm, the `omarchy-dev` channel; `packages.txt` lists the clients' packages
  (collected the morning after, with the merged build installed by then; the clients' packages did not change: Mesa
  26.2.5, GTK 3.24.52, GTK 4.24.1, Qt 6.12.0, foot 1.28.0, Alacritty 0.17.0, Quickshell 0.3.2; kernel 7.2.8-10-omarchy,
  the Galaxy Book 7.3.0-3-omarchy).
- The runner is `abnight.sh` (`start.sh` copies it, `scripts/bench` and the package to `/root/abnight` and starts it
  detached as root): a block writes the env file for its variant, restarts SDDM for a fresh session, waits 60 s after
  the shell is up and runs `measure.sh --rounds 1`, every workload 12 s, the `performance` governor, memory 60 s after
  the compositor's start and 10 s after the last workload. A round is one block of each variant, the order alternating
  per round. In the first round each variant also ran the deploy check (`ABNIGHT_CHECK=1`). The env file is restored at
  the end. System timers and Omarchy's update checks were stopped for the run.
- Started 19:28 on 2026-10-28 (the XPS 19:34), the end set to 07:30 on 2026-10-29; the last blocks ended 07:08 to
  07:28. Blocks per variant: X200 30, T550 32, XPS 31, lianli 31, Chromebook 30, T460s 31, Mac mini 33. The Galaxy
  Book has 6 off and 5 on blocks: at 21:05, in an off block, its GPU's management unit stopped answering and the
  kernel's hang recovery never completed, so the compositor stayed stuck in the driver until a power cycle the next
  morning (not a Hypoland matter; the blocks before it are complete). On the X200 the first on block had an i915 GPU
  hang in Xwayland's context at 19:47 (the chip reset, Xwayland died, the compositor went on) that left the rest of
  that block without frames: `x200/left-out.txt` names it, it is not in the medians or the raw values, and the 29 on
  blocks after it ran clean. The checks of the first round passed everywhere except that X200 on block.

## Machines

| alias | machine | GPU, Mesa driver | screen | CPUs, RAM |
|---|---|---|---|---|
| `x200` | ThinkPad X200 | GMA 4500MHD (GM45, Gen 4.5), `crocus`, GLES 2 only | 1280x800 | 2, 6 GB |
| `t550` | ThinkPad T550 (host name `aa`) | HD Graphics 5500 (Broadwell), `iris` | 1920x1080 | 4, 16 GB |
| `xps` | Dell XPS 13 9343 | HD Graphics 5500 (Broadwell), `iris` | 3200x1800 at scale 2 | 4, 8 GB |
| `lianli` | desktop, AMD A8-6600K | Radeon HD 8570D, `r600` | 1920x1200 | 4, 8 GB |
| `chromebook` | Dell Chromebook 11 3120, Celeron N2840 | Bay Trail, `crocus`, GLES 3.0 | 1366x768 | 2, 4 GB |
| `t460s` | ThinkPad T460s, Core i7-6600U | HD Graphics 520 (Skylake), `iris` | 1920x1080 at scale 1.5 | 4, 20 GB |
| `galaxybook` | Samsung Galaxy Book4 Edge, Snapdragon X Elite, aarch64 | Adreno X1-85, `freedreno` | 2880x1800 at scale 2, 120 Hz | 12, 16 GB |
| `macmini-intel` | Apple Mac mini Late 2014, Core i5-4260U | HD Graphics 5000 (Haswell GT3), `crocus` | 1920x1200 | 4, 4 GB |

## Files

- `table.txt`: compositor CPU, session CPU, frames on the screen, memory and latency medians per workload and machine,
  off -> on (`python3 table.py <run>`).
- `compare.txt`: `bench.sh --compare` per machine, every key, with its `better` / `WORSE` flags (`report.sh`'s output).
- `<machine>/off/values.txt` and `<machine>/on/values.txt`: `<key> <median> <min> <max>` over the blocks, the format
  `bench.sh --compare` reads; `bench.txt` next to it is the machine line; `raw.txt` has every value of every block
  (`@ <block> <key> <value>`).
- `<machine>/log`: the runner's log with the time of every block; `left-out.txt` where a block is excluded.
- `packages.txt`, `abnight.sh`, `start.sh`, `report.sh`, `table.py`.

## What it shows

- Every shm workload costs the compositor less with the switch on, on every machine: `gtk3-scroll` T550 19.8 -> 13.1%,
  XPS 21.8 -> 14.2, Chromebook 29.0 -> 15.6, Mac mini 28.3 -> 14.3, lianli 27.4 -> 23.2, X200 18.8 -> 17.6;
  `terminal-scroll` T550 11.2 -> 8.0, XPS 24.6 -> 15.7, Chromebook 12.9 -> 7.2, Mac mini 20.4 -> 10.8, lianli 13.7 ->
  11.8; `qt-software-sprites` Mac mini 32.5 -> 7.0, lianli 25.8 -> 7.0, Chromebook 26.1 -> 14.8 (the client 50 -> 58
  fps), X200 19.8 -> 11.3, XPS 26.2 -> 22.9, T550 13.4 -> 10.1; `qt-software-scroll` 1 to 4 points lower everywhere.
  Frames on the screen the same or higher. GL clients, the shell, workspace switching and the latencies unchanged.
- Two costs of the GBM version: `resize` 2 to 9 points higher on every Intel machine, all of it kernel time (a fresh GEM
  object per buffer, whose pages the kernel allocates and clears per resize commit), with the X200 and the XPS at 54
  to 55 fps during the drag instead of 60; and idle memory: Pss +2.2 MiB, heap +2.2 MiB, 2 to 4 threads more (the
  GBM device opens a second Mesa screen), the GPU memory three idle terminals add doubled or more.
- The Galaxy Book's five on blocks: the sprites 25 -> 13%, `resize` 40 -> 65% at 78 instead of 114 fps, +2.8 MiB Pss
  and 6 threads; the dumb-buffer version measured there on 2026-10-29 keeps the sprites' gain with none of the costs.

## Caveats

- The build is the GBM version with the row copy; what master ships since 2026-10-29 keeps the gains and has neither
  cost. Compare a later build with these `off` values for the pre-switch state of r781, not with `on`.
- `ghostty-scroll` did not run on lianli and the Chromebook (no frames, 0.02% compositor CPU): read nothing into it.
- The T550's host name is `aa`. The Mac mini's sprites in a session that ran the whole list are higher than in a fresh
  one (see AGENTS.md); the blocks here all ran the whole list.
