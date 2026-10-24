#!/usr/bin/env bash
# Runs on the machine under test, started by bench.sh, profile.sh or scripts/deploy.sh (over ssh or locally).
# Puts the running compositor under workloads and reports what they cost, or checks that its session works.
# Nothing about the machine is fixed: the compositor, its user, its install prefix and its Wayland socket are
# taken from the running process.
#
# Usage: measure.sh [options]
#   --mode bench|perf|energy|check
#                       bench measures CPU time and memory (default), perf records with perf and prints
#                       where the CPU time goes, energy measures the power the machine draws under each
#                       workload and the instructions the compositor executes, check prints PASS / FAIL
#                       lines for the session (config, a window drawn on the screen, a GPU client, an X11
#                       client, Chromium, errors in the log) and RESULT: PASS or FAIL
#   --seconds N         length of a workload (default 12)
#   --rounds N          how often the workloads are repeated, bench only (default 1)
#   --workloads LIST    comma separated, default: idle,gpu-client,terminal-scroll,alacritty-scroll,video,nautilus,flea,shm-fullwindow,workspace-switch
#   --client NAME=CMD   one more workload: CMD is started as a client and measured as NAME, can be repeated
#   --process NAME      name of the compositor process (default: hypoland, then Hypoland, then Hyprland)
#   --settle N          age of the compositor in seconds before memory is measured (default 60)
#   --keep-governor     leave the CPU frequency governor alone
#   --stages REGEX      functions whose inclusive time perf mode prints
#   --out DIR           directory for raw data on this machine (default: a new one from mktemp -d)
#   --meter auto|rapl|battery|none
#                       energy meter (default auto: RAPL when the CPU has it, else the battery). none only
#                       counts instructions and cycles
#   --idle N            length of the idle baseline taken before and after every workload (default 10)
#   --min-battery N     stop when the battery is below N percent (default 30)
#   --powercap DIR, --power-supply DIR
#                       where the meters are (default /sys/class/powercap and /sys/class/power_supply)
#
# Lines starting with "@" are the values: "@ <round> <key> <value>". A workload whose client is not
# installed is skipped. As root the governor is set to performance and suspend is inhibited for the run;
# without root both are left alone and said so. The energy mode never changes the governor, energy depends
# on it.
#
# Energy: RAPL counts what the CPU package uses (cores, and the GPU where it is in the package). Without
# RAPL (Intel before Sandy Bridge, so the X200) the battery's discharge rate is integrated instead. It
# covers the whole machine, screen included, and only reads while the machine runs on battery. The idle
# baseline around a workload is subtracted, so the net power is what the workload adds: the client and
# the compositor drawing it. Two builds differ only in the compositor's part.

MODE=bench SECONDS_PER_RUN=12 ROUNDS=1 SETTLE=60 PROCESS="" KEEP_GOVERNOR=0 OUT=""
METER=auto IDLE=10 MIN_BATTERY=30 POWERCAP=/sys/class/powercap POWER_SUPPLY=/sys/class/power_supply
WORKLOADS=idle,gpu-client,terminal-scroll,alacritty-scroll,video,nautilus,flea,shm-fullwindow,workspace-switch
STAGES='Render::IHyprRenderer::renderMonitor|Render::GL::CHyprGLRenderer::endRender|Render::GL::CHyprGLRenderer::beginRenderInternal|Render::GL::CEGLSync::create|Render::CRenderPass::render|Render::GL::CHyprOpenGLImpl::end\(\)|Render::GL::CGLFramebuffer::internalAlloc|Render::GL::CGLTexture::update|Aquamarine::CDRMOutput::commitState|drmModeAtomicCommit|Aquamarine::getDRMProp|Aquamarine::getDRMPropBlob|__x64_sys_ioctl|clock_gettime|read_hpet|_CWlSurfaceCommit|shmem_alloc_and_add_folio|drm_clflush_sg|Render::IHyprRenderer::renderLayer|Render::IHyprRenderer::renderAllClientsForWorkspace|Monitor::CMonitor::scheduleFrame|Animation::CHyprAnimationManager::tick|CInputManager::[A-Za-z]+|CPointerManager::[A-Za-z]+'
CLIENT_NAMES=() CLIENT_CMDS=()

while [ $# -gt 0 ]; do
    case $1 in
        --mode) MODE=$2; shift ;;
        --seconds) SECONDS_PER_RUN=$2; shift ;;
        --rounds) ROUNDS=$2; shift ;;
        --workloads) WORKLOADS=$2; shift ;;
        --client) CLIENT_NAMES+=("${2%%=*}"); CLIENT_CMDS+=("${2#*=}"); shift ;;
        --process) PROCESS=$2; shift ;;
        --settle) SETTLE=$2; shift ;;
        --keep-governor) KEEP_GOVERNOR=1 ;;
        --stages) STAGES=$2; shift ;;
        --out) OUT=$2; shift ;;
        --meter) METER=$2; shift ;;
        --idle) IDLE=$2; shift ;;
        --min-battery) MIN_BATTERY=$2; shift ;;
        --powercap) POWERCAP=$2; shift ;;
        --power-supply) POWER_SUPPLY=$2; shift ;;
        *) echo "measure.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
case $MODE in bench | perf | energy | check) ;; *) echo "measure.sh: unknown mode: $MODE" >&2; exit 2 ;; esac
case $METER in auto | rapl | battery | none) ;; *) echo "measure.sh: unknown meter: $METER" >&2; exit 2 ;; esac
[ "$MODE" = energy ] || METER=none

# ---- the compositor and its session

for name in ${PROCESS:-hypoland Hypoland Hyprland}; do
    P=$(pgrep -n -x "$name" 2>/dev/null) && PROCESS=$name && break
