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

# Ad-hoc code signature. Sign inside-out: Sparkle's nested helpers/XPC services first,
# then the framework, then the main binary, then the app. (--deep is unreliable for
# Sparkle, so each nested component is signed explicitly.) Signing is also required for
# SMAppService login-item registration.
echo "Signing (ad-hoc)..."
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ -d "${SPARKLE}" ]; then
  codesign --force --sign - "${SPARKLE}/XPCServices/Downloader.xpc"
  codesign --force --sign - "${SPARKLE}/XPCServices/Installer.xpc"
  codesign --force --sign - "${SPARKLE}/Updater.app"
  codesign --force --sign - "${SPARKLE}/Autoupdate"
  codesign --force --sign - "${APP}/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --sign - "${APP}/Contents/MacOS/Perch"
codesign --force --sign - "${APP}"

echo "Built ${APP}"
echo "Move it to /Applications (so the login-item path stays stable), then launch it"
echo "and toggle 'Launch at Login' from the shelf's right-click menu."
