#!/bin/bash
# start.sh NAME UNTIL PKG_X86 [workloads] : copies abnight.sh and scripts/bench to /root/abnight on the machines in
# HOSTS and starts it detached, writing /root/abnight/NAME. PKG_X86 is the x86_64 package file on the desktop, copied
# to each machine's /root/abnight; the Galaxy Book takes GALAXY_PKG (a path on the machine).
NAME=$1 UNTIL=$2 PKG=$3 WL=${4:-}
C=/var/cache/pacman/pkg
D=$(dirname "$(readlink -f "$0")")
cd /home/jonny/Work/hypoland || exit 1
for h in ${HOSTS:-x200 xps lianli chromebook t460s}; do
    case $h in
        x200) HYP=/root/abnight/${PKG##*/}; HYPR="/root/ab/hyprland-0.56.2-4-x86_64.pkg.tar.zst /root/ab/omarchy-hyprland-titlebars-0.2.2-2-x86_64.pkg.tar.zst"; PR=pr ;;
        galaxybook) HYP=${GALAXY_PKG:?}; HYPR="$C/hyprland-0.56.2-4-aarch64.pkg.tar.xz $C/omarchy-hyprland-titlebars-0.2.2-2-aarch64.pkg.tar.zst"; PR="" ;;
        *) HYP=/root/abnight/${PKG##*/}; HYPR="$C/hyprland-0.56.2-4-x86_64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.2.2-2-x86_64.pkg.tar.zst"; PR="" ;;
    esac
    printf '%-11s ' $h
    tar -C scripts -cz bench | ssh -o BatchMode=yes root@$h "rm -rf /root/abnight/bench && mkdir -p /root/abnight && tar -xz -C /root/abnight" || { echo "copy failed"; continue; }
    scp -q "$D/abnight.sh" root@$h:/root/abnight/ || { echo "copy failed"; continue; }
    # the packages of the build under test, installed before the run: abnight.sh only swaps between the two compositors
    if [ $h != galaxybook ]; then
        scp -q "$PKG" ${BENCH_PKG:+"$BENCH_PKG"} root@$h:/root/abnight/ || { echo "package copy failed"; continue; }
        ssh -o BatchMode=yes root@$h "pacman -U --noconfirm --ask=4 /root/abnight/${PKG##*/} ${BENCH_PKG:+/root/abnight/${BENCH_PKG##*/}} >/dev/null 2>&1 && pacman -Q hypoland ${BENCH_PKG:+hypoland-bench} | tr '\n' ' '" || { echo "install failed"; continue; }
    else
        ssh -o BatchMode=yes root@$h "pacman -U --noconfirm --ask=4 $HYP ${GALAXY_BENCH_PKG:-} >/dev/null 2>&1 && pacman -Q hypoland ${GALAXY_BENCH_PKG:+hypoland-bench} | tr '\n' ' '" || { echo "install failed"; continue; }
    fi
    [ $h = x200 ] && ssh -o BatchMode=yes root@x200 "mkdir -p /root/abnight/pr && cp /root/ab/pr/intel-gles2.lua /root/ab/pr/omarchy-hw-intel-gles2 /root/abnight/pr/"
    ssh -o BatchMode=yes root@$h "ls $HYP $HYPR >/dev/null || exit 1; ABNIGHT_WORKLOADS='$WL' setsid -f nohup bash /root/abnight/abnight.sh /root/abnight/$NAME $UNTIL $HYP '$HYPR' $PR >/dev/null 2>&1 </dev/null; sleep 2; tail -1 /root/abnight/$NAME/log"
done
