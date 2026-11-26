#!/bin/bash
# energy.sh OUT UNTIL HYPOLAND_PKG HYPRLAND_PKGS
# The power Hypoland and stock Hyprland 0.57.2-4 draw, measured by RAPL (the CPU package: cores, GPU, memory controller),
# in alternating blocks until the time UNTIL (HH:MM): each block one compositor, a fresh SDDM session, 60 s after it
# started, measure.sh --mode energy over the workloads in WORKLOADS below (each 30 s, an idle baseline of 10 s before
# and after it). A round has one block of each, in turns first, and starts only when one more still fits. Adapted
# from the night runner (test-results/night-20261111/abnight.sh). As root, detached:
#   setsid -f nohup bash energy.sh OUT 07:30 HYPOLAND_PKG "HYPRLAND_PKG TITLEBARS_PKG" >/dev/null 2>&1 </dev/null
# Only on machines with RAPL: it refuses to start without a package zone. The machine stays on its charger (RAPL does
# not need the battery), but the power profile is the one Omarchy picks on battery (balanced, through its saved choice
# for AC in ~/.local/state/omarchy/powerprofiles/ac, which the shell applies at every session start), since the
# question is battery life. For the run it stops the system's timers and Omarchy's update checks. `touch OUT/stop`
# stops after the block that runs. Ends with HYPOLAND_PKG, Omarchy's files, the timers and the profile as before.
# Writes OUT/log and OUT/<compositor>-<round>.txt, the output of measure.sh.
set -u
OUT=$1 UNTIL=$2 HYPOLAND=$3 HYPRLAND=$4
D=$(dirname "$(readlink -f "$0")")
O=/usr/share/omarchy
# workloads whose client does the same work whatever the compositor: frame-limited clients, fixed-rate input and
# timers. Not the terminals' print loops or the games, which do more work under a compositor that takes their frames
# faster, so their energy says nothing about the compositor's.
WORKLOADS=${ENERGY_WORKLOADS:-idle,gpu-client,video,video-window,gtk3-scroll,gtk4-scroll,qt-quick-scroll,qt-software-scroll,gtk3-x11-scroll,gtk4-spinner,qt-software-sprites,tk-canvas,workspace-switch,idle-windows,dev,notifications,menu,nautilus-scroll}
PROFILE=${ENERGY_PROFILE:-balanced}
mkdir -p "$OUT"
exec >>"$OUT/log" 2>&1
log() { echo "$(date '+%F %T') $*"; }
END=$(date -d "$UNTIL" +%s)
[ "$END" -gt "$(date +%s)" ] || END=$(date -d "tomorrow $UNTIL" +%s)
compositor() { pgrep -x 'hypoland|Hyprland'; }
# hypoland provides hyprland, pacman -Q hyprland names it too
installed() { if pacman -Q hypoland >/dev/null 2>&1; then echo hypoland; else echo hyprland; fi; }
USERNAME=$(ps -o user= -p "$(compositor | head -1)")
HOMEDIR=$(getent passwd "$USERNAME" | cut -d: -f6)

rapl=0
for z in /sys/class/powercap/intel-rapl:*; do
    [[ $(basename "$z") == *:*:* ]] && continue
    [[ $(cat "$z/name" 2>/dev/null) == package* ]] && rapl=1
done
[ $rapl = 1 ] || { log "no RAPL package zone on $(uname -n), nothing to measure energy with: not started"; touch "$OUT/done"; exit 1; }
log "until $(date -d "@$END" '+%F %T') on $(uname -n), user $USERNAME, hypoland $HYPOLAND, hyprland $HYPRLAND, profile $PROFILE"
log "workloads $WORKLOADS"

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
cp $O/default/hypr/envs.lua "$OUT/envs.lua.orig"

