#!/bin/bash
#
# Cut a new Perch release in one command: bump the version, build + sign + zip the app,
# publish a GitHub Release, and update the Homebrew cask.
#
#   ./Scripts/release.sh 0.2.0
#
# The Homebrew tap is expected at ../homebrew-tap (override with PERCH_TAP_DIR).
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version>   e.g. ./Scripts/release.sh 0.2.0}"
TAG="v${VERSION}"
ZIP="/tmp/Perch.zip"
TAP_DIR="${PERCH_TAP_DIR:-../homebrew-tap}"
CASK="${TAP_DIR}/Casks/perch.rb"

[ -f "${CASK}" ] || { echo "Cask not found at ${CASK} (set PERCH_TAP_DIR)"; exit 1; }

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

# 4. Publish the GitHub Release (asset must be named Perch.zip to match the cask URL).
gh release create "${TAG}" "${ZIP}" \
  --repo maxthegray/Perch \
  --target main \
  --title "Perch ${VERSION}" \
  --notes "Install: \`brew tap maxthegray/tap && brew trust --cask maxthegray/tap/perch && brew install --cask perch\`, then \`xattr -dr com.apple.quarantine /Applications/Perch.app\` (or right-click ▸ Open once)."

# 5. Point the cask at the new version + hash and push the tap.
sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "${CASK}"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "${CASK}"
git -C "${TAP_DIR}" add Casks/perch.rb
git -C "${TAP_DIR}" commit -m "perch ${VERSION}"
git -C "${TAP_DIR}" push origin HEAD

echo "Released ${TAG} and updated the Homebrew cask."
