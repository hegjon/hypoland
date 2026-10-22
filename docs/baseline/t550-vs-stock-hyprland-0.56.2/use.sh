#!/bin/bash
# use.sh hypoland|hyprland : installs one variant and restarts the SDDM session
set -u
case $1 in
hypoland)
    pacman -U --noconfirm --ask=4 /root/ab/hypoland-*.pkg.tar.zst >/dev/null 2>&1 || { echo "install failed"; exit 1; } ;;
hyprland)
    pacman -U --noconfirm --ask=4 /var/cache/pacman/pkg/hyprland-0.56.2-4-x86_64.pkg.tar.zst /var/cache/pacman/pkg/omarchy-hyprland-titlebars-0.2.2-2-x86_64.pkg.tar.zst >/dev/null 2>&1 || { echo "install failed"; exit 1; } ;;
*) echo "usage: $0 hypoland|hyprland"; exit 2 ;;
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
