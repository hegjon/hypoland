# Render checks

Engineering notes of Hypoland, moved out of `AGENTS.md` on 2026-11-12 unchanged. `AGENTS.md` has the rules and
the current state; the notes say what was tried, measured and dropped. Add new findings here, with the date.

`scripts/bench/clients/render.py`, the nested runs and the bugs they found.

- Render checks (2026-10-31, asked for by the user as small tests that rendering is correct; `scripts/bench/clients/render.py`,
  run by the session check, `check_render()`): two shm windows of the check's own, drawn in 7x7 blocks it knows pixel by
  pixel, on an empty workspace: a whole buffer, 24 frames of four small damaged rectangles, 12 new buffers further on in
  the pool with only a band damaged (as foot's new buffer per line), and a dialog of the first (`set_parent`, it floats
  from the start) with a half transparent band, moved and closed. At every step the focused window has to show exactly
  what it drew (an integer scale only; over the other window its transparent band to within a step of premultiplied
  alpha), and the screen has to be what a full repaint of the same scene shows: the shell is frozen (SIGSTOP), the screen
  read from the scanned-out buffer (`hypoland-kmsgrab`, grim where it cannot), the workspace switched away and back, and
  read again. The pointer is parked in the monitor's corner and the compositor's own notifications dismissed first.
  `--selftest` commits a change without its damage, which the checks have to catch (they do, 4096 pixels). The first
  runs found two bugs: on the X200 a zero-copy window's small updates did not reach the screen until something else
  redrew the place (245000 pixels stale after 24 frames of rectangles; the same with `HYPOLAND_SHM_ZEROCOPY=force`, none
  with `=0`): `CWLSurfaceResource::flushCPUWrites()` took the commit's buffer damage (`accumulateBufferDamage()` clears
  what it returns for a buffer that is not synchronous), so the window's damage of the monitors after the commit
  (`CWLSurface::computeDamage()`) found none; it reads it now (`SSurfaceState::pendingBufferDamage()`), since the zero
  copy of 2026-10-29 it had done so for every zero-copy shm buffer. And on the Galaxy Book (freedreno) every edge in a
  window's content was a step off and 433 pixels next to damaged rectangles differed from a full repaint: surfaces are
  sampled with the linear filter, and freedreno puts the texel centers a hair off, so a sliver of the neighbours mixed in
  and a pixel next to a damaged area kept the mix with what its neighbour showed before; a surface drawn texel for texel
  (its box in pixels the texture's size, the whole texture, no buffer transform, no render modifier) takes the nearest
  texel now (`IElementRenderer::drawSurface()`), which Intel and AMD showed the same way already. On the T550 and the T460s
  (scale 1.5) 9000 to 24000 pixels differed from a full repaint after the small updates: one-pixel rims around every
  updated rectangle, up to 67 steps off, since a scaled surface is filtered and the pixels next to its damage take in the
  texels inside; a surface not drawn texel for texel damages `ceil(scale)` pixels more all round now
  (`IHyprRenderer::damageSurface()`), and both pass. The pixel checks need an integer scale and are skipped at 1.5.
  Since 2026-11-01 a surface counts as texel for texel by its texel's size on the monitor (one pixel, an integer scale,
  no viewport source), not by having no viewport: Qt sets a viewport destination on every window, and the XPS (scale
  2) grew every small update of Qt's windows, with `CRegion::expand()`, which unions the grown rectangles one at a
  time, the square of their number: 39% of the compositor's time under `qt-software-sprites` (a profile with the debug
  package). The growth that remains makes the region in one go (`expandRegion()`, `pixman_region32_init_rects`). XPS,
  3 fresh sessions each: the sprites 14.3 -> 8.0% (2.38 -> 1.33 ms a frame), `qt-software-scroll` 4.15 -> 3.9,
  `terminal-scroll` 3.2 -> 3.0, GTK 3 the same; the T460s (1.5, grown as before) the same
  (`test-results/damage-20261101/`). Nested render checks pass at 1, 2 and 1.6, `--selftest` fails.
  The same evening (asked for again by the user before a weekend away) more steps: a desynchronized subsurface over the first
  window, drawn by itself in small rectangles, moved by the parent's commit and destroyed; two subsurfaces scaled by a
  viewport (a 34x26 buffer shown at 157x122, a 301x233 one at the same size) with small damage; an xdg popup without a
  grab, opened and closed; an overlay layer (`zwlr_layer_shell_v1`, 400x240, the top third opaque, the rest clear) left
  alone until the alpha bounds clip it, then drawn into where it was clear with only that damaged, then closed; and the
  dialog shrinking itself to half its size. Three bugs, all upstream's: a subsurface moved by its parent's commit and then
  destroyed stayed on the screen (`CSubsurface::damageLastArea()` damages where it was at its own last commit, the unmap
  now damages where it is drawn too; `damageLastArea()` computed the larger of the two sizes and used neither); a floating
  window whose surface shrank by itself left its old area (a window's commit damaged the surface's damage only, a size
  change damages the window and the old surface box now, `CWindow::m_lastCommitSize`, set at the map as well); and a
  buffer magnified by a viewport left a rim of old pixels around its updates, half a magnified texel wide
  (`damageSurface()` expands by `ceil(max(scale, texel / 2 + 1))` monitor pixels now, the texel's size from the viewport
  or buffer scale). Then two more steps, a subsurface whose buffer is turned by a quarter (`set_buffer_transform` 90) and
  one cut out of a larger buffer and stretched (a viewport source at 30,20 60x45 of a 120x90 buffer, shown at 157x122),
  and a fourth bug, upstream's as well: `CWLSurface::computeDamage()` turned the buffer damage and then scaled it by
  the surface's size over the unturned buffer size, which stretched one axis and squashed the other, and it cut the
  source out in surface units without taking its offset off; it works in the turned buffer's pixels now, as wlroots
  does, and most updates of the turned subsurface no longer miss the screen. Not a bug of Hypoland's: a window's rounding rounds each of its subsurfaces at their own corners, also
  in the middle of the window (upstream does the same), so with rounding on the pixel checks leave the subsurfaces'
  corner squares out. A capture of its own each time, as grim takes, has the compositor repaint the whole monitor first
  (`CScreencopyFrame` without damage, and a share's first frame, `!m_sharing`, which a share counts again 0.5 s after its
  last frame), so the repaint checks saw nothing through grim. Where kmsgrab cannot read the screen (radeon's legacy
  modesetting, a headless output, more than one monitor) the check captures the compositor's frames without a pause on
  its own connection (`--grab screencopy`, `Sharing`): a `copy_with_damage` frame is always pending, and the pointer moves
  a pixel in its corner when nothing else draws, so every frame is an incremental one of the work buffer, which damage
  keeps up like the screen's buffers; the pointer's corner is left out of the comparison.
  `scripts/bench/render-nested.sh [--scale S] [--transform T] [--config extra.lua]... [--binary PATH]` runs it against a
  compositor of the tree started inside the desktop's session with one headless output (the nested window switched off,
  so the desktop's screen does not matter), in about two minutes: before the fixes it failed exactly the four bugs' steps
  at scale 1, after them it passes at 1, 2 and 1.6, with gaps, borders, rounding and animations as well. It
  passes as well on turned outputs (2026-11-01: transforms 1, 2, 3, 5 and 7, the frames through the work buffer, at scales
  1, 2 and 1.6) and with the blur of Omarchy's Glassy theme (`default/hypr/glass.lua`: size 4, 2 passes, noise; the
  dialog's half transparent band shows the blur there, so its translucent pixels are left out); `--selftest` fails 7 steps
  on both, so neither repaints everything. The configs are in `scripts/bench/render-configs/` since 2026-11-02 (`base.lua`:
  gaps, borders, rounding 8 and Hyprland 0.57.0's example animations; `glassy.lua`, `shadows.lua` with a range of 20 (removed
  with the shadows on 2026-11-12), `dim.lua` with `dim_inactive` and an inactive opacity of 0.8, where translucent pixels are left out as under blur, and
  `titlebars.lua` as Omarchy sets them up), `--config` can come more than once, and `scripts/bench/render-matrix.sh`
  runs the nested checks over the effects, scales 1, 2 and 1.6 and turned outputs in one go (`--quick`: scale 1 with each
  effect, about 13 minutes). The shadows and the titlebars found a bug of the fade-out (a closing window's fade below).
  Compositor frames come in the monitor's own coordinates, turned; a capture of the scanned-out buffer of a turned monitor
  would not be, and the pixel checks are skipped for it. Steps that found nothing:
  the popup repositioned (`xdg_popup.reposition`), the layer moved by its margin while clipped and made smaller, a popup of
  the layer while it is clipped (2026-11-02, as Omarchy's bar opens a menu; shown whole past the clip and the layer), the dialog
  resized by the compositor (2026-11-02, with the windows animation) and given a longer title (its titlebar redrawn), a
  window group (2026-11-02: the group bar, a second window into it, the tabs switched, the shown one closed, ungrouped), a
  floating window in a special workspace (2026-11-02, Omarchy's scratchpad: shown over the dimmed workspace, small updates
  there, hidden; while it is shown the full repaint is the special workspace hidden and shown again, since Omarchy hides it
  on a workspace switch), the first window fullscreen and back (it has to be fullscreen at the monitor's logical size, or
  the step fails). And an opaque region (2026-11-02, `wl_surface.set_opaque_region`): the dialog drawn opaque and saying
  so, then a band of it cleared and the region shrunk to the parts around it, only the band damaged. It found a fifth bug,
  upstream's: `CWindowPresentation::opaque()` compared the extents of the opaque region with the buffer's size, so a region
  with a hole counted as opaque at scale 1, and the window was drawn without blending where nothing rounds it (Omarchy's
  square corners) and without blur, its clear band black (in a full repaint too); at scale 2 no region counted. The region
  has to cover the surface's box now, both in surface coordinates. With them the full matrix passes, 68 checks a case
  (2026-11-02). The same morning the deploy check on the T550 and the T460s (1920x1080 at 1.5, Omarchy's group bar) failed
  `grouped` with a row of the group bar left on the screen, which nested runs never show (llvmpipe breaks a tie on a pixel
  centre on the other side than iris): upstream's group bar and the titlebars rounded their box in logical pixels, so while
  a window slid at a fractional scale the bar was drawn up to half a logical pixel outside the window's damage (at logical
  35, pixel 52.5, with the window at 35.4), and `damageBox()` / `damageWindow()` rounded a box at a half pixel to start a
  row after the one iris draws it on. Both decorations keep the fractional box and round in the monitor's pixels as the
  border does, and box damage takes every pixel a box touches (`Math::coveredPixels()`). `render-configs/omarchy.lua` is
  Omarchy's own look (square corners, its group bar and animations); the matrix runs it at 1 and 1.5 and the base at 1.5. The EGL import of a udmabuf fails there, so zero copy is the machines' to check. lianli (r600)
  failed the pixel checks with zero copy and passed them with `HYPOLAND_SHM_ZEROCOPY=0` (2026-10-31 and 11-01): the radeon
  kernel driver refuses a command stream that samples a linear texture whose rows are not a multiple of 64 pixels
  (`evergreen_surface_check_linear_aligned: texture pitch 1896 invalid must be aligned with 64`, then `Invalid command
  stream!` in the kernel log) and drops the frame's draws with it, and Mesa imports such a udmabuf without complaint, so
  the check's window (1896 pixels wide) vanished after the first workspace switch and stayed off the screen, also through
  grim, until it attached a new buffer. foot and the night's workloads did not hit it (none in the kernel log of the
  night of 2026-10-31); the render checks had about 5900 command streams refused since 2026-10-31. Since 2026-11-01 radeon samples in place only
  buffers whose rows are a multiple of 256 bytes and that start 256 bytes aligned (`CWLSHMBuffer::tryZeroCopy()`); the
  rest are copied into the dumb buffers, whose rows the kernel aligns. lianli passes all 72 checks with zero copy on.
  On the Galaxy Book (freedreno) the copies of a frame that went through the work buffer (to the screen, into the mirror
  and from the mirror into a screen capture) were filtered linearly at the same size, and freedreno's texel centers a
  hair off put one of the two triangles of each copy a step off: grim's screenshot failed the pixel checks, and the screen
  kept the copy's pixels outside later damage (`rectangles` failed after the screenshot step). Those copies take the
  nearest texel when they are texel for texel (`CHyprOpenGLImpl` at the end of a frame, `CScreenshareFrame::renderMonitor()`).
  That left the work buffer's texture on the nearest texel (a texture keeps its filters), and the blur set only the
  minification filter of what it samples while its upsample magnifies: after a screenshot the blur would have come
  out blocky (found by a review the same day, not seen on a machine). The blur sets both filters now, and the screen
  shader's pass keeps the filter it had.
  The last 29 pixels there, a step off in columns next to the small updates of the subsurface turned by a quarter, came
  from the same filter: a turned buffer is texel for texel at its turned size, but only unturned ones took the nearest
  texel; they all do since 2026-11-01 (`IElementRenderer::drawSurface()`), and the Galaxy Book passes all 71 checks.
  Three more bugs, upstream's, found on samsung-i5 (scale 1.5) on 2026-11-11 after the user photographed vkmark's cube in
  the top left two thirds of the screen and old frames of its horse below: a main surface smaller than its window counts
  as small and is drawn at its own size (`CSurfacePassElement::getTexBox()`), which was taken from the buffer
  (`getViewporterCorrectedSize()`, no buffer scale), so vkmark's 1920x1080 buffer at buffer scale 2 (wl_output's integer
  scale; a 960x540 surface in a 1280x720 fullscreen window) was drawn twice its size, cut to the window, while its damage
  covered its own size; it takes the surface's logical size now (render check `fullscreen buffer scale`, which fails at
  1.6 nested without it, 50726 pixels). A main surface smaller than its window and not drawn at its own size, which the
  renderer stretches or whose edge pixels it repeats out to the window's edges (`render:expand_undersized_textures`), as
  a window that went fullscreen until the client draws at the new size, damaged only its own size: its commit damages the
  whole window then, and a change between the two ways as well (`CWindow`, `m_lastCommitOwnSize`; check `fullscreen not
  followed`, which fails at scale 1 too). And the pass hid what is under an opaque box by rounding it to the nearest
  pixel, so at a fractional scale a pixel row the box covers in part counted as covered, the window under was not drawn
  there and the surface's part transparent edge pixel blended over the frame's old one (`opaque region shrunk` failed on
  samsung-i5 with a row of old colour at each edge of the band); occlusion takes the pixels a box covers whole now
  (`Math::wholePixels()`), and a surface drawn with the linear filter gives up the half texel and half pixel at its opaque
  region's edge (`CSurfacePassElement::filteredEdge()`). Real programs were checked the same way that day with a
  stale-pixel detector of the session's scratchpad (`/tmp/phx-x2/scripts/stale.py`: the program and the shell frozen, the
  scanout read, a workspace switch away and back, read again): about 150 samples on samsung-i5 of terminals, toolkits,
  Chromium, video, the games, Omarchy's menu and notifications, scale changes, window swaps, moves and resizes,
  screenshots and fullscreen toggles found nothing more.
