#!/bin/bash
# Soak runs that alternate the compositor, to compare Hypoland with stock Hyprland on the same machine over the same
# hours. Run as root on the machine under test, with soak.sh in the session user's home:
#
#   setsid -f nohup /root/soak-ab.sh HOURS [hypoland|hyprland|"hypoland hyprland"] >/dev/null 2>&1 </dev/null
#
# Each block installs one compositor from /var/cache/pacman/pkg (the installed hypoland package, and the newest
# hyprland and omarchy-hyprland-titlebars packages there), starts a new SDDM session, waits for it to settle and runs
# BLOCK_CYCLES (default 1) cycles of soak.sh as the session user, alternating until HOURS are up. Without a stock
# Hyprland in the cache (or where it cannot run, the X200) pass "hypoland": the blocks then only renew the session.
# For the whole run it stops the system's timers (snapper, plocate, man-db and the like) and any update check, keeps
# energy-meter.sh running where /root has it and RAPL is there, and puts it all back at the end with Hypoland
# installed. Stop early with `touch <run dir>/stop`; the block that runs ends after its current workload. A battery
# that discharges below MIN_BATTERY percent (default 40) stops the run the same way: a flat battery means a shutdown
# and the disk password at the next boot.
#
# Writes ~<user>/soak/ab-<time>/: ab.log, blocks.txt, one soak.sh directory per block and report.txt, the medians of
# both compositors side by side. SOAK_SHORT and SOAK_WORKLOADS are passed on, for a quick check of the whole thing.
set -u
HOURS=${1:?hours}
USERNAME=${SOAK_USER:-a}
BLOCK_CYCLES=${BLOCK_CYCLES:-1}
UIDN=$(id -u "$USERNAME")
HOMEDIR=$(getent passwd "$USERNAME" | cut -d: -f6)
SOAK=$HOMEDIR/soak.sh
CACHE=/var/cache/pacman/pkg
AB=$HOMEDIR/soak/ab-$(date +%Y%m%d-%H%M%S)
END=$(($(date +%s) + HOURS * 3600))

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
mkdir -p "$AB"
chown "$USERNAME:" "$HOMEDIR/soak" "$AB"
exec >>"$AB/ab.log" 2>&1
log() { echo "$(date '+%F %T') $*"; }
[ -r "$SOAK" ] || { log "no $SOAK"; exit 1; }

# the packages of both compositors
pkgfile() { # newest file of a package in the cache, optionally of a version
    find "$CACHE" -maxdepth 1 -name "$1-${2:-[0-9]}*.pkg.tar.*" ! -name "*.sig" | sort -V | tail -1
}
HYPOLAND=$(pkgfile hypoland "$(pacman -Q hypoland 2>/dev/null | awk '{print $2}')")
HYPRLAND="$(pkgfile hyprland) $(pkgfile omarchy-hyprland-titlebars)"
VARIANTS=${2:-}
if [ -z "$VARIANTS" ]; then
    VARIANTS=hypoland
    [ -n "$(pkgfile hyprland)" ] && [ -n "$(pkgfile omarchy-hyprland-titlebars)" ] && VARIANTS="hypoland hyprland"
fi
[ -n "$HYPOLAND" ] || { log "no package of the installed hypoland in $CACHE"; exit 1; }
log "soak A/B for $HOURS h on $(uname -n), blocks of $BLOCK_CYCLES cycle(s), variants: $VARIANTS"
log "hypoland: $HYPOLAND"
[[ $VARIANTS == *hyprland* ]] && log "hyprland: $HYPRLAND"

# ---- what is paused for the run

