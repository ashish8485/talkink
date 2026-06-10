#!/usr/bin/env bash
# Build the drag-to-Applications DMG from dist/Söyle.app, with the visual
# install layout (background + positioned icons) via dmgbuild.
# Called by notarize.sh (which then notarizes + staples the DMG itself).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Söyle.app"
OUT="${1:-dist/Soyle.dmg}"
[ -d "${APP}" ] || { echo "xx ${APP} not found — run scripts/build_app.sh Release first"; exit 1; }
rm -f "${OUT}"

if python3 -c "import dmgbuild" 2>/dev/null; then
  python3 -m dmgbuild -s packaging/dmg_settings.py -D app="${APP}" "Söyle" "${OUT}"
else
  echo "!! dmgbuild missing (pip3 install --user dmgbuild) — plain DMG fallback, no visual layout"
  STAGE="$(mktemp -d)"
  cp -R "${APP}" "${STAGE}/"
  ln -s /Applications "${STAGE}/Applications"
  hdiutil create -volname "Söyle" -srcfolder "${STAGE}" -ov -format UDZO -quiet "${OUT}"
  rm -rf "${STAGE}"
fi
echo "OK ${OUT}"
