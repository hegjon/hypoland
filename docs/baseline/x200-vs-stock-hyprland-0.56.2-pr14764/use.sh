#!/bin/bash
# use.sh hypoland|pr : installs one variant and restarts the SDDM session
set -u
O=/usr/share/omarchy
case $1 in
hypoland)
    rm -f $O/default/hypr/intel-gles2.lua $O/bin/omarchy-hw-intel-gles2
    cp /root/ab/envs.lua.orig $O/default/hypr/envs.lua
    pacman -U --noconfirm --ask=4 /root/ab/hypoland-*.pkg.tar.zst >/dev/null 2>&1 || { echo "install failed"; exit 1; } ;;
pr)
    pacman -U --noconfirm --ask=4 /root/ab/hyprland-0.56.2-4-*.pkg.tar.zst /root/ab/omarchy-hyprland-titlebars-*.pkg.tar.zst >/dev/null 2>&1 || { echo "install failed"; exit 1; }
    install -m 755 /root/ab/pr/omarchy-hw-intel-gles2 $O/bin/
    install -m 644 /root/ab/pr/intel-gles2.lua $O/default/hypr/
    grep -q intel-gles2 $O/default/hypr/envs.lua ||
        sed -i 's/^require("default.hypr.nvidia")$/&\nrequire("default.hypr.intel-gles2")/' $O/default/hypr/envs.lua
    grep -q intel-gles2 $O/default/hypr/envs.lua || { echo "envs.lua not patched"; exit 1; } ;;
*) echo "usage: $0 hypoland|pr"; exit 2 ;;
esac
systemctl stop sddm
for _ in $(seq 1 100); do pgrep -x 'hypoland|Hyprland' >/dev/null || break; sleep 0.2; done
systemctl --user -M a@ stop graphical-session.target graphical-session-pre.target 2>/dev/null
sleep 2
systemctl start sddm
for _ in $(seq 1 180); do pgrep -x 'hypoland|Hyprland' >/dev/null && break; sleep 0.5; done
pgrep -ax 'hypoland|Hyprland' || echo "no compositor"
pacman -Q hypoland hyprland 2>/dev/null
pgrep -x 'hypoland|Hyprland' >/dev/null
