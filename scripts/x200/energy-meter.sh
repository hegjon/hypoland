#!/bin/bash
# Energy meter for soak.sh, on machines whose RAPL counters only root can read (the default since CVE-2020-8694).
# Run as root next to the soak run:
#
#   setsid -f /root/energy-meter.sh >/dev/null 2>&1 </dev/null
#
# Twice a second it writes "<epoch seconds> <µJ since the start>" to /run/soak-energy (readable by everyone): the
# energy of the CPU package zones (cores, GPU and uncore on Intel since Sandy Bridge), with the wraps of the
# counters taken out. soak.sh reads it before and after every workload. It exits when no soak.sh has been
# running for a minute (it waits two minutes for one to start).
set -u
OUT=${1:-/run/soak-energy}
# the package zones only, intel-rapl:0:0 and the like are slices of the package
ZONES=(/sys/class/powercap/intel-rapl:[0-9])
[ -r "${ZONES[0]}/energy_uj" ] || { echo "energy-meter.sh: no readable RAPL package zone" >&2; exit 1; }
declare -a PREV RANGE
for i in "${!ZONES[@]}"; do
    PREV[i]=$(<"${ZONES[i]}/energy_uj")
    RANGE[i]=$(<"${ZONES[i]}/max_energy_range_uj")
done
TOTAL=0 SEEN=0 GONE=$SECONDS
while :; do
    for i in "${!ZONES[@]}"; do
        cur=$(<"${ZONES[i]}/energy_uj")
        d=$((cur - PREV[i]))
        [ $d -lt 0 ] && d=$((d + RANGE[i]))
        TOTAL=$((TOTAL + d))
        PREV[i]=$cur
    done
    echo "$EPOCHREALTIME $TOTAL" >"$OUT.tmp" && chmod 644 "$OUT.tmp" && mv -f "$OUT.tmp" "$OUT"
    if pgrep -f "soak\.sh" >/dev/null; then
        SEEN=1 GONE=$SECONDS
    elif [ $((SECONDS - GONE)) -ge $((SEEN ? 60 : 120)) ]; then
        break
    fi
    sleep 0.5
done
rm -f "$OUT"
