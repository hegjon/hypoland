# Sourced by bench.sh and profile.sh: where the machine under test is and how a script gets there.
#
#   BENCH_HOST    ssh host of the machine under test, or "local" for this machine (default: $X200_HOST, x200)
#   BENCH_LOGIN   ssh login used for measuring (default: root). Any other login is tried with sudo and
#                 measures without root when that needs a password: no governor change, no suspend inhibitor
#   BENCH_DEPLOY  script that builds, deploys, restarts and checks (default: ./test-x200.sh). It gets the
#                 host as X200_HOST and the build directory as BUILD_DIR

BENCH_HOST=${BENCH_HOST:-${X200_HOST:-x200}}
BENCH_LOGIN=${BENCH_LOGIN:-root}
BENCH_DEPLOY=${BENCH_DEPLOY:-./test-x200.sh}

target_is_local() {
    [ "$BENCH_HOST" = local ] || [ "$BENCH_HOST" = localhost ]
}

# runs a script on the machine under test, as root when that is possible without a password
target_run() { # script, arguments
    local script=$1 args="" arg
    shift
    for arg in "$@"; do
        args+=" $(printf '%q' "$arg")"
    done

    if target_is_local; then
        if [ "$(id -u)" != 0 ] && sudo -n true 2>/dev/null; then
            sudo -n bash "$script" "$@"
        else
            bash "$script" "$@"
        fi
        return
    fi

    # the script travels on stdin, so the machine under test needs no copy of the repository
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$BENCH_LOGIN@$BENCH_HOST" \
        "if [ \"\$(id -u)\" != 0 ] && sudo -n true 2>/dev/null; then exec sudo -n bash -s --$args; else exec bash -s --$args; fi" <"$script" 2>&1 |
        grep --line-buffered -v "^Pseudo-terminal"
    return "${PIPESTATUS[0]}"
}

# builds, deploys and restarts through BENCH_DEPLOY. Nothing is deployed to this machine
target_deploy() { # log file, arguments of the deploy script
    local log=$1
    shift
    if target_is_local; then
        echo "local run, measuring the compositor that is running" >"$log"
        return 0
    fi
    X200_HOST=$BENCH_HOST "$BENCH_DEPLOY" "$@" >"$log" 2>&1
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
  --no-build         deploy the build that is there
  --no-deploy        measure the compositor that is running, deploy and restart nothing
  --seconds N        length of a workload
  --workloads LIST   idle,gpu-client,terminal-scroll,alacritty-scroll,video,nautilus,flea,shm-fullwindow,workspace-switch
  --client NAME=CMD  one more workload: CMD is started as a client and measured as NAME
  --process NAME     name of the compositor process (default: hypoland, then Hypoland, then Hyprland)
  --keep-governor    leave the CPU frequency governor alone'
