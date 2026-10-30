#!/usr/bin/env bash
# Measures CPU time and memory of the compositor on the machine under test, to compare a change against a
# baseline. Builds the package, installs it and restarts the session through scripts/deploy.sh, whose checks
# have to pass, then runs the workloads of scripts/bench/measure.sh. With --no-deploy or --host local it
# measures the compositor that is running.
#
# Usage: ./bench.sh [options] [label]
#        ./bench.sh --compare <baseline dir> <candidate dir>
#
#   --rounds N         how often the workloads are repeated (default 3)
#   --settle N         age of the compositor in seconds before memory is measured (default 60)
#   --energy           measure the power each workload costs and the instructions the compositor executes,
#                      with the governor left alone (workloads of 30 s). Without RAPL (the X200) the meter
#                      is the battery: unplug the charger first
#   --meter M          auto, rapl, battery or none (only instructions and cycles), with --energy
#   --idle N           length of the idle baseline before and after every workload (default 10), with --energy
#   --min-battery N    stop below N percent battery (default 30), with --energy
#   --powercap DIR, --power-supply DIR
#                      where the meters are on the machine under test (default /sys/class/...)
# TARGET_HELP
#
# Writes test-results/bench-<time>-<label>/values.txt with "<key> <median> <min> <max>" per line.

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1
. scripts/bench/target.sh

compare() {
    [ -f "$1/values.txt" ] && [ -f "$2/values.txt" ] || { echo "no values.txt in $1 or $2" >&2; exit 2; }
    awk '
        NR == FNR {base[$1] = $2; lo[$1] = $3; hi[$1] = $4; next}
        !($1 in base) {next}
        {
            d = $2 - base[$1]
            # a change inside the spread of the rounds of either run is noise
            noise = (hi[$1] - lo[$1] > $4 - $3) ? hi[$1] - lo[$1] : $4 - $3
            # two starts of the same build differ by up to 1.2 MiB and 0.2 points of CPU time; a key lands anywhere in a
            # frame of 16.7 ms, a guess for latencies until more runs show their spread
            floor = ($1 ~ /^mem\./) ? 1500 : ($1 ~ /^latency\./) ? 3 : 0.3
            # the start of a session is one sample a round, with the 10 ms steps of the process start time and the shell in it
            if ($1 ~ /^startup\..*_ms$/)
                floor = 30
            if (noise < floor)
                noise = floor
            mark = ""
            # the power of the whole machine drifts, a guess until real runs show how much
            if ($1 ~ /^power\./ && noise < 0.3)
                noise = 0.3
            # instructions repeat to about a percent
            if ($1 ~ /^perf\./ && noise < base[$1] / 50)
                noise = base[$1] / 50
            if ($1 ~ /^(cpu\..*[._]percent|cpu\..*\.ms_per_frame|gpu\..*\.busy_(percent|ms_per_frame)|mem\..*_kB|binary\.size_kB|power\.(baseline\.W|.*\.net_W)|perf\..*\.Minstructions|latency\..*_ms|startup\..*_ms)$/ && (d > noise || d < -noise) && d != 0)
                mark = (d < 0) ? "better" : "WORSE"
            if ($1 ~ /^fps\./ && d < -1)
                mark = "WORSE"
            printf "%-38s %10s %10s %+10.2f  %s\n", $1, base[$1], $2, d, mark
        }
    ' "$1/values.txt" "$2/values.txt"
    grep -h "^invalid" "$1/values.txt" "$2/values.txt" | sed 's/^/NOT VALID: /'
    # values of different machines or workloads say nothing about a change
    local a b
    a=$(grep -h "^machine:" "$1/bench.txt" 2>/dev/null)
    b=$(grep -h "^machine:" "$2/bench.txt" 2>/dev/null)
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then
        echo "NOTE: the two runs are from different machines or kernels:"
        printf '  %s\n  %s\n' "$a" "$b"
    fi
}

ROUNDS=3 LABEL="" SECONDS_SET=0 MODE=bench
while [ $# -gt 0 ]; do
    case $1 in
        --compare) [ $# -eq 3 ] || { target_usage "$0"; exit 2; }; compare "$2" "$3"; exit 0 ;;
        --rounds) ROUNDS=$2; shift ;;
        --settle) MEASURE_ARGS+=(--settle "$2"); shift ;;
        --energy) MODE=energy ;;
        --meter | --idle | --min-battery | --powercap | --power-supply) MEASURE_ARGS+=("$1" "$2"); shift ;;
        -h | --help) target_usage "$0"; exit 0 ;;
        -*)
            [ "$1" = --seconds ] && SECONDS_SET=1
            target_option "$@" || { echo "unknown argument: $1" >&2; exit 2; }
            shift $((TARGET_SHIFT - 1))
            ;;
        *) LABEL=-$1 ;;
    esac
    shift
done
if [ $SECONDS_SET = 0 ]; then
    # a battery reports a new discharge rate every few seconds, energy needs longer windows
    if [ $MODE = energy ]; then MEASURE_ARGS+=(--seconds 30); else MEASURE_ARGS+=(--seconds 20); fi
fi

[ $MODE = energy ] && LABEL=-energy$LABEL
OUT=test-results/bench-$(date +%Y%m%d-%H%M%S)$LABEL
mkdir -p "$OUT"
{ git rev-parse HEAD; git status --short; } >"$OUT/source.txt" 2>&1
git diff HEAD >"$OUT/source.diff" 2>&1

if [ $DEPLOY = 1 ] && ! target_deploy "$OUT/test.log" "${DEPLOY_ARGS[@]}"; then
    echo "the deploy failed, nothing was measured:"
    grep -E "^(FAIL|build failed)" "$OUT/test.log"
    exit 1
fi

target_run --mode $MODE --rounds "$ROUNDS" "${MEASURE_ARGS[@]}" | tee "$OUT/bench.txt" | grep --line-buffered -v "^@"
if ! grep -q "^@ .* mem.end" "$OUT/bench.txt"; then
    echo "the measurement did not finish, see $OUT/bench.txt"
    exit 1
fi

# median, min and max over the rounds
grep "^@" "$OUT/bench.txt" | sort -k3,3 -k4,4g | awk '
    function flush() {
        if (n) printf "%s %s %s %s\n", key, v[int((n + 1) / 2)], v[1], v[n]
        n = 0
    }
    $3 != key {flush(); key = $3}
    {v[++n] = $4}
    END {flush()}
' >"$OUT/values.txt"

echo
column -t -N key,median,min,max "$OUT/values.txt"
grep -q "^invalid" "$OUT/values.txt" && echo "NOT VALID: a screensaver, a lock, a compositor restart, the charger or a low battery got in the way"
echo "values: $OUT/values.txt"
