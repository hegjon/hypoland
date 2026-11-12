# Fullscreen games and the measured direct scanout

Engineering notes of Hypoland, moved out of `AGENTS.md` on 2026-11-12 unchanged. `AGENTS.md` has the rules and
the current state; the notes say what was tried, measured and dropped. Add new findings here, with the date.

`xwayland:legacy_fullscreen` and `CScanoutAuto`.

- Fullscreen games (2026-11-09, `test-results/games-20261109/`, after the user saw Omarchy's bar over the games above).
  GravityMark's fullscreen is an X11 window it places itself: override-redirect, the monitor's size, `_MOTIF_WM_HINTS`
  without decorations and no `_NET_WM_STATE_FULLSCREEN`, so it was a floating window under the top layer, the bar over it
  (stock Hyprland the same). `xwayland:legacy_fullscreen` (on by default) makes such a window fullscreen when it maps: no
  decorations by its Motif hints, the normal window type, no parent, not transient or modal, and exactly an enabled
  monitor's box to within a pixel (`CX11Backend::isLegacyFullscreen()`, computed in `updateTraits()` only, since the traits
  are read every frame; hyprtester `legacyFullscreen` with `hyprtester/clients/legacy-fullscreen.cpp`, an xcb client).
  0.3.0 against it, one round on the machines: the same frame rates, the compositor's CPU a frame 3 to 11% lower, the bar
  hidden. `render:direct_scanout` is auto (2) by default since then, with auto redefined: upstream's scans out only windows
  whose content type is game, which neither game sets; Hypoland's measures each fullscreen window both ways and keeps the
  better (`CScanoutAuto` in `src/output/ScanoutAuto.*`, pure logic fed times by `CMonitor::updateScanoutAuto()` once a frame
  and by the output's commits; 22 unit tests in `tests/output/ScanoutAuto.cpp` run it against simulated clients, the
  machines' cases among them). Which way is better is not known beforehand. Scanned out, a client without vsync that draws
  faster than the screen runs short of buffers: Mesa's EGL waits for a free one with `wl_display.sync` round trips (102908
  syncs for 1656 commits on the T550), the compositor's context switches go up thirty times and its CPU twice, and with `on`
  (1) Xonotic low drew 131 instead of 170 fps on the T550, 138 instead of 205 on the T460s and 455 instead of 700 on the
  Galaxy Book; a client held to about the refresh rate that way (Galaxy Book ultimate: 121 instead of 135) cannot be told
  from one that draws at it anyway, which is what the first auto (a rate threshold, r947 to r951 of `wip/legacy-fullscreen`,
  on master as d3d0933e0) got wrong. And a GPU-bound game gains on the plane (Xonotic ultimate 2 to 8% more frames and none
  dropped on the way to the screen: Mac mini 28 -> 50 shown, samsung-i5 11.8 -> 18.2), while the X200 at low draws 77 to 80
  fps either way but the GM45 composites only 27 of them a second and shows 48 to 52 scanned out. So the choice measures
  the frames the screen shows first (the window's new buffers that an output commit went out after, counted by the
  window's commits: by buffer object, a client cycling three or four buffers faster than the refresh rate had the same one
  current at two frames in a row, and vkcube read 32 to 41 instead of 60 nested) and the frames the client draws second,
  each over a second after half a second to settle (the client reallocates for the other formats); shown at 90% of the
  refresh rate or more either way counts as equal, so the client's rate decides (the Galaxy Book showed Xonotic low at 113
  composited and 120 scanned out, at a third fewer of its frames). A window shown at about every refresh composited while
  it draws faster than that is not tried on the plane at all (the measurement cost the Galaxy Book a tenth of the frames of
  a 12 s run). The other way is measured again after 15 s, doubled up to 240 s; a scanned-out window only when it draws
  near the refresh rate (below it, it cannot be short of buffers); and at once when the screen shows the window at a fifth
  more or less than when it chose (a game's loading screen, then its play: measured composited first, where it is, then
  scanned out; two measurements more than twice apart in drawn rate are of other scenes and taken again after a second).
  A plane that refuses the buffers for a second and four buffers leaves it composited until the next try. With scanout on by
  default the X200 aborted in every session a few seconds into the fullscreen `video` workload (`fsab/`, 8 of 8 sessions of
  auto and of the first auto): the output takes the format of the buffer it scans out, mpv's 10-bit XRGB2101010, and the
  frames composited after it allocated what they render into in that format, which GLES 2 cannot render into. Until
  2026-11-10 such buffers were kept off the plane, which cost the fullscreen video wherever the plane takes them; since then
  what is rendered into keeps a format the renderer can render into, the output's format from before the scanout
  (`CMonitor::renderableFormat()`, for the swapchain in `updateSwapchain()`, the work buffers in `resources()` and the render
  buffer in `beginRender()`), and 10-bit buffers are scanned out again. The swapchain alone (r957) still aborted in 8 of 8
  sessions (work buffers allocated in XRGB2101010, `markMirrorFBStale()`); with all three (r958) none of 8 sessions of auto
  and on did, and the video cost 0.60 to 0.62 ms of compositor CPU a frame against 0.85 composited
  (`test-results/dscost-20261110/x200-10bit-*`). The T550, the Mac mini and the XPS refuse mpv's buffers on the plane
  anyway. On the Galaxy Book master with the block cost the fullscreen video 1.09 against 0.57 ms a frame of the build
  before (r954 against r951, 2 fresh sessions each, `test-results/gb-20261110/`; its GPU hung in the third block, 10:31),
  and the fix is not measured there yet. A buffer the plane
  refuses (KMS's test fails, after the settling and two buffers) ends the scanout measurement at once: every refused frame
  is tested in KMS again. The fullscreen handlers offer a fullscreen window the scanout formats as dmabuf feedback when it
  goes fullscreen, as the first auto did, and it keeps them unless it measured better composited (with them Intel clients
  take X-tiled over Y-tiled buffers and draw slower: the first auto lost 4 to 11% at low composited). Offering them only
  for the scanout measurement and taking them back otherwise (r950 to r962) cost the fullscreen `video` workload a third of
  its frames on the screen (T550 20 against 30 fps, XPS 26, Mac mini 22, `fsab/`): mpv reads the formats when it starts,
  its buffers were refused, and after the formats were taken back it drew 20 fps composited (r963 on the T550: off 30.0,
  on 30.1, auto 20.1; r964, which leaves a refused window its formats: 30.0). `HYPOLAND_SCANOUT_DEBUG=1` prints every change of the
  choice with its rates to stderr (the session's journal); `RATE`, "better composited", in `hyprctl monitors`' blocked
  reasons. Measured overnight (2026-11-09, `test-results/games-20261109/dsm/`, variants off / auto / old = master's auto,
  `VARIANTS=off,auto,old python3 ds3table.py dsm`, medians `python3 dsmsum.py dsm`, in `dsm/summary.txt`; the builds before
  r959 in `dsm-r1` to `dsm-r9`): r959 (`wip/ds-measure` 4/ec0293a95), 8 fresh sessions of each on six machines, game fps
  off / auto / old: Galaxy Book ultimate 135.5 / 134.9 / 119.4 (shown 114.9 / 116.4 / 102.8, the compositor 0.28 / 1.31 /
  1.88 ms a frame), low 714.6 / 694.2 / 709.0; X200 low shown 26.8 / 52.0 / 46.5, ultimate 3.2 / 5.7 / 5.7; Mac mini
  ultimate shown 28.9 / 45.9 / 47.2; samsung-i5 ultimate shown 11.8 / 18.2 / 18.2, low 101.3 / 98.1 / 99.5; T550 ultimate
  43.6 / 46.1 / 46.1, low 169.9 / 167.7 / 167.5; XPS ultimate 20.8 / 22.4 / 22.3, low 82.1 / 82.3 / 82.0; GravityMark the
  same everywhere, its compositor 30% cheaper a frame on the Galaxy Book. Where auto scans out a client that outruns the
  display because the screen shows more of it that way, the compositor pays for the client's busy wait (XPS low 2.33 ms a
  frame against 1.70 off, 1.90 old): a profile on samsung-i5 under `on` (`test-results/profile-20261109-195948`, against
  `-200123` off) has the kernel at 53% of the compositor's samples and libwayland-server at 10%, Mesa's `wl_display.sync`
  round trips answered, the drawing 15%; on the XPS about 8300 round trips a second, 3.6 ms of the compositor's CPU a frame on
  the plane against 1.7 composited, for 59 frames shown against 53. So since 2026-11-10 auto weighs that cost as well: each
  measurement takes the compositor's CPU time (`CLOCK_PROCESS_CPUTIME_ID`, Mesa's threads included) per frame shown; a plane
  that costs more than 1.5 times and 0.3 ms a frame more than composited (`COSTLIER`, `COSTLIER_MIN`) is chosen only when
  the screen shows 30% more frames on it (`WORTH_ITS_COST`: the X200's 48 against 27 passes, the XPS's 59 against 53 does
  not), a scanned-out window that grows that costly is measured again at once, and a window that measured better
  composited because the plane cost more (`m_pollsOnThePlane`) is tried on the plane at its retries only, not at every
  change of scene (Xonotic's demo changes scene every few seconds: without that, r956, the XPS kept 2.19 ms a frame). XPS
  low, 5 fresh sessions each (`test-results/dscost-20261110/`, `xps-r959`): 1.98 ms a frame (1.94 to 2.03) against 2.19 for
  master's auto (1.69 to 2.22) and 1.77 off, the screen 57.2 frames a second either way, the game 81.0 against 80.6;
  ultimate shown 22.4 against 20.8 off, as before. What is left over off is the one measurement on the plane within the
  benchmark's 12 s, whose retries double up to 240 s in a longer game. The X200, the T550, the Mac mini and samsung-i5 the
  same as master (3 rounds each of the rule's first version, r955): X200 low shown 51.6 against 51.8. The final build r964 (`dsm-r964/`, 4 fresh sessions each on the X200, T550, XPS and
  Mac mini, the games and `video`, `nautilus`, `flea`): the games as r959 (X200 low shown 52.0 / 46.8 old / 26.7 off, Mac
  mini ultimate 48.0 / 47.7 / 28.8), the fullscreen video at 30 fps on the screen everywhere with the compositor's CPU as
  with off, `nautilus` and `flea` unchanged, and master's first auto aborted the X200 in all 4 of its sessions.
  Tests (2026-11-10): hyprtester's `directScanout`, `directScanoutRefused`, `directScanoutFormat` and `directScanoutAuto`
  (`hyprtester/src/tests/clients/direct-scanout.cpp`) put a fullscreen window drawn in linear GBM buffers on the
  compositor's main device (`hyprtester/clients/dmabuf-fullscreen.cpp`, `--format xrgb8888|xrgb2101010|argb8888`, `--shrink`,
  `--transform`) on a headless output, which takes any buffer in a commit: on the plane and drawing, off it under a
  notification, a software cursor (headless outputs have no cursor plane, so the tests make the cursor invisible) and out of
  fullscreen, a grim screenshot of it while scanned out, closed on the plane, refused for a buffer a pixel small, one turned
  by 180 degrees and `direct_scanout = 0`, the output back in its own format after an ARGB8888 buffer, a 10-bit buffer
  scanned out, composited around it three times and the output back in its format out of fullscreen (`directScanout10Bit`;
  the X200's abort does not show nested, the test passes without its fix), and auto measuring composited first and
  choosing the plane for a client at the refresh rate. Without the format restore of `handleDSleave()` they fail. Not covered nested: what a KMS driver accepts, the scanout tranche of the
  dmabuf feedback (only made with a session) and mirrors (a mirror output cannot be removed again within the test).
  A window's formats do not change in the middle of a game (2026-11-12, `CScanoutAuto::wantsScanoutFormats()`): every
  change of a window's dmabuf feedback with other modifiers makes Mesa's Vulkan WSI report its swapchain suboptimal, and a
  game rebuilds it, SuperTuxKart freezing for about 2 s. Auto offered the scanout formats while it measured or chose the
  plane and took them back when it chose composited, so a game it switched between the two got them changed several times
  a race: in the night of 2026-11-11 (`HYPOLAND_SCANOUT_DEBUG` in the journal of four machines) the T460s's race was on the
  plane for 29 s, a scene measured better composited, the rebuild's stall looked like another scene and the plane came
  back, 42 instead of 38 s; the Galaxy Book's had four changes, the same to the second in every session, 44 s. Now the
  formats change at most twice for a window (`MAX_FORMAT_CHANGES`), a window on the plane by choice for 10 s keeps them
  (`KEEP_FORMATS`) and one measured better composited loses them only after 10 s composited (`WITHDRAW_FORMATS`), so a
  loading screen composited for a moment does not decide (that alone left one change at the Galaxy Book's race start and
  its Steady FPS 0). 3 fresh sessions each: the Galaxy Book's race 38.1 s, Steady / Mostly stable 60 / 113 and 141.6 fps
  (stock 53 / 102, 130.2), the T460s 38.2 s and 43.5 fps (stock 40.0), the X200 still shows Xonotic's lowest effects on the
  plane at 52 frames a second. Unit tests `gamePlayedOnThePlaneKeepsTheFormats`,
  `formatsAreTakenBackAndOfferedAgainOnceAtMost` and `loadingScreenCompositedForAMomentKeepsTheFormats`. And no scanout
  tranche at all where the outputs are not on the render device (`displayOnRenderDevice()` in `LinuxDMABUF.cpp`): the
  tranche names the render device with the planes' formats, and on macmini-m1 the display controller (apple-drm) is a
  device of its own next to the asahi GPU, whose render node aquamarine takes as the sole one; Mesa's Vulkan WSI ignores a
  tranche's target device and takes the first tranche listing the format, so SuperTuxKart's swapchain was made with the
  display's modifiers and failed, and Yamagi Quake II with Vulkan outran the display on the plane at 34.6% of the
  compositor's CPU (stock 4.7). Without the tranche (17 sessions of each that night): SuperTuxKart 263.9 fps (stock 253.0),
  Yamagi Quake II 632 fps as stock at 3.5%.
