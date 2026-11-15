# Comparisons with stock Hyprland

Engineering notes of Hypoland, moved out of `AGENTS.md` on 2026-11-12 unchanged. `AGENTS.md` has the rules and
the current state; the notes say what was tried, measured and dropped. Add new findings here, with the date.

The baselines and A/B nights, oldest first. The raw values are in `docs/baseline/` and `test-results/`.

- Baseline failure of stock Hyprland 0.56.2 is saved in `docs/baseline/stock-hyprland-0.56.2-crash.txt`:
  `eglCreateContext failed with both GLES 3.2 and GLES 3.0` (EGL_BAD_MATCH), then an assert in
  `CHyprOpenGLImpl::CHyprOpenGLImpl()`. Aquamarine's own `CDRMRenderer` also wants GLES 3, but that is
  only needed for multi-GPU and its failure is non-fatal.
- Comparisons with stock Hyprland 0.56.2 (2026-10-22, Omarchy config, medians of 3 alternating rounds, raw data and
  scripts included): `docs/baseline/x200-vs-stock-hyprland-0.56.2-pr14764/` (started on the X200 with Omarchy's
  GLES 3 override, omacom/omarchy#14764) and `docs/baseline/t550-vs-stock-hyprland-0.56.2/`. Hypoland uses
  25-64% less compositor CPU under load on the X200, 10-55% on the T550, and about 60% less Pss on both, with
  the same frames.
- The regression baseline is `docs/baseline/20261027-all-machines-r761-vs-hyprland-0.56.2/` (the night of 2026-10-27
  to 28): every workload on all eight machines, Hypoland r761 (the compositor code of master 46ccda03f) against
  Hyprland 0.56.2-4, 37 to 41 fresh sessions of each per machine in alternating blocks (`abnight.sh` there, the runner
  the A/B nights use), medians with min and max per machine and compositor, every block's values, the table and the
  scripts. Its README says how to compare a build against it. Hypoland's compositor costs less in nearly every
  workload (workspace switching about half, shm windows a half to a third where the uploads were the limit), 43 to
  45 MiB Pss against 112 to 117 (145 on the Galaxy Book), shows a focus change, a resize step or a menu close one to
  two frames earlier on iris and freedreno, and on the X200 shows 42 to 60 fps where Hyprland 0.56.2 shows 30. Behind Hyprland 0.56.2:
  `qt-software-sprites` on the Mac mini (20.3% -> 32.5%, Haswell `crocus`, with the damage merging; not
  investigated) and the Galaxy Book (21.5 -> 25.6), the Galaxy Book's workspace switch and menu by about a point,
  its GTK 4 client (Vulkan) at 3.5 to 20% against a steady 3.5% with the compositor the same, the X200's `resize` at
  twice the frames, and a focus change 0.3 to 1 ms slower on the crocus machines.
- The baseline against Hyprland 0.57.0 is `docs/baseline/20261030-all-machines-r871-vs-hyprland-0.57.0/` (the night of
  2026-10-30 to 31, made the same way): Hypoland r871 (master a3911009c, the 0.57.0 port with the zero-copy flush fix)
  against Hyprland 0.57.0-2 on the same eight machines (not the T490), 10 to 12 fresh sessions of each, every workload
  with `launch` and `many-windows` (not `startup`), `raw.txt` with every block's values. Hyprland 0.57.0 runs with
  `quirks:skip_non_kms_dmabuf_formats = false`: its default broke the T550's session under Omarchy r7438 (no wallpaper,
  no EGL config with alpha). Hypoland costs less compositor CPU in nearly every workload (shm windows a fifth to a tenth
  of Hyprland's with zero copy: `terminal-scroll` T550 11.9 -> 2.9%, XPS 22.5 -> 3.1), 40 to 44 MiB Pss at the start
  against 113 to 116 (149 on the Galaxy Book), 46 to 54 at the end against 114 to 154, has Omarchy's terminal open and
  drawn 34 to 150 ms sooner, and shows more frames on the X200 in most workloads (`resize` and the sprites 60 against
  30). Behind it that night: a focus change among many windows and many windows' CPU on the X200 (both fixed the next
  morning, see the animation tick and `HYPOLAND_SHM_ZEROCOPY` under Tools), a toast on the T550 and the T460s (bimodal
  in every build since r761, open), the terminal closing on the Mac mini (8 against 4 ms) and the Chromebook, kitty's
  frames on the Chromebook (15 against 22 fps), the Galaxy Book's workspace switch and menu as before. Hyprland 0.57.0
  died five times without a core dump, killed by a signal (start-hyprland's `Couldn't waitpid for hyprland: No child
  processes` is how its wait loop reports that), Hypoland once (the X200, at the end of `dev`), and three Hypoland sessions
  of the XPS the next morning: the kernel's realtime watchdog, see "Realtime and its guard" under Tools.
  The night of 2026-10-31 to 11-01 repeated it with r896 (the morning's fixes) on nine machines, samsung-i5 included, 25 to
  31 blocks of each (`test-results/night-20261031/`, `table.txt`; not a baseline directory): the same picture, and stock
  Hyprland 0.57.0 hung on the X200 twice, blocked on a dead Xwayland (see the Xwayland paragraph further down; its blocks
  21 and 28 are left out). Behind Hyprland 0.57.0 that night: the terminal closing on the crocus machines (fixed the next
  day by the snapshot buffers, see the fade under Tools), the Galaxy Book's workspace switch and menu as before, and a
  toast, by half a frame on samsung-i5 (Ivy Bridge, every block: 35.5 against 29 ms) and the T550 (28 against 21). Not
  the alpha bounds, the work buffer, zero copy, realtime or its guard (each switched off on samsung-i5, 3 fresh sessions
  each). A timeline of the shell's socket calls, the compositor's and the GPU requests (`test-results/toast-20261101/`,
  `toasttrace.sh`, `toastgpu.py`): under Hypoland the shell commits its first toast frame 5 ms after the D-Bus message
  with its GPU work still running, and the compositor submits a frame with it 5 ms later, whose GPU work then waits for
  the shell's, misses the next vblank and flips at the one after; under Hyprland the shell renders only after the frame
  callbacks of the frame before (at 12.5 ms), and the compositor picks it up at a vblank. Read with the GPU requests
  (`toastgpu.py`): Hypoland's frame 5 ms after the shell's commit is not the toast's (one of the shell's commits that
  waits for no fence applied at once and was drawn as soon as nothing was pending), it takes the swapchain's one pending
  flip, finishes on the GPU behind the shell's work after the next vblank, and the toast's own frame, ready at 23 ms,
  waits for that flip at the vblank after (34 ms); Hyprland draws at vblanks only, so its first frame after the shell's
  buffer is ready has the toast. So it is drawing as soon as damage comes, which shows a single surface's update sooner
  everywhere else, against a client whose commits arrive in parts, one waiting for its GPU work. Open; the fence fix of
  2026-11-01 did not change it (36 ms, 3 fresh sessions), nor did the GPU's lowest clock pinned at its highest for both
  compositors (2026-11-02, 13 fresh sessions each, `test-results/toast-20261102/`: samsung-i5 35.5 against 29.5 ms, the
  T550 28.8 against 19.3), so it is not stock's capture waking the GPU up either.
  An experiment against it, `HYPOLAND_FENCE_HOLD` (taken out again), is under Tools.
  The night of 2026-11-01 to 02 repeated it with r919 (the fixes of 11-01) on eight machines, 28 to 33 blocks of each
  (`test-results/night-20261101/`, `table.txt`; the Galaxy Book hung at 01:22, see `MACHINES.md`): Hypoland less compositor
  CPU per frame in every workload on every machine, 39.6 to 42.1 MiB Pss at the start against 112 to 116. Stock Hyprland
  0.57.0 died in 13 blocks (the XPS 7, in `resize` and `launch`, the Chromebook 2, the T550 1, the X200 3 in
  `gtk3-x11-scroll`), Hypoland in none; those blocks are left out (`<host>.skip`). Against r896: the Qt software sprites at
  half the CPU or less (X200 24.2 -> 9.6%, Chromebook 27.3 -> 12.6), Omarchy's terminal closing in a third to two thirds of
  the time (XPS 10.2 -> 3.2 ms, X200 9.9 -> 4.7), kitty on the Chromebook at 22.5 instead of 15.6 fps. Behind stock: the
  toast above (T550, samsung-i5, lianli, the Chromebook, the T460s), the Chromebook's focus change under `dev` (5.1 against
  8.1 ms, the night before too), the Mac mini's resize redraw (the alpha bounds) and the XPS's menu (bimodal).
  Before 0.3.0 (2026-11-02 evening to 11-03 morning, `test-results/ab-20261102-rc/` and `test-results/night-20261102-rc/`,
  `summary.txt` in each): r919 against the release candidate in alternating fresh sessions on seven machines, 8 to 10 blocks
  of each, then the candidate against Hyprland 0.57.0 on six, 15 to 16 blocks of each, and a 13-hour soak on the T490. No
  regression: against r919 only `launch.closed_ms` changed (85 to 142 ms instead of 3 to 9, foot's contents fade out since
  84d62b4ad instead of vanishing; against stock, which drops them at once, it is not comparable) and the Galaxy Book's
  `launch.close_ms` (8.7 -> 11.0 ms, the closing snapshot draws the whole window now; stock 11.4); against stock the same
  places as with r919 (the toast, the Chromebook's `dev` focus). Hypoland passed every session check, stock failed 2 to
  55, the Chromebook's two being the viewport rim and the opaque region with a hole fixed here; stock died in five
  blocks, Hypoland in none. A crash at the end of a session on lianli (no mouse) was found and fixed that evening
  (b0bd1941a: without a pointer device the seat refused to clear a closed window's pointer focus and kept listening to
  its surface, which the last frame's render pass held until the renderer went, after the input manager; upstream's
  too), and none came back in 36 session ends; the soak held its Pss within 0.6 MB over its last eleven hours. The X200
  and the Mac mini could not be reached that night. The Galaxy Book ran the first candidate against stock, 16 blocks of
  each, until its UFS storage stopped at 06:33 (rpmh timeouts in the controller's resume, not the GPU); after the user's
  power cycle the final master passed its session check there (98 of 98).
  The released 0.3.0 against Hyprland 0.57.0-4 is `docs/baseline/20261103-all-machines-0.3.0-vs-hyprland-0.57.0/` (2026-11-03
  12:46 to 11-04 07:30, ten machines with samsung-i5 and the T490, 31 to 37 fresh sessions of each, the Galaxy Book 2:
  its GPU hung at a Chromium start in its third Hypoland block); the lab page (`scripts/web/lab.py`) used it until 2026-11-11. Hypoland
  less compositor CPU in nearly every workload on every machine, 40 to 43 MiB Pss at the start against 113 to 116 (148),
  every session check passed (stock failed 2 to 56); no compositor died. Behind stock: the toast as before, the X200's
  `resize` (more frames) and the Galaxy Book's workspace switch, menu and Chromium window from its two sessions.
  Master r957 (29b9f86a9: the measured direct scanout, merged frame damage, 10-bit buffers on the plane) against Hyprland
  0.57.1-2 is `docs/baseline/20261110-all-machines-r957-vs-hyprland-0.57.1/` (2026-11-10 23:09 to 11-11 07:30, eleven
  machines with macmini-m1, 8 to 10 fresh sessions of each, every workload with the games and ElectroBench; Omarchy-dev
  r7677 sets `HYPRLAND_NO_RT=1`, so both ran without realtime except on the Galaxy Book); the lab and terminals pages used
  it from 2026-11-11 to 11-13 (two nights since, below), without macmini-intel, which had no monitor that night (headless later blocks). No Hypoland
  compositor died; Hypoland passed every session check on ten machines, the M1's 31 render failures were Omarchy's pointer
  warp (fixed in the checks, c8c87f613). Hypoland's compositor costs less per frame in 15 to 41 workloads a machine and
  more in none of the comparable ones except: the M1's Qt software sprites (80 against 70% at 39 against 55 fps: the second
  shm texture, see `HYPOLAND_SINGLE_TEXTURE` under Tools, fixed for asahi), the Galaxy Book's menu, lianli's ElectroBench
  (0.05 to 0.08 ms a frame); and the T490 shows Velocitty at 28 against 34 frames a second with the client's CPU the same,
  only there (zero copy is not it, open). The next morning the deploy check of `port/0.57.2` on macmini-intel found a
  crash of master too: a monitor that connects while a screen capture is pending (the KVM's HDMI coming up during the
  check's screencopy) made its framebuffers at 0x0 in `CScreenshareManager::onOutputCommit()`, which asserted; it takes
  only allocated resources now (`CMonitor::allocatedResources()`, a31250872, hyprtester `monitorConnectsWhileCaptured`).
  The night of 2026-11-11 to 12 repeated it with master r966 (with the game workloads) on all eleven machines, 13 to 18
  fresh sessions of each (`docs/baseline/20261111-all-machines-r966-vs-hyprland-0.57.1/`, which the files page used from 2026-11-12 and
  the web pages take Hyprland's numbers from since 2026-11-13; `test-results/night-20261111/summary.txt`;
  macmini-m1 ran r967, r966 with the dmabuf fix below): Hypoland's compositor cheaper a frame in 23 to 45 workloads a machine and dearer in six
  (the Galaxy Book's menu, Flea and Xonotic, the Mac mini 2014's vkmark and Xonotic at its highest effects), the games
  drawing as fast or faster (vkmark samsung-i5 235 against 364, Mac mini 2014 447 against 759, Galaxy Book 2652 against
  3721), every session check passed on ten machines. It found the two direct scanout bugs fixed the next morning (fullscreen
  games, under Tools). On the X200 Hypoland's GPU context hung three times in 6 s at 03:25 (`dev`, i915 "GPU HANG ... in
  hypoland") and crocus aborted it in the frame's `glFlush()` once the kernel had banned the client
  (`CHyprGLRenderer::endRender()`; crocus' `replace_hw_ctx()` fails then): its first in 13 blocks that night and none in
  r957's night, while the X200's GPU also hung in Xwayland (twice under stock, which then hung both times, once under
  Hypoland) and in Xonotic; open. The i915 error state (`/sys/class/drm/card1/error`) keeps the first hang until it is
  cleared (`echo 1 >` it), and held a day-old Xwayland hang then.
  The night of 2026-11-12 to 13 ran master r991 (e5a1c2d8e: after the dead code and effects removal, with the centred
  small fullscreen surface) alone on all eleven, realtime off (`HYPRLAND_NO_RT=1`, as Omarchy sets it) against on, 8 to
  12 fresh sessions of each (`docs/baseline/20261112-all-machines-r991-realtime-off-vs-on/`, its README has the
  realtime results). Since 2026-11-13 the web pages take Hypoland's numbers from its realtime-off sessions (the Galaxy
  Book's realtime-on ones, as Hyprland ran there) against Hyprland's of the night before: two nights in a row with the
  same packages but Folio, so Folio stays on the r966 night and the Mac mini 2014 (headless in one, on its monitor in
  the other) is left out. Against r966 of the night before, r991's memory is lower on every machine (Pss and Rss, the
  binary smaller) and the rest about the same; no compositor died, every check passed but `render fullscreen smaller
  rectangles` on the XPS and the Galaxy Book (scale 2), a regression of e5a1c2d8e fixed on `wip/rt-fixes` (r992).
  The night of 2026-11-14 to 15 ran master r992 (92942ceba) against Hyprland 0.57.2-2 on twelve machines, the new
  ThinkPad P14s Gen 2a (radeonsi, 4K at scale 2) among them, 14 to 22 fresh sessions of each
  (`docs/baseline/20261114-all-machines-r992-vs-hyprland-0.57.2/`, which the web pages take their numbers from since
  2026-11-15, Nautilus's from the r966 night: Omarchy's update of 2026-11-13 removed Nautilus; `test-results/night-20261114/summary.txt`).
  The new hp-amd (A6-7310, radeonsi) gave no numbers: its GPU hung under GravityMark 20 minutes in. Hypoland's compositor
  cheaper a frame in 24 to 43 workloads a machine and dearer in three, all on the Galaxy Book (the menu, Flea and GTK 3
  scrolling); 40 to 57 MiB Pss at the start against 115 to 145; every session check passed, Hyprland's failed 4 to 60;
  no compositor crash of Hypoland (Hyprland hit a GPU hang on the X200). Against r966 most changes moved Hyprland too (the
  Mac mini 2014 on its monitor now, Omarchy's update); Hypoland's alone: lianli's workspace switch, 7 to 10 ms in about
  half the sessions against 2 before and under Hyprland, open.
