#!/bin/bash
# abpr.sh OUT ROUNDS : Hypoland master vs stock Hyprland, alternating, as root, detached
OUT=$1 ROUNDS=$2
WL=idle,gpu-client,terminal-scroll,shm-fullwindow,workspace-switch
: > "$OUT"
ready() { # the instance lock file names the compositor and quickshell is up
    local p
    for _ in $(seq 1 120); do
        p=$(pgrep -x 'hypoland|Hyprland')
        [ -n "$p" ] && grep -qx "$p" /run/user/1000/hypr/*/hyprland.lock 2>/dev/null && pgrep -x quickshell >/dev/null && return 0
        sleep 0.5
    done
    return 1
}
for r in $(seq 1 "$ROUNDS"); do
  for label in hypoland hyprland; do
    /root/ab/use.sh $label >> "$OUT.setup" 2>&1 && ready || { echo "$label $r setup failed" >> "$OUT"; continue; }
    sleep 10
    for w in ${WL//,/ }; do
      perf stat -a -x, -e drm:drm_vblank_event_delivered -o /tmp/vbl.stat -- sleep 3600 >/dev/null 2>&1 &
      pp=$!
      bash /root/ab/measure.sh --mode bench --seconds 20 --settle 60 --workloads "$w" 2>&1 \
        | grep -vE '^@ [0-9]+ (mem\.start|binary)' | sed "s/^/$label $r $w /" >> "$OUT"
      pkill -P $pp; wait $pp 2>/dev/null
      echo "$label $r $w @ 1 flips.$w $(awk -F, '/vblank/{print $1}' /tmp/vbl.stat)" >> "$OUT"
    done
  done
done
/root/ab/use.sh hypoland >> "$OUT.setup" 2>&1
echo DONE >> "$OUT"
