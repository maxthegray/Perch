#!/bin/bash
#
# Cut a new Perch release in one command: bump the version, build + Developer ID
# sign, notarize, staple, zip, publish a GitHub Release, and update the appcast.
#
#   ./Scripts/release.sh 0.2.0
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version>   e.g. ./Scripts/release.sh 0.2.0}"
TAG="v${VERSION}"
ZIP="/tmp/Perch.zip"
NOTARY_ZIP="/tmp/Perch-notary.zip"
APPCAST="appcast.xml"
DOWNLOAD_URL="https://github.com/maxthegray/Perch/releases/download/${TAG}/Perch.zip"
NOTARY_PROFILE="${PERCH_NOTARY_PROFILE:-PerchNotary}"

# 1. Stamp the version into the bundle.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" Resources/Info.plist

# 2. Build with Developer ID, hardened runtime, and secure timestamps.
PERCH_DISTRIBUTION=1 ./Scripts/build-app.sh

# Sparkle's sign_update tool is fetched by SwiftPM alongside the framework.
SIGN_UPDATE="$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1)"
[ -n "${SIGN_UPDATE}" ] || { echo "sign_update not found after release build"; exit 1; }

# 3. Submit a ZIP to Apple, then staple the resulting ticket to the app. ZIP files
# cannot themselves be stapled, so the final distributable is created afterward.
rm -f "${NOTARY_ZIP}"
ditto -c -k --keepParent Perch.app "${NOTARY_ZIP}"
xcrun notarytool submit "${NOTARY_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
xcrun stapler staple Perch.app
xcrun stapler validate Perch.app

# 4. Verify Gatekeeper acceptance and create the final, stapled update archive.
codesign --verify --deep --strict --verbose=2 Perch.app
spctl --assess --type execute --verbose=4 Perch.app
rm -f "${ZIP}"
ditto -c -k --keepParent Perch.app "${ZIP}"
SHA="$(shasum -a 256 "${ZIP}" | awk '{print $1}')"
echo "sha256: ${SHA}"

# 5. Sign the final ZIP with Sparkle's EdDSA key and regenerate the appcast.
SIG_ATTRS="$(${SIGN_UPDATE} "${ZIP}")"   # sparkle:edSignature="..." length="..."
PUBDATE="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")"
cat > "${APPCAST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Perch</title>
    <link>${DOWNLOAD_URL}</link>
    <description>Auto-update feed for Perch.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="${DOWNLOAD_URL}" ${SIG_ATTRS} type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

# 6. Commit release metadata before publishing so the appcast exists on main.
git add Resources/Info.plist "${APPCAST}"
git commit -m "Release ${TAG}"
git push origin HEAD

# 7. Publish the notarized, stapled archive.
gh release create "${TAG}" "${ZIP}" \
  --repo maxthegray/Perch \
  --target main \
  --title "Perch ${VERSION}" \
  --notes "Download \`Perch.zip\`, unzip, and drag Perch to /Applications. Perch is signed and notarized by Apple."

echo "Released ${TAG}."
