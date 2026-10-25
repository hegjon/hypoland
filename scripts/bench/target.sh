# shellcheck shell=bash
# Sourced by bench.sh, profile.sh and scripts/deploy.sh: where the machine under test is and how measure.sh gets
# there.
#
#   BENCH_HOST    ssh host of the machine under test, or "local" for this machine (default: x200)
#   BENCH_LOGIN   ssh login used for measuring (default: root). Any other login is tried with sudo and
#                 measures without root when that needs a password: no governor change, no suspend inhibitor.
#                 Deploying always logs in as root

BENCH_HOST=${BENCH_HOST:-x200}
BENCH_LOGIN=${BENCH_LOGIN:-root}

# the ssh options of every script that reaches a machine
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

target_is_local() {
    [ "$BENCH_HOST" = local ] || [ "$BENCH_HOST" = localhost ]
}

# runs scripts/bench/measure.sh on a machine, as root when that is possible without a password. The whole
# directory travels as a tar stream on stdin, so the machine needs no copy of the repository; it is unpacked into a
# temporary directory there and removed afterwards
measure_on() { # login@host, arguments of measure.sh
    local target=$1 args="" arg run
    shift
    for arg in "$@"; do
        args+=" $(printf '%q' "$arg")"
    done
    run="bash \"\$d/bench/measure.sh\"$args"
    tar -C scripts -cz bench | ssh "${SSH_OPTS[@]}" "$target" \
        "d=\$(mktemp -d) && tar -xz -C \"\$d\" || exit 1
        if [ \"\$(id -u)\" != 0 ] && sudo -n true 2>/dev/null; then sudo -n $run; else $run; fi
        s=\$?; rm -rf \"\$d\"; exit \$s" 2>&1 |
        grep --line-buffered -v "^Pseudo-terminal"
    return "${PIPESTATUS[1]}"
}

# runs measure.sh on the machine under test
target_run() { # arguments of measure.sh
    if target_is_local; then
        if [ "$(id -u)" != 0 ] && sudo -n true 2>/dev/null; then
            sudo -n bash scripts/bench/measure.sh "$@"
        else
            bash scripts/bench/measure.sh "$@"
        fi
        return
    fi
    measure_on "$BENCH_LOGIN@$BENCH_HOST" "$@"
}

# builds the package, installs it, restarts the session and checks it (scripts/deploy.sh). Nothing is deployed
# to this machine
target_deploy() { # log file, options of scripts/deploy.sh
    local log=$1
    shift
    if target_is_local; then
        echo "local run, measuring the compositor that is running" >"$log"
        return 0
    fi
    scripts/deploy.sh "$@" "$BENCH_HOST" >"$log" 2>&1
}

# options bench.sh and profile.sh have in common. Sets MEASURE_ARGS, DEPLOY and DEPLOY_ARGS, returns 1 for
# an option it does not know
DEPLOY=1
DEPLOY_ARGS=()
MEASURE_ARGS=()
TARGET_SHIFT=0
target_option() { # the remaining command line
    TARGET_SHIFT=1
    case $1 in
        --host) BENCH_HOST=$2; TARGET_SHIFT=2 ;;
        --login) BENCH_LOGIN=$2; TARGET_SHIFT=2 ;;
        --no-build) DEPLOY_ARGS+=(--no-build) ;;
        --no-deploy) DEPLOY=0 ;;
        --seconds | --workloads | --client | --process | --stages) MEASURE_ARGS+=("$1" "$2"); TARGET_SHIFT=2 ;;
        --keep-governor) MEASURE_ARGS+=("$1") ;;
        *) return 1 ;;
    esac
}

TARGET_HELP='  --host HOST        ssh host of the machine under test, or "local" (default: $BENCH_HOST, x200)
  --login USER       ssh login for measuring (default: root)
  --no-build         deploy the package that was built last
  --no-deploy        measure the compositor that is running, deploy and restart nothing
  --seconds N        length of a workload
  --workloads LIST   idle,gpu-client,terminal-scroll,alacritty-scroll,video,nautilus,flea,shm-fullwindow,workspace-switch,
                     gtk3-scroll,gtk4-scroll,qt-quick-scroll,qt-software-scroll,gtk3-x11-scroll,gtk4-spinner,
                     qt-software-sprites,video-window,idle-windows,dev
  --client NAME=CMD  one more workload: CMD is started as a client and measured as NAME
  --process NAME     name of the compositor process (default: hypoland, then Hypoland, then Hyprland)
  --keep-governor    leave the CPU frequency governor alone'
