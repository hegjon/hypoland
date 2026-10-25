#!/usr/bin/env bash
# Builds the Arch package from the working tree and installs it on test machines (see MACHINES.md): copies it
# into the pacman cache there, so the versions before it stay for going back, installs it with pacman, restarts
# SDDM (which logs in again) and checks the new session with `scripts/bench/measure.sh --mode check`, sent there by
# scripts/bench/target.sh. Logs in as root@<host>. The hosts are deployed in parallel, each into its own log.
#
# Usage: scripts/deploy.sh [options] host...
#
#   --no-build     install the package that was built last
#   --no-install   only check the session that is running (the aarch64 Galaxy Book builds its own package on
#                  the machine, see MACHINES.md)
#   --restart      restart SDDM also with --no-install: a machine left without input locks its session after
#                  5 minutes, and only a new session gets past the lock screen
#   --no-check     install and restart, check nothing
#   --debug        install hypoland-debug too, the symbols perf needs (profile.sh)
#
# Writes test-results/deploy-<time>/<host>.log and the screenshots of the checks into <host>/ next to it.

set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
. scripts/bench/target.sh

BUILD=1 INSTALL=1 CHECK=1 DEBUG=0 RESTART="" HOSTS=()
while [ $# -gt 0 ]; do
    case $1 in
        --no-build) BUILD=0 ;;
        --no-install) INSTALL=0 BUILD=0 ;;
        --no-check) CHECK=0 ;;
        --debug) DEBUG=1 ;;
        --restart) RESTART=1 ;;
        -h | --help) target_usage "$0"; exit 0 ;;
        -*) echo "unknown argument: $1" >&2; exit 2 ;;
        *) HOSTS+=("$1") ;;
    esac
    shift
done
RESTART=${RESTART:-$INSTALL}
[ ${#HOSTS[@]} -gt 0 ] || { echo "no host given, see --help" >&2; exit 2; }

OUT=test-results/deploy-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
SSH=(ssh "${SSH_OPTS[@]}")

# ---- build

PACKAGES=()
if [ $INSTALL = 1 ]; then
    if [ $BUILD = 1 ]; then
        echo "building the package..."
        # makepkg keeps its build directory, so only what changed is compiled. It configures again every time,
        # which regenerates the embedded shader sources
        if ! (cd packaging/arch && makepkg -f --noconfirm) >"$OUT/makepkg.log" 2>&1; then
            tail -n 20 "$OUT/makepkg.log"
            echo "build failed, see $OUT/makepkg.log"
            exit 1
        fi
    fi
    mapfile -t PACKAGES < <(cd packaging/arch && makepkg --packagelist | grep -v -- "-debug-")
    [ $DEBUG = 1 ] && mapfile -t -O 1 PACKAGES < <(cd packaging/arch && makepkg --packagelist | grep -- "-debug-")
    for p in "${PACKAGES[@]}"; do
        [ -f "$p" ] || { echo "$p is missing, build it first (leave out --no-build)"; exit 1; }
    done
    echo "package: $(basename "${PACKAGES[0]}")"
fi

# ---- one host, its output goes into its log

deploy() { # host
    local h=$1 arch old p out dir
    local cached=()
    if ! "${SSH[@]}" "root@$h" true; then
        echo "FAIL  ssh root@$h"
        return 1
    fi

    if [ $INSTALL = 1 ]; then
        arch=$("${SSH[@]}" "root@$h" uname -m)
        if [ "$arch" != "$(uname -m)" ]; then
            echo "FAIL  $h is $arch and the package $(uname -m): build it on the machine (MACHINES.md), then check it with --no-install"
            return 1
        fi
        for p in "${PACKAGES[@]}"; do
            cached+=("/var/cache/pacman/pkg/$(basename "$p")")
        done
        # --ask=4 answers yes to removing what the package conflicts with (hyprland on a first install)
        if scp -q "${PACKAGES[@]}" "root@$h:/var/cache/pacman/pkg/" &&
            "${SSH[@]}" "root@$h" "pacman -U --noconfirm --ask=4 ${cached[*]}"; then
            echo "PASS  installed $(basename "${PACKAGES[0]}")"
        else
            echo "FAIL  installing the package"
            return 1
        fi
    fi

    if [ "$RESTART" = 1 ]; then
        # SDDM logs in again, the new compositor writes its pid into the lock file of its instance
        old=$("${SSH[@]}" "root@$h" "pgrep -n -x hypoland")
        "${SSH[@]}" "root@$h" "systemctl restart sddm"
        if "${SSH[@]}" "root@$h" "for i in \$(seq 1 60); do
                P=\$(pgrep -n -x hypoland)
                [ -n \"\$P\" ] && [ \"\$P\" != '$old' ] && grep -qx \"\$P\" /run/user/*/hypr/*/hyprland.lock 2>/dev/null && exit 0
                sleep 1
            done; exit 1"; then
            echo "PASS  new session after restarting SDDM"
        else
            echo "FAIL  no new compositor within 60 s of restarting SDDM"
            return 1
        fi
    fi

    [ $CHECK = 1 ] || return 0
    out=$(measure_on "root@$h" --mode check)
    echo "$out"
    dir=$(sed -n 's/^screenshots: \(\/tmp\/hypoland-measure\.[A-Za-z0-9]*\) on .*/\1/p' <<<"$out")
    if [ -n "$dir" ]; then
        mkdir -p "$OUT/$h"
        scp -q "root@$h:$dir/*.png" "$OUT/$h/" 2>/dev/null
        "${SSH[@]}" "root@$h" "rm -rf '$dir'"
    fi
    grep -q "^RESULT: PASS" <<<"$out"
}

declare -A PIDS
for h in "${HOSTS[@]}"; do
    deploy "$h" >"$OUT/$h.log" 2>&1 &
    PIDS[$h]=$!
done

FAILED=0
for h in "${HOSTS[@]}"; do
    if wait "${PIDS[$h]}"; then
        echo "== $h: PASS ($(grep -c "^PASS" "$OUT/$h.log") passed, $(grep -c "^SKIP" "$OUT/$h.log") skipped)"
    else
        echo "== $h: FAIL"
        FAILED=1
        # a failure without a FAIL line, such as no compositor running, is in the last line
        grep -q "^FAIL" "$OUT/$h.log" || tail -n 1 "$OUT/$h.log"
    fi
    grep -E "^(FAIL|SKIP)" "$OUT/$h.log"
done
echo "logs: $OUT"
exit $FAILED
