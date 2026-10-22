#!/bin/bash
# Long stability run of the installed compositor (the SDDM session), for a release.
#
#   setsid -f nohup ./soak.sh [hours] >/dev/null 2>&1 </dev/null
#
# SOAK_SHORT=1 runs one cycle with workloads of seconds instead of minutes, to check the script itself.
# Runs as the session user on the machine under test. It repeats a cycle of workloads (GPU client, terminal
# scrolling in foot (shm) and alacritty (GL), a fullscreen video in mpv, nautilus (GTK 4) with fullscreen toggles,
# flea (Quickshell) paged, searched and switched between views with keys, Xwayland with fullscreen toggles, workspace switching, window churn, Chromium over shm, screenshots and
# recording, config reload, DPMS off/on, idle, glmark2; the ones whose program is not installed are skipped) and samples the compositor every minute:
# memory (Pss, anonymous, GPU buffers), CPU time, fds, threads, IPC latency. It records compositor restarts,
# core dumps, GPU hangs and journal errors, keeps an hourly screenshot and writes report.txt at the end.
# Every workload is also a benchmark: the compositor's CPU time and, with perf, its user space instructions and
# cycles per second go to cpu.txt, glmark2's score to glmark2.txt. The report compares the first and the last
# cycles (a cost that grows) and gives the medians over the run (to compare builds and machines).
# Energy: with RAPL the power of the CPU package (cores and GPU) during every workload goes to cpu.txt too, and the
# report gives it net of the idle workload. The counters are root only, so a root helper has to run next to the
# soak: copy energy-meter.sh to /root and start it as root (see there). Without it, or without RAPL (the X200),
# the energy columns are nan.
# After a compositor restart the run attaches to the new instance and goes on.
# Omarchy's screensaver and idle lock are switched off for the run and put back afterwards. Stop early with
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

