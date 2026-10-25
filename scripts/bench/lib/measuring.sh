# shellcheck shell=bash
# Part of measure.sh: what is measured around a workload: CPU time, memory, GPU buffers, perf and the meter.

# on-CPU time of all threads of the compositor in ns, the 1% steps of pidstat are too coarse for small changes
cputime() { cat /proc/$P/task/*/schedstat 2>/dev/null | awk '{s += $1} END {printf "%.0f\n", s}'; }

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
    local name=$1 t0 t1 c0 c1 m0 m1 sampler=""
    if command -v pidstat >/dev/null; then
        pidstat -u -p $P 1 "$SECONDS_PER_RUN" >"$OUT/$name.pidstat" &
        sampler=$!
    fi
    battery_check
    m0=$(mark) c0=$(cputime) t0=$(date +%s%N)
    window "$name"
    c1=$(cputime) t1=$(date +%s%N) m1=$(mark)
    [ -n "$sampler" ] && wait "$sampler"
    echo "--- $name; clients: $(clients)$(in_the_way)"
    [ -n "$(in_the_way)" ] && value "invalid.$name" 1
    value "cpu.$name.percent" "$(awk -v c=$((c1 - c0)) -v t=$((t1 - t0)) 'BEGIN {printf "%.2f", 100 * c / t}')"
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

rec() {
    if [ "$MODE" = perf ]; then perf_rec "$1"; else bench "$1"; fi
}
