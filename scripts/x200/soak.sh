#!/bin/bash
# Long stability run of the installed compositor (the SDDM session), for a release.
#
#   setsid -f nohup ./soak.sh [hours] >/dev/null 2>&1 </dev/null
#
# SOAK_SHORT=1 runs one cycle with workloads of seconds instead of minutes, to check the script itself.
# Runs as the session user on the machine under test. It repeats a cycle of workloads (GPU client, terminal
# scrolling, Xwayland with fullscreen toggles, workspace switching, window churn, Chromium over shm,
# screenshots and recording, config reload, DPMS off/on, idle) and samples the compositor every minute:
# memory (Pss, anonymous, GPU buffers), CPU time, fds, threads, IPC latency. It records compositor restarts,
# core dumps, GPU hangs and journal errors, keeps an hourly screenshot and writes report.txt at the end.
# Omarchy's screensaver is switched off for the run and put back afterwards. Stop early with
# `touch <outdir>/stop`.
set -u

HOURS=${1:-13}
# workload lengths in seconds
T_LONG=180 T_IDLE=300 T_DPMS=30 MAX_CYCLES=0
[ "${SOAK_SHORT:-0}" = 1 ] && T_LONG=10 T_IDLE=10 T_DPMS=5 MAX_CYCLES=1
OUT=$HOME/soak/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT/shots" "$OUT/clients"
exec >>"$OUT/soak.log" 2>&1
END=$(($(date +%s) + HOURS * 3600))
START=$(date +%s)
log() { echo "$(date '+%F %T') $*"; }

