#!/bin/bash
# start.sh NAME UNTIL PKG_X86 [workloads] (night of 2026-11-25 to 26: the Hypoland 0.4.0 release packages, plain build, on x200 and turbox again (both hung in night-20261124-040's stock blocks) against Hyprland 0.57.2-2; turbox with pr-r300, the GLES 3 override on its R500 GPU) : copies abnight.sh, pr/ and scripts/bench of this tree to /root/abnight on
# the machines in HOSTS, installs the Hypoland package under test and starts abnight.sh detached, writing
# /root/abnight/NAME. PKG_X86 is the x86_64 package file on the desktop; the Galaxy Book takes GALAXY_PKG (a path on the
# machine, built there), macmini-m1 M1_PKG the same way. Stock Hyprland 0.57.2-2 and omarchy-hyprland-titlebars 0.4.0-1 (the omarchy repository) must be
# in each machine's pacman cache (pacman -Sw hyprland omarchy-hyprland-titlebars).
NAME=$1 UNTIL=$2 PKG=$3 WL=${4:-}
C=/var/cache/pacman/pkg
D=$(dirname "$(readlink -f "$0")")
cd "${TREE:-$D/../..}" && [ -d scripts/bench ] || exit 1
echo "scripts/bench from $(pwd) at $(git log --oneline -1 | cut -c1-60)"
set -o pipefail
for h in ${HOSTS:-x200 turbox}; do
    case $h in
        turbox) HYP=/root/abnight/${PKG##*/}; HYPR="$C/hyprland-0.57.2-2-x86_64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.4.0-1-x86_64.pkg.tar.zst"; PR=pr-r300 ;;
        x200) HYP=/root/abnight/${PKG##*/}; HYPR="$C/hyprland-0.57.2-2-x86_64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.4.0-1-x86_64.pkg.tar.zst"; PR=pr ;;
        galaxybook) HYP=${GALAXY_PKG:?}; HYPR="$C/hyprland-0.57.2-2-aarch64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.4.0-1-aarch64.pkg.tar.zst"; PR="" ;;
        macmini-m1) HYP=${M1_PKG:?}; HYPR="$C/hyprland-0.57.2-2-aarch64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.4.0-1-aarch64.pkg.tar.zst"; PR="" ;;
        *) HYP=/root/abnight/${PKG##*/}; HYPR="$C/hyprland-0.57.2-2-x86_64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.4.0-1-x86_64.pkg.tar.zst"; PR="" ;;
    esac
    printf '%-14s ' $h
    tar -C scripts -cz bench | ssh -o BatchMode=yes root@$h "rm -rf /root/abnight/bench /root/abnight/pr /root/abnight/pr-r300 && mkdir -p /root/abnight && tar -xz -C /root/abnight" || { echo "copy failed"; continue; }
    scp -q "$D/abnight.sh" root@$h:/root/abnight/ && scp -q -r "$D/pr" "$D/pr-r300" root@$h:/root/abnight/ || { echo "copy failed"; continue; }
    if [ $h != galaxybook ] && [ $h != macmini-m1 ]; then
        scp -q "$PKG" root@$h:/root/abnight/ || { echo "package copy failed"; continue; }
    fi
    ssh -o BatchMode=yes root@$h "pacman -U --noconfirm --ask=4 $HYP >/dev/null 2>&1 && pacman -Q hypoland | tr '\n' ' '" || { echo "install failed"; continue; }
    X=
    [ $h = turbox ] && X="ABNIGHT_NO_STARTUP=1 ABNIGHT_READY_S=300 ABNIGHT_SETTLE_LOAD=2"
    ssh -o BatchMode=yes root@$h "ls $HYP $HYPR >/dev/null || exit 1; ABNIGHT_CHECK=${ABNIGHT_CHECK-1} ABNIGHT_NO_STARTUP=${ABNIGHT_NO_STARTUP-} ABNIGHT_ONLY=${ABNIGHT_ONLY-} $X ABNIGHT_WORKLOADS='$WL' setsid -f nohup bash /root/abnight/abnight.sh /root/abnight/$NAME '$UNTIL' $HYP '$HYPR' $PR >/dev/null 2>&1 </dev/null; sleep 2; tail -1 /root/abnight/$NAME/log"
done
