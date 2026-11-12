# Renderer, input and scheduling work

Engineering notes of Hypoland, moved out of `AGENTS.md` on 2026-11-12 unchanged. `AGENTS.md` has the rules and
the current state; the notes say what was tried, measured and dropped. Add new findings here, with the date.

The switches in the compositor's environment, how each path works, what it gained and what was dropped.

Switches named below that no longer exist (removed on 2026-11-12, the paths they compared are decided):
`HYPOLAND_SHM_TEXTURE=linear-gl`, `HYPOLAND_SHM_TEXTURE_DEVICE`, `HYPOLAND_NO_COALESCE`, `HYPOLAND_COALESCE_FRAME`,
`HYPOLAND_COALESCE_RECT_COST`, `HYPOLAND_COALESCE_DEBUG`, `HYPOLAND_NO_BATCH_RECTS`, `HYPOLAND_BATCH_MIN_RECTS`.

- `HYPOLAND_NO_DIRECT_RENDER=1` makes every frame go through the work buffer, for comparing the two paths.
- `HYPOLAND_FENCE_HOLD=<ms>` (2026-11-02, an experiment, off by default; taken out again before 0.3.0, the code is
  commit b5222a9ee, its four source files to check out from there) held a frame while a client's commit on the
  monitor waits for the GPU to finish its buffer (`CMonitorFrameScheduler::holdForClients()`): such a frame queues on the
  GPU behind that client's work anyway, misses the vblank it was drawn for and holds the one flip that can be pending, so
  the frame with the client's update waits a refresh for it (the toast above). Held, the frame is drawn when the buffers
  that were waiting at its start are ready (`CSurfaceStateQueue::unlockFence()` tells the monitor), after `<ms>` at the
  latest; later commits do not extend it, and a frame without damage (the cursor on its plane) is not held.
  `HYPOLAND_FENCE_HOLD_DEBUG=1` prints every hold to stderr (T550, a notifications run: 38 holds, 3.9 ms median, all ended
  by the buffers). The toast with 17 ms, 8 fresh sessions each, off -> on: Mac mini 32.6 -> 16.9 ms (every block lower),
  T550 29.6 -> 22.4, T460s 21.5 -> 24.0 (overlapping); the compositor's CPU the same, 1 to 3% fewer frames on the screen.
  The other workloads, 8 fresh sessions each on the T550, the T460s, the Mac mini and the Chromebook (13 workloads,
  `test-results/hold-20261102/hold2/`; the toast alone is `hold1/`): a focus change under the `dev` load comes later with
  it (T550 3.0 -> 5.5 ms, T460s 3.3 -> 4.9, Chromebook 7.5 -> 9.3: the frame with the new border waits for the log
  terminal's buffer), the Chromebook's video window shows 24.0 instead of 26.6 frames a second in every block (its GPU
  busy 100 -> 90%: a frame held until the client's buffer is done no longer overlaps that work on the GPU), and the toast
  is bimodal per session in that run (Mac mini 13 to 14 ms in 3 blocks, 28 to 31 in 5, against 31 to 33); a resize step
  on the T460s 2.8 -> 1.4 ms, the rest within the spread. Both runs pooled, 16 sessions each, the toast: Mac mini 32.6 ->
  21.7 ms, T550 28.8 -> 25.0, T460s 21.5 -> 24.0. So it was not kept: it trades a toast's frame for a focus change's.
- `HYPOLAND_NO_COALESCE=1` uploads and draws the damage rectangles as the client sent them instead of merging them on
  crocus and r600 (`CHyprOpenGLImpl::coalesceDamage()`), `HYPOLAND_SINGLE_TEXTURE=1` updates the shown shm texture in
  place as upstream does instead of the idle second one (`CGLTexture::update()`), both for comparing the paths on a
  machine (2026-10-28). Since 2026-11-11 one texture is the default on asahi (`singleTexture()`, `=0` gives two): the
  driver pays per upload call there, mostly in the kernel, and the second texture's missed damage doubled the calls (the
  M1's Qt sprites 79 to 81% at 39 fps with two, 64% at 57 with one, 3 fresh sessions each; Hyprland 0.57.1 70% at 55).
  The dumb-buffer row copy (`HYPOLAND_SHM_TEXTURE=linear`) and zero copy (`HYPOLAND_SHM_ZEROCOPY=force`) cost 1.2 and
  2.6% there in one session each (`test-results/m1sprites-20261111/`, with a KVM re-enumerating on the M1's USB every
  9 s), not yet checked for stale pixels or render errors. Like `HYPOLAND_PROFILE_PASS` they have to reach the session environment (`~/.config/uwsm/env`).
- `HYPOLAND_SHM_TEXTURE` (2026-10-28/29): every synchronous (shm) texture gets a linear DRM dumb buffer of the
  compositor's own device as its storage, imported as an EGLImage (`CGLTexture::backWithBuffer()`, aquamarine's
  `CDRMDumbAllocator` on the primary node; a texture gets its buffer at its second update, the first stays on Mesa's
  storage so a one-shot texture costs nothing extra), and the compositor copies the damaged rows into the mapped buffer
  itself (`copyIntoBuffer()`, a 1x1 `glTexSubImage2D` afterwards so the driver knows the texture changed) instead of Mesa
  tiling every upload on the CPU. On by default on iris, crocus and r600, where it was measured (off -> on, two fresh
  sessions each, 2026-10-29: `gtk3-scroll` T550 19.7 -> 13.0%, XPS 21.7 -> 14.0, Chromebook 26.8 -> 17.7, Mac mini 28.1
  -> 11.3, lianli 27.4 -> 23.3, X200 18.1 -> 17.4, T460s 14.2 -> 14.0; `terminal-scroll` T550 11.4 -> 8.5, XPS 23.5 ->
  15.7, Chromebook 13.4 -> 8.7, Mac mini 19.9 -> 8.4, lianli 13.7 -> 11.8; `qt-software-sprites` lianli 25.8 -> 7.0, Mac
  mini 27.0 -> 6.6, Chromebook 25.5 -> 16.7 at 56 instead of 50 fps, X200 19.6 -> 11.1, T550 13.4 -> 10.1, XPS 25.9 ->
  23.0; `qt-software-scroll` 1 to 4 points lower except on the Chromebook; `resize`, idle Pss, heap, threads, frames and
  latencies the same) and on freedreno (Galaxy Book, 2 fresh sessions each: sprites 27.1 -> 17.2%, `terminal-scroll` 6.9
  -> 7.3 at 73 instead of 65 fps, GTK 3, `resize`, Pss and threads the same), off elsewhere. `0` or `off` switches it off, `linear` on,
  `linear-gl` keeps Mesa's upload into the buffer (into an imported buffer each `glTexSubImage2D` has Mesa query, wait
  and clear through blorp, hundreds of ioctls a frame: XPS sprites 24.1% against 16.5 off, `test-results/profile-20261028-144044`).
  Two versions before cost: GBM buffers of a separately opened device gave a second Mesa screen (+2.2 MiB Pss, 2 to 4
  threads) and a fresh GEM object per buffer, cleared by the kernel per resize commit (`resize` +2 to +9 points on Intel,
  54 fps on the X200 and XPS; the night of 2026-10-28, 30 to 33 fresh sessions each on seven machines,
  `test-results/abnight-20261028-shmtex/`), and `DMA_BUF_IOCTL_SYNC` calls around the copy made i915 flush the whole
  buffer from the caches twice per update on GM45 (X200 `gtk3-scroll` 18.5 -> 27.7%); the mapping is write-combining, so
  they are gone. Same way into the session environment (`~/.config/uwsm/env`).