# the power profile: Omarchy's saved choice for AC, which the shell applies when a session starts
STATE=$HOMEDIR/.local/state/omarchy/powerprofiles
if [ -e "$STATE/ac" ]; then cp "$STATE/ac" "$OUT/profile-ac.orig"; else rm -f "$OUT/profile-ac.orig"; fi
PROFILE_BEFORE=$(powerprofilesctl get 2>/dev/null)
install -d -o "$USERNAME" -g "$(id -gn "$USERNAME")" "$STATE"
echo "$PROFILE" >"$STATE/ac"
chown "$USERNAME:" "$STATE/ac"
profile_restore() {
    if [ -e "$OUT/profile-ac.orig" ]; then cp "$OUT/profile-ac.orig" "$STATE/ac"; else rm -f "$STATE/ac"; fi
    [ -n "$PROFILE_BEFORE" ] && powerprofilesctl set "$PROFILE_BEFORE"
}

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

stock_files() { # on|off: pr/stock-quirks.lua for the stock blocks
    if [ "$1" = on ]; then
        install -m 644 "$D/pr/stock-quirks.lua" $O/default/hypr/
        grep -q stock-quirks $O/default/hypr/envs.lua ||
            sed -i 's/^require("default.hypr.nvidia")$/&\nrequire("default.hypr.stock-quirks")/' $O/default/hypr/envs.lua
        grep -q stock-quirks $O/default/hypr/envs.lua || { log "envs.lua not patched for the quirks"; return 1; }
    else
        rm -f $O/default/hypr/stock-quirks.lua
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
    if [ "$1" = hyprland ]; then stock_files on || return 1; else stock_files off; fi
    systemctl stop sddm
    for _ in $(seq 1 100); do compositor >/dev/null || break; sleep 0.2; done
    systemctl --user -M "$USERNAME@" stop graphical-session.target graphical-session-pre.target 2>/dev/null
    sleep 2
    # every Quickshell instance leaves its log in /run/user (tmpfs), which no SDDM restart clears
    rm -rf /run/user/*/quickshell/by-id/* /run/user/*/quickshell/by-pid/*
    systemctl start sddm
    ready || { log "no session with $1"; return 1; }
    pgrep -x "$([ "$1" = hypoland ] && echo hypoland || echo Hyprland)" >/dev/null || { log "$1 is not what runs"; return 1; }
    log "$1 up: $(pacman -Q "$(installed)")"
    # the shell's start and Omarchy's autostart have run
    sleep 60
    # the shell set the profile from the saved choice at its start; make sure, the run is void otherwise
    [ "$(powerprofilesctl get 2>/dev/null)" = "$PROFILE" ] || { log "profile $(powerprofilesctl get 2>/dev/null), setting $PROFILE"; powerprofilesctl set "$PROFILE"; }
}

restore() {
    trap - EXIT
    log "back to hypoland"
    use hypoland
    profile_restore
    log "profile $(powerprofilesctl get 2>/dev/null)"
    kill "$GUARD" 2>/dev/null
    [ -n "$TIMERS" ] && systemctl start $TIMERS && log "started the timers again"
    rm -rf /tmp/energy-measure
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
        rm -rf /tmp/energy-measure
        timeout -k 30 3600 bash "$D/bench/measure.sh" --mode energy --meter rapl --seconds 30 --rounds 1 \
            --out /tmp/energy-measure --workloads "$WORKLOADS" >"$OUT/$v-$r.txt" 2>&1
        rc=$?
        log "$v round $r: $(grep -c '^@' "$OUT/$v-$r.txt") values, profile $(powerprofilesctl get 2>/dev/null)$(grep -q '^@ [0-9]* invalid' "$OUT/$v-$r.txt" && echo ', some invalid')"
        if [ $rc = 124 ] || [ $rc = 137 ]; then
            log "$v round $r took an hour, killing its compositor"
            pkill -9 -x "$([ "$v" = hypoland ] && echo hypoland || echo Hyprland)"
        fi
    done
    last=$(($(date +%s) - start))
done
