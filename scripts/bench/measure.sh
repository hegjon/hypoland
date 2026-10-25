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
#                       client, Chromium, GTK 3 (also through Xwayland), GTK 4 and Qt Quick windows, errors
#                       in the log) and RESULT: PASS or FAIL
#   --seconds N         length of a workload (default 12)
#   --rounds N          how often the workloads are repeated, bench only (default 1)
#   --workloads LIST    comma separated, default: idle,gpu-client,terminal-scroll,alacritty-scroll,video,nautilus,flea,shm-fullwindow,workspace-switch,gtk3-scroll,gtk4-scroll,qt-quick-scroll,qt-software-scroll,gtk3-x11-scroll,gtk4-spinner,qt-software-sprites,video-window,idle-windows,dev
#   --client NAME=CMD   one more workload: CMD is started as a client and measured as NAME, can be repeated
#   --env NAME=VALUE    a variable for the clients, as a session's hl.env gives it to the programs it starts (the
#                       Mesa overrides of Omarchy's GLES 3 override for stock Hyprland on the X200), can be repeated
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
WORKLOADS=idle,gpu-client,terminal-scroll,alacritty-scroll,video,nautilus,flea,shm-fullwindow,workspace-switch,gtk3-scroll,gtk4-scroll,qt-quick-scroll,qt-software-scroll,gtk3-x11-scroll,gtk4-spinner,qt-software-sprites,video-window,idle-windows,dev
STAGES='Render::IHyprRenderer::renderMonitor|Render::GL::CHyprGLRenderer::endRender|Render::GL::CHyprGLRenderer::beginRenderInternal|Render::GL::CEGLSync::create|Render::CRenderPass::render|Render::GL::CHyprOpenGLImpl::end\(\)|Render::GL::CGLFramebuffer::internalAlloc|Render::GL::CGLTexture::update|Aquamarine::CDRMOutput::commitState|drmModeAtomicCommit|Aquamarine::getDRMProp|Aquamarine::getDRMPropBlob|__x64_sys_ioctl|clock_gettime|read_hpet|_CWlSurfaceCommit|shmem_alloc_and_add_folio|drm_clflush_sg|Render::IHyprRenderer::renderLayer|Render::IHyprRenderer::renderAllClientsForWorkspace|Monitor::CMonitor::scheduleFrame|Animation::CHyprAnimationManager::tick|CInputManager::[A-Za-z]+|CPointerManager::[A-Za-z]+'
CLIENT_NAMES=() CLIENT_CMDS=() CLIENT_ENV=()

while [ $# -gt 0 ]; do
    case $1 in
        --mode) MODE=$2; shift ;;
        --seconds) SECONDS_PER_RUN=$2; shift ;;
        --rounds) ROUNDS=$2; shift ;;
        --workloads) WORKLOADS=$2; shift ;;
        --client) CLIENT_NAMES+=("${2%%=*}"); CLIENT_CMDS+=("${2#*=}"); shift ;;
        --env) CLIENT_ENV+=("$2"); shift ;;
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
SESSIONENV+=("${CLIENT_ENV[@]}")

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
    # a notification left on the screen is drawn over the windows in every frame
    asuser /usr/share/omarchy/bin/omarchy-shell -q notifications dismissAll >/dev/null 2>&1
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