- `HYPOLAND_SHM_ZEROCOPY` (2026-10-29): a wl_shm buffer whose pool is a memfd sealed against shrinking gets a udmabuf of
  its own pages (`/dev/udmabuf`, which logind's uaccess gives the seat's user) imported as a linear EGLImage and used as
  the texture, so nothing is copied (`CWLSHMBuffer::tryZeroCopy()`). The buffer is asynchronous like a dmabuf: the
  surface keeps it until the next one, the renderer until the frame that read it is done (`needsRenderFence()` fences for
  such a buffer on crocus too) and the client gets its release after that (foot: 276 releases for 279 commits in 8 s on
  lianli). foot and Qt's software backend seal their pools so; GTK 3 seals only against further seals (`gdk-wayland`, no
  zero copy there), GTK 4 (4.24) seals against shrinking as well, so its cairo buffers on the X200 take the path; GTK 4
  elsewhere, Chromium and Xwayland use GPU buffers on the test machines; clients close the pool fd after
  mapping, so read the seals from the compositor's `/proc/<pid>/fd` (`F_GET_SEALS`). On by default where GPU reads snoop
  the CPU caches, since the compositor cannot flush another process's writes: i915 with an LLC (`I915_PARAM_HAS_LLC`:
  iris, crocus from Sandy Bridge, not GM45 or Bay Trail) and r600 (there only for rows of a multiple of 64 pixels, see the
  render checks below); `0` switches it off, `force` ignores the gate.
  Since 2026-10-29 evening it is on without an LLC as well (GM45, Bay Trail): there the GPU reads memory and the compositor
  writes the client's damaged cache lines back itself at every commit (`CWLSHMBuffer::flushCPUWrites()`, `clflush`
  per 64 bytes of each damaged row, x86 only; `force` is zero copy without the flush and the screen shows specks of
  old glyphs on Bay Trail within seconds, `flush` the flush on any driver). Since 2026-10-30 it writes back the damage
  since the buffer's last commit, not only the commit's: a client that draws into several buffers in turn first repaints
  into the one it reuses what changed since that buffer was last shown (buffer age, foot's `reapply_old_damage`), and
  the next frame, which redraws the previous frame's damage from this buffer, read those lines stale from memory (the
  user saw old glyphs flash in foot on the X200 while omarchy-update printed its progress bars). `CCPUFlushTracker` keeps
  per surface the damage of its last 8 commits and when each of its last 8 buffers was last committed; a buffer new to
  the surface is written back whole (kernel-zeroed pages included), as is one back after more than 8 commits or after a
  size change, and a commit it does not see (a copied buffer, a dmabuf) resets it. A check for it:
  `scripts/machines/stale-check.sh` (copy it to the machine, run it as root) has foot rewrite random lines in place, stops the
  writer, captures the scanout, evicts the caches with 256 MB of writes, switches workspace away and back and captures
  again; differing window pixels are a stale frame. Before, 15 of 15 runs on the X200 (12 to 92 rows) and 4 of 15 on
  the Chromebook; after, 0 of 15 on both. Its cost (4 fresh sessions of each, X200 / Chromebook): `qt-software-sprites`
  5.6 -> 6.0% / 7.7 -> 8.1% of a CPU, since the previous frame's squares are written back too; `terminal-scroll` (per
  frame), `gtk4-scroll`, `resize-foot`, frames and memory the same. Against the dumb-buffer copy
  (`HYPOLAND_SHM_ZEROCOPY=0`, 2 fresh sessions each, compositor CPU): Chromebook `qt-software-scroll` 12.9 -> 4.1%,
  the sprites 14.0 -> 7.8, `terminal-scroll` 7.1 -> 5.4, `resize` 28.6 -> 22.9, `resize-foot` 37.1 -> 25.8; X200
  `qt-software-scroll` 9.8 -> 6.2, the sprites 11.7 -> 5.7, `terminal-scroll` 9.8 -> 9.7 (a full window's clflush costs
  the Core 2 what its row copy did), but `resize` 19.2 -> 20.8 and `resize-foot` 25.2 -> 28.0 (foot makes a pool and
  a buffer per resize step, each a udmabuf and an EGL import, which the GM45's driver pays more for than a new
  texture); GTK 3 unchanged (its pools cannot be pinned), frames and latencies the same, Pss 2 MB higher (the
  flush faults the clients' pool pages into the compositor's mapping). A client that painted into one buffer and got it
  back at once pays instead: the compositor holds the committed buffer until the next one, so GTK 4's cairo backend
  (the X200, where GTK 4 has no GL) paints the next frame into a second buffer with that buffer's stale region on top,
  and Nautilus toggling fullscreen twice a second (`nautilus`) costs 34.7% of a CPU against 30.2% with the copy
  (2026-10-30, 4 fresh sessions each, the compositor at 3.35% and the frames the same, the same pools made, 4.09 against
  3.73 s of user time per 10 s; `force`, zero copy without the flush, costs the client the same, the flush itself is 0.4
  points of the compositor). foot and Qt's software backend double-buffer anyway and cost the same or less (the night of
  2026-10-29, 31 fresh sessions each: Qt software clients 25.2 -> 24.3% on the X200). The i915 PMU's busy time is not to be read on
  GM45 or Bay Trail for shm windows: it shows 0% for a scrolling window in one session and 61% in another.
  Compositor CPU with the dumb buffers -> zero copy (2 fresh sessions each, 2026-10-29): `terminal-scroll` XPS 15.8 ->
  4.1%, T550 8.0 -> 3.6, T460s 8.0 -> 3.3, Mac mini 8.8 -> 4.5, lianli 11.8 -> 2.6; `qt-software-scroll` T550 10.2 ->
  3.7 and the sprites 10.1 -> 3.8 (Qt's pools qualify); `resize` XPS 33.6 -> 21.0, T550 17.2 -> 11.6, T460s 16.2 ->
  10.7, Mac mini 26.1 -> 13.9, lianli 17.6 -> 12.1 (`redrawn` 2 to 10 ms sooner); GTK 3, frames and Pss the same, GPU
  memory at the end of a run 20 MB lower on the XPS. Deploy checks pass with it on the XPS,
  T460s, Mac mini, lianli and T550; two scanout captures of a scrolling foot differ, so nothing is stale.
  Since 2026-10-31 the decision is made at a buffer's attach, per surface (`CWLSHMBuffer::onAttach()`,
  `CWLSurfaceResource::m_shmFresh`): foot scrolls by attaching a new `wl_buffer` further on in its pool for every line,
  so a printing terminal made a udmabuf and an EGL import per commit (6967 in two minutes of `many-windows` on the Galaxy
  Book with zero copy forced), which under many small windows cost more than copying them. A surface whose last eight
  attaches were mostly new buffers gets those below 1 MiB (256 kB on radeon, where a copy is a staging texture and a
  blit) copied; a copied buffer is sampled in place from a later attach once the surface reuses its buffers, never the
  other way (going back to copies uploads the whole buffer: a per-buffer rule, zero copy only from a buffer's second
  attach, lost for that reason, Chromebook `terminal-scroll` 5.4 -> 11.2%). Per frame with 10 / 20 / 40 windows of
  `many-windows` (5 to 8 fresh sessions each): X200 2.47 / 3.36 / 5.42 -> 1.44 / 1.99 / 3.22 ms (Hyprland 0.57.0: 1.91
  / 2.30 / 3.44), Chromebook 2.58 / 3.66 / 5.92 -> 1.96 / 2.88 / 4.82, Mac mini 1.10 / 1.54 / 2.52 -> 0.99 / 1.29 / 2.02,
  T460s 1.04 / 1.40 / 2.03 -> 0.98 / 1.34 / 1.81, lianli 2.46 -> 2.25 with 40; the rest of the benchmark and memory the
  same, a focus change among the windows 0.2 to 0.35 ms later. The write-back of GM45 and Bay Trail was not the cost:
  without it (`force`) the Chromebook paid the same and the X200 0.2 to 0.8 of its 1.3 to 2.2 ms. Measurements and
  scripts: `test-results/morning-20261031/`.