done
[ -n "${P:-}" ] || { echo "no compositor is running (looked for ${PROCESS:-hypoland, Hypoland, Hyprland})"; exit 1; }

TESTUSER=$(stat -c %U /proc/$P)
USERHOME=$(getent passwd "$TESTUSER" | cut -d: -f6)
RUNTIME=/run/user/$(id -u "$TESTUSER")
BINARY=$(readlink -f /proc/$P/exe)
BINDIR=$(dirname "$BINARY")
ROOT=0
[ "$(id -u)" = 0 ] && ROOT=1
if [ $ROOT = 0 ] && [ "$(id -un)" != "$TESTUSER" ]; then
    echo "the compositor runs as $TESTUSER, run this as $TESTUSER or as root"
    exit 1
fi

# every instance writes its pid and its Wayland socket into a lock file
LOCK=$(grep -l -x "$P" "$RUNTIME"/hypr/*/hyprland.lock 2>/dev/null | head -1)
[ -n "$LOCK" ] || { echo "no instance directory of pid $P in $RUNTIME/hypr"; exit 1; }
SIG=$(basename "$(dirname "$LOCK")")
SOCKET=$(sed -n 2p "$LOCK")

# clients get the environment the compositor was started with (locale, PATH, XDG variables), plus what the
# compositor sets for its children
mapfile -d '' SESSIONENV </proc/$P/environ
SESSIONENV+=(HOME="$USERHOME" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" HYPRLAND_INSTANCE_SIGNATURE="$SIG")
[ -d /usr/share/omarchy ] && SESSIONENV+=(OMARCHY_PATH=/usr/share/omarchy)

# runs a command in the session of the compositor. The script itself may arrive on stdin, nothing may read from it
asuser() {
    if [ $ROOT = 1 ]; then
        runuser -u "$TESTUSER" -- env -i -C "$USERHOME" "${SESSIONENV[@]}" "$@" </dev/null
    else
        env -i -C "$USERHOME" "${SESSIONENV[@]}" "$@" </dev/null
    fi
}
H() { asuser timeout 8 "$BINDIR/hyprctl" "$@"; }

# the dispatchers are Lua in this version and plain words before it
dispatch() { # lua, legacy
    [ "$(H dispatch "$1" 2>/dev/null)" = ok ] || H dispatch $2 >/dev/null 2>&1
}

# Clients are started as leaders of their own process group and stopped through it, so stopping one takes
# its children along and never hits a window of the user.
CLIENTS=0
client() { # seconds to live, command
    local ttl=$1 pidfile
    shift
    CLIENTS=$((CLIENTS + 1))
    pidfile=$CLIENTDIR/client.$CLIENTS.pid
    rm -f "$pidfile"
    asuser setsid sh -c 'echo $$ >"$0"; exec timeout "$1" sh -c "$2"' "$pidfile" "$ttl" "$*" >/dev/null 2>&1 &
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$pidfile" ] && break
        sleep 0.1
    done
}
stop_clients() {
    local pidfile
    local pid
    for pidfile in "$CLIENTDIR"/client.*.pid; do
        pid=$(cat "$pidfile" 2>/dev/null)
        rm -f "$pidfile"
        # the clients' directory belongs to the compositor user: only signal a process group of that user
        [[ $pid =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || continue
        [ "$(ps -o uid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$(id -u "$TESTUSER")" ] || continue
        kill -- "-$pid" 2>/dev/null
    done
}

# ---- energy meters

# RAPL: the package zones only (intel-rapl:0, not intel-rapl:0:0), the subzones are slices of the package
rapl_zones() {
    local z
    for z in "$POWERCAP"/intel-rapl:*; do
        [[ $(basename "$z") == *:*:* ]] && continue
        [[ $(cat "$z/name" 2>/dev/null) == package* ]] && echo "$z"
    done
}

# batteries that report a discharge rate
batteries() {
    local b
    for b in "$POWER_SUPPLY"/*; do
        [ "$(cat "$b/type" 2>/dev/null)" = Battery ] || continue
        [ -r "$b/power_now" ] || { [ -r "$b/current_now" ] && [ -r "$b/voltage_now" ]; } || continue
        echo "$b"
    done
}

# the discharge rate in µW, over all batteries
battery_power() {
    local b s=0
    for b in $BATTERIES; do
        if [ -r "$b/power_now" ]; then
            s=$((s + $(cat "$b/power_now")))
        else
            s=$((s + $(cat "$b/current_now") * $(cat "$b/voltage_now") / 1000000))
        fi
    done
    echo $s
}

# stops the run when the battery runs low or the charger is plugged in, both would end or spoil it
battery_check() {
    [ "$METER" = battery ] || return 0
    local b status capacity
    for b in $BATTERIES; do
        status=$(cat "$b/status")
        capacity=$(cat "$b/capacity" 2>/dev/null || echo 100)
        if [ "$status" != Discharging ]; then
            echo "$(basename "$b") is $status, the battery can only measure while the machine runs on it"
            value invalid.charger 1
            exit 1
        fi
        if [ "$capacity" -lt "$MIN_BATTERY" ]; then
            echo "$(basename "$b") is at $capacity%, below --min-battery $MIN_BATTERY: stopped, plug the charger in"
            value invalid.battery-low 1
            exit 1
        fi
    done
}

# picks the meter and checks it can be read, before anything is changed on the machine
meter_setup() {
    RAPL_ZONES="" RAPL_WRAP="" BATTERIES="" SAMPLER=""
    if [ "$METER" = auto ]; then
        if [ -n "$(rapl_zones)" ]; then METER=rapl; else METER=battery; fi
    fi
    case $METER in
        rapl)
            RAPL_ZONES=$(rapl_zones)
            [ -n "$RAPL_ZONES" ] || { echo "no RAPL package zones in $POWERCAP"; exit 1; }
            if ! cat $(printf '%s/energy_uj ' $RAPL_ZONES) >/dev/null 2>&1; then
                echo "the RAPL counters are readable by root only: run as root, or"
                echo "    sudo chmod a+r $POWERCAP/intel-rapl:*/energy_uj"
                exit 1
            fi
            RAPL_WRAP=$(for z in $RAPL_ZONES; do cat "$z/max_energy_range_uj"; done)
            ;;
        battery)
            BATTERIES=$(batteries)
            if [ -z "$BATTERIES" ]; then
                echo "no RAPL and no battery that reports its discharge rate, nothing to measure energy with"
                echo "(--meter none only counts instructions and cycles)"
                exit 1
            fi
            if [ "$(cat $(printf '%s/status ' $BATTERIES) | sort -u)" != Discharging ]; then
                echo "this machine has no RAPL, so the battery is the meter and it only reads on battery:"
                echo "unplug the charger and run again, or use --meter none to only count instructions and cycles"
                exit 1
            fi
            battery_check
            ;;
    esac
}

