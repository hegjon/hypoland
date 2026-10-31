#!/bin/bash
# render-nested.sh [--scale S] [--config FILE] [--binary PATH] [--out DIR] [render.py options...] : the render checks
# (clients/render.py) against a compositor of this tree started inside the desktop's session, with one headless output
# of 1280x800 at scale S (1 by default) and the nested window switched off, so the desktop's screen does not matter.
# The screen is captured without a pause (render.py --grab screencopy), so stale pixels show as they would on a real
# screen. FILE is Lua added to the config (Omarchy's gaps, rounding and animations, for instance). Takes a few minutes;
# prints the checks and exits like render.py. Not a GM45: the machines' deploy check is the final judge.
SCALE=1 EXTRA= OUT=
BIN=$(dirname "$(readlink -f "$0")")/../../build/hypoland
while [ $# -gt 0 ]; do
    case $1 in
        --scale) SCALE=$2; shift 2 ;;
        --config) EXTRA=$2; shift 2 ;;
        --binary) BIN=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        *) break ;;
    esac
done
HERE=$(dirname "$(readlink -f "$0")")
HYPRCTL=$HERE/../../build/hyprctl/hyprctl
command -v "$HYPRCTL" >/dev/null || HYPRCTL=hyprctl
[ -x "$BIN" ] || { echo "render-nested.sh: no compositor at $BIN (build it, or --binary)" >&2; exit 2; }
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/render-nested.XXXXXX")}
mkdir -p "$OUT"
{
    echo "hl.monitor({ output = \"HEADLESS-1\", mode = \"1280x800@60\", position = \"0x0\", scale = \"$SCALE\" })"
    echo 'hl.monitor({ output = "", disabled = true })'
    [ -n "$EXTRA" ] && cat "$EXTRA"
} >"$OUT/config.lua"
HYPRLAND_NO_CRASHREPORTER=1 "$BIN" --config "$OUT/config.lua" >"$OUT/compositor.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null; wait $PID 2>/dev/null' EXIT
LOCK=
for _ in $(seq 1 100); do
    LOCK=$(grep -lx "$PID" "$XDG_RUNTIME_DIR"/hypr/*/hyprland.lock 2>/dev/null | head -n 1)
    [ -n "$LOCK" ] && break
    sleep 0.1
done
[ -n "$LOCK" ] || { echo "render-nested.sh: the compositor did not start, see $OUT/compositor.log" >&2; exit 2; }
SIG=$(basename "$(dirname "$LOCK")")
SOCKET=$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock
for _ in $(seq 1 50); do [ -S "$SOCKET" ] && break; sleep 0.1; done
sleep 1
HYPRLAND_INSTANCE_SIGNATURE=$SIG timeout 5 "$HYPRCTL" output create headless HEADLESS-1 >/dev/null
sleep 1.5
echo "compositor $BIN, scale $SCALE, output in $OUT"
WAYLAND_DISPLAY=$(sed -n 2p "$LOCK") timeout 300 python3 -I -B "$HERE/clients/render.py" --socket "$SOCKET" --out "$OUT/render" \
    --grab screencopy --no-freeze "$@"