- `HYPOLAND_ALPHA_BOUNDS` (2026-10-29, asked for as "can omarchy-shell be drawn differently"): a layer surface with an alpha
  channel is blended over everything under it, also where its pixels are fully transparent, and Omarchy's shell
  (Quickshell: four layer surfaces per output, ARGB8888 dmabufs from Qt's GL swapchain, never an opaque region,
  whole-surface damage on every commit) keeps three such surfaces across the screen: since Omarchy r7338 (commit
  e2d618ac of 2026-10-19, "Keep the bar surface full-size so drags survive empty workspaces"; the T550's r7218 and the
  Galaxy Book's are older) the bar's window spans the whole screen with the strip painted at the top, the dock's window
  (a 207 px band at the bottom on the X200) stays mapped on every workspace with its contents hidden, and the
  notification column (399 px at the right) stays mapped while empty, both on purpose (remapping disturbs focus and
  the scrolling layout, the comments in `DockWindow.qml` and `notifications/Service.qml` say). On the X200 the three
  cost more GPU time per frame than the window under them (`HYPOLAND_PROFILE_PASS`, which names a surface after its
  layer namespace or app id since that day: under `gtk3-scroll` the GTK window 3.07 ms, the bar 3.00, the
  notifications 1.02, the dock 0.90 of 8.35 ms, the same share in `terminal-scroll`, the sprites and `video-window`),
  on the XPS they are 13 to 17 points of GPU busy time under a scrolling window. Hypoland cannot know a dmabuf's
  pixels, so once such a surface has not committed for 150 ms, a frame draws the largest alpha of every 8x8 block of
  its buffer into a small framebuffer (`alphamax.frag`, `gl_FragCoord` picks the block, 64 fetches per pixel of an
  eighth-size target, about one full-screen pass), the next frame reads it back (64 kB for 1280x800, the GPU finished
  it with the frame before) and `renderLayer()` clips the surface to the box of the blocks with any alpha
  (`CHyprOpenGLImpl::analyzeLayerAlpha()`, `CLayerSurface::m_alphaBounds`; a box of nothing skips the layer). A commit
  drops the box until the next analysis, so a surface that animates is drawn whole; not for blurred layers (their
  transparent pixels show the blur), surfaces with a viewport source, a transform or subsurfaces (a viewport
  destination, which Qt sets on every window, is fine). `0` switches it off, `debug` prints every box to stderr
  (X200: bar 1280x800 -> 1280x32, dock and notifications -> nothing, the wallpaper -> all). X200, GPU time per frame with
  the profile on: `gtk3-scroll` 8.35 -> 3.41 ms (the bar 0.03), sprites 7.08 -> 2.84, `terminal-scroll` 8.66 -> 3.70, and
  the frames the profile had cost came back (52 -> 60, 47 -> 59, 25 -> 30 fps). Fresh sessions on the X200, on against
  off (`bench.sh`, 12 s each): `gtk3-scroll` 60 instead of 52 fps, the sprites 59 / 47, `resize` 59 / 41,
  `terminal-scroll` 30 / 25, `dev` 45 / 42; compositor CPU `gpu-client` 4.3 / 6.3, `video-window` 3.6 / 4.7, `dev` 8.5 /
  9.5; the i915 PMU's busy time `gtk3-scroll` 0.0 / 26.4%, `terminal-scroll` 0.1 / 12.5, the sprites 1.4 / 21.0 (one
  opaque window costs the GM45 almost nothing: a scrolling foot keeps it busy 0.5%; the profile's milliseconds per
  element are mostly its own glFinish drains, read its shares); the `dev` scroll 43 / 51 ms, `resize` redrawn 52 /
  63, the menu open 484 / 504. On the XPS (iris, 3200x1800): GPU busy `gtk3-scroll` 26.7 / 40.1%, `terminal-scroll`
  18.8 / 34.8, the sprites 4.7 / 8.7, `gpu-client` 29.0 / 33.7, `resize` 69.4 / 78.2, `video-window` 29.8 / 36.2;
  compositor CPU the sprites 8.1 / 10.8, `terminal-scroll` 3.6 / 4.3; `resize` redrawn 27 / 34 ms; the package's power
  net of idle (`bench.sh --energy`, RAPL, 2 rounds) `terminal-scroll` 10.8 / 11.6 W, `gtk3-scroll` 9.1 / 9.4,
  `gpu-client` 2.2 / 2.5, `video-window` 4.0 / 4.3. The readback waits
  for a native fence of the analysis draw (a frame whose fence is not signaled leaves it for the next): without it
  the readback at the next frame's start waited for the whole frame before, which iris still has in flight, and the
  XPS opened the menu 36 ms later and spent 3 points more GPU on `workspace-switch`; the rest of those two losses
  was the shell: while it is busy its windows commit about twice a second each (a workspace switch has the bar
  commit 16 times for its indicator's animation, and the wallpaper, the dock and the notification column twice each,
  every one a new buffer with the whole surface damaged: 316 + 40 + 42 + 40 commits in the X200's 56 s
  `workspace-switch`, WAYLAND_DEBUG of the shell; a menu toggle a second has the bar, dock and wallpaper commit
  once a second each), so each was analyzed a hundred times a minute; a surface whose last two commits came less
  than two seconds apart is drawn whole until it has been quiet for two seconds (at one second the XPS still paid
  27 ms of its menu's opening for three 3200x1800 analyses), and a commit without a new buffer or damage keeps the box. What stays is the shell's doing and the largest cost under it: a
  full-size bar window whose every animation frame damages the whole screen makes the compositor repaint
  everything under it (16 full repaints per workspace switch), and re-rendering the wallpaper on every switch
  does the same twice more; a strip-sized bar window and no wallpaper commit would remove them (reported as
  omacom/omarchy#16997 on 2026-10-29, the captures and scripts in `~/Work/omarchy-shell-layers/`). With the back-off (r803, on / off, 2 fresh
  sessions each): `workspace-switch` costs the same GPU time everywhere (T460s 11.7 / 12.0%, T550 4.4 / 4.3, Mac
  mini 12.0 / 11.7), the menu opens the same or sooner (X200 369 / 473 ms, Chromebook 616 / 684, T460s 162 / 164),
  a toast shows sooner (T460s 16 / 26 ms, Mac mini 30 / 37, Chromebook 31 / 41; lianli 28 / 26 and the X200 67 / 55
  within their spread), and the scrolling gains stay (GPU busy T460s `gtk3-scroll` 22 / 29, `terminal-scroll` 11 /
  15, `resize` 27 / 32; Mac mini `gtk3-scroll` 30 / 54, `resize` 7.5 / 46; X200 `gtk3-scroll` 55 / 40 fps, `resize`
  60 / 40). One cost stands: the Mac mini's `resize` redraw 27.5 / 24.3 ms. Deploy checks pass on the X200, T460s,
  lianli, Chromebook, Mac mini and Galaxy Book, the scanout is identical with it on and off. Tried and dropped: the
  surface shader discarding its a == 0 pixels instead (`discard`): slower on GM45, the bar 3.00 -> 4.94 ms, the blend is
  not the limit there, the shader is. The shell patched instead (bar window the strip's height, dock mapped only on
  floating workspaces, notification column only with a toast; `shellmod.sh` in the session's scratchpad) gives the same
  on the XPS (GPU busy `gtk3-scroll` 39.8 -> 26.7%, `terminal-scroll` 34 -> 19, `workspace-switch` 24 -> 7, GPU memory at
  the end of a run 324 -> 251 MB) but loses the toast's latency to the map, and Omarchy chose the full-size window, so
  the compositor side is the one kept. The shell itself: Pss 230-290 MB, 29-37 threads, GPU memory 52-107 MB of which
  26-45 MB are its swapchains; its CPU under `menu` is the guard batch (the user's menu work of 2026-10-27), under
  `notifications` about 4% of a core with a `ps` per toast. Captures and scripts: the session's scratchpad `shell/`.
  Since 2026-10-30 the analysis runs between frames, not in one: a layer's commit arms a timer for its settle time (150 ms,
  or 2 s while its commits come less than 2 s apart), and the tick draws the block maxima in strips of about a million
  pixels of the buffer every 2 ms (`CHyprOpenGLImpl::issueAlphaStrip()`, each strip flushed, the last one with a native
  fence), polls the fence and reads the box back (`readAlphaBounds()`, `m_alphaTimer`, `m_alphaPending`); the shader takes
  16 bilinear taps between the texels of an 8x8 block instead of 64 fetches, with the result scaled so a quarter of 1/255
  still leaves a nonzero pixel, and the backdrop (the wallpaper) is not analyzed. Before, the whole draw sat in the first
  frame after the settle, which was the user's next action: the XPS opened the menu 11 ms later in every one of 30 night
  blocks (r786 against r797, 2026-10-29 to 30, 29 to 31 fresh sessions of each on all eight machines, `night2` in the
  session's scratchpad), and that is gone (on against off with the timer build, 10 rounds: 296 against 295 ms); the menu
  closes 0.4 to 2.6 ms sooner than with the in-frame draw on the T550, Mac mini, Chromebook, Galaxy Book and X200, a toast
  shows 1.8 to 6 ms sooner on the T550, lianli and X200, and CPU, frames and GPU time are the same (r797 against r799, 7 to
  8 fresh sessions each, 2026-10-30 morning). On iris the readback itself blocks the main thread for 0.3 to 12 ms (median
  0.7 to 0.9) and the strips issue in about 150 us each (the first 1.7 to 2.7 ms). Open: on the T460s (scale 1.5) the
  first frame of a resize step comes 1 ms later with the bar clipped (1.1 to 1.5 ms without, 1.1 to 4.2 with, in every
  block of the night; the same with the timer build, with the GPU clock pinned to its maximum, and with the empty layers
  drawn instead of skipped, so it is the clip of the bar's surface itself; `redrawn`, which is what the user sees, is
  unchanged), while on the XPS the clip makes the step faster (1.3 against 1.6 ms) and spread its `redrawn` only through
  i915's frequency scaling (tight and better, 27 to 31 against 32 to 42 ms, with the clock pinned). For telling such costs
  apart `HYPOLAND_ALPHA_BOUNDS=noclip` analyzes but draws every layer whole and `=noskip` clips but draws a layer whose buffer
  has no alpha whole instead of skipping it. The Mac mini's `resize` (master r914, 2026-11-01, 2 to 4 fresh sessions each,
  `test-results/ab-20261101/`): with the alpha bounds `redrawn` 27.5 ms and a resize step's 90th percentile 10 ms, without
  them 23.8 / 3.4, with `noclip` 24.6 / 4.2, with `noskip` 27 / 8.7, at a GPU busy 10% against 42%; and the same with the
  GPU's minimum clock pinned at its maximum (28.1 / 10 against 24.0 / 4.8, GPU busy 1% against 32%). So not i915's
  frequency scaling and not the skipped layers but the bar's clipped draw itself; open, it needs a frame timeline as
  the toast's (`test-results/toast-20261101/`). The night also showed the GTK 4 cost of the zero copy under `HYPOLAND_SHM_ZEROCOPY`
  above, and the Chromebook's `workspace-switch` 0.7 points of CPU higher with the alpha bounds (6.3 -> 7.1%, every block,
  the same with the timer build; its GPU time 22 -> 13%), not looked into.
- A focus change under fcitx5 (2026-10-30, the user: "a focus change shown is worse is a regression on Hypoland"): the
  baseline of 2026-10-27 had it 0.3 to 1 ms slower than Hyprland 0.56.2 on the crocus machines, the 90th percentile twice
  as slow. A perf timeline of the compositor (its reads, ioctls, context switches) and a 20 kHz sampled profile windowed
  between the arrow key's evdev read and the atomic commit (the scripts are `focus/` in the session's scratchpad:
  `focustrace.sh`, `focusprof.sh`, `analyze.py`, `profwin.py`, `callers.py`, `probes.sh`, `swap.sh`) showed the extra as
  main-thread CPU in libc and libxkbcommon: fcitx5 (Omarchy's input method) grabs the keyboard on every focus change,
  for which the compositor copied the keymap text into a new shm file, and recreates its virtual keyboard with the
  keymap it got back, which the compositor compiled (100 kB of text), serialized twice in both formats into four shm
  files, and compared as a whole against a copy kept per wl_keyboard resource at the keyboard switch; uprobes on the Mac
  mini counted 15 `xkb_keymap_new_from_string` and 62 `xkb_keymap_get_as_string` in 12 focus steps. Hyprland 0.56.2 does
  the same work, its loop ordering just put it after the commit more often. Since then the text and files are made once
  per compiled keymap and shared (`IKeyboard::SKeymapFiles`, `filesForKeymap()`, a cache of four that references the
  keymaps), a virtual keyboard whose text matches a keyboard's reuses that keymap (`CVirtualKeyboardV1Resource`), the
  IME grab sends the shared read-only file, and the seat tells keymaps apart by hash and length (0 compiles and
  serializations in the same 12 steps). A/B r800 against r809, 6 to 7 fresh sessions each (`idle-windows`,
  `workspace-switch`, `dev`): the focus change Chromebook 6.25 -> 5.85 ms, Mac mini 2.3 -> 2.1, T550 2.1 -> 2.0,
  lianli 1.7 -> 1.6; under the `dev` load 12.7 -> 9.6, 5.6 -> 4.0, 4.4 -> 3.5, 13.2 -> 11.2; compositor CPU in `dev`
  8.27 -> 7.72% on the Chromebook and 0.15 to 0.2 points lower on the others, `workspace-switch` 0.1 to 0.2 lower; Pss at
  the end of a run 0.9 to 1.3 MB lower on all four (the keymap copies), the heap at start 0.2 to 0.6 MB lower.
  Two more in the same path, measured as r811 against r809 the same way (7 to 8 sessions each): `Keybinds::CKeybindManager::
  canInvokeNow()` asked the shortcuts-inhibit protocol, a view query over every window, once per bind on every key event,
  a hundred queries per key press, now once per event; and the `activelayout` IPC event came twice per focus change (on
  `applyConfigToKeyboard()` and on the virtual keyboard's keymap request: 31 events in a run with 16 focus changes on
  the T490) and Omarchy's bar (`shell/plugins/bar/widgets/KeyboardLayout.qml`) runs `hyprctl -j devices` for each; a
  keyboard posts it only when its layout name changes now (`IKeyboard::m_activeLayoutPosted`), a virtual keyboard that
  types in the seat's active layout posts none at its creation (1 event and 30 fewer `hyprctl` runs in the same run).
  r809 -> r811: the focus change Chromebook 5.8 -> 5.3 ms, Mac mini 2.15 -> 1.9, T550 1.95 -> 1.8, lianli 1.6 -> 1.5, the
  workspace switch's window 5.9 -> 5.3 on the Chromebook, the whole session's CPU under `dev` 0.6 to 1.4 points lower
  (Chromebook 26.2 -> 24.8%, Mac mini 17.9 -> 17.3, T550 11.5 -> 10.9, lianli 14.3 -> 13.5: the bar's `hyprctl` runs),
  the compositor's and memory the same. Against the baseline's Hyprland 0.56.2 the Chromebook's focus change is now
  5.3 against 5.8 ms and the Mac mini's 1.9 against 2.1. The X200, measured in the evening (r800 against r811, 10 sessions
  each): the focus change 3.9 -> 3.35 ms (Hyprland 0.56.2: 3.6), 3.95 -> 3.4 in `workspace-switch`, 6.15 -> 5.4 under
  `dev`; compositor CPU `dev` 4.88 -> 4.53%, `workspace-switch` 2.50 -> 2.32, the session under `dev` 18.6 -> 17.4;
  Pss at the end of a run 45.4 -> 44.0 MB; `dev.type_ms` 2.9 -> 3.6 is the one figure that went the other way there.
- Animations take their values for the next vblank (2026-10-31, `CMonitor::nextPresentation()`, `curveStep()` in
  `AnimationManager.cpp`): hyprutils' `getCurveStep()` reads the clock itself, in whole milliseconds, when the frame is
  drawn, so a frame drawn right after an animation began showed its start value. The baseline against Hyprland 0.57.0 had
  a focus change among many windows a frame late (T550 3.4 -> 13.7 ms): a perf timeline on the Galaxy Book
  (`test-results/morning-20261031/galaxybook-zctrace/`, `zcan.py`) had every measured step equal one of the compositor's
  commits, the first when it came 2.5 ms or later after the key, the next one when it came sooner, since Omarchy's border
  fades with easeOutQuint over 539 ms. Zero copy made the first frame come sooner, which made it look like a zero-copy
  delay. The tick now computes a bezier animation's value for the next vblank of the monitor that renders (the fastest
  for timer ticks), from the last vblank the hardware stamped and the refresh period; springs, VRR and tearing keep the
  tick's own time. 6 to 8 fresh sessions each: a focus change among 10 / 20 / 40 windows XPS 10.2 / 16.8 / 18.0 -> 2.1 /
  2.5 / 2.8 ms, T550 14.4 / 14.4 / 13.4 -> 1.8 / 2.1 / 2.7, Galaxy Book 5.1 / 3.6 / 3.4 -> 2.4 / 2.1 / 2.0;
  `launch.opened` 31, 19 and 8 ms sooner; CPU and the other latencies the same within their spread. The XPS's menu
  opened 317 -> 328 ms in that A/B (blocks 296 to 322 against 318 to 338), but not because of the lead: the same build with
  the lead switched off (a diagnostic `HYPOLAND_NO_ANIM_LEAD`, never on master) opens it in 325 against 331 ms with it on
  (6 fresh sessions each, 306 to 343 against 301 to 343), while a focus change among 10 / 20 windows stays 16.2 / 17.5 ->
  2.1 / 2.4 ms; the XPS's menu is bimodal per session, 300 to 320 or 325 to 345 ms, in every build of that day.
