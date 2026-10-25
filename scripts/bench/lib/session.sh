# shellcheck shell=bash
# Part of measure.sh: the compositor under test, its session, and the clients started in it.

for name in ${PROCESS:-hypoland Hypoland Hyprland}; do
    P=$(pgrep -n -x "$name" 2>/dev/null) && PROCESS=$name && break
done
[ -n "${P:-}" ] || { echo "no compositor is running (looked for ${PROCESS:-hypoland, Hypoland, Hyprland})"; exit 1; }

TESTUSER=$(stat -c %U /proc/$P)
USERHOME=$(getent passwd "$TESTUSER" | cut -d: -f6)
RUNTIME=/run/user/$(id -u "$TESTUSER")
BINARY=$(readlink -f /proc/$P/exe)
BINDIR=$(dirname "$BINARY")
ROOT=0
[ "$(id -u)" = 0 ] && ROOT=1
if [ $ROOT = 0 ] && [ "$(id -un)" != "$TESTUSER" ]; then
    echo "the compositor runs as $TESTUSER, run this as $TESTUSER or as root"
    exit 1
fi

# every instance writes its pid and its Wayland socket into a lock file
LOCK=$(grep -l -x "$P" "$RUNTIME"/hypr/*/hyprland.lock 2>/dev/null | head -1)
[ -n "$LOCK" ] || { echo "no instance directory of pid $P in $RUNTIME/hypr"; exit 1; }
SIG=$(basename "$(dirname "$LOCK")")
SOCKET=$(sed -n 2p "$LOCK")

# clients get the environment the compositor was started with (locale, PATH, XDG variables), plus what the
# compositor sets for its children
mapfile -d '' SESSIONENV </proc/$P/environ
SESSIONENV+=(HOME="$USERHOME" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" HYPRLAND_INSTANCE_SIGNATURE="$SIG")
[ -d /usr/share/omarchy ] && SESSIONENV+=(OMARCHY_PATH=/usr/share/omarchy)
SESSIONENV+=("${CLIENT_ENV[@]}")

# runs a command in the session of the compositor. The script itself may arrive on stdin, nothing may read from it
asuser() {
    if [ $ROOT = 1 ]; then
        runuser -u "$TESTUSER" -- env -i -C "$USERHOME" "${SESSIONENV[@]}" "$@" </dev/null
    else
        env -i -C "$USERHOME" "${SESSIONENV[@]}" "$@" </dev/null
    fi
}
H() { asuser timeout 8 "$BINDIR/hyprctl" "$@"; }

# the dispatchers are Lua in this version and plain words before it
dispatch() { # lua, legacy
    [ "$(H dispatch "$1" 2>/dev/null)" = ok ] || H dispatch $2 >/dev/null 2>&1
}

# Clients are started as leaders of their own process group and stopped through it, so stopping one takes
# its children along and never hits a window of the user.
CLIENTS=0
client() { # seconds to live, command
    local ttl=$1 pidfile
    shift
    CLIENTS=$((CLIENTS + 1))
    pidfile=$CLIENTDIR/client.$CLIENTS.pid
    rm -f "$pidfile"
    asuser setsid sh -c 'echo $$ >"$0"; exec timeout "$1" sh -c "$2"' "$pidfile" "$ttl" "$*" >/dev/null 2>&1 &
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$pidfile" ] && break
        sleep 0.1
    done
}
stop_clients() {
    local pidfile
    local pid
    for pidfile in "$CLIENTDIR"/client.*.pid; do
        pid=$(cat "$pidfile" 2>/dev/null)
        rm -f "$pidfile"
        # the clients' directory belongs to the compositor user: only signal a process group of that user
        [[ $pid =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || continue
        [ "$(ps -o uid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$(id -u "$TESTUSER")" ] || continue
        kill -- "-$pid" 2>/dev/null
    done
}