# GPU buffers are system memory on integrated graphics and in no process statistic. Prints the total, the shared and the
# purgeable part in KiB: an open DRM file shows up once per file descriptor, a client id is counted once. Purgeable
# buffers are those Mesa keeps in its cache for reuse, counted in the total, but the kernel takes them back when it
# needs memory
gpu_memory() {
    cat /proc/$P/fdinfo/* 2>/dev/null | awk '
        function kib(v, unit) {return unit == "MiB" ? v * 1024 : unit == "KiB" ? v : v / 1024}
        function commit() {
            if (id != "" && !(id in seen)) {
                total += t
                shared += s
                purgeable += u
                seen[id] = 1
            }
            t = s = u = 0
        }
        /^drm-client-id:/ {commit(); id = $2}
        /^drm-total-/ {t += kib($2, $3)}
        /^drm-shared-/ {s += kib($2, $3)}
        /^drm-purgeable-/ {u += kib($2, $3)}
        END {commit(); printf "%d %d %d\n", total, shared, purgeable}'
}

memory() { # name
    local gpu shared purgeable
    awk -v r=$ROUND -v n="$1" '
        /^(Rss|Pss|Pss_Anon|Pss_File|Anonymous|AnonHugePages|Private_Clean|Private_Dirty):/ {sub(":", "", $1); printf "@ %s mem.%s.%s_kB %s\n", r, n, $1, $2}
    ' /proc/$P/smaps_rollup
    value "mem.$1.heap_kB" "$(awk '/\[heap\]/ {h = 1; next} h && /^Rss:/ {print $2; exit}' /proc/$P/smaps)"
    read -r gpu shared purgeable < <(gpu_memory)
    value "mem.$1.gpu_kB" "$gpu"
    value "mem.$1.gpu_private_kB" "$((gpu - shared))"
    value "mem.$1.gpu_purgeable_kB" "$purgeable"
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
    [ "$MODE" != perf ] && value "fps.gpu-client" "$(fps_mean "$log")"
}

# the mean of the frame rates a client printed like weston-simple-egl ("... frames in 5 seconds: 60.0 fps"), after
# its first N reports
fps_mean() { # log, N
    awk -v skip="${2:-0}" '/frames in/ && ++n > skip {s += $(NF - 1); c++} END {if (c) printf "%.1f", s / c; else print "nan"}' "$1" 2>/dev/null
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
video_workload() { # workload, mpv options. The clip loops: a 30 fps client buffer
    [ -s "$VIDEO" ] || asuser sh -c 'mkdir -p "${0%/*}" && ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 \
        -t 20 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$0"' "$VIDEO"
    client $((SECONDS_PER_RUN + 10)) "exec mpv $2 --loop-file=inf --no-audio --really-quiet '$VIDEO'"
    sleep 4
    rec "$1"
    stop_clients
}

needs_video="mpv ffmpeg"
workload_video() { video_workload video --fs; } # fullscreen, where the buffer can be scanned out directly

needs_video_window="mpv ffmpeg"
workload_video_window() { video_workload video-window; } # in a tiled window, every frame is composited

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

# ---- toolkits: test windows in GTK 3, GTK 4 and Qt Quick, for the workloads and the checks

# A toolkit window shows a long text. By default it scrolls the text at 400 pixels per second, a full window of
# damage on every frame. "spinner" (GTK) keeps the text still under a spinning spinner, a small damage region;
# "sprites" (Qt) moves 60 small squares over it, many small regions. "check" scrolls on the test color. The window
# prints the renderer the toolkit picked and its frame rate like weston-simple-egl.
# GTK 3 draws with cairo into shm buffers, through Xwayland as well. GTK 4 picks its renderer itself: cairo, also
# into shm buffers, where it finds neither GLES 3 nor Vulkan (the X200). Qt Quick draws with GL, its software
# backend into shm buffers like Qt Widgets, and only redraws what changed. Qt logs to the journal when the session
# has one, QT_FORCE_STDERR_LOGGING brings the frame rate to the log.
toolkit() { # gtk3|gtk4|gtk3-x11|qt-quick|qt-software, [check|spinner|sprites]
    [ -s "$CLIENTDIR/toolkit.qml" ] || toolkit_sources
    case $1 in
        gtk3 | gtk4) echo "exec env GDK_BACKEND=wayland python3 -I $CLIENTDIR/toolkit.py ${1#gtk}.0 $2" ;;
        gtk3-x11) echo "exec env GDK_BACKEND=x11 DISPLAY=$(xdisplay) python3 -I $CLIENTDIR/toolkit.py 3.0 $2" ;;
        qt-quick) echo "exec env QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 qml6 $CLIENTDIR/toolkit.qml -- $2" ;;
        qt-software) echo "exec env QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 QT_QUICK_BACKEND=software qml6 $CLIENTDIR/toolkit.qml -- $2" ;;
    esac
}

toolkit_name() { # gtk3|gtk4|gtk3-x11|qt-quick|qt-software
    case $1 in
        gtk3) echo "GTK 3" ;;
        gtk4) echo "GTK 4" ;;
        gtk3-x11) echo "GTK 3 (Xwayland)" ;;
        qt-quick) echo "Qt Quick" ;;
        qt-software) echo "Qt Quick (software)" ;;
    esac
}

renderer_of() { sed -n 's/.*renderer: //p' "$1" 2>/dev/null | head -n 1; } # log

# Xwayland starts with the first X11 client; its display is in the environment of the session
xdisplay() { asuser systemctl --user show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p'; }

toolkit_sources() {
    cat >"$CLIENTDIR/toolkit.py" <<'EOF'
# A GTK 3 or GTK 4 window with a long text: scrolls it at a constant speed, or with "spinner" keeps it still under
# a spinner. Prints the renderer GTK picked and every 5 s its frame rate, the way weston-simple-egl does. With
# "check" it draws on the test color.
import sys

import gi
from gi.repository import GLib

version, mode = sys.argv[1], "".join(sys.argv[2:3])
GTK3 = version == "3.0"
# the app id of the window, set before GTK starts
GLib.set_prgname(f"hypoland-gtk{version[0]}-test")
gi.require_version("Gdk", version)
gi.require_version("Gtk", version)
from gi.repository import Gdk, Gtk

TEXT = "\n".join(f"{i:5}  the quick brown fox jumps over the lazy dog {i * 7919 % 100000:05}" for i in range(1, 2001))
SPEED = 0 if mode == "spinner" else 400  # pixels per second

if mode == "check":
    css = Gtk.CssProvider()
    style = "window, textview, textview text { background: #ff00ff; color: #202020; }"
    if GTK3:
        css.load_from_data(style.encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    else:
        css.load_from_string(style)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)

view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True)
view.get_buffer().set_text(TEXT)
scrolled = Gtk.ScrolledWindow(vexpand=True)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
window = Gtk.Window(title="Hypoland GTK test")
window.set_default_size(1200, 800)
start = last = count = 0


# runs once per frame, frames come with the compositor's frame callbacks
def tick(widget, clock):
    global start, last, count
    now = clock.get_frame_time()
    if not last:
        start = now
        print("renderer:", "cairo" if GTK3 else type(window.get_renderer()).__name__.removesuffix("Renderer").lower(), flush=True)
    else:
        adj = scrolled.get_vadjustment()
        y = adj.get_value() + SPEED * (now - last) / 1e6
        adj.set_value(0 if y >= adj.get_upper() - adj.get_page_size() else y)
        count += 1
        if now - start >= 5e6:
            print(f"{count} frames in 5 seconds: {count * 1e6 / (now - start):.1f} fps", flush=True)
            start, count = now, 0
    last = now
    return True


scrolled.add_tick_callback(tick)
widgets = [scrolled]
if mode == "spinner":
    spinner = Gtk.Spinner()
    spinner.set_size_request(48, 48)
    spinner.start()
    widgets.insert(0, spinner)
if GTK3:
    scrolled.add(view)
    for w in widgets:
        box.pack_start(w, w is scrolled, True, 0)
    window.add(box)
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    Gtk.main()
else:
    loop = GLib.MainLoop()
    scrolled.set_child(view)
    for w in widgets:
        box.append(w)
    window.set_child(box)
    window.connect("close-request", lambda _: loop.quit())
    window.present()
    loop.run()
EOF
    cat >"$CLIENTDIR/toolkit.qml" <<'EOF'
// The Qt Quick counterpart of toolkit.py: a window with a long text that scrolls at a constant speed, or with
// "sprites" stays still under 60 small moving squares. Prints the graphics API Qt Quick picked and every 5 s its
// frame rate, the way weston-simple-egl does. With "check" it draws on the test color.
import QtQuick

Window {
    id: window

    readonly property bool check: Qt.application.arguments.indexOf("check") >= 0
    readonly property bool sprites: Qt.application.arguments.indexOf("sprites") >= 0
    // seconds the sprites have moved
    property real time: 0
    // the frames Qt Quick swapped: it waits for the compositor's frame callbacks first, its animations do not
    property real start: 0
    property int count: 0

    // a position going back and forth between 0 and range
    function bounce(p, range) {
        const m = p % (2 * range);
        return m < range ? m : 2 * range - m;
    }

    width: 1200
    height: 800
    visible: true
    title: "Hypoland Qt test"
    color: check ? "#ff00ff" : "#1e1e1e"

    onFrameSwapped: {
        const now = Date.now();
        if (!start) {
            start = now;
            const api = list.GraphicsInfo.api;
            console.log("renderer: " + (api === GraphicsInfo.OpenGL ? "opengl" : api === GraphicsInfo.Software ? "software" : api === GraphicsInfo.Vulkan ? "vulkan" : "graphics API " + api));
        } else {
            count++;
            if (now - start >= 5000) {
                console.log(count + " frames in 5 seconds: " + (count * 1000 / (now - start)).toFixed(1) + " fps");
                start = now;
                count = 0;
            }
        }
    }

    ListView {
        id: list

        anchors.fill: parent
        interactive: false
        model: 2000
        delegate: Text {
            required property int index

            text: ("    " + (index + 1)).slice(-5) + "  the quick brown fox jumps over the lazy dog " + ("0000" + (index + 1) * 7919 % 100000).slice(-5)
            font.family: "monospace"
            color: window.check ? "#202020" : "#d0d0d0"
        }
    }

    Repeater {
        model: window.sprites ? 60 : 0

        Rectangle {
            required property int index

            width: 24
            height: 24
            color: Qt.hsla(index / 60, 0.8, 0.5, 1)
            x: window.bounce(index * 97 + (80 + index * 37 % 200) * window.time, window.width - width)
            y: window.bounce(index * 61 + (60 + index * 53 % 200) * window.time, window.height - height)
        }
    }

    FrameAnimation {
        running: true
        onTriggered: {
            if (window.sprites) {
                window.time += frameTime;
                return;
            }
            const y = list.contentY + 400 * frameTime;
            list.contentY = y >= list.contentHeight - list.height ? 0 : y;
        }
    }
}
EOF
}

toolkit_workload() { # workload, client, mode
    local log=$CLIENTDIR/$1.log warmup
    rm -f "$log"
    client $((SECONDS_PER_RUN + 10)) "$(toolkit "$2" "$3") >$log 2>&1"
    sleep 5
    # what the client reported while it started is not measured
    warmup=$(grep -c "frames in" "$log" 2>/dev/null)
    rec "$1"
    stop_clients
    echo "    $(toolkit_name "$2"), renderer $(renderer_of "$log")"
    [ "$MODE" != perf ] && value "fps.$1" "$(fps_mean "$log" "$warmup")"
}

needs_gtk3_scroll="python3 gi:Gtk-3.0"
workload_gtk3_scroll() { toolkit_workload gtk3-scroll gtk3; }

needs_gtk4_scroll="python3 gi:Gtk-4.0"
workload_gtk4_scroll() { toolkit_workload gtk4-scroll gtk4; }

needs_qt_quick_scroll="qml6"
workload_qt_quick_scroll() { toolkit_workload qt-quick-scroll qt-quick; }

needs_qt_software_scroll="qml6"
workload_qt_software_scroll() { toolkit_workload qt-software-scroll qt-software; }

# The same GTK 3 window as an X11 client, drawn through Xwayland. It gets no frame callbacks, so its frame rate is
# its own pace, not what the compositor presents
needs_gtk3_x11_scroll="python3 gi:Gtk-3.0 x11"
workload_gtk3_x11_scroll() { toolkit_workload gtk3-x11-scroll gtk3-x11; }

needs_gtk4_spinner="python3 gi:Gtk-4.0"
workload_gtk4_spinner() { toolkit_workload gtk4-spinner gtk4 spinner; }

needs_qt_software_sprites="qml6"
workload_qt_software_sprites() { toolkit_workload qt-software-sprites qt-software sprites; }

# Three terminals that print for 4 s and then wait: the memory idle shm windows keep in the compositor, measured while
# they are open (mem.idle-windows.*). A window that never drew again after its last resize has no second texture to
# give back, see CGLTexture::update(); real windows mostly have (typing, a page that loads)
needs_idle_windows="foot"
workload_idle_windows() {
    local i total purgeable before after
    # what the kernel cannot take back: Mesa keeps freed buffers in its cache, purgeable
    read -r total _ purgeable < <(gpu_memory)
    before=$((total - purgeable))
    for i in 1 2 3; do
        client $((SECONDS_PER_RUN + 25)) "exec foot -e sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do ls -la /usr/lib | head -n 8; sleep 0.4; done; exec sleep 600'"
        sleep 1
    done
    sleep 4
    rec idle-windows
    memory idle-windows
    # what the windows hold. Only meaningful as the first workload of a fresh session: buffers an earlier workload
    # left behind are freed meanwhile. radeon reports no memory in fdinfo, it reads 0 there
    read -r total _ purgeable < <(gpu_memory)
    after=$((total - purgeable))
    value "mem.idle-windows.gpu_added_kB" "$((after - before))"
    stop_clients
}

# A developer's screen as dwindle tiles it: an editor on the left half, on the right a console above a terminal
# that keeps changing. All three are Alacritty, which draws with GL (terminal-scroll and idle-windows have foot's
# shm). The editor is nvim without the user's config (Omarchy's LazyVim would set itself up on a first start) on a
# generated C file of 210000 lines, the console a shell in a generated git repository whose commits add 3000 lines
# each, with 9000 lines changed and not committed. They are the same on every machine and generated again when the
# generator changes.
DEV=$USERHOME/.cache/hypoland-bench/dev
dev_sources() {
    cat >"$CLIENTDIR/dev-gen.sh" <<'EOF'
set -e
mkdir -p "$1"
cd "$1"
awk 'BEGIN {
    print "/* items.c, generated for the Hypoland benchmark */"
    print "#include <stdio.h>\n#include <stdlib.h>\n\nstruct item {\n    int count;\n    int *values;\n    const char *name;\n};\n"
    for (i = 1; i <= 14000; i++) {
        printf "/*\n * f%05d: adds up the values of an item that are %d modulo %d, takes v off the others\n */\n", i, i % 7, 7 + i % 5
        printf "static int f%05d(const struct item *it, int v) {\n    int sum = %d;\n\n", i, i % 101
        printf "    for (int i = 0; i < it->count; i++) {\n        if (it->values[i] %% %d == %d)\n", 7 + i % 5, i % 7
        printf "            sum += it->values[i] * %d;\n        else\n            sum -= v;\n    }\n", i % 13 + 2
        printf "    printf(\"%%s: f%05d %%d\\n\", it->name, sum);\n    return sum + %d;\n}\n\n", i, i % 997
    }
}' >a.c
awk '/^    return sum \+/ && ++n % 3 == 0 {sub(/;$/, " + 1;")} {print}' a.c >b.c
diff -u --color=always a.c b.c >dev.diff || true
# the user's git config stays out of it, a signing key or a hook would change what happens
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Dev GIT_AUTHOR_EMAIL=dev@example.org GIT_COMMITTER_NAME=Dev GIT_COMMITTER_EMAIL=dev@example.org
rm -rf repo
mkdir -p repo/src
cd repo
git init -q -b main
for i in $(seq 1 30); do
    head -n $((i * 3000)) ../a.c >src/items.c
    echo "items $i" >VERSION
    git add -A
    GIT_AUTHOR_DATE="@$((1767268800 + i * 3600)) +0000" GIT_COMMITTER_DATE="@$((1767268800 + i * 3600)) +0000" \
        git commit -q -m "items: add f$(((i - 1) * 200 + 1)) to f$((i * 200))"
