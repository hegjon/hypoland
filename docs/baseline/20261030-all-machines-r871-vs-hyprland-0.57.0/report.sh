#!/bin/bash
# report.sh RUN [host...] : fetches /root/abnight/RUN from the machines into ./RUN/<host>/ and writes, per compositor,
# values.txt in bench.sh's format ("<key> <median> <min> <max>" over the blocks), raw.txt with every value of every block
# ("@ <block> <key> <value>") and a bench.txt with the machine line,
# then compares Hyprland 0.57.0 (baseline) with Hypoland (candidate) through bench.sh --compare. Blocks named in
# ./RUN/<host>.skip (one file name a line, e.g. hyprland-16.txt) are left out.
RUN=$1
shift
HOSTS=${*:-x200 t550 xps lianli chromebook t460s galaxybook macmini-intel}
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
        grep -h "^machine:" "${files[@]}" | head -1 >"$d/$v/bench.txt"
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
    done
    blocks="$(ls "$d"/hypoland-[0-9]*.txt 2>/dev/null | wc -l) Hypoland / $(ls "$d"/hyprland-[0-9]*.txt 2>/dev/null | wc -l) Hyprland 0.57.0 blocks, $skipped left out"
    echo "== $h: $blocks, Hyprland 0.57.0 -> Hypoland"
    (cd "$REPO" && ./bench.sh --compare "$d/hyprland" "$d/hypoland")
done
