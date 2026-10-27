# shellcheck shell=bash
# Part of measure.sh: the check mode, does the session work after a deploy. Prints PASS / FAIL lines.

RESULT=0 MONITOR=""
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; RESULT=1; }
skip() { echo "SKIP  $*"; }
info() { echo "INFO  $*"; }

nclients() { H clients -j | grep -c '"address"'; }
# waits until there are more windows than before
mapped() { # windows before, seconds
    local i
    for i in $(seq 1 "$2"); do
        [ "$(nclients)" -gt "$1" ] && return 0
        sleep 1
    done
    return 1
}

# the share of the test color in an image, in percent. A screenshot can have alpha (Chromium's buffers do), which
# would count in the mean. Everything else turns black before the color turns white, or white pixels (the bar's
# text) would count as the color
magenta() { magick "$1" -alpha off -fuzz 12% -fill black +opaque '#ff00ff' -fill white -opaque '#ff00ff' -format '%[fx:int(mean*100)]' info: 2>/dev/null || echo 0; }
# the frame rate a client printed: weston-simple-egl "... frames in 5 seconds: 60.0 fps", glxgears "= 59.9 FPS"
fps_of() { awk '/frames in/ {s += $(NF - 1); c++} END {if (c) printf "%.0f", s / c; else print 0}' "$1" 2>/dev/null; }

# a screenshot through the compositor of the monitor under test, kept in $OUT
screenshot() { # file name
    asuser timeout 20 grim -o "$MONITOR" "$CLIENTDIR/$1" >/dev/null 2>&1 && cp "$CLIENTDIR/$1" "$OUT/$1"
}
# passes when at least 10% of a screenshot is the test color, trying again for up to N seconds
check_drawn() { # what, file name, seconds to wait for it
    local p start=$SECONDS
    while :; do
        if ! screenshot "$2"; then
            fail "$1: no screenshot from grim"
            return
        fi
        p=$(magenta "$OUT/$2")
        [ "$p" -ge 10 ] || [ $((SECONDS - start)) -ge "${3:-0}" ] && break
        sleep 2
    done
    if [ "$p" -ge 10 ]; then
        pass "$1 ($p% of the screen is the test color${3:+, after $((SECONDS - start)) s})"
    else
        fail "$1: only $p% of the screen is the test color${3:+ after $((SECONDS - start)) s}"
    fi
}

check_config() {
    local out blur
    out=$(H configerrors)
    if [ -z "$(tr -d '[:space:]' <<<"$out")" ]; then pass "config loads without errors"; else fail "config errors: $(head -3 <<<"$out" | tr '\n' ' ')"; fi

    # options are set through eval with a Lua config and through keyword before. Blur is set to the value it
    # has, so the session is left as it was
    blur=$(H getoption decoration:blur:enabled -j | grep -oE '"(bool|int)": *[a-z0-9]+' | grep -oE '[a-z0-9]+$')
    case $blur in 1 | true) blur=true ;; *) blur=false ;; esac
    out=$(H eval "hl.config({decoration={blur={enabled=$blur}}})")
    [ "$out" = ok ] || out=$(H keyword decoration:blur:enabled $blur)
    if [ "$out" = ok ]; then pass "setting an option returns ok"; else fail "setting an option: $out"; fi
    # removed features stay registered as options that do nothing
    out=$(H eval "hl.config({misc={disable_hyprland_logo=true}})")
    [ "$out" = ok ] || out=$(H keyword misc:disable_hyprland_logo true)
    if [ "$out" = ok ]; then pass "setting a removed option returns ok"; else fail "setting a removed option: $out"; fi
}

