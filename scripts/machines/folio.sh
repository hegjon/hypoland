#!/bin/bash
# Builds the commit of Folio (github.com/omacom/folio, MIT, Omarchy's file manager) that the benchmark's folio workloads
# and the soak run, FOLIO_COMMIT in scripts/bench/lib/workloads.sh, on the test machines and installs it into
# /opt/folio/<commit>/, next to Omarchy's folio package, which it leaves alone:
#
#   scripts/machines/folio.sh <ssh host>...    over ssh as root, one machine after the other
#
# A commit and not Omarchy's package, so every machine runs the same Folio whatever Omarchy updated it to. Built on each
# machine, so the aarch64 ones get theirs too; git, gcc and make come with Omarchy, cmake and the Qt headers (part of
# Arch's Qt packages) are installed with pacman. Only the app is built, not its tests.
set -euo pipefail

[ $# -gt 0 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

root=$(cd "$(dirname "$0")/../.." && pwd)
commit=$(sed -n 's/^FOLIO_COMMIT=//p' "$root/scripts/bench/lib/workloads.sh")
soak=$(sed -n 's/^FOLIO_COMMIT=//p' "$root/scripts/machines/soak.sh")
[[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "no FOLIO_COMMIT in scripts/bench/lib/workloads.sh"; exit 1; }
[ "$commit" = "$soak" ] || { echo "FOLIO_COMMIT differs: workloads.sh $commit, soak.sh $soak"; exit 1; }

for host in "$@"; do
    echo "=== $host"
    ssh -o BatchMode=yes "root@$host" bash -s -- "$commit" <<'EOF' || echo "=== $host: FAILED"
set -euo pipefail
commit=$1
dest=/opt/folio/$commit
if [ -x "$dest/folio" ]; then
    echo "already installed: $dest"
    exit 0
fi
pacman -S --needed --noconfirm git cmake make gcc pkgconf glib2 libarchive zlib qt6-base qt6-declarative \
    qt6-imageformats qt6-multimedia qt6-svg qt6-wayland >/dev/null
src=$(mktemp -d /tmp/folio.XXXXXX)
trap 'rm -rf "$src"' EXIT
cd "$src"
git init -q folio
git -C folio fetch -q --depth 1 https://github.com/omacom/folio.git "$commit"
git -C folio checkout -q FETCH_HEAD
[ "$(git -C folio rev-parse HEAD)" = "$commit" ]
(cd folio && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >"$src/build.log" 2>&1 &&
    nice -n 10 cmake --build build --target folio -j"$(nproc)" >>"$src/build.log" 2>&1) || { tail -20 build.log; exit 1; }
rm -rf "$dest.new"
install -Dm755 folio/build/folio "$dest.new/folio"
install -Dm644 folio/LICENSE "$dest.new/LICENSE"
echo "$commit" >"$dest.new/COMMIT"
chmod -R a+rX /opt/folio
mv "$dest.new" "$dest"
echo "installed $dest/folio"
EOF
done
