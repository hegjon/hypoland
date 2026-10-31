#!/bin/bash
# start.sh NAME UNTIL PKG_X86 [workloads] : copies abnight.sh, pr/ and scripts/bench of this tree to /root/abnight on
# the machines in HOSTS, installs the Hypoland package under test and starts abnight.sh detached, writing
# /root/abnight/NAME. PKG_X86 is the x86_64 package file on the desktop; the Galaxy Book takes GALAXY_PKG (a path on the
# machine, built there). Stock Hyprland 0.57.0-2 and omarchy-hyprland-titlebars 0.3.0-2 (the omarchy repository) must be
# in each machine's pacman cache (pacman -Sw hyprland omarchy-hyprland-titlebars).
NAME=$1 UNTIL=$2 PKG=$3 WL=${4:-}
C=/var/cache/pacman/pkg
D=$(dirname "$(readlink -f "$0")")
cd "$D/../../.." || exit 1
for h in ${HOSTS:-x200 t550 xps lianli chromebook t460s galaxybook macmini-intel}; do
    case $h in
        x200) HYP=/root/abnight/${PKG##*/}; HYPR="$C/hyprland-0.57.0-2-x86_64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.3.0-2-x86_64.pkg.tar.zst"; PR=pr ;;
        galaxybook) HYP=${GALAXY_PKG:?}; HYPR="$C/hyprland-0.57.0-2-aarch64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.3.0-2-aarch64.pkg.tar.zst"; PR="" ;;
        *) HYP=/root/abnight/${PKG##*/}; HYPR="$C/hyprland-0.57.0-2-x86_64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.3.0-2-x86_64.pkg.tar.zst"; PR="" ;;
    esac
    printf '%-14s ' $h
    tar -C scripts -cz bench | ssh -o BatchMode=yes root@$h "rm -rf /root/abnight/bench /root/abnight/pr && mkdir -p /root/abnight && tar -xz -C /root/abnight" || { echo "copy failed"; continue; }
    scp -q "$D/abnight.sh" root@$h:/root/abnight/ && scp -q -r "$D/pr" root@$h:/root/abnight/ || { echo "copy failed"; continue; }
    if [ $h != galaxybook ]; then
        scp -q "$PKG" root@$h:/root/abnight/ || { echo "package copy failed"; continue; }
    fi
    ssh -o BatchMode=yes root@$h "pacman -U --noconfirm --ask=4 $HYP >/dev/null 2>&1 && pacman -Q hypoland | tr '\n' ' '" || { echo "install failed"; continue; }
    ssh -o BatchMode=yes root@$h "ls $HYP $HYPR >/dev/null || exit 1; ABNIGHT_CHECK=${ABNIGHT_CHECK-1} ABNIGHT_NO_STARTUP=${ABNIGHT_NO_STARTUP-} ABNIGHT_WORKLOADS='$WL' setsid -f nohup bash /root/abnight/abnight.sh /root/abnight/$NAME $UNTIL $HYP '$HYPR' $PR >/dev/null 2>&1 </dev/null; sleep 2; tail -1 /root/abnight/$NAME/log"
done
