#!/bin/bash
#
# Build and sign Perch.app. Local builds prefer an installed Apple signing identity;
# release builds set PERCH_DISTRIBUTION=1 to require Developer ID signing,
# hardened runtime, and trusted timestamps suitable for notarization.
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Perch.app"
CONFIG="release"

# Prefer Developer ID, then Apple Development, and finally ad-hoc signing for local
# builds. Override with PERCH_SIGN_IDENTITY when a specific identity is required.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
DEVELOPER_ID="$(printf '%s\n' "${IDENTITIES}" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
APPLE_DEVELOPMENT="$(printf '%s\n' "${IDENTITIES}" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
SIGN_IDENTITY="${PERCH_SIGN_IDENTITY:-${DEVELOPER_ID:-${APPLE_DEVELOPMENT:--}}}"
DISTRIBUTION="${PERCH_DISTRIBUTION:-0}"

if [ "${DISTRIBUTION}" = "1" ]; then
  IDENTITY_INFO="$(printf '%s\n' "${IDENTITIES}" | grep -F "${SIGN_IDENTITY}" | head -1 || true)"
  if [[ "${IDENTITY_INFO}" != *"Developer ID Application:"* ]]; then
    echo "error: a Developer ID Application certificate is required for a release"
    echo "Create one in Xcode > Settings > Accounts > Manage Certificates, then retry."
    exit 1
  fi
fi

SIGN_FLAGS=(--force --sign "${SIGN_IDENTITY}")
if [ "${DISTRIBUTION}" = "1" ]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi

echo "Building (${CONFIG})..."
swift build -c "${CONFIG}"
BIN=".build/${CONFIG}/Perch"

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/Perch"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
else
  echo "  (no Resources/AppIcon.icns -- run 'swift Scripts/make-icon.swift' for a custom icon)"
fi

# Embed Sparkle.framework for auto-updates. The binary already carries an rpath to
# @executable_path/../Frameworks (set in Package.swift).
FRAMEWORK=".build/${CONFIG}/Sparkle.framework"
if [ -d "${FRAMEWORK}" ]; then
  echo "Embedding Sparkle.framework..."
  mkdir -p "${APP}/Contents/Frameworks"
  cp -R "${FRAMEWORK}" "${APP}/Contents/Frameworks/"
else
  echo "  WARNING: ${FRAMEWORK} not found -- auto-update will be disabled"
fi

# Sign inside-out: Sparkle's nested helpers/XPC services first, then the framework,
# main binary, and app. (--deep is unreliable for Sparkle.)
echo "Signing with stable identity ${SIGN_IDENTITY}..."
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ -d "${SPARKLE}" ]; then
  codesign "${SIGN_FLAGS[@]}" "${SPARKLE}/XPCServices/Installer.xpc"
  codesign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "${SPARKLE}/XPCServices/Downloader.xpc"
  codesign "${SIGN_FLAGS[@]}" "${SPARKLE}/Autoupdate"
  codesign "${SIGN_FLAGS[@]}" "${SPARKLE}/Updater.app"
  codesign "${SIGN_FLAGS[@]}" "${APP}/Contents/Frameworks/Sparkle.framework"
fi
codesign "${SIGN_FLAGS[@]}" "${APP}/Contents/MacOS/Perch"
codesign "${SIGN_FLAGS[@]}" "${APP}"

codesign --verify --deep --strict --verbose=2 "${APP}"

echo "Built ${APP}"
echo "Move it to /Applications (so the login-item path stays stable), then launch it"
echo "and toggle 'Launch at Login' from the shelf's right-click menu."