done
# a change that is not committed, for git status and a git diff of 9000 lines
awk '/sum -= v;/ && ++n % 4 == 0 {sub(/v;/, "v + 1;")} {print}' ../a.c | head -n 90000 >src/items.c
EOF
    cat >"$CLIENTDIR/dev-move.lua" <<'EOF'
-- moves through the file while the editor has the focus, the way holding a key does: a line forty times a second,
-- and every 2 seconds a jump to another part of the file. Stops once the file DEV_QUIET names is there
local step, focused, quiet = 0, true, os.getenv("DEV_QUIET")
vim.api.nvim_create_autocmd("FocusGained", { callback = function() focused = true end })
vim.api.nvim_create_autocmd("FocusLost", { callback = function() focused = false end })
vim.uv.new_timer():start(1000, 25, vim.schedule_wrap(function()
    if not focused or (quiet and vim.uv.fs_stat(quiet)) then
        return
    end
    step = step + 1
    if step % 80 == 0 then
        vim.cmd("normal! " .. (step * 7919 % vim.fn.line("$") + 1) .. "Gzz")
    else
        vim.cmd("normal! \5")
    end
end))
EOF
    # the shell of the console, git diff runs through a pager that pages through it for 2 s
    cat >"$CLIENTDIR/dev-shellrc" <<'EOF'
