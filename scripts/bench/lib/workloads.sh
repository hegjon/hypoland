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

needs_ghostty_scroll="ghostty"
workload_ghostty_scroll() { # the same in Ghostty: a GTK 4 window with Ghostty's own OpenGL renderer (needs OpenGL 3.3, not the X200)
    client $((SECONDS_PER_RUN + 10)) "exec ghostty -e sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec ghostty-scroll
    stop_clients
}

needs_kitty_scroll="kitty"
workload_kitty_scroll() { # the same in kitty, which draws with OpenGL 3.3 as well (not the X200); it takes the command as arguments
    client $((SECONDS_PER_RUN + 10)) "exec kitty sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec kitty-scroll
    stop_clients
}

needs_velocitty_scroll="velocitty"
workload_velocitty_scroll() { # the same in Velocitty, a terminal for Omarchy that draws on the CPU (shm, like foot); from its release tarball, not packaged
    client $((SECONDS_PER_RUN + 10)) "exec velocitty -e sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec velocitty-scroll
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

# Games, as Phoronix ran them on Omarchy 4.5 against Arch and CachyOS (published 2026-11-06): there Omarchy showed 3 to 6%
# fewer frames in GravityMark and in Xonotic above its lowest effects, and the article named the desktop as a possible
# cause. Fullscreen at the monitor's size without vsync, so the game draws as fast as the GPU lets it and the compositor
# shows the newest frame at each refresh: the game's own frame rate is fps.<workload>, the screen's fps.<workload>.screen.
#
# Xonotic (the xonotic package, 1.1 GB of data) plays its benchmark demo the-big-keybench as fast as it can, as Phoronix's
# test does, at one of its effects presets, as a native Wayland client (SDL 2 through sdl2-compat, which takes Wayland when
# both are there; Phoronix's bundled build does the same). The demo is 35534 frames, minutes on these machines, so it is
# stopped after the window: stopped, the game prints the frames and seconds of the demo so far, which make fps.<workload>.
# The timing starts when loading ends (CL_SignonReply 4, printed with developer 1), the window 3 s later, after the first
# shader compiles. A fresh user directory each time, so no config of the user's applies and nothing is written into the
# package's data; no sound.
XONOTIC_ARGS="-benchmark demos/the-big-keybench -nosound +r_glsl 1 +vid_fullscreen 1 +vid_desktopfullscreen 1 \
+cl_curl_enabled 0 +r_texture_dds_load 1 +cl_playerdetailreduction 0 +developer 1 +cl_allow_uid2name 0"
XONOTIC_RESULT='^[0-9]+ frames [0-9.]+ seconds [0-9.]+ fps'
xonotic_result() { grep -a -m 1 -E "$XONOTIC_RESULT" "$1" 2>/dev/null; } # log
xonotic_workload() { # workload, effects preset: low, high, ultra or ultimate
    local log=$CLIENTDIR/$1.log home=$CLIENTDIR/$1.home result
    # lianli's r600 (ARUBA) locked up under the ultimate preset every time (2026-11-09, five lockups in three sessions, each
    # reset by the driver); the EliteBook's radeon GPU died after lockups, so above low the radeon driver is left out
    if [ "$2" != low ] && readlink /sys/class/drm/card*/device/driver 2>/dev/null | grep -q '/radeon$'; then
        echo "    skipped, the effects above low lock up r600 GPUs (radeon)"
        return
    fi
    rm -rf "$log" "$home"
    asuser mkdir -p "$home"
    client $((SECONDS_PER_RUN + 300)) "exec xonotic-sdl -userdir '$home' $XONOTIC_ARGS +exec effects-$2.cfg >$log 2>&1"
    # loading takes 5 s on the desktop, the slow machines read 1 GB of data first
    if ! await_log "$log" 'CL_SignonReply: 4' 120 running; then
        echo "    Xonotic did not start its demo: $(grep -a -i -m 1 -E 'error|failed' "$log")"
        value "invalid.$1" 1
        stop_clients
        return
    fi
    sleep 3
    rec "$1"
    # a demo that ended inside the window had its last frames and the game's exit measured
    result=$(xonotic_result "$log")
    [ -n "$result" ] && { echo "    the demo ended inside the window"; value "invalid.$1" 1; }
    stop_clients
    await_log "$log" "$XONOTIC_RESULT" 10
    result=$(xonotic_result "$log")
    echo "    Xonotic, effects $2: ${result:-no result}"
    echo "    $(grep -a -m 1 -E '^GL_RENDERER:' "$log")"
    asuser rm -rf "$home"
    [ -n "$result" ] || { value "invalid.$1" 1; return; }
    [ "$MODE" != perf ] && value "fps.$1" "$(awk '{printf "%.1f", $5; exit}' <<<"$result")"
}

needs_xonotic_low="xonotic-sdl"
workload_xonotic_low() { xonotic_workload xonotic-low low; } # Phoronix's one Xonotic win for Omarchy, at more than 1000 fps there

needs_xonotic_high="xonotic-sdl"
workload_xonotic_high() { xonotic_workload xonotic-high high; }

needs_xonotic_ultra="xonotic-sdl"
workload_xonotic_ultra() { xonotic_workload xonotic-ultra ultra; }

needs_xonotic_ultimate="xonotic-sdl"
workload_xonotic_ultimate() { xonotic_workload xonotic-ultimate ultimate; } # Phoronix's largest Xonotic loss, -4.9%

# GravityMark (the AUR package gravitymark, in /opt/gravitymark) flies through 200000 asteroids for 167 s whatever the frame
# rate, an X11 client through Xwayland; OpenGL needs 4.5, so not the X200, Vulkan not r600. It reports nothing when it is
# stopped early, so the window is its benchmark run, from 5 s after its start for 155 s whatever --seconds says, and
# fps.<workload> is its own mean over the run (its "FPS:", what Phoronix reports). fps.<workload>.low is the frame rate at
# the 99th percentile of its frame times after the first 5 s: stutter, such as a frame the compositor held up, shows there
GRAVITYMARK=${GRAVITYMARK:-/opt/gravitymark/bin/GravityMark.x64}
[ -x "$GRAVITYMARK" ] || [ ! -x /opt/gravitymark/bin/GravityMark.arm64 ] || GRAVITYMARK=/opt/gravitymark/bin/GravityMark.arm64
gravitymark_workload() { # workload, renderer options
    local log=$CLIENTDIR/$1.log times=$CLIENTDIR/$1.times result
    rm -f "$log" "$times"
    # its libraries are next to it and it reads ../data.zip
    client 600 "cd '${GRAVITYMARK%/*}' && exec env DISPLAY=$(xdisplay) LD_LIBRARY_PATH=. './${GRAVITYMARK##*/}' -vsync 0 -fps 1 \
        -benchmark 1 -close 1 -fullscreen 1 -times '$times' $2 >$log 2>&1"
    if ! await_log "$log" 'Starting .* Benchmark' 120 running; then
        # its errors come last (E: lines, an X error); a crash leaves only its progress lines
        echo "    skipped, GravityMark did not start: $(grep -a -v -E '^\s*$' "$log" | tail -n 2 | tr '\n' ' ')$(client_running || echo '(it exited)')"
        stop_clients
        return
    fi
    sleep 5
    SECONDS_PER_RUN=155 rec "$1"
    # it closes itself after its result (-close 1), so this waits for the line, not for the client
    await_log "$log" 'FPS: [0-9.]+' 60
    stop_clients
    result=$(sed -n -E 's/.*FPS: ([0-9.]+).*/\1/p' "$log" | head -n 1)
    echo "    GravityMark $2: $(grep -a -m 1 -E ' Device: .*\(' "$log" | sed 's/.*Device: //'), ${result:-no result} fps, score $(sed -n -E 's/.*Score: ([0-9]+).*/\1/p' "$log" | head -n 1)"
    [ -n "$result" ] || { value "invalid.$1" 1; return; }
    [ "$MODE" = perf ] && return
    value "fps.$1" "$result"
    value "fps.$1.low" "$(awk 'NR == 1 {s = $2} $2 >= s + 5 {print $3}' "$times" 2>/dev/null | sort -n | awk '{t[NR] = $1} END {
        i = int(NR * 0.99)
        if (i < 1) i = 1
        if (NR && t[i] > 0) printf "%.1f", 1 / t[i]; else print "nan"}')"
}

