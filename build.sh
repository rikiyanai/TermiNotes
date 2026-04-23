#!/bin/bash

# TermiNotes Build Script
# Bundles the Swift files into a proper .app structure

APP_NAME="TermiNotes"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Compiling Swift files..."
swiftc -o "${MACOS_DIR}/${APP_NAME}" \
    TermiNotesApp.swift \
    ContentView.swift \
    TerminalSanitizer.swift \
    -parse-as-library \
    -O

echo "Copying Info.plist..."
cp Info.plist "${CONTENTS_DIR}/Info.plist"

echo "Successfully built ${BUNDLE_DIR}"
echo "You can now run it with: open ${BUNDLE_DIR}"
