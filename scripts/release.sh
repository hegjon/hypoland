#!/bin/bash
# Release a new version of Hypoland.
#
#   scripts/release.sh [--dry-run] [--skip-build] [--yes] <version>
#
# 1. Checks: on master, no uncommitted changes, the same as origin/master, the tag is free, CHANGELOG.md has an
#    "Unreleased" section and CI passed for the newest commit it built on master.
# 2. Writes the version into VERSION, CHANGELOG.md ("Unreleased" becomes "<version> - <date>") and AGENTS.md,
#    commits "Release <version>" and tags it v<version> (annotated, "Hypoland <version>").
# 3. Builds the Arch package from scratch (makepkg -fC in packaging/arch) and resets the PKGBUILD.
# 4. Writes the release notes from the CHANGELOG.md section to packaging/arch/release-notes-v<version>.md.
# 5. Asks, then pushes master and the tag together and publishes the GitHub release with the package attached.
#    The release workflow adds the source tarball; the script waits for it and checks that it is there.
#
# Nothing leaves this machine before the question in step 5. Answering no, an error or Ctrl-C before the push
# removes the commit and the tag again. --dry-run does steps 1-4 and then removes them, --skip-build (only with
# --dry-run) leaves out the package. --yes does not ask. The X200 is not touched, install the package there
# yourself.
set -eu

REPO=hegjon/hypoland
DRY=0 SKIP_BUILD=0 YES=0 NEW=
for arg in "$@"; do
    case $arg in
    --dry-run) DRY=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --yes) YES=1 ;;
    -h | --help)
        sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"
        exit 0
        ;;
    -*)
        echo "unknown option $arg" >&2
        exit 2
        ;;
    *) NEW=$arg ;;
    esac
done

die() {
    echo "error: $*" >&2
    exit 1
}
step() { printf '\n==> %s\n' "$*"; }

