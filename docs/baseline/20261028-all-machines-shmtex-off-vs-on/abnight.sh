#!/bin/bash
# abnight.sh OUT UNTIL A_NAME A_ENV B_NAME B_ENV
# Two variants of the installed Hypoland that differ only by the compositor's environment, with every workload of
# measure.sh (bench/ next to this script), in alternating blocks until the time UNTIL (HH:MM): each block one variant,
# a fresh SDDM session with the variant's lines in the user's ~/.config/uwsm/env (A_ENV / B_ENV, e.g. "" and
# "export HYPOLAND_SHM_TEXTURE=linear"), measured 60 s after it started. A round has one block of each, in turns first,
# and starts only when one more still fits. Derived from the abnight.sh of docs/baseline/20261027-all-machines-r761-vs-
# hyprland-0.56.2 (which swapped packages); the rest is the same. As root, detached:
#   setsid -f nohup bash abnight.sh OUT 07:30 off "" on "export HYPOLAND_SHM_TEXTURE=linear" >/dev/null 2>&1 </dev/null
# For the run it stops the system's timers and Omarchy's update checks, and stops below 40% battery while discharging.
# `touch OUT/stop` stops after the block that runs. Ends with the env file as before and a fresh session, Omarchy's
# timers as before. Writes OUT/log and OUT/<variant>-<round>.txt, the output of measure.sh.
set -u
OUT=$1 UNTIL=$2 A=$3 A_ENV=$4 B=$5 B_ENV=$6
D=$(dirname "$(readlink -f "$0")")
mkdir -p "$OUT"
exec >>"$OUT/log" 2>&1
log() { echo "$(date '+%F %T') $*"; }
END=$(date -d "$UNTIL" +%s)
[ "$END" -gt "$(date +%s)" ] || END=$(date -d "tomorrow $UNTIL" +%s)
compositor() { pgrep -x hypoland; }
USERNAME=$(ps -o user= -p "$(compositor | head -1)")
HOME_=$(getent passwd "$USERNAME" | cut -d: -f6)
ENVF=$HOME_/.config/uwsm/env
log "until $(date -d "@$END" '+%F %T') on $(uname -n), user $USERNAME, $(pacman -Q hypoland), $A: '$A_ENV', $B: '$B_ENV'"

# another measurement first
while pgrep -f "bench/[m]easure.sh" >/dev/null; do sleep 30; done

# ---- paused for the run, see soak-ab.sh