cd "$DEV_REPO"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_PAGER=cat PAGER=cat
git() {
    if [ "$1" = diff ]; then
        command git -c color.ui=always "$@" | python3 -I "$DEV_PAGER" 2
    else
        command git "$@"
    fi
}
PS1='\[\033[1;32m\]a@dev\[\033[0m\]:\[\033[1;34m\]~/repo\[\033[0m\]\$ '
EOF
    cat >"$CLIENTDIR/dev-log.py" <<'EOF'
# a busy server's log: 200 lines a second, and every 10 s the trace of a failing request, 400 lines at once
import sys
import time

i = 0
while True:
    stamp = time.strftime("%H:%M:%S")
    for _ in range(10):
        i += 1
        level = "\033[33mWARN\033[0m " if i % 37 == 0 else "INFO "
        sys.stdout.write(f"{stamp}.{i * 7 % 1000:03d} {level} worker-{i % 8}: GET /api/items/{i * 7919 % 100000} 200 in {i % 97 + 3} ms\n")
    if i % 2000 == 0:
        sys.stdout.write(f"{stamp} \033[31mERROR\033[0m worker-{i % 8}: request {i} failed\n")
        sys.stdout.writelines(f"    at f{(i + k) % 14000 + 1:05d} (items.c:{(i * k) % 210000 + 1})\n" for k in range(400))
    sys.stdout.flush()
    time.sleep(0.05)
EOF
    cat >"$CLIENTDIR/dev-pager.py" <<'EOF'
# pages through what comes on stdin the way holding space in less does, ten pages a second for as many seconds as
# the first argument says
import os
import sys
import time

lines = sys.stdin.read().splitlines()
rows = os.get_terminal_size(1).lines - 1
end = time.monotonic() + float(sys.argv[1])
for n in range(0, len(lines), rows):
    sys.stdout.write("\033[H\033[2J" + "\n".join(lines[n : n + rows]))
    sys.stdout.flush()
    time.sleep(0.1)
    if time.monotonic() > end:
        break
