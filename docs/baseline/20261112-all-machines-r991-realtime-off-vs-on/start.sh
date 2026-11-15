#!/bin/bash
# start.sh UNTIL PKG_X86 [host...] : copies abrt.sh and scripts/bench of the main tree to /root/abrt on each host,
# the x86 package too (the aarch64 ones are paths on the machine: GALAXY_PKG, M1_PKG), moves a leftover
# ~a/.config/uwsm/env.d/90-hypoland-rt of the PGO A/B aside (/root/abrt/90-hypoland-rt.pgo-leftover) and starts
# abrt.sh detached into /root/abrt/$RUN (default rt-20261112).
UNTIL=$1 PKG=$2
shift 2
RUN=${RUN:-rt-20261112}
D=$(dirname "$(readlink -f "$0")")
cd /home/jonny/Work/hypoland || exit 1
for h in ${@:-x200 t550 xps lianli chromebook t460s t490 samsung-i5 macmini-intel galaxybook macmini-m1}; do
    case $h in
        galaxybook) HYP=${GALAXY_PKG:?} ;;
        macmini-m1) HYP=${M1_PKG:?} ;;
        *) HYP=/root/abrt/${PKG##*/} ;;
    esac
    printf '%-14s ' "$h"
    tar -C scripts -cz bench | ssh -o BatchMode=yes root@$h "rm -rf /root/abrt/bench && mkdir -p /root/abrt && tar -xz -C /root/abrt" || { echo "copy failed"; continue; }
    scp -q "$D/abrt.sh" root@$h:/root/abrt/ || { echo "copy failed"; continue; }
    case $h in galaxybook | macmini-m1) ;; *) scp -q "$PKG" root@$h:/root/abrt/ || { echo "package copy failed"; continue; } ;; esac
    ssh -o BatchMode=yes root@$h "ls $HYP >/dev/null || exit 1
        F=/home/a/.config/uwsm/env.d/90-hypoland-rt
        [ -e \$F ] && grep -q PGO \$F && mv \$F /root/abrt/90-hypoland-rt.pgo-leftover && echo -n 'moved the PGO env file aside; '
        setsid -f nohup bash /root/abrt/abrt.sh /root/abrt/$RUN '$UNTIL' $HYP >/dev/null 2>&1 </dev/null; sleep 3; tail -1 /root/abrt/$RUN/log"
done
