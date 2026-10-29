#!/bin/bash
# start.sh NAME UNTIL PKG BENCH_PKG [workloads] : copies abnight.sh and scripts/bench to /root/abnight on the machines
# in HOSTS, installs PKG and BENCH_PKG (x86_64 package files on the desktop; the Galaxy Book takes GALAXY_PKG and
# GALAXY_BENCH_PKG, paths on the machine) and starts the run detached, writing /root/abnight/NAME: the variants "off"
# (the env file as it is) and "on" (export HYPOLAND_SHM_TEXTURE=linear) in alternating fresh sessions until UNTIL.
NAME=$1 UNTIL=$2 PKG=$3 BENCH_PKG=$4 WL=${5:-}
D=$(dirname "$(readlink -f "$0")")
cd /home/jonny/Work/hypoland || exit 1
for h in ${HOSTS:-x200 t550 xps lianli chromebook t460s macmini-intel galaxybook}; do
    printf '%-14s ' $h
    tar -C scripts -cz bench | ssh -o BatchMode=yes root@$h "rm -rf /root/abnight/bench && mkdir -p /root/abnight && tar -xz -C /root/abnight" || { echo "copy failed"; continue; }
    scp -q "$D/abnight.sh" root@$h:/root/abnight/ || { echo "copy failed"; continue; }
    if [ $h != galaxybook ]; then
        scp -q "$PKG" "$BENCH_PKG" root@$h:/root/abnight/ || { echo "package copy failed"; continue; }
        ssh -o BatchMode=yes root@$h "pacman -U --noconfirm --ask=4 /root/abnight/${PKG##*/} /root/abnight/${BENCH_PKG##*/} >/dev/null 2>&1 && pacman -Q hypoland hypoland-bench | tr '\n' ' '" || { echo "install failed"; continue; }
    else
        ssh -o BatchMode=yes root@$h "pacman -U --noconfirm --ask=4 ${GALAXY_PKG:?} ${GALAXY_BENCH_PKG:?} >/dev/null 2>&1 && pacman -Q hypoland hypoland-bench | tr '\n' ' '" || { echo "install failed"; continue; }
    fi
    # ABNIGHT_CHECK=1 has the first round run the session checks of a deploy for both variants as well
    ssh -o BatchMode=yes root@$h "ABNIGHT_WORKLOADS='$WL' ABNIGHT_CHECK='${ABNIGHT_CHECK:-}' setsid -f nohup bash /root/abnight/abnight.sh /root/abnight/$NAME $UNTIL off '' on 'export HYPOLAND_SHM_TEXTURE=linear' >/dev/null 2>&1 </dev/null; sleep 2; tail -1 /root/abnight/$NAME/log"
done