needs_gravitymark_gl="$GRAVITYMARK x11 xprop"
workload_gravitymark_gl() { gravitymark_workload gravitymark-gl -opengl; }

needs_gravitymark_vk="$GRAVITYMARK x11 xprop"
workload_gravitymark_vk() { gravitymark_workload gravitymark-vk -vulkan; }

# ElectroBench (github.com/deadbeef7/ElectroBench, built into /opt/electrobench by scripts/machines/electrobench.sh) has
# four scenes of fixed length without vsync, each run by itself here, fullscreen and in a window (every frame composited;
# scenes 2 to 4 tile alone on the workspace, scene 1's window is not resizable and floats), as a native Wayland client (SDL 2 through sdl2-compat, which would take X11
# without SDL_VIDEODRIVER). Scene 1, the guns, needs OpenGL 2.1 (the X200 too) and draws every face of its 110 guns with
# glBegin / glEnd, twice a frame, which keeps Mesa busy on the CPU: about 5 fps on the desktop. Scenes 2 to 4, the ocean,
# the pool and the power lines (4x MSAA), need OpenGL 3.3 core and are the GPU's work; without it they exit, skipped.
# A scene times itself from after its setup (shaders, meshes) for 60 s (the guns) or 45 s and prints its frames' mean,
# fps.<workload>. It puts its frame rate into its window's title after its first second of frames or more, which is
# the sign it draws: the window starts 2 s after that and ends about 5 s before the scene does (the scene printing its
# result before the window ended makes the workload invalid)
ELECTROBENCH=${ELECTROBENCH:-/opt/electrobench/ElectroBench}
EB_RESULT='Benchmark Results - Time : [0-9.]+s, Average FPS : [0-9.]+'
electrobench_drawing() { H -j clients 2>/dev/null | grep -q -E '"title": "ElectroBench[^"]* - FPS : '; }
# the size it asks for is in its log, the size it got from the compositor
electrobench_window() { H -j clients 2>/dev/null | python3 -I -c 'import json, sys
for c in json.load(sys.stdin):
    if c.get("class") == "ElectroBench":
        print("%dx%d, fullscreen %s" % (*c["size"], c.get("fullscreen")))
        break'; }
electrobench_workload() { # workload, scene option, scene seconds, [--windowed]
    local log=$CLIENTDIR/$1.log result i window
    rm -f "$log"
    # it reads shaders/ and assets/ from the working directory first
    client $(($3 + 180)) "cd '${ELECTROBENCH%/*}' && exec env SDL_VIDEODRIVER=wayland './${ELECTROBENCH##*/}' $2 ${4:-} >$log 2>&1"
    for ((i = 0; i < 480; i++)); do
        electrobench_drawing && break
        client_running || break
        sleep 0.25
    done
    if ! electrobench_drawing; then
        echo "    skipped, ElectroBench did not run: $(grep -a -v -E '^\s*$|^ |^Assets:' "$log" | tail -n 1)"
        stop_clients
        return
    fi
    sleep 2
    window=$(electrobench_window)
    # when the scene printed its result, to the tenth of a second: rec's own steps around the window take seconds on
    # the slow machines, so the result being there when rec returns does not mean it came inside the window
    (until grep -a -q -E "$EB_RESULT" "$log"; do sleep 0.1; done; date +%s%N >"$log.ended") &
    local watcher=$!
    WINDOW_END=
    SECONDS_PER_RUN=$(($3 - 8)) rec "$1"
    await_log "$log" "$EB_RESULT" 120 running
    sleep 0.2
    kill $watcher 2>/dev/null
    wait $watcher 2>/dev/null
    if [ -s "$log.ended" ] && [ -n "$WINDOW_END" ] && [ "$(cat "$log.ended")" -lt "$WINDOW_END" ]; then
        echo "    the scene ended $(((WINDOW_END - $(cat "$log.ended")) / 1000000)) ms before the window did"
        value "invalid.$1" 1
    fi
    rm -f "$log.ended"
    stop_clients
    result=$(grep -a -m 1 -o -E "$EB_RESULT" "$log")
    echo "    ElectroBench $2 ${4:-}: window $window, $(grep -a -m 1 -E '^Renderer: ' "$log" | sed 's/ |.*//;s/^Renderer: //')${result:+, }${result:-no result}"
    [ -n "$result" ] || { value "invalid.$1" 1; return; }
    [ "$MODE" != perf ] && value "fps.$1" "$(sed -E 's/.*Average FPS : //' <<<"$result")"
}

needs_electrobench_guns="$ELECTROBENCH"
workload_electrobench_guns() { electrobench_workload electrobench-guns --og-only 60; }

needs_electrobench_guns_window="$ELECTROBENCH"
workload_electrobench_guns_window() { electrobench_workload electrobench-guns-window --og-only 60 --windowed; }

needs_electrobench_ocean="$ELECTROBENCH"
workload_electrobench_ocean() { electrobench_workload electrobench-ocean --scene-only 45; }

needs_electrobench_ocean_window="$ELECTROBENCH"
workload_electrobench_ocean_window() { electrobench_workload electrobench-ocean-window --scene-only 45 --windowed; }

needs_electrobench_pool="$ELECTROBENCH"
workload_electrobench_pool() { electrobench_workload electrobench-pool --pool-only 45; }

needs_electrobench_pool_window="$ELECTROBENCH"
workload_electrobench_pool_window() { electrobench_workload electrobench-pool-window --pool-only 45 --windowed; }

needs_electrobench_lines="$ELECTROBENCH"
workload_electrobench_lines() { electrobench_workload electrobench-lines --pole-only 45; }

needs_electrobench_lines_window="$ELECTROBENCH"
workload_electrobench_lines_window() { electrobench_workload electrobench-lines-window --pole-only 45 --windowed; }

# The graphics benchmarks of Phoronix's first look at the Snapdragon X2 Elite on Linux (2026-10-21, phoronix.com/review/
# snapdragon-x2-linux/2): SuperTuxKart with Vulkan at its Ultimate effects, Yamagi Quake II's timedemo with Vulkan and with
# OpenGL 3, 16x anisotropic filtering and MSAA, and vkmark in mailbox mode, run as Phoronix's test profiles run them
# (pts/supertuxkart-1.8.1, pts/yquake2-1.3.0, pts/vkmark-1.3.2), but fullscreen at the monitor's size like the games
# above. Each reports what Phoronix reports, its own frame rate or score, as fps.<workload>.

# whether the GPU is a radeon one: lianli's r600 (ARUBA) locked up under Xonotic's heavier effects (2026-11-09), and the
# EliteBook's radeon GPU died after lockups, so heavy GPU workloads that were not tried there leave it out
radeon_gpu() { readlink /sys/class/drm/card*/device/driver 2>/dev/null | grep -q '/radeon$'; }

# the focused monitor's size in the compositor's logical coordinates, as a client that is not scale aware sees it: WxH
logical_size() {
    H -j monitors 2>/dev/null | python3 -I -c 'import json, sys
for m in json.load(sys.stdin):
    if m.get("focused"):
        w, h = (m["height"], m["width"]) if m.get("transform", 0) % 2 else (m["width"], m["height"])
        print("%dx%d" % (round(w / m["scale"]), round(h / m["scale"])))
        break'
}

# the size and fullscreen state of a client's window as the compositor has it, by class or title
window_of() { # class or title
    H -j clients 2>/dev/null | python3 -I -c 'import json, sys
for c in json.load(sys.stdin):
    if sys.argv[1] in (c.get("class"), c.get("title")):
        print("%dx%d, fullscreen %s" % (*c["size"], c.get("fullscreen")))
        break' "$1"
}

# when a line matching a regex shows up in a log, in ns since the epoch, written into a file by a watcher in the
# background: rec's own steps around the window take seconds on the slow machines, so a result being there when rec
# returns does not mean it came inside the window. Prints the watcher's pid
watch_for_line() { # log, regex, file
    rm -f "$3"
    (until grep -a -q -E "$2" "$1" 2>/dev/null; do sleep 0.1; done; date +%s%N >"$3") >/dev/null 2>&1 &
    echo $!
}
# whether the line came before the window ended (WINDOW_END, set by rec), which makes the workload invalid; stops the watcher
ended_inside_window() { # watcher's pid, file, workload
    local ended
    kill "$1" 2>/dev/null
    wait "$1" 2>/dev/null
    ended=$(cat "$2" 2>/dev/null)
    rm -f "$2"
    [ -n "$ended" ] && [ -n "$WINDOW_END" ] && [ "$ended" -lt "$WINDOW_END" ] || return 1
    echo "    the benchmark ended $(((WINDOW_END - ended) / 1000000)) ms before the window did"
    value "invalid.$3" 1
}

# SuperTuxKart (the supertuxkart package, 774 MB) in its benchmark mode: the replay of a race on black_forest with one ghost
# kart, about 38 s of race after loading, timed by the game. No frame limit (max_fps 9999), no sound, Christmas hats and
# bunny ears off, a fresh save directory (SUPERTUXKART_SAVEDIR) each time, as Phoronix's config, and no vsync
# (swap-interval-vsync 0: Phoronix's config sets swap-interval, a name 1.5 does not know, so its runs had vsync, and the
# Galaxy Book's Vulkan run stayed at 119 of its 120 Hz with it; without vsync the Vulkan renderer presents in immediate
# mode on Linux, the OpenGL one with a swap interval of 0); fullscreen at the monitor's logical size, since SDL 2 is not
# scale aware (1440x900 on the Galaxy Book). The game writes its log into the save directory: when the race ends it
# prints the frames and the time of the race, which make the mean frame rate, fps.<workload>, and its own "Steady FPS"
# and "Mostly stable FPS", Phoronix's two charts, as fps.<workload>.steady and .stable (frame rates that most of the
# race's frames reach, the game's profiler.cpp; a few long stalls make them 0). The window starts 4 s after the game read
# the replay (the race's countdown) and lasts 30 s, inside the race, which takes longer when the game stalls.
STK_EFFECTS_ULTIMATE="--enable-glow --enable-bloom --enable-light-shaft --enable-dof --enable-motion-blur --enable-mlaa \
--enable-ssao --enable-ibl --enable-hd-textures --enable-dynamic-lights --anisotropic=16 --shadows=1024"
STK_RESULT="Profiler: Frame count '[0-9]+', Time \(ms\) '[0-9]+', Steady FPS '[0-9]+', Mostly stable FPS '[0-9]+'"
supertuxkart_workload() { # workload, render driver: vulkan or gl
    local dir=$CLIENTDIR/$1.save log result watcher window frames ms steady stable
    if [ "$2" = vulkan ] && radeon_gpu; then
        echo "    skipped, the radeon driver has no Vulkan"
        return
    fi
    log=$dir/config-0.10/stdout.log
    rm -rf "$dir"
    asuser mkdir -p "$dir/config-0.10" "$dir/data"
    # asuser's stdin is /dev/null, so the config goes in as an argument
    asuser sh -c 'printf "%s\n" "$1" >"$0"' "$dir/config-0.10/config.xml" '<?xml version="1.0"?>
<stkconfig version="8" >
    <Audio sfx_on="false" music_on="false" />
    <Video fullscreen="true" max_fps="9999" vulkan_fullscreen_desktop="true" />
    <GFX swap-interval-vsync="0" />
</stkconfig>'
    client 600 "exec env SUPERTUXKART_SAVEDIR='$dir' XDG_DATA_HOME='$dir/data' supertuxkart --benchmark --unlock-all \
        --xmas=2 --easter=2 --no-sound --fullscreen --screensize=$(logical_size) --render-driver=$2 $STK_EFFECTS_ULTIMATE \
        >$CLIENTDIR/$1.out 2>&1"
    # loading takes 15 s on the T550
    if ! await_log "$log" 'Replay: Reading replay file' 180 running; then
        echo "    skipped, SuperTuxKart did not start its benchmark: $(sed 's/\x1b\[[0-9;]*m//g' "$log" "$CLIENTDIR/$1.out" 2>/dev/null | grep -a -i -E 'error|fatal' | grep -v 'User Config' | tail -n 1)"
        stop_clients
        return
    fi
    sleep 4
    window=$(window_of supertuxkart)
    watcher=$(watch_for_line "$log" "$STK_RESULT" "$log.ended")
    WINDOW_END=
    SECONDS_PER_RUN=30 rec "$1"
    await_log "$log" "$STK_RESULT" 180 running
    sleep 0.2
    ended_inside_window "$watcher" "$log.ended" "$1"
    stop_clients
    result=$(grep -a -m 1 -o -E "$STK_RESULT" "$log")
    echo "    SuperTuxKart $2: window $window, $(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -a -m 1 -o -E '(Vulkan|GL) renderer: .*|OpenGL renderer: .*' ), ${result:-no result}"
    [ -n "$result" ] || { value "invalid.$1" 1; return; }
    [ "$MODE" = perf ] && return
    read -r frames ms steady stable < <(grep -o -E "'[0-9]+'" <<<"$result" | tr -d "'" | tr '\n' ' ')
    value "fps.$1" "$(awk -v f="$frames" -v t="$ms" 'BEGIN {if (t > 0) printf "%.1f", 1000 * f / t; else print "nan"}')"
    value "fps.$1.steady" "$steady"
    value "fps.$1.stable" "$stable"
    asuser rm -rf "$dir"
}

needs_supertuxkart_vk="supertuxkart"
workload_supertuxkart_vk() { supertuxkart_workload supertuxkart-vk vulkan; } # Phoronix's chart

needs_supertuxkart_gl="supertuxkart"
workload_supertuxkart_gl() { supertuxkart_workload supertuxkart-gl gl; }

# Yamagi Quake II (built with id's demo data into /opt/yquake2 by scripts/machines/yquake2.sh) plays the demo q2demo1.dm2
# as a timedemo, as fast as it can, and prints the frames, seconds and frame rate of each pass (632 frames: 20.8 s on the
# T550 with Vulkan, 2 to 3 s on the Galaxy Book). Phoronix plays it once; here it is played over and over (a config that
# stops the server and sets the next demo to itself, since starting a map clears it), and fps.<workload> is the frames
# over the seconds of the passes that ran during the window: from the first pass to end after it started to the one
# running when it ended. The first pass is not measured (shaders, caches). Phoronix's options: textures as the game
# shipped them, no frame limit, no vsync, 16x anisotropic filtering, 16x MSAA (the driver's most where it has fewer: 8 on
# Intel, 4 with Vulkan on the Adreno); fullscreen at the desktop's resolution in pixels (r_mode -2, vid_fullscreen 2:
# 2880x1800 on the Galaxy Book) instead of Phoronix's 1920x1080 window, a native Wayland client (SDL 2 through sdl2-compat), its
# config in a directory of its own under the user's home (-cfgdir), no sound. A renderer that does not start makes the
# game try another, so the workload is skipped unless the renderer it asked for drew the demo.
YQUAKE2=${YQUAKE2:-/opt/yquake2/quake2}
YQ2_RESULT='^[0-9]+ frames, [0-9.]+ seconds: [0-9.]+ fps'
yq2_passes() { grep -a -c -E "$YQ2_RESULT" "$1" 2>/dev/null; } # log
yquake2_workload() { # workload, renderer: vk or gl3, the name its refresher has
    local log=$CLIENTDIR/$1.log cfg=.hypoland-bench-$1 n0 n1 i result passes
    # no Vulkan there, and 16x MSAA without vsync was not tried on the r600 that locked up under Xonotic's heavier effects
    if radeon_gpu; then
        echo "    skipped on the radeon driver"
        return
    fi
    rm -f "$log"
    asuser rm -rf "$USERHOME/$cfg"
    asuser mkdir -p "$USERHOME/$cfg/baseq2"
    # a demo map started over the one that ended ends at once (thousands of passes of 0 frames a second): the server first
    asuser sh -c 'printf "%s\n" killserver "set nextdemo \"exec loop.cfg\"" "demomap q2demo1.dm2" >"$0"' "$USERHOME/$cfg/baseq2/loop.cfg"
    client $((SECONDS_PER_RUN + 900)) "cd '${YQUAKE2%/*}' && exec env SDL_VIDEODRIVER=wayland './${YQUAKE2##*/}' -cfgdir $cfg \
        +set timedemo 1 +set vid_fullscreen 2 +set r_mode -2 +set r_retexturing 2 +set r_scale8bittextures 1 +set vid_maxfps 999 \
        +set r_vsync 0 +set vid_renderer $2 +set r_anisotropic 16 +set r_msaa_samples 16 +set s_initsound 0 +exec loop.cfg >$log 2>&1"
    if ! await_log "$log" "$YQ2_RESULT" 300 running || ! grep -a -E '^Refresh: ' "$log" | tail -n 1 | grep -q "$3"; then
        echo "    skipped, Yamagi Quake II did not play the demo with $3: $(grep -a -m 1 -E '^Refresh: ' "$log")$(grep -a -i -E 'error|failed|reverting' "$log" | tail -n 1)"
        stop_clients
        asuser rm -rf "$USERHOME/$cfg"
        return
    fi
    sleep 1
    n0=$(yq2_passes "$log")
    rec "$1"
    n1=$(yq2_passes "$log")
    # the pass running when the window ended, at most 15 minutes on the slowest machine
    for ((i = 0; i < 3600; i++)); do
        [ "$(yq2_passes "$log")" -gt "$n1" ] && break
        client_running || break
        sleep 0.25
    done
    echo "    Yamagi Quake II $3: window $(window_of quake2), $(grep -a -m 1 -E 'MSAA' "$log" | sed 's/^[. ]*//')"
    stop_clients
    result=$(grep -a -E "$YQ2_RESULT" "$log" | sed -n "$((n0 + 1)),$((n1 + 1))p")
    passes=$(grep -c . <<<"$result")
    echo "    $passes passes: $(awk '{printf "%s%s fps", (NR > 1 ? ", " : ""), $5}' <<<"$result")"
    asuser rm -rf "$USERHOME/$cfg"
    # the pass running at the window's end has to be there, or the game stopped
    [ "$passes" -gt "$((n1 - n0))" ] || { value "invalid.$1" 1; return; }
    [ "$MODE" != perf ] && value "fps.$1" "$(awk '{f += $1; s += $3} END {if (s > 0) printf "%.1f", f / s; else print "nan"}' <<<"$result")"
}

needs_yquake2_vk="$YQUAKE2"
workload_yquake2_vk() { yquake2_workload yquake2-vk vk Vulkan; }

needs_yquake2_gl3="$YQUAKE2"
workload_yquake2_gl3() { yquake2_workload yquake2-gl3 gl3 OpenGL3; }

# vkmark (the vkmark package) runs its 13 scenes for 10 s each, fullscreen in mailbox mode (Phoronix's chart; Phoronix's
# window had its screen's size), and prints its score, the mean of the scenes' frame rates, which is fps.<workload>. The
# window is the run, from 2 s into the first scene for 124 s, whatever --seconds says. Without a Vulkan device it exits.
needs_vkmark="vkmark"
workload_vkmark() {
    local log=$CLIENTDIR/vkmark.log result watcher window
    if radeon_gpu; then
        echo "    skipped, the radeon driver has no Vulkan"
        return
    fi
    rm -f "$log"
    client 400 "exec vkmark --fullscreen -p mailbox >$log 2>&1"
    if ! await_log "$log" '^\[vertex\]' 60 running; then
        echo "    skipped, vkmark did not start: $(grep -a -v -E '^\s*$|^=+$' "$log" | tail -n 1)"
        stop_clients
        return
    fi
    sleep 2
    window=$(window_of com.github.vkmark.vkmark)
    watcher=$(watch_for_line "$log" 'vkmark Score: [0-9]+' "$log.ended")
    WINDOW_END=
    SECONDS_PER_RUN=124 rec vkmark
    await_log "$log" 'vkmark Score: [0-9]+' 60 running
    sleep 0.2
    ended_inside_window "$watcher" "$log.ended" vkmark
    stop_clients
    result=$(sed -n -E 's/.*vkmark Score: ([0-9]+).*/\1/p' "$log" | head -n 1)
    echo "    vkmark: window $window, $(sed -n -E 's/^ *Device Name: *//p' "$log" | head -n 1), score ${result:-none}"
    [ -n "$result" ] || { value "invalid.vkmark" 1; return; }
    [ "$MODE" != perf ] && value "fps.vkmark" "$result"
}

needs_nautilus="nautilus"
workload_nautilus() { # GTK 4 redrawing a full window of icons, fullscreen toggled twice a second
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
# directory as scripts/machines/soak.sh)
FILES=$USERHOME/.cache/hypoland-bench/files-25000
# Flea 0.4.1 is a GPUI window (Rust, drawn through wgpu; 0.3.12 was a Quickshell window): on the X200 (GM45, OpenGL
# 2.1, no Vulkan) it opens no window and the shell shows a critical notification, "No graphics driver could open Flea",
# which stays over the windows for the rest of the session (it covered every later workload of the night of 2026-11-10
# and failed a deploy check's render steps).
# Returns whether its window is there; otherwise the workload is skipped and the notification dismissed
flea_opened() {
    if H -j clients 2>/dev/null | grep -q -i '"class": *"[^"]*flea'; then
        return 0
    fi
    echo "    skipped, Flea opened no window (it needs Vulkan or OpenGL 3)"
    stop_clients
    asuser timeout 5 /usr/share/omarchy/bin/omarchy-shell -q notifications dismissAll >/dev/null 2>&1
    return 1
}
needs_flea="flea"
workload_flea() { # a file manager for Omarchy (not its default), a GPUI window, paged through with keys
    local i key
    [ -e "$FILES/file-25000.txt" ] || asuser bash -c 'mkdir -p "$0" && cd "$0" && touch file-{00001..25000}.txt' "$FILES"
    client $((SECONDS_PER_RUN + 20)) "exec flea '$FILES'"
    sleep 8
    flea_opened || return
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
    # flea 0.3.12 exec'd qs and left a backend; the bracket keeps pkill from matching its own command line
    asuser pkill -f "[q]s -p /usr/share/flea" >/dev/null 2>&1
    asuser pkill -x flea >/dev/null 2>&1
    sleep 1
}

# A folder of 5000 empty files in Flea (a file manager for Omarchy, a GPUI window) and in Nautilus (GTK 4, its list
# view), scrolled with the Down key held on the uinput keyboard for the whole run (root only): the compositor forwards
# the one press and the client repeats it at the session's rate (Omarchy: 40 a second after 250 ms, so about 480 of
# the files in a 12 s run), as a finger resting on the key would. At the end, with the window still open, the memory of
# the clients (mem.<name>.clients_*: the Pss of their processes, their cgroups' current and peak memory) and of the
# compositor (mem.<name>.*, as for mem.start). Added 2026-10-29, 5000 files and the memory asked for by the user.
SCROLL_FILES=5000
scroll_files() { # the folder
    local dir=$USERHOME/.cache/hypoland-bench/files-$SCROLL_FILES
    [ -e "$dir/file-$SCROLL_FILES.txt" ] || asuser bash -c 'mkdir -p "$0" && cd "$0" && touch file-{0001..5000}.txt' "$dir"
    echo "$dir"
}
clients_memory() { # name: the processes in the clients' scopes
    local root pss=0 cur=0 peak=0 d p
    root=$(cgroot)
    [ -n "$root" ] && [ -d "$root/$SLICE" ] || return 0
    for d in "$root/$SLICE"/*.scope; do
        [ -d "$d" ] || continue
        cur=$((cur + $(cat "$d/memory.current" 2>/dev/null || echo 0) / 1024))
        peak=$((peak + $(cat "$d/memory.peak" 2>/dev/null || echo 0) / 1024))
        for p in $(cat "$d/cgroup.procs" 2>/dev/null); do
            pss=$((pss + $(awk '/^Pss:/ {print $2}' "/proc/$p/smaps_rollup" 2>/dev/null || echo 0)))
        done
    done
    value "mem.$1.clients_Pss_kB" "$pss"
    value "mem.$1.clients_cgroup_kB" "$cur"
    value "mem.$1.clients_peak_kB" "$peak"
}
scroll_folder() { # workload, seconds to wait for the window, command with FOLDER for the folder; OPENED, if set, is a
    # function that says whether the window opened (and cleans up when it did not)
    local name=$1 wait=$2 driver folder
    shift 2
    # the key would go into the password field of a lock screen
    if [ -n "$(in_the_way)" ]; then
        echo "--- $name: not measured,$(in_the_way)"
        value "invalid.$name" 1
        return
    fi
    folder=$(scroll_files)
    client $((SECONDS_PER_RUN + 25)) "${*//FOLDER/$folder}"
    sleep "$wait"
    if [ -n "${OPENED:-}" ] && ! "$OPENED"; then
        return
    fi
    rm -f "$OUT/$name.key.txt"
    env -i PATH="$PATH" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" python3 -I "$CLIENTSRC/holdkey.py" down $((SECONDS_PER_RUN + 1)) \
        >"$OUT/$name.key.txt" 2>&1 &
    driver=$!
    for _ in $(seq 1 50); do # the keyboard is there after 2 s
        grep -q "^down" "$OUT/$name.key.txt" 2>/dev/null && break
        sleep 0.1
    done
    rec "$name"
    wait $driver
    clients_memory "$name"
    memory "$name"
    stop_clients
}
needs_flea_scroll="flea root"
workload_flea_scroll() {
    OPENED=flea_opened scroll_folder flea-scroll 8 "exec flea 'FOLDER'"
    asuser pkill -f "[q]s -p /usr/share/flea" >/dev/null 2>&1
    asuser pkill -x flea >/dev/null 2>&1
    sleep 1
}
needs_nautilus_scroll="nautilus root"
workload_nautilus_scroll() {
    # the list view, one file per Down; a grid moves a row
    local view
    view=$(asuser gsettings get org.gnome.nautilus.preferences default-folder-viewer 2>/dev/null)
    [ -n "$view" ] && [ "$view" != "'list-view'" ] && asuser gsettings set org.gnome.nautilus.preferences default-folder-viewer list-view >/dev/null 2>&1
    scroll_folder nautilus-scroll 5 "exec nautilus --new-window 'FOLDER'"
    asuser nautilus -q >/dev/null 2>&1
    [ -n "$view" ] && [ "$view" != "'list-view'" ] && asuser gsettings set org.gnome.nautilus.preferences default-folder-viewer "${view//\'/}" >/dev/null 2>&1
    return 0
}

# Folio, Omarchy's file manager since omacom/omarchy#18378 (2026-11-10, in place of Nautilus): C++ and Qt Quick,
# a process and a window per launch (app id folio). The same two workloads as Nautilus': `folio` the icon folder in its
# grid with fullscreen toggled twice a second, `folio-scroll` the 5000 files in its list with Down held. It remembers
# its view (grid, list or columns) in ~/.config/folio/folio.conf; the workloads set it before the start and put the
# user's file back afterwards. Added 2026-11-11, asked for by the user. Both need Folio 0.4.0 or later (2026-11-12, the
# version on every machine since), so results compare across machines. Folio 0.1.1 to 0.4.0 do not scroll the list to
# the cursor on Down (the cursor walks off the bottom, the view stays; fixed in omacom/folio#18, still open), so until a
# release has the fix `folio-scroll` measures the cursor and the details pane, not scrolling.
FOLIOCONF=$USERHOME/.config/folio/folio.conf
folio_view() { # view: grid or list. Keeps the user's settings for folio_restore
    if [ -e "$FOLIOCONF" ] && [ ! -e "$CLIENTDIR/folio.conf" ]; then
        cp -p "$FOLIOCONF" "$CLIENTDIR/folio.conf"
    elif [ ! -e "$FOLIOCONF" ]; then
        : >"$CLIENTDIR/folio.conf.none"
    fi
    asuser bash -c 'mkdir -p "${0%/*}" && { [ -e "$0" ] || echo "[General]" >"$0"; } &&
        if grep -q "^viewMode=" "$0"; then sed -i "s/^viewMode=.*/viewMode=$1/" "$0"; else sed -i "/^\[General\]/a viewMode=$1" "$0"; fi' \
        "$FOLIOCONF" "$1"
}
folio_restore() { # after stop_clients: each launch is a process of its own, so a window of the user's stays
    if [ -e "$CLIENTDIR/folio.conf" ]; then
        asuser cp "$CLIENTDIR/folio.conf" "$FOLIOCONF"
        rm -f "$CLIENTDIR/folio.conf"
    elif [ -e "$CLIENTDIR/folio.conf.none" ]; then
        rm -f "$FOLIOCONF" "$CLIENTDIR/folio.conf.none"
    fi
}
needs_folio="folio>=0.4.0"
workload_folio() { # Qt Quick redrawing a full window of icons, fullscreen toggled twice a second
    folio_view grid
    client $((SECONDS_PER_RUN + 15)) "exec folio /usr/share/icons/Adwaita/symbolic/actions"
    sleep 5
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do
        dispatch 'hl.dsp.window.fullscreen({action="toggle"})' "fullscreen"; sleep 0.5
    done) &
    local toggler=$!
    rec folio
    wait $toggler
    stop_clients
    folio_restore
}
needs_folio_scroll="folio>=0.4.0 root"
workload_folio_scroll() {
    # the list, one file per Down; the grid moves a row
    folio_view list
    scroll_folder folio-scroll 5 "exec folio 'FOLDER'"
    folio_restore
    return 0
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

# Three terminals and workspace 1 and 2 in turns, twice a second. Then how long a switch takes to show, by keys: to
# a neighbouring window and to the other workspace (latency.workspace-switch.*, see switching())
needs_workspace_switch="foot"
workload_workspace_switch() {
    for i in 1 2 3; do
        client $((SECONDS_PER_RUN + 60)) "exec foot -e sleep 600"
        sleep 1
    done
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do
        dispatch "hl.dsp.focus({workspace=2})" "workspace 2"; sleep 0.5
        dispatch "hl.dsp.focus({workspace=1})" "workspace 1"; sleep 0.5
    done) &
    local switcher=$!
    rec workspace-switch
    wait $switcher
    switching workspace-switch --classes foot --focus 12 --workspace 8 --bar 8
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
# has one, QT_FORCE_STDERR_LOGGING brings the frame rate to the log. Tk (its own client, toolkit-tk.py) draws only
# through X11, with core X11 requests that Xwayland carries out; its "canvas" is the 60 squares, "menu" the window of
# the menu and dialog check.
toolkit() { # gtk3|gtk4|gtk3-x11|qt-quick|qt-software|tk, [check|spinner|sprites|canvas|menu]
    [ -s "$CLIENTDIR/toolkit-tk.py" ] || toolkit_sources
    case $1 in
        gtk3 | gtk4) echo "exec env GDK_BACKEND=wayland python3 -I $CLIENTDIR/toolkit.py ${1#gtk}.0 $2" ;;
        gtk3-x11) echo "exec env GDK_BACKEND=x11 DISPLAY=$(xdisplay) python3 -I $CLIENTDIR/toolkit.py 3.0 $2" ;;
        qt-quick) echo "exec env QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 qml6 $CLIENTDIR/toolkit.qml -- $2" ;;
        qt-software) echo "exec env QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 QT_QUICK_BACKEND=software qml6 $CLIENTDIR/toolkit.qml -- $2" ;;
        tk) echo "exec env DISPLAY=$(xdisplay) python3 -I $CLIENTDIR/toolkit-tk.py $2" ;;
    esac
}

