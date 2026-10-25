# shellcheck shell=bash
# Part of measure.sh: the workloads. needs_<name> lists the programs a workload starts, workload_<name> runs it;
# the programs they start as clients are in clients/ next to the script.

needs_idle=""
workload_idle() {
    sleep 2
    rec idle
}

needs_gpu_client="weston-simple-egl"
workload_gpu_client() {
    local log=$CLIENTDIR/fps.log
    rm -f "$log"
    client $((SECONDS_PER_RUN + 10)) "exec stdbuf -oL weston-simple-egl >$log 2>&1"
    sleep 4
    rec gpu-client
    stop_clients
    # a lower CPU time only counts when the client still gets its frames
    [ "$MODE" != perf ] && value "fps.gpu-client" "$(fps_mean "$log")"
}

# the mean of the frame rates a client printed like weston-simple-egl ("... frames in 5 seconds: 60.0 fps"), after
# its first N reports
fps_mean() { # log, N
    awk -v skip="${2:-0}" '/frames in/ && ++n > skip {s += $(NF - 1); c++} END {if (c) printf "%.1f", s / c; else print "nan"}' "$1" 2>/dev/null
}

needs_terminal_scroll="foot"
workload_terminal_scroll() {
    client $((SECONDS_PER_RUN + 10)) "exec foot -e sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec terminal-scroll
    stop_clients
}

needs_alacritty_scroll="alacritty"
workload_alacritty_scroll() { # the same scrolling in a terminal that draws with GL instead of shm
    client $((SECONDS_PER_RUN + 10)) "exec alacritty -e sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec alacritty-scroll
    stop_clients
}

# A 20 s 720p H.264 clip, encoded once into the user's cache. Decoded in software unless the user's mpv config
# says otherwise, as Omarchy's does not.
VIDEO=$USERHOME/.cache/hypoland-bench/video.mp4
video_workload() { # workload, mpv options. The clip loops: a 30 fps client buffer
    [ -s "$VIDEO" ] || asuser sh -c 'mkdir -p "${0%/*}" && ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 \
        -t 20 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$0"' "$VIDEO"
    client $((SECONDS_PER_RUN + 10)) "exec mpv $2 --loop-file=inf --no-audio --really-quiet '$VIDEO'"
    sleep 4
    rec "$1"
    stop_clients
}

needs_video="mpv ffmpeg"
workload_video() { video_workload video --fs; } # fullscreen, where the buffer can be scanned out directly

needs_video_window="mpv ffmpeg"
workload_video_window() { video_workload video-window; } # in a tiled window, every frame is composited

needs_nautilus="nautilus"
workload_nautilus() { # GTK 4 redrawing a full window of icons, fullscreen toggled twice a second
    local i
    client $((SECONDS_PER_RUN + 15)) "exec nautilus --new-window /usr/share/icons/Adwaita/symbolic/actions"
    sleep 5
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do
        dispatch 'hl.dsp.window.fullscreen({action="toggle"})' "fullscreen"; sleep 0.5
    done) &
    local toggler=$!
    rec nautilus
    wait $toggler
    stop_clients
    # a nautilus that was already running opens the window itself, quitting closes it too
    asuser nautilus -q >/dev/null 2>&1
}

# 25000 empty files, made once in the user's cache, so the listing is the same on every machine and run (the same
# directory as scripts/x200/soak.sh)
FILES=$USERHOME/.cache/hypoland-bench/files-25000
needs_flea="flea"
workload_flea() { # Omarchy's file manager, a Quickshell window, paged through with keys
    local i key
    [ -e "$FILES/file-25000.txt" ] || asuser bash -c 'mkdir -p "$0" && cd "$0" && touch file-{00001..25000}.txt' "$FILES"
    client $((SECONDS_PER_RUN + 20)) "exec flea '$FILES'"
    sleep 8
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do # 4 pages a second, 20 down and 20 back up
        key=Page_Down
        [ $(((i - 1) / 5 % 2)) = 1 ] && key=Page_Up
        for _ in 1 2 3 4; do
            dispatch "hl.dsp.send_shortcut({mods=\"\", key=\"$key\"})" "sendshortcut ,$key,"
            sleep 0.25
        done
    done) &
    local pager=$!
    rec flea
    wait $pager
    stop_clients
    # flea execs qs and leaves a backend; the bracket keeps pkill from matching its own command line
    asuser pkill -f "[q]s -p /usr/share/flea" >/dev/null 2>&1
    asuser pkill -x flea >/dev/null 2>&1
    sleep 1
}