check_output() {
    MONITOR=$(H monitors | awk '$1 == "Monitor" && $2 != "FALLBACK" {print $2; exit}')
    if [ -z "$MONITOR" ] && [ "$(H output create headless HYPOLAND-CHECK)" = ok ]; then
        # nothing connected: the GPU draws a headless output all the same, it only reaches no screen
        HEADLESS=HYPOLAND-CHECK MONITOR=HYPOLAND-CHECK
        sleep 4
    fi
    if [ -z "$MONITOR" ]; then
        fail "no monitor and no headless output to draw on"
        return 1
    fi
    pass "output $MONITOR: $(H monitors | awk -v m="$MONITOR" '$1 == "Monitor" {on = $2 == m} on && /@/ {print $1; exit}')${HEADLESS:+, headless}"
    if H monitors | grep -q "solitaryBlockedBy:.*lock"; then
        # the lock screen covers every window, and only the password or a new session ends it
        fail "the session is locked, nothing else was checked (systemctl restart sddm as root gives a new session)"
        return 1
    fi
    pass "no lock screen in the way"
    info "$(H layers | grep -c 'namespace:') layer surfaces (bar, wallpaper, notifications)"
}

check_window() {
    local before p
    if [ -n "$(missing foot)" ]; then
        skip "test window: foot is not installed"
        return
    fi
    cp "$CLIENTSRC/magenta.sh" "$CLIENTDIR/"
    before=$(nclients)
    client 60 "exec foot sh $CLIENTDIR/magenta.sh"
    if ! mapped "$before" 10; then
        fail "test window (foot) did not map"
        stop_clients
        return
    fi
    pass "test window mapped"
    sleep 2
    # A screenshot makes the compositor draw through its work buffer for a while, so the buffer the screen scans
    # out is read first: it shows whether drawing straight into it works. Root only, and only unambiguous with
    # one monitor.
    if [ -n "$HEADLESS" ] || [ $ROOT = 0 ] || ! command -v hypoland-kmsgrab >/dev/null ||
        [ "$(H monitors | grep -c '^Monitor ')" != 1 ]; then
        skip "scanned-out buffer (needs root, hypoland-kmsgrab and one real monitor)"
    elif hypoland-kmsgrab "$OUT/scanout.ppm" >/dev/null 2>&1 && magick "$OUT/scanout.ppm" "$OUT/scanout.png" 2>/dev/null; then
        rm -f "$OUT/scanout.ppm"
        p=$(magenta "$OUT/scanout.png")
        if [ "$p" -ge 10 ]; then pass "the screen shows the window ($p% of the scanned-out buffer is the test color)"; else fail "the screen does not show the window: $p% of the scanned-out buffer is the test color"; fi
    else
        fail "hypoland-kmsgrab could not read the scanned-out buffer"
    fi
    check_drawn "test window drawn" window.png
    stop_clients
}

check_chromium() {
    local before page="data:text/html,<body style='background:%23ff00ff'>"
    if [ -n "$(missing chromium)" ]; then
        skip "Chromium is not installed"
        return
    fi
    before=$(nclients)
    client 90 "exec chromium --ozone-platform=wayland --no-first-run --user-data-dir=$CLIENTDIR/chromium \"$page\""
    # Its first frame can take long (5 to 30 s on lianli, r600, with the fresh profile), and until then the window
    # shows a buffer it has not drawn yet
    if mapped "$before" 40; then
        check_drawn "Chromium draws its page" chromium.png 60
    else
        fail "Chromium did not map a window"
    fi
    stop_clients
    sleep 1
}