# The sampler logs "<ns> <µJ since the start>" twice a second. RAPL: the steps of the counters, each corrected
# for a wraparound, so a window may be longer than the range of a counter. Battery: the discharge rate
# integrated over time (trapezoids). A window reads the total at its ends from the log.
meter_start() {
    [ "$METER" = none ] && return 0
    (
        zones=($RAPL_ZONES) wrap=($RAPL_WRAP) prev=() cur=() total=0
        read_rapl() {
            cur=()
            for i in "${!zones[@]}"; do cur+=("$(cat "${zones[$i]}/energy_uj")"); done
        }
        if [ "$METER" = rapl ]; then read_rapl; prev=("${cur[@]}"); else p=$(battery_power); fi
        last=$(date +%s%N)
        echo "$last 0"
        while :; do
            sleep 0.5
            now=$(date +%s%N)
            if [ "$METER" = rapl ]; then
                read_rapl
                for i in "${!zones[@]}"; do
                    d=$((cur[i] - prev[i]))
                    [ $d -lt 0 ] && d=$((d + wrap[i]))
                    total=$((total + d))
                done
                prev=("${cur[@]}")
            else
                q=$(battery_power)
                total=$((total + (p + q) * (now - last) / 2000000000))
                p=$q
            fi
            echo "$now $total"
            last=$now
        done
    ) >"$OUT/power.log" &
    SAMPLER=$!
    sleep 1
}

meter_describe() {
    case $METER in
        rapl) echo "RAPL $(for z in $RAPL_ZONES; do cat "$z/name"; done | paste -sd,)" ;;
        battery)
            local b
            for b in $BATTERIES; do
                echo -n "battery $(basename "$b") $(cat "$b/capacity" 2>/dev/null)% "
            done
            echo "(whole machine, screen included)"
            ;;
        none) echo "none, instructions and cycles only" ;;
    esac
}

mark() { date +%s%N; }

# joules between two marks, interpolated between the samples around them
joules() { # mark, mark
    [ "$METER" = none ] && { echo 0; return; }
    # the sampler has to be past the end of the window
    local i
    for i in $(seq 1 30); do
        [ "$(tail -1 "$OUT/power.log" | cut -d' ' -f1)" -ge "$2" ] 2>/dev/null && break
        sleep 0.1
    done
    awk -v t0="$1" -v t1="$2" '
        function at(t,   i) {
            for (i = 2; i <= n; i++)
                if (ts[i] >= t)
                    return e[i - 1] + (e[i] - e[i - 1]) * (t - ts[i - 1]) / (ts[i] - ts[i - 1])
            return e[n]
        }
        NF == 2 {ts[++n] = $1; e[n] = $2}
        END {printf "%.3f", (at(t1) - at(t0)) / 1e6}
    ' "$OUT/power.log"
}

watts() { # mark, mark
    awk -v j="$(joules "$1" "$2")" -v a="$1" -v b="$2" 'BEGIN {printf "%.3f", j / ((b - a) / 1e9)}'
}

# ---- what would spoil the numbers

# The Omarchy shell starts a screensaver after 150 s and locks after 300 s without input. Both are
# switched off for the run with the flag files its own toggles use, and put back afterwards.
OMARCHY=$USERHOME/.local/state/omarchy
HAD_AWAKE=0 HAD_SAVER_OFF=0 GOVERNOR="" INHIBIT="" HEADLESS=""
[ -d "$OMARCHY" ] || OMARCHY=""
[ -n "$OMARCHY" ] && [ -e "$OMARCHY/indicators/stay-awake" ] && HAD_AWAKE=1
[ -n "$OMARCHY" ] && [ -e "$OMARCHY/toggles/screensaver-off" ] && HAD_SAVER_OFF=1

set_governor() { for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "$1" >"$g"; done; }
restore() {
    trap - EXIT
    stop_clients
    if [ -n "$OMARCHY" ]; then
        [ $HAD_AWAKE = 1 ] || rm -f "$OMARCHY/indicators/stay-awake"
        [ $HAD_SAVER_OFF = 1 ] || rm -f "$OMARCHY/toggles/screensaver-off"
    fi
    [ -n "$GOVERNOR" ] && set_governor "$GOVERNOR"
    [ -n "$INHIBIT" ] && kill "$INHIBIT" 2>/dev/null
    [ -n "${SAMPLER:-}" ] && kill "$SAMPLER" 2>/dev/null
    [ -n "$HEADLESS" ] && H output remove "$HEADLESS" >/dev/null
    dispatch "hl.dsp.focus({workspace=1})" "workspace 1"
}
trap restore EXIT
# a lost connection must not leave the machine with the settings of the run
trap 'exit 1' HUP INT TERM PIPE

