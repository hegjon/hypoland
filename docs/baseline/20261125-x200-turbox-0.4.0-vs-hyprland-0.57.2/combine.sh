#!/bin/bash
# combine.sh OUT : the blocks of night-20261124-040 and night-20261125 (Hypoland 0.4.0 release against Hyprland
# 0.57.2-2, the same packages both nights) for x200 and turbox in one run, aggregated as report.sh does.
# Night 1's blocks keep their numbers, night 2's get 100 added (101, 102, ...), so raw.txt tells them apart.
set -eu
T=/home/jonny/Work/hypoland/test-results
REPO=/home/jonny/Work/hypoland
OUT=$1
N1=$T/night-20261124-040/night-20261124-040
N2=$T/night-20261125/night-20261125
for h in x200 turbox; do
    d=$OUT/$h
    mkdir -p "$d/blocks"
    for n in 1 2; do
        src=$([ $n = 1 ] && echo $N1 || echo $N2)
        add=$([ $n = 1 ] && echo 0 || echo 100)
        skip=$src/$h.skip
        for f in "$src/$h"/hypoland-[0-9]*.txt "$src/$h"/hyprland-[0-9]*.txt; do
            [ -e "$f" ] || continue
            b=${f##*/}
            grep -qx "$b" "$skip" 2>/dev/null && continue
            # hypoland-3.txt / hypoland-3-startup.txt -> number + add
            num=$(echo "$b" | sed -E 's/^[a-z]+-([0-9]+).*/\1/')
            new=$(echo "$b" | sed -E "s/^([a-z]+)-[0-9]+/\1-$((num + add))/")
            cp "$f" "$d/blocks/$new"
        done
        for c in hypoland-check.txt hyprland-check.txt log; do
            [ -e "$src/$h/$c" ] && cp "$src/$h/$c" "$d/${c%.txt}-night$n.${c##*.}"
        done
    done
    # log has no extension: the loop above wrote log-night1.log / log-night2.log
    for v in hypoland hyprland; do
        mkdir -p "$d/$v"
        files=("$d/blocks"/$v-[0-9]*.txt)
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
        python3 "$REPO/scripts/bench/openmetrics.py" write "$d/$v" --label machine="$h" --label run="night-20261124-040+night-20261125"
    done
    echo "== $h: $(grep -cE '^@ [0-9]+ cpu\.gpu-client\.percent ' "$d/hypoland/raw.txt") Hypoland / $(grep -cE '^@ [0-9]+ cpu\.gpu-client\.percent ' "$d/hyprland/raw.txt") Hyprland sessions"
    (cd "$REPO" && ./bench.sh --compare "$d/hyprland" "$d/hypoland") > "$d/compare.txt" 2>&1 || true
    rm -rf "$d/blocks"
done
