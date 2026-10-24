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
- Changes to the X200 other than installing Hypoland packages built from the branch (`scripts/deploy.sh`, which
  `bench.sh` and `profile.sh` call) and files in `/tmp` (no other packages, no system config). The benchmark
  sets the CPU governor and the Omarchy idle flags for its run and puts them back.

## Setup

The X200 runs the installed Hypoland package through SDDM. Every build is tested there as a package:
`scripts/deploy.sh x200` builds it from the working tree, installs it, restarts SDDM and checks the new session
(see the testing workflow in `AGENTS.md`); `bench.sh` and `profile.sh` call it.

1. Note the installed version (`ssh x200 pacman -Q hypoland`), it is the one to go back to.
2. Check that `scripts/deploy.sh --no-install x200` passes before the first experiment.

At the end put the version from step 1 back: `ssh root@x200 pacman -U --noconfirm
/var/cache/pacman/pkg/hypoland-<version>-x86_64.pkg.tar.zst` and `ssh root@x200 systemctl restart sddm`, then check
it with `scripts/deploy.sh --no-install x200`. Builds of uncommitted changes get the version of the commit they
are on, so a kept change has to be committed before its package can be told apart.

## Rules

- Never reboot the X200. Restart the session with `ssh root@x200 systemctl restart sddm`. If the X200 stays
  unreachable or the GPU hangs for good, stop the job and write down what happened; its last kernel messages are
  in `/var/log/netconsole/x200.log` on the desktop.
- Work on a new local branch `overnight/<topic>` from `master` (not an existing one: `overnight/ram-cpu` holds the
  unmerged build flag commits). One commit per kept change, with the measured numbers in the commit message.
  Never push. Leave `master` and uncommitted files in the working tree as they are.
- One change per experiment, so every number belongs to one cause.
- Revert an experiment that does not pass or does not gain (`git checkout -- <files>`), keep a line about it in
  the journal so it is not tried twice.
- Build for `x86-64`, never `-march=native`.
- Leave the X200 as it was found: the package version from the start installed again (see Setup), nothing
  added to `~/.config/uwsm/env`.

## How to measure

`./bench.sh <label>` builds the package, installs it, restarts the session, runs the checks of
`scripts/deploy.sh` (they have to pass) and measures: memory 60 s after the start and again after the workloads, CPU time of five workloads
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
- For finding where the time or the memory goes: `./profile.sh` (perf, with the debug package for symbols),
  `heaptrack` and `/proc/<pid>/smaps` on the X200. Wrap remote commands in `timeout`.
- A change to rendering is only verified on the X200: `scripts/deploy.sh x200` passes (no `Failed to link shader`
  in the compositor's log, the test window in the screenshots). Look at the screenshots in
  `test-results/deploy-*/x200/`.

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
