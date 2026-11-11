#!/bin/bash
# Builds Yamagi Quake II (github.com/yquake2/yquake2, GPL-2, not in Arch's repositories) with its Vulkan renderer on the
# test machines and installs it with the data of id's Quake II demo into /opt/yquake2, where the benchmark's yquake2-*
# workloads (scripts/bench/lib/workloads.sh) look for it:
#
#   scripts/machines/yquake2.sh <ssh host>...    over ssh as root, one machine after the other
#
# The versions are Phoronix's (its test profile pts/yquake2-1.3.0): yquake2 8.10 with the OpenGL 1.4, OpenGL 3.2, GLES 3
# and software renderers, ref_vk 1.0.2, and pak0.pak of the 3.14 demo, which has the demo q2demo1.dm2 its timedemo plays;
# the downloads are checked against the profile's SHA-256. Built on each machine, so the aarch64 ones get theirs too;
# gcc and make come with Omarchy, the libraries are installed with pacman.
set -euo pipefail

[ $# -gt 0 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

for host in "$@"; do
    echo "=== $host"
    ssh -o BatchMode=yes "root@$host" bash -s <<'EOF' || echo "=== $host: FAILED"
set -euo pipefail
pacman -S --needed --noconfirm sdl2-compat openal curl vulkan-headers vulkan-icd-loader unzip >/dev/null
src=$(mktemp -d /tmp/yquake2.XXXXXX)
trap 'rm -rf "$src"' EXIT
cd "$src"
fetch() { # file, sha256, url...
    local file=$1 sum=$2 url
    shift 2
    for url in "$@"; do
        curl -fsSL --retry 2 -o "$file" "$url" && echo "$sum  $file" | sha256sum -c --quiet && return 0
    done
    echo "could not download $file"
    return 1
}
fetch yquake2.zip 800722af4ab573644a76efb5150217dc1b8b3b829f51f84b16f7686c20c22304 \
    https://github.com/yquake2/yquake2/archive/refs/tags/QUAKE2_8_10.zip
fetch ref_vk.zip cc6783f8efbf29b9cede2abfac1d3ab233d3af97cf39bb358dfbfcc8767b74ac \
    https://github.com/yquake2/ref_vk/archive/refs/tags/v1.0.2.zip
fetch demo.exe 7ace5a43983f10d6bdc9d9b6e17a1032ba6223118d389bd170df89b945a04a1e \
    https://deponie.yamagi.org/quake2/idstuff/q2-314-demo-x86.exe \
    https://master.dl.sourceforge.net/project/dcquake/quake2/demo/q2-314-demo-x86.exe
unzip -q yquake2.zip
unzip -q ref_vk.zip
unzip -q demo.exe 'Install/Data/baseq2/pak0.pak' 'Install/Data/baseq2/players/*' || [ -s Install/Data/baseq2/pak0.pak ]
(cd yquake2-QUAKE2_8_10 && nice -n 10 make -j"$(nproc)" >"$src/build.log" 2>&1) || { tail -20 build.log; exit 1; }
(cd ref_vk-1.0.2 && nice -n 10 make -j"$(nproc)" >"$src/build-vk.log" 2>&1) || { tail -20 build-vk.log; exit 1; }
rel=yquake2-QUAKE2_8_10/release
cp ref_vk-1.0.2/release/ref_vk.so "$rel/"
cp -r Install/Data/baseq2/pak0.pak Install/Data/baseq2/players "$rel/baseq2/"
cp yquake2-QUAKE2_8_10/LICENSE "$rel/LICENSE"
echo "8.10, ref_vk 1.0.2, Quake II 3.14 demo data" >"$rel/VERSION"
rm -rf /opt/yquake2.new
cp -r "$rel" /opt/yquake2.new
chmod -R a+rX /opt/yquake2.new
rm -rf /opt/yquake2
mv /opt/yquake2.new /opt/yquake2
echo "installed /opt/yquake2: $(ls /opt/yquake2 | tr '\n' ' ')"
EOF
done
