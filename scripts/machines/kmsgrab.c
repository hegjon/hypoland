// Saves the buffer the display currently scans out as a PPM image. Unlike a screenshot through the compositor,
// this shows exactly what reaches the screen, and does not change how the compositor renders the frame.
// Needs root (DRM_IOCTL_MODE_GETFB2 only hands out buffer handles to CAP_SYS_ADMIN).
//
// Build: gcc -O2 -o kmsgrab kmsgrab.c $(pkg-config --cflags --libs libdrm gbm)
// Usage: kmsgrab out.ppm
#include <fcntl.h>
#include <gbm.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s out.ppm\n", argv[0]);
        return 2;
    }

    for (int card = 0; card < 8; card++) {
        char path[64];
        snprintf(path, sizeof(path), "/dev/dri/card%d", card);
        int fd = open(path, O_RDWR | O_CLOEXEC);
        if (fd < 0)
            continue;

        drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
        drmModePlaneRes* planes = drmModeGetPlaneResources(fd);
        if (!planes) {
            close(fd);
            continue;
        }

        for (uint32_t i = 0; i < planes->count_planes; i++) {
            drmModePlane* plane = drmModeGetPlane(fd, planes->planes[i]);
            if (!plane || !plane->fb_id || !plane->crtc_id) {
                drmModeFreePlane(plane);
                continue;
            }

            drmModeFB2* fb = drmModeGetFB2(fd, plane->fb_id);
            drmModeFreePlane(plane);
            if (!fb || !fb->handles[0] || fb->width < 320) { // skip cursor planes
                drmModeFreeFB2(fb);
                continue;
            }

            int dmabuf = -1;
            if (drmPrimeHandleToFD(fd, fb->handles[0], DRM_CLOEXEC, &dmabuf)) {
                perror("drmPrimeHandleToFD");
                return 1;
            }

            struct gbm_device*                 gbm  = gbm_create_device(fd);
            struct gbm_import_fd_modifier_data data = {
                .width    = fb->width,
                .height   = fb->height,
                .format   = fb->pixel_format,
                .num_fds  = 1,
                .fds      = {dmabuf},
                .strides  = {(int)fb->pitches[0]},
                .offsets  = {(int)fb->offsets[0]},
                .modifier = fb->modifier,
            };
            struct gbm_bo* bo = gbm_bo_import(gbm, GBM_BO_IMPORT_FD_MODIFIER, &data, 0);
            if (!bo) {
                fprintf(stderr, "gbm_bo_import failed\n");
                return 1;
            }

            uint32_t stride  = 0;
            void*    mapData = NULL;
            uint8_t* px      = gbm_bo_map(bo, 0, 0, fb->width, fb->height, GBM_BO_TRANSFER_READ, &stride, &mapData);
            if (!px) {
                fprintf(stderr, "gbm_bo_map failed\n");
                return 1;
            }

            // Copy the buffer out first and convert afterwards: the compositor draws into this buffer again a few
            // frames later, so a slow read picks up half-drawn frames. Freeze animated clients for exact results.
            uint8_t* copy = malloc((size_t)stride * fb->height);
            memcpy(copy, px, (size_t)stride * fb->height);
            gbm_bo_unmap(bo, mapData);

            uint8_t* rgb = malloc((size_t)fb->width * fb->height * 3);
            for (uint32_t y = 0; y < fb->height; y++) {
                for (uint32_t x = 0; x < fb->width; x++) {
                    const uint8_t* p = copy + y * stride + x * 4; // XRGB8888 / ARGB8888, little endian: B G R X
                    uint8_t*       o = rgb + ((size_t)y * fb->width + x) * 3;
                    o[0]             = p[2];
                    o[1]             = p[1];
                    o[2]             = p[0];
                }
            }

            FILE* out = fopen(argv[1], "wb");
            fprintf(out, "P6\n%u %u\n255\n", fb->width, fb->height);
            fwrite(rgb, 3, (size_t)fb->width * fb->height, out);
            fclose(out);
            printf("%s: %ux%u fb %u modifier 0x%llx\n", path, fb->width, fb->height, fb->fb_id, (unsigned long long)fb->modifier);

            gbm_bo_destroy(bo);
            gbm_device_destroy(gbm);
            close(dmabuf);
            return 0;
        }
        close(fd);
    }

    fprintf(stderr, "no scanout buffer found\n");
    return 1;
}
