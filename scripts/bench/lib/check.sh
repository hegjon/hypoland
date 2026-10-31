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
    # a check while Omarchy's startup cover is up sees a black screen (the Chromebook's first check after its update of
    # 2026-10-30, every pixel of the screenshot and the scanout black, a minute before the same check passed)
    local waited=0
    while startup_cover && [ $waited -lt 60 ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if startup_cover; then
        fail "Omarchy's startup cover is still up after 60 s"
    elif [ $waited -gt 0 ]; then
        info "waited $waited s for Omarchy's startup cover to go"
    fi
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

# The screen shows what it should (clients/render.py, root, added 2026-10-31): two shm windows of its own, drawn in
# blocks it knows pixel by pixel, through a whole buffer, small damaged rectangles, new buffers further on in the pool,
# a window with a transparent band floating over the other, moved and closed. At every step the focused window has to
# show exactly what it drew (an integer scale only), and the screen has to be what a full repaint of the same scene
# shows (the shell frozen, the workspace switched away and back): a pixel left stale or drawn wrong by the damage
# tracking, the merged uploads, the clipped layers or a read in place fails it. The screen is read from the scanned-out
# buffer where hypoland-kmsgrab can, through the compositor (grim) where it cannot. Screens that differ are kept
check_render() {
    local grab=kmsgrab line out=$CLIENTDIR/render.txt
    if [ $ROOT = 0 ]; then
        skip "render checks (they freeze the shell and read the screen, root only)"
        return
    fi
    if [ -n "$HEADLESS" ] || ! command -v hypoland-kmsgrab >/dev/null || [ "$(H monitors | grep -c '^Monitor')" != 1 ]; then
        grab=grim
    fi
    env -i PATH="$PATH" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" timeout 180 python3 -I "$CLIENTSRC/render.py" \
        --socket "$RUNTIME/hypr/$SIG/.socket.sock" --out "$CLIENTDIR/render" --grab $grab >"$out" 2>&1
    grep -q "^\(PASS\|FAIL\|SKIP\)" "$out" || fail "render checks did not run: $(tail -n 1 "$out")"
    grep -q "reading the screen through the compositor" "$out" && grab=grim
    while read -r line; do
        case $line in
            PASS*) pass "${line#PASS  } ($grab)" ;;
            FAIL*) fail "${line#FAIL  }" ;;
            SKIP*) skip "${line#SKIP  }" ;;
            INFO*) info "${line#INFO  }" ;;
        esac
    done <"$out"
    for line in "$CLIENTDIR"/render/*.ppm; do
        [ -e "$line" ] && magick "$line" "$OUT/render-$(basename "${line%.ppm}" | tr ' ' '-').png" 2>/dev/null
    done
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

# the box of a color in an image, "W H X Y" in its pixels; nothing when less than 0.1% of the image has the color
color_box() { # file, color
    local mask=$CLIENTDIR/mask.png
    magick "$1" -alpha off -fuzz 12% -fill black +opaque "$2" -fill white -opaque "$2" "$mask" 2>/dev/null || return
    [ "$(magick "$mask" -format '%[fx:mean*1000>=1]' info: 2>/dev/null)" = 1 ] || return
    magick "$mask" -format '%@' info: 2>/dev/null | awk -F'[x+]' '{print $1, $2, $3, $4}'
}

# Whether what a client put at X11 coordinates shows there: the window's box on the screen ("W H X Y", pixels of the
# screenshot), the window in X11 ("X Y W H", pixels of Xwayland), and the same two of the item. The ratio of the two
# kinds of pixels is the window's width on the screen over its width in X11 (1 at scale 1 and with Xwayland's zero
# scaling). Prints yes or no and how far off the item is (x y w h, screen pixels); within 2% of the window's width and
# 4 pixels counts
placed() { # window on the screen, window in X11, item on the screen, item in X11
    awk -v a="$1" -v b="$2" -v c="$3" -v d="$4" 'BEGIN {
        split(a, ws, " "); split(b, wx, " "); split(c, is, " "); split(d, ix, " ")
        s = ws[1] / wx[3]; tol = ws[1] * 0.02 + 4
        dx = is[3] - ws[3] - (ix[1] - wx[1]) * s; dy = is[4] - ws[4] - (ix[2] - wx[2]) * s
        dw = is[1] - ix[3] * s; dh = is[2] - ix[4] * s
        ok = dx * dx <= tol * tol && dy * dy <= tol * tol && dw * dw <= tol * tol && dh * dh <= tol * tol
        printf "%s %+.0f %+.0f %+.0f %+.0f", ok ? "yes" : "no", dx, dy, dw, dh
    }'
}

# waits until a client's log has a line starting with a word, and prints it
await_line() { # log, word, seconds
    for _ in $(seq 1 $(($3 * 5))); do
        grep -m1 "^$2 " "$1" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

# the window with a title as the compositor has it: "X Y W H floating" in its logical coordinates
window_by_title() { # title
    H clients -j | python3 -I -c 'import json, sys
for c in json.load(sys.stdin):
    if c["title"] == sys.argv[1]:
        print(*c["at"], *c["size"], int(c["floating"]))
        break' "$1" 2>/dev/null
}

# Tk draws only through X11 (clients/toolkit-tk.py, mode menu): its window through Xwayland, drawn; a menu, an X11
# window the window manager does not manage (override-redirect), where Tk put it on the window and above it; and a
# dialog that belongs to the window, floating and whole over it. The client takes each step when a file appears in the
# clients' directory, and prints where it put things in X11
check_tk() {
    local log=$CLIENTDIR/check-tk.log before line win wbox box r dialog parent
    if [ -n "$(missing "$needs_tk_canvas")" ]; then
        skip "Tk window: $(missing "$needs_tk_canvas") is not installed"
        return
    fi
    if ! xwayland_up; then
        fail "Tk window: Xwayland does not answer on $(xdisplay)"
        return
    fi
    rm -f "$CLIENTDIR/tk-menu" "$CLIENTDIR/tk-dialog"
    before=$(nclients)
    client 60 "$(toolkit tk menu) >$log 2>&1"
    if ! mapped "$before" 15; then
        fail "Tk window did not map: $(tail -n 1 "$log" 2>/dev/null)"
        stop_clients
        return
    fi
    sleep 1
    check_drawn "Tk window (Xwayland) drawn" tk.png 10
    if ! line=$(await_line "$log" window 10); then
        fail "Tk window: it did not stay at one place ($(tail -n 1 "$log" 2>/dev/null))"
        stop_clients
        return
    fi
    win=${line#window }

    touch "$CLIENTDIR/tk-menu"
    if ! line=$(await_line "$log" menu 10); then
        fail "Tk menu: not posted ($(tail -n 1 "$log" 2>/dev/null))"
        stop_clients
        return
    fi
    sleep 1
    if ! screenshot tk-menu.png; then
        fail "Tk menu: no screenshot from grim"
    else
        wbox=$(color_box "$OUT/tk-menu.png" "#ff00ff")
        box=$(color_box "$OUT/tk-menu.png" "#00ff00")
        if [ -z "$wbox" ]; then
            fail "Tk menu: the window is not on the screen"
        elif [ -z "$box" ]; then
            fail "Tk menu: not on the screen (under the window, or not drawn)"
        else
            r=$(placed "$wbox" "$win" "$box" "${line#menu }")
            if [ "${r%% *}" = yes ]; then pass "Tk menu above its window, where Tk put it"; else fail "Tk menu: off by ${r#* } pixels (x y w h) from where Tk put it"; fi
        fi
    fi

    touch "$CLIENTDIR/tk-dialog"
    line=$(await_line "$log" dialog 10)
    for _ in $(seq 1 25); do
        dialog=$(window_by_title "Hypoland Tk dialog")
        [ -n "$dialog" ] && break
        sleep 0.2
    done
    if [ -z "$line" ] || [ -z "$dialog" ]; then
        fail "Tk dialog did not map ($(tail -n 1 "$log" 2>/dev/null))"
        stop_clients
        return
    fi
    # Omarchy animates a window in
    sleep 1.5
    parent=$(window_by_title "Hypoland Tk test")
    # floating, with its middle on the window it belongs to
    r=$(awk -v d="$dialog" -v p="$parent" 'BEGIN {
        split(d, a, " "); split(p, b, " "); x = a[1] + a[3] / 2; y = a[2] + a[4] / 2
        print (a[5] == 1 && x > b[1] && x < b[1] + b[3] && y > b[2] && y < b[2] + b[4]) ? "yes" : "no" }')
    if [ "$r" = yes ]; then pass "Tk dialog floats over its window"; else fail "Tk dialog: at ${dialog% *}, floating ${dialog##* }, its window at ${parent% *}"; fi
    if ! screenshot tk-dialog.png; then
        fail "Tk dialog: no screenshot from grim"
    else
        wbox=$(color_box "$OUT/tk-dialog.png" "#ff00ff")
        box=$(color_box "$OUT/tk-dialog.png" "#00ffff")
        if [ -z "$wbox" ]; then
            fail "Tk dialog: its window is not on the screen"
        elif [ -z "$box" ]; then
            fail "Tk dialog: not on the screen (under its window, or not drawn)"
        else
            # whole: as large on the screen as Tk made it, in the scale of its window
            r=$(awk -v w="$wbox" -v x="$win" -v b="$box" -v d="${line#dialog }" 'BEGIN {
                split(w, ws, " "); split(x, wx, " "); split(b, bs, " "); split(d, ds, " ")
                s = ws[1] / wx[3]; tol = ws[1] * 0.02 + 4; dw = bs[1] - ds[1] * s; dh = bs[2] - ds[2] * s
                printf "%s %+.0f %+.0f", dw * dw <= tol * tol && dh * dh <= tol * tol ? "yes" : "no", dw, dh }')
            if [ "${r%% *}" = yes ]; then pass "Tk dialog shown whole"; else fail "Tk dialog: off by ${r#* } pixels (w h) from the size Tk gave it"; fi
        fi
    fi
    stop_clients
    sleep 1
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
    check_render
    check_chromium
    check_toolkits
    check_tk
    check_clients
    info "compositor memory: $(awk '/^(Rss|Pss|Anonymous):/ {printf "%s %d MiB, ", $1, $2 / 1024}' /proc/$P/smaps_rollup | sed 's/, $//')"
    check_logs "$since"
}
