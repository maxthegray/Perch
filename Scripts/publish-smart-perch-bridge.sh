#!/bin/bash
#
# Point the legacy smart-perch update feed at the first unified Perch release.
# Run this once, after that release has been published from main.
#
#   ./Scripts/publish-smart-perch-bridge.sh 0.9.0
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: publish-smart-perch-bridge.sh <version>}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be MAJOR.MINOR.PATCH"
  exit 1
fi

REPO="maxthegray/Perch"
BRANCH="smart-perch"
TAG="v${VERSION}"
EXPECTED_URL="releases/download/${TAG}/Perch.zip"

if [ "$(git branch --show-current)" != "main" ]; then
  echo "error: run this from main after publishing ${TAG}"
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "error: the worktree must be clean"
  exit 1
fi
if ! grep -Fq "${EXPECTED_URL}" appcast.xml; then
  echo "error: appcast.xml does not point to ${TAG}/Perch.zip"
  exit 1
fi

gh release view "${TAG}" --repo "${REPO}" >/dev/null

CURRENT_SHA="$(
  gh api "repos/${REPO}/contents/appcast.xml?ref=${BRANCH}" --jq .sha
)"
CONTENT="$(base64 < appcast.xml | tr -d '\n')"

gh api --method PUT "repos/${REPO}/contents/appcast.xml" \
  --raw-field message="Bridge Smart Perch updates to ${TAG}" \
  --raw-field content="${CONTENT}" \
  --raw-field sha="${CURRENT_SHA}" \
  --raw-field branch="${BRANCH}" \
  --silent

echo "Legacy Smart Perch installs will update to ${TAG}, then follow the main feed."