print()
EOF
    dev_driver_source
    if [ "$(cat "$DEV/generator" 2>/dev/null)" != "$(md5sum <"$CLIENTDIR/dev-gen.sh")" ]; then
        asuser bash "$CLIENTDIR/dev-gen.sh" "$DEV" >/dev/null 2>&1 &&
            asuser sh -c 'md5sum <"$0" >"$1"' "$CLIENTDIR/dev-gen.sh" "$DEV/generator"
    fi
}

dev_windows() { # editor, console, lower right terminal: the commands they run
    local xy before
    # each window has to be there before the next one splits it
    before=$(nclients)
    client $((SECONDS_PER_RUN + 150)) "exec alacritty --class hypoland-dev-editor -e $1"
    mapped "$before" 10
    before=$(nclients)
    client $((SECONDS_PER_RUN + 150)) "exec env DEV_REPO='$DEV/repo' DEV_SHELLRC=$CLIENTDIR/dev-shellrc DEV_PAGER=$CLIENTDIR/dev-pager.py alacritty --class hypoland-dev-console -e $2"
    mapped "$before" 10
    # dwindle splits the window under the pointer, which has to be the console on the right
    xy=$(H monitors | awk '/^Monitor/ {m = 1} m && / at / {split($1, r, "[x@]"); split($3, p, "x")} m && /scale:/ {s = $2}
        m && /focused: yes/ {printf "%d %d", p[1] + r[1] / s * 3 / 4, p[2] + r[2] / s / 2; exit}')
    dispatch "hl.dsp.cursor.move({x=${xy% *}, y=${xy#* }})" "movecursor $xy"
    before=$(nclients)
    client $((SECONDS_PER_RUN + 150)) "exec alacritty --class hypoland-dev-lower -e $3"
    mapped "$before" 10
    sleep 4
}

focus() { # class
    local address
    address=$(window_address "$1")
    dispatch "hl.dsp.focus({window=\"address:$address\"})" "focuswindow address:$address"
}

# The developer's screen driven by a uinput keyboard (root only) through dev.py, first under load and then key by
# key. Load: every 3 s the focus moves (SUPER+Left, SUPER+Right, the binds of Omarchy) between the editor, which
# scrolls a line 40 times a second and jumps every 2 s while it has the focus, and the console, which gets a command
# typed into it: every other time a diff of 9000 lines paged through, in between ls, git status or a commit of 3000
# lines. Below the console a busy log that never has the focus. The CPU time of the compositor is measured over it
# (cpu.dev.*). Then the editor stops scrolling by itself, and dev.py waits for every key until the frame that shows
# it: moving to the editor and back, scrolling (Ctrl-D, Ctrl-U), jumping to a line (<line>G), typing a command.
# Medians and 90th percentiles in ms (latency.dev.*). Screencopy takes the compositor off direct rendering while it
# captures, which is why the CPU time is measured before.
needs_dev="alacritty nvim git python3 root"
workload_dev() {
    local driver border kind line median p90 n timeouts i
    # the keys would go into the password field of a lock screen
    if [ -n "$(in_the_way)" ]; then
        echo "--- dev: not measured,$(in_the_way)"
        value "invalid.dev" 1
        return
    fi
    dev_sources
    rm -f "$CLIENTDIR/dev-quiet" "$OUT/dev.txt"
    dev_windows "env DEV_QUIET=$CLIENTDIR/dev-quiet nvim --clean -R -n -i NONE -S $CLIENTDIR/dev-move.lua +200 '$DEV/a.c'" \
        "bash --rcfile $CLIENTDIR/dev-shellrc -i" "python3 -I -u $CLIENTDIR/dev-log.py"
    focus hypoland-dev-console
    sleep 1
    H clients -j >"$OUT/dev.clients.json"
    H monitors -j >"$OUT/dev.monitors.json"
    border=$(H getoption general:border_size | awk '/^int:/ {print $2}')
    env -i PATH="$PATH" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" python3 -I "$CLIENTDIR/dev.py" \
        --clients "$OUT/dev.clients.json" --monitors "$OUT/dev.monitors.json" --editor hypoland-dev-editor \
        --console hypoland-dev-console --border "${border:-2}" --load "$SECONDS_PER_RUN" --quiet "$CLIENTDIR/dev-quiet" \
        >"$OUT/dev.txt" 2>&1 &
    driver=$!
    # the keyboard is there after 2 s
    for i in $(seq 1 50); do
        grep -q "^load" "$OUT/dev.txt" && break
        sleep 0.2
    done
    rec dev
    wait "$driver"
    [ -n "$(in_the_way)" ] && value "invalid.dev" 1
    stop_clients
    grep -v -E "^(load|latency)" "$OUT/dev.txt" | sed 's/^/    /'
    for kind in focus scroll jump type; do
        timeouts=$(grep -c "^latency $kind timeout" "$OUT/dev.txt")
        [ "$timeouts" -gt 0 ] && value "latency.dev.${kind}_timeouts" "$timeouts"
        line=$(awk -v k=$kind '$1 == "latency" && $2 == k && $3 != "timeout" {print $3}' "$OUT/dev.txt" | sort -g | awk '
            {v[NR] = $1} END {if (NR) printf "%s %s %d", v[int((NR + 1) / 2)], v[int(NR * 0.9 + 0.99)], NR}')
        if [ -z "$line" ]; then
            echo "    $kind: nothing changed on the screen ($timeouts keys)"
            continue
        fi
        read -r median p90 n <<<"$line"
        value "latency.dev.${kind}_ms" "$median"
        value "latency.dev.${kind}_p90_ms" "$p90"
        echo "    $kind: $median ms, 90% within $p90 ms ($n keys, $timeouts timeouts)"
    done
}

# the address of the window of a class, for the window selectors of the dispatchers
window_address() { H clients | awk -v c="$1" '/^Window / {a = $2} $1 == "class:" && $2 == c {print "0x" a; exit}'; }

dev_driver_source() {
    cat >"$CLIENTDIR/dev.py" <<'EOF'
# Drives the developer's screen with a uinput keyboard, which takes the kernel's input path like a real one, and
# measures how long a key takes to show on the screen. A Wayland client without libraries, so it runs wherever Python
# does. Needs root for /dev/uinput.
#
# dev.py --clients FILE --monitors FILE --editor CLASS --console CLASS --border N --load SECONDS --cycles N --quiet FILE
# FILEs are the JSON of hyprctl clients -j and monitors -j. The console has the focus at the start and the editor is
# left of it.
# The load phase (prints "load" when it starts) moves between the editor, which scrolls by itself while it has the
# focus, and the console, which gets a command typed, every 3 s. The latency phase creates the quiet file, which stops
# the editor's scrolling, and then waits for every key until a small region of the output changes, captured with
# wlr-screencopy: moving to the editor (SUPER+Left), scrolling (Ctrl-D, Ctrl-U), jumping to a line (<line>G), back to
# the console (SUPER+Right) and typing a command. The time is from the key press to the commit of the first frame
# that shows the change (the compositor stamps a copied frame when it commits it), the display shows it at its next
# refresh. Keys go down at a random point of the frame, as a person's do. Prints "latency <kind> <ms>" or
# "latency <kind> timeout" for every key it waits for.
import argparse
import array
import fcntl
import json
import mmap
import os
import random
import select
import socket
import struct
import time

TIMEOUT = 2.0  # seconds a key may take to show


def now():
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC)


def u32(*v):
    return struct.pack(f"={len(v)}I", *v)


def i32(*v):
    return struct.pack(f"={len(v)}i", *v)


def string(s):
    b = s.encode() + b"\0"
    return u32(len(b)) + b + b"\0" * (-len(b) % 4)


def unstring(p, off):
    (n,) = struct.unpack_from("=I", p, off)
    return p[off + 4 : off + 3 + n].decode(), off + 4 + n + (-n % 4)


class Wayland:
    def __init__(self):
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.last = 1
        self.handlers = {1: self.on_display}
        self.data = b""

    def new(self, handler=None):
        self.last += 1
        self.handlers[self.last] = handler
        return self.last

    def send(self, obj, op, args=b"", fds=None):
        msg = u32(obj, ((8 + len(args)) << 16) | op) + args
        if fds:
            self.sock.sendmsg([msg], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", fds))])
        else:
            self.sock.sendall(msg)

    def on_display(self, op, p):
        if op == 0:
            obj, code = struct.unpack_from("=2I", p)
            raise SystemExit(f"dev.py: protocol error on object {obj}, code {code}: {unstring(p, 8)[0]}")
        if op == 1:
            self.handlers.pop(struct.unpack_from("=I", p)[0], None)

    def dispatch(self, timeout):
        """Handles the events that arrive within timeout seconds, returns whether any did"""
        if not select.select([self.sock], [], [], max(timeout, 0))[0]:
            return False
        chunk = self.sock.recv(1 << 16)
        if not chunk:
            raise SystemExit("dev.py: the compositor closed the connection")
        self.data += chunk
        while len(self.data) >= 8:
            obj, word = struct.unpack_from("=2I", self.data)
            size = word >> 16
            if len(self.data) < size:
                break
            payload, self.data = self.data[8:size], self.data[size:]
            handler = self.handlers.get(obj)
            if handler:
                handler(word & 0xFFFF, payload)
        return True

    def wait(self, cond, timeout):
        """Handles events until cond() holds, returns whether it does"""
        deadline = time.monotonic() + timeout
        while not cond():
            left = deadline - time.monotonic()
            if left <= 0:
                return False
            self.dispatch(left)
        return True

    def roundtrip(self):
        done = []
        self.send(1, 0, u32(self.new(lambda op, p: done.append(op))))
        if not self.wait(lambda: done, 5):
            raise SystemExit("dev.py: the compositor does not answer")


class Screencopy:
    """Captures a region of the output, in the output's logical coordinates"""

    def __init__(self, wl, output_name):
        self.wl = wl
        globs = {}

        def on_global(op, p):
            if op == 0:
                (name,) = struct.unpack_from("=I", p)
                iface, off = unstring(p, 4)
                globs.setdefault(iface, []).append((name, struct.unpack_from("=I", p, off)[0]))

        self.registry = wl.new(on_global)
        wl.send(1, 1, u32(self.registry))
        wl.roundtrip()
        if "zwlr_screencopy_manager_v1" not in globs:
            raise SystemExit("dev.py: the compositor has no wlr-screencopy")
        self.shm = self.bind(globs["wl_shm"][0][0], "wl_shm", 1)
        name, version = globs["zwlr_screencopy_manager_v1"][0]
        self.version = min(version, 3)
        self.manager = self.bind(name, "zwlr_screencopy_manager_v1", self.version)
        names = {}
        for name, version in globs["wl_output"]:
            oid = self.bind(name, "wl_output", min(version, 4))
            # the name event, wl_output version 4
            wl.handlers[oid] = lambda op, p, oid=oid: names.update({oid: unstring(p, 0)[0]}) if op == 4 else None
        wl.roundtrip()
        outputs = [o for o, n in names.items() if n == output_name] or (list(names) if len(globs["wl_output"]) == 1 else [])
        if not outputs:
            raise SystemExit(f"dev.py: no output {output_name}")
        self.output = outputs[0]

    def bind(self, name, iface, version, handler=None):
        oid = self.wl.new(handler)
        self.wl.send(self.registry, 0, u32(name) + string(iface) + u32(version, oid))
        return oid


class Frame:
    def __init__(self, sc, region):
        self.sc = sc
        self.info = None
        self.described = False
        self.stamp = None
        self.failed = False
        self.id = sc.wl.new(self.on_event)
        sc.wl.send(sc.manager, 1, u32(self.id) + i32(0) + u32(sc.output) + i32(*region))

    def on_event(self, op, p):
        if op == 0 and self.info is None:  # buffer: format, width, height, stride
            self.info = struct.unpack_from("=4I", p)
            self.described = self.sc.version < 3
        elif op == 6:  # buffer_done
            self.described = True
        elif op == 2:  # ready
            hi, lo, nsec = struct.unpack_from("=3I", p)
            self.stamp = ((hi << 32) | lo) * 1_000_000_000 + nsec
        elif op == 3:
            self.failed = True

    def done(self):
        return self.stamp is not None or self.failed

    def copy(self, buffer, damage):
        self.sc.wl.send(self.id, 2 if damage else 0, u32(buffer))

    def destroy(self):
        self.sc.wl.send(self.id, 1)


class Region:
    """A region and three shm buffers for it: two for frames in turn, one for the frame the others are compared with"""

    def __init__(self, sc, box):
        self.sc = sc
        self.box = box
        self.buffers = None
        self.turn = 0

    def frame(self):
        f = Frame(self.sc, self.box)
        if not self.sc.wl.wait(lambda: f.described or f.failed, 5) or f.failed or f.info is None:
            raise SystemExit(f"dev.py: no frame for the region {self.box}")
        if self.buffers is None:
            self.allocate(f.info)
        return f

    def allocate(self, info):
        fmt, width, height, stride = info
        self.size = stride * height
        fd = os.memfd_create("hypoland-latency", os.MFD_CLOEXEC)
        os.ftruncate(fd, 3 * self.size)
        self.map = mmap.mmap(fd, 3 * self.size)
        pool = self.sc.wl.new()
        self.sc.wl.send(self.sc.shm, 0, u32(pool) + i32(3 * self.size), fds=[fd])
        os.close(fd)
        self.buffers = []
        for i in range(3):
            self.buffers.append(self.sc.wl.new())
            self.sc.wl.send(pool, 0, u32(self.buffers[-1]) + i32(i * self.size, width, height, stride) + u32(fmt))
        self.sc.wl.send(pool, 1)

    def pixels(self, i):
        return self.map[i * self.size : (i + 1) * self.size]

    def share(self, f):
        """Shares a frame for the next commit, into the buffer that is not being compared"""
        self.turn ^= 1
        f.copy(self.buffers[self.turn], True)
        return self.turn

    def current(self):
        """The region as the next frame shows it, or as it is when nothing draws (a copy without damage draws the
        whole output once)"""
        f = self.frame()
        f.copy(self.buffers[2], True)
        if not self.sc.wl.wait(f.done, 0.1):
            f.destroy()
            f = self.frame()
            f.copy(self.buffers[2], False)
            self.sc.wl.wait(f.done, 2)
        f.destroy()
        return self.pixels(2)

    def settled(self):
        """The region once two frames in a row show the same, an animation may still run after a key"""
        last = self.current()
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline:
            pixels = self.current()
            if pixels == last:
                return pixels
            last = pixels
        return last

    def until_changed(self, press, delay):
        """Presses the keys after delay seconds and returns the nanoseconds until a frame shows the region changed,
        None on a timeout"""
        before = self.settled()
        # settled() returns right after a commit
        time.sleep(delay)
        f = self.frame()
        slot = self.share(f)
        following = self.frame()
        start = press()
        deadline = time.monotonic() + TIMEOUT
        while self.sc.wl.wait(f.done, deadline - time.monotonic()):
            # the next frame waits for the next commit before this one is looked at
            g, f = f, following
            gslot, slot = slot, self.share(f)
            g.destroy()
            if not g.failed and self.pixels(gslot) != before:
                f.destroy()
                return g.stamp - start
            following = self.frame()
        f.destroy()
        following.destroy()
        return None


# ---- keyboard

UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x405C5503, 0x5501, 0x5502
EV_SYN, EV_KEY = 0, 1
KEYS = {"esc": 1, "enter": 28, "ctrl": 29, "shift": 42, "space": 57, "super": 125, "left": 105, "right": 106}
KEYS.update({str(d): 2 + (d - 1) % 10 for d in range(10)})
for row, first in (("qwertyuiop", 16), ("asdfghjkl", 30), ("zxcvbnm", 44)):
    KEYS.update({c: first + i for i, c in enumerate(row)})


class Keyboard:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        for code in set(KEYS.values()):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
        fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("=4H80sI", 0x06, 0x4859, 0x504F, 1, b"hypoland-bench keyboard", 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        # libinput and the compositor pick the device up, and the first key makes it the seat's keyboard
        time.sleep(1.5)
        self.key(KEYS["shift"], 1)
        self.key(KEYS["shift"], 0)
        time.sleep(0.5)

    def key(self, code, value):
        os.write(self.fd, struct.pack("=qqHHi", 0, 0, EV_KEY, code, value) + struct.pack("=qqHHi", 0, 0, EV_SYN, 0, 0))

    def chord(self, chord):
        """Presses a chord like super+left and returns when the last key went down"""
        codes = [KEYS[k] for k in chord.split("+")]
        for code in codes[:-1]:
            self.key(code, 1)
            time.sleep(0.005)
        start = now()
        self.key(codes[-1], 1)
        for code in reversed(codes):
            self.key(code, 0)
        return start

    def close(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def chord_of(c):
    return {" ": "space", "\n": "enter"}.get(c, f"shift+{c.lower()}" if c.isupper() else c)


# letters and spaces only, other characters sit on different keys in different layouts. git diff pages for 2 s
LOAD_COMMANDS = ("ls", "git diff", "git status", "git diff", "git show", "git diff")
COMMANDS = ("git status", "ls", "git log", "git diff")


def main():
    ap = argparse.ArgumentParser()
    for a in ("clients", "monitors", "editor", "console", "quiet"):
        ap.add_argument("--" + a, required=True)
    ap.add_argument("--border", type=int, default=2)
    ap.add_argument("--load", type=float, default=12)
    ap.add_argument("--cycles", type=int, default=6)
    args = ap.parse_args()

    monitor = next(m for m in json.load(open(args.monitors)) if m["focused"])
    frame = 1 / (monitor.get("refreshRate") or 60)
    boxes = {}
    for c in json.load(open(args.clients)):
        if c["class"] in (args.editor, args.console):
            boxes[c["class"]] = (c["at"][0] - monitor["x"], c["at"][1] - monitor["y"], c["size"][0], c["size"][1])
    ex, ey, ew, eh = boxes[args.editor]
    cx, cy, cw, ch = boxes[args.console]
    b = max(args.border, 1)

    wl = Wayland()
    sc = Screencopy(wl, monitor["name"])
    # the border above a window changes color with the focus, the text inside with a key. The console is cleared
    # before a command is typed, which keeps the prompt at the top
    editor_border = Region(sc, (ex + 8, ey - b, ew - 16, b))
    console_border = Region(sc, (cx + 8, cy - b, cw - 16, b))
    editor_text = Region(sc, (ex + ew // 4, ey + eh // 8, ew // 2, eh // 6))
    console_text = Region(sc, (cx + 4, cy + 4, cw - 8, max(ch // 8, 32)))

    kb = Keyboard()
    rng = random.Random(1)

    def typed(text, pause=0.06):
        for c in text:
            kb.chord(chord_of(c))
            time.sleep(pause)

    def probe(kind, region, chord):
        ns = region.until_changed(lambda: kb.chord(chord), rng.uniform(0, frame))
        print(f"latency {kind} {'timeout' if ns is None else f'{ns / 1e6:.1f}'}", flush=True)

    try:
        print("load", flush=True)
        end = time.monotonic() + args.load + 1
        turn = 0
        while time.monotonic() < end:
            kb.chord("super+left")
            time.sleep(3)
            kb.chord("super+right")
            console = time.monotonic()
            time.sleep(0.3)
            typed(LOAD_COMMANDS[turn % len(LOAD_COMMANDS)] + "\n")
            turn += 1
            time.sleep(max(console + 3 - time.monotonic(), 0))

        open(args.quiet, "w").close()
        print("latency phase", flush=True)
        time.sleep(2.5)
        for cycle in range(args.cycles):
            probe("focus", editor_border, "super+left")
            probe("scroll", editor_text, "ctrl+d")
            probe("scroll", editor_text, "ctrl+d")
            probe("scroll", editor_text, "ctrl+u")
            for jump in range(2):
                typed(str(1000 + (2 * cycle + jump) * 7919 * 13 % 150000))
                probe("jump", editor_text, "shift+g")
            probe("focus", console_border, "super+right")
            kb.chord("ctrl+l")
            for c in COMMANDS[cycle % len(COMMANDS)]:
                probe("type", console_text, chord_of(c))
            kb.chord("enter")
            time.sleep(1)
    finally:
        kb.close()


main()
EOF
}

# a client given with --client
workload_custom() { # name, command
    client $((SECONDS_PER_RUN + 10)) "$2"
    sleep 4
    rec "$1"
    stop_clients
}

missing() { # programs, gi:<namespace>-<version> for a library Python reaches through GObject introspection, x11 for Xwayland, root
    local prog lib
    for prog in $1; do
        if [ "$prog" = x11 ]; then
            [ -n "$(xdisplay)" ] || { echo "Xwayland"; return; }
            continue
        fi
        if [ "$prog" = root ]; then
            [ $ROOT = 1 ] || { echo "root (for a uinput keyboard)"; return; }
            continue
        fi
        if [[ $prog == gi:* ]]; then
            lib=${prog#gi:}
            asuser python3 -I -c "import gi; gi.require_version('${lib%-*}', '${lib##*-}')" >/dev/null 2>&1 ||
                { echo "${lib%-*} ${lib##*-} for Python (python-gobject)"; return; }
            continue
        fi
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

# a window of each toolkit, drawn on the screen and getting its frames
check_toolkits() {
    local tk what needs lacking before log fps
    for tk in gtk3 gtk4 gtk3-x11 qt-quick qt-software; do
        what="$(toolkit_name $tk) window"
        needs=needs_${tk//-/_}_scroll
        lacking=$(missing "${!needs}")
        if [ -n "$lacking" ]; then
            skip "$what: $lacking is not installed"
            continue
        fi
        log=$CLIENTDIR/check-$tk.log
        before=$(nclients)
        client 40 "$(toolkit $tk check) >$log 2>&1"
        if ! mapped "$before" 15; then
            fail "$what did not map: $(tail -n 1 "$log" 2>/dev/null)"
            stop_clients
            continue
        fi
        # a window can open with an animation (Omarchy fades it in), and a screenshot during it sees a window that
        # is not opaque yet. The Qt software window maps within 0.1 s, before the first look for it
        sleep 1
        check_drawn "$what drawn" "$tk.png" 10
        # the client reports its frame rate 5 s after its first frame
        for _ in $(seq 1 10); do
            grep -q "frames in" "$log" && break
            sleep 1
        done
        fps=$(fps_of "$log")
        if [ "$fps" -ge 20 ]; then pass "$what at $fps fps (renderer $(renderer_of "$log"))"; else fail "$what at $fps fps (renderer $(renderer_of "$log"))"; fi
        stop_clients
        sleep 1
    done
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

    display=$(xdisplay)
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
    check_toolkits
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
