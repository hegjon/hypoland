#!/bin/bash
# abrt.sh OUT UNTIL PKG
# One Hypoland package, realtime on against off: blocks alternate between HYPRLAND_NO_RT=1 (nort, what Omarchy sets) and
# HYPRLAND_NO_RT=0 (rt), each a fresh SDDM session, the order reversed every other round, a round only when one more fits
# before UNTIL (HH:MM). The variable goes into the user's ~/.config/uwsm/env.d/90-hypoland-rt, which comes after
# Omarchy's default. Each block: the opt-in startup workload (it restarts SDDM itself), then every workload of
# measure.sh (bench/ next to this script) 60 s after the shell is up; in round 1 the deploy's session check as well.
# After every block: whether the compositor that was measured still runs (rtkit's RLIMIT_RTTIME kills it with SIGKILL and
# no log line, start-hypoland then starts another), core dumps and crash reports since the block began, and the
# compositor's Realtime / SIGXCPU lines in the journal. As root, detached:
#   setsid -f nohup bash abrt.sh OUT 07:30 PKG >/dev/null 2>&1 </dev/null
# `touch OUT/stop` stops after the block that runs. Ends with PKG installed, the env.d file as before and the timers
# started again; writes OUT/done.
set -u
OUT=$1 UNTIL=$2 PKG=$3
D=$(dirname "$(readlink -f "$0")")
mkdir -p "$OUT"
exec >>"$OUT/log" 2>&1
log() { echo "$(date '+%F %T') $*"; }
END=$(date -d "$UNTIL" +%s)
[ "$END" -gt "$(date +%s)" ] || END=$(date -d "tomorrow $UNTIL" +%s)
# the user's compositor, not SDDM's greeter (which runs hypoland as user sddm)
compositor() { ps -o pid=,user= --sort=start_time -C hypoland 2>/dev/null | awk '$2 != "sddm" {p = $1} END {print p}'; }
while pgrep -f "bench/[m]easure.sh" >/dev/null; do sleep 30; done
for _ in $(seq 1 120); do [ -n "$(compositor)" ] && break; sleep 1; done
USERNAME=$(ps -o user= -p "$(compositor)")
UHOME=$(getent passwd "$USERNAME" | cut -d: -f6)
RTF=$UHOME/.config/uwsm/env.d/90-hypoland-rt
log "until $(date -d "@$END" '+%F %T') on $(uname -n), user $USERNAME, $PKG"
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
if [ -e "$RTF" ]; then cp -a "$RTF" "$OUT/rtfile.orig"; else rm -f "$OUT/rtfile.orig"; fi

