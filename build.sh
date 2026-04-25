#!/bin/bash

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
# Using TermiNotesAppKit.swift as the main entry point
swiftc -o "${MACOS_DIR}/${APP_NAME}" \
    TermiNotesAppKit.swift \
    -O

echo "Copying Info.plist..."
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# Copy appicon.png if it exists
if [ -f "appicon.png" ]; then
    cp appicon.png "${RESOURCES_DIR}/appicon.png"
fi

echo "Successfully built ${BUNDLE_DIR}"
echo "You can now run it with: open ${BUNDLE_DIR}"
