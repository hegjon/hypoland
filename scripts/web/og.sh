#!/bin/sh
# Renders scripts/web/og.html into web/og.png (1200x630) with Playwright's Chromium (needs Node.js; the first
# time, fetch the browser with: npx playwright@1.49.1 install chromium).
# A plain `chromium --headless --screenshot` cuts the page off, its viewport is smaller than the window.
set -e
cd "$(dirname "$0")/../.."
npx --yes playwright@1.49.1 screenshot --browser=chromium --viewport-size=1200,630 \
    "file://$PWD/scripts/web/og.html" web/og.png
