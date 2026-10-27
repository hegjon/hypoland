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
#                       client, Chromium, GTK 3 (also through Xwayland), GTK 4 and Qt Quick windows, a Tk
#                       window with a menu and a dialog through Xwayland, errors in the log) and RESULT: PASS
#                       or FAIL
#   --seconds N         length of a workload (default 12)
#   --rounds N          how often the workloads are repeated, bench only (default 1)
#   --workloads LIST    comma separated, default: all of them (WORKLOADS below)
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
WORKLOADS=idle,gpu-client,terminal-scroll,alacritty-scroll,video,nautilus,flea,shm-fullwindow,workspace-switch,gtk3-scroll,gtk4-scroll,qt-quick-scroll,qt-software-scroll,gtk3-x11-scroll,gtk4-spinner,qt-software-sprites,tk-canvas,video-window,idle-windows,dev,resize,notifications,menu
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

# The parts of the script are in lib/ and the programs it starts as clients in clients/, next to it: the whole
# directory comes to the machine (target.sh). setup.sh runs when it is sourced, the others only define functions
HERE=$(dirname "$(readlink -f "$0")")
CLIENTSRC=$HERE/clients
# shellcheck source=lib/session.sh
. "$HERE/lib/session.sh"
# shellcheck source=lib/meters.sh
. "$HERE/lib/meters.sh"
# shellcheck source=lib/setup.sh
. "$HERE/lib/setup.sh"
# shellcheck source=lib/measuring.sh
. "$HERE/lib/measuring.sh"
# shellcheck source=lib/workloads.sh
. "$HERE/lib/workloads.sh"
# shellcheck source=lib/check.sh
. "$HERE/lib/check.sh"

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
