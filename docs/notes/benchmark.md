# The benchmark and its workloads

Engineering notes of Hypoland, moved out of `AGENTS.md` on 2026-11-12 unchanged. `AGENTS.md` has the rules and
the current state; the notes say what was tried, measured and dropped. Add new findings here, with the date.

`bench.sh`, `scripts/bench/measure.sh`, what each workload does and measures, and their first results.

- `./bench.sh <label>` measures a change on the normal build: memory 60 s after the start and after the
  workloads, CPU time of its workloads (`--help` lists them), three rounds, into
  `test-results/bench-<time>-<label>/values.txt`.
  `./bench.sh --compare <dir> <dir>` prints the difference. It runs with the `performance` governor, so its CPU
  numbers are lower than the ones below (GPU client 3.7% instead of 7-10%). The brief for unattended optimization
  runs is `docs/overnight-ram-cpu.md`.
  CPU time (since 2026-10-26, asked for by the user: work moved from the compositor into a client must show in a
  sum), all in percent of one CPU over the workload's window: `cpu.<workload>.percent` is the compositor alone, the
  scheduler's time of all its threads, comparable with every earlier run. `clients_percent` is the workload's
  clients with every process they start, also those that ended: `measure.sh` starts each client in a transient scope
  of `hypolandbench.slice` under the user's systemd manager (`systemd-run --user --scope`) and reads the slice's
  `cpu.stat`. `total_percent` is the user's whole session, `user@<uid>.service`: the compositor, Xwayland and the
  shell (uwsm runs all three in `wayland-wm@hyprland.desktop.service`, so they cannot be told apart by cgroup), the
  clients and the session's services. `machine_percent` is every CPU's busy time from `/proc/stat`, with the kernel
  threads (the GPU driver's work no process is charged for), interrupts and the benchmark itself. For
  `gtk3-x11-scroll` the session is about 30% on the T550 against 5.5% compositor and 4.3% client: the X11 path's work
  is in Xwayland. Clients that run as fast as they can make their sum a measure of throughput, not of cost:
  `terminal-scroll`'s `ls` loop (133% clients on the T550) and `alacritty-scroll` print more when the terminal takes
  their output faster. `ghostty-scroll` (added 2026-10-28, asked for by the user) is the same loop in Ghostty, a GTK 4
  window drawn by Ghostty's own OpenGL renderer: it needs OpenGL 3.3, so it is skipped on the X200, and the `ghostty`
  package elsewhere (Omarchy's repository; installed on the T550, the XPS, lianli, the T460s, the Chromebook, the
  Galaxy Book and the Mac mini that day). `kitty-scroll` is the same in kitty (OpenGL 3.3 as well, the `kitty` package,
  installed on the same seven machines the same day; kitty takes the command as arguments, no `-e`). On the T550 the
  compositor costs the same with all three GL terminals (5.0%); Ghostty shows 45 frames a second against 60. `velocitty-scroll`
  (added 2026-11-03, asked for by the user) is the same in Velocitty (github.com/valvesky/velocitty), a terminal for Omarchy
  that draws on the CPU into shm buffers like foot but reuses three buffers, so it always takes the zero-copy path; it
  is not packaged, its release tarball's binary goes to `/usr/local/bin/velocitty` (on macmini-m1 only so far), and the
  workload is skipped where it is missing. Games (added 2026-11-09, asked for by the user after Phoronix's Omarchy 4.5
  comparison of 2026-11-06, where Omarchy showed 3 to 6% fewer frames than Arch with Plasma in GravityMark and in Xonotic
  above its lowest effects, and the article named the desktop as a possible cause): `xonotic-low` and `xonotic-ultimate`
  (`xonotic-high` and `xonotic-ultra` too, not in the default list) play Xonotic's benchmark demo `the-big-keybench`
  fullscreen without vsync at that effects preset, as Phoronix's test does, a native Wayland client (SDL 2 through
  sdl2-compat takes Wayland, Phoronix's bundled build as well). The demo is 35534 frames, minutes on these machines, so it
  is stopped after the window, 3 s after loading ends; stopped, the game prints its frames and seconds so far, which
  make `fps.xonotic-*`. A fresh `-userdir` each time, no sound. `gravitymark-gl` and `gravitymark-vk` run GravityMark
  (Tellusim's, the AUR package `gravitymark` in `/opt/gravitymark`, x86_64 and aarch64) fullscreen without vsync, an X11
  client through Xwayland. Its benchmark lasts 167 s whatever the frame rate and it reports nothing when stopped early,
  so the window is its run (155 s from 5 s after its start, whatever `--seconds` says) and `fps.gravitymark-*` its own
  mean (`FPS:`); `fps.gravitymark-*.low` is the frame rate at the 99th percentile of its frame times. OpenGL needs 4.5
  (not the X200), Vulkan not r600: it says so and is skipped. They come last in the default list, about 8 minutes a round, so the A/B nights (`abnight.sh`, which runs the default
  list) have them, and its `table.py` shows the client's own frame rate as well.
  The game's frame rate is the throughput figure; `fps.*.screen` is what the compositor showed. Tested nested on the
  desktop first (2026-11-09, RX 7600, 1920x1080 headless: Xonotic low 1513 fps, ultimate 825, GravityMark OpenGL 155.3
  fps, Vulkan 151.1), then on nine machines the same day (`test-results/games-20261109/`), which have `xonotic` and the AUR
  package installed now: not the Chromebook (652 MB free for Xonotic's 1.1 GB) nor macmini-m1. lianli's r600 locked up five
  times under `xonotic-ultimate` (stock Hyprland 0.57.0 aborted on the GPU reset), so presets above low are skipped on
  radeon. GravityMark draws 0.5 to 6 fps on the Intel GPUs (about 1 on the XPS at 3200x1800) and 19.6 on the Galaxy Book;
  its OpenGL renderer segfaults on the T550, the XPS and the Galaxy Book, it cannot run on the X200, samsung-i5 or lianli,
  and its Vulkan renderer fails on the Mac mini. One round against Hyprland 0.57.0 (`ab/`, `abtable.py`): Xonotic low 5
  to 9% more frames under Hypoland on Intel (the XPS 19%), ultimate 1 to 8%, GravityMark the same, with less compositor
  CPU a frame. Fullscreen and direct scanout for them are further down (fullscreen games). ElectroBench (added 2026-11-10,
  asked for by the user, github.com/deadbeef7/ElectroBench, GPL-3, not packaged: `scripts/machines/electrobench.sh <host>...`
  builds a pinned commit on the machine into `/opt/electrobench` and installs glew) has four scenes of fixed length without
  vsync, each run by itself fullscreen and in a window: `electrobench-guns` (scene 1, OpenGL 2.1, 60 s, so the X200 too),
  `electrobench-ocean`, `-pool` and `-lines` (OpenGL 3.3 core, 45 s each, skipped without it), each with a `-window` twin,
  about 7 minutes a round, last in the default list. A native Wayland client (`SDL_VIDEODRIVER=wayland`: sdl2-compat
  takes X11 otherwise, and without a DISPLAY it fails rather than try Wayland); Arch's GLEW is built for GLX, so on an EGL
  context `glewInit()` returns `GLEW_ERROR_NO_GLX_DISPLAY` after loading the functions, which scenes 2 to 4 took for a
  failure: they accept it since upstream merged our fix (PR #60, 2026-11-10; until then the install script patched them). The workload waits for `FPS :` in the window's title (the scene
  draws), measures from 2 s later until about 5 s before the scene's end (invalid if the scene printed its result before the window ended) and takes the scene's own mean as `fps.<workload>`.
  Scene 1 draws every face of its 110 guns with `glBegin` / `glEnd`, twice a frame: 0.6 fps on the X200, 1.6 on the T550, 3.4 on the T460s,
  1.2 on the Galaxy Book, 5.4 nested on the desktop. Its window is not resizable, so in a window it floats at 1280x720 pixels (853x480 at the T460s'
  1.5); the other scenes tile. SDL 2 is not scale aware, so at a fractional scale the fullscreen buffer is the logical size
  scaled up. First run, T460s, fresh session, one round (game fps fullscreen / window; compositor CPU ms a frame): guns 3.4
  / 3.3 (0.53 / 0.84), ocean 12.3 / 12.6 (0.43 / 0.82), pool 18.1 / 19.2 (0.50 / 0.96), lines 48.4 / 49.7 (0.54 / 0.91),
  the GPU busy 89 to 100% in all (`test-results/bench-20261110-*-eb-t460s-fresh/`). The Galaxy Book draws
  the lines in a window at 102 fps (`-eb-galaxybook`). Installed on every machine on 2026-11-10 (the Galaxy Book after
  its power cycle). Scenes 2 to 4 once on every machine the same day (`-eb-quick-*`, ocean / pool in a window / lines,
  game fps): Galaxy Book 13.6 / 49.6 / 103.6, T490 12.9 / 19.9 / 48.6, T550 10.5 / 15.5 / 36.0, Mac mini 10.1 / 13.5 /
  44.4, lianli 9.9 / 14.3 / 35.5, samsung-i5 6.1 / 9.1 / 26.7, XPS 5.4 / 6.2 / 14.4, Chromebook 2.3 / 5.3 / 12.1. The
  screen shows every frame on iris and freedreno, but only about half of them on crocus in a window (Mac mini pool 13.5
  drawn / 6.7 shown, samsung-i5 9.1 / 4.5, Chromebook 5.3 / 2.6) and on lianli's r600 in all three (lines 35.5 / 16.5);
  not looked into yet. macmini-m1 has no monitor, so stock Hyprland has no `wl_output` for SDL ("The video driver did not
  add any displays", which ElectroBench reports as no OpenGL 3.3): with `hyprctl output create headless` it draws 53.5 /
  83.8 / 193.5 (asahi). The workload's check that the scene did not end inside the window compares when the result was
  printed with the window's end (`WINDOW_END`, set by `bench()`): the result being there when `rec` returned was too
  coarse, since its steps around the window take seconds on the Chromebook. The graphics benchmarks of Phoronix's first
  look at the Snapdragon X2 Elite on Linux (added 2026-11-11, asked for by the user, phoronix.com/review/snapdragon-x2-linux/2,
  run as Phoronix's test profiles pts/supertuxkart-1.8.1, pts/yquake2-1.3.0 and pts/vkmark-1.3.2 run them, but fullscreen
  at the monitor's size), last in the default list, about 5 minutes a round: `supertuxkart-vk` (the `supertuxkart` package,
  774 MB) is SuperTuxKart's `--benchmark`, the replay of a race on black_forest (38 s of race), Vulkan, Ultimate effects, no
  frame limit; `fps.supertuxkart-vk` is its frames over its time, `.steady` and `.stable` its "Steady FPS" and "Mostly stable
  FPS" (Phoronix's two charts), the window 30 s inside the race; `supertuxkart-gl`, OpenGL, is outside the default list.
  Phoronix's config sets vsync off as `swap-interval`, a name SuperTuxKart 1.5 does not know (it is `swap-interval-vsync`),
  so its runs had vsync: the Galaxy Book's stayed at 119 of its 120 Hz with it. `yquake2-vk` and `yquake2-gl3` are Yamagi
  Quake II's timedemo of the demo q2demo1.dm2 (632 frames) with 16x anisotropic filtering and 16x MSAA (8 on Intel, 4 with
  Vulkan on the Adreno), played over and over (a config that stops the server and starts the demo again: a demo started
  over the one that ended ends at once, thousands of 0-frame passes a second), `fps.<workload>` the frames over the seconds
  of the passes the window overlaps; not packaged in Arch, `scripts/machines/yquake2.sh <host>...` builds Phoronix's
  versions (8.10, ref_vk 1.0.2) on a machine into `/opt/yquake2` with the Quake II 3.14 demo's data. `vkmark` (the `vkmark`
  package) runs its 13 scenes of 10 s fullscreen in mailbox mode, `fps.vkmark` its score. All are skipped on radeon (no
  Vulkan, and 16x MSAA without vsync was not tried on the r600 that locked up under Xonotic) and where the API is missing.
  Installed on 2026-11-11 on every machine but the X200 and lianli. First runs that day, one round each (`supertuxkart-vk` /
  `yquake2-vk` / `yquake2-gl3` / `vkmark`): Galaxy Book 121.9 / 195.8 / 287.3 / 3805, T550 33.2 / 29.4 / 109.9 / 772, T460s
  42.1 / 21.9 / 85.0 / 1231, T490 44.6 / 20.5 / 66.8 / 1174, samsung-i5 18.8 / 16.7 / 63.5 / 489, XPS 17.3 / 10.6 / 46.0 /
  250, Chromebook 9.7 / 9.5 / 59.9 / 464, macmini-m1 none / 1930 / 903 / 8764. vkmark at scale 1.5 (T550, T460s, T490,
  samsung-i5) ran before the drawing fix of that day (render checks above). The first runs found two bugs of the measured
  direct scanout, both fixed on 2026-11-12 (fullscreen games below): SuperTuxKart's race stalled under
  `render:direct_scanout = auto` (its Steady and Mostly stable FPS 0; the night of 2026-11-11: 15 of 15 races on the
  Galaxy Book, 7 of 13 on the T460s, 3 of 13 on the T490, never under stock), and on macmini-m1 it gave no result
  (`vkCreateSwapchainKHR failed`). The T460s's four invalid results and macmini-intel's missing ones of that day did not
  come back in that night (macmini-intel on a headless output). `flea-scroll` and `nautilus-scroll` (added 2026-10-29, asked for by the
  user) scroll a folder of 5000 empty files in Flea (a keyboard-first file manager for Omarchy, thisisgm/flea, in
  Omarchy's package repository but never its default; a Quickshell window in 0.3.12, a GPUI window in 0.4.1) and in
  Nautilus (GTK 4, its list view,
  set for the run if needed) with the Down key held on the uinput keyboard for the whole run
  (`clients/holdkey.py`, root only): the compositor forwards the one press and the client repeats it at the session's
  rate (Omarchy: 40 a second after 250 ms, about 480 files in the 12 s). At the end, with the window still open, the
  clients' memory (`mem.<name>.clients_Pss_kB`, the Pss of the processes in their scopes; `clients_cgroup_kB` and
  `clients_peak_kB`, the scopes' current and peak memory, page cache included) and the compositor's (`mem.<name>.*` as
  for `mem.start`). One run each, 2026-10-29: both at 40 frames a second on the T550 and the X200; compositor T550
  3.1% / 3.3%, X200 3.8% / 4.2%; the client Flea 13% / 27%, Nautilus 31% / 59% (GTK 4 on cairo on the X200); the
  clients' Pss with the folder loaded Flea 105 MB, Nautilus 115 to 119 MB on both, their cgroups' peak Flea 111 / 163 MB,
  Nautilus 92 / 180 MB (X200 / T550); the compositor 42 to 45 MB Pss. The older `flea` and
  `nautilus` workloads page with four keys a second and toggle fullscreen twice a second, which is why they show 8 and
  25 to 32 frames a second. Flea 0.4.1 is a GPUI window (`flea --gui` runs `flea-gui`, Rust, drawn through wgpu; "the
  QML frontend is no longer available") and opens no window on the X200
  (GM45: OpenGL 2.1, no Vulkan), and the shell's critical notification "No graphics driver could open Flea" stayed over
  the windows for the rest of the session (every later workload of the X200's blocks in the night of 2026-11-10, a deploy
  check's render steps): since 2026-11-12 both Flea workloads check for its window (`flea_opened()`) and are skipped
  without it, the notification dismissed. Flea is Omarchy's package, not pinned like Folio: 0.4.3-1 on every machine
  but macmini-intel since 2026-11-18 17:52 (the user's request; 0.4.2-2 on most before, galaxybook and hp-amd had
  0.4.3 already), so Flea's numbers across that date compare only with that in mind. `folio` and `folio-scroll` (added 2026-11-11, asked for by the user) are the same two as
  Nautilus' in Folio (`folio`, C++ and Qt Quick), Omarchy's file manager in place of Nautilus since omacom/omarchy#18378
  of 2026-11-10; the soak has it too (`w_folio`, `w_files_folio`, `w_search_folio`). Folio keeps its view in
  `~/.config/folio/folio.conf`, which they set and put back. Since 2026-11-12 the two workloads need Folio 0.4.0 or later
  (`folio>=0.4.0` in `missing()`), installed on all eleven machines that day from Omarchy's repository (0.1.1, 0.2.0 or
  none before). Folio 0.1.1 to 0.4.0 (0.2.0 released 2026-11-11, a2bc0ca; 0.4.0 checked on the XPS on 2026-11-12) do
  not scroll the list to the cursor on Down: the cursor walks off the bottom and the view stays (XPS, screenshots), so
  until that is fixed `folio-scroll` measures the cursor and the details pane redrawn, not scrolling, and does not
  compare with `nautilus-scroll`. The fix is in omacom/folio#18, open on 2026-11-11 and tested on the XPS (the report,
  a headless test and the screenshots are in `test-results/folio-scroll-bug-20261111/`). From 2026-11-16 (asked for by
  the user) both workloads and the soak's ran one commit of Folio built on each machine into `/opt/folio/<commit>/`
  (`FOLIO_COMMIT`, `scripts/machines/folio.sh`, both gone since), not Omarchy's package: 2e2a716 of 2026-11-16
  (omacom/folio#79, after 0.5.0), which keeps the cursor in sight on Down, so `folio-scroll` scrolls from then on and its
  numbers before do not compare; on 2026-11-18 briefly bf947e6 (tag v0.6.1).
  Since 2026-11-18 (asked for by the user) they run Omarchy's package again, `/usr/bin/folio` (`FOLIO` overrides it),
  and need 0.6.1 or later (`folio>=0.6.1` in `missing()`; the soak's `folio_ok`), from Omarchy's edge repository on
  every machine that day. 0.6.1 (tag of 2026-11-17): its list is a tree (omacom/folio#160), an idle window no longer
  draws every refresh (omacom/folio#100), and CTRL 1, 2, 3 are columns, list and grid (grid, list, columns before; the
  soak's `w_folio` keys follow), so Folio's numbers before do not compare either. The workloads still set the view by
  `viewMode=` in `folio.conf`, which 0.6.1 reads the same way. The package follows Omarchy's updates, so a later
  version can move the numbers: `bench.txt`'s header line `apps:` has the Folio and Flea packages of the run. First run,
  one round of each
  in a fresh session (compositor CPU / frames on the screen, the client):
  T460s `folio` 1.41% / 18.9 fps, `folio-scroll` 4.11% / 58.5 fps, client 22.3%, its Pss 88 MB (Nautilus 2.16% / 27.8,
  3.10% / 40.5, 28.5%, 119 MB); XPS `folio` 1.79% / 17.9, `folio-scroll` 4.73% / 58.5, 30.5%, 91 MB (Nautilus 2.78% /
  20.8, 3.26% / 40.4, 33.5%, 111 MB). Before 2026-10-26 the clients ran in root's ssh session (`user-0.slice`), which
  the CPU controller weighs against the user's slice; now they share the user's slice with the compositor, as programs
  started from the desktop do in `app.slice`. `systemd-run` expands `$` in the command it runs like `ExecStart=`
  does, so it runs with `--expand-environment=no` (a client's `$$` came out as `$` and nothing stopped them).
  `fps.<workload>.screen` (since 2026-10-26) is the frames the compositor put on the screen per second over the same
  window: its page flips, counted as the flip events DRM delivers to it (`perf stat -a -e
  drm:drm_vblank_event_delivered`, root; the same tracepoint on i915, radeon and msm). Idle reads 0.0 and
  `gpu-client` 60.1 on the X200. Read a sum of CPU time with it: a compositor that shows more frames makes its
  clients draw more. `fps.<workload>` without `.screen` stays the client's own frame rate.
  `gpu.<workload>.busy_percent` (since 2026-10-29) is the time the GPU's render engine was busy over the same window, from
  the i915 PMU (`perf stat -a -e i915/rcs0-busy/`, root; radeon and msm have no such counter, nothing is reported
  there): the compositor's blending, the clients' drawing and Mesa's copies all count. On the XPS a scrolling GTK 3
  window keeps it at 40%, a GL client at 60 fps at 34%, the resize drag at 78%. `cpu.<workload>.ms_per_frame` and
  `gpu.<workload>.busy_ms_per_frame` (since 2026-10-29 evening, asked for by the user) are the same two per frame the
  compositor put on the screen, in milliseconds (percent times ten over `fps.<workload>.screen`), so a build that shows
  more frames is not read as one that costs more: on the X200 `gtk3-scroll` went from 14.4% at 40 fps to 18.2% at 55
  with the alpha bounds, which is 3.6 to 3.3 ms of compositor CPU a frame.
- OpenMetrics (2026-11-16, asked for by the user): next to `values.txt`, `bench.sh` writes `results.om` and a night's
  `report.sh` (from `test-results/night-20261116/`) one per compositor, with every value of every round or block instead
  of the medians, labelled with what it was measured on, so that a file says what it holds without its directory and
  loads into Prometheus or VictoriaMetrics as it is (`promtool tsdb create-blocks-from openmetrics`).
  `scripts/bench/openmetrics.py` writes and reads it, standard library only: a key's first part is the group, its last
  the statistic and the middle the `workload` label (`phase` for `mem.start` / `mem.end`), so
  `cpu.folio-scroll.ms_per_frame` in round 2 is
  `hypoland_cpu_ms_per_frame{machine="t490",compositor="hypoland",version="0.3.0.r1025.g...-1",run="bench-...",block="2",workload="folio-scroll"}`,
  `fps.<workload>`, `flips.<workload>` and `invalid.<workload>` are `hypoland_fps` and so on with only the label, and
  `hypoland_run_info` has the machine's kernel, cores and memory, the binary, its instance, the clocksource and the
  governor. A metric whose statistic ends in a unit (`kB`, `ms`, `ms_per_frame`, `percent`, `W`, ...) declares it.
  `openmetrics.py values FILE [--label compositor=hyprland]` prints `values.txt` from it (the same medians, the lower
  middle one with an even count), `openmetrics.py keys FILE` every sample. The version label is the package (`package:`,
  a line `measure.sh` prints since that day), for older runs `g<commit>` from the compositor's instance signature; the
  time of every sample is the compositor's start. A night's file is 4 to 5 times its `raw.txt` (2.4 MB for one
  compositor on the X200 for the 11-14 night), plain all the same: the desktop's btrfs compresses it (zstd). The files
  are not committed, by decision of the user: `.gitignore`'s `result*` keeps them out, also in `docs/baseline/`, whose
  `values.txt` and `raw.txt` stay what is in git. Every older result was converted the same day
  (`test-results/om-convert-20261116/convert.sh`): the 180 compositors of `docs/baseline/` (versions from their READMEs,
  the time the start the README gives, else the day; the two A/Bs of 2026-10-22 with both compositors in one `raw.txt`),
  598 `bench.sh` runs and 226 nights' compositors in `test-results/`. Read back, each gives its `values.txt` exactly,
  except 9 bench runs of September and October with 2 to 5 lines that two writers interleaved (`@ 1
  cpu.terminal-scroll.stddev 0@ 1 @ 1 mem.end.Rss_kB 81740`), which are left out. The `prometheus_client` parser (strict
  about the format) accepts all 1004 files. Not converted: the shmtex night in `test-results/abnight-20261028-shmtex/`
  has no `raw.txt` (its copy in `docs/baseline/` has). `bench.sh --compare`, the nights' `table.py` and `scripts/web/`
  still read `values.txt` and `raw.txt`.
- `bench.sh` and `profile.sh` are not tied to the X200 (they were `bench-x200.sh` and `profile-x200.sh` until
  2026-09-28). `--host <ssh host>` or `--host local` picks the machine, `--login` the ssh login (root by default,
  without root the governor is left alone), `--no-deploy` measures the compositor that is running,
  `--workloads a,b` picks workloads and `--client name=command` measures any client as one more workload.
  The work on the machine under test is `scripts/bench/measure.sh`. It takes the compositor (`hypoland`, then
  `Hypoland` of older builds, then `Hyprland`), its user, prefix, instance and Wayland socket from the running
  process and its `hyprland.lock`, starts clients with the environment of the compositor, skips workloads whose
  client is not installed and only touches the Omarchy idle flags where Omarchy is installed. Since 2026-10-25
  evening it is split: `measure.sh` parses the options and runs the mode, its parts are in `scripts/bench/lib/`
  (`session.sh`, `meters.sh`, `setup.sh`, which runs when sourced, `measuring.sh`, `workloads.sh`, `check.sh`) and
  the programs it starts as clients are files in `scripts/bench/clients/`, which editors and linters can read
  (`python3 -m py_compile`, `luac -p`). `scripts/bench/target.sh` holds the ssh part for `bench.sh`, `profile.sh`
  and `scripts/deploy.sh`: it sends the whole `scripts/bench` directory as a tar stream on stdin and runs it from
  a temporary directory, which it removes afterwards, so an edit runs without a deploy. The same files are installed
  on the machines by the `hypoland-bench` package (since 2026-10-27, a second package of the PKGBUILD, which
  `scripts/deploy.sh` installs with the compositor): `hypoland-measure` is `measure.sh`, for a check or a
  measurement on the machine itself, and `hypoland-soak`, `hypoland-soak-ab` and `hypoland-energy-meter` are the
  soak scripts, which needed copies in `~a` and `/root` before (`soak-ab.sh` still prefers those copies when they
  are there). Build,
  install and restart go through `scripts/deploy.sh`, whose checks have to pass (`--no-build` installs the
  package that was built last).
- Toolkit workloads (added 2026-10-25): `measure.sh` brings its own GTK client (`scripts/bench/clients/toolkit.py`,
  Python with `python-gobject`) and Qt Quick client (`toolkit.qml`, `qml6`) and starts them, so the machines need
  nothing beyond Omarchy. Both show the same long text
  and print their renderer and frame rate (`fps.*`, the frames the compositor let them draw): `gtk3-scroll`,
  `gtk4-scroll`, `qt-quick-scroll` and `qt-software-scroll` (Qt Quick's software backend, shm like Qt Widgets)
  scroll it, a full window of damage per frame; `gtk3-x11-scroll` is the GTK 3 one through Xwayland;
  `gtk4-spinner` has only a spinner moving, `qt-software-sprites` 60 small squares (many small damage regions);
  `video-window` is the `video` clip in a tiled window instead of fullscreen. `tk-canvas` (added 2026-10-27) is the
  60 squares on a Tk canvas (`clients/toolkit-tk.py`, Python's `tkinter`): Tk draws only through X11 on Linux, with
  core X11 requests that Xwayland carries out. The canvas redraws the bounding box of what changed into a new pixmap of
  the X server and copies it to the window, so with the squares all over it the damage is one region of close to the
  whole window per frame, not many small ones. An X11 client gets no frame callbacks: Tk moves the squares 60 times a
  second by its own timer (`fps.tk-canvas`), what the screen shows is `fps.tk-canvas.screen`. On the X200 (r748, 2
  rounds) the compositor takes 4.5%, Tk 10.4% and the session 70%: Xwayland is about 55% of a core and shows 44 of
  the 57 frames (`gtk3-x11-scroll`: compositor 3.1%, session 57%, 28 frames on the screen). The deploy check runs the
  same client with a menu and a dialog: the Tk window drawn, a menu (an X11 window the window manager does not manage,
  override-redirect) posted at a fifth of the window, which has to show above it where Tk put it, compared in the
  screenshot to the window's own box in proportion, so any scale works; and a dialog that belongs to the window
  (`transient`, type dialog), which has to float over it and show whole. Tk is not part of Omarchy: the `tk` package
  has to be installed (`pacman -S tk` as root), the workload and the check are skipped without it. They port the useful ideas of
  Phoronix's gtkperf, x11perf, qmlbench and video-cpu-usage (the user decided against running Phoronix tests).
  GTK 2 is not in Arch any more. `idle-windows` opens three foot windows that print for 4 s and then sit idle, and
  reports the GPU memory they add without the purgeable part (`mem.idle-windows.gpu_added_kB`). Only meaningful as
  the only workload of a fresh session (`--workloads idle-windows`): buffers an earlier workload left are freed in
  the meantime. radeon reports no memory in fdinfo, 0 there. Its windows and those of `workspace-switch` and
  `resize` also measure switching between them, see below. `dev` (suggested by the user) is a developer's screen
  in Alacritty: nvim (`--clean`, LazyVim would set itself up first) on a C file of 210000 lines on the left half, a
  console on the right, below it a log of 200 lines a second with a burst of 400 lines every 10 s, which never has
  the focus. The files and a git repository are generated, the same everywhere. A uinput keyboard (root only) drives
  it, the same input path as a real one, in two phases on the same windows. Load, `cpu.dev.*`: every 3 s the focus
  moves (SUPER+Left, SUPER+Right, Omarchy's binds) between the editor, which scrolls a line 40 times a second and
  jumps every 2 s while it has the focus, and the console, which gets a command typed into it, every other time a
  `git diff` of 9000 lines paged through ten times a second, in between `ls`, `git status` or a `git show` of 3000
  lines. Latency, `latency.dev.<kind>_ms` (median) and `_p90_ms`: the editor stops scrolling by itself, and every
  key is followed until the first frame that shows it, `focus` (SUPER+Left into the editor and SUPER+Right back),
  `scroll` (Ctrl-D, Ctrl-U), `jump` (`<line>G`) and `type` (a command typed into the cleared console). The frames
  come from wlr-screencopy of a small region (the border above the window, or its text) until it changes. Keys go
  down at a random point of the frame, as a person's do: pressed right after a commit, as at first, every key had
  the same phase and the 90th percentile hardly differed from the median. The driver is
  `scripts/bench/clients/dev.py`, a Python script without libraries, so it runs on every machine, with the parts it
  shares with `windows.py` (Wayland, screencopy, the uinput keyboard and pointer, the hyprctl socket) in
  `latency.py`; the generator of the files, the editor's movements, the console's shell and the log are the `dev-*`
  files next to it. The drivers run as root from the directory `target.sh` unpacked, not from the user's. The time
  ends at the commit of that frame (the compositor stamps a copied frame when it commits it), the display shows it
  at its next refresh. On a screen where nothing else draws the compositor commits right after the key, so there
  the time is its own work (about 2 ms on the T550); in `dev` the log keeps every frame busy and a key waits for
  the next one.
  Every workload with several windows measures switching between them the same way after its CPU time
  (`scripts/bench/clients/windows.py`, root only): `focus` moves the focus to a neighbouring window with SUPER+arrow,
  in a direction picked at random among those that have one, until the border of the window that had it changes
  (`workspace-switch`, `idle-windows`, `resize`); `workspace-switch` also has `workspace`, SUPER+2 and SUPER+1, until
  the middle of a window changes, and `bar` (added 2026-10-26), the same keys until the first quarter of Omarchy's bar
  changes: its workspace widget, redrawn by the shell after the compositor's event (T550: 15.6 ms against 1.7 ms
  for the window). Since Omarchy r7338 the bar's window spans the screen (see `HYPOLAND_ALPHA_BOUNDS` under Tools), so
  the region is the strip's thickness at most (since 2026-10-29; before, a quarter of the screen, and the window
  animation changed it at the first frame: the 2 ms `bar_ms` readings of r7338 machines were that). The driver waits
  0.7 s after every step for Omarchy's border animation (539 ms)
  to end. `resize` (added 2026-10-26) puts foot (shm) and Alacritty (GL) side by side, both full of one long line of
  numbers that wraps at the window's edge, and drags the split between them with SUPER and the right button
  (Omarchy's resize bind) by a uinput absolute pointer, 125 motions a second like a mouse, for the CPU time
  (`cpu.resize.*`): every motion has both clients draw at a new size. Then single motions of the same drag,
  `latency.resize.resize_ms` until the first frame that shows them (the compositor moved the windows) and
  `redrawn_ms` until the first frame that shows the region across the split as it then stays for 0.5 s (both clients
  drew at their new size). The text has to reach the split: with the short lines of `ls -la` a client's redraw
  changed no pixel there on wide screens, and `redrawn` was the compositor's first frame. foot runs with
  `resize-delay-ms=0`: by default it waits 100 ms after the last resize before it reflows its text, which made
  `redrawn` 108 ms on every step. A/B against stock Hyprland 0.56.2 (2026-10-26, 4 to 5 alternating rounds on all
  seven machines): on the T550, the XPS and the Galaxy Book stock shows a switch or a resize about a frame later
  (focus 7.1 / 16.3 / 3.7 ms against 1.8 / 2.0 / 1.4, `redrawn` 5 to 15 ms longer), on the X200, the EliteBook, lianli
  and the Chromebook the two are the same. `cpu.resize` is the same or up to 2 points lower, except on the X200
  (16.8% stock with the GLES 3 override, 21.5% Hypoland). `resize-foot`, not in the default list, is the same with
  foot on both sides: shm buffers only, which no GL driver or Mesa variable touches. On the X200 (rounds 2 to 4 of
  2026-10-26) it shows the same gap as `resize`, so it is not Alacritty under stock's GLES 3 override: compositor
  23% / 31%, clients 75% / 110%, session 98% / 141% (stock / Hypoland). It is the frames: during the drag the X200
  shows 40 frames a second under stock and 60 under Hypoland (`fps.resize.screen`, 4 rounds of each, 2026-10-26), and
  every frame has both clients draw at a new size. Per frame on the screen Hypoland's compositor costs 13% less
  (`resize` 0.36 / 0.41 points per frame a second, `resize-foot` 0.52 / 0.59), the whole session the same (`resize`
  +4%, `resize-foot` -6%). `gtk3-scroll` in the same run: stock 30 fps on the screen and the client, Hypoland 59,
  with the session 33% cheaper per frame.
  Omarchy's shell (added 2026-10-26, both skipped where `omarchy-shell shell ping` does not answer): `notifications`
  has notify-send deliver a notification a second from four senders, low urgency (5 s each), over an idle foot window,
  so about five cards stand in the shell's column at the right of the screen, one sliding in and one going every
  second; they end up in the shell's history, the cards are dismissed afterwards. Then `latency.notifications.toast_ms`:
  one notification at a time sent over the session bus by `scripts/bench/clients/shell.py` run as the user (the
  bus refuses root; `sessionbus.py` next to it marshals the D-Bus call by hand, so no library is needed) until the
  top of the shell's notification column changes, each closed through the bus again. `menu` toggles Omarchy's menu
  (SUPER+SPACE) every second over the same window, through the global shortcut the shell registers (`hyprctl
  globalshortcuts`): a fullscreen overlay layer with a half transparent scrim and a card in the middle, which takes
  the keyboard focus. Then `latency.menu.open_ms` from SUPER+SPACE by the uinput keyboard until the scrim shows in a
  strip at the left of the screen, `close_ms` from Escape until it is gone, `search_ms` from a letter typed into
  the open menu's search line until the rows of its card change, and `select_ms` from Down or Up until the selected
  row, moved into the middle rows first, shows moved (`scripts/bench/clients/shell.py`). The shell's own
  CPU time is in `cpu.*.total_percent` (the session), not in the compositor's. Measured 2026-10-26
  (one round of 12 s on a fresh session, `performance` governor; compositor / whole session, latency medians):

  | | X200 | T550 |
  |---|---|---|
  | notifications | 3.4% / 17.3% | 2.7% / 11.2% |
  | menu | 2.0% / 88% | 1.3% / 61% |
  | menu open / close | 427 / 36 ms | 178 / 10 ms |
  | menu search | | 85 ms |
  | menu select | | 5 ms |
  | toast | | 23 ms |

  Opening the menu is the shell's work: it maps a fresh fullscreen surface and fills the card every time, which
  costs the X200 both cores for most of a second and the T550 0.6 cores, and the scrim shows after 0.26 to 0.61 s
  there. Closing is an unmap, a frame or two. The A/B of 2026-10-26 had `close` two to three frames slower than
  stock on the X200 and the Chromebook (31.5 against 6.3 ms), one frame on r600: the layer's map and unmap simulate
  a mouse move (upstream #16455, cherry-picked as c56c3db8d, not in 0.56.2), that showed the cursor Omarchy hides on
  key presses, Escape hid it again, and the frame for that repainted the whole screen (two screen buffers, the
  benchmark's last frame was a full one) while the pending screencopy's readback blocked the compositor for about
  24 ms and the shell's unmap waited. Fixed 2026-10-27: a simulated move keeps a cursor hidden
  (`CInputManager::m_simulatedMovement`, checked by the renderer's mouse move listener). X200 close 5.6 ms, the rest
  unchanged. Found with perf tracepoints (the shell's and the compositor's socket calls, the atomic commits, the
  vblanks, `-k CLOCK_MONOTONIC`, so the driver's stamps line up) and stderr prints in the renderer.
  Screencopy takes the compositor off direct rendering while it captures, which is why the CPU time is measured in
  the load phase only. It refuses to run on a locked session, whose password field would get the keys: on
  2026-10-25 a run typed six commands into the X200's lock screen (six failed logins for `faillock`, which locks
  the account at 10; reset with `faillock --user a --reset`). Before 2026-10-25 evening the developer's screen was
  lighter (`dev-log` / `dev-diff`, a 20000 line file paged through four times a second, a log of 20 lines a
  second, driven with `hyprctl`), its numbers below are not comparable. `measure.sh` dismisses Omarchy's
  notifications when it starts: one left on the screen is drawn over the windows in every frame. `--env NAME=VALUE`
  gives the clients a variable, as a session's `hl.env` gives the programs it starts (the Mesa overrides of the
  GLES 3 override for stock Hyprland on the X200). Zed (GPU, Vulkan) is a candidate for a later editor, it cannot
  run on the X200. Measured 2026-10-25 (compositor CPU, `performance` governor):

  | | X200 | T550 | XPS (scale 2) |
  |---|---|---|---|
  | terminal-scroll (foot) | 9.9% | 11.4% | 23.4% |
  | gtk3-scroll | 19.3% | 19.8% | 23.3% (42 fps) |
  | gtk4-scroll | 11.0% (cairo) | 4.4% (Vulkan) | 5.6% (Vulkan) |
  | qt-quick-scroll | 3.8% (47 fps) | 4.1% | 5.3% |
  | qt-software-scroll | 9.4% | 13.8% | 12.5% |
  | gtk3-x11-scroll | 3.6% | 5.4% | 6.8% |
  | gtk4-spinner | 4.0% | 4.2% | 5.0% |
  | qt-software-sprites | 58.8% (37 fps) | 13.4% | 29.7% |
  | video-window | 3.1% | 2.6% | 2.8% |

  - GTK 4 finds neither GLES 3 nor Vulkan on the X200 and draws with cairo into shm buffers. Qt Quick draws with
    GLES 2 there, but scrolls at 47 fps where its software backend makes 60.
  - `qt-software-sprites` cost the X200 six times the full-window scroll: Mesa 38% of the compositor's samples,
    pixman 17%, libc 26%. Every draw is repeated per damage rectangle and `CGLTexture::uploadRegion()` made one
    `glTexSubImage2D` per rectangle, and the double buffered update adds the damage of the update before, which
    pixman splits into bands of many small rectangles. Fixed on 2026-10-25 for crocus
    (`CHyprOpenGLImpl::coalesceDamage()`, `Math::coalesceRegion()`): above 8 rectangles the frame damage and the
    upload are merged into horizontal strips, or their bounding box. X200: 59.1% -> 31.7% CPU, the client 36.5 ->
    55.1 fps, every other workload unchanged. Not on other drivers: on the XPS (iris, 3200x1800) merging cost
    30.2% -> 36.3%, the bounding box of the squares is the whole window, 21 MB per frame; without it the XPS is
    unchanged. The lighter `dev-log` / `dev-diff` on the XPS: 2.5% / 1.2%, the same before and after. A/B on all
    six machines (2026-10-25, 15 workloads, 3 rounds each): only the X200 changes. On r600 (lianli, 2026-10-27) the
    merging is on as well: every upload rectangle is a staging texture and a blit there, and the second texture
    doubled the rectangles, so the sprites cost 81.8% against 48.2% for stock in the A/B of 2026-10-26; merged 26.1%.
    On the Mac mini (Haswell, crocus with the tiled copy, 1920x1200) the merging loses (2026-10-28, from the overnight
    A/B of 2026-10-27, where the sprites cost 32.5% against 20.3% for Hyprland 0.56.2 at the same 60 fps; alternating
    fresh sessions with the switches `HYPOLAND_NO_COALESCE=1` and `HYPOLAND_SINGLE_TEXTURE=1` in the compositor's
    environment, see Tools below): the sprites 26.7% merged against 24.1% as sent, `qt-software-scroll` 10.4 against
    8.5, the Chromium window, the terminal and GTK 3 the same. One texture alone changes nothing (26.7 against 27.3),
    both off at once, upstream's upload path, gives 21.1% and 8.3%, against 18.6% and 9.8% for Hyprland 0.56.2
    measured the same way: the second texture only costs when the rectangles are not merged, since the strips cover
    the stale damage anyway. On the Chromebook (Bay Trail, crocus, also the tiled copy, 2 slow cores) the merging
    halves the cost, 25.5% at 49 fps against 52.6% at 34 fps, and one texture changes nothing (25.4 against 25.0), so
    what decides is the per-call cost against the copy, not the GPU generation. The other 6 points on the Mac mini
    come from the session's history: after about eight workloads of the benchmark's list the sprites cost 32.5%
    instead of 26.7% and stay there (reproduced from the full list today, exactly the overnight figure; Hyprland
    0.56.2 gains 1.7 the same way), with the same profile and the same instructions (2.68 against 2.80 G in 8 s) at
    24% fewer per cycle and 20% more cache misses: the copies got slower, which memory is open. Not a leftover window
    or process, not a pending capture frame or the work-buffer path (the Chromium, nautilus and workspace-switch
    workloads and a grim capture each alone before the sprites leave it at 26.8 to 27.1). The merging stays on for
    every crocus: its loss on the Mac mini is small, its gain on the Chromebook and the X200 large. Scripts and
    numbers: `test-results/macmini-sprites-20261028/`.
    Since 2026-11-10 (branch `wip/coalesce-cost`) a frame's damage is merged on every driver, by a cost per rectangle
    (`Math::coalesceRegion()`: the cheapest of the rectangles as they are, horizontal strips and their bounding box, a
    rectangle costing as much as 64k pixels; `HYPOLAND_COALESCE_RECT_COST` sets it, `HYPOLAND_COALESCE_FRAME=off` and
    `=legacy` give the drawing no merging or 0.3.0's crocus/r600 gate, `HYPOLAND_COALESCE_DEBUG=1|frames` prints the
    choices), uploads keep crocus and r600 at 8k, and an element with 4 or more damage rectangles is drawn in one draw call
    over all of them (`CHyprOpenGLImpl::drawQuadInRegion()`, only for textures sampled at the nearest texel and solid
    rectangles: linear filtering in sub-triangles came out a step off at 1.6 and when magnified; `HYPOLAND_NO_BATCH_RECTS`,
    `HYPOLAND_BATCH_MIN_RECTS`). Qt's sprites on the XPS were 730 draw calls a frame (365 rectangles, two elements), 7
    now. Batching from one rectangle cost 2 to 9% more compositor CPU in workspace switching, `dev` and many windows on
    every machine (a vertex buffer uploaded per element, where a scissored draw of the quad the VAO holds is cheaper), hence
    the 4. master / batched from 1 / from 4, 11 to 14 fresh sessions of each on five machines (2026-11-10,
    `test-results/minb-20261110/summary.txt`; from 1 against merging off on ten in `test-results/batch-20261106/`): the
    sprites XPS 17.6 / 6.7 / 6.6% (Galaxy Book from 1: 14.1 -> 7.2), everything else within 1 to 3% of master (Chromebook
    workspace switch 5.73 / 6.09 / 5.90, X200 3.46 / 3.74 / 3.50), the `dev` typing latency Mac mini 10.5 / 8.9 / 8.8 ms,
    lianli 8.7 / 7.7 / 7.6. The render matrix passes (`render-matrix.sh --quick`, 7 of 7).
  - Mesa uploads a shm window into an idle tiled texture through a temporary of the window's size that it mallocs
    and frees per upload (`crocus_map_tiled_memcpy()` from Gen 5 on, `iris_map_tiled_memcpy()`; Gen 4 maps the
    texture directly, which is why the X200 gained from the idle second texture and Bay Trail lost). Upstream's
    `mallopt(M_TRIM_THRESHOLD, 6 pages)` gave that memory back to the kernel every time, and with huge pages off
    for the compositor the kernel faulted and cleared it in again 4 KiB at a time: on the Chromebook (crocus, Bay
    Trail) two thirds of the compositor's time under `qt-software-scroll`, 46.5% against 18.0% for stock, which has
    huge pages. Fixed 2026-10-27 (`CCompositor::setMallocThreshold()`, `CHyprOpenGLImpl::scheduleHeapTrim()`):
    freed memory stays up to 32 MiB and the heap is trimmed 5 s after the last upload, or 1 s after a shm window
    closes that was larger than any still updating (`untrackBackTexture()`; the windows left would keep the trim
    away: on the Chromebook a closed tiled foot gave 5.7 MiB back within a second while a small floating one kept
    printing). Chromebook
    `qt-software-scroll` 46.5% -> 15.5%, `gtk3-scroll` 54.4% -> 28.9%, `terminal-scroll` 21.9% -> 13.8%, Pss at
    the end of a run unchanged; lianli unchanged. Keeping huge pages on instead got half way (35.2% / 42.7%). The
    iris machines take the same path but do not pay for it: on the T550 (alternating r725 and master twice, fresh
    sessions, 2026-10-27) `gtk3-scroll`, `qt-software-scroll` and `qt-software-sprites` are 19.7% / 13.7% / 13.1%
    with both, the clients the same, idle Pss 44.4 against 44.8 MiB (heap 0.3 MiB more). A run right after a deploy
    check showed the clients 3 to 6 points higher: the check's leftovers in that session, not the build. Found with
    `profile.sh` (kernel `do_anonymous_page` under
    `CGLTexture::update`) and gdb with Arch's debuginfod for the Mesa frames.
    Since 2026-10-31 a destroyed surface schedules the same trim (`~CWLSurfaceResource()`): zero copy never uploads, so
    what closed windows had freed stayed in the heap (at the end of a run 14.3 -> 12.8 MiB on the T460s, 14.6 -> 13.1 on
    lianli, anonymous Pss 1.5 MiB lower; a nested session that opens and closes 40 foot windows twice ends below its
    start, so what the machines keep comes from the session's other work).
  - - The copy itself is the compositor's time under shm windows: profiles of 2026-10-28
    (`test-results/profile-20261028-*`) have Mesa's `linear_to_ytiled_faster` at 64 to 81% of the samples in
    `terminal-scroll`, `gtk3-scroll` and the sprites on iris (T550, XPS), libc's memcpy into Mesa's staging texture at
    70 to 80% on r600 and into the GTT mapping on the X200, all near memcpy speed. Fixed in two steps, see `HYPOLAND_SHM_TEXTURE` and
    `HYPOLAND_SHM_ZEROCOPY` under Tools below: a linear buffer of our own as the texture's storage, filled by the
    compositor's own row copy, and no copy at all for the clients whose pools can be pinned. The first experiment
    (2026-10-28, GBM buffers, Mesa's upload into them, two fresh sessions each) already gave `gtk3-scroll` T550 19.6 ->
    12.6%, XPS 25.6 -> 17.2, Chromebook 26.5 -> 14.9, Mac mini 27.4 -> 10.2, lianli 27.3 -> 22.7, `terminal-scroll` T550
    11.0 -> 7.9, XPS 24.7 -> 15.8, Mac mini 20.7 -> 10.8, X-tiled as good on iris and little on crocus, and one loss, the
    XPS sprites 16.5 -> 24.1%: into an imported buffer every small `glTexSubImage2D` has Mesa query and wait on the
    buffer and clear through blorp, hundreds of ioctls a frame (`test-results/profile-20261028-144044`), hence the row
    copy. Not done: `CSHMPool::resize()` with `mremap`
    changed nothing in `resize` (XPS 34.1 -> 34.2%, X200 and lianli the same): foot never resizes a pool, it creates a
    128 MiB pool per buffer and destroys the old one, so the kernel's share of that profile is the mapping and unmapping
    of those pools.
  - The rest of it was pixman: 97% of its samples came from the `wl_surface.damage` / `damage_buffer` requests, each
    unioned into the pending region on arrival (`addSafeDamage()`), the square of the number of rectangles. They are
    collected and made into the region once at commit now (`flushDamage()`, `pixman_region32_init_rects()`), the
    same region. `qt-software-sprites`: X200 31.6% -> 19.4% (59.9 fps), XPS 29.6% -> 24.2%, T550 and Galaxy Book
    unchanged within noise; X200 `gtk3-scroll` and `gtk4-scroll` 0.5 to 1 point lower. `gpu-client` on the Galaxy
    Book varies by 1.5 points between runs (rounds 3.5 to 5.8%), do not read a change there.
  - CPU time on the Galaxy Book measures cache warmth as much as work (2026-10-28, from the overnight A/B of
    2026-10-27, where its GTK 4 and Qt Quick clients cost 3.5 to 20% under Hypoland and a steady 3.5% under Hyprland
    0.56.2 at the same 119 fps). A slow client start runs the same instructions at the same 3.3 GHz with a quarter
    of the instructions per cycle: every L1 miss also misses the L2 and three quarters of the cycles are instruction
    fetch stalls. The slow or fast mode is set per client start by the core the scheduler picks: the Snapdragon's
    three clusters of four cores sleep (`cpu-sleep-0`, the deep idle state) between the frames of a 120 Hz client,
    and a cluster nothing else wakes loses its caches, so a client placed there refetches its working set every
    frame. With the deep idle states disabled every start is fast (2.5% CPU, IPC 3.3), not THP, ASLR, frequency,
    buffer modifiers or the protocol traffic, which are identical in both modes. Stock Hyprland never shows it
    because its two extra threads keep all three clusters half awake (720 context switches a second against 590,
    32 migrations a second against 2); under Hypoland the third cluster sleeps. The compositor pays the same way: with
    the GTK 4 client running it executes the same 0.22 G instructions in 4 s at IPC 0.74 (2.3% CPU) with deep idle
    on and IPC 1.64 (1.1%) with it off, which is where the Galaxy Book's `workspace-switch` 3.4 -> 4.5 against stock
    comes from. Not a Hypoland bug: the kernel's placement and idle choices on a machine whose compositor wakes
    less. Scripts and raw numbers of the experiments: `test-results/galaxybook-cold-caches-20261028/`.
  - GTK 3 costs the X200 about twice what GTK 4 does (19.2% / 11.0%, both cairo into shm) because GTK 3 damages the
    whole window on every frame, GTK 4 only the text column that changes (`WAYLAND_DEBUG`: 1576x850 against
    about 470x850). The client's doing, not the compositor's. GTK 3 also sends `set_window_geometry` with every
    commit, the window ignores an unchanged one.
  - The border damage while windows animate (`CHyprBorderDecoration::damageEntire()`, region math per tick) is
    still 4.2% of the compositor's time in workspace switching on the EliteBook, about 0.35 points of CPU.
  - `dev` on r725 (2026-10-25, 3 rounds; latency median / 90th percentile in ms, 12 focus changes, 18 scrolls,
    12 jumps and 39 typed keys per round, no timeouts):

    | | CPU | focus | scroll | jump | type |
    |---|---|---|---|---|---|
    | X200 | 5.2% | 6.3 / 15.9 | 63.8 / 73.6 | 42.1 / 50.6 | 7.4 / 16.2 |
    | T550 | 4.1% | 11.0 / 21.8 | 26.5 / 37.3 | 15.7 / 29.7 | 8.2 / 18.0 |
    | XPS (3200x1800) | 4.9% | 9.6 / 20.0 | 34.4 / 56.4 | 21.3 / 36.8 | 12.0 / 18.2 |
    | EliteBook | 4.1% | 12.2 / 18.3 | 25.4 / 36.3 | 16.4 / 35.6 | 9.3 / 17.7 |
    | lianli | 4.3% | 8.1 / 20.5 | 26.7 / 36.3 | 17.2 / 29.5 | 9.1 / 18.2 |
    | Galaxy Book (120 Hz) | 5.5% | 8.9 / 13.0 | 16.4 / 19.0 | 13.0 / 17.9 | 7.3 / 10.2 |

    What the compositor alone does (`focus`) and a key echoed by the shell (`type`) take under a frame at the median
    everywhere. Scrolling is nvim and Alacritty redrawing the editor: about one and a half frames at 60 Hz, two on
    the XPS and the Galaxy Book, almost four on the X200 (64 ms). The compositor's CPU time is about the same on
    every machine, the clients make the difference.
- Startup, launch and many windows (added 2026-10-30, asked for by the user for the numbers of Hypoland 0.3.0 against
  Hyprland 0.57.0). `startup` (`clients/startup.py`, root, not in the default list: it restarts SDDM, and the rest of
  the list then runs in the new session; alone with `--rounds` for several starts) follows a fresh session from the
  start of the compositor process: `startup.ipc_ms` until IPC answers, `first_frame_ms` until its first page flip,
  `wallpaper_ms` and `bar_ms` until the shell's layers are there, `desktop_ms` until the startup cover Omarchy r7438
  keeps over the screen (an overlay layer named like the wallpaper) is gone, `cpu_ms` (the compositor with its ended
  threads) and `session_cpu_ms` (uwsm's `wayland-wm@` service: the compositor, the shell, Xwayland) 20 s after the
  start, and `mem.startup.*` then; `exec_ms` is SDDM's start until the process, the same for any compositor. The session
  is ended the way abnight.sh does it (SDDM stopped, the old compositor gone, the session targets stopped): a plain
  restart under Hyprland 0.57.0 left SDDM's greeter, its session not ending in time and the new login failing to take
  the VT. The compositor followed is the process that holds the instance lock, stock 0.57.0 starts a short-lived one of
  the same name first. `launch` (`clients/launch.py`, root) opens Omarchy's terminal with SUPER+RETURN on an empty
  workspace (5 to 9) and closes it with SUPER+W, eight times after one that is not counted: `latency.launch.open_ms` /
  `close_ms` until the middle of the screen first changes, `opened_ms` / `closed_ms` until it stays (animation over,
  terminal drawn); opening is mostly the terminal's own start. `many-windows` puts 10, 20 and 40 foot windows, each
  printing five lines a second, in an even floating grid (5x2, 5x4, 8x5: dwindle would leave the last ones a few pixels
  wide) and measures each count like a workload (`cpu.many-windows-<n>.*` with `ms_per_frame`, `mem.many-windows-<n>.*`)
  and its focus and workspace switch latency, with the printing paused (a printed line changed the switch's region
  first: -0.9 ms on the Galaxy Book). First run, T550, master 0c18b6755 (the 0.57 port), one round: IPC 416 ms, first
  frame 294 ms, bar 1.8 s, compositor 410 ms and session 19.4 s of CPU in the first 20 s (the shell and Omarchy's login
  scripts), 43.2 MiB Pss; Omarchy's terminal (foot there) opens in 140 ms, drawn at 282, closes in 5.5; with 10 / 20 /
  40 windows the compositor takes 3.1 / 8.0 / 13.3% (1.15 / 1.39 / 2.22 ms a frame), Pss 44.6 / 46.1 / 48.5 MiB, a focus
  move 10 / 9 / 9 ms. Galaxy Book, Hypoland r871 against Hyprland 0.57.0-2 (2026-10-31, the median of 2 fresh sessions
  each): IPC 262 / 425 ms, first frame 197 / 223, bar 606 / 781, desktop 2366 / 2541, compositor CPU in the first 20 s
  350 / 920 ms with 227 / 1423 page flips, Pss then 44.9 / 151 MiB, the terminal 117 / 123 ms to open, 345 / 378 drawn;
  40 windows 5.4% (1.0 ms a frame at 120 Hz); Mac mini: IPC 407, first frame 307, bar 2.1 s, 40 windows 14.6% (2.44 ms).
  `bench.sh --compare` treats `startup.*_ms` like latencies with a noise floor of 30 ms.
- `./bench.sh --energy <label>` measures energy instead of speed (added 2026-09-28, after omacom/ttfx#46): the
  power the machine draws under each workload, net of an idle baseline taken before and after it (`power.*.net_W`,
  `energy.*.net_J`, with the drift of the baseline as `pm_W`), the idle session itself (`power.baseline.W`) and
  the instructions and cycles of the compositor from `perf stat` (`perf.*.Minstructions`, within about 1% from
  run to run, the steadiest figure to compare builds by). The governor is left alone, energy depends on it.
  The meter is RAPL where the CPU has it (the desktop: AMD package counter, root only) and otherwise the battery's
  discharge rate, which covers the whole machine including the screen and reads only on battery. The X200 has no
  RAPL, so it has to run unplugged: its battery showed 26%, 7.3 V (design 11.1 V) and `Not charging` on the
  charger, check it before trusting it with a run. The run stops below `--min-battery` (30%) and when the charger
  is plugged in, since a flat battery means a reboot and the disk password. `--meter none` only counts
  instructions and cycles and works on the charger. First run with a real meter on 2026-11-12: seven machines have a
  RAPL package zone (the T550, XPS, Chromebook, Mac mini 2014, T460s, T490 and samsung-i5; not the X200, lianli, the
  Galaxy Book or macmini-m1), and on the T550 the idle baselines before and after a workload agreed to 0.02 W (3.0 W).
  Where RAPL has a platform zone (`psys`: the T460s and T490) the same figures come for the whole machine as well
  (`power.*.psys_W`, `psys_net_W`, `power.baseline.psys_W`; T460s idle 1.8 W, the GPU client 7.0 W, against 0.6 and 2.9
  for the package); it counts a charging battery too, which the lab's batteries, always on AC and full or at their
  limit, do not. The 0.3 W noise floor of `--compare` for power is still a guess. An A/B against Hyprland 0.57.1 that
  day (`test-results/energy-20261112/`, alternating fresh sessions, the `balanced` profile Omarchy uses on battery)
  leaves out the workloads whose client does more work under a faster compositor (the terminals' print loops, the
  games).
