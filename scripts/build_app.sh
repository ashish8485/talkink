#!/usr/bin/env bash
# Build Söyle.app: xcodebuild (compiles the MLX Metal library) -> assemble bundle
# -> copy the metallib resource bundle into Resources -> ad-hoc codesign.
# Usage: scripts/build_app.sh [Release|Debug]
set -euo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # so multibyte chars tokenize cleanly
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="Talkink"
EXEC="Soyle"   # internal executable name (bundle id continuity) — display name is Talkink
CONFIG="${1:-Release}"
DD="${ROOT}/DerivedData"
PROD="${DD}/Build/Products/${CONFIG}"
APP="${ROOT}/dist/${APP_NAME}.app"

# Dev/QA tooling (recording studio + --vadtest/--dictatetest) is OFF by default so
# shipped builds never include it. SOYLE_DEVTOOLS=1 flips the Package.swift toggle
# on for this build only, then restores it (even on failure, via the trap).
if [ -n "${SOYLE_DEVTOOLS:-}" ]; then
  echo "==> dev tools ENABLED (SOYLE_DEVTOOLS=1), not for release"
  trap 'sed -i "" "s/let soyleDevTools = true/let soyleDevTools = false/" "${ROOT}/Package.swift"' EXIT
  sed -i '' 's/let soyleDevTools = false/let soyleDevTools = true/' "${ROOT}/Package.swift"
fi

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

# Embed Sparkle (auto-update). The executable references @rpath/Sparkle.framework.
if [ -d "${PROD}/Sparkle.framework" ]; then
  mkdir -p "${APP}/Contents/Frameworks"
  cp -R "${PROD}/Sparkle.framework" "${APP}/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP}/Contents/MacOS/${EXEC}" 2>/dev/null || true
else
  echo "xx Sparkle.framework not found in build products - aborting"
  exit 1
fi

echo "==> codesign (hardened runtime + entitlements — required for notarization)"
SIGN_ID="${SOYLE_SIGN_IDENTITY:-}"
if [ -z "${SIGN_ID}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  SIGN_ID="Developer ID Application"
fi
if [ -z "${SIGN_ID}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Soyle Dev"; then
  SIGN_ID="Soyle Dev"
fi
ENTITLEMENTS="${ROOT}/packaging/Soyle.entitlements"
# A secure timestamp is required for notarization but needs a real CA-backed
# identity; skip it for ad-hoc/self-signed dev builds.
TS_FLAG="--timestamp=none"
case "${SIGN_ID}" in "Developer ID"*) TS_FLAG="--timestamp" ;; esac
# No --deep: Apple deprecated it; nested components are signed individually,
# inside-out (Sparkle's pre-signed pieces must be re-signed with OUR identity
# for notarization — the procedure from Sparkle's sandboxing/signing docs).
SIGN_TARGET="${SIGN_ID:--}"
[ -z "${SIGN_ID}" ] && echo "    ad-hoc (run scripts/dev_sign_setup.sh for a stable identity that survives rebuilds)" \
                    || echo "    identity: ${SIGN_ID}"
SPARKLE_FW="${APP}/Contents/Frameworks/Sparkle.framework"
if [ -d "${SPARKLE_FW}" ]; then
  while IFS= read -r -d '' nested; do
    codesign --force --options runtime "${TS_FLAG}" \
      --preserve-metadata=entitlements --sign "${SIGN_TARGET}" "${nested}"
  done < <(find "${SPARKLE_FW}/Versions/B/XPCServices" -name "*.xpc" -maxdepth 1 -print0 2>/dev/null)
  [ -f "${SPARKLE_FW}/Versions/B/Autoupdate" ] && \
    codesign --force --options runtime "${TS_FLAG}" --sign "${SIGN_TARGET}" "${SPARKLE_FW}/Versions/B/Autoupdate"
  [ -d "${SPARKLE_FW}/Versions/B/Updater.app" ] && \
    codesign --force --options runtime "${TS_FLAG}" --sign "${SIGN_TARGET}" "${SPARKLE_FW}/Versions/B/Updater.app"
  codesign --force "${TS_FLAG}" --sign "${SIGN_TARGET}" "${SPARKLE_FW}"
fi
codesign --force --options runtime "${TS_FLAG}" \
  --entitlements "${ENTITLEMENTS}" --sign "${SIGN_TARGET}" "${APP}"
codesign --verify --strict "${APP}" && echo "    signature verified"

echo "OK built ${APP}"
du -sh "${APP}" | sed 's/^/  size: /'
echo "  self-test:  \"${APP}/Contents/MacOS/${EXEC}\" --selftest <audio.wav>"
echo "  launch:     open \"${APP}\""