ROUND=1
value() { echo "@ $ROUND $1 $2"; } # key value
meter_setup

if [ -n "$OMARCHY" ]; then
    asuser mkdir -p "$OMARCHY/indicators" "$OMARCHY/toggles"
    asuser touch "$OMARCHY/indicators/stay-awake" "$OMARCHY/toggles/screensaver-off"
    asuser pkill -f "[o]rg.omarchy.screensaver"
fi
dispatch 'hl.dsp.dpms({action=[[on]]})' "dpms on"

# root writes its data into a directory only it can write to, the clients (run as the compositor user) into
# one they own below it. Others may only pass through (711) to reach the clients' directory.
if [ -z "$OUT" ]; then
    OUT=$(mktemp -d /tmp/hypoland-measure.XXXXXX)
else
    mkdir -p "$OUT"
fi
chmod 711 "$OUT"
CLIENTDIR=$OUT/clients
rm -rf "$CLIENTDIR"
mkdir -m 700 "$CLIENTDIR"
[ $ROOT = 1 ] && chown "$TESTUSER" "$CLIENTDIR"

echo "machine: $(uname -n), $(uname -r), $(nproc) cores, $(awk '/MemTotal/ {printf "%d MiB", $2 / 1024}' /proc/meminfo)"
echo "compositor: $BINARY, pid $P, user $TESTUSER, instance $SIG"
echo "clocksource: $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null)"
[ "$MODE" = energy ] && echo "meter: $(meter_describe)"
meter_start

in_the_way() {
    H clients | grep -q "org.omarchy.screensaver" && echo " SCREENSAVER-RUNNING"
    H monitors | grep -q "solitaryBlockedBy:.*lock" && echo " SESSION-LOCKED"
}

clients() { H clients | awk '/class:/ {print $2}' | sort | uniq -c | awk '{printf "%sx %s, ", $1, $2}'; }

# ---- measuring

# on-CPU time of all threads of the compositor in ns, the 1% steps of pidstat are too coarse for small changes
cputime() { cat /proc/$P/task/*/schedstat 2>/dev/null | awk '{s += $1} END {printf "%.0f\n", s}'; }

memory() { # name
    awk -v r=$ROUND -v n="$1" '
        /^(Rss|Pss|Pss_Anon|Pss_File|Anonymous|AnonHugePages|Private_Clean|Private_Dirty):/ {sub(":", "", $1); printf "@ %s mem.%s.%s_kB %s\n", r, n, $1, $2}
    ' /proc/$P/smaps_rollup
    value "mem.$1.heap_kB" "$(awk '/\[heap\]/ {h = 1; next} h && /^Rss:/ {print $2; exit}' /proc/$P/smaps)"
    # GPU buffers are system memory on integrated graphics and in no process statistic
    # an open DRM file shows up once per file descriptor, a client id is counted once
    cat /proc/$P/fdinfo/* 2>/dev/null | awk -v r=$ROUND -v n="$1" '
        function kib(v, unit) {return unit == "MiB" ? v * 1024 : unit == "KiB" ? v : v / 1024}
        function commit() {
            if (id != "" && !(id in seen)) {
                total += t
                shared += s
                seen[id] = 1
            }
            t = s = 0
        }
        /^drm-client-id:/ {commit(); id = $2}
        /^drm-total-/ {t += kib($2, $3)}
        /^drm-shared-/ {s += kib($2, $3)}
        END {commit(); printf "@ %s mem.%s.gpu_kB %d\n@ %s mem.%s.gpu_private_kB %d\n", r, n, total, r, n, total - shared}'
    value "mem.$1.threads" "$(awk '/^Threads:/ {print $2}' /proc/$P/status)"
}

# the instructions and cycles of the compositor over the window, energy mode only
window() { # name
    if [ "$MODE" = energy ] && command -v perf >/dev/null; then
        perf stat -x, -o "$OUT/$1.perf" -e instructions,cycles -p $P -- sleep "$SECONDS_PER_RUN" >/dev/null 2>&1 && return
    fi
    sleep "$SECONDS_PER_RUN"
}

bench() { # name
    local name=$1 t0 t1 c0 c1 m0 m1 sampler=""
    if command -v pidstat >/dev/null; then
        pidstat -u -p $P 1 "$SECONDS_PER_RUN" >"$OUT/$name.pidstat" &
        sampler=$!
    fi
    battery_check
    m0=$(mark) c0=$(cputime) t0=$(date +%s%N)
    window "$name"
    c1=$(cputime) t1=$(date +%s%N) m1=$(mark)
    [ -n "$sampler" ] && wait "$sampler"
    echo "--- $name; clients: $(clients)$(in_the_way)"
    [ -n "$(in_the_way)" ] && value "invalid.$name" 1
    value "cpu.$name.percent" "$(awk -v c=$((c1 - c0)) -v t=$((t1 - t0)) 'BEGIN {printf "%.2f", 100 * c / t}')"
    if [ "$MODE" = energy ]; then
        [ -s "$OUT/$name.perf" ] && awk -v r=$ROUND -v n="$name" -F, '
            $1 ~ /^[0-9]+$/ {k = $3; sub(/:.*/, "", k); printf "@ %s perf.%s.M%s %.2f\n", r, n, k, $1 / 1e6}
        ' "$OUT/$name.perf"
        if [ "$METER" != none ]; then
            local w
            w=$(watts "$m0" "$m1")
            value "power.$name.W" "$w"
            # the net power needs the idle baseline after the workload, see baseline()
            PENDING="$name $w $(((m1 - m0) / 1000000))"
        fi
    fi
    [ -n "$sampler" ] && awk -v r=$ROUND -v n="$name" -v p="$PROCESS" '
        $1 == "Average:" {printf "@ %s cpu.%s.user %s\n@ %s cpu.%s.kernel %s\n", r, n, $4, r, n, $5; next}
        $NF == p {v = $(NF - 2); s += v; q += v * v; c++}
        END {if (c > 1) printf "@ %s cpu.%s.stddev %.2f\n", r, n, sqrt((q - s * s / c) / (c - 1))}
    ' "$OUT/$name.pidstat"
}

