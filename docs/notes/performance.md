# Performance, profiles and memory

Engineering notes of Hypoland, moved out of `AGENTS.md` on 2026-11-12 unchanged. `AGENTS.md` has the rules and
the current state; the notes say what was tried, measured and dropped. Add new findings here, with the date.

GPU time per frame, CPU profiles, memory and the overnight runs of September 2026, mostly on the X200.

Performance (X200, `HYPOLAND_PROFILE_PASS`, GPU time per frame, 4 windows plus a 60 fps client):

| | before 2026-09-27 evening | now |
|---|---|---|
| full-screen redraw | 19.1 ms (pass 14.3 + clear 1.4 + copy 3.4) | 14.4 ms |
| small updates | 3.4 ms (pass 1.7 + clear 1.4 + copy 0.3) | 1.7 ms |

- Every frame used to clear the whole 1280x800 work buffer (1.4 ms, Gen4 has no fast clear). Now only the damage
  is cleared: the pass paints the background over its damage anyway (`clearRegionAfterInvalidation()`).
- Frames are drawn straight into the screen buffer when nothing needs the work buffer (no zoom, no rotated output,
  no mirror or screen sharing), `CHyprOpenGLImpl::canRenderDirectly()`. That removes the copy
  from the work buffer to the screen. Screen buffers are imported twice: as a renderbuffer to render into and as a
  texture to sample from (blur), with a stencil renderbuffer. The screen buffer holds the frame from bufferAge
  frames ago and the damage covers everything since, so blur samples correct pixels outside the damage.
- Fill rate is the limit: one fullscreen 1280x800 blended surface costs about 3.3 ms.
- Borders cost about 0.4 ms per window on a full redraw, they are already limited to the border ring.
- Omarchy gives every window an opacity rule (`default-opacity` tag), so no window occludes the wallpaper.
  With opaque windows the occlusion pass skips what is underneath.
- Quickshell's notification layer is a transparent overlay layer that is blended over every damaged area under it. It
  was fullscreen when this was found; the Omarchy 4 of 2026-10-26 keeps it as a column at the right of the screen
  (465x800 on the X200) and has the dock as another, a strip of 245 px at the bottom (`hyprctl layers`).
- The wallpaper counts as opaque (`CSurfacePassElement::isBackdrop()`, 2026-09-29): the lowest surface of the
  background layer, when it covers the monitor and has no fade or blur. Omarchy's wallpaper is a Quickshell window
  with `color: "transparent"`, so its buffer has alpha and no opaque region, and the pass painted
  `misc:background_color` under it on every redraw (1.0 ms of a full-screen redraw) and blended it. It is drawn
  without blending now and hides the clear. Transparent pixels of a wallpaper show over black instead of over
  `misc:background_color`. A full tile with a window at opacity 0.9: 6.89 -> 5.78 ms GPU time per frame; opaque
  windows (2.95 ms) hide the wallpaper anyway. Measured with i915 request tracing, not `HYPOLAND_PROFILE_PASS`.

CPU profile: run `./profile.sh`. It installs the package with `hypoland-debug` (makepkg builds with frame
pointers, Arch's default flags, so the package needs no profiling build; the debug package has the symbols),
switches the Omarchy screensaver and idle lock off, records five workloads with `perf` as root, prints the report
to `test-results/profile-*/profile.txt` and removes the debug package. Use `--keep` to leave it installed;
`perf report` on the saved data only resolves symbols while it is. Until 2026-10-24 it used a separate build
without the package's hardening flags (`-D_GLIBCXX_ASSERTIONS`, `_FORTIFY_SOURCE=3`, stack clash and CET
protection), so older profiles are not exactly comparable.
Findings:
- Idle desktop: 0.1% CPU.
- GPU client at 60 fps, 10% CPU: `renderMonitor` 76% of it. `endRender` 52% (of which `CEGLSync::create` 25%,
  this is where the driver flushes and submits the batch, and `CDRMOutput::commitState` 11% with the atomic commit
  8%), `CRenderPass::render` 19%. Clock reads 3%, DRM property re-reads in aquamarine 4%.
