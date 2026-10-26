# shellcheck shell=bash
# Part of measure.sh: what is measured around a workload: CPU time, memory, GPU buffers, perf and the meter.

# on-CPU time of all threads of the compositor in ns, the 1% steps of pidstat are too coarse for small changes
cputime() { cat /proc/$P/task/*/schedstat 2>/dev/null | awk '{s += $1} END {printf "%.0f\n", s}'; }

# The CPU time a workload costs in all: work a change moves from the compositor into the clients (or into Xwayland,
# the shell or the driver's kernel threads) is not in the compositor's. In ns: a cgroup's, with every process that
# ran in it, also those that ended (empty when it is not there), and the busy time of all CPUs from /proc/stat, in
# its ticks of 1/CLK_TCK s
cgtime() { awk '$1 == "usage_usec" {printf "%.0f\n", $2 * 1000}' "$1/cpu.stat" 2>/dev/null; } # cgroup path
TICK_NS=$((1000000000 / $(getconf CLK_TCK)))
busytime() { awk -v t=$TICK_NS '$1 == "cpu" {printf "%.0f\n", ($2 + $3 + $4 + $7 + $8 + $9) * t; exit}' /proc/stat; }
cgroot() { [ -n "$USERCG" ] && echo "/sys/fs/cgroup$USERCG"; }

# The frames the compositor put on the screen: its page flips, counted as the flip events DRM delivers to it (the
# same tracepoint on i915, radeon and msm), with perf as root. A client's own frame rate is fps.<workload>. A sum of
# CPU time says little without them: a compositor that shows more frames makes its clients draw more (resize on the
# X200). FLIPS is 1 when perf can count them, found out on first use
FLIP_EVENT=drm:drm_vblank_event_delivered
FLIPS=""
flips_counted() {
    if [ -z "$FLIPS" ]; then
        FLIPS=0
        [ $ROOT = 1 ] && command -v perf >/dev/null && perf stat -a -x, -e $FLIP_EVENT -- true >/dev/null 2>&1 && FLIPS=1
    fi
    [ $FLIPS = 1 ]
}

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
    local name=$1 t0 t1 c0 c1 m0 m1 u0 u1 k0 k1 b0 b1 sampler="" flipper="" user
    if command -v pidstat >/dev/null; then
        pidstat -u -p $P 1 "$SECONDS_PER_RUN" >"$OUT/$name.pidstat" &
        sampler=$!
    fi
    if flips_counted; then
        perf stat -a -x, -e $FLIP_EVENT -o "$OUT/$name.flips" -- sleep "$SECONDS_PER_RUN" >/dev/null 2>&1 &
        flipper=$!
    fi
    battery_check
    user=$(cgroot)
    m0=$(mark) c0=$(cputime) t0=$(date +%s%N) u0=$(cgtime "$user") k0=$(cgtime "$user/$SLICE") b0=$(busytime)
    window "$name"
    c1=$(cputime) t1=$(date +%s%N) u1=$(cgtime "$user") k1=$(cgtime "$user/$SLICE") b1=$(busytime) m1=$(mark)
    [ -n "$sampler" ] && wait "$sampler"
    [ -n "$flipper" ] && wait "$flipper"
    echo "--- $name; clients: $(clients)$(in_the_way)"
    [ -n "$(in_the_way)" ] && value "invalid.$name" 1
    value "cpu.$name.percent" "$(percent $((c1 - c0)) $((t1 - t0)))"
    # the clients' slice is there while they run; without clients it reads nothing at both ends
    if [ ${#SCOPE[@]} -gt 0 ] && [ "${k1:-0}" -ge "${k0:-0}" ]; then
        value "cpu.$name.clients_percent" "$(percent $((${k1:-0} - ${k0:-0})) $((t1 - t0)))"
    fi
    [ -n "$u0" ] && [ -n "$u1" ] && value "cpu.$name.total_percent" "$(percent $((u1 - u0)) $((t1 - t0)))"
    value "cpu.$name.machine_percent" "$(percent $((b1 - b0)) $((t1 - t0)))"
    [ -n "$flipper" ] && awk -F, -v r=$ROUND -v n="$name" -v s="$SECONDS_PER_RUN" -v e=$FLIP_EVENT '
        $3 == e && $1 ~ /^[0-9]+$/ {printf "@ %s fps.%s.screen %.1f\n", r, n, $1 / s}' "$OUT/$name.flips"
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

percent() { awk -v c="$1" -v t="$2" 'BEGIN {printf "%.2f", 100 * c / t}'; } # ns of CPU time, ns of wall time

rec() {
    if [ "$MODE" = perf ]; then perf_rec "$1"; else bench "$1"; fi
}
