#!/bin/bash
#
# Cut a new Perch release in one command: bump the version, build + sign + zip the app,
# publish a GitHub Release, and update the appcast.
#
#   ./Scripts/release.sh 0.2.0
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version>   e.g. ./Scripts/release.sh 0.2.0}"
TAG="v${VERSION}"
ZIP="/tmp/Perch.zip"
APPCAST="appcast.xml"
DOWNLOAD_URL="https://github.com/maxthegray/Perch/releases/download/${TAG}/Perch.zip"

# Sparkle's sign_update tool (fetched by SwiftPM alongside the Sparkle framework).
SIGN_UPDATE="$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1)"
[ -n "${SIGN_UPDATE}" ] || { echo "sign_update not found -- run 'swift build -c release' first"; exit 1; }

# 1. Stamp the version into the bundle.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" Resources/Info.plist

# 2. Build + zip, then hash.
./Scripts/build-app.sh
rm -f "${ZIP}"
ditto -c -k --keepParent Perch.app "${ZIP}"
SHA="$(shasum -a 256 "${ZIP}" | awk '{print $1}')"
echo "sha256: ${SHA}"

# 3. Commit the version bump on the app repo.
if ! git diff --quiet Resources/Info.plist; then
  git add Resources/Info.plist
  git commit -m "Release ${TAG}"
  git push origin HEAD
fi

# 4. Publish the GitHub Release.
gh release create "${TAG}" "${ZIP}" \
  --repo maxthegray/Perch \
  --target main \
  --title "Perch ${VERSION}" \
  --notes "Download \`Perch.zip\`, unzip, and drag to /Applications. Right-click ▸ Open once (or \`xattr -dr com.apple.quarantine /Applications/Perch.app\`) to clear the Gatekeeper prompt."

# 4b. Sign the zip with Sparkle's EdDSA key and regenerate the appcast so existing
#     installs auto-update. The feed lives on main (SUFeedURL points at raw.github).
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
git add "${APPCAST}"
git commit -m "Appcast ${TAG}"
git push origin HEAD

echo "Released ${TAG}."