TIMERS=$(systemctl list-units --type=timer --state=active --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
[ -n "$TIMERS" ] && systemctl stop $TIMERS && log "stopped timers: $TIMERS"
# Omarchy's bar looks for updates when its shell starts, so at every new session (soak.sh stops them during its run)
UPDATE_CHECK='^(/usr)?/bin/bash /usr/(share/omarchy/)?bin/(omarchy-update-available|checkupdates)( |$)|^(/bin/sh /usr/bin/fakeroot -- )?pacman -Sy .*--dbpath /tmp/checkup-db-'
(while sleep 5; do pkill -u "$USERNAME" -f "$UPDATE_CHECK" && log "stopped an update check"; done) &
GUARD=$!
MIN_BATTERY=${MIN_BATTERY:-40}
battery_low() {
    local b
    for b in /sys/class/power_supply/*; do
        [ "$(cat "$b/type" 2>/dev/null)" = Battery ] && [ "$(cat "$b/status" 2>/dev/null)" = Discharging ] || continue
        [ "$(cat "$b/capacity" 2>/dev/null || echo 100)" -lt "$MIN_BATTERY" ] && return 0
    done
    return 1
}
stop_if_battery_low() {
    [ -e "$AB/stop" ] || ! battery_low || { log "battery below $MIN_BATTERY% and discharging, stopping"; touch "$AB/stop"; }
}
energy_meter() {
    [ -x /root/energy-meter.sh ] && [ -r /sys/class/powercap/intel-rapl:0/energy_uj ] || return 0
    pgrep -f "[e]nergy-meter.sh" >/dev/null || setsid -f /root/energy-meter.sh >/dev/null 2>&1 </dev/null
}

# ---- one compositor, a new session

installed() { pacman -Q hypoland >/dev/null 2>&1 && echo hypoland || echo hyprland; }
compositor() { pgrep -u "$USERNAME" -x 'hypoland|Hyprland'; }
ready() { # the compositor has written its lock file and the shell is up
    local p
    for _ in $(seq 1 240); do
        p=$(compositor | head -1)
        [ -n "$p" ] && grep -qx "$p" /run/user/"$UIDN"/hypr/*/hyprland.lock 2>/dev/null && pgrep -u "$USERNAME" -x quickshell >/dev/null && return 0
        sleep 0.5
    done
    return 1
}
use() { # variant
    if [ "$(installed)" != "$1" ]; then
        if [ "$1" = hypoland ]; then
            pacman -U --noconfirm --ask=4 $HYPOLAND >/dev/null 2>&1
        else
            pacman -U --noconfirm --ask=4 $HYPRLAND >/dev/null 2>&1
        fi || { log "installing $1 failed"; return 1; }
    fi
    systemctl stop sddm
    for _ in $(seq 1 100); do compositor >/dev/null || break; sleep 0.2; done
    systemctl --user -M "$USERNAME@" stop graphical-session.target graphical-session-pre.target 2>/dev/null
    sleep 2
    # Quickshell leaves the logs of ended instances in the tmpfs, and a shell that spun (the clock of the bar in the
    # repeated hour of 2026-10-25) wrote up to 380 MB, which filled /run/user after a few sessions. Nothing of the
    # session runs now, so they go; the space of a file a straggler still writes to is freed when it ends
    rm -rf /run/user/"$UIDN"/quickshell/by-id/* /run/user/"$UIDN"/quickshell/by-pid/* 2>/dev/null
    systemctl start sddm
    ready || { log "no session with $1"; return 1; }
    # the shell's start, Omarchy's autostart and the update check have run
    sleep 60
}

restore() {
    trap - EXIT
    kill "$GUARD" 2>/dev/null
    [ -n "${RUN:-}" ] && kill "$RUN" 2>/dev/null
    if [ "$(installed)" != hypoland ]; then
        log "back to hypoland"
        use hypoland
    fi
    [ -n "$TIMERS" ] && systemctl start $TIMERS && log "started the timers again"
    report
    log "done"
}
trap restore EXIT
trap 'exit 1' HUP INT TERM

# ---- report: the medians of each compositor over its blocks

report() {
    local v dirs
    each() { local d; for d in $dirs; do cat "$d/$1" 2>/dev/null; done; } # a file of every block
    {
        echo "Soak A/B on $(uname -n), $(cat /sys/class/dmi/id/product_version /sys/class/dmi/id/product_name 2>/dev/null | head -1)"
        echo "blocks (number variant package directory):"
        sed 's/^/  /' "$AB/blocks.txt" 2>/dev/null
        echo
        for v in $VARIANTS; do
            dirs=$(awk -v v="$v" '$2 == v {print $4}' "$AB/blocks.txt" 2>/dev/null)
            [ -n "$dirs" ] || continue
            echo "== $v: $(echo "$dirs" | wc -l) block(s), $(each soak.log | grep -c EVENT) events"
            # cpu.txt: cycle workload cpu% Minstructions/s Mcycles/s W seconds
            each cpu.txt | awk '
                function med(s,   a, n, i, j, t) {n = split(s, a, " "); if (!n) return "nan"
                    for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] + 0 < a[i] + 0) {t = a[i]; a[i] = a[j]; a[j] = t}
                    return a[int((n + 1) / 2)]}
                {order[$2] = order[$2] ? order[$2] : ++k; c[$2] = c[$2] " " $3; if ($4 != "nan") i[$2] = i[$2] " " $4; if ($6 != "nan") w[$2] = w[$2] " " $6; n[$2]++}
                END {printf "  %-24s %4s %8s %12s %7s\n", "workload", "runs", "CPU %", "Minstr/s", "W"
                    for (x in order) line[order[x]] = x
                    for (o = 1; o <= k; o++) {x = line[o]; printf "  %-24s %4d %8s %12s %7s\n", x, n[x], med(c[x]), med(i[x]), med(w[x])}}'
            # samples.txt: time elapsed pid pss anon rss gpu fds threads cpu ipc clients xwayland quickshell state cpu_C fan
            each samples.txt | awk '
                function med(s,   a, n, i, j, t) {n = split(s, a, " "); if (!n) return "nan"
                    for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] + 0 < a[i] + 0) {t = a[i]; a[i] = a[j]; a[j] = t}
                    return a[int((n + 1) / 2)]}
                $1 != "time" && $4 ~ /^[0-9]+$/ {p = p " " $4; an = an " " $5; g = g " " $7; if ($16 ~ /^[0-9]+$/) t = t " " $16}
                END {printf "  memory, median of the samples: Pss %d MiB, anonymous %d MiB, GPU buffers %d MiB; CPU %s C\n",
                    med(p) / 1024, med(an) / 1024, med(g) / 1024, med(t)}'
            each glmark2.txt | awk '{s = s " " $2} END {if (s) print "  glmark2 scores:" s}'
            echo
        done
    } >"$AB/report.txt"
}

# ---- blocks

N=0
while [ "$(date +%s)" -lt "$END" ] && [ ! -e "$AB/stop" ]; do
    for v in $VARIANTS; do
        stop_if_battery_low
        [ "$(date +%s)" -lt "$END" ] && [ ! -e "$AB/stop" ] || break
        N=$((N + 1))
        log "block $N: $v"
        use "$v" || { sleep 60; continue; }
        energy_meter
        DIR=$AB/$(printf '%03d' $N)-$v
        echo "$N $v $(pacman -Q "$v" | awk '{print $2}') $DIR" >>"$AB/blocks.txt"
        runuser -u "$USERNAME" -- env -i HOME="$HOMEDIR" USER="$USERNAME" LOGNAME="$USERNAME" LANG=C.UTF-8 \
            PATH=/usr/local/bin:/usr/bin:/usr/share/omarchy/bin XDG_RUNTIME_DIR=/run/user/"$UIDN" DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$UIDN"/bus \
            SOAK_CYCLES="$BLOCK_CYCLES" SOAK_OUT="$DIR" SOAK_SHORT="${SOAK_SHORT:-0}" ${SOAK_WORKLOADS:+SOAK_WORKLOADS="$SOAK_WORKLOADS"} \
            bash "$SOAK" 24 &
        RUN=$!
        while kill -0 "$RUN" 2>/dev/null; do
            stop_if_battery_low
            [ -e "$AB/stop" ] && [ -d "$DIR" ] && touch "$DIR/stop"
            sleep 10
        done
        wait "$RUN"
        RUN=""
        log "block $N done: $(tail -1 "$DIR/soak.log" 2>/dev/null)"
        report
    done
done