perf_rec() { # name
    local name=$1 c0 c1 t0 t1
    c0=$(cputime) t0=$(date +%s%N)
    perf record -q -F 999 --call-graph fp -p $P -o "$OUT/$name.data" -- sleep "$SECONDS_PER_RUN" >/dev/null 2>&1
    c1=$(cputime) t1=$(date +%s%N)
    local list
    list=$(clients)
    echo
    echo "################ $name"
    echo "compositor cpu $(awk -v c=$((c1 - c0)) -v t=$((t1 - t0)) 'BEGIN {printf "%.2f", 100 * c / t}')%; clients: ${list:-none}$(in_the_way)"
    [ -s "$OUT/$name.data" ] || { echo "perf recorded nothing (kernel.perf_event_paranoid, or perf is not installed)"; return; }
    echo "--- self time by library"
    perf report -i "$OUT/$name.data" --no-children --sort dso --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -6
    echo "--- self time by function"
    perf report -i "$OUT/$name.data" --no-children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -10 | sed -E 's/ +- +- +$//' | cut -c1-140
    echo "--- inclusive time of the main stages"
    perf report -i "$OUT/$name.data" --children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" |
        grep -E "\] ($STAGES)" |
        awk '{k=$0; sub(/^ +[0-9.]+% +[0-9.]+% +\[.\] /,"",k); sub(/\(.*/,"",k); sub(/[ \t-]+$/,"",k); if(!(k in s)){s[k]=1; printf "  %7s  %s\n",$1,k}}' | head -24
}

rec() {
    if [ "$MODE" = perf ]; then perf_rec "$1"; else bench "$1"; fi
}

# ---- workloads: needs_<name> lists the programs a workload starts, workload_<name> runs it

needs_idle=""
workload_idle() {
    sleep 2
    rec idle
}

needs_gpu_client="weston-simple-egl"
workload_gpu_client() {
    local log=$CLIENTDIR/fps.log
    rm -f "$log"
    client $((SECONDS_PER_RUN + 10)) "exec stdbuf -oL weston-simple-egl >$log 2>&1"
    sleep 4
    rec gpu-client
    stop_clients
    # a lower CPU time only counts when the client still gets its frames
    [ "$MODE" != perf ] && value "fps.gpu-client" "$(awk '/frames in/ {s += $(NF - 1); c++} END {if (c) printf "%.1f", s / c; else print "nan"}' "$log" 2>/dev/null)"
}

needs_terminal_scroll="foot"
workload_terminal_scroll() {
    client $((SECONDS_PER_RUN + 10)) "exec foot -e sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec terminal-scroll
    stop_clients
}

needs_alacritty_scroll="alacritty"
workload_alacritty_scroll() { # the same scrolling in a terminal that draws with GL instead of shm
    client $((SECONDS_PER_RUN + 10)) "exec alacritty -e sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec alacritty-scroll
    stop_clients
}

# A 20 s 720p H.264 clip, encoded once into the user's cache. Decoded in software unless the user's mpv config
# says otherwise, as Omarchy's does not.
VIDEO=$USERHOME/.cache/hypoland-bench/video.mp4
needs_video="mpv ffmpeg"
workload_video() { # fullscreen, looping: a 30 fps client buffer that can be scanned out directly
    [ -s "$VIDEO" ] || asuser sh -c 'mkdir -p "${0%/*}" && ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 \
        -t 20 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$0"' "$VIDEO"
    client $((SECONDS_PER_RUN + 10)) "exec mpv --fs --loop-file=inf --no-audio --really-quiet '$VIDEO'"
    sleep 4
    rec video
    stop_clients
}

needs_nautilus="nautilus"
workload_nautilus() { # GTK 4 redrawing a full window of icons, fullscreen toggled twice a second
    local i
    client $((SECONDS_PER_RUN + 15)) "exec nautilus --new-window /usr/share/icons/Adwaita/symbolic/actions"
    sleep 5
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do
        dispatch 'hl.dsp.window.fullscreen({action="toggle"})' "fullscreen"; sleep 0.5
    done) &
    local toggler=$!
    rec nautilus
    wait $toggler
    stop_clients
    # a nautilus that was already running opens the window itself, quitting closes it too
    asuser nautilus -q >/dev/null 2>&1
}