TIMERS=$(systemctl list-units --type=timer --state=active --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
[ -n "$TIMERS" ] && systemctl stop $TIMERS && log "stopped timers: $TIMERS"
UPDATE_CHECK='^(/usr)?/bin/bash /usr/(share/omarchy/)?bin/(omarchy-update-available|checkupdates)( |$)|^(/bin/sh /usr/bin/fakeroot -- )?pacman -Sy .*--dbpath /tmp/checkup-db-'
(while sleep 5; do pkill -u "$USERNAME" -f "$UPDATE_CHECK" && log "stopped an update check"; done) &
GUARD=$!
battery_low() {
    local b
    for b in /sys/class/power_supply/*; do
        [ "$(cat "$b/type" 2>/dev/null)" = Battery ] && [ "$(cat "$b/status" 2>/dev/null)" = Discharging ] || continue
        [ "$(cat "$b/capacity" 2>/dev/null || echo 100)" -lt 40 ] && return 0
    done
    return 1
}

# the env file as it was: kept in OUT, restored at the end
mkdir -p "$(dirname "$ENVF")"
chown "$USERNAME:" "$(dirname "$ENVF")"
if [ -e "$ENVF" ]; then cp "$ENVF" "$OUT/env.orig"; else : >"$OUT/env.orig"; fi
# the switch must not be set already
grep -v '^export HYPOLAND_SHM_TEXTURE=' "$OUT/env.orig" >"$OUT/env.base"

# ---- one variant, a new session

ready() { # the instance lock file names the compositor and the shell is up
    local p
    for _ in $(seq 1 240); do
        p=$(compositor)
        [ -n "$p" ] && grep -qx "$p" /run/user/*/hypr/*/hyprland.lock 2>/dev/null && pgrep -x quickshell >/dev/null && return 0
        sleep 0.5
    done
    return 1
}

use() { # A|B, or restore
    local env
    case $1 in
        "$A") env=$A_ENV ;;
        "$B") env=$B_ENV ;;
        restore) env= ;;
    esac
    if [ "$1" = restore ]; then
        cp "$OUT/env.orig" "$ENVF"
    else
        { cat "$OUT/env.base"; [ -n "$env" ] && printf '%s\n' "$env"; } >"$ENVF"
    fi
    chown "$USERNAME:" "$ENVF"
    systemctl stop sddm
    for _ in $(seq 1 100); do compositor >/dev/null || break; sleep 0.2; done
    systemctl --user -M "$USERNAME@" stop graphical-session.target graphical-session-pre.target 2>/dev/null
    sleep 2
    # every Quickshell instance leaves its log in /run/user (tmpfs), which no SDDM restart clears
    rm -rf /run/user/*/quickshell/by-id/* /run/user/*/quickshell/by-pid/*
    systemctl start sddm
    ready || { log "no session for $1"; return 1; }
    local p
    p=$(compositor | head -1)
    # the variant's variable has to be in the compositor's environment, or not
    local have
    have=$(tr '\0' '\n' <"/proc/$p/environ" | grep -c '^HYPOLAND_SHM_TEXTURE=')
    if [ -n "$env" ]; then [ "$have" = 1 ] || { log "$1: the variable did not reach the compositor"; return 1; }
    else [ "$have" = 0 ] || { log "$1: the variable is set in the compositor"; return 1; }; fi
    log "$1 up: $(pacman -Q hypoland), env: $(tr '\0' '\n' <"/proc/$p/environ" | grep '^HYPOLAND_' | tr '\n' ' ')"
    # the shell's start and Omarchy's autostart have run
    sleep 60
}

restore() {
    trap - EXIT
    log "env file back as before, a fresh session"
    use restore
    kill "$GUARD" 2>/dev/null
    [ -n "$TIMERS" ] && systemctl start $TIMERS && log "started the timers again"
    rm -rf /tmp/abnight-measure
    log "done"
    touch "$OUT/done"
}
trap restore EXIT
trap 'exit 1' HUP INT TERM

r=0 last=0
while :; do
    r=$((r + 1))
    [ $r -gt 1 ] && [ $(($(date +%s) + last)) -gt "$END" ] && { log "no time for round $r"; break; }
    start=$(date +%s)
    order=("$A" "$B")
    [ $((r % 2)) = 0 ] && order=("$B" "$A")
    for v in "${order[@]}"; do
        battery_low && { log "battery below 40% and discharging, stopping"; touch "$OUT/stop"; }
        [ -e "$OUT/stop" ] && break 2
        use "$v" || continue
        rm -rf /tmp/abnight-measure
        # ABNIGHT_WORKLOADS limits the workloads, for a quick check of the whole thing
        bash "$D/bench/measure.sh" --rounds 1 --out /tmp/abnight-measure ${ABNIGHT_WORKLOADS:+--workloads "$ABNIGHT_WORKLOADS"} \
            >"$OUT/$v-$r.txt" 2>&1
        log "$v round $r: $(grep -c '^@' "$OUT/$v-$r.txt") values$(grep -q '^@ [0-9]* invalid' "$OUT/$v-$r.txt" && echo ', some invalid')"
        # ABNIGHT_CHECK=1: the session checks of a deploy as well, once for each variant, in the first round
        if [ -n "${ABNIGHT_CHECK:-}" ] && [ $r = 1 ]; then
            bash "$D/bench/measure.sh" --mode check >"$OUT/$v-check.txt" 2>&1
            log "$v check: $(grep -c '^PASS' "$OUT/$v-check.txt") passed, $(grep -c '^FAIL' "$OUT/$v-check.txt") failed"
        fi
    done
    last=$(($(date +%s) - start))
done