# a window of each toolkit, drawn on the screen and getting its frames
check_toolkits() {
    local tk what needs lacking before log fps
    for tk in gtk3 gtk4 gtk3-x11 qt-quick qt-software; do
        what="$(toolkit_name $tk) window"
        needs=needs_${tk//-/_}_scroll
        lacking=$(missing "${!needs}")
        if [ -n "$lacking" ]; then
            skip "$what: $lacking is not installed"
            continue
        fi
        if [ $tk = gtk3-x11 ] && ! xwayland_up; then
            fail "$what: Xwayland does not answer on $(xdisplay)"
            continue
        fi
        log=$CLIENTDIR/check-$tk.log
        before=$(nclients)
        client 40 "$(toolkit $tk check) >$log 2>&1"
        if ! mapped "$before" 15; then
            fail "$what did not map: $(tail -n 1 "$log" 2>/dev/null)"
            stop_clients
            continue
        fi
        # a window can open with an animation (Omarchy fades it in), and a screenshot during it sees a window that
        # is not opaque yet. The Qt software window maps within 0.1 s, before the first look for it
        sleep 1
        check_drawn "$what drawn" "$tk.png" 10
        # the client reports its frame rate 5 s after its first frame
        for _ in $(seq 1 10); do
            grep -q "frames in" "$log" && break
            sleep 1
        done
        fps=$(fps_of "$log")
        if [ "$fps" -ge 20 ]; then pass "$what at $fps fps (renderer $(renderer_of "$log"))"; else fail "$what at $fps fps (renderer $(renderer_of "$log"))"; fi
        stop_clients
        sleep 1
    done
}

check_clients() {
    local fps display
    if [ -n "$(missing weston-simple-egl)" ]; then
        skip "GPU client: weston-simple-egl is not installed"
    else
        client 15 "exec stdbuf -oL weston-simple-egl >$CLIENTDIR/egl.log 2>&1"
        sleep 12
        stop_clients
        fps=$(fps_of "$CLIENTDIR/egl.log")
        if [ "$fps" -ge 20 ]; then pass "GPU client (weston-simple-egl) at $fps fps"; else fail "GPU client (weston-simple-egl) at $fps fps"; fi
    fi

    display=$(xdisplay)
    if [ -n "$(missing "glxgears xprop")" ]; then
        skip "X11 client: $(missing "glxgears xprop") is not installed"
    elif [ -z "$display" ]; then
        skip "X11 client: no DISPLAY in the environment of the session"
    elif ! xwayland_up; then
        fail "X11 client: Xwayland does not answer on $display"
    else
        client 15 "exec env DISPLAY=$display stdbuf -oL glxgears >$CLIENTDIR/gears.log 2>&1"
        sleep 12
        stop_clients
        fps=$(fps_of "$CLIENTDIR/gears.log")
        if [ "$fps" -ge 20 ]; then pass "X11 client through Xwayland (glxgears) at $fps fps"; else fail "X11 client through Xwayland (glxgears) at $fps fps"; fi
    fi
}

check_logs() {
    local since=$1 n
    n=$( (asuser journalctl --user _PID=$P -o cat 2>/dev/null; cat "$RUNTIME/hypr/$SIG/hyprland.log" 2>/dev/null) |
        grep -ciE "GL_INVALID|GLES error|shader.*fail|Failed to (link|compile)")
    if [ "$n" = 0 ]; then pass "no GL or shader errors in the compositor's log"; else fail "$n GL or shader error lines in the compositor's log"; fi
    n=$(find "$USERHOME/.cache/hyprland" -type f -newermt "@$since" 2>/dev/null | wc -l)
    if [ "$n" = 0 ]; then pass "no new crash reports"; else fail "$n new crash reports in $USERHOME/.cache/hyprland"; fi
    if [ $ROOT = 1 ] && command -v coredumpctl >/dev/null; then
        n=$(coredumpctl list --no-legend --no-pager --since "@$since" 2>/dev/null | awk '{print $NF}' | sort | uniq -c | awk '{printf "%s %sx, ", $2, $1}')
        if [ -z "$n" ]; then pass "no core dumps"; else info "core dumps since the compositor started: ${n%, }"; fi
    fi
    if pgrep -x "$PROCESS" | grep -qx "$P"; then pass "the compositor ran through without a restart"; else fail "the compositor restarted or died"; fi
}

checks() {
    local since
    # a session that was just started needs a moment for its shell and autostart
    [ "$(ps -o etimes= -p $P)" -lt 20 ] && sleep $((20 - $(ps -o etimes= -p $P)))
    since=$(($(date +%s) - $(ps -o etimes= -p $P)))
    if ! H version >/dev/null 2>&1; then
        fail "hyprctl does not answer"
        return
    fi
    pass "compositor running, hyprctl responds"
    info "$(H version | head -1 | sed 's/ (.*//')"
    info "$(H version | grep -m1 '^Hypoland')"
    check_config
    check_output || return
    check_window
    check_chromium
    check_toolkits
    check_clients
    info "compositor memory: $(awk '/^(Rss|Pss|Anonymous):/ {printf "%s %d MiB, ", $1, $2 / 1024}' /proc/$P/smaps_rollup | sed 's/, $//')"
    check_logs "$since"
}
