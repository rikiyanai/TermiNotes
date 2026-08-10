#!/bin/bash
set -euo pipefail

VERIFY_BINARY="${TMPDIR:-/tmp}/TermiNotesVerification"

swiftc -D TERMINOTES_VERIFICATION \
    TermiNotesAppKit.swift \
    TermiNotesStorage.swift \
    TextLineIndex.swift \
    ScreenshotPipeline.swift \
    TerminalSanitizer.swift \
    Tests/TermiNotesVerification.swift \
    -O \
    -o "$VERIFY_BINARY"

"$VERIFY_BINARY"