toolkit_name() { # gtk3|gtk4|gtk3-x11|qt-quick|qt-software|tk
    case $1 in
        gtk3) echo "GTK 3" ;;
        gtk4) echo "GTK 4" ;;
        gtk3-x11) echo "GTK 3 (Xwayland)" ;;
        qt-quick) echo "Qt Quick" ;;
        qt-software) echo "Qt Quick (software)" ;;
        tk) echo "Tk (Xwayland)" ;;
    esac
}

renderer_of() { sed -n 's/.*renderer: //p' "$1" 2>/dev/null | head -n 1; } # log

# Xwayland starts with the first X11 client; its display is in the environment of the session
xdisplay() { asuser systemctl --user show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p'; }

# Hypoland starts Xwayland when the first X11 client connects, Hyprland with the compositor. An X11 test waits until
# it answers (xprop's connection starts it), so neither its start nor a client waiting for it is in a measurement or
# a check's time limit. A fresh one gets 2 s more, for what it does after its first answer
xwayland_up() {
    local display started=0
    display=$(xdisplay)
    [ -n "$display" ] || return 1
    pgrep -u "$TESTUSER" -x Xwayland >/dev/null || started=1
    for _ in $(seq 1 20); do
        if asuser env DISPLAY="$display" timeout 5 xprop -root -len 1 _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1; then
            [ $started = 1 ] && sleep 2
            return 0
        fi
        sleep 1
    done
    return 1
}

toolkit_sources() {
    cp "$CLIENTSRC/toolkit.py" "$CLIENTSRC/toolkit.qml" "$CLIENTSRC/toolkit-tk.py" "$CLIENTDIR/"
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
needs_gtk3_x11_scroll="python3 gi:Gtk-3.0 x11 xprop"
workload_gtk3_x11_scroll() { toolkit_workload gtk3-x11-scroll gtk3-x11; }

needs_gtk4_spinner="python3 gi:Gtk-4.0"
workload_gtk4_spinner() { toolkit_workload gtk4-spinner gtk4 spinner; }

needs_qt_software_sprites="qml6"
workload_qt_software_sprites() { toolkit_workload qt-software-sprites qt-software sprites; }

# Tk's canvas through Xwayland: 60 small squares moving over a still text. The canvas redraws the bounding box of what
# changed, with the squares all over the window close to all of it, into a new pixmap of the X server, and copies that
# to the window: one large damage region per frame, not the many small ones of qt-software-sprites. Core X11 drawing
# that Xwayland does, whose CPU time is in the session's total_percent. Like gtk3-x11-scroll the frame rate is the
# client's own pace (60 moves a second), the screen's is fps.tk-canvas.screen. Tk is not part of Omarchy (the tk package)
needs_tk_canvas="python3 py:tkinter x11 xprop"
workload_tk_canvas() { toolkit_workload tk-canvas tk canvas; }

# Three terminals that print for 4 s and then wait: the memory idle shm windows keep in the compositor, measured while
# they are open (mem.idle-windows.*). A window that never drew again after its last resize has no second texture to
# give back, see CGLTexture::update(); real windows mostly have (typing, a page that loads). Then how long a move of
# the focus between them takes to show (latency.idle-windows.*)
needs_idle_windows="foot"
workload_idle_windows() {
    local i total purgeable before after
    # what the kernel cannot take back: Mesa keeps freed buffers in its cache, purgeable
    read -r total _ purgeable < <(gpu_memory)
    before=$((total - purgeable))
    for i in 1 2 3; do
        client $((SECONDS_PER_RUN + 60)) "exec foot -e sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do ls -la /usr/lib | head -n 8; sleep 0.4; done; exec sleep 600'"
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
    switching idle-windows --classes foot --focus 12
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
    # the generator of the files, the editor's movements, the console's shell with its pager and the log. The driver
    # runs as root from where it came, not from the user's directory
    cp "$CLIENTSRC/dev-gen.sh" "$CLIENTSRC/dev-move.lua" "$CLIENTSRC/dev-shellrc" "$CLIENTSRC/dev-log.py" \
        "$CLIENTSRC/dev-pager.py" "$CLIENTDIR/"
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
    local driver border i
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
    env -i PATH="$PATH" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" python3 -I "$CLIENTSRC/dev.py" \
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
    latencies dev "$OUT/dev.txt"
}

# Two terminals side by side, foot (shm) and Alacritty (GL), both full of one long line of numbers that wraps at the
# window's edge, so that every new width reflows all of it, and the split between them dragged left and right with
# SUPER and the right button (Omarchy's resize bind) by a uinput pointer (root only), 125 motions a second like a
# mouse: every motion has both clients draw at a new size and the compositor take their new buffers (cpu.resize.*).
# Then how long a step of the drag takes to show, the first frame that shows it (resize, the compositor) and the first
# that shows both windows drawn at their new size (redrawn), and moves of the focus between them (latency.resize.*)
RESIZE_TEXT="sh -c 'seq -s, 100000 104000; exec sleep 600'"
resize_workload() { # workload, command of the second terminal, its class
    local name=$1 before driver i
    if [ -n "$(in_the_way)" ]; then
        echo "--- $name: not measured,$(in_the_way)"
        value "invalid.$name" 1
        return
    fi
    before=$(nclients)
    # foot reflows 100 ms after the last resize by default
    client $((SECONDS_PER_RUN + 90)) "exec foot -o resize-delay-ms=0 -e $RESIZE_TEXT"
    mapped "$before" 10
    before=$(nclients)
    client $((SECONDS_PER_RUN + 90)) "$2"
    mapped "$before" 10
    sleep 1
    # dwindle keeps the direction of a split (Omarchy's preserve_split), and a window of the workload before that was
    # still closing can leave it top and bottom: then the new window's split is turned
    if [ "$(H clients | awk '$1 == "at:" {split($2, a, ","); print a[2]}' | sort -u | wc -l)" -gt 1 ]; then
        dispatch 'hl.dsp.layout("togglesplit")' "togglesplit"
        echo "    the windows were top and bottom, turned the split"
    fi
    sleep 2
    windows_driver --classes "foot,$3" --drag $((SECONDS_PER_RUN + 1)) --focus 8 --resize 12 >"$OUT/$name.txt" 2>&1 &
    driver=$!
    # the devices are there after 3.5 s
    for i in $(seq 1 50); do
        grep -q "^load" "$OUT/$name.txt" && break
        sleep 0.2
    done
    grep -q "^load" "$OUT/$name.txt" || value "invalid.$name" 1
    rec "$name"
    wait "$driver"
    [ -n "$(in_the_way)" ] && value "invalid.$name" 1
    stop_clients
    latencies "$name" "$OUT/$name.txt"
}

needs_resize="foot alacritty python3 root"
workload_resize() { resize_workload resize "exec alacritty -e $RESIZE_TEXT" Alacritty; }

# The same with foot on both sides, not in the default list: shm buffers only, which no GL driver or Mesa variable (the
# GLES 3 override stock Hyprland needs on the X200) touches
needs_resize_foot="foot python3 root"
workload_resize_foot() { resize_workload resize-foot "exec foot -o resize-delay-ms=0 -e $RESIZE_TEXT" foot; }

# ---- Omarchy's shell: Quickshell's layer surfaces over a window, as a session has them

OMARCHY_SHELL=/usr/share/omarchy/bin/omarchy-shell

# a foot window full of text that sits still, for the shell to draw over
idle_window() { # seconds to live
    local before
    before=$(nclients)
    client "$1" "exec foot -e sh -c 'seq -s, 100000 104000; exec sleep 600'"
    mapped "$before" 10
}

# Notifications arriving one a second from four senders, each shown for 5 s (low urgency): about five cards stand in
# the shell's column at the right of the screen, over the window, one sliding in and one going every second
# (cpu.notifications.*; the shell's own time is in the session's total_percent). They go into the shell's history like
# any other, the cards are dismissed at the end. Then one at a time over the session bus, how long a notification
# takes until its card shows (latency.notifications.toast_ms, see clients/shell.py)
needs_notifications="foot notify-send shell"
workload_notifications() {
    local sender i
    idle_window $((SECONDS_PER_RUN + 30))
    sleep 2
    (for i in $(seq 1 $((SECONDS_PER_RUN + 6))); do
        asuser notify-send -a "hypoland-bench $((i % 4))" -u low "Notification $i" \
            "The quick brown fox jumps over the lazy dog, $i times" >/dev/null 2>&1
        sleep 1
    done) &
    sender=$!
    sleep 4
    rec notifications
    wait $sender
    asuser timeout 5 $OMARCHY_SHELL -q notifications dismissAll >/dev/null 2>&1
    sleep 2
    latency_phase_user notifications shell.py --toast 8
    stop_clients
}

# Omarchy's menu (SUPER+SPACE) opened and closed over the same window, each for a second: a fullscreen overlay
# layer with a scrim and a card in the middle, mapped and unmapped, the keyboard focus going to it and back to the
# window (cpu.menu.*). It is toggled as the bind does it, through the global shortcut the shell registers, or through
# omarchy-shell where it has none. Then by keys, how long SUPER+SPACE takes until the scrim shows, Escape until it is
# gone, a letter typed into the open menu's search line until its rows change, and Down and Up moving its selected row
# (latency.menu.open_ms, close_ms, search_ms, select_ms, see clients/shell.py)
needs_menu="foot shell"
MENU_SHORTCUT=0
menu_toggle() {
    if [ $MENU_SHORTCUT = 1 ]; then
        dispatch 'hl.dsp.global("omarchy:menu.root")' "global omarchy:menu.root"
    else
        asuser timeout 5 $OMARCHY_SHELL -q shell toggle omarchy.menu '{"menu":"root"}' >/dev/null 2>&1
    fi
}
menu_close() { H layers | grep -q "namespace: omarchy-menu" && menu_toggle; }
workload_menu() {
    local toggler i
    MENU_SHORTCUT=0
    H globalshortcuts 2>/dev/null | grep -q "^omarchy:menu.root " && MENU_SHORTCUT=1
    menu_close
    idle_window $((SECONDS_PER_RUN + 60))
    sleep 2
    (for i in $(seq 1 $((SECONDS_PER_RUN / 2 + 3))); do
        menu_toggle; sleep 1
        menu_toggle; sleep 1
    done) &
    toggler=$!
    sleep 4
    rec menu
    wait $toggler
    sleep 1
    menu_close
    latency_phase menu shell.py --menu 10 --search 10 --select 10
    menu_close
    stop_clients
}

# ---- the session's start, opening and closing windows, many windows

# The start of a session (added 2026-10-30, asked for by the user for the 0.3.0 numbers): SDDM restarted, which logs in
# again, and the new compositor followed from the start of its process (clients/startup.py): when its IPC answers
# (startup.ipc_ms), when its first frame reaches the screen (first_frame_ms, its first page flip), when the shell's
# wallpaper and bar layers are there (wallpaper_ms, bar_ms), the CPU time the compositor (cpu_ms, with its ended
# threads) and uwsm's service with the compositor, the shell and Xwayland (session_cpu_ms) have used STARTUP_SECONDS
# after the start, and the compositor's memory then (mem.startup.*). exec_ms is the time from the restart to the
# process, the old session ending and the login, the same for any compositor. Not in WORKLOADS: the rest of the run
# measures the new session, which is younger than --settle. Run it alone (--workloads startup, with --rounds for
# several starts) or first in a list.
needs_startup="python3 root"
STARTUP_SECONDS=20
workload_startup() {
    local key v
    stop_clients
    python3 -I "$CLIENTSRC/startup.py" --process "$PROCESS" --runtime "$RUNTIME" --seconds $STARTUP_SECONDS \
        --perf "$OUT/startup.$ROUND.perf" >"$OUT/startup.txt" 2>&1
    grep -v -E "^(startup|pid) " "$OUT/startup.txt" | sed 's/^/    /'
    while read -r _ key v; do
        if [ "$v" = timeout ]; then
            echo "    $key: nothing within 60 s"
            value "invalid.startup" 1
            continue
        fi
        value "startup.$key" "$v"
    done < <(grep "^startup " "$OUT/startup.txt")
    grep -q "^pid " "$OUT/startup.txt" || { echo "--- startup: no new compositor"; exit 1; }
    # the workloads after it run in the new session: its compositor, instance, socket and environment
    # shellcheck source=session.sh
    . "$HERE/lib/session.sh"
    echo "--- startup: compositor pid $P, instance $SIG"
    memory startup
    [ -n "$OMARCHY" ] && asuser /usr/share/omarchy/bin/omarchy-shell -q notifications dismissAll >/dev/null 2>&1
    dispatch 'hl.dsp.dpms({action=[[on]]})' "dpms on"
}

# a workspace on the focused monitor without windows, among 5 to 9 (1 and 2 are the workloads')
empty_workspace() {
    local used ws
    used=$(H clients | awk '$1 == "workspace:" {print $2}' | sort -u)
    for ws in 5 6 7 8 9; do
        grep -qx "$ws" <<<"$used" || { echo "$ws"; return 0; }
    done
    return 1
}

close_on_workspace() { # workspace
    local a
    for a in $(H clients | awk -v w="$1" '/^Window / {a = $2} $1 == "workspace:" && $2 == w {print "0x" a}'); do
        dispatch "hl.dsp.window.close({window=\"address:$a\"})" "closewindow address:$a"
    done
}

# Omarchy's terminal opened with its bind (SUPER+RETURN, uwsm-app and xdg-terminal-exec as a person's key starts it) on
# an empty workspace and closed with SUPER+W, by a uinput keyboard (clients/launch.py, root only; added 2026-10-30): the
# time until the middle of the screen first changes (latency.launch.open_ms, close_ms) and until it stays as it then is
# (opened_ms, closed_ms: the animation has ended and the terminal has drawn, or the wallpaper shows again). Opening is
# mostly the terminal's start, the same under any compositor; the compositor's part is the bind, the map, the layout,
# the animation and the frame. The terminal runs outside the clients' slice, so there is no CPU time here.
needs_launch="python3 root xdg-terminal-exec"
LAUNCH_STEPS=8
workload_launch() {
    local ws xy
    if [ -n "$(in_the_way)" ]; then
        echo "--- launch: not measured,$(in_the_way)"
        value "invalid.launch" 1
        return
    fi
    if ! ws=$(empty_workspace); then
        echo "--- launch: not measured, no empty workspace among 5 to 9"
        value "invalid.launch" 1
        return
    fi
    dispatch "hl.dsp.focus({workspace=$ws})" "workspace $ws"
    sleep 1
    # the pointer at the right edge, out of the region and of the bar and the dock, which show on hover
    xy=$(H monitors | awk '/^Monitor/ {m = 1} m && / at / {split($1, r, "[x@]"); split($3, p, "x")} m && /scale:/ {s = $2}
        m && /focused: yes/ {printf "%d %d", p[1] + r[1] / s - 2, p[2] + r[2] / s / 2; exit}')
    dispatch "hl.dsp.cursor.move({x=${xy% *}, y=${xy#* }})" "movecursor $xy"
    sleep 0.5
    echo "--- launch: on workspace $ws"
    latency_phase launch launch.py --steps $LAUNCH_STEPS
    grep -q "launch.py: no window opened" "$OUT/launch.txt" 2>/dev/null && value "invalid.launch" 1
    close_on_workspace "$ws"
    sleep 1
    dispatch "hl.dsp.focus({workspace=1})" "workspace 1"
    sleep 1
}

# Many terminals on one workspace (added 2026-10-30): 10, then 20, then 40 foot windows (shm) in an even grid over the
# work area (5x2, 5x4, 8x5), floating, as dwindle would split the newest window again and again until the last ones are a
# few pixels wide. Each prints a line five times a second, so most frames have several small windows to update. For each
# count the CPU time (cpu.many-windows-<n>.*, with ms_per_frame: what a frame costs with n windows), the memory with them
# open (mem.many-windows-<n>.*, the windows' textures) and how long a move of the focus and a switch to workspace 2 and
# back take to show (latency.many-windows-<n>.*, see switching()). The windows stop printing for the latencies: the
# switch is timed by the middle of a window, which a line printed after the key would change first.
needs_many_windows="foot python3"
MANY_WINDOWS="10:5x2 20:5x4 40:8x5"

# the work area of the focused monitor in the compositor's logical coordinates, without the bar: x y width height
work_area() {
    H monitors -j | python3 -I -c '
import json, sys
m = next(m for m in json.load(sys.stdin) if m["focused"])
w, h = m["width"] / m["scale"], m["height"] / m["scale"]
if m.get("transform", 0) % 2:
    w, h = h, w
l, t, r, b = (m.get("reserved") or [0, 0, 0, 0])[:4]
print(int(m["x"] + l), int(m["y"] + t), int(w - l - r), int(h - t - b))'
}

# the windows of a class floating in a grid of cells over the work area, in the order hyprctl lists them
grid_windows() { # class, columns, rows
    local cols=$2 rows=$3 x y w h cw ch i=0 a wx wy
    read -r x y w h < <(work_area)
    cw=$((w / cols)) ch=$((h / rows))
    for a in $(H clients | awk -v c="$1" '/^Window / {a = $2} $1 == "class:" && $2 == c {print "0x" a}'); do
        wx=$((x + i % cols * cw + 4)) wy=$((y + i / cols * ch + 4))
        dispatch "hl.dsp.window.float({action=\"enable\", window=\"address:$a\"})" "setfloating address:$a"
        dispatch "hl.dsp.window.resize({x=$((cw - 8)), y=$((ch - 8)), window=\"address:$a\"})" "resizewindowpixel exact $((cw - 8)) $((ch - 8)),address:$a"
        dispatch "hl.dsp.window.move({x=$wx, y=$wy, window=\"address:$a\"})" "movewindowpixel exact $wx $wy,address:$a"
        i=$((i + 1))
    done
}

workload_many_windows() {
    local n=0 step target cols rows before flag=$CLIENTDIR/many-windows-print
    touch "$flag"
    for step in $MANY_WINDOWS; do
        target=${step%%:*} cols=${step#*:} rows=${step##*x}
        cols=${cols%x*}
        while [ $n -lt "$target" ]; do
            before=$(nclients)
            client $((SECONDS_PER_RUN * 3 + 400)) "exec foot --app-id hypoland-many -e sh -c 'while :; do [ -e $flag ] && date +%T.%N; sleep 0.2; done'"
            if ! mapped "$before" 10; then
                echo "--- many-windows-$target: window $((n + 1)) did not open"
                value "invalid.many-windows-$target" 1
                stop_clients
                return
            fi
            n=$((n + 1))
        done
        grid_windows hypoland-many "$cols" "$rows"
        sleep 4
        rec "many-windows-$target"
        memory "many-windows-$target"
        rm -f "$flag"
        sleep 0.5
        switching "many-windows-$target" --classes hypoland-many --focus 6 --workspace 6
        touch "$flag"
    done
    rm -f "$flag"
    stop_clients
    sleep 2
}

# ---- latency: drivers in clients/ press keys and move a pointer through uinput devices (root only) and print
# "latency <kind> <ms>" or "latency <kind> timeout" for every step they waited for on the screen

# medians and 90th percentiles in ms, latency.<workload>.<kind>_ms and _p90_ms, and what else the driver printed
latencies() { # workload, the driver's output
    local kind line median p90 n timeouts
    grep -v -E "^(load|latency)" "$2" | sed 's/^/    /'
    for kind in $(awk '$1 == "latency" && NF == 3 && !seen[$2]++ {print $2}' "$2"); do
        timeouts=$(grep -c "^latency $kind timeout" "$2")
        [ "$timeouts" -gt 0 ] && value "latency.$1.${kind}_timeouts" "$timeouts"
        line=$(awk -v k="$kind" '$1 == "latency" && $2 == k && $3 != "timeout" {print $3}' "$2" | sort -g | awk '
            {v[NR] = $1} END {if (NR) printf "%s %s %d", v[int((NR + 1) / 2)], v[int(NR * 0.9 + 0.99)], NR}')
        if [ -z "$line" ]; then
            echo "    $kind: nothing changed on the screen ($timeouts steps)"
            continue
        fi
        read -r median p90 n <<<"$line"
        value "latency.$1.${kind}_ms" "$median"
        value "latency.$1.${kind}_p90_ms" "$p90"
        echo "    $kind: $median ms, 90% within $p90 ms ($n steps, $timeouts timeouts)"
    done
}

windows_driver() { # windows.py options
    env -i PATH="$PATH" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" python3 -I "$CLIENTSRC/windows.py" \
        --socket "$RUNTIME/hypr/$SIG/.socket.sock" "$@"
}

# the latency phase of a workload after its CPU time is measured, by a driver in clients/ (root only)
latency_phase() { # workload, driver, its options
    local name=$1 driver=$2
    shift 2
    if [ $ROOT = 0 ]; then
        echo "    latency: not measured, its keys need root (a uinput keyboard)"
        return
    fi
    if [ -n "$(in_the_way)" ]; then
        echo "    latency: not measured,$(in_the_way)"
        return
    fi
    env -i PATH="$PATH" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" python3 -I "$CLIENTSRC/$driver" \
        --socket "$RUNTIME/hypr/$SIG/.socket.sock" "$@" >"$OUT/$name.txt" 2>&1
    latencies "$name" "$OUT/$name.txt"
}

# the same as the user, for a driver that needs the session bus (which refuses root) and no uinput device: it goes into
# the clients' directory, which the user can read, with the parts it imports
latency_phase_user() { # workload, driver, its options
    local name=$1 driver=$2
    shift 2
    if [ -n "$(in_the_way)" ]; then
        echo "    latency: not measured,$(in_the_way)"
        return
    fi
    cp "$CLIENTSRC/$driver" "$CLIENTSRC/latency.py" "$CLIENTSRC/sessionbus.py" "$CLIENTDIR/"
    asuser python3 -I "$CLIENTDIR/$driver" --socket "$RUNTIME/hypr/$SIG/.socket.sock" "$@" >"$OUT/$name.txt" 2>&1
    latencies "$name" "$OUT/$name.txt"
}

# How long switching between the windows of a workload takes to show: the focus moved to a neighbouring window by
# SUPER+arrow, and with --workspace to workspace 2 and back (see clients/windows.py)
switching() { # workload, windows.py options
    local name=$1
    shift
    latency_phase "$name" windows.py "$@"
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

missing() { # programs, <program>>=<version> for a program at least as new as its package's version, gi:<namespace>-<version> for a library Python reaches through GObject introspection, py:<module> for a Python module, x11 for Xwayland, root, shell for Omarchy's
    local prog lib have
    for prog in $1; do
        if [[ $prog == *'>='* ]]; then
            asuser sh -c "command -v ${prog%%>=*}" >/dev/null 2>&1 || { echo "${prog%%>=*} ${prog#*>=} or later"; return; }
            have=$(pacman -Q "${prog%%>=*}" 2>/dev/null | cut -d' ' -f2)
            [ -n "$have" ] && [ "$(vercmp "$have" "${prog#*>=}")" -ge 0 ] ||
                { echo "${prog%%>=*} ${prog#*>=} or later (${have:-not a package} here)"; return; }
            continue
        fi
        if [[ $prog == py:* ]]; then
            asuser python3 -I -c "import ${prog#py:}" >/dev/null 2>&1 || { echo "${prog#py:} for Python"; return; }
            continue
        fi
        if [ "$prog" = x11 ]; then
            [ -n "$(xdisplay)" ] || { echo "Xwayland"; return; }
            continue
        fi
        if [ "$prog" = shell ]; then
            [ "$(asuser timeout 5 $OMARCHY_SHELL shell ping 2>/dev/null)" = ok ] || { echo "Omarchy's shell"; return; }
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
# With RAPL's platform zone (psys) the same again for the whole machine, as power.*.psys_W and power.*.psys_net_W.
# Where the workload showed frames, the net energy per frame on the screen as well (energy.*.net_mJ_per_frame, asked
# for by the user on 2026-11-12): a compositor that shows more frames makes its clients draw more, which the power
# alone counts against it. The net, not the gross: the idle machine's power spread over more frames would make any
# compositor that shows more of them look cheaper.
PENDING="" BEFORE="" PBEFORE=""
baseline() {
    if [ "$METER" = none ]; then
        sleep 1
        return
    fi
    sleep 2
    battery_check
    local m0 m1 w wp="" name gross ms pgross fps
    m0=$(mark)
    sleep "$IDLE"
    m1=$(mark)
    w=$(watts "$m0" "$m1")
    value power.baseline.W "$w"
    if [ -n "$PSYS" ]; then
        wp=$(watts "$m0" "$m1" 3)
        value power.baseline.psys_W "$wp"
    fi
    if [ -n "$PENDING" ] && [ -n "$BEFORE" ]; then
        read -r name gross ms pgross fps <<<"$PENDING"
        awk -v r=$ROUND -v n="$name" -v g="$gross" -v a="$BEFORE" -v b="$w" -v s="$ms" -v f="${fps:--}" 'BEGIN {
            net = g - (a + b) / 2
            pm = (a > b ? a - b : b - a) / 2
            printf "@ %s power.%s.net_W %.3f\n@ %s power.%s.pm_W %.3f\n", r, n, net, r, n, pm
            printf "@ %s energy.%s.net_J %.2f\n", r, n, net * s / 1000
            if (f != "-") printf "@ %s energy.%s.net_mJ_per_frame %.2f\n", r, n, net * 1000 / f
            printf "    %.2f W, %.2f W above the idle baseline (+-%.2f W)\n", g, net, pm
        }'
        [ -n "$wp" ] && [ -n "$PBEFORE" ] && [ "${pgross:--}" != - ] &&
            awk -v r=$ROUND -v n="$name" -v g="$pgross" -v a="$PBEFORE" -v b="$wp" -v f="${fps:--}" 'BEGIN {
                net = g - (a + b) / 2
                printf "@ %s power.%s.psys_net_W %.3f\n@ %s power.%s.psys_pm_W %.3f\n", r, n, net, r, n, (a > b ? a - b : b - a) / 2
                if (f != "-") printf "@ %s energy.%s.psys_net_mJ_per_frame %.2f\n", r, n, net * 1000 / f
                printf "    the machine (psys) %.2f W, %.2f W above its idle baseline\n", g, net
            }'
    fi
    PENDING=""
    BEFORE=$w PBEFORE=$wp
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
        if [[ " ${!needs} " == *" x11 "* ]] && ! xwayland_up; then
            echo "=== $n $name: skipped, Xwayland does not answer on $(xdisplay)"
            value "invalid.$name" 1
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
