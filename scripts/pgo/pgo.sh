#!/bin/bash
# Profile guided build of the compositor (x86-64): 4 to 6.5% less compositor CPU a frame and 3.3 MiB less of the
# binary's code in memory, measured on ten machines in the night of 2026-11-15 (docs/notes/performance.md).
#
#   scripts/pgo/pgo.sh train DIR HOST...   build the instrumented package from the tree, run the session check and one
#                                          round of the benchmark with it on every HOST, put the machines' package
#                                          back and merge their counters into DIR/profile
#   scripts/pgo/pgo.sh build DIR           build the package with DIR/profile and the section order made from it; the
#                                          packages land in packaging/arch as a deploy's do, so
#                                          `scripts/deploy.sh --no-build HOST...` installs and checks them
#
# A profile belongs to the source it was trained on: a function changed since then is compiled without one, so train
# again before a release. Both builds use one build directory of their own (~/.cache/hypoland-pgo, the tree's stays as
# it is): GCC matches a function to its counters by a checksum that has the source file's path in it, the generated
# sources in the build directory among them, so the build that uses a profile has to be where the training's was.
set -u
cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
ROOT=$PWD
CMD=${1:-}; DIR=${2:-}
[ -n "$DIR" ] || { sed -n '2,13p' "$0"; exit 1; }
mkdir -p "$DIR" && DIR=$(readlink -f "$DIR") || exit 1
CACHE=${HYPOLAND_PGO_BUILDDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hypoland-pgo}
T=$ROOT/scripts/pgo
# the flags come from the makepkg plugin packaging/makepkg-pgo/pgo.sh
[ -f "${MAKEPKG_LIBRARY:-/usr/share/makepkg}/buildenv/pgo.sh" ] || {
    echo "the makepkg plugin is not installed: install -Dm644 packaging/makepkg-pgo/pgo.sh /usr/share/makepkg/buildenv/pgo.sh (as root)"
    exit 1
}

# makepkg_in LOG [VAR=value...]: a build in the profile builds' directory, its packages listed in DIR/packages, the
# committed pkgver line back after it
makepkg_in() {
    local log=$1 ok=1; shift
    (cd packaging/arch && env BUILDDIR="$CACHE" "$@" nice -n 19 ionice -c 3 makepkg -f --noconfirm) >"$log" 2>&1 || ok=0
    # the packages it made, read while the PKGBUILD still has the version makepkg wrote into it
    (cd packaging/arch && env BUILDDIR="$CACHE" "$@" makepkg --packagelist) >"$DIR/packages" 2>/dev/null
    local committed; committed=$(git show HEAD:packaging/arch/PKGBUILD 2>/dev/null | sed -n 's/^pkgver=//p')
    [ -n "$committed" ] && sed -i "s/^pkgver=.*/pkgver=$committed/" packaging/arch/PKGBUILD
    [ $ok = 1 ] || { tail -n 20 "$log"; echo "build failed, see $log"; exit 1; }
}