# 25000 empty files, made once in the user's cache, so the listing is the same on every machine and run (the same
# directory as scripts/x200/soak.sh)
FILES=$USERHOME/.cache/hypoland-bench/files-25000
needs_flea="flea"
workload_flea() { # Omarchy's file manager, a Quickshell window, paged through with keys
    local i key
    [ -e "$FILES/file-25000.txt" ] || asuser bash -c 'mkdir -p "$0" && cd "$0" && touch file-{00001..25000}.txt' "$FILES"
    client $((SECONDS_PER_RUN + 20)) "exec flea '$FILES'"
    sleep 8
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do # 4 pages a second, 20 down and 20 back up
        key=Page_Down
        [ $(((i - 1) / 5 % 2)) = 1 ] && key=Page_Up
        for _ in 1 2 3 4; do
            dispatch "hl.dsp.send_shortcut({mods=\"\", key=\"$key\"})" "sendshortcut ,$key,"
            sleep 0.25
        done
    done) &
    local pager=$!
    rec flea
    wait $pager
    stop_clients
    # flea execs qs and leaves a backend; the bracket keeps pkill from matching its own command line
    asuser pkill -f "[q]s -p /usr/share/flea" >/dev/null 2>&1
    asuser pkill -x flea >/dev/null 2>&1
    sleep 1
}

needs_shm_fullwindow="chromium"
workload_shm_fullwindow() {
    local page="data:text/html,<body style='background:linear-gradient(90deg,red,blue)'><marquee scrollamount=20 style='font:60px sans-serif;color:white'>Hypoland</marquee><div style='animation:s 2s linear infinite;width:200px;height:200px;background:lime'></div><style>@keyframes s{to{transform:translateX(900px) rotate(360deg)}}</style>"
    client $((SECONDS_PER_RUN + 40)) "exec chromium --ozone-platform=wayland --no-first-run --user-data-dir=$CLIENTDIR/chromium \"$page\""
    sleep 24
    rec shm-fullwindow
    stop_clients
    sleep 1
}

needs_workspace_switch="foot"
workload_workspace_switch() {
    local i
    for i in 1 2 3; do
        client $((SECONDS_PER_RUN + 15)) "exec foot -e sleep 60"
        sleep 1
    done
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do
        dispatch "hl.dsp.focus({workspace=2})" "workspace 2"; sleep 0.5
        dispatch "hl.dsp.focus({workspace=1})" "workspace 1"; sleep 0.5
    done) &
    local switcher=$!
    rec workspace-switch
    wait $switcher
    stop_clients
}

# a client given with --client
workload_custom() { # name, command
    client $((SECONDS_PER_RUN + 10)) "$2"
    sleep 4
    rec "$1"
    stop_clients
}

missing() { # programs
    local prog
    for prog in $1; do
        asuser sh -c "command -v $prog" >/dev/null 2>&1 || { echo "$prog"; return; }
    done
}

# The power of the idle session, sampled between the workloads. A workload's net power is its power minus the
# mean of the baselines before and after it, half their difference is how far off that mean can be.
PENDING="" BEFORE=""
baseline() {
    if [ "$METER" = none ]; then
        sleep 1
        return
    fi
    sleep 2
    battery_check
    local m0 m1 w name gross ms
    m0=$(mark)
    sleep "$IDLE"
    m1=$(mark)
    w=$(watts "$m0" "$m1")
    value power.baseline.W "$w"
    if [ -n "$PENDING" ] && [ -n "$BEFORE" ]; then
        read -r name gross ms <<<"$PENDING"
        awk -v r=$ROUND -v n="$name" -v g="$gross" -v a="$BEFORE" -v b="$w" -v s="$ms" 'BEGIN {
            net = g - (a + b) / 2
            pm = (a > b ? a - b : b - a) / 2
            printf "@ %s power.%s.net_W %.3f\n@ %s power.%s.pm_W %.3f\n", r, n, net, r, n, pm
            printf "@ %s energy.%s.net_J %.2f\n", r, n, net * s / 1000
            printf "    %.2f W, %.2f W above the idle baseline (+-%.2f W)\n", g, net, pm
        }'
    fi
    PENDING=""
    BEFORE=$w
}

between() {
    if [ "$MODE" = energy ]; then baseline; else sleep 1; fi
}

