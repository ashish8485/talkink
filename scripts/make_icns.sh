#!/usr/bin/env bash
# Generate packaging/AppIcon.icns from scripts/make_icon.swift (all iconset sizes).
set -euo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
cd "$(dirname "$0")/.."

SET="$(mktemp -d)/Soyle.iconset"
mkdir -p "${SET}" packaging
gen() { swift scripts/make_icon.swift "$1" "$2"; }

gen 16   "${SET}/icon_16x16.png"
gen 32   "${SET}/icon_16x16@2x.png"
gen 32   "${SET}/icon_32x32.png"
gen 64   "${SET}/icon_32x32@2x.png"
gen 128  "${SET}/icon_128x128.png"
gen 256  "${SET}/icon_128x128@2x.png"
gen 256  "${SET}/icon_256x256.png"
gen 512  "${SET}/icon_256x256@2x.png"
gen 512  "${SET}/icon_512x512.png"
gen 1024 "${SET}/icon_512x512@2x.png"

iconutil -c icns "${SET}" -o packaging/AppIcon.icns
echo "wrote packaging/AppIcon.icns ($(stat -f%z packaging/AppIcon.icns) bytes)"