ready() {
    local p
    for _ in $(seq 1 240); do
        p=$(compositor)
        [ -n "$p" ] && grep -qx "$p" /run/user/*/hypr/*/hyprland.lock 2>/dev/null && pgrep -x quickshell >/dev/null && return 0
        sleep 0.5
    done
    return 1
}
setrt() { # 0|1|orig
    install -d -o "$USERNAME" -g "$USERNAME" "$UHOME/.config/uwsm" "$UHOME/.config/uwsm/env.d"
    if [ "$1" = orig ]; then
        if [ -e "$OUT/rtfile.orig" ]; then cp -a "$OUT/rtfile.orig" "$RTF"; else rm -f "$RTF"; fi
        return 0
    fi
    printf '# realtime A/B of 2026-11-12 (abrt.sh), removed when it ends\nexport HYPRLAND_NO_RT=%s\n' "$1" >"$RTF"
    chown "$USERNAME:" "$RTF"
}
state() { # what the running compositor got: its HYPRLAND_NO_RT and its main thread's policy
    local p
    p=$(compositor)
    echo "pid $p, $(tr '\0' '\n' </proc/"$p"/environ 2>/dev/null | grep '^HYPRLAND_NO_RT=' || echo 'HYPRLAND_NO_RT unset'), $(chrt -p "$p" 2>/dev/null | head -1 | sed 's/.*policy: //')"
}
session() { # 0|1|orig
    if [ "$(pacman -Q hypoland 2>/dev/null)" != "$(pacman -Qp "$PKG" 2>/dev/null | grep '^hypoland ')" ]; then
        pacman -U --noconfirm --ask=4 "$PKG" >>"$OUT/pacman.log" 2>&1 || { log "installing $PKG failed"; return 1; }
    fi
    setrt "$1"
    systemctl stop sddm
    for _ in $(seq 1 100); do pgrep -x hypoland >/dev/null || break; sleep 0.2; done
    systemctl --user -M "$USERNAME@" stop graphical-session.target graphical-session-pre.target 2>/dev/null
    sleep 2
    rm -rf /run/user/*/quickshell/by-id/* /run/user/*/quickshell/by-pid/*
    systemctl start sddm
    ready || { log "no session"; return 1; }
    log "up: $(pacman -Q hypoland), $(state)"
}
after() { # name round pid since: what happened to the compositor during the block
    local name=$1 r=$2 pid=$3 since=$4 now c rep
    now=$(compositor)
    [ "$now" = "$pid" ] || log "$name round $r: the compositor $pid is gone (now: ${now:-none}), $(journalctl -q --since "@$since" -k 2>/dev/null | grep -ciE 'hang|reset|fault') kernel lines about hangs or faults"
    c=$(coredumpctl list --since "@$since" --no-legend 2>/dev/null | awk '{for (i = 5; i <= NF; i++) if ($i ~ /^\//) {print $i; break}}' | sort | uniq -c | tr '\n' ' ')
    [ -n "$c" ] && log "$name round $r: core dumps: $c" && coredumpctl list --since "@$since" >"$OUT/cores-$name-$r.txt" 2>&1
    rep=$(find "$UHOME/.cache/hyprland" -name 'hyprlandCrashReport*' -newermt "@$since" 2>/dev/null)
    if [ -n "$rep" ]; then
        mkdir -p "$OUT/crash-$name-$r"
        cp $rep "$OUT/crash-$name-$r/"
        log "$name round $r: $(echo "$rep" | wc -l) crash report(s), copied to crash-$name-$r"
    fi
    c=$(journalctl -q --since "@$since" _COMM=hypoland 2>/dev/null | grep -E 'Realtime|SIGXCPU|realtime' | tee -a "$OUT/realtime-$name-$r.txt" | wc -l)
    [ "$c" -gt 0 ] && log "$name round $r: $c realtime lines from the compositor (realtime-$name-$r.txt)"
    log "$name round $r after: $(state)"
}
restore() {
    trap - EXIT
    log "back to Omarchy's realtime setting"
    session orig
    kill "$GUARD" 2>/dev/null
    [ -n "$TIMERS" ] && systemctl start $TIMERS && log "started the timers again"
    rm -rf /tmp/abrt-measure /tmp/abrt-startup
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
    order=(nort rt)
    [ $((r % 2)) = 0 ] && order=(rt nort)
    for name in "${order[@]}"; do
        battery_low && { log "battery below 40% and discharging, stopping"; touch "$OUT/stop"; }
        [ -e "$OUT/stop" ] && break 2
        v=1
        [ $name = rt ] && v=0
        since=$(date +%s)
        session $v || continue
        rm -rf /tmp/abrt-startup
        timeout 600 bash "$D/bench/measure.sh" --rounds 1 --out /tmp/abrt-startup --workloads startup >"$OUT/$name-$r-startup.txt" 2>&1
        log "$name round $r startup: $(grep -c '^@' "$OUT/$name-$r-startup.txt") values"
        ready || { log "no session after the startup measurement"; after $name $r none "$since"; continue; }
        pid=$(compositor)
        log "$name round $r measuring: $(state)"
        rm -rf /tmp/abrt-measure
        # a block takes 15 to 25 minutes; one that hangs has a hung compositor, which SDDM cannot stop either
        timeout -k 30 3600 bash "$D/bench/measure.sh" --rounds 1 --out /tmp/abrt-measure ${ABRT_WORKLOADS:+--workloads "$ABRT_WORKLOADS"} \
            >"$OUT/$name-$r.txt" 2>&1
        rc=$?
        log "$name round $r: $(grep -c '^@' "$OUT/$name-$r.txt") values$(grep -q '^@ [0-9]* invalid' "$OUT/$name-$r.txt" && echo ', some invalid')"
        if [ $rc = 124 ] || [ $rc = 137 ]; then
            log "$name round $r took an hour, killing its compositor"
            pkill -9 -x hypoland
        fi
        if [ $r = 1 ]; then
            bash "$D/bench/measure.sh" --mode check >"$OUT/$name-check.txt" 2>&1
            log "$name check: $(grep -c '^PASS' "$OUT/$name-check.txt") passed, $(grep -c '^FAIL' "$OUT/$name-check.txt") failed"
        fi
        after $name $r "$pid" "$since"
    done
    last=$(($(date +%s) - start))
done
