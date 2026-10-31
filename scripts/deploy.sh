#!/usr/bin/env bash
# Builds the Arch package from the working tree and installs it on test machines (see
# ~/Work/infrastructure/MACHINES.md): copies it into the pacman cache there, so the versions before it stay for going
# back, installs it with pacman, restarts SDDM (which logs in again) and checks the new session with
# `scripts/bench/measure.sh --mode check`, sent there by scripts/bench/target.sh. A passing check ends with one more
# restart, which the checked compositor has to leave without a core dump. Logs in as root@<host>. The hosts are
# deployed in parallel, each into its own log.
#
# Usage: scripts/deploy.sh [options] host...
#
#   --no-build     install the package that was built last
#   --no-install   only check the session that is running (the aarch64 Galaxy Book builds its own package on
#                  the machine, see ~/Work/infrastructure/MACHINES.md)
#   --restart      restart SDDM also with --no-install: a machine left without input locks its session after
#                  5 minutes, and only a new session gets past the lock screen
#   --no-check     install and restart, check nothing
#   --debug        install hypoland-debug too, the symbols perf needs (profile.sh)
#
# Writes test-results/deploy-<time>/<host>.log and the screenshots of the checks into <host>/ next to it.
#
# makepkg writes the version it built into packaging/arch/PKGBUILD. When the package was installed on at least one
# machine, that pkgver is committed (`PKGBUILD: pkgver <version>, deployed to <hosts>`, decided by the user on
# 2026-10-27), so the commits say which build the machines got. The version counts the commits before it, so the
# next deploy builds one count higher even without other changes. Not with --no-build, not on a detached HEAD.

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
    echo "packages: $(basename -a "${PACKAGES[@]}" | tr '\n' ' ')"
fi

commit_pkgver() { # hosts that got the package
    local ver other
    git symbolic-ref -q HEAD >/dev/null || { echo "detached HEAD, the pkgver is not committed"; return 0; }
    git diff --quiet HEAD -- packaging/arch/PKGBUILD && return 0
    # only the pkgver line may differ, so an edit of the PKGBUILD never ends up in this commit
    other=$(git diff HEAD -- packaging/arch/PKGBUILD | grep -E '^[-+]' | grep -vE '^(---|\+\+\+) ' | grep -vcE '^[-+]pkgver=')
    if [ "$other" != 0 ]; then
        echo "the PKGBUILD has other changes, the pkgver is not committed"
        return 0
    fi
    ver=$(sed -n 's/^pkgver=//p' packaging/arch/PKGBUILD)
    if git commit -q -m "PKGBUILD: pkgver $ver, deployed to $*" -- packaging/arch/PKGBUILD; then
        echo "committed: PKGBUILD: pkgver $ver, deployed to $*"
    else
        echo "committing the pkgver failed"
    fi
}

# ---- one host, its output goes into its log

new_session() { # host: restarts SDDM, which logs in again, and waits until a new compositor holds the lock of its instance
    local h=$1 old
    old=$("${SSH[@]}" "root@$h" "pgrep -n -x hypoland")
    "${SSH[@]}" "root@$h" "systemctl restart sddm"
    "${SSH[@]}" "root@$h" "for i in \$(seq 1 60); do
            P=\$(pgrep -n -x hypoland)
            [ -n \"\$P\" ] && [ \"\$P\" != '$old' ] && grep -qx \"\$P\" /run/user/*/hypr/*/hyprland.lock 2>/dev/null && exit 0
            sleep 1
        done; exit 1"
}

deploy() { # host
    local h=$1 arch old p out dir since
    local cached=()
    if ! "${SSH[@]}" "root@$h" true; then
        echo "FAIL  ssh root@$h"
        return 1
    fi

    if [ $INSTALL = 1 ]; then
        arch=$("${SSH[@]}" "root@$h" uname -m)
        if [ "$arch" != "$(uname -m)" ]; then
            echo "FAIL  $h is $arch and the package $(uname -m): build it on the machine (~/Work/infrastructure/MACHINES.md), then check it with --no-install"
            return 1
        fi
        for p in "${PACKAGES[@]}"; do
            cached+=("/var/cache/pacman/pkg/$(basename "$p")")
        done
        # --ask=4 answers yes to removing what the package conflicts with (hyprland on a first install). The
        # kmsgrab built by hand into /usr/local/bin before the hypoland-bench package would come first in the path
        if scp -q "${PACKAGES[@]}" "root@$h:/var/cache/pacman/pkg/" &&
            "${SSH[@]}" "root@$h" "pacman -U --noconfirm --ask=4 ${cached[*]} && rm -f /usr/local/bin/hypoland-kmsgrab"; then
            echo "PASS  installed $(basename -a "${PACKAGES[@]}" | tr '\n' ' ')"
        else
            echo "FAIL  installing the package"
            return 1
        fi
    fi

    if [ "$RESTART" = 1 ]; then
        if new_session "$h"; then
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
    grep -q "^RESULT: PASS" <<<"$out" || return 1

    # the checked compositor has to exit cleanly as well: a crash at the end of a session is seen by nobody (lianli
    # dumped core at most session ends from 2026-10-30, a layer freed during the shutdown), so end it with one more
    # restart and look for its core dump
    [ "$RESTART" = 1 ] || return 0
    old=$("${SSH[@]}" "root@$h" "pgrep -n -x hypoland")
    since=$("${SSH[@]}" "root@$h" "date +%s")
    if ! new_session "$h"; then
        echo "FAIL  no new compositor within 60 s of restarting SDDM after the checks"
        return 1
    fi
    # systemd-coredump takes a few seconds to write the core
    p=$("${SSH[@]}" "root@$h" "sleep 5; coredumpctl list --no-legend --no-pager --since @$since $old 2>/dev/null | awk '{print \$8}'")
    if [ -z "$p" ]; then
        echo "PASS  the checked compositor exited without a core dump"
    else
        echo "FAIL  the checked compositor dumped core on exit ($p, coredumpctl info $old as root)"
        return 1
    fi
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
if [ $BUILD = 1 ]; then
    DEPLOYED=()
    for h in "${HOSTS[@]}"; do
        grep -q "^PASS  installed" "$OUT/$h.log" && DEPLOYED+=("$h")
    done
    [ ${#DEPLOYED[@]} -gt 0 ] && commit_pkgver "${DEPLOYED[@]}"
fi
echo "logs: $OUT"
exit $FAILED
