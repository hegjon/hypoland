# Wayland: GPU-rendered frames are committed before their rendering is submitted on drivers without EGL_ANDROID_native_fence_sync (stale/garbage regions in the window)

## Summary

NOTE: I used an AI coding tool to gather the captures, the protocol log and the compositor-side trace below; the description is mine.

On a GPU whose Mesa driver has no `EGL_ANDROID_native_fence_sync` (AMD Radeon HD 6470M, Mesa `r600`,
kernel driver `radeon`), Chromium's Wayland dmabuf path commits a buffer before the GPU work that fills it has
reached the kernel. The compositor composites the buffer as soon as it is committed, and because there is no
pending GPU write on the dmabuf at that moment, implicit sync cannot order the read after the write. The screen
then shows uninitialised memory, freed pages of earlier buffers or stale content in the regions Chromium
damaged, until something repaints the whole screen. A compositor that renders a few milliseconds later shows the
frame correctly.

The visible trigger is a window resize (for example another window opening next to Chromium in a tiling
compositor and closing again), after which the animated parts of the page stay corrupt.

## Environment

- Chromium 155.0.8059.84 (Arch Linux package), `--ozone-platform=wayland`, GPU compositing on (default here,
  the GPU has GLES 3)
- GPU: AMD Radeon HD 6470M (TeraScale 2, 1002:6760), Mesa 26.2.5 `r600`, kernel 7.2.8 `radeon` driver.
  No `EGL_ANDROID_native_fence_sync`, no DRM syncobj support (`DRM_CAP_SYNCOBJ_TIMELINE` is 0), so the
  compositor offers neither `wp_linux_drm_syncobj_manager_v1` nor `zwp_linux_explicit_synchronization_v1`
- Compositor: Hyprland 0.56.2 (wayland 1.26.0)
- CPU: Core i5-2450M, 2 cores / 4 threads

## Steps to reproduce

1. Start Chromium on Wayland with GPU compositing on this kind of GPU with an animated page, for example
   `data:text/html,<body style='background:linear-gradient(90deg,red,blue)'><marquee scrollamount=20 style='font:60px sans-serif;color:white'>Hello</marquee><div style='animation:s 2s linear infinite;width:200px;height:200px;background:lime'></div><style>@keyframes s{to{transform:translateX(900px) rotate(360deg)}}</style>`
2. Open a second window next to it so that Chromium is resized (a tiling compositor does that), wait a few
   seconds, close the second window so Chromium is resized back.
3. Look at the band of the page where the marquee and the animated square move.

## Expected

The page animates normally after the resize.

## Actual

The band that Chromium damages every frame shows garbage: the compositor's wallpaper (the fresh buffer is read
as fully transparent), scrambled pieces of the previous, smaller frames (the freed pages of the old buffers) or
slices of the square from earlier frames. A screenshot taken through the compositor's screen-copy path a moment
later is correct, and after it the screen is correct too.

## Evidence

All of this was measured on the machine above, with Chromium frozen (`SIGSTOP`) at capture time where noted.

- A capture of the scanout buffer (kmsgrab) and a compositor screenshot (`grim`, which forces a full
  re-render from the current client buffers) taken at the same moment differ by about 150,000 pixels inside
  Chromium's window. The screenshot is right, the screen is wrong. Three seconds later both are identical.
- A burst of ten screenshots while Chromium runs is correct except for the one taken right after a commit.
- `WAYLAND_DEBUG=1`: Chromium uses `zwp_linux_dmabuf_v1` buffers (AR24, three in rotation, after the resize
  2048x850 with a `wp_viewport` source of 1576x850), reports partial `wl_surface.damage` per frame, and
  receives `wl_buffer.release` about 0.3 ms after each commit. No explicit sync protocol is bound.
- A temporary trace in the compositor's `wl_surface.commit` handler exported the dmabuf's pending write
  fences (`DMA_BUF_IOCTL_EXPORT_SYNC_FILE` / poll for `POLLIN`) at commit time. 421 of 421 Chromium commits
  arrived with no pending GPU write on the buffer. For comparison, the Quickshell shell's dmabuf commits on the
  same machine had a pending write in 32 of 33 cases. Probing the same buffer again 1, 2, 4, 8, 16 and 32 ms
  after Chromium's commit found a pending write at +4 ms in 13 of 232 cases and at +8 ms in 12 of 232, i.e.
  writes to the committed buffer land a few milliseconds after the commit.
- The compositor (Hyprland) already defers a commit until the dmabuf's pending writes have signalled, which
  cannot help when the write is not there yet at commit time.
- Mesa's `glFlush` is synchronous in a context that has imported an EGLImage (`HasExternallySharedImages`),
  and the `radeon` kernel driver executes the GFX ring in order and syncs readers to writers through the
  dma-buf reservation object, so once the rendering is in the kernel before the commit, the compositor cannot
  read too early. The ordering is therefore broken before the kernel.

Still reproduces with `--disable-partial-swap`, `--disable-gpu-rasterization`, `--use-angle=gles`,
`mesa_glthread=false`, and with Chromium running inside a nested Weston. Does not reproduce with
`--disable-gpu` or `--disable-gpu-compositing` (shm buffers), nor with `weston-simple-egl` on the same
compositor. Does not reproduce on an Intel HD 5500 (`iris`), which has native fence sync.

## Analysis

`GLOzoneImageRepresentation::EndAccess` (gpu/command_buffer/service/shared_image/gl_ozone_image_representation.cc)
creates a GPU fence for the buffer only when `gl::GLFence::IsGpuFenceSupported()` is true, and otherwise
passes an empty fence with the comment that the code "may rely on implicit synchronization in case GpuFence
support is not available". `GbmSurfacelessWayland::Present` then calls `glFlush()` and submits the frame
immediately because there is no fence to wait for. Implicit synchronization only works if the GPU work is
submitted before the buffer is committed; the measurements show it is not, so on these drivers Chromium
hands the compositor a buffer whose rendering is still pending in user space.

I have not pinned down which layer defers the submission past the commit (Skia's flush/submit, ANGLE's
handling of `glFlush`, or the thread the flush runs on); the fix does not depend on that.

## Suggested fix

When GPU fences are unsupported, wait for GPU completion before the commit: create an `EGL_KHR_fence_sync`
fence (available on r600 and everywhere else) at EndAccess / Present time and client-wait on it on the
presenter's worker thread, as the `use_egl_fence_sync_` path in `GbmSurfacelessWayland` and the comment in
`OutputPresenterGL::InitializeCapabilities` ("the Presenter commonly waits on CPU for GPU to finish with a
(EGL) fence + a worker thread") suggest it once did, or at least `glFinish()` before the commit. This costs
a frame of latency on these drivers, which is unavoidable without fences.

## Workaround

`--disable-gpu-compositing` (or `--disable-gpu`).