# The session environment for hyprctl and the clients. /proc/<pid>/environ only has what the compositor was
# started with, it sets the instance, the sockets and DISPLAY itself: the instance and the Wayland socket come
# from the hyprland.lock that names the compositor, DISPLAY from the systemd user environment (uwsm exports it).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export XDG_CURRENT_DESKTOP=Hyprland DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
COMP=""
attach() { # to the running compositor, again after it restarted (a run of 0.2.0 kept talking to the dead one)
    local pid lock
    pid=$(pgrep -u "$(id -u)" -x hypoland | head -1)
    [ -n "$pid" ] || return 1
    [ "$pid" = "$COMP" ] && return 0
    [ -n "$COMP" ] && log "attaching to the new compositor, pid $pid"
    lock=$(grep -l -x "$pid" "$XDG_RUNTIME_DIR"/hypr/*/hyprland.lock 2>/dev/null | head -1)
    [ -n "$lock" ] || return 1
    HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$lock")")
    WAYLAND_DISPLAY=$(sed -n 2p "$lock")
    DISPLAY=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p')
    export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1} DISPLAY=${DISPLAY:-:0}
    COMP=$pid
}
attach || { log "no compositor with a hyprland.lock running"; exit 1; }
H() { timeout 10 hyprctl "$@"; }
dispatch() { H dispatch "$1" >/dev/null 2>&1; }

OMARCHY=$HOME/.local/state/omarchy
# screensaver-off only stops the screensaver, the lock after 300 s idle needs Omarchy's stay-awake indicator
HAD_SAVER_OFF=0 HAD_STAY_AWAKE=0
[ -e "$OMARCHY/toggles/screensaver-off" ] && HAD_SAVER_OFF=1
[ -e "$OMARCHY/indicators/stay-awake" ] && HAD_STAY_AWAKE=1

# clients run as leaders of their own process group, so stopping one takes its children along
CLIENTS=()
SAMPLER=""
PERF=""
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
    [ -n "$PERF" ] && stop_perf
    [ $HAD_SAVER_OFF = 1 ] || rm -f "$OMARCHY/toggles/screensaver-off"
    [ $HAD_STAY_AWAKE = 1 ] || rm -f "$OMARCHY/indicators/stay-awake"
    dispatch 'hl.dsp.dpms({action=[[on]]})'
    dispatch "hl.dsp.focus({workspace=1})"
    report
    log "done"
}
trap restore EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$OMARCHY/toggles" "$OMARCHY/indicators"
touch "$OMARCHY/toggles/screensaver-off" "$OMARCHY/indicators/stay-awake"
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
            sleep 20 # until the new one wrote its lock and answers
            attach
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
        H monitors -j 2>/dev/null | jq -e '.[0].solitaryBlockedBy // [] | map(ascii_downcase) | index("lock")' >/dev/null 2>&1 && state=locked
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
        grep -vE "xkbcomp|keycode|Set a breakpoint on|^\*\*\* BUG \*\*\*$|quickshell\.dbus\.properties" | sort | uniq -c | sort -rn | head -20 |
        sed 's/^ *\([0-9]*\) /EVENT journal (\1x): /' | while read -r l; do log "$l"; done
}

# ---- workloads, each a few minutes

w_gpu() { client "exec weston-simple-egl" gpu; sleep $T_LONG; stop_clients; }
w_scroll() { client "exec foot -e sh -c 'while true; do ls -la /usr/lib; done'" scroll; sleep $T_LONG; stop_clients; }
w_scroll_alacritty() {
    command -v alacritty >/dev/null || return 0
    client "exec alacritty -e sh -c 'while true; do ls -la /usr/lib; done'" scroll-alacritty; sleep $T_LONG; stop_clients
}
VIDEO=$HOME/.cache/hypoland-bench/video.mp4
w_video() {
    command -v mpv >/dev/null && command -v ffmpeg >/dev/null || return 0
    [ -s "$VIDEO" ] || { mkdir -p "${VIDEO%/*}" && ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 \
        -t 20 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$VIDEO"; }
    client "exec mpv --fs --loop-file=inf --no-audio --really-quiet '$VIDEO'" video; sleep $T_LONG; stop_clients
}
w_nautilus() {
    command -v nautilus >/dev/null || return 0
    client "exec nautilus --new-window /usr/share/icons/Adwaita/symbolic/actions" nautilus
    sleep 5
    local i
    for i in $(seq 1 20); do dispatch 'hl.dsp.window.fullscreen({action="toggle"})'; sleep 1; done
    # new windows and folders, then quit: a nautilus that was already running owns the windows
    for i in 1 2 3; do nautilus --new-window /usr/share/icons/Adwaita >/dev/null 2>&1; sleep 2; done
    stop_clients
    nautilus -q >/dev/null 2>&1
}
FILES=$HOME/.cache/hypoland-bench/files
key() { dispatch "hl.dsp.send_shortcut({mods=\"$1\", key=\"$2\"})"; sleep "${3:-0.25}"; }
w_flea() {
    command -v flea >/dev/null || return 0
    [ -e "$FILES/file-5000.txt" ] || { mkdir -p "$FILES" && (cd "$FILES" && for i in $(seq -w 1 5000); do : >"file-$i.txt"; done); }
    client "exec flea '$FILES'" flea
    sleep 8
    local i j v
    for i in $(seq 1 $((T_LONG >= 40 ? T_LONG / 20 : 1))); do
        for j in $(seq 1 20); do key "" Page_Down; done
        for j in $(seq 1 20); do key "" Page_Up; done
        for v in 2 3 1; do key CTRL $v 2; done # columns, grid, back to the list
        key "" slash 1; for j in 1 2 3 4; do key "" $j; done; sleep 2; key "" Escape 1 # filter the listing
    done
    stop_clients
    # flea execs qs and leaves a backend; the bracket keeps pkill from matching its own command line
    pkill -f "[q]s -p /usr/share/flea"; pkill -x flea; sleep 1
}
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
w_glmark2() { # a fixed set of scenes, the score shows whether the frames the clients get stay the same
    local d=8 score
    [ "${SOAK_SHORT:-0}" = 1 ] && d=2
    command -v glmark2-es2-wayland >/dev/null || return 0
    timeout 300 glmark2-es2-wayland --fullscreen -b build:duration=$d -b texture:duration=$d \
        -b shading:shading=phong:duration=$d -b effect2d:duration=$d -b desktop:effect=blur:windows=4:duration=$d \
        -b pulsar:duration=$d >"$OUT/clients/glmark2-last.log" 2>&1
    cat "$OUT/clients/glmark2-last.log" >>"$OUT/clients/glmark2.log"
    score=$(sed -n 's/.*glmark2 Score: *\([0-9]*\).*/\1/p' "$OUT/clients/glmark2-last.log")
    [ -n "$score" ] || { log "EVENT glmark2 gave no score"; return 0; }
    echo "$CYCLE $score" >>"$OUT/glmark2.txt"
}

# ---- report, also written when the run is stopped early

# runs a workload and writes the compositor's CPU time during it to cpu.txt: a cost that grows from cycle to cycle
# shows something that piles up (the screen share sessions of 0.2.0 doubled every frame's cost over a night).
# With perf it adds the compositor's user space instructions and cycles per second (perf_event_paranoid 2 lets the
# user count its own processes in user space only), steadier than the CPU time to compare builds by.
cputicks() { awk '{print $14 + $15}' "/proc/$COMP/stat" 2>/dev/null; }
stop_perf() { # SIGINT makes perf stat write its counts
    local i
    for i in $(seq 1 25); do
        kill -INT "$PERF" 2>/dev/null
        sleep 0.2
        # gone, or a zombie that only waits for wait
        case $(awk '{print $3}' /proc/"$PERF"/stat 2>/dev/null) in "" | Z) break ;; esac
    done
    kill "$PERF" 2>/dev/null
    wait "$PERF" 2>/dev/null
    PERF=""
}
# the package energy in µJ from energy-meter.sh, empty without a fresh reading
ENERGY_FILE=/run/soak-energy
energy() {
    local t e
    read -r t e 2>/dev/null <"$ENERGY_FILE" || return 0
    awk -v t="$t" -v now="$EPOCHREALTIME" 'BEGIN {exit !(now - t < 5)}' && echo "$t $e"
}
HAVE_PERF=0
command -v perf >/dev/null && perf stat -e instructions:u -p "$COMP" -- true >/dev/null 2>&1 && HAVE_PERF=1
measured() { # workload
    local t0 c0 t1 c1 e0 e1 ins=nan cyc=nan
    attach
    t0=$EPOCHREALTIME c0=$(cputicks) e0=$(energy)
    if [ $HAVE_PERF = 1 ]; then
        perf stat -x, -e instructions:u,cycles:u -p "$COMP" -o "$OUT/perf.tmp" >/dev/null 2>&1 &
        PERF=$!
        sleep 0.5 # bash starts it with SIGINT ignored, until perf sets its own handler a SIGINT is lost
    fi
    "$1"
    t1=$EPOCHREALTIME c1=$(cputicks) e1=$(energy)
    if [ -n "$PERF" ]; then
        stop_perf
        ins=$(awk -F, '$3 == "instructions:u" && $1 ~ /^[0-9]+$/ {print $1}' "$OUT/perf.tmp")
        cyc=$(awk -F, '$3 == "cycles:u" && $1 ~ /^[0-9]+$/ {print $1}' "$OUT/perf.tmp")
    fi
    [ -n "$c0" ] && [ -n "$c1" ] && [ "$c1" -ge "$c0" ] &&
        awk -v w="$1" -v c="$CYCLE" -v d=$((c1 - c0)) -v t0="$t0" -v t1="$t1" -v hz="$(getconf CLK_TCK)" \
            -v ins="${ins:-nan}" -v cyc="${cyc:-nan}" -v e0="${e0:-nan nan}" -v e1="${e1:-nan nan}" '
            function rate(x) {return x == "nan" ? "nan" : sprintf("%.1f", x / 1e6 / (t1 - t0))}
            BEGIN {split(e0, a, " "); split(e1, b, " ")
                # watts between the two readings of the meter, they are at most half a second old
                pw = (a[1] == "nan" || b[1] == "nan" || b[1] <= a[1]) ? "nan" : sprintf("%.2f", (b[2] - a[2]) / 1e6 / (b[1] - a[1]))
                printf "%s %s %.2f %s %s %s\n", c, w, 100 * d / hz / (t1 - t0), rate(ins), rate(cyc), pw}' >>"$OUT/cpu.txt"
}

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
        echo "per workload: compositor CPU %, compositor user space Minstructions/s and Mcycles/s (perf) and the power"
        echo "of the CPU package with the GPU (RAPL, net = over the idle workload), median of the first and the last"
        echo "cycles (up to 5 each) and of the whole run:"
        printf "  %-22s %6s | %-20s | %-23s | %7s | %-23s\n" "" "" "CPU %" "Minstructions/s" "Mcyc/s" "package W"
        printf "  %-22s %6s | %6s %6s %6s | %7s %7s %7s | %7s | %5s %5s %5s %5s\n" workload cycles first last all first last all all first last all net
        # shellcheck disable=SC2016
        local stats='$2 == w {n++; cpu[n] = $3; ins[n] = $4; cyc[n] = $5; pw[n] = $6}
            function med(a, from, to,   i, k, v, t, x) {k = 0; for (i = from; i <= to; i++) if (a[i] != "nan" && a[i] != "") v[++k] = a[i] + 0
                for (i = 1; i <= k; i++) for (t = i + 1; t <= k; t++) if (v[t] < v[i]) {x = v[i]; v[i] = v[t]; v[t] = x}
                return k ? v[int((k + 1) / 2)] : "nan"}'
        local idle_w
        idle_w=$(awk -v w=w_idle "$stats END {print med(pw, 1, n)}" "$OUT/cpu.txt" 2>/dev/null)
        for w in $(awk '{print $2}' "$OUT/cpu.txt" 2>/dev/null | sort -u); do
            awk -v w="$w" -v idle="${idle_w:-nan}" "$stats"'
                END {h = (n >= 10) ? 5 : int((n + 1) / 2); all = med(pw, 1, n)
                    net = (all == "nan" || idle == "nan") ? "nan" : sprintf("%.2f", all - idle)
                    printf "  %-22s %6d | %6s %6s %6s | %7s %7s %7s | %7s | %5s %5s %5s %5s\n", w, n, med(cpu, 1, h), med(cpu, n - h + 1, n), med(cpu, 1, n),
                        med(ins, 1, h), med(ins, n - h + 1, n), med(ins, 1, n), med(cyc, 1, n), med(pw, 1, h), med(pw, n - h + 1, n), all, net}' "$OUT/cpu.txt"
        done
        echo
        if [ -s "$OUT/glmark2.txt" ]; then
            awk '{n++; s[n] = $2} END {h = (n >= 10) ? 5 : int((n + 1) / 2)
                f = 0; for (i = 1; i <= h; i++) f += s[i]; l = 0; for (i = n - h + 1; i <= n; i++) l += s[i]
                a = 0; for (i = 1; i <= n; i++) a += s[i]
                printf "glmark2 score: first %.0f, last %.0f, mean %.0f (%d runs)\n", f / h, l / h, a / n, n}' "$OUT/glmark2.txt"
        else
            echo "glmark2: not run (glmark2-es2-wayland is not installed)"
        fi
        echo
        echo "state other than ok in $(awk 'NR > 1 && $15 != "ok"' "$OUT/samples.txt" | wc -l) of $(($(wc -l <"$OUT/samples.txt") - 1)) samples"
    } >"$OUT/report.txt"
}

