#!/usr/bin/env bash
# Build Söyle.app: xcodebuild (compiles the MLX Metal library) -> assemble bundle
# -> copy the metallib resource bundle into Resources -> ad-hoc codesign.
# Usage: scripts/build_app.sh [Release|Debug]
set -euo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # so multibyte chars tokenize cleanly
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="Söyle"
EXEC="Soyle"
CONFIG="${1:-Release}"
DD="${ROOT}/DerivedData"
PROD="${DD}/Build/Products/${CONFIG}"
APP="${ROOT}/dist/${APP_NAME}.app"

echo "==> xcodebuild (${CONFIG}) - compiles Swift + MLX C++ + Metal shaders"
xcodebuild -scheme "${EXEC}" -configuration "${CONFIG}" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "${DD}" build >/tmp/soyle_build.log 2>&1 \
  || { echo "xx build failed:"; tail -60 /tmp/soyle_build.log; exit 1; }

[ -x "${PROD}/${EXEC}" ] || { echo "xx no executable at ${PROD}/${EXEC}"; exit 1; }

echo "==> assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${PROD}/${EXEC}" "${APP}/Contents/MacOS/${EXEC}"
cp "${ROOT}/packaging/Info.plist" "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"
[ -f "${ROOT}/packaging/AppIcon.icns" ] && cp "${ROOT}/packaging/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

# Copy ALL SwiftPM resource bundles (mlx-swift_Cmlx has the REQUIRED default.metallib).
shopt -s nullglob
for b in "${PROD}"/*.bundle; do
  cp -R "${b}" "${APP}/Contents/Resources/"
done
shopt -u nullglob

if [ ! -d "${APP}/Contents/Resources/mlx-swift_Cmlx.bundle" ]; then
  echo "xx mlx-swift_Cmlx.bundle (Metal library) not found in build products - aborting"
  exit 1
fi

echo "==> codesign"
SIGN_ID="${SOYLE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_ID}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Soyle Dev"; then
  SIGN_ID="Soyle Dev"
fi
if [ -n "${SIGN_ID}" ]; then
  echo "    stable identity: ${SIGN_ID}"
  codesign --force --deep --sign "${SIGN_ID}" "${APP}"
else
  echo "    ad-hoc (run scripts/dev_sign_setup.sh for a stable identity that survives rebuilds)"
  codesign --force --deep --sign - "${APP}"
fi

echo "OK built ${APP}"
du -sh "${APP}" | sed 's/^/  size: /'
echo "  self-test:  \"${APP}/Contents/MacOS/${EXEC}\" --selftest <audio.wav>"
echo "  launch:     open \"${APP}\""
