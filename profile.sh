#!/usr/bin/env bash
# Profiles the compositor on the machine under test: installs the package with its debug package (makepkg
# builds with frame pointers, so every package has complete call stacks; the debug package has the symbols),
# records the compositor with perf under the workloads of scripts/bench/measure.sh and removes the debug
# package again. With --no-deploy or --host local it profiles the compositor that is running.
#
# Usage: ./profile.sh [options] [seconds per workload]
#
#   --keep             leave the debug package on the machine under test, for perf report on the saved data
#   --stages REGEX     functions whose inclusive time is printed
# TARGET_HELP

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1
. scripts/bench/target.sh

KEEP=0
while [ $# -gt 0 ]; do
    case $1 in
        --keep) KEEP=1 ;;
        -h | --help) target_usage "$0"; exit 0 ;;
        -*)
            target_option "$@" || { echo "unknown argument: $1" >&2; exit 2; }
            shift $((TARGET_SHIFT - 1))
            ;;
        *[!0-9]*) echo "unknown argument: $1" >&2; exit 2 ;;
        *) MEASURE_ARGS+=(--seconds "$1") ;;
    esac
    shift
done
target_is_local && DEPLOY=0

OUT=test-results/profile-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

if [ $DEPLOY = 1 ]; then
    echo "building and installing the package with its debug package..."
    target_deploy "$OUT/deploy.log" --debug "${DEPLOY_ARGS[@]}" || { echo "the deploy failed:"; grep -E "^(FAIL|build failed)" "$OUT/deploy.log"; exit 1; }
fi

target_run --mode perf "${MEASURE_ARGS[@]}" | tee "$OUT/profile.txt"

if [ $DEPLOY = 1 ] && [ $KEEP -eq 0 ]; then
    echo
    echo "removing the debug package..."
    ssh "${SSH_OPTS[@]}" "root@$BENCH_HOST" "pacman -R --noconfirm hypoland-debug" >"$OUT/restore.log" 2>&1
fi
echo "report: $OUT/profile.txt"