- Realtime and its guard (2026-10-31). Since upstream #15465 (July 2026, in the fork base and in 0.57.0) the compositor
  puts its main thread on SCHED_RR through rtkit (`NInit::gainRealTime()`; `HYPRLAND_NO_RT=1` keeps it off), which rtkit
  grants only under RLIMIT_RTTIME, set to 150 ms soft and 200 ms hard (the most Arch's rtkit allows). The kernel adds up
  the time a realtime thread runs without sleeping and compares it with the limits only when the thread returns to user
  space (the posix CPU timers run as task work): an overrun in user space gets SIGXCPU at the soft limit, and upstream's
  handler drops realtime (`Realtime budget exceeded (SIGXCPU)` in the journal, seven times on the XPS in the night), but a
  single kernel call that runs from below the soft limit past the hard one gets SIGKILL with no SIGXCPU before it and
  nothing in any log, and start-hypoland starts a new compositor with every window gone. That was the deaths of the 0.57.0
  baseline night and three Hypoland sessions on the XPS the next morning (r877, in `workspace-switch`, `menu` and
  `resize`), found with `perf record -e signal:signal_generate` on every machine (`/root/sigtrace/`: `sig=9
  code=SI_KERNEL` raised by the compositor's own main thread). `test-results/rt-20261031/rttest.py` shows both cases
  under rtkit's limits (a spin gets SIGXCPU, a 3 GB read from /dev/zero SIGKILL), and `hyprctl eval 'local f =
  io.open("/dev/zero", "rb"); return #f:read(2^31)'` kills a compositor that rtkit made realtime every time, nested or
  on a machine. What the XPS's long call was is not known: it did not come back in 11 more sessions of r877 and r878 that
  afternoon, the XPS had no compaction stalls, and the main thread's longest stretches in the workloads were 32 ms there
  (a scheduler trace of its sleeps and wake-ups, `stretch.py`); closing the 40 windows of `many-windows` at once is the
  longest everywhere (Galaxy Book 146 to 162 ms, a SIGXCPU in most sessions; T550 77 ms), as is the end of a session.
  Realtime is worth keeping (r878 with and without `HYPRLAND_NO_RT=1`, 6 to 8 fresh sessions each on six machines,
  `test-results/rt-20261031/rtab-summary.txt`): without it the Chromebook shows a workspace switch in 5.75 instead of
  2.85 ms, with 40 windows 17.5 instead of 4.45, a focus change among 40 windows in 16.5 instead of 9.7, a resize step in
  4.4 instead of 2.2 and a closing terminal in 21.4 instead of 15.1; the other machines switch 5 to 25% slower, lianli
  closes a terminal in 4.4 instead of 3.7, and the compositor's CPU is 1 to 11% higher without it (`dev` on the T550 3.76
  against 3.36%). So a guard thread (`guardRealtime()` in `src/init/initHelpers.cpp`) polls every 40 ms: when the event
  loop has not gone round since its last poll it reads the main thread's state (`/proc/self/task/<tid>/stat`), takes
  realtime away when that was running at two polls in a row (80 to 120 ms in one go; the kernel stops counting at once,
  also in the middle of a kernel call), and asks rtkit for it again from its own thread when the main thread has slept in
  the loop's epoll through three polls, 2 s after the drop at the earliest, backing off to a minute when rtkit says no
  (`Realtime: ...` lines in the journal). The event loop is `wl_display_run()` written out (`CEventLoopManager::enterLoop()`)
  and counts its rounds with one atomic; the guard waits for the next round while the main thread sleeps in the loop's
  epoll (`/proc/self/task/<tid>/syscall`), not while it sleeps inside a round (a GPU fence), which the same round can
  follow with a long call. `HYPOLAND_NO_RT_GUARD=1` keeps realtime and leaves the guard out, for measuring it. The long
  read is survived every time, nested and on the Galaxy Book, back on realtime 2 to 3 s later; hyprtester 176/176. At idle
  on the X200 the guard wakes 6 times a second (the main thread 3.7). Two versions before: polling every 20 ms and dropping
  at 40 ms cost 1 to 7% more compositor CPU on six machines (lianli `workspace-switch` 2.21 -> 2.31%, the Mac mini's `dev`
  3.38 -> 3.53) and dropped realtime a few times a session on the X200 (the end of `many-windows` among them); 40 / 80 ms
  with the loop telling the guard when it slept (a `poll()` more per round) still cost 2 to 5% in `workspace-switch` and
  doubled the tiny `idle-windows` (0.02 -> 0.04% on the T550; `test-results/rt-20261031/guard40-summary.txt`).
- A closing window's fade damages only where it is drawn (2026-10-31, `CWindowFadeout::damage()`): upstream's fade-out
  damaged the whole monitor on every animation step, so closing a window repainted the screen for half a second (Omarchy's
  `windowsOut` and `fadeOut`). The snapshot is still the monitor's size; the window's part of it (`m_contentBox`: its frame
  with decorations and popups and its surface tree's extents) is mapped through the fade's scale and position, and the
  frame damages where it was drawn last and where it is drawn now; blur and a dim around the window keep the whole
  monitor. Nested screenshots before, 40 and 100 ms into and after a fade match master outside the window, the frame
  after the fade matches a full repaint. XPS (3200x1800), 3 fresh sessions each, a floating 640x400 foot over two tiled
  ones closed 10 times (`test-results/rt-20261031/fadebench.sh`, the second after each close): the GPU busy 733 / 724 /
  725 -> 507 / 491 / 503 ms (i915 PMU), the compositor's CPU 160 to 220 -> 130 to 170 ms, the same page flips. Seen while testing it, upstream's too: a foot window that closes fades as its
  border alone, foot drops its buffer before the toplevel. Since 2026-11-01 a window whose surface is about to apply a
  state without a buffer (the unmap of such a client) takes its snapshot at the surface's precommit, while the last buffer
  is still current (`CWaylandBackend` emits `unmapSoon`, `CWindow::m_unmapSnapshot`, dropped at the next commit when the
  state was not applied after all): foot's contents fade out with it (a nested compositor with a 0.5 s fade, grim every
  40 ms: r919 shows the border alone from the first frame, now the magenta window fades; `fadetest.sh` in
  `test-results/fade-20261101/`).
  Until 2026-11-02 the window's box was measured when the fade was made, after the window's close event, which drops its
  decorations from the decoration positioner: the box had only the border, and a closing window left its titlebar, its
  shadow or a group bar on the screen until something else drew there (r885 to r926; on Omarchy's floating workspaces,
  which have titlebars). It is measured at the start of `CWindow::unmapWindow()` now (`CWindowFadeout::contentBoxOf()`).
  Found by the render checks with `render-configs/titlebars.lua` and `shadows.lua` (above).
  The snapshot a close fades out from (`makeSnapshotFB()`) was a new framebuffer of the monitor's size per close, and on
  i915 Mesa has a new buffer's pages allocated and cleared at once (`DRM_IOCTL_I915_GEM_SET_DOMAIN` in `crocus_bo_alloc`,
  9 MB at 1920x1200): uprobes on the snapshot and `CWindow::unmapWindow()` on the Mac mini had the snapshot at 3.3 ms of a
  3.7 ms unmap, almost all of it that ioctl (`snaptrace.sh`, `snapan.py` and both traces in `test-results/pool-20261101/`).
  Since 2026-11-01 the monitor keeps them (`CMonitorResources::getUnusedSnapshotFB()`, like the work buffers: one a fade
  left is taken again, freed 5 s after its last use): snapshot 0.14 ms, and Omarchy's terminal closes (`launch.close_ms`,
  r909 against the pool, 4 fresh sessions each) on the Mac mini in 3.35 instead of 7.75 ms, the X200 4.15 / 9.9, the
  Chromebook 9.8 / 14.85, every block; the rest of `launch` and `menu` the same (`test-results/pool-20261101/`). Hyprland
  0.57.0 closed it in 7.7 ms on the Mac mini and 13.7 on the Chromebook in the night of 2026-10-31.
