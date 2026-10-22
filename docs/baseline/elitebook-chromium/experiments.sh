#!/bin/bash
# Chromium corruption on the EliteBook (r600): experiments to run as root on the EliteBook
# AFTER the soak has finished (no soak.sh running). Written 2026-10-22.
#
#   scp docs/baseline/elitebook-chromium/experiments.sh root@elitebook:/tmp/ && ssh root@elitebook bash /tmp/experiments.sh all
#
# Each experiment reproduces the known trigger (open a foot window next to Chromium, close it,
# so Chromium is resized back to full width), freezes Chromium 1 s later and captures the screen
# with kmsgrab AND grim at the same moment. The pair tells buffer content apart from screen content:
#   kmsgrab bad, grim good  -> the screen was not repainted (compositor damage / buffer age)
#   both bad                -> Chromium committed an incomplete buffer (Chromium or r600 side)
# Results go to /tmp/exp/<name>-{kms,grim}.png and the pixel difference is printed.
#
# Results 2026-10-22: baseline corrupt (kmsgrab differs from grim, grim is right, the screen is right again after
# any full repaint); corrupt as well with --disable-partial-swap, --disable-gpu-rasterization, --use-angle=gles,
# mesa_glthread=false and inside nested weston; grim bursts while Chromium runs are clean except right after a
# commit. A compositor trace (temporary code in CWLSurfaceResource's commit, removed again) showed that every
# Chromium commit arrived without a pending GPU write fence on the dmabuf while Quickshell's commits had one,
# and that writes on the committed buffer appeared a few ms later: Chromium submits its rendering after the
# commit when the driver has no native fences. Not a compositor bug. See MACHINES.md.
set -u
PID=$(pgrep -x hypoland | head -1)
SIG=$(runuser -u a -- env XDG_RUNTIME_DIR=/run/user/1000 timeout 10 hyprctl instances | awk -v pid="$PID" '/^instance/{s=$2; sub(":","",s)} /pid:/ && $2==pid {print s}')
[ -n "$SIG" ] || { echo "no running compositor instance"; exit 1; }
U() { runuser -u a -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$SIG "$@"; }
H() { U timeout 10 hyprctl "$@"; }
page="data:text/html,<body style='background:linear-gradient(90deg,red,blue)'><marquee scrollamount=20 style='font:60px sans-serif;color:white'>Hypoland</marquee><div style='animation:s 2s linear infinite;width:200px;height:200px;background:lime'></div><style>@keyframes s{to{transform:translateX(900px) rotate(360deg)}}</style>"
install -d -m 1777 /tmp/exp
pgrep -f soak.sh >/dev/null && { echo "soak.sh is still running, refusing"; exit 1; }
cleanup() { pkill -CONT -f exp-chr 2>/dev/null; U systemctl --user stop exp-chr exp-foot exp-weston 2>/dev/null; U systemctl --user reset-failed 2>/dev/null; }
trap cleanup EXIT

capture() { # name: kmsgrab and grim as close together as possible
    hypoland-kmsgrab /tmp/exp/$1-kms.ppm >/dev/null 2>&1 &
    U timeout 15 grim /tmp/exp/$1-grim.png
    wait
    magick /tmp/exp/$1-kms.ppm /tmp/exp/$1-kms.png; rm -f /tmp/exp/$1-kms.ppm
    echo "$1: differing pixels kmsgrab vs grim: $(compare -metric AE /tmp/exp/$1-kms.png /tmp/exp/$1-grim.png /dev/null 2>&1)"
}

