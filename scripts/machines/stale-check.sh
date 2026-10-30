#!/bin/bash
# stale-check.sh <runs> <label>: as root on a test machine with an Omarchy session (it restarts SDDM), detached:
#   setsid nohup bash stale-check.sh 15 mylabel >/dev/null 2>&1 </dev/null &
# foot shows a screen whose lines are rewritten in place at random rows (partial damage, the case where a client repaints the previous frame's damage into
# the buffer it reuses). Per run: the writer runs 2 s and stops, the scanout is captured (A), the CPU caches are evicted by
# writing 256 MB, the workspace is switched away and back so the compositor redraws the window from foot's unchanged
# buffer, now in memory, and the scanout is captured again (B). Pixels of the window that differ between A and B are a
# frame drawn from memory the client had written but the CPU had not written back. Output /root/stale/<label>.txt
set -u
RUNS=${1:-15}; L=${2:-test}; D=/root/stale; mkdir -p $D /tmp/staletest; chmod 777 /tmp/staletest
RT=/run/user/1000; U=a
S=/home/a/.local/state/omarchy; mkdir -p $S/indicators $S/toggles
had_awake=0; [ -e $S/indicators/stay-awake ] && had_awake=1
had_ss=0; [ -e $S/toggles/screensaver-off ] && had_ss=1
# a fresh session, so no screensaver, lock or blanked screen from idle time before; the idle flags at once
systemctl restart sddm
for _ in $(seq 1 240); do
    p=$(pgrep -x hypoland)
    [ -n "$p" ] && grep -qx "$p" $RT/hypr/*/hyprland.lock 2>/dev/null && pgrep -x quickshell >/dev/null && break
    sleep 0.5
done
touch $S/indicators/stay-awake $S/toggles/screensaver-off; chown -R a:a $S
sleep 20
pid=$(pgrep -x hypoland); sig=""
for d in $RT/hypr/*/; do grep -qx "$pid" $d/hyprland.lock 2>/dev/null && sig=$(basename $d); done
H() { runuser -u $U -- env XDG_RUNTIME_DIR=$RT HYPRLAND_INSTANCE_SIGNATURE=$sig timeout 5 hyprctl "$@"; }
log() { echo "$(date +%T) $*" >> $D/$L.txt; }
: > $D/$L.txt
log "$(pacman -Q hypoland), compositor $pid, env: $(tr '\0' '\n' < /proc/$pid/environ | grep HYPOLAND | tr '\n' ' ')"
journalctl --user -M $U@ -u wayland-wm@hyprland.desktop.service -b --no-pager 2>/dev/null | grep -i "zero copy" | tail -2 >> $D/$L.txt
cat > /tmp/staletest/writer.py <<'PY'
import os, random, sys, time
rows, cols = os.get_terminal_size()
sys.stdout.write("\033[?25l\033[2J"); sys.stdout.flush()
chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#@%&"
while True:
    if os.path.exists("/tmp/staletest/run"):
        for _ in range(3):
            r = random.randint(1, rows)
            sys.stdout.write("\033[%d;1H%s" % (r, "".join(random.choice(chars) for _ in range(cols))))
        sys.stdout.flush()
        time.sleep(0.004)
    else:
        time.sleep(0.05)
PY
chmod 644 /tmp/staletest/writer.py; rm -f /tmp/staletest/run
runuser -u $U -- env -C /home/$U HOME=/home/$U XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-1 PATH=/usr/local/bin:/usr/bin setsid foot --app-id staletest -e python3 -I /tmp/staletest/writer.py >/tmp/staletest/foot.log 2>&1 &
sleep 3
H dispatch "hl.dsp.focus({ window = 'class:staletest' })" >/dev/null
sleep 1
read -r X Y W HH < <(H -j clients | python3 -c 'import json,sys
for c in json.load(sys.stdin):
    if c["class"] == "staletest": print(c["at"][0], c["at"][1], c["size"][0], c["size"][1]); break')
log "window at $X,$Y size ${W}x$HH"
if [ -z "${W:-}" ]; then log "ABORT: no staletest window ($(tail -2 /tmp/staletest/foot.log | tr '\n' ' '))"; touch $D/done-$L; exit 1; fi
cat > /tmp/staletest/cmp.py <<'PY'
import sys
def ppm(p):
    d = open(p, "rb").read(); parts = d.split(b"\n", 3)
    w, h = map(int, parts[1].split()); return w, h, parts[3]
x, y, w, h = map(int, sys.argv[3:7])
wa, ha, a = ppm(sys.argv[1]); wb, hb, b = ppm(sys.argv[2])
diff = 0; rows = set()
for yy in range(max(y, 0), min(y + h, ha)):
    o = (yy * wa + max(x, 0)) * 3; e = (yy * wa + min(x + w, wa)) * 3
    if a[o:e] != b[o:e]:
        ra, rb = a[o:e], b[o:e]
        n = sum(1 for i in range(0, len(ra), 3) if ra[i:i+3] != rb[i:i+3]); diff += n; rows.add(yy)
print(diff, len(rows))
PY
bad=0
for r in $(seq 1 $RUNS); do
    touch /tmp/staletest/run; sleep 2; rm -f /tmp/staletest/run; sleep 0.5
    rm -f /tmp/staletest/a.ppm /tmp/staletest/b.ppm
    hypoland-kmsgrab /tmp/staletest/a.ppm >/dev/null 2>&1 || { log "run $r: no capture A"; continue; }
    dd if=/dev/zero of=/dev/shm/staletest-evict bs=1M count=256 status=none; rm -f /dev/shm/staletest-evict
    H dispatch "hl.dsp.focus({ workspace = 2 })" >/dev/null; sleep 1.2
    H dispatch "hl.dsp.focus({ workspace = 1 })" >/dev/null; sleep 1.5
    hypoland-kmsgrab /tmp/staletest/b.ppm >/dev/null 2>&1 || { log "run $r: no capture B"; continue; }
    read -r n rows < <(python3 -I /tmp/staletest/cmp.py /tmp/staletest/a.ppm /tmp/staletest/b.ppm $X $Y $W $HH)
    [ "$n" -gt 0 ] && { bad=$((bad+1)); cp /tmp/staletest/a.ppm $D/$L-a$r.ppm; cp /tmp/staletest/b.ppm $D/$L-b$r.ppm; }
    log "run $r: $n pixels in $rows rows differ"
done
log "RESULT $L: $bad of $RUNS runs showed stale pixels"
pkill -f "app-id staletest"; pkill -f "/tmp/staletest/writer.py"
[ $had_awake = 0 ] && rm -f $S/indicators/stay-awake; [ $had_ss = 0 ] && rm -f $S/toggles/screensaver-off
touch $D/done-$L
