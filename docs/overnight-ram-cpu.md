# Overnight job: lower RAM and CPU usage

Brief for an unattended run. The user is asleep: nobody can answer questions, type the disk password or
look at the screen. Read `AGENTS.md` first, its rules apply.

## Goal

Find changes that lower the compositor's memory or CPU time on the X200 and prove each one with a measurement.
A change without a measured gain outside the noise is not kept.

## Scope (decided by the user on 2026-09-27)

Allowed:
- Internal optimizations without a visible change in behaviour.
- Patches to the embedded aquamarine in `subprojects/aquamarine`.

Not allowed, write them down as proposals in the journal instead:
- Removing features, also the ones `AGENTS.md` lists for removal (screen shaders and so on).
- Changing defaults of config options.
- Anything that touches the compatibility requirements in `AGENTS.md`.
- Changes to the X200 outside `~/hypoland` and `/tmp`, apart from switching between the SDDM session and the test
  loop as described below (no packages, no other system config). The benchmark sets the CPU governor and the
  Omarchy idle flags for its run and puts them back.

## Setup

The X200 normally runs the installed Hypoland package through SDDM. `test-x200.sh`, `bench.sh` and `profile.sh`
need the tty1 test loop that runs the build in `~/hypoland` (see the testing pitfalls in `AGENTS.md`):

1. `ssh root@x200 bash /home/a/hypoland/setup-root.sh a` (tty1 autologin for `a`, SDDM disabled) and
   `ssh x200 chmod +x ~/hypoland/run-loop.sh`.
2. Stop the SDDM session so the loop gets tty1: `ssh root@x200 systemctl stop sddm`, then
   `ssh root@x200 systemctl --user -M a@ stop graphical-session.target graphical-session-pre.target` and
   `ssh root@x200 systemctl restart getty@tty1`.
3. Check that `./test-x200.sh` passes before the first experiment.

At the end put the session back: `ssh x200 'chmod -x ~/hypoland/run-loop.sh; touch ~/hypoland/stop'` (the loop
leaves when the compositor exits), `ssh root@x200 bash /home/a/hypoland/setup-root.sh --undo`,
`ssh root@x200 pkill -x hypoland`, `ssh x200 rm ~/hypoland/stop`, stop `graphical-session.target` as above and
`ssh root@x200 systemctl restart sddm`. Check that `/usr/bin/hypoland` is
running again under `start-hypoland`.

## Rules

- Never reboot the X200. With the loop, restart the compositor with `pkill -x hypoland` and a dead loop with
  `ssh root@x200 systemctl restart getty@tty1`. If the X200 stays unreachable or the GPU hangs for good, stop
  the job and write down what happened.
- Work on a new local branch `overnight/<topic>` from `master` (not an existing one: `overnight/ram-cpu` holds the
  unmerged build flag commits). One commit per kept change, with the measured numbers in the commit message.
  Never push. Leave `master` and uncommitted files in the working tree as they are.
- One change per experiment, so every number belongs to one cause.
- Revert an experiment that does not pass or does not gain (`git checkout -- <files>`), keep a line about it in
  the journal so it is not tried twice.
- Build for `x86-64`, never `-march=native`.
- Leave the X200 as it was found: back on the SDDM session with the installed package (see Setup), no
  `~/hypoland/env`, no `~/hypoland/test.lua`.

## How to measure

`./bench.sh <label>` builds, deploys, restarts, runs `./test-x200.sh` (has to pass) and measures on the
normal build: memory 60 s after the start and again after the workloads, CPU time of five workloads
(idle, GPU client at 60 fps, terminal scrolling, Chromium over shm, workspace switching), three rounds of 20 s
each. It takes about 10 minutes. Results go to `test-results/bench-<time>-<label>/values.txt`.

`./bench.sh --compare <baseline dir> <candidate dir>` prints the difference and marks what is outside the
spread of the rounds.

- Measure the baseline of `master` twice at the start (`baseline-a`, `baseline-b`); older baselines in
  `test-results/` belong to older code. On 2026-09-28 the difference between two starts of the same build was up
  to 0.2 points of CPU time and 1.2 MiB of memory. `--compare` only marks differences above 0.3 points and 1.5 MiB.
  A gain has to be clearly larger.
- Measure a candidate that looks good a second time before it is kept.
- After every kept change the new measurement is the baseline for the next one.
- The benchmark runs with the `performance` governor, so its CPU numbers are lower than the ones in `AGENTS.md`
  (measured with `schedutil`). Compare benchmark numbers only with benchmark numbers.
- `fps.gpu-client` has to stay at about 60. Less CPU time with fewer frames is not a gain.
- A run with an `invalid.*` line (screensaver, lock, compositor restart or crash) does not count.
- For finding where the time or the memory goes: `./profile.sh` (perf, separate build with frame pointers),
  `heaptrack` and `/proc/<pid>/smaps` on the X200. Wrap remote commands in `timeout`.
- A change to rendering is only verified on the X200: no `Failed to link shader` in `~/hypoland/loop.log`, the
  screenshot of `test-x200.sh` shows the window. Look at the screenshot.

## Journal

Keep `test-results/overnight-<topic>/journal.md` up to date after every experiment (earlier runs have their own
journals in `test-results/overnight/` and `test-results/overnight-startup/`, do not overwrite them), so the run can be continued after
an interruption and read in the morning:

| # | change | result dir | RAM (Pss, Anonymous) | CPU per workload | kept / reverted, why |

End with a summary: what was kept (commit ids), total gain against `baseline-a`, proposals that were out of
scope, and open problems.

## Candidates

Starting points. Measure first, the list is a guess. Add what profiling shows. Most of the first list (2026-09-27)
is done or ruled out: THP, the shader compiler, the CRTC mode, the EGL fence, workspace switching, idle wakeups and
compiler flags. See `AGENTS.md` for the numbers.

Memory (2026-09-28, 60 s after the start in the benchmark: Pss 55.2 MiB, Rss 95.8 MiB, anonymous 22.1 MiB):
1. The binary is mapped almost completely. The build flag commits on `overnight/ram-cpu` (`--gc-sections`, `-O2`,
   `-Os` outside the hot paths) save 2.9 MiB Pss, but were not merged by decision of the user: do not repeat them.
2. The XCursor theme and the keymaps are handled (loaded on first use, shared). What `heaptrack` shows at idle now.
3. Shaders that are compiled at start but never used with the default options: compile them on first use.

CPU:
1. `CHyprBorderDecoration::damageEntire()`, about 7% of the compositor's time while windows animated, measured
   before the animation tick change of 2026-09-29. Measure again.
2. `Time::fromTimespec()` makes four clock reads per presented frame (about 1% of the GPU client's compositor
   time), every read is a system call with the HPET clocksource.
3. Per-frame work that does not depend on the damage: passes over all windows, string handling, allocations in
   the render path (`perf` with `--call-graph`, `heaptrack` allocation counts while a client runs).

Out of scope for a night (needs a Mesa build): a crocus-only Mesa without LLVM, see the journal of 2026-09-29.

Checked before and not worth repeating (details in `AGENTS.md`): the speed of the shm upload copy, blur,
`malloc_trim` and the malloc arenas, moving the GSettings cursor sync into a child, `GALLIUM_THREAD=0`. Clock reads
do matter (every read is a system call on the X200), so do not dismiss them as sampling skid.
