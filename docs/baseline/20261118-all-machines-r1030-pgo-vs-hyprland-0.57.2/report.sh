#!/bin/bash
# report.sh RUN [host...] : fetches /root/abnight/RUN from the machines into ./RUN/<host>/ and writes, per compositor,
# values.txt in bench.sh's format ("<key> <median> <min> <max>" over the blocks), raw.txt with every value of every block
# ("@ <block> <key> <value>"), a bench.txt with the first block's machine, compositor and package lines and results.om
# (every value of every block in OpenMetrics, scripts/bench/openmetrics.py),
# then compares Hyprland 0.57.2 (baseline) with Hypoland (candidate) through bench.sh --compare. Blocks named in
# ./RUN/<host>.skip (one file name a line, e.g. hyprland-16.txt) are left out.
RUN=$1
shift
HOSTS=${*:-x200 t550 xps lianli chromebook t460s t490 samsung-i5 macmini-m1 hp-amd p14s macmini-intel}
REPO=/home/jonny/Work/hypoland
here=$(pwd)
for h in $HOSTS; do
    d=$here/$RUN/$h
    mkdir -p "$d"
    scp -q -r "root@$h:/root/abnight/$RUN/*" "$d/" 2>/dev/null || { echo "== $h: nothing fetched"; continue; }
    skipped=0
    for v in hypoland hyprland; do
        mkdir -p "$d/$v"
        files=()
        for f in "$d"/$v-[0-9]*.txt; do
            [ -e "$f" ] || continue
            if grep -qx "${f##*/}" "$here/$RUN/$h.skip" 2>/dev/null; then skipped=$((skipped + 1)); else files+=("$f"); fi
        done
        [ ${#files[@]} -gt 0 ] || continue
        # the first block's lines about the machine and the compositor (its start and package: results.om's time and version)
        for l in machine compositor package clocksource; do grep -h "^$l:" "${files[@]}" | head -1; done >"$d/$v/bench.txt"
        for f in "${files[@]}"; do
            b=${f##*-}
            grep "^@" "$f" | awk -v b="${b%.txt}" 'NF >= 4 {print "@", b, $3, $4}'
        done | sort -s -t' ' -k2,2n >"$d/$v/raw.txt"
        grep -h "^@" "${files[@]}" | awk 'NF >= 4 {print $3, $4}' | sort -k1,1 -k2,2g | awk '
            function flush() {
                if (n) printf "%s %s %s %s\n", key, v[int((n + 1) / 2)], v[1], v[n]
                n = 0
            }
            $1 != key {flush(); key = $1}
            {v[++n] = $2}
            END {flush()}
        ' >"$d/$v/values.txt"
        # every value of every block in OpenMetrics, labelled with machine, compositor, version, run and block
        python3 "$REPO/scripts/bench/openmetrics.py" write "$d/$v" --label machine="$h" --label run="$RUN"
    done
    blocks="$(ls "$d"/hypoland-[0-9]*.txt 2>/dev/null | wc -l) Hypoland / $(ls "$d"/hyprland-[0-9]*.txt 2>/dev/null | wc -l) Hyprland 0.57.2 blocks, $skipped left out"
    echo "== $h: $blocks, Hyprland 0.57.2 -> Hypoland"
    (cd "$REPO" && ./bench.sh --compare "$d/hyprland" "$d/hypoland")
done