train_host() {
    local h=$1 pkg=$2 before back
    before=$(ssh "root@$h" 'pacman -Q hypoland' | tr ' ' '-') || { echo "$h: not reachable"; return 1; }
    back=$(ssh "root@$h" "ls /var/cache/pacman/pkg/$before-*.pkg.tar.zst /var/cache/pacman/pkg/$before-*.pkg.tar.xz 2>/dev/null | head -n 1")
    [ -n "$back" ] || echo "$h: no package of $before in its cache: the instrumented one stays until the next deploy"
    ssh "root@$h" 'rm -rf /var/tmp/hypoland-pgo; mkdir -m 1777 /var/tmp/hypoland-pgo && setfacl -d -m u::rw,g::rw,o::rw /var/tmp/hypoland-pgo' || return 1
    scp -q "$pkg" "root@$h:/var/tmp/" && ssh "root@$h" "pacman -U --noconfirm /var/tmp/${pkg##*/} && systemctl restart sddm" >"$DIR/train-$h-install.log" 2>&1 ||
        { echo "$h: install failed, see $DIR/train-$h-install.log"; return 1; }
    sleep 40
    scripts/deploy.sh --no-install "$h" >"$DIR/train-$h-check.log" 2>&1
    sleep 15
    ./bench.sh --host "$h" --no-deploy --rounds 1 --settle 30 ${TRAIN_WORKLOADS:+--workloads "$TRAIN_WORKLOADS"} "pgo-train-$h" >"$DIR/train-$h-bench.log" 2>&1
    # the compositor writes its counters when its session ends; then the package from before the training comes back
    ssh "root@$h" "systemctl stop sddm; sleep 8; ${back:+pacman -U --noconfirm $back 2>&1 | tail -n 1;} systemctl start sddm" >>"$DIR/train-$h-install.log" 2>&1
    rm -rf "$DIR/prof-$h"; scp -q -r "root@$h:/var/tmp/hypoland-pgo" "$DIR/prof-$h"
    echo "$h: $(ls "$DIR/prof-$h" 2>/dev/null | wc -l) counter files, check: $(grep -m1 -E 'PASS|FAIL' <(tac "$DIR/train-$h-check.log")), now $(ssh "root@$h" 'pacman -Q hypoland')"
}

case $CMD in
train)
    shift 2; [ $# -gt 0 ] || { echo "train needs machines"; exit 1; }
    echo "building the instrumented package..."
    makepkg_in "$DIR/build-generate.log" PGO_GENERATE=/var/tmp/hypoland-pgo PKGDEST="$DIR"
    pkg=$(grep -m1 '/hypoland-[0-9]' "$DIR/packages")
    # every counter's function, read from the instrumented binary while it is there
    python3 "$T/gcovnames.py" "$CACHE/hypoland/src/build/hypoland" "$CACHE/hypoland/src/build/hypoland" >"$DIR/gcovnames.txt"
    git rev-parse HEAD >"$DIR/commit"
    for h in "$@"; do train_host "$h" "$pkg" & done; wait
    dirs=(); for h in "$@"; do [ -n "$(ls "$DIR/prof-$h" 2>/dev/null)" ] && dirs+=("$DIR/prof-$h"); done
    [ ${#dirs[@]} -gt 0 ] || { echo "no machine gave a profile"; exit 1; }
    rm -rf "$DIR/profile"; cp -r "${dirs[0]}" "$DIR/profile"
    for d in "${dirs[@]:1}"; do gcov-tool merge -o "$DIR/merged" "$DIR/profile" "$d" && rm -rf "$DIR/profile" && mv "$DIR/merged" "$DIR/profile"; done
    python3 "$T/executed.py" "$DIR/profile" "$DIR/gcovnames.txt" >"$DIR/executed.txt"
    echo "profile of ${#dirs[@]} machines in $DIR/profile: $(ls "$DIR/profile" | wc -l) counter files, $(wc -l <"$DIR/executed.txt") functions ran"
    ;;
build)
    [ -d "$DIR/profile" ] && [ -s "$DIR/executed.txt" ] || { echo "$DIR has no profile, train first"; exit 1; }
    [ "$(cat "$DIR/commit" 2>/dev/null)" = "$(git rev-parse HEAD)" ] || echo "note: the profile was trained on $(cut -c1-9 "$DIR/commit" 2>/dev/null), the tree is at $(git rev-parse --short HEAD)"
    echo "building with the profile..."
    makepkg_in "$DIR/build-use.log" PGO_PROFILE="$DIR/profile"
    nm -S "$CACHE/hypoland/src/build/hypoland" >"$DIR/syms.txt"
    python3 "$T/order.py" "$DIR/executed.txt" "$DIR/syms.txt" >"$DIR/order.ld" || exit 1
    echo "linking in the training's order..."
    makepkg_in "$DIR/build-order.log" PGO_PROFILE="$DIR/profile" PGO_ORDER="$DIR/order.ld"
    cp "$DIR/packages" packaging/arch/.last-build
    grep -v -- -debug- packaging/arch/.last-build
    ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
