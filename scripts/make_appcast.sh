#!/usr/bin/env bash
# Generate appcast.xml (the Sparkle update feed) for the latest release.
#
# One-time setup:
#   BIN=$(ls -d DerivedData/SourcePackages/artifacts/sparkle*/Sparkle/bin | head -1)
#   "$BIN/generate_keys"     # prints the public key → paste into
#                            # packaging/Info.plist (SUPublicEDKey).
#                            # The private key stays in your login keychain.
#
# Per release (AFTER the GitHub release with Soyle.zip exists):
#   scripts/make_appcast.sh v0.3.0 dist/Soyle.zip
#   git add appcast.xml && git commit -m "release: appcast for v0.3.0" && git push
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: make_appcast.sh vX.Y.Z path/to/Soyle.zip}"
ZIP="${2:?usage: make_appcast.sh vX.Y.Z path/to/Soyle.zip}"
VER="${TAG#v}"
BIN=$(ls -d DerivedData/SourcePackages/artifacts/sparkle*/Sparkle/bin 2>/dev/null | head -1)
[ -n "${BIN}" ] || { echo "xx Sparkle tools not found — run scripts/build_app.sh once first"; exit 1; }
[ -f "${ZIP}" ] || { echo "xx ${ZIP} not found"; exit 1; }

# Prints: sparkle:edSignature="…" length="…" (needs the private key in the keychain)
SIG_ATTRS=$("${BIN}/sign_update" "${ZIP}")
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" packaging/Info.plist)
PUBDATE=$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Söyle</title>
    <item>
      <title>Söyle ${VER}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD_NUM}</sparkle:version>
      <sparkle:shortVersionString>${VER}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/hasso5703/soyle/releases/tag/${TAG}</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/hasso5703/soyle/releases/download/${TAG}/Soyle.zip"
        ${SIG_ATTRS}
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST
echo "OK appcast.xml written for ${TAG} — commit & push AFTER the GitHub release exists."
