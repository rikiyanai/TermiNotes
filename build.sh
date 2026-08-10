#!/bin/bash
set -euo pipefail

# TermiNotes Build Script
# Bundles the AppKit version into a proper .app structure

APP_NAME="TermiNotes"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Compiling TermiNotes (AppKit version)..."
# Package.swift is the single source-list owner; this script only bundles its release product.
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
test -x "${BIN_DIR}/${APP_NAME}"
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

echo "Copying Info.plist..."
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# Copy appicon.png if it exists
if [ -f "appicon.png" ]; then
    cp appicon.png "${RESOURCES_DIR}/appicon.png"
fi

echo "Signing app bundle..."
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "Successfully built ${BUNDLE_DIR}"
echo "You can now run it with: open ${BUNDLE_DIR}"
