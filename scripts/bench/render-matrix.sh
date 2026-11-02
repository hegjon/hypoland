#!/bin/bash
# render-matrix.sh [--binary PATH] [--out DIR] [--quick] : render-nested.sh over the scales, turns and effects Hypoland
# keeps (configs in render-configs/: base.lua is gaps, borders, rounding and animations, the others add blur, shadows,
# dimmed and translucent unfocused windows and titlebars to it; omarchy.lua is Omarchy's own look on its own), one nested
# compositor after the other, about two minutes each. --quick runs scale 1 without effects, the base with each effect
# and Omarchy's look once. Prints a line per case and the failed checks, exits 1 when any case failed. Not a GM45: the
# machines' deploy check is the final judge (llvmpipe draws a box at a half pixel on other rows than iris does).
HERE=$(dirname "$(readlink -f "$0")")
C=$HERE/render-configs
BINARY=() OUT= QUICK=
while [ $# -gt 0 ]; do
    case $1 in
        --binary) BINARY=(--binary "$2"); shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --quick) QUICK=1; shift ;;
        *) echo "render-matrix.sh: unknown option $1" >&2; exit 2 ;;
    esac
done
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/render-matrix.XXXXXX")}
mkdir -p "$OUT"
# name, then render-nested.sh's options
CASES=(
    "scale-1|--scale 1"
    "base|--config $C/base.lua"
    "blur|--config $C/base.lua --config $C/glassy.lua"
    "shadows|--config $C/base.lua --config $C/shadows.lua"
    "dim|--config $C/base.lua --config $C/dim.lua"
    "titlebars|--config $C/base.lua --config $C/titlebars.lua"
    "omarchy|--config $C/omarchy.lua"
)
[ -n "$QUICK" ] || CASES+=(
    "scale-2|--scale 2"
    "scale-1.6|--scale 1.6"
    "base-scale-2|--scale 2 --config $C/base.lua"
    "blur-scale-2|--scale 2 --config $C/base.lua --config $C/glassy.lua"
    "turned-90|--transform 1 --config $C/base.lua"
    "turned-90-scale-2|--transform 1 --scale 2"
    "flipped-270|--transform 7 --scale 1.6"
    "base-scale-1.5|--scale 1.5 --config $C/base.lua"
    "omarchy-scale-1.5|--scale 1.5 --config $C/omarchy.lua"
)
FAILED=0
for c in "${CASES[@]}"; do
    name=${c%%|*}
    read -r -a opts <<<"${c#*|}"
    "$HERE/render-nested.sh" "${BINARY[@]}" "${opts[@]}" --out "$OUT/$name" >"$OUT/$name.txt" 2>&1
    rc=$?
    printf '%-20s %s, %d passed, %d failed, %d skipped\n' "$name" "$([ $rc = 0 ] && echo PASS || echo FAIL)" \
        "$(grep -c '^PASS' "$OUT/$name.txt")" "$(grep -c '^FAIL' "$OUT/$name.txt")" "$(grep -c '^SKIP' "$OUT/$name.txt")"
    grep '^FAIL' "$OUT/$name.txt" | sed 's/^/    /'
    [ $rc = 0 ] || FAILED=1
done
echo "output in $OUT"
exit $FAILED
