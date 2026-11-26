#!/bin/bash
# start.sh NAME UNTIL [workloads] : copies energy.sh, pr/, the Hypoland package next to this script and scripts/bench of
# this tree to /root/energy on the machines in HOSTS (the machines with RAPL), installs that package and starts
# energy.sh detached, writing /root/energy/NAME. Stock Hyprland 0.57.2-4 and omarchy-hyprland-titlebars 0.4.0-3 must be in
# each machine's pacman cache.
NAME=$1 UNTIL=$2 WL=${3:-}
C=/var/cache/pacman/pkg
D=$(dirname "$(readlink -f "$0")")
PKG=$(ls "$D"/hypoland-0.4.0-*-x86_64.pkg.tar.zst | tail -1)
cd "${TREE:-$D/../..}" && [ -d scripts/bench ] || exit 1
echo "scripts/bench from $(pwd) at $(git log --oneline -1 | cut -c1-60), package ${PKG##*/}"
set -o pipefail
for h in ${HOSTS:-t550 xps chromebook macmini-intel t460s t490 samsung-i5}; do
    HYP=/root/energy/${PKG##*/} HYPR="$C/hyprland-0.57.2-4-x86_64.pkg.tar.zst $C/omarchy-hyprland-titlebars-0.4.0-3-x86_64.pkg.tar.zst"
    printf '%-14s ' $h
    tar -C scripts -cz bench | ssh -o BatchMode=yes root@$h "rm -rf /root/energy/bench /root/energy/pr && mkdir -p /root/energy && tar -xz -C /root/energy" || { echo "copy failed"; continue; }
    scp -q "$D/energy.sh" root@$h:/root/energy/ && scp -q -r "$D/pr" root@$h:/root/energy/ || { echo "copy failed"; continue; }
    scp -q "$PKG" root@$h:/root/energy/ || { echo "package copy failed"; continue; }
    ssh -o BatchMode=yes root@$h "pacman -U --noconfirm --ask=4 $HYP >/dev/null 2>&1 && pacman -Q hypoland | tr '\n' ' '" || { echo "install failed"; continue; }
    ssh -o BatchMode=yes root@$h "ls $HYP $HYPR >/dev/null || exit 1; ENERGY_WORKLOADS='$WL' setsid -f nohup bash /root/energy/energy.sh /root/energy/$NAME '$UNTIL' $HYP '$HYPR' >/dev/null 2>&1 </dev/null; sleep 2; tail -1 /root/energy/$NAME/log"
done
