#!/bin/bash
# abnight.sh OUT UNTIL HYPOLAND_PKG HYPRLAND_PKGS [pr]
# Hypoland against Hyprland 0.56.2 with every workload of measure.sh (bench/ next to this script), in alternating
# blocks until the time UNTIL (HH:MM): each block one compositor, a fresh SDDM session, measured 60 s after it
# started. A round has one block of each, in turns first, and starts only when one more still fits. As root, detached:
#   setsid -f nohup bash abnight.sh OUT 07:30 HYPOLAND_PKG "HYPRLAND_PKG TITLEBARS_PKG" [pr] >/dev/null 2>&1 </dev/null
# With pr (the X200, where Hyprland 0.56.2 does not start on its own): omarchy PR 14764's GLES 3 override
# (pr/intel-gles2.lua and pr/omarchy-hw-intel-gles2 next to this script) while Hyprland 0.56.2 runs, and its Mesa
# overrides for the clients. For the run it stops the system's timers and Omarchy's update checks, and stops below
# 40% battery while discharging. `touch OUT/stop` stops after the block that runs. Ends with HYPOLAND_PKG, Omarchy's
# files and the timers as before. Writes OUT/log and OUT/<compositor>-<round>.txt, the output of measure.sh.
set -u
OUT=$1 UNTIL=$2 HYPOLAND=$3 HYPRLAND=$4 PR=${5:-}
D=$(dirname "$(readlink -f "$0")")
O=/usr/share/omarchy
mkdir -p "$OUT"
exec >>"$OUT/log" 2>&1
log() { echo "$(date '+%F %T') $*"; }
END=$(date -d "$UNTIL" +%s)
[ "$END" -gt "$(date +%s)" ] || END=$(date -d "tomorrow $UNTIL" +%s)
compositor() { pgrep -x 'hypoland|Hyprland'; }
# hypoland provides hyprland, pacman -Q hyprland names it too
installed() { if pacman -Q hypoland >/dev/null 2>&1; then echo hypoland; else echo hyprland; fi; }
USERNAME=$(ps -o user= -p "$(compositor | head -1)")
log "until $(date -d "@$END" '+%F %T') on $(uname -n), user $USERNAME, hypoland $HYPOLAND, hyprland $HYPRLAND ${PR:+(with the GLES 3 override)}"

# another measurement first (the Chromebook's baseline when this started)
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
[ -n "$PR" ] && cp $O/default/hypr/envs.lua "$OUT/envs.lua.orig"

# ---- one compositor, a new session

ready() { # the instance lock file names the compositor and the shell is up
    local p
    for _ in $(seq 1 240); do
        p=$(compositor)
        [ -n "$p" ] && grep -qx "$p" /run/user/*/hypr/*/hyprland.lock 2>/dev/null && pgrep -x quickshell >/dev/null && return 0
        sleep 0.5
    done
    return 1
}

pr_files() { # on|off
    if [ "$1" = on ]; then
        install -m 755 "$D/pr/omarchy-hw-intel-gles2" $O/bin/
        install -m 644 "$D/pr/intel-gles2.lua" $O/default/hypr/
        grep -q intel-gles2 $O/default/hypr/envs.lua ||
            sed -i 's/^require("default.hypr.nvidia")$/&\nrequire("default.hypr.intel-gles2")/' $O/default/hypr/envs.lua
        grep -q intel-gles2 $O/default/hypr/envs.lua || { log "envs.lua not patched"; return 1; }
    else
        rm -f $O/default/hypr/intel-gles2.lua $O/bin/omarchy-hw-intel-gles2
        cp "$OUT/envs.lua.orig" $O/default/hypr/envs.lua
    fi
}

use() { # hypoland|hyprland
    if [ "$(installed)" != "$1" ]; then
        if [ "$1" = hypoland ]; then
            pacman -U --noconfirm --ask=4 "$HYPOLAND" >>"$OUT/pacman.log" 2>&1
        else
            pacman -U --noconfirm --ask=4 $HYPRLAND >>"$OUT/pacman.log" 2>&1
        fi || { log "installing $1 failed"; return 1; }
    fi
    if [ -n "$PR" ]; then
        if [ "$1" = hyprland ]; then pr_files on || return 1; else pr_files off; fi
    fi
    systemctl stop sddm
    for _ in $(seq 1 100); do compositor >/dev/null || break; sleep 0.2; done
    systemctl --user -M "$USERNAME@" stop graphical-session.target graphical-session-pre.target 2>/dev/null
    sleep 2
    # every Quickshell instance leaves its log in /run/user (tmpfs), which no SDDM restart clears: on 2026-10-26
    # the logs of the shell's spin in the hour the clock repeated at the end of DST filled it, and a session failed
    rm -rf /run/user/*/quickshell/by-id/* /run/user/*/quickshell/by-pid/*
    systemctl start sddm
    ready || { log "no session with $1"; return 1; }
    pgrep -x "$([ "$1" = hypoland ] && echo hypoland || echo Hyprland)" >/dev/null || { log "$1 is not what runs"; return 1; }
    log "$1 up: $(pacman -Q "$(installed)")"
    # the shell's start and Omarchy's autostart have run
    sleep 60
}

restore() {
    trap - EXIT
    log "back to hypoland"
    use hypoland
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
    order=(hypoland hyprland)
    [ $((r % 2)) = 0 ] && order=(hyprland hypoland)
    for v in "${order[@]}"; do
        battery_low && { log "battery below 40% and discharging, stopping"; touch "$OUT/stop"; }
        [ -e "$OUT/stop" ] && break 2
        use "$v" || continue
        env=()
        [ "$v" = hyprland ] && [ -n "$PR" ] && env=(--env MESA_GLES_VERSION_OVERRIDE=3.0 --env MESA_GLSL_VERSION_OVERRIDE=300)
        rm -rf /tmp/abnight-measure
        # ABNIGHT_WORKLOADS limits the workloads, for a quick check of the whole thing
        bash "$D/bench/measure.sh" --rounds 1 --out /tmp/abnight-measure ${ABNIGHT_WORKLOADS:+--workloads "$ABNIGHT_WORKLOADS"} \
            "${env[@]}" >"$OUT/$v-$r.txt" 2>&1
        log "$v round $r: $(grep -c '^@' "$OUT/$v-$r.txt") values$(grep -q '^@ [0-9]* invalid' "$OUT/$v-$r.txt" && echo ', some invalid')"
        # ABNIGHT_CHECK=1: the session checks of a deploy as well, once for each compositor, in the first round
        if [ -n "${ABNIGHT_CHECK:-}" ] && [ $r = 1 ]; then
            bash "$D/bench/measure.sh" --mode check "${env[@]}" >"$OUT/$v-check.txt" 2>&1
            log "$v check: $(grep -c '^PASS' "$OUT/$v-check.txt") passed, $(grep -c '^FAIL' "$OUT/$v-check.txt") failed"
        fi
    done
    last=$(($(date +%s) - start))
done