workloads() {
    local name fn needs lacking i n=0
    [ "$MODE" = energy ] && [ -z "$BEFORE" ] && baseline
    for name in ${WORKLOADS//,/ }; do
        fn=${name//-/_}
        n=$((n + 1))
        if ! declare -F "workload_$fn" >/dev/null || [ "$fn" = custom ]; then
            echo "=== $n $name: no such workload"
            continue
        fi
        needs=needs_$fn
        lacking=$(missing "${!needs}")
        if [ -n "$lacking" ]; then
            echo "=== $n $name: skipped, $lacking is not installed"
            continue
        fi
        echo "=== $n $name"
        "workload_$fn"
        between
    done
    for i in "${!CLIENT_NAMES[@]}"; do
        n=$((n + 1))
        echo "=== $n ${CLIENT_NAMES[$i]}: ${CLIENT_CMDS[$i]}"
        workload_custom "${CLIENT_NAMES[$i]}" "${CLIENT_CMDS[$i]}"
        between
    done
}

# ---- check mode: does the session work, after a deploy

RESULT=0 MONITOR=""
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; RESULT=1; }
skip() { echo "SKIP  $*"; }
info() { echo "INFO  $*"; }

nclients() { H clients -j | grep -c '"address"'; }
# waits until there are more windows than before
mapped() { # windows before, seconds
    local i
    for i in $(seq 1 "$2"); do
        [ "$(nclients)" -gt "$1" ] && return 0
        sleep 1
    done
    return 1
}

# the share of the test color in an image, in percent. A screenshot can have alpha (Chromium's buffers do), which
# would count in the mean
magenta() { magick "$1" -alpha off -fuzz 12% -fill white -opaque '#ff00ff' -fill black +opaque white -format '%[fx:int(mean*100)]' info: 2>/dev/null || echo 0; }
# the frame rate a client printed: weston-simple-egl "... frames in 5 seconds: 60.0 fps", glxgears "= 59.9 FPS"
fps_of() { awk '/frames in/ {s += $(NF - 1); c++} END {if (c) printf "%.0f", s / c; else print 0}' "$1" 2>/dev/null; }

# a screenshot through the compositor of the monitor under test, kept in $OUT
screenshot() { # file name
    asuser timeout 20 grim -o "$MONITOR" "$CLIENTDIR/$1" >/dev/null 2>&1 && cp "$CLIENTDIR/$1" "$OUT/$1"
}
# passes when at least 10% of a screenshot is the test color, trying again for up to N seconds
check_drawn() { # what, file name, seconds to wait for it
    local p start=$SECONDS
    while :; do
        if ! screenshot "$2"; then
            fail "$1: no screenshot from grim"
            return
        fi
        p=$(magenta "$OUT/$2")
        [ "$p" -ge 10 ] || [ $((SECONDS - start)) -ge "${3:-0}" ] && break
        sleep 2
    done
    if [ "$p" -ge 10 ]; then
        pass "$1 ($p% of the screen is the test color${3:+, after $((SECONDS - start)) s})"
    else
        fail "$1: only $p% of the screen is the test color${3:+ after $((SECONDS - start)) s}"
    fi
}

check_config() {
    local out blur
    out=$(H configerrors)
    if [ -z "$(tr -d '[:space:]' <<<"$out")" ]; then pass "config loads without errors"; else fail "config errors: $(head -3 <<<"$out" | tr '\n' ' ')"; fi

    # options are set through eval with a Lua config and through keyword before. Blur is set to the value it
    # has, so the session is left as it was
    blur=$(H getoption decoration:blur:enabled -j | grep -oE '"(bool|int)": *[a-z0-9]+' | grep -oE '[a-z0-9]+$')
    case $blur in 1 | true) blur=true ;; *) blur=false ;; esac
    out=$(H eval "hl.config({decoration={blur={enabled=$blur}}})")
    [ "$out" = ok ] || out=$(H keyword decoration:blur:enabled $blur)
    if [ "$out" = ok ]; then pass "setting an option returns ok"; else fail "setting an option: $out"; fi
    # removed features stay registered as options that do nothing
    out=$(H eval "hl.config({misc={disable_hyprland_logo=true}})")
    [ "$out" = ok ] || out=$(H keyword misc:disable_hyprland_logo true)
    if [ "$out" = ok ]; then pass "setting a removed option returns ok"; else fail "setting a removed option: $out"; fi
}

check_output() {
    MONITOR=$(H monitors | awk '$1 == "Monitor" && $2 != "FALLBACK" {print $2; exit}')
    if [ -z "$MONITOR" ] && [ "$(H output create headless HYPOLAND-CHECK)" = ok ]; then
        # nothing connected: the GPU draws a headless output all the same, it only reaches no screen
        HEADLESS=HYPOLAND-CHECK MONITOR=HYPOLAND-CHECK
        sleep 4
    fi
    if [ -z "$MONITOR" ]; then
        fail "no monitor and no headless output to draw on"
        return 1
    fi
    pass "output $MONITOR: $(H monitors | awk -v m="$MONITOR" '$1 == "Monitor" {on = $2 == m} on && /@/ {print $1; exit}')${HEADLESS:+, headless}"
    if H monitors | grep -q "solitaryBlockedBy:.*lock"; then
        # the lock screen covers every window, and only the password or a new session ends it
        fail "the session is locked, nothing else was checked (systemctl restart sddm as root gives a new session)"
        return 1
    fi
    pass "no lock screen in the way"
    info "$(H layers | grep -c 'namespace:') layer surfaces (bar, wallpaper, notifications)"
}

check_window() {
    local before p
    if [ -n "$(missing foot)" ]; then
        skip "test window: foot is not installed"
        return
    fi
    cat >"$CLIENTDIR/magenta.sh" <<'EOF'
#!/bin/sh
i=0
while [ $i -lt 120 ]; do printf '\033[48;2;255;0;255m%400s' ''; i=$((i + 1)); done
sleep 60
EOF
    before=$(nclients)
    client 60 "exec foot sh $CLIENTDIR/magenta.sh"
    if ! mapped "$before" 10; then
        fail "test window (foot) did not map"
        stop_clients
        return
    fi
    pass "test window mapped"
    sleep 2
    # A screenshot makes the compositor draw through its work buffer for a while, so the buffer the screen scans
    # out is read first: it shows whether drawing straight into it works. Root only, and only unambiguous with
    # one monitor.
    if [ -n "$HEADLESS" ] || [ $ROOT = 0 ] || ! command -v hypoland-kmsgrab >/dev/null ||
        [ "$(H monitors | grep -c '^Monitor ')" != 1 ]; then
        skip "scanned-out buffer (needs root, hypoland-kmsgrab and one real monitor)"
    elif hypoland-kmsgrab "$OUT/scanout.ppm" >/dev/null 2>&1 && magick "$OUT/scanout.ppm" "$OUT/scanout.png" 2>/dev/null; then
        rm -f "$OUT/scanout.ppm"
        p=$(magenta "$OUT/scanout.png")
        if [ "$p" -ge 10 ]; then pass "the screen shows the window ($p% of the scanned-out buffer is the test color)"; else fail "the screen does not show the window: $p% of the scanned-out buffer is the test color"; fi
    else
        fail "hypoland-kmsgrab could not read the scanned-out buffer"
    fi
    check_drawn "test window drawn" window.png
    stop_clients
}