needs_shm_fullwindow="chromium"
workload_shm_fullwindow() {
    local page="data:text/html,<body style='background:linear-gradient(90deg,red,blue)'><marquee scrollamount=20 style='font:60px sans-serif;color:white'>Hypoland</marquee><div style='animation:s 2s linear infinite;width:200px;height:200px;background:lime'></div><style>@keyframes s{to{transform:translateX(900px) rotate(360deg)}}</style>"
    client $((SECONDS_PER_RUN + 40)) "exec chromium --ozone-platform=wayland --no-first-run --user-data-dir=$CLIENTDIR/chromium \"$page\""
    sleep 24
    rec shm-fullwindow
    stop_clients
    sleep 1
}

needs_workspace_switch="foot"
workload_workspace_switch() {
    local i
    for i in 1 2 3; do
        client $((SECONDS_PER_RUN + 15)) "exec foot -e sleep 60"
        sleep 1
    done
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do
        dispatch "hl.dsp.focus({workspace=2})" "workspace 2"; sleep 0.5
        dispatch "hl.dsp.focus({workspace=1})" "workspace 1"; sleep 0.5
    done) &
    local switcher=$!
    rec workspace-switch
    wait $switcher
    stop_clients
}

# ---- toolkits: test windows in GTK 3, GTK 4 and Qt Quick, for the workloads and the checks

# A toolkit window shows a long text. By default it scrolls the text at 400 pixels per second, a full window of
# damage on every frame. "spinner" (GTK) keeps the text still under a spinning spinner, a small damage region;
# "sprites" (Qt) moves 60 small squares over it, many small regions. "check" scrolls on the test color. The window
# prints the renderer the toolkit picked and its frame rate like weston-simple-egl.
# GTK 3 draws with cairo into shm buffers, through Xwayland as well. GTK 4 picks its renderer itself: cairo, also
# into shm buffers, where it finds neither GLES 3 nor Vulkan (the X200). Qt Quick draws with GL, its software
# backend into shm buffers like Qt Widgets, and only redraws what changed. Qt logs to the journal when the session
# has one, QT_FORCE_STDERR_LOGGING brings the frame rate to the log.
toolkit() { # gtk3|gtk4|gtk3-x11|qt-quick|qt-software, [check|spinner|sprites]
    [ -s "$CLIENTDIR/toolkit.qml" ] || toolkit_sources
    case $1 in
        gtk3 | gtk4) echo "exec env GDK_BACKEND=wayland python3 -I $CLIENTDIR/toolkit.py ${1#gtk}.0 $2" ;;
        gtk3-x11) echo "exec env GDK_BACKEND=x11 DISPLAY=$(xdisplay) python3 -I $CLIENTDIR/toolkit.py 3.0 $2" ;;
        qt-quick) echo "exec env QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 qml6 $CLIENTDIR/toolkit.qml -- $2" ;;
        qt-software) echo "exec env QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 QT_QUICK_BACKEND=software qml6 $CLIENTDIR/toolkit.qml -- $2" ;;
    esac
}

toolkit_name() { # gtk3|gtk4|gtk3-x11|qt-quick|qt-software
    case $1 in
        gtk3) echo "GTK 3" ;;
        gtk4) echo "GTK 4" ;;
        gtk3-x11) echo "GTK 3 (Xwayland)" ;;
        qt-quick) echo "Qt Quick" ;;
        qt-software) echo "Qt Quick (software)" ;;
    esac
}

renderer_of() { sed -n 's/.*renderer: //p' "$1" 2>/dev/null | head -n 1; } # log

