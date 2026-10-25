# shellcheck shell=bash
# Part of measure.sh: the energy meters, RAPL or the battery, sampled into power.log for the energy mode.

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
