#!/bin/sh
# Export the web build and zip it for itch.io
set -e
cd "$(dirname "$0")"
G="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
rm -rf build/web && mkdir -p build/web
"$G" --headless --import >/dev/null 2>&1 || true
"$G" --headless --export-release "Web" build/web/index.html
(cd build/web && rm -f ../night-broom-web.zip && zip -qr ../night-broom-web.zip .)
ls -la build/night-broom-web.zip