- shm client redrawing a large window (Chromium), 26% CPU: `CGLTexture::update` 71%. About 38% of all samples
  are the kernel allocating, clearing and cache-flushing pages for a new GPU buffer on every upload
  (`shmem_alloc_and_add_folio`, `drm_clflush_sg`), about 23% is the `memcpy`.
- Terminal scrolling fast (foot, shm), 15% CPU: `CGLTexture::update` 74%, the same upload cost as Chromium.
- Workspace switching with three windows and animations, 15% CPU: only 30% is `renderMonitor`. Clock reads are
  17% (`read_hpet` 12%), the rest is spread over animation ticks, layout and damage. Fixed on 2026-09-29, see below.
- Hypoland's own code is flat, no function has more than about 1% self time.
- The X200 uses the HPET clocksource (the TSC is marked unstable), so every clock read is a slow syscall.
- Fixed: uploading into a shm texture the GPU still reads from made crocus allocate, clear and cache-flush a
  staging buffer every time (2.4x the cost of the upload, measured with a standalone benchmark). Synchronous
  textures are now double buffered (`CGLTexture::update()`): the update goes into the texture that was shown one
  update ago, plus the damage it missed. Chromium 26.8% -> 12.8% CPU, fast terminal scrolling 14.8% -> 11.3%.
- Fixed: the event loop read the clock once per timer when rescheduling and when timers fire; it reads it once
  per pass now. Workspace switching 14.9% -> 12.7%.
- Checked on 2026-09-27, not worth optimizing:
  - The shm upload (`glTexSubImage2D`, crocus copies through a GTT mapping) runs at the memory bus limit:
    1.64 ms for a full 1280x800 frame with glibc memcpy. SSE2 non-temporal stores are the same through the GTT,
    `rep movsb` is slower, and the best case (own WC mapped linear buffer) is 1.45 ms. Hand-written copies or
    inline assembly would not help.
  - `CEGLSync::create` is where Mesa's threaded context runs the whole frame (draws and batch submit). A frame
    with one 60 fps client was 2 draws and 16 ioctls, all needed except the mode re-read, which is fixed
    (13 ioctls now, see below).
- Tried and dropped (2026-10-27): reading a screen capture into an shm buffer asynchronously.
  `CScreenshareFrame::copyShm()` calls `glReadPixels` right after drawing the capture, which waits for the GPU (24 ms
  on the X200 after a full redraw; the comment in `CGLFramebuffer::readPixels()` suggests a pixel buffer object). A
  pixel buffer object (`NV_pixel_buffer_object`, which Mesa offers in GLES 2) is no help on crocus: Mesa only copies
  into one on the GPU with shader images (`st_init_pbo_helpers()`, `max_shader_images`), which Gen4 lacks, and
  otherwise waits and copies on the CPU all the same. Tried instead: a fence after the capture and the read when it
  signals, as `copyDmabuf()` finishes. On the X200 (weston-simple-egl and a client capturing the whole output without
  pause, 3 rounds of each build) captures on damage, as a recorder takes them, went from 30 to 16 a second and the
  screen from 55 to 33 fps; immediate captures showed 33 instead of 30 fps on the screen at the same rate. Traced with
  uprobes: the GPU is the limit. Without the wait the compositor queues the next screen frame behind the capture, and
  it misses its refresh (78 of 102 frame gaps were 33 ms, against 11 of 169); and the read, of a buffer the GPU has
  finished, took 13.7 ms of CPU time on the main thread, against 19.3 ms for the whole read with its wait before
  (likely Mesa reads the tiled buffer directly then, instead of copying it on the GPU into memory the CPU reads fast).
  Clients that capture into dmabufs (the screen sharing portal, OBS) take the asynchronous path already.

Memory (X200, idle Omarchy session 60 s after start, `heaptrack` and `/proc/<pid>/smaps`):
- Fixed: aquamarine created a second EGL context for the primary GPU, which is only needed when a secondary GPU
  blits (`CDRMBackend::primaryRenderer()` now creates it on demand). It cost heap and a Mesa driver thread.
- Fixed: shaders were preprocessed with glslang, only to resolve `#include`. `CShaderLoader` expands includes
  itself now and leaves `#define` / `#if` to the driver, so libglslang (2.5 MiB, private to the compositor) is no
  longer loaded.
