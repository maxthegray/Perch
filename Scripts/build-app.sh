#!/bin/bash
#
# Build Perch.app -- a real, ad-hoc-signed .app bundle you can move to /Applications
# and register as a login item (right-click the shelf > Launch at Login).
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Perch.app"
CONFIG="release"

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

# Use the stable Apple Development identity in this machine's Keychain. Ad-hoc signing
# changes Perch's code identity on every rebuild, which makes macOS repeatedly request
# Desktop/Downloads access. Override with PERCH_SIGN_IDENTITY when needed.
SIGN_IDENTITY="${PERCH_SIGN_IDENTITY:-D574D8FBAAF610A87A0C9B5703845E690B7A5676}"

# Sign inside-out: Sparkle's nested helpers/XPC services first, then the framework,
# main binary, and app. (--deep is unreliable for Sparkle.)
echo "Signing with stable identity ${SIGN_IDENTITY}..."
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ -d "${SPARKLE}" ]; then
  codesign --force --sign "${SIGN_IDENTITY}" "${SPARKLE}/XPCServices/Downloader.xpc"
  codesign --force --sign "${SIGN_IDENTITY}" "${SPARKLE}/XPCServices/Installer.xpc"
  codesign --force --sign "${SIGN_IDENTITY}" "${SPARKLE}/Updater.app"
  codesign --force --sign "${SIGN_IDENTITY}" "${SPARKLE}/Autoupdate"
  codesign --force --sign "${SIGN_IDENTITY}" "${APP}/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --sign "${SIGN_IDENTITY}" "${APP}/Contents/MacOS/Perch"
codesign --force --sign "${SIGN_IDENTITY}" "${APP}"

echo "Built ${APP}"
echo "Move it to /Applications (so the login-item path stays stable), then launch it"
echo "and toggle 'Launch at Login' from the shelf's right-click menu."