check_chromium() {
    local before page="data:text/html,<body style='background:%23ff00ff'>"
    if [ -n "$(missing chromium)" ]; then
        skip "Chromium is not installed"
        return
    fi
    before=$(nclients)
    client 90 "exec chromium --ozone-platform=wayland --no-first-run --user-data-dir=$CLIENTDIR/chromium \"$page\""
    # Its first frame can take long (5 to 30 s on lianli, r600, with the fresh profile), and until then the window
    # shows a buffer it has not drawn yet
    if mapped "$before" 40; then
        check_drawn "Chromium draws its page" chromium.png 60
    else
        fail "Chromium did not map a window"
    fi
    stop_clients
    sleep 1
}

check_clients() {
    local fps display
    if [ -n "$(missing weston-simple-egl)" ]; then
        skip "GPU client: weston-simple-egl is not installed"
    else
        client 15 "exec stdbuf -oL weston-simple-egl >$CLIENTDIR/egl.log 2>&1"
        sleep 12
        stop_clients
        fps=$(fps_of "$CLIENTDIR/egl.log")
        if [ "$fps" -ge 20 ]; then pass "GPU client (weston-simple-egl) at $fps fps"; else fail "GPU client (weston-simple-egl) at $fps fps"; fi
    fi

    # Xwayland starts with the first X11 client; its display is in the environment of the session
    display=$(asuser systemctl --user show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p')
    if [ -n "$(missing glxgears)" ]; then
        skip "X11 client: glxgears is not installed"
    elif [ -z "$display" ]; then
        skip "X11 client: no DISPLAY in the environment of the session"
    else
        client 15 "exec env DISPLAY=$display stdbuf -oL glxgears >$CLIENTDIR/gears.log 2>&1"
        sleep 12
        stop_clients
        fps=$(fps_of "$CLIENTDIR/gears.log")
        if [ "$fps" -ge 20 ]; then pass "X11 client through Xwayland (glxgears) at $fps fps"; else fail "X11 client through Xwayland (glxgears) at $fps fps"; fi
    fi
}

check_logs() {
    local since=$1 n
    n=$( (asuser journalctl --user _PID=$P -o cat 2>/dev/null; cat "$RUNTIME/hypr/$SIG/hyprland.log" 2>/dev/null) |
        grep -ciE "GL_INVALID|GLES error|shader.*fail|Failed to (link|compile)")
    if [ "$n" = 0 ]; then pass "no GL or shader errors in the compositor's log"; else fail "$n GL or shader error lines in the compositor's log"; fi
    n=$(find "$USERHOME/.cache/hyprland" -type f -newermt "@$since" 2>/dev/null | wc -l)
    if [ "$n" = 0 ]; then pass "no new crash reports"; else fail "$n new crash reports in $USERHOME/.cache/hyprland"; fi
    if [ $ROOT = 1 ] && command -v coredumpctl >/dev/null; then
        n=$(coredumpctl list --no-legend --no-pager --since "@$since" 2>/dev/null | awk '{print $NF}' | sort | uniq -c | awk '{printf "%s %sx, ", $2, $1}')
        if [ -z "$n" ]; then pass "no core dumps"; else info "core dumps since the compositor started: ${n%, }"; fi
    fi
    if pgrep -x "$PROCESS" | grep -qx "$P"; then pass "the compositor ran through without a restart"; else fail "the compositor restarted or died"; fi
}

checks() {
    local since
    # a session that was just started needs a moment for its shell and autostart
    [ "$(ps -o etimes= -p $P)" -lt 20 ] && sleep $((20 - $(ps -o etimes= -p $P)))
    since=$(($(date +%s) - $(ps -o etimes= -p $P)))
    if ! H version >/dev/null 2>&1; then
        fail "hyprctl does not answer"
        return
    fi
    pass "compositor running, hyprctl responds"
    info "$(H version | head -1 | sed 's/ (.*//')"
    info "$(H version | grep -m1 '^Hypoland')"
    check_config
    check_output || return
    check_window
    check_chromium
    check_clients
    info "compositor memory: $(awk '/^(Rss|Pss|Anonymous):/ {printf "%s %d MiB, ", $1, $2 / 1024}' /proc/$P/smaps_rollup | sed 's/, $//')"
    check_logs "$since"
}

if [ "$MODE" = check ]; then
    checks
    echo "screenshots: $OUT on $(uname -n)"
    if [ $RESULT = 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; fi
    exit $RESULT
fi

if [ "$MODE" = perf ]; then
    workloads
    echo
    echo "perf data: $OUT on $(uname -n)"
    exit 0
fi

# frequency scaling and a suspend would both spoil the numbers
if [ $ROOT = 1 ] && [ $KEEP_GOVERNOR = 0 ] && [ "$MODE" = bench ] && [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    set_governor performance
    echo "governor: $GOVERNOR -> performance"
else
    echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo none), left alone"
fi
if [ $ROOT = 1 ] && command -v systemd-inhibit >/dev/null; then
    systemd-inhibit --what=sleep:idle:handle-lid-switch --why="compositor benchmark" sleep infinity </dev/null &
    INHIBIT=$!
fi
AC=$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1)
[ "$AC" = 0 ] && [ "$METER" != battery ] && echo "WARNING: running on battery"

value "binary.size_kB" "$(($(stat -c %s "$BINARY") / 1024))"

# memory is compared when the session has settled
AGE=$(ps -o etimes= -p $P)
[ "$AGE" -lt "$SETTLE" ] && sleep $((SETTLE - AGE))
value "compositor.age_s" "$(ps -o etimes= -p $P | tr -d ' ')"
memory start

for ROUND in $(seq 1 "$ROUNDS"); do
    echo "====== round $ROUND of $ROUNDS"
    workloads
done

# what the workloads left behind: leaks, caches and buffers that are never given back
sleep 10
memory end
pgrep -x "$PROCESS" | grep -qx "$P" || value "invalid.compositor-restarted" 1