- Both together: RSS 113.6 -> 100.1 MiB, anonymous 38.0 -> 27.2 MiB, PSS 73.8 -> 60.1 MiB, one thread less,
  compositor CPU with `weston-simple-egl` unchanged (7.3%).
- What is left: about 17 MiB heap, of which about 7 MiB is Mesa compiler state created with the first shader and
  1.7 MiB the GL context. libLLVM shows 19 MiB RSS but only 6 MiB PSS, the pages are shared with Quickshell and
  Xwayland and come from loading the library (`DRAW_USE_LLVM=0` changes nothing). The Hypoland binary is about
  14 MiB of clean file pages.
- The "started without start-hypoland" notification loads fontconfig and pango (about 1.5 MiB heap) when the test
  loop starts `hypoland` directly; a start through `start-hypoland` (the SDDM session) does not.

Overnight run 2026-09-28 (journal in `test-results/overnight/journal.md`), measured with `./bench.sh`
(`performance` governor), before -> after:

| | before | after |
|---|---|---|
| Pss / Rss / anonymous, 60 s after the start | 62.2 / 102.5 / 29.2 MiB | 55.2 / 95.8 / 22.1 MiB |
| GPU memory, 60 s after a plain restart | 73.5 MiB | 52.0 MiB |
| GPU client at 60 fps | 3.69% | 3.17% |
| terminal scrolling | 10.56% | 10.13% |
| Chromium over shm | 11.01% | 10.20% |
| workspace switching | 8.97% | 8.62% |

- Transparent huge pages are off for the compositor (`prctl(PR_SET_THP_DISABLE)` in `main()`), an atfork handler
  gives clients the system default back. The X200 runs with THP `always`.
- Mesa keeps 5.7 MiB of GLSL built-in function tables after the first shader compile.
  `CHyprOpenGLImpl::scheduleShaderCompilerRelease()` calls `glReleaseShaderCompiler()` and `malloc_trim()` 10 s
  after the last compile. Without the trim the memory stays in the heap.
- Frames get no EGL fence on crocus (`CHyprGLRenderer::needsRenderFence()`), i915 has implicit sync. The fence
  is still made for explicit sync clients, screen sharing, multi GPU and other drivers. It was skipped on all of
  i915 until 2026-10-23: iris (Broadwell and later) submits `glFlush()` on Mesa's driver thread, so the commit could
  overtake the batch and the XPS (3200x1800) showed half drawn frames; `GALLIUM_THREAD=0` hid it. The driver name
  comes from `EGL_MESA_query_driver` (`CHyprOpenGLImpl::m_eglDriverName`). Until 2026-11-01 a frame without a fence
  left the fence of the last frame that had one in the output's state, and aquamarine sets `IN_FENCE_FD` whenever the
  state holds one (`Atomic.cpp`, not only when that commit set it), so on crocus every frame after a zero copy window
  (since 2026-10-29) or a screen capture (since the fence was skipped there) went to KMS with that long signalled fence:
  i915 takes an explicit fence instead of the buffer's implicit one, so it did not wait for the frame's rendering before
  the flip, and the GPU got no boost from the commit worker's wait. On the Chromebook the GPU then stayed at its
  lowest clock under kitty after `terminal-scroll` (foot, zero copy), 15 instead of 23 fps at 76% busy, in every block
  of the night of 2026-10-31 (the third workload of a block is `terminal-scroll`); the commit worker's waits on
  `i915_request_wait_begin`, 22 a second with kitty alone, were none. The implicit path resets the explicit fences
  of a normal frame now (`CHyprGLRenderer::endRender()`); kitty after foot 22.6 fps at 27%. Upstream always fences
  where explicit sync works, so it never mixes the two. Scripts: `test-results/fence-20261101/`.
- aquamarine keeps the mode of the CRTC (`SDRMConnector::atomic.currentMode`) instead of reading it on every commit.
  A frame with one 60 fps client is 13 ioctls now, 9 of them are Mesa's buffer cache (`GEM_MADVISE`, `GEM_BUSY`).
