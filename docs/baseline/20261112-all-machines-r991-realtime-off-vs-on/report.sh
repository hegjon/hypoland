#!/bin/bash
# report.sh RUN [host...] : fetches /root/abrt/RUN (abrt.sh) from the machines into ./RUN/<host>/ and writes, per variant
# (nort: HYPRLAND_NO_RT=1, rt: HYPRLAND_NO_RT=0), values.txt in bench.sh's format ("<key> <median> <min> <max>" over the
# blocks), raw.txt ("@ <block> <key> <value>") and bench.txt with the machine line, then compares nort (baseline) with rt
# (candidate) through bench.sh --compare. Blocks named in ./RUN/<host>.skip (e.g. rt-3.txt) are left out.
RUN=$1
shift
HOSTS=${*:-x200 t550 xps lianli chromebook t460s t490 samsung-i5 galaxybook macmini-intel macmini-m1}
REPO=/home/jonny/Work/hypoland
here=$(pwd)
for h in $HOSTS; do
    d=$here/$RUN/$h
    mkdir -p "$d"
    scp -q -r "root@$h:/root/abrt/$RUN/*" "$d/" 2>/dev/null || { echo "== $h: nothing fetched"; continue; }
    skipped=0
    for v in nort rt; do
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
    blocks="$(ls "$d"/nort-[0-9]*.txt 2>/dev/null | grep -vc startup) HYPRLAND_NO_RT=1 / $(ls "$d"/rt-[0-9]*.txt 2>/dev/null | grep -vc startup) HYPRLAND_NO_RT=0 blocks, $skipped left out"
    echo "== $h: $blocks, realtime off -> on"
    (cd "$REPO" && ./bench.sh --compare "$d/nort" "$d/rt")
done