COMP=$(pgrep -u "$(id -u)" -x hypoland | head -1)
[ -n "$COMP" ] || { log "no compositor running"; exit 1; }
# The session environment for hyprctl and the clients. /proc/<pid>/environ only has what the compositor was
# started with, it sets the instance, the sockets and DISPLAY itself: the instance and the Wayland socket come
# from the hyprland.lock that names the compositor, DISPLAY from the systemd user environment (uwsm exports it).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
LOCK=$(grep -l -x "$COMP" "$XDG_RUNTIME_DIR"/hypr/*/hyprland.lock 2>/dev/null | head -1)
[ -n "$LOCK" ] || { log "no hyprland.lock for pid $COMP"; exit 1; }
HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$LOCK")")
WAYLAND_DISPLAY=$(sed -n 2p "$LOCK")
DISPLAY=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p')
export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1} DISPLAY=${DISPLAY:-:0}
export XDG_CURRENT_DESKTOP=Hyprland DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
H() { timeout 10 hyprctl "$@"; }
dispatch() { H dispatch "$1" >/dev/null 2>&1; }

OMARCHY=$HOME/.local/state/omarchy
HAD_SAVER_OFF=0
[ -e "$OMARCHY/toggles/screensaver-off" ] && HAD_SAVER_OFF=1

# clients run as leaders of their own process group, so stopping one takes its children along
CLIENTS=()
SAMPLER=""
CYCLE=0
client() {
    setsid sh -c "$1" </dev/null >>"$OUT/clients/$2.log" 2>&1 &
    CLIENTS+=($!)
}
stop_clients() {
    local p
    for p in "${CLIENTS[@]}"; do kill -- "-$p" 2>/dev/null; done
    CLIENTS=()
    sleep 1
}
restore() {
    trap - EXIT
    stop_clients
    [ -n "$SAMPLER" ] && kill "$SAMPLER" 2>/dev/null
    [ $HAD_SAVER_OFF = 1 ] || rm -f "$OMARCHY/toggles/screensaver-off"
    dispatch 'hl.dsp.dpms({action=[[on]]})'
    dispatch "hl.dsp.focus({workspace=1})"
    report
    log "done"
}
trap restore EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$OMARCHY/toggles"
touch "$OMARCHY/toggles/screensaver-off"
pkill -f "[o]rg.omarchy.screensaver"
dispatch 'hl.dsp.dpms({action=[[on]]})'

# ---- sampler, one line per minute

kb() { awk -v k="$2" '$1 == k":" {print $2; exit}' "$1" 2>/dev/null; }
pss_of() { # Pss of the user's process with this name, 0 when it is not running
    local p
    p=$(pgrep -u "$(id -u)" -x "$1" | head -1)
    if [ -n "$p" ]; then kb /proc/"$p"/smaps_rollup Pss; else echo 0; fi
}
gpu_kb() { # GPU buffers of a process, counted once per DRM client
    cat /proc/"$1"/fdinfo/* 2>/dev/null | awk '
        $1 == "drm-client-id:" {id = $2}
        $1 == "drm-total-system0:" && !(id in seen) {seen[id] = 1; v = $2; if ($3 == "MiB") v *= 1024; s += v}
        END {print s + 0}'
}
sampler() {
    local pid last_pid="" ticks last_ticks="" t0 t1 lat clients state cpu hz
    hz=$(getconf CLK_TCK)
    echo "time elapsed_min pid pss_kB anon_kB rss_kB gpu_kB fds threads cpu_pct ipc_ms clients xwayland_pss_kB quickshell_pss_kB state" >"$OUT/samples.txt"
    while :; do
        pid=$(pgrep -u "$(id -u)" -x hypoland | head -1)
        if [ -n "$last_pid" ] && [ "$pid" != "$last_pid" ]; then
            log "EVENT compositor restarted: pid $last_pid -> ${pid:-none}"
            last_ticks=""
        fi
        last_pid=$pid
        if [ -z "$pid" ]; then sleep 60; continue; fi
        ticks=$(awk '{print $14 + $15}' /proc/"$pid"/stat 2>/dev/null)
        cpu=nan
        [ -n "$last_ticks" ] && cpu=$(awk -v a="$last_ticks" -v b="$ticks" -v hz="$hz" 'BEGIN {printf "%.1f", (b - a) / hz / 60 * 100}')
        last_ticks=$ticks
        t0=$(date +%s%N)
        clients=$(H clients -j 2>/dev/null | jq length 2>/dev/null)
        t1=$(date +%s%N)
        lat=$(((t1 - t0) / 1000000))
        [ -n "$clients" ] || {
            clients=nan
            log "EVENT hyprctl did not answer (${lat} ms)"
        }
        state=ok
        H clients 2>/dev/null | grep -q "org.omarchy.screensaver" && state=screensaver
        H monitors -j 2>/dev/null | jq -e '.[0].solitaryBlockedBy // [] | index("lock")' >/dev/null 2>&1 && state=locked
        echo "$(date +%T) $((($(date +%s) - START) / 60)) $pid $(kb /proc/"$pid"/smaps_rollup Pss) $(kb /proc/"$pid"/status RssAnon) $(kb /proc/"$pid"/status VmRSS) $(gpu_kb "$pid") $(ls /proc/"$pid"/fd 2>/dev/null | wc -l) $(kb /proc/"$pid"/status Threads) $cpu $lat $clients $(pss_of Xwayland) $(pss_of quickshell) $state" >>"$OUT/samples.txt"
        sleep 60
    done
}
sampler &
SAMPLER=$!

# ---- events: core dumps, GPU hangs, errors in the compositor's journal

check_events() {
    local since="@$1"
    coredumpctl list --since "$since" --no-pager 2>/dev/null | grep -v "^TIME\|No coredumps" | sed 's/^/EVENT coredump: /' | while read -r l; do log "$l"; done
    journalctl -k --since "$since" --no-pager -q 2>/dev/null | grep -iE "gpu hang|i915.*(reset|error|hang)|out of memory|oom-kill" | sed 's/^/EVENT kernel: /' | while read -r l; do log "$l"; done
    # one line per distinct message, with its count
    journalctl --user --since "$since" --no-pager -q -o cat -u wayland-wm@hyprland.desktop.service 2>/dev/null |
        grep -iE "crash|assert|segfault|abort|Failed to link|GL_OUT_OF|error|invalid|\*\*\* BUG" |
        grep -vE "xkbcomp|keycode|Set a breakpoint on|^\*\*\* BUG \*\*\*$" | sort | uniq -c | sort -rn | head -20 |
        sed 's/^ *\([0-9]*\) /EVENT journal (\1x): /' | while read -r l; do log "$l"; done
}

# ---- workloads, each a few minutes

w_gpu() { client "exec weston-simple-egl" gpu; sleep $T_LONG; stop_clients; }
w_scroll() { client "exec foot -e sh -c 'while true; do ls -la /usr/lib; done'" scroll; sleep $T_LONG; stop_clients; }
w_xwayland_fullscreen() {
    client "exec glxgears" glxgears
    sleep 5
    local i
    for i in $(seq 1 20); do dispatch 'hl.dsp.window.fullscreen({action="toggle"})'; sleep 3; done
    stop_clients
}
w_workspaces() {
    local i
    for i in 1 2 3; do client "exec foot -e sleep 600" ws; sleep 1; done
    for i in $(seq 1 60); do
        dispatch "hl.dsp.focus({workspace=2})"; sleep 0.5
        dispatch "hl.dsp.focus({workspace=1})"; sleep 0.5
    done
    stop_clients
}
w_churn() { # open and close many windows, tiled and floating
    local i
    for i in $(seq 1 15); do client "exec foot -e sleep 30" churn; sleep 0.7; done
    for i in 1 2 3; do dispatch 'hl.dsp.window.float({action="toggle"})'; sleep 1; done
    sleep 3
    stop_clients
}
w_chromium() {
    local page="data:text/html,<body style='background:linear-gradient(90deg,red,blue)'><marquee scrollamount=20 style='font:60px sans-serif;color:white'>Hypoland</marquee><div style='animation:s 2s linear infinite;width:200px;height:200px;background:lime'></div><style>@keyframes s{to{transform:translateX(900px) rotate(360deg)}}</style>"
    client "exec chromium --ozone-platform=wayland --no-first-run --user-data-dir=$OUT/chromium \"$page\"" chromium
    sleep $T_LONG
    stop_clients
}
w_capture() { # screencopy, recording, the screen share path
    client "exec weston-simple-egl" capture-gpu
    sleep 3
    local i
    for i in 1 2 3 4 5; do timeout 15 grim "$OUT/clients/grim.png" || log "EVENT grim failed"; sleep 2; done
    timeout -s INT 12 wf-recorder -f "$OUT/clients/rec.mp4" >/dev/null 2>&1
    [ -s "$OUT/clients/rec.mp4" ] || log "EVENT wf-recorder wrote nothing"
    rm -f "$OUT/clients/rec.mp4" "$OUT/clients/grim.png"
    stop_clients
}
w_reload() { H reload >/dev/null || log "EVENT hyprctl reload failed"; sleep 5; }
w_dpms() {
    dispatch 'hl.dsp.dpms({action=[[off]]})'; sleep $T_DPMS
    dispatch 'hl.dsp.dpms({action=[[on]]})'; sleep 5
}
w_idle() { sleep $T_IDLE; }

# ---- report, also written when the run is stopped early

report() {
    {
        echo "Soak test $(basename "$OUT"): $(pacman -Q hypoland 2>/dev/null)"
        echo "ran $((($(date +%s) - START) / 60)) min, $CYCLE cycles"
        echo
        echo "events:"
        grep "EVENT" "$OUT/soak.log" | sed 's/^/  /' || true
        grep -q "EVENT" "$OUT/soak.log" || echo "  none"
        echo
        echo "compositor, first hour against last hour (median of the samples):"
        awk 'NR > 1 && $4 != "" {n++; e[n] = $2; pss[n] = $4; anon[n] = $5; gpu[n] = $7; fds[n] = $8; thr[n] = $9; lat[n] = $11}
            function med(a, from, to,   i, k, v, t) {k = 0; for (i = from; i <= to; i++) v[++k] = a[i]
                for (i = 1; i <= k; i++) for (t = i + 1; t <= k; t++) if (v[t] < v[i]) {x = v[i]; v[i] = v[t]; v[t] = x}
                return k ? v[int((k + 1) / 2)] : "nan"}
            END {
                if (n < 2) {print "  not enough samples"; exit}
                h = (n >= 120) ? 60 : int(n / 2)
                printf "  %-14s %10s %10s\n", "", "first", "last"
                printf "  %-14s %10s %10s\n", "Pss kB", med(pss, 1, h), med(pss, n - h + 1, n)
                printf "  %-14s %10s %10s\n", "anonymous kB", med(anon, 1, h), med(anon, n - h + 1, n)
                printf "  %-14s %10s %10s\n", "GPU kB", med(gpu, 1, h), med(gpu, n - h + 1, n)
                printf "  %-14s %10s %10s\n", "fds", med(fds, 1, h), med(fds, n - h + 1, n)
                printf "  %-14s %10s %10s\n", "threads", med(thr, 1, h), med(thr, n - h + 1, n)
                printf "  %-14s %10s %10s\n", "IPC ms", med(lat, 1, h), med(lat, n - h + 1, n)
            }' "$OUT/samples.txt"
        echo
        echo "state other than ok in $(awk 'NR > 1 && $15 != "ok"' "$OUT/samples.txt" | wc -l) of $(($(wc -l <"$OUT/samples.txt") - 1)) samples"
    } >"$OUT/report.txt"
}

# ---- main loop

log "soak test for $HOURS h, compositor pid $COMP, $(pacman -Q hypoland 2>/dev/null)"
LAST_EVENTS=$START
LAST_SHOT=0
while [ "$(date +%s)" -lt "$END" ] && [ ! -e "$OUT/stop" ]; do
    CYCLE=$((CYCLE + 1))
    log "cycle $CYCLE"
    for w in w_gpu w_scroll w_xwayland_fullscreen w_workspaces w_churn w_capture w_reload w_dpms w_idle; do
        [ "$(date +%s)" -lt "$END" ] && [ ! -e "$OUT/stop" ] || break
        log "  $w"
        $w
    done
    # Chromium is heavy on this machine, every third cycle (and in the short run)
    { [ $((CYCLE % 3)) = 0 ] || [ $MAX_CYCLES = 1 ]; } && [ "$(date +%s)" -lt "$END" ] && log "  w_chromium" && w_chromium
    now=$(date +%s)
    check_events "$LAST_EVENTS"
    LAST_EVENTS=$now
    if [ $((now - LAST_SHOT)) -ge 3600 ]; then
        timeout 15 grim -s 0.5 "$OUT/shots/$(date +%H%M).png" || log "EVENT hourly screenshot failed"
        LAST_SHOT=$now
    fi
    [ $MAX_CYCLES -gt 0 ] && [ $CYCLE -ge $MAX_CYCLES ] && break
done
