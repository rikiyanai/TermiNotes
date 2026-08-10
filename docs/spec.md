# TermiNotes Specification

## Overview
TermiNotes is a lightweight macOS menu bar application designed for quick markdown/text editing with a specific focus on preserving the visual integrity of terminal-style diagrams and box-drawing characters.

## Core Constraints & Goals
- **Menu Bar Residency:** Lives exclusively in the macOS menu bar. No Dock icon.
- **Visual Parity:** Must preserve copy-pasted terminal diagrams (e.g., `git log --graph`, `diff`, box-drawing ASCII).
- **Persistence:** Notes must persist across app restarts.
- **Speed:** Editing must not synchronously rescan the full document or decode screenshot history; the popover must focus immediately on open.
- **Terminal Optimization:** Preserve note text exactly and sanitize only through the explicit "Copy for Terminal" action.

## Tech Stack
- **Language:** Swift 5.x
- **Framework:** AppKit
- **Minimum OS:** macOS 13.0 (Ventura).

## Architectural Design

### 1. App Structure
- **Entry Point:** `TermiNotesApplication` in `TermiNotesAppKit.swift`.
- **Canonical target:** `Package.swift` is the only source-list owner. `build.sh` bundles its release product.
- **UI:** Native AppKit status item and popover; `LSUIElement = true` hides the Dock icon.
- **Legacy entry points:** Removed. There is no parallel SwiftUI or test-app executable owner.

### 2. The Editor
- **Component:** A plain `NSTextView` inside `NSScrollView`.
- **Formatting:**
    - Font: `NSFont.monospacedSystemFont`.
    - The text container has infinite width and never wraps terminal structures.
    - Smart quotes, dashes, text replacement, spelling correction, and data detection are disabled.
- **UX:**
    - The popover makes the text view first responder on open.
    - **Safe-Copy Feature:** A "Copy for Terminal" button (or CMD+Shift+C) that:
        1. Strips smart quotes (`“` -> `"`).
        2. Strips smart dashes (`—` -> `--`).
        3. Joins multiple lines with ` \` (backslash-space) to allow multi-line commands to be pasted without immediate execution.
        4. Trims trailing newlines to prevent accidental "Enter" on paste.

### 3. Diagram Preservation Logic
To ensure terminal diagrams look correct:
- Every character must have the exact same width (Monospaced).
- Leading/Trailing whitespace must be preserved.
- No "Smart" text replacement (quotes, dashes, ellipses).

### 4. Persistence
- `TermiNotesStorage` is the sole durable-state owner.
- Notes, toggle metadata, and screenshots live under `~/Library/Application Support/TermiNotes`.
- Note, toggle, and screenshot writes use atomic replacement and propagate errors to the UI and unified log.
- Screenshot history has no silent retention deletion. Same-second captures receive unique names.
- The shelf renders at most the newest 50 thumbnails; this display bound never deletes stored history.

### 5. Performance Ownership
- `TextLineIndex` owns UTF-16 line lookup for toggle/caret operations; callers do not scan from document start.
- Full fold and width reconciliation is coalesced until a short typing pause.
- `ScreenshotWatcher` performs clipboard hashing and writes on a utility queue. Folder scanning is available only for an explicitly supplied, user-authorized URL; the app never probes Desktop at launch.
- Screenshot thumbnails are bounded ImageIO thumbnails decoded off the main thread and cached.
- A hidden screenshot sidebar performs no thumbnail indexing or decoding.

## Core Feature State
- [x] Menu-bar AppKit popover.
- [x] Monospaced no-wrap editor with Application Support persistence.
- [x] Automatic focus on open.
- [x] Explicit "Copy for Terminal" sanitization.
- [x] Toggle lists and screenshot shelf.
- [x] Light/dark appearance through native system colors.

## File Structure
- `TermiNotes/`
    - `TermiNotesAppKit.swift`
    - `TermiNotesStorage.swift`
    - `TextLineIndex.swift`
    - `ScreenshotPipeline.swift`
    - `TerminalSanitizer.swift`
    - `Package.swift`
    - `Tests/TermiNotesVerification.swift`
    - `Info.plist`
