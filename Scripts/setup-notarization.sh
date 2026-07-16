#!/bin/bash
# Save Perch's Apple notarization credentials in the login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
DEVELOPER_ID="$(printf '%s\n' "${IDENTITIES}" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"

if [ -z "${DEVELOPER_ID}" ]; then
  echo "No Developer ID Application certificate is installed."
  echo "Open Xcode > Settings > Accounts > select your team > Manage Certificates."
  echo "Click + and create a Developer ID Application certificate, then run this again."
  exit 1
fi

TEAM_ID="$(printf '%s\n' "${DEVELOPER_ID}" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
if [ -z "${TEAM_ID}" ]; then
  echo "Could not determine the Team ID from: ${DEVELOPER_ID}"
  exit 1
fi

APPLE_ID="${1:-}"
if [ -z "${APPLE_ID}" ]; then
  read -r -p "Apple Account email: " APPLE_ID
fi

echo "Using ${DEVELOPER_ID}"
echo "Apple will securely prompt for an app-specific password."
echo "Create one at https://account.apple.com if you have not already."
xcrun notarytool store-credentials "PerchNotary" \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}"

echo "Perch notarization credentials are ready."