[ -n "$NEW" ] || die "usage: $0 [--dry-run] [--skip-build] [--yes] <version>"
[[ $NEW =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the version must look like 0.2.0, not $NEW"
[ "$SKIP_BUILD" = 0 ] || [ "$DRY" = 1 ] || die "--skip-build only works with --dry-run"

ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$ROOT"
TAG=v$NEW
OLD=$(cat VERSION)
BASE=$(cat VERSION_HYPRLAND)
TODAY=$(date +%F)
NOTES=$ROOT/packaging/arch/release-notes-$TAG.md

# --- 1. checks
step "Checking"
for tool in git gh makepkg hyprwayland-scanner; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
done
[ "$(printf '%s\n%s\n' "$OLD" "$NEW" | sort -V | tail -1)" = "$NEW" ] && [ "$OLD" != "$NEW" ] ||
    die "$NEW is not newer than the current version $OLD"
[ "$(git branch --show-current)" = master ] || die "not on master"
git diff --quiet HEAD -- || die "uncommitted changes: $(git diff --name-only HEAD -- | tr '\n' ' ')"
git fetch -q origin master
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] ||
    die "master and origin/master differ, push or pull first"
# The local repository also has the tags of upstream Hyprland and possibly aquamarine, some of which use the
# same names as Hypoland versions
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null &&
    die "the tag $TAG exists locally ($(git log -1 --format='%h %an: %s' "$TAG")), delete it with git tag -d $TAG if it is not Hypoland's"
[ -z "$(git ls-remote --tags origin "refs/tags/$TAG")" ] || die "the tag $TAG is already on origin"
gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 && die "GitHub already has a release $TAG"

grep -q '^## Unreleased$' CHANGELOG.md || die 'CHANGELOG.md has no "## Unreleased" section'
SECTION=$(awk '/^## Unreleased$/ { on = 1; next } on && /^## / { exit } on' CHANGELOG.md)
[ -n "$(echo "$SECTION" | tr -d '[:space:]')" ] || die 'the "Unreleased" section of CHANGELOG.md is empty'

# CI skips commits that only change the web page or text, so check the newest run on master. A run for HEAD
# itself has to be finished.
HEAD_SHA=$(git rev-parse HEAD)
RUNS=$(gh run list -R "$REPO" -w ci.yaml -b master -e push -L 30 --json headSha,status,conclusion,url \
    --jq '.[] | [.headSha, .status, .conclusion, .url] | join("|")')
RUN=$(echo "$RUNS" | awk -F"|" -v sha="$HEAD_SHA" '$1 == sha' | head -1)
[ -n "$RUN" ] || RUN=$(echo "$RUNS" | head -1)
[ -n "$RUN" ] || die "no CI run on master found"
IFS="|" read -r RUN_SHA RUN_STATUS RUN_CONCLUSION RUN_URL <<<"$RUN"
[ "$RUN_STATUS" = completed ] || die "CI is still running for ${RUN_SHA:0:9}, wait for it: $RUN_URL"
[ "$RUN_CONCLUSION" = success ] || die "CI failed for ${RUN_SHA:0:9}: $RUN_URL"
if [ "$RUN_SHA" = "$HEAD_SHA" ]; then
    echo "CI passed for HEAD ${HEAD_SHA:0:9}"
else
    echo "CI passed for ${RUN_SHA:0:9}, the newest commit it built; later commits changed no code"
    git diff --stat "$RUN_SHA" HEAD | tail -1
fi
echo "Hypoland $OLD -> $NEW, based on Hyprland $BASE"

# --- 2. version, changelog, commit and tag
step "Committing the release and tagging $TAG"
START=$HEAD_SHA CREATED=0 PUSHED=0
cleanup() {
    git checkout -q -- packaging/arch/PKGBUILD 2>/dev/null || true
    [ "$CREATED" = 1 ] && [ "$PUSHED" = 0 ] || return 0
    echo "Removing the release commit and the tag $TAG again"
    git tag -d "$TAG" >/dev/null 2>&1 || true
    git reset -q --keep "$START"
}
trap cleanup EXIT
# a closed pipe (| head) or a lost terminal would otherwise kill the script before cleanup undoes the release commit
trap 'exit 130' INT TERM HUP PIPE

echo "$NEW" >VERSION
sed -i "s/^## Unreleased$/## $NEW - $TODAY/" CHANGELOG.md
sed -i -E "s/^Hypoland [0-9.]+ is based on Hyprland [0-9.]+\./Hypoland $NEW is based on Hyprland $BASE./" CHANGELOG.md
sed -i -E "s/\(([0-9.]+), the package$/($NEW, the package/; s/\`Hypoland [0-9.]+, based on Hyprland [0-9.]+\`/\`Hypoland $NEW, based on Hyprland $BASE\`/" AGENTS.md
CREATED=1
git commit -q -m "Release $NEW" -- VERSION CHANGELOG.md AGENTS.md
git tag -a "$TAG" -m "Hypoland $NEW"
git show --stat --format='%h %s' HEAD | cat

# --- 3. package
# the PKGBUILD names a build at the release tag with the plain version
PKG=hypoland-$NEW-1-x86_64.pkg.tar.zst
# the same build's second package: the benchmark, the checks and the soak scripts of the test machines
BENCH_PKG=hypoland-bench-$NEW-1-x86_64.pkg.tar.zst
if [ "$SKIP_BUILD" = 1 ]; then
    step "Skipping the package build"
else
    step "Building the Arch package (a clean build, about 15 minutes)"
    LOG=$ROOT/packaging/arch/makepkg-$TAG.log
    (cd packaging/arch && makepkg -fC >"$LOG" 2>&1) || die "makepkg failed, see $LOG"
    git checkout -q -- packaging/arch/PKGBUILD
    [ -f "packaging/arch/$PKG" ] || die "makepkg did not write packaging/arch/$PKG"
    [ -f "packaging/arch/$BENCH_PKG" ] || die "makepkg did not write packaging/arch/$BENCH_PKG"
    echo "packaging/arch/$PKG ($(du -h "packaging/arch/$PKG" | cut -f1)), packaging/arch/$BENCH_PKG ($(du -h "packaging/arch/$BENCH_PKG" | cut -f1))"
    # what the packaged binary says about itself: the version, the tag and no uncommitted changes
    tmp=$(mktemp -d)
    bsdtar -xf "packaging/arch/$PKG" -C "$tmp" usr/bin/hypoland
    version=$("$tmp/usr/bin/hypoland" --version 2>&1 || true)
    rm -rf "$tmp"
    echo "$version" | sed 's/^/  /'
    echo "$version" | grep -qF "Hypoland $NEW, based on Hyprland $BASE" &&
        echo "$version" | grep -qF "Tag: $TAG," && echo "$version" | grep -q " clean (" ||
        die "the hypoland binary of the package does not report version $NEW, tag $TAG and a clean tree"
    # Omarchy's session starts this file, a wrong prefix leaves a black screen
    bsdtar -xOf "packaging/arch/$PKG" usr/share/wayland-sessions/hyprland.desktop | grep -qx "Exec=/usr/bin/start-hypoland" ||
        die "the session file of the package does not start /usr/bin/start-hypoland"
fi

# --- 4. release notes
step "Writing the release notes"
libs=$(pacman -Q hyprutils hyprlang hyprcursor hyprgraphics hyprwire | awk '{ sub(/-[0-9]+$/, "", $2); printf "%s%s %s", sep, $1, $2; sep = ", " }')
{
    echo "Hypoland $NEW, based on Hyprland $BASE. Hypoland is a fork of [Hyprland](https://github.com/hyprwm/Hyprland) for old GPUs that only support OpenGL ES 2.0 / OpenGL 2.1, developed and tested on a ThinkPad X200 (GMA 4500MHD) running Omarchy."
    echo
    # one line per paragraph: GitHub keeps the line breaks of the changelog
    echo "$SECTION" | sed 's/^### /## /' | awk '
        !started && /^$/ { next }
        { started = 1 }
        /^$/ || /^#/ { if (p != "") print p; p = ""; print; next }
        /^ *- / { if (p != "") print p; p = $0; next }
        { sub(/^ +/, ""); p = p " " $0 }
        END { if (p != "") print p }' | cat -s
    cat <<EOF

## Install

On Arch Linux, download \`$PKG\` below and install it with:

\`\`\`sh
sudo pacman -U $PKG
\`\`\`

It provides and conflicts with \`hyprland\`, so it replaces the installed Hyprland; Omarchy's session starts it unchanged. It is built for baseline \`x86-64\` against the Arch packages of $TODAY ($libs). If pacman reports newer versions of these libraries, build the package yourself in \`packaging/arch\` with \`makepkg -f\`.

For other distributions see the [README](https://github.com/$REPO#building), and build for baseline \`x86-64\`, not \`-march=native\`.

The full list of changes is in [CHANGELOG.md](https://github.com/$REPO/blob/$TAG/CHANGELOG.md).

Hypoland is an independent project. It is not affiliated with or endorsed by Hyprland or its developers.
EOF
} >"$NOTES"
echo "$NOTES"
echo "----------------------------------------------------------------------"
cat "$NOTES"
echo "----------------------------------------------------------------------"

if [ "$DRY" = 1 ]; then
    step "Dry run: nothing was pushed"
    exit 0
fi

# --- 5. publish
if [ "$YES" = 0 ]; then
    echo
    echo "Edit $NOTES now if you want to, the release uses the file as it is when you answer."
    read -r -p "Push master and $TAG to origin and publish the release on GitHub? [y/N] " answer
    [ "$answer" = y ] || [ "$answer" = Y ] || exit 1
fi

step "Pushing master and $TAG"
git push --atomic origin master "refs/tags/$TAG"
PUSHED=1

step "Publishing the GitHub release"
gh release create "$TAG" -R "$REPO" --verify-tag --title "Hypoland $NEW" --notes-file "$NOTES" \
    "packaging/arch/$PKG" "packaging/arch/$BENCH_PKG"

step "Waiting for the release workflow to attach the source tarball"
RUN_ID=
for _ in $(seq 30); do
    RUN_ID=$(gh run list -R "$REPO" -w release.yaml -e release -L 5 --json databaseId,headBranch \
        --jq ".[] | select(.headBranch == \"$TAG\") | .databaseId" | head -1)
    [ -n "$RUN_ID" ] && break
    sleep 5
done
[ -n "$RUN_ID" ] || die "the release workflow did not start, run it by hand: gh workflow run release.yaml -R $REPO -f tag=$TAG"
gh run watch "$RUN_ID" -R "$REPO" --exit-status >/dev/null || die "the release workflow failed: gh run view $RUN_ID -R $REPO --log-failed"
gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name' | grep -qx "hypoland-source-$TAG.tar.gz" ||
    die "the source tarball is missing from the release"

step "Released Hypoland $NEW"
gh release view "$TAG" -R "$REPO" --json url,assets --jq '.url, (.assets[] | "  " + .name)'