# Xwayland starts with the first X11 client; its display is in the environment of the session
xdisplay() { asuser systemctl --user show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p'; }

toolkit_sources() {
    cp "$CLIENTSRC/toolkit.py" "$CLIENTSRC/toolkit.qml" "$CLIENTDIR/"
}

toolkit_workload() { # workload, client, mode
    local log=$CLIENTDIR/$1.log warmup
    rm -f "$log"
    client $((SECONDS_PER_RUN + 10)) "$(toolkit "$2" "$3") >$log 2>&1"
    sleep 5
    # what the client reported while it started is not measured
    warmup=$(grep -c "frames in" "$log" 2>/dev/null)
    rec "$1"
    stop_clients
    echo "    $(toolkit_name "$2"), renderer $(renderer_of "$log")"
    [ "$MODE" != perf ] && value "fps.$1" "$(fps_mean "$log" "$warmup")"
}

needs_gtk3_scroll="python3 gi:Gtk-3.0"
workload_gtk3_scroll() { toolkit_workload gtk3-scroll gtk3; }

needs_gtk4_scroll="python3 gi:Gtk-4.0"
workload_gtk4_scroll() { toolkit_workload gtk4-scroll gtk4; }

needs_qt_quick_scroll="qml6"
workload_qt_quick_scroll() { toolkit_workload qt-quick-scroll qt-quick; }

needs_qt_software_scroll="qml6"
workload_qt_software_scroll() { toolkit_workload qt-software-scroll qt-software; }

# The same GTK 3 window as an X11 client, drawn through Xwayland. It gets no frame callbacks, so its frame rate is
# its own pace, not what the compositor presents
needs_gtk3_x11_scroll="python3 gi:Gtk-3.0 x11"
workload_gtk3_x11_scroll() { toolkit_workload gtk3-x11-scroll gtk3-x11; }

needs_gtk4_spinner="python3 gi:Gtk-4.0"
workload_gtk4_spinner() { toolkit_workload gtk4-spinner gtk4 spinner; }

needs_qt_software_sprites="qml6"
workload_qt_software_sprites() { toolkit_workload qt-software-sprites qt-software sprites; }

# Three terminals that print for 4 s and then wait: the memory idle shm windows keep in the compositor, measured while
# they are open (mem.idle-windows.*). A window that never drew again after its last resize has no second texture to
# give back, see CGLTexture::update(); real windows mostly have (typing, a page that loads)
needs_idle_windows="foot"
workload_idle_windows() {
    local i total purgeable before after
    # what the kernel cannot take back: Mesa keeps freed buffers in its cache, purgeable
    read -r total _ purgeable < <(gpu_memory)
    before=$((total - purgeable))
    for i in 1 2 3; do
        client $((SECONDS_PER_RUN + 25)) "exec foot -e sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do ls -la /usr/lib | head -n 8; sleep 0.4; done; exec sleep 600'"
        sleep 1
    done
    sleep 4
    rec idle-windows
    memory idle-windows
    # what the windows hold. Only meaningful as the first workload of a fresh session: buffers an earlier workload
    # left behind are freed meanwhile. radeon reports no memory in fdinfo, it reads 0 there
    read -r total _ purgeable < <(gpu_memory)
    after=$((total - purgeable))
    value "mem.idle-windows.gpu_added_kB" "$((after - before))"
    stop_clients
}

# A developer's screen as dwindle tiles it: an editor on the left half, on the right a console above a terminal
# that keeps changing. All three are Alacritty, which draws with GL (terminal-scroll and idle-windows have foot's
# shm). The editor is nvim without the user's config (Omarchy's LazyVim would set itself up on a first start) on a
# generated C file of 210000 lines, the console a shell in a generated git repository whose commits add 3000 lines
# each, with 9000 lines changed and not committed. They are the same on every machine and generated again when the
# generator changes.
DEV=$USERHOME/.cache/hypoland-bench/dev
dev_sources() {
    # the generator of the files, the editor's movements, the console's shell with its pager, the log and the driver
    cp "$CLIENTSRC/dev-gen.sh" "$CLIENTSRC/dev-move.lua" "$CLIENTSRC/dev-shellrc" "$CLIENTSRC/dev-log.py" \
        "$CLIENTSRC/dev-pager.py" "$CLIENTSRC/dev.py" "$CLIENTDIR/"
    if [ "$(cat "$DEV/generator" 2>/dev/null)" != "$(md5sum <"$CLIENTDIR/dev-gen.sh")" ]; then
        asuser bash "$CLIENTDIR/dev-gen.sh" "$DEV" >/dev/null 2>&1 &&
            asuser sh -c 'md5sum <"$0" >"$1"' "$CLIENTDIR/dev-gen.sh" "$DEV/generator"
    fi
}

dev_windows() { # editor, console, lower right terminal: the commands they run
    local xy before
    # each window has to be there before the next one splits it
    before=$(nclients)
    client $((SECONDS_PER_RUN + 150)) "exec alacritty --class hypoland-dev-editor -e $1"
    mapped "$before" 10
    before=$(nclients)
    client $((SECONDS_PER_RUN + 150)) "exec env DEV_REPO='$DEV/repo' DEV_SHELLRC=$CLIENTDIR/dev-shellrc DEV_PAGER=$CLIENTDIR/dev-pager.py alacritty --class hypoland-dev-console -e $2"
    mapped "$before" 10
    # dwindle splits the window under the pointer, which has to be the console on the right
    xy=$(H monitors | awk '/^Monitor/ {m = 1} m && / at / {split($1, r, "[x@]"); split($3, p, "x")} m && /scale:/ {s = $2}
        m && /focused: yes/ {printf "%d %d", p[1] + r[1] / s * 3 / 4, p[2] + r[2] / s / 2; exit}')
    dispatch "hl.dsp.cursor.move({x=${xy% *}, y=${xy#* }})" "movecursor $xy"
    before=$(nclients)
    client $((SECONDS_PER_RUN + 150)) "exec alacritty --class hypoland-dev-lower -e $3"
    mapped "$before" 10
    sleep 4
}

focus() { # class
    local address
    address=$(window_address "$1")
    dispatch "hl.dsp.focus({window=\"address:$address\"})" "focuswindow address:$address"
}

# The developer's screen driven by a uinput keyboard (root only) through dev.py, first under load and then key by
# key. Load: every 3 s the focus moves (SUPER+Left, SUPER+Right, the binds of Omarchy) between the editor, which
# scrolls a line 40 times a second and jumps every 2 s while it has the focus, and the console, which gets a command
# typed into it: every other time a diff of 9000 lines paged through, in between ls, git status or a commit of 3000
# lines. Below the console a busy log that never has the focus. The CPU time of the compositor is measured over it
# (cpu.dev.*). Then the editor stops scrolling by itself, and dev.py waits for every key until the frame that shows
# it: moving to the editor and back, scrolling (Ctrl-D, Ctrl-U), jumping to a line (<line>G), typing a command.
# Medians and 90th percentiles in ms (latency.dev.*). Screencopy takes the compositor off direct rendering while it
# captures, which is why the CPU time is measured before.
needs_dev="alacritty nvim git python3 root"
workload_dev() {
    local driver border kind line median p90 n timeouts i
    # the keys would go into the password field of a lock screen
    if [ -n "$(in_the_way)" ]; then
        echo "--- dev: not measured,$(in_the_way)"
        value "invalid.dev" 1
        return
    fi
    dev_sources
    rm -f "$CLIENTDIR/dev-quiet" "$OUT/dev.txt"
    dev_windows "env DEV_QUIET=$CLIENTDIR/dev-quiet nvim --clean -R -n -i NONE -S $CLIENTDIR/dev-move.lua +200 '$DEV/a.c'" \
        "bash --rcfile $CLIENTDIR/dev-shellrc -i" "python3 -I -u $CLIENTDIR/dev-log.py"
    focus hypoland-dev-console
    sleep 1
    H clients -j >"$OUT/dev.clients.json"
    H monitors -j >"$OUT/dev.monitors.json"
    border=$(H getoption general:border_size | awk '/^int:/ {print $2}')
    env -i PATH="$PATH" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" python3 -I "$CLIENTDIR/dev.py" \
        --clients "$OUT/dev.clients.json" --monitors "$OUT/dev.monitors.json" --editor hypoland-dev-editor \
        --console hypoland-dev-console --border "${border:-2}" --load "$SECONDS_PER_RUN" --quiet "$CLIENTDIR/dev-quiet" \
        >"$OUT/dev.txt" 2>&1 &
    driver=$!
    # the keyboard is there after 2 s
    for i in $(seq 1 50); do
        grep -q "^load" "$OUT/dev.txt" && break
        sleep 0.2
    done
    rec dev
    wait "$driver"
    [ -n "$(in_the_way)" ] && value "invalid.dev" 1
    stop_clients
    grep -v -E "^(load|latency)" "$OUT/dev.txt" | sed 's/^/    /'
    for kind in focus scroll jump type; do
        timeouts=$(grep -c "^latency $kind timeout" "$OUT/dev.txt")
        [ "$timeouts" -gt 0 ] && value "latency.dev.${kind}_timeouts" "$timeouts"
        line=$(awk -v k=$kind '$1 == "latency" && $2 == k && $3 != "timeout" {print $3}' "$OUT/dev.txt" | sort -g | awk '
            {v[NR] = $1} END {if (NR) printf "%s %s %d", v[int((NR + 1) / 2)], v[int(NR * 0.9 + 0.99)], NR}')
        if [ -z "$line" ]; then
            echo "    $kind: nothing changed on the screen ($timeouts keys)"
            continue
        fi
        read -r median p90 n <<<"$line"
        value "latency.dev.${kind}_ms" "$median"
        value "latency.dev.${kind}_p90_ms" "$p90"
        echo "    $kind: $median ms, 90% within $p90 ms ($n keys, $timeouts timeouts)"
    done
}

# the address of the window of a class, for the window selectors of the dispatchers
window_address() { H clients | awk -v c="$1" '/^Window / {a = $2} $1 == "class:" && $2 == c {print "0x" a; exit}'; }

# a client given with --client
workload_custom() { # name, command
    client $((SECONDS_PER_RUN + 10)) "$2"
    sleep 4
    rec "$1"
    stop_clients
}

missing() { # programs, gi:<namespace>-<version> for a library Python reaches through GObject introspection, x11 for Xwayland, root
    local prog lib
    for prog in $1; do
        if [ "$prog" = x11 ]; then
            [ -n "$(xdisplay)" ] || { echo "Xwayland"; return; }
            continue
        fi
        if [ "$prog" = root ]; then
            [ $ROOT = 1 ] || { echo "root (for a uinput keyboard)"; return; }
            continue
        fi
        if [[ $prog == gi:* ]]; then
            lib=${prog#gi:}
            asuser python3 -I -c "import gi; gi.require_version('${lib%-*}', '${lib##*-}')" >/dev/null 2>&1 ||
                { echo "${lib%-*} ${lib##*-} for Python (python-gobject)"; return; }
            continue
        fi
        asuser sh -c "command -v $prog" >/dev/null 2>&1 || { echo "$prog"; return; }
    done
}

# The power of the idle session, sampled between the workloads. A workload's net power is its power minus the
# mean of the baselines before and after it, half their difference is how far off that mean can be.
PENDING="" BEFORE=""
baseline() {
    if [ "$METER" = none ]; then
        sleep 1
        return
    fi
    sleep 2
    battery_check
    local m0 m1 w name gross ms
    m0=$(mark)
    sleep "$IDLE"
    m1=$(mark)
    w=$(watts "$m0" "$m1")
    value power.baseline.W "$w"
    if [ -n "$PENDING" ] && [ -n "$BEFORE" ]; then
        read -r name gross ms <<<"$PENDING"
        awk -v r=$ROUND -v n="$name" -v g="$gross" -v a="$BEFORE" -v b="$w" -v s="$ms" 'BEGIN {
            net = g - (a + b) / 2
            pm = (a > b ? a - b : b - a) / 2
            printf "@ %s power.%s.net_W %.3f\n@ %s power.%s.pm_W %.3f\n", r, n, net, r, n, pm
            printf "@ %s energy.%s.net_J %.2f\n", r, n, net * s / 1000
            printf "    %.2f W, %.2f W above the idle baseline (+-%.2f W)\n", g, net, pm
        }'
    fi
    PENDING=""
    BEFORE=$w
}

between() {
    if [ "$MODE" = energy ]; then baseline; else sleep 1; fi
}

workloads() {
    local name fn needs lacking i n=0
    [ "$MODE" = energy ] && [ -z "$BEFORE" ] && baseline
    for name in ${WORKLOADS//,/ }; do
        fn=${name//-/_}
        n=$((n + 1))
        if ! declare -F "workload_$fn" >/dev/null || [ "$fn" = custom ]; then
            echo "=== $n $name: no such workload"
            continue
        fi
        needs=needs_$fn
        lacking=$(missing "${!needs}")
        if [ -n "$lacking" ]; then
            echo "=== $n $name: skipped, $lacking is not installed"
            continue
        fi
        echo "=== $n $name"
        "workload_$fn"
        between
    done
    for i in "${!CLIENT_NAMES[@]}"; do
        n=$((n + 1))
        echo "=== $n ${CLIENT_NAMES[$i]}: ${CLIENT_CMDS[$i]}"
        workload_custom "${CLIENT_NAMES[$i]}" "${CLIENT_CMDS[$i]}"
        between
    done
}
