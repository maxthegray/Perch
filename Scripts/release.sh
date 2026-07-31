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
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be MAJOR.MINOR.PATCH"
  exit 1
fi

IFS=. read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "${VERSION}"
BUILD=$((10#${VERSION_MAJOR} * 1000000 + 10#${VERSION_MINOR} * 10000 + 10#${VERSION_PATCH} * 10))
TAG="v${VERSION}"
ZIP="/tmp/Perch.zip"
NOTARY_ZIP="/tmp/Perch-notary.zip"
ASSET_NAME="Perch.zip"
TARGET_BRANCH="main"
RELEASE_TITLE="Perch ${VERSION}"

CURRENT_BRANCH="$(git branch --show-current)"
if [ "${CURRENT_BRANCH}" != "${TARGET_BRANCH}" ]; then
  echo "error: releases must be cut from ${TARGET_BRANCH}, not ${CURRENT_BRANCH}"
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "error: release requires a clean worktree"
  exit 1
fi
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "error: tag ${TAG} already exists"
  exit 1
fi

APPCAST="appcast.xml"
DOWNLOAD_URL="https://github.com/maxthegray/Perch/releases/download/${TAG}/${ASSET_NAME}"
NOTARY_PROFILE="${PERCH_NOTARY_PROFILE:-PerchNotary}"

# What changed, written once in Resources/ReleaseNotes.json and published three ways: the
# app's What's New window reads the bundled copy, the appcast description below is what
# Sparkle shows *before* installing, and the same words become the release body. Resolved
# now, before anything is built or notarized, so a release with no notes fails in a second
# rather than after a trip to Apple.
NOTES_HTML="$(python3 Scripts/release-notes.py "${VERSION}" --format html)"
NOTES_MARKDOWN="$(python3 Scripts/release-notes.py "${VERSION}" --format markdown)"

# Refuse to publish a commit CI has not vouched for. The `swift test` below runs on
# whatever toolchain this machine happens to have; CI runs the one that decides whether
# the project builds for everyone else. v1.0.0 shipped from a commit whose *test target
# did not compile* on CI — a green local run is exactly what hid it, so a green local run
# is no longer enough on its own.
#
# PERCH_SKIP_CI_CHECK=1 bypasses this for an emergency release from a machine that cannot
# reach GitHub. It is a deliberate override, not a default.
if [ "${PERCH_SKIP_CI_CHECK:-0}" = "1" ]; then
  echo "WARNING: skipping the CI check at your request — nothing has verified this commit"
else
  HEAD_SHA="$(git rev-parse HEAD)"
  git fetch --quiet origin "${TARGET_BRANCH}"
  if [ "$(git rev-parse "origin/${TARGET_BRANCH}")" != "${HEAD_SHA}" ]; then
    echo "error: origin/${TARGET_BRANCH} does not point at HEAD (${HEAD_SHA:0:7})."
    echo "       Push first, so CI runs on the commit this release would publish."
    exit 1
  fi

  echo "Checking CI on ${HEAD_SHA:0:7}..."
  CI_DEADLINE=$((SECONDS + 1800))
  CI_APPEARS_BY=$((SECONDS + 300))
  while :; do
    CI_RESULT="$(gh run list --repo maxthegray/Perch --workflow CI --commit "${HEAD_SHA}" \
      --limit 1 --json status,conclusion \
      --jq '.[0] | "\(.status)/\(.conclusion // "pending")"' 2>/dev/null || true)"
    case "${CI_RESULT}" in
      completed/success)
        echo "CI passed on ${HEAD_SHA:0:7}."
        break
        ;;
      completed/*)
        echo "error: CI concluded '${CI_RESULT#*/}' on ${HEAD_SHA:0:7}. Fix it before releasing."
        exit 1
        ;;
      ""|null/*|"null")
        # GitHub takes a moment to register a run after a push, so an absent run is
        # "not yet" rather than "never" — but only briefly, because it is also what a
        # commit that never triggered CI looks like.
        if [ "${SECONDS}" -ge "${CI_APPEARS_BY}" ]; then
          echo "error: no CI run for ${HEAD_SHA:0:7} after 5 minutes. Did the workflow trigger?"
          exit 1
        fi
        sleep 20
        ;;
      *)
        if [ "${SECONDS}" -ge "${CI_DEADLINE}" ]; then
          echo "error: CI was still ${CI_RESULT%%/*} on ${HEAD_SHA:0:7} after 30 minutes."
          exit 1
        fi
        sleep 20
        ;;
    esac
  done
fi

swift test

create_release_zip() {
  local destination="$1"

  rm -f "${destination}"
  /usr/bin/zip -qry --symlinks "${destination}" Perch.app

  # Finder metadata stored as AppleDouble files invalidates the sealed root of
  # embedded frameworks when extracted by non-Apple tools (including Chrome's
  # ZIP handling). Never publish an archive containing those entries.
  if /usr/bin/unzip -Z1 "${destination}" | grep -Eq '(^|/)\._|^__MACOSX/'; then
    echo "error: ${destination} contains AppleDouble metadata"
    exit 1
  fi
}

# 1. Stamp the version into the bundle.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" Resources/Info.plist

# 2. Build with Developer ID, hardened runtime, and secure timestamps.
PERCH_DISTRIBUTION=1 ./Scripts/build-app.sh

# Sparkle's sign_update tool is fetched by SwiftPM alongside the framework.
SIGN_UPDATE="$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1)"
[ -n "${SIGN_UPDATE}" ] || { echo "sign_update not found after release build"; exit 1; }

# 3. Submit a ZIP to Apple, then staple the resulting ticket to the app. ZIP files
# cannot themselves be stapled, so the final distributable is created afterward.
create_release_zip "${NOTARY_ZIP}"
xcrun notarytool submit "${NOTARY_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
xcrun stapler staple Perch.app
xcrun stapler validate Perch.app

# 4. Verify Gatekeeper acceptance and create the final, stapled update archive.
codesign --verify --deep --strict --verbose=2 Perch.app
spctl --assess --type execute --verbose=4 Perch.app
create_release_zip "${ZIP}"

# Validate what users actually receive: extract with the system unzip tool and
# re-run signature, ticket, and Gatekeeper checks on that extracted bundle.
VERIFY_DIR="$(mktemp -d /tmp/Perch-release-verify.XXXXXX)"
trap 'rm -rf "${VERIFY_DIR}"' EXIT
/usr/bin/unzip -q "${ZIP}" -d "${VERIFY_DIR}"
codesign --verify --deep --strict --verbose=2 "${VERIFY_DIR}/Perch.app"
xcrun stapler validate "${VERIFY_DIR}/Perch.app"
spctl --assess --type execute --verbose=4 "${VERIFY_DIR}/Perch.app"
rm -rf "${VERIFY_DIR}"
trap - EXIT

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
      <description><![CDATA[
${NOTES_HTML}
      ]]></description>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
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
  --target "${TARGET_BRANCH}" \
  --title "${RELEASE_TITLE}" \
  --notes "${NOTES_MARKDOWN}"

echo "Released ${TAG}."