- Not merged, by decision of the user (2026-09-28): the build changes. They are the commits `13ee9d36` and
  `4b16588f` on the local branch `overnight/ram-cpu`. The binary is mapped almost completely, so its size is
  memory: `--gc-sections`, `-O2`, and `-Os` for code outside the frame and input paths take the binary from
  18.1 to 13.9 MiB and Pss down by 2.9 MiB without a change in CPU time. `-Os` for everything saves 5 MiB more
  but costs 3 to 9% CPU time, `-Os` for everything except render / helpers / output costs 4% in workspace switching.
  `--gc-sections` alone (`-ffunction-sections -fdata-sections`, no `-O2` / `-Os`) is in since 2026-10-29: the binary
  14.99 -> 13.56 MB, `.text` 12.0 -> 10.85 MB, 1.0 MiB less file Pss on the X200 and T550 with CPU and latencies
  unchanged (2 fresh sessions each).
- Two static tables (2026-10-29): aquamarine's PNP id table is a constexpr array of string_views searched once per
  connector instead of an unordered_map a static initializer built at startup (`hwdata.hpp.in`, -450 kB of heap, -125 kB
  of code), and the keybind manager's XKB translation state shares the keyboards' keymap (`IKeyboard::keymapForRules()`,
  one xkb compile per config reload instead of two, -110 kB): Pss at start X200 44.7 -> 43.9 MiB, T550 44.9 -> 44.3
  (anonymous -0.6 MiB), 43.1 / 43.2 with gc-sections. Found with a preload allocation tracer and per-file Pss
  (`test-results/heap-20261028/`): the binary's 11.6 MiB of code is the largest Pss item, paged in almost completely; the
  165 other libraries cost 1.6 MiB together; Hypoland's own C++ heap is about 1.4 MB, Mesa's several.
- Idle shm windows give their second texture back (2026-10-25, `CHyprOpenGLImpl::trackBackTexture()`): a texture
  that was not updated between two sweeps a second apart frees the one its updates went into. Three foot windows that
  printed and then sat idle, GPU memory without the purgeable part: X200 8 -> 6 MiB, T550 16 -> 8, XPS 48 -> 24,
  Galaxy Book 40 -> 25, no CPU change. A window has a second texture only after two commits at its last size (a
  resize makes a new texture). iris and crocus keep small freed buffers in Mesa's cache and give them back at a later
  free (not counted as purgeable either), larger ones at once.
