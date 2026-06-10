#!/usr/bin/env bash
# Notarize + staple dist/Söyle.app and produce the distributable Soyle.zip.
#
# One-time setup (after enrolling in the Apple Developer Program):
#   1. Xcode → Settings → Accounts → your Apple ID → Manage Certificates…
#      → "+" → "Developer ID Application"  (build_app.sh picks it up automatically)
#   2. Create an app-specific password at https://account.apple.com
#      → Sign-In and Security → App-Specific Passwords
#   3. Store the credentials once (TEAMID is on https://developer.apple.com/account):
#        xcrun notarytool store-credentials soyle-notary \
#          --apple-id YOU@EXAMPLE.COM --team-id TEAMID --password app-specific-pw
#
# Then per release:  scripts/build_app.sh Release && scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Söyle.app"
PROFILE="${SOYLE_NOTARY_PROFILE:-soyle-notary}"
OUT_ZIP="${1:-dist/Soyle.zip}"

[ -d "${APP}" ] || { echo "xx ${APP} not found — run scripts/build_app.sh Release first"; exit 1; }

# Notarization requires a Developer ID signature + hardened runtime + timestamp.
# (Capture once: `grep -q` in a pipefail pipeline SIGPIPEs codesign on match.
#  -dvv, not -dv: the Authority= lines only print at the second verbosity level.)
SIGN_INFO="$(codesign -dvv "${APP}" 2>&1)"
echo "${SIGN_INFO}" | grep -q "flags=0x10000(runtime)" \
  || { echo "xx hardened runtime missing — rebuild with current build_app.sh"; exit 1; }
echo "${SIGN_INFO}" | grep -q "Authority=Developer ID Application" \
  || { echo "xx not signed with a Developer ID Application identity"; exit 1; }

echo "==> uploading for notarization (profile: ${PROFILE})"
ditto -c -k --keepParent "${APP}" /tmp/soyle_notarize_upload.zip
xcrun notarytool submit /tmp/soyle_notarize_upload.zip \
  --keychain-profile "${PROFILE}" --wait \
  || { echo "xx notarization failed — inspect with: xcrun notarytool log <submission-id> --keychain-profile ${PROFILE}"; exit 1; }

echo "==> stapling the ticket to the app"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

echo "==> Gatekeeper assessment (what a user's Mac will decide)"
spctl --assess --type execute -vv "${APP}"

echo "==> packaging the stapled app"
ditto -c -k --keepParent "${APP}" "${OUT_ZIP}"

echo "==> building + notarizing the drag-to-Applications DMG"
scripts/make_dmg.sh dist/Soyle.dmg
DEV_ID="$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed 's/^[^"]*"//; s/"$//')"
codesign --force --timestamp --sign "${DEV_ID}" dist/Soyle.dmg
xcrun notarytool submit dist/Soyle.dmg --keychain-profile "${PROFILE}" --wait \
  || { echo "xx DMG notarization failed"; exit 1; }
xcrun stapler staple dist/Soyle.dmg
spctl --assess --type open --context context:primary-signature -vv dist/Soyle.dmg

echo "OK notarized + stapled:"
echo "   dist/Soyle.dmg  → human downloads (GitHub release)"
echo "   ${OUT_ZIP}  → Sparkle update feed (GitHub release + make_appcast.sh)"
