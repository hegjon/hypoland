# shellcheck shell=bash
# Part of measure.sh: what would spoil the numbers is switched off for the run and put back at the exit, and
# the directories of the run are made. Runs when sourced.

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
