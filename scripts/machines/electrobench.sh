#!/bin/bash
# Builds ElectroBench (github.com/deadbeef7/ElectroBench, GPL-3, not packaged) on the test machines and installs it into
# /opt/electrobench, where the benchmark's electrobench-* workloads (scripts/bench/lib/workloads.sh) look for it:
#
#   scripts/machines/electrobench.sh <ssh host>...    over ssh as root, one machine after the other
#
# It is built on each machine, so the aarch64 ones get theirs too; gcc, make and git come with Omarchy, glew is
# installed with pacman. The commit is pinned, so every machine runs the same scenes.
#
# The pinned commit needs ElectroBench's PR #60 (merged 2026-11-10): Arch's GLEW is built for GLX, and on a Wayland
# (EGL) context glewInit() loads the GL functions and then returns GLEW_ERROR_NO_GLX_DISPLAY. Scene 1 ignores what it
# returns, scenes 2 to 4 took it for a failure and exited ("glewInit failed"), so before it they only ran through
# Xwayland.
set -euo pipefail

COMMIT=${ELECTROBENCH_COMMIT:-c8c264a}
[ $# -gt 0 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

for host in "$@"; do
    echo "=== $host"
    ssh -o BatchMode=yes "root@$host" COMMIT="$COMMIT" bash -s <<'EOF' || echo "=== $host: FAILED"
set -euo pipefail
pacman -S --needed --noconfirm glew glu sdl2-compat >/dev/null
src=$(mktemp -d /tmp/electrobench.XXXXXX)
trap 'rm -rf "$src"' EXIT
git clone -q https://github.com/deadbeef7/ElectroBench.git "$src"
cd "$src"
git -c advice.detachedHead=false checkout -q "$COMMIT"
nice -n 10 make -j"$(nproc)" >build.log 2>&1 || { tail -20 build.log; exit 1; }
rm -rf /opt/electrobench.new
install -d /opt/electrobench.new
install -m 755 build/ElectroBench /opt/electrobench.new/
cp -r shaders assets LICENSE /opt/electrobench.new/
git rev-parse --short HEAD >/opt/electrobench.new/VERSION
rm -rf /opt/electrobench
mv /opt/electrobench.new /opt/electrobench
echo "installed /opt/electrobench: $(cat /opt/electrobench/VERSION)"
EOF
done