- Tried and dropped (2026-10-25): shm textures with one texture (as upstream) on every driver but crocus. Slower on
  iris (T550 `qt-software-scroll` 13.8% -> 16.3%), the same on the XPS, a little faster on freedreno (Galaxy Book
  `gtk3-scroll` 15.4% -> 14.5%, sprites 26.3% -> 22.7%, within that machine's spread of about 1.5 points). Double
  buffering stays on all drivers.
- The GPU memory that grows over a benchmark run is Mesa's buffer cache (purgeable) on Intel: what is held changes by
  -8 to +6 MiB. The Galaxy Book holds 23 to 39 MiB more after a run (2880x1800): it comes once, with the first
  `qt-software-sprites` (+45 MiB, no other workload adds any), and further sprites windows add nothing, so a high-water
  mark (a driver cache or a buffer kept once allocated), not a leak. Not narrowed down further.
- Not worth it: the GSettings cursor sync leaves 4 glib threads in the compositor, moving it into a child saves
  0.2 MiB. `malloc_trim` alone finds nothing, the heap is not fragmented. Idle is 3 wakeups per second.
- GPU buffers are system memory on Gen4 and in no process statistic; read them from `/proc/<pid>/fdinfo`
  (`drm-total-system0`), the benchmark reports them as `mem.*.gpu_kB`. The compositor held 100.4 MiB 60 s after the
  start of the benchmark (73.5 MiB after a plain restart), more than its Pss. Now 65 to 74 MiB in the benchmark and
  52.0 MiB after a plain restart (Pss 53.1 MiB, anonymous 20.8 MiB there). The totals vary by up to 8 MiB between runs because
  `test-x200.sh` switched blur on and took a screenshot (blur and mirror framebuffers); `scripts/deploy.sh`, which
  replaced it on 2026-10-24, leaves blur as it was but still takes screenshots.
  - The group bar kept four gradient textures of the size of the monitor (15.6 MiB), also without any window
    group. They are one pixel wide now, the picture is identical.
  - Unused work buffers were only dropped when the next one was requested, which never happens while the monitor
    renders directly. `CMonitorResources` releases them with a timer now (8 MiB).
  - The swapchain has two screen buffers instead of three, three with `render:new_render_scheduling`.
  - A framebuffer that was allocated but never drawn into costs nothing, i915 allocates pages on first use.
    Allocating the blur framebuffer lazily gains nothing.
- The Chromium workload is bimodal, a round is either about 9.0% or about 10.5%. Look at the rounds in `bench.txt`.
- Open: `CHyprBorderDecoration::damageEntire()` was about 7% of the compositor's time while windows animate,
  measured before the tick change of 2026-09-29 below.

Overnight run 2026-09-29 (branch `overnight/startup`, journal in `test-results/overnight-startup/journal.md`),
startup and CPU time with animations. Measured on the X200 with the SDDM session, `schedutil` governor:

| | master 8ae8a37c0 | overnight/startup |
|---|---|---|
| startup: compositor instructions in the first 11 s | 938 M | 783 M |
| startup: compositor CPU in the first 12 s | 730-760 ms | 590-620 ms |
| startup: IPC answers after exec | 0.73-0.82 s | 0.68-0.74 s |
| workspace switching with animations, CPU | 14.2% | 6.1% |
| GPU client at 60 fps, terminal scrolling, Chromium over shm | 6.3 / 10.7 / 11.2% | unchanged |

- Animations ticked every millisecond: after upstream 2b0fd417d the animation timer was re-armed with 1 ms after
  every tick, although every rendered frame ticks right before it draws. The whole tick (all animated variables and
  their damage) ran up to 16 times per 60 Hz frame. Continuous ticking now uses the frame interval of the fastest
  monitor, a requested tick still comes after 1 ms. Same page flips, less than half the CPU.
- Clock reads cost real time, they are not sampling skid as a note of 2026-09-27 assumed: with the HPET
  clocksource every read is a system call and an MMIO read, about 1.2% of the compositor's time per read and tick
  while animating. The tick reads the clock once now. `Time::fromTimespec()` made four reads per presented frame because it did not trust `steady_clock` to be
  `CLOCK_MONOTONIC`, and the frame scheduler, the animation tick and the animation timer's re-arm one each: eight
  reads per frame with a GPU client (489 a second at 60 fps, counted with `perf stat -e
  syscalls:sys_enter_clock_gettime -p <pid>`, the callers from `perf record -g` of the same event; with the HPET
  clocksource the vDSO cannot read the clock, so each read is a system call). Since 2026-10-28 it is one:
  `fromTimespec()` converts directly after checking once that the two clocks agree, and
  `CMonitorFrameScheduler::onFrame()` reads the clock once for the presentation timer, `renderMonitor()`, the
  animation tick and the timer re-arm. 188 reads a second then; the two per frame left are Mesa's
  `__crocus_bo_unreference`, which reads it for every buffer it caches. Effect on the X200 (three alternating fresh
  sessions, r767 against r768): the GPU client 2.88 -> 2.82% compositor CPU, video 2.61 -> 2.56, workspace switching
  3.77 -> 3.73, every new round below every old one; `dev` and the terminal within their spread. About 2% of the
  compositor's time in those workloads, 0.05 points of CPU.
- Startup, instructions of the main thread: keyboards with the same rules share one keymap (-5%), the "screen
  share denied" text is rendered on first use so pango and fontconfig (about 130 ms of CPU and a thread) are not
  loaded at all (-3%), XCursor shapes are loaded on first use (-6%).
- Startup profile (compositor, about 0.6 s of CPU until IPC): the Mesa driver load in `CGBMAllocator` is 116 ms
  (`dlopen` 72 ms, drirc XML 15 ms, `crocus_screen_create` 12 ms), the first frame about 75 ms of which 44 ms are
  buffer allocations, Omarchy's Lua event handlers 37 ms, `libinput_udev_assign_seat` 51 ms, GSettings sync 23 ms.
  The very first frame takes a work buffer, later ones render directly. The black screen after that is Quickshell
  and Omarchy's login scripts (uwsm, powerprofilesctl, udiskie, hidden-entries, pacman, find on both cores).
- `libgallium` links `libLLVM`, which crocus does not use at runtime; loading it costs 19-27 ms per GL process.
  A crocus-only Mesa without LLVM needs `mesa_clc` at build time (LLVM, `libclc`, `LLVMSPIRVLib`), see the journal.
- Not worth it: `GALLIUM_THREAD=0` for the compositor (-1% on the GPU client only); glFlush waits for Mesa's
  threaded context on every frame anyway (`_tc_sync`).
- Measuring from the desktop: long ssh sessions end early, run measurements detached on the X200. `tl2.sh` (one
  startup timeline with instructions) and `abrun.sh` (A/B of packages with page flips) are in the journal's
  directory, they call `scripts/bench/measure.sh` copied to the X200.

## Profile guided builds (2026-11-12 and 2026-11-15)

`scripts/pgo/pgo.sh` builds the compositor with GCC's profile feedback (x86-64 only, the packages `scripts/deploy.sh`
and `scripts/release.sh` build are plain): `train DIR HOST...` builds an instrumented package, runs the session check
and one round of the benchmark with it on the machines and merges their counters; `build DIR` compiles with them
(`-fprofile-use`) and links the functions in the order of the training: the ones that ran first, the hottest in front,
their cold parts after them (`order.py`, the linker's `--section-ordering-file`), so the code a session uses is in few
pages.

The flags come from a makepkg plugin, `packaging/makepkg-pgo/pgo.sh` (since 2026-11-18), installed as root as
`/usr/share/makepkg/buildenv/pgo.sh`; `pgo.sh` stops when it is missing. It reads `PGO_GENERATE=DIR` (the instrumented
build, counters into DIR), `PGO_PROFILE=DIR` (the build with them) and `PGO_ORDER=FILE` (the section order) from the
environment and adds the flags to `CFLAGS`, `CXXFLAGS` and `LDFLAGS` of a package with `pgo` in its options. The
PKGBUILD asks for the option only when one of the variables is set, since makepkg refuses an option it does not know:
a plain build needs no plugin. Until then the PKGBUILD passed the flags to CMake (`HYPOLAND_PGO_FLAGS`), which gave
them to the compositor and the embedded aquamarine only; now hyprctl, start-hypoland and hypoland-kmsgrab are
instrumented and built with the profile too. The counter files are named after the object files' paths below makepkg's
`src/` instead of `src/build/`, so a profile trained before 2026-11-18 has `build#` in front of its names (rename them,
or train again).

Measured in the night of 2026-11-15 against the plain build of the same source (r992), alternating in fresh sessions,
9 to 14 sessions each on ten x86 machines, the profile from six of them (`test-results/night-20261115/summary.txt`):

- compositor CPU a frame: 4 to 6.5% less on every machine (median over the workloads, lianli most, samsung-i5 least)
- the binary's code in memory at the start of a session: 5.3 to 5.6 MiB against 8.7 to 8.9; Pss 5 to 7% lower
- latencies 0 to 2.5% lower, frame rates the same, every session check passed

Without the ordering, the profile alone gave the CPU but less of the memory (2026-11-12: 9.0 MiB of code to 5.4 - 6.0
with it, `test-results/pgo-20261112/summary.txt`).

- A profile belongs to its source: a function changed since the training is compiled without one (`build` says when
  the tree has moved on), so train again before building a release with it.
- A profile also belongs to its paths: GCC finds a function's counters by a checksum with the source file's path in
  it, and some sources are generated into the build directory (a build elsewhere stops with `source locations for
  function ... have changed`). So `pgo.sh` builds both the instrumented and the final package in one build directory
  of its own, `~/.cache/hypoland-pgo`. The instrumented compositor writes its counters to `/var/tmp/hypoland-pgo` when
  its session ends; its package has the release 0.1, and the training puts the machine's package back when the
  machine's pacman cache has it.
- CMake caches `CMAKE_EXE_LINKER_FLAGS`, so the PKGBUILD passes it on every build, with or without an order file.
- `gcovnames.py` reads which function each counter record belongs to from the instrumented binary (the profile only
  has checksums), `executed.py` lists the functions that ran with their counts and the order they first ran in.
