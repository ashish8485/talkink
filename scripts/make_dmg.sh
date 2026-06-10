#!/usr/bin/env bash
# Build the drag-to-Applications DMG from dist/Söyle.app.
# Called by notarize.sh (which then notarizes + staples the DMG itself).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Söyle.app"
OUT="${1:-dist/Soyle.dmg}"
[ -d "${APP}" ] || { echo "xx ${APP} not found — run scripts/build_app.sh Release first"; exit 1; }

STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
rm -f "${OUT}"
hdiutil create -volname "Söyle" -srcfolder "${STAGE}" -ov -format UDZO -quiet "${OUT}"
rm -rf "${STAGE}"
echo "OK ${OUT}"