trigger() { # $1 name, $2.. extra chromium flags; env WAYLAND_DISPLAY may be overridden by WLD
    rm -rf /tmp/exp-chr; install -d -o a /tmp/exp-chr
    U systemd-run --user -q --unit=exp-chr -E WAYLAND_DISPLAY=${WLD:-wayland-1} ${CHR_ENV:-} chromium "${@:2}" --ozone-platform=wayland --no-first-run --user-data-dir=/tmp/exp-chr "$page"
    sleep 15
    U systemd-run --user -q --unit=exp-foot -E WAYLAND_DISPLAY=${WLD:-wayland-1} foot -e sleep 600
    sleep 4
    U systemctl --user stop exp-foot
    if [ -n "${BURST:-}" ]; then # unfrozen captures every ~0.1 s right after the resize
        local i; for i in 1 2 3 4 5 6 7 8; do hypoland-kmsgrab /tmp/exp/$1-burst$i.ppm >/dev/null 2>&1; magick /tmp/exp/$1-burst$i.ppm /tmp/exp/$1-burst$i.png; rm -f /tmp/exp/$1-burst$i.ppm; done
    fi
    sleep 1
    pkill -STOP -f exp-chr
    sleep 0.5
    capture "$1"
    sleep 3
    capture "$1-later"
    pkill -CONT -f exp-chr
    U systemctl --user stop exp-chr
    sleep 2
}

e_baseline() { trigger baseline; }
e_nodamage() { # full redraw every frame: if the corruption is gone, the screen was stale, not the buffer
    H eval 'hl.config({debug={damage_tracking=0}})'
    trigger nodamage
    H eval 'hl.config({debug={damage_tracking=2}})'
}
e_nested_weston() { # Chromium inside nested weston: corruption there too -> not a Hyprland/Hypoland problem
    U systemd-run --user -q --unit=exp-weston -E WAYLAND_DISPLAY=wayland-1 weston --backend=wayland --socket=wayland-9 --width=1500 --height=850
    sleep 5
    WLD=wayland-9 trigger weston
    U systemctl --user stop exp-weston
}
e_debug() { # protocol log of the trigger: buffer type (dmabuf or shm), sizes, damage rectangles
    CHR_ENV="-E WAYLAND_DEBUG=1 -p StandardError=file:/tmp/exp/chromium-wayland-debug.log" trigger debug
    echo "protocol log: /tmp/exp/chromium-wayland-debug.log ($(grep -c 'wl_surface.*damage' /tmp/exp/chromium-wayland-debug.log) damage lines, dmabuf: $(grep -c 'zwp_linux_buffer_params' /tmp/exp/chromium-wayland-debug.log), shm: $(grep -c 'wl_shm_pool' /tmp/exp/chromium-wayland-debug.log))"
}
e_nopartial() { trigger nopartial --disable-partial-swap; } # Chromium redraws its whole buffer every frame
e_burst() { BURST=1 trigger burst; }
e_grimburst() { # grim (full redraw into the work buffer) 10 times while Chromium runs, right after the resize
    rm -rf /tmp/exp-chr; install -d -o a /tmp/exp-chr
    U systemd-run --user -q --unit=exp-chr chromium --ozone-platform=wayland --no-first-run --user-data-dir=/tmp/exp-chr "$page"
    sleep 15
    U systemd-run --user -q --unit=exp-foot foot -e sleep 600
    sleep 4
    U systemctl --user stop exp-foot
    local i; for i in 1 2 3 4 5 6 7 8 9 10; do U timeout 15 grim /tmp/exp/grimburst$i.png; hypoland-kmsgrab /tmp/exp/kmsburst$i.ppm >/dev/null 2>&1; done
    for i in 1 2 3 4 5 6 7 8 9 10; do magick /tmp/exp/kmsburst$i.ppm /tmp/exp/kmsburst$i.png; rm -f /tmp/exp/kmsburst$i.ppm; done
    U systemctl --user stop exp-chr
}
e_variant() { trigger "$1-1" "${@:2}"; trigger "$1-2" "${@:2}"; } # name, chromium flags; twice (three rotating buffers)

case "${1:-all}" in
    all) e_baseline; e_nodamage; e_nested_weston; e_debug; e_nopartial ;;
    variant) e_variant "${@:2}" ;;
    *) "e_$1" ;;
esac
ls -la /tmp/exp