# ---- main loop

log "soak test for $HOURS h, compositor pid $COMP, $(pacman -Q hypoland 2>/dev/null), perf $HAVE_PERF, energy $([ -n "$(energy)" ] && echo RAPL || echo none)"
LAST_EVENTS=$START
LAST_SHOT=0
while [ "$(date +%s)" -lt "$END" ] && [ ! -e "$OUT/stop" ]; do
    CYCLE=$((CYCLE + 1))
    log "cycle $CYCLE"
    for w in w_gpu w_scroll w_scroll_alacritty w_video w_nautilus w_flea w_xwayland_fullscreen w_workspaces w_churn w_capture w_reload w_dpms w_idle w_glmark2; do
        [ "$(date +%s)" -lt "$END" ] && [ ! -e "$OUT/stop" ] || break
        log "  $w"
        measured $w
    done
    # Chromium is heavy on this machine, every third cycle (and in the short run)
    { [ $((CYCLE % 3)) = 0 ] || [ $MAX_CYCLES = 1 ]; } && [ "$(date +%s)" -lt "$END" ] && log "  w_chromium" && measured w_chromium
    now=$(date +%s)
    check_events "$LAST_EVENTS"
    LAST_EVENTS=$now
    if [ $((now - LAST_SHOT)) -ge 3600 ]; then
        timeout 15 grim -s 0.5 "$OUT/shots/$(date +%H%M).png" || log "EVENT hourly screenshot failed"
        LAST_SHOT=$now
    fi
    [ $MAX_CYCLES -gt 0 ] && [ $CYCLE -ge $MAX_CYCLES ] && break
done
