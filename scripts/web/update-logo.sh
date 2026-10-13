#!/bin/sh
# Copies the logo from assets/logo/ into web/ and renders the link preview image web/og.png.
# Run it after regenerating the logo with scripts/logo/retro.py.
set -e
cd "$(dirname "$0")/../.."
cp assets/logo/header.svg web/header.svg
cp assets/logo/hypoland.svg web/icon.svg
cp assets/logo/hypoland-32.png web/favicon.png
scripts/web/og.sh
