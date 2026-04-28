# TermiNotes Specification

## Overview
TermiNotes is a lightweight macOS menu bar application designed for quick markdown/text editing with a specific focus on preserving the visual integrity of terminal-style diagrams and box-drawing characters.

## Core Constraints & Goals
- **Menu Bar Residency:** Lives exclusively in the macOS menu bar. No Dock icon.
- **Visual Parity:** Must preserve copy-pasted terminal diagrams (e.g., `git log --graph`, `diff`, box-drawing ASCII).
- **Persistence:** Notes must persist across app restarts.
- **Speed:** Zero-latency interaction; immediate focus on open.
- **Terminal Optimization:** Automatically sanitize text for safe terminal execution (no "smart" quotes, optional single-line flattening).

## Tech Stack
- **Language:** Swift 5.x
- **Framework:** SwiftUI
- **Minimum OS:** macOS 13.0 (Ventura) for `MenuBarExtra` support.

## Architectural Design

### 1. App Structure
- **Entry Point:** `TermiNotesApp.swift` using `MenuBarExtra` with `.window` style.
- **State Management:** `@AppStorage` for simple string persistence in `UserDefaults`.
- **UI Element:** `LSUIElement = true` in `Info.plist` to hide from Dock.

### 2. The Editor (ContentView)
- **Component:** `TextEditor` wrapped in a `VStack`.
- **Formatting:**
    - Font: `Font.system(.body, design: .monospaced)`
    - Disable Autocorrection: `.autocorrectionDisabled(true)`
    - Disable Capitalization: `.textInputAutocapitalization(.never)`
    - Disable Smart Quotes/Dashes: These often require `NSTextView` level overrides if SwiftUI defaults are too aggressive, but `autocorrectionDisabled` is the first line of defense.
- **UX:**
    - `@FocusState` to trigger keyboard focus on appear.
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

## Feature Roadmap
- [ ] Basic `MenuBarExtra` setup.
- [ ] Monospaced `TextEditor` with persistence.
- [ ] Automatic focus on open.
- [ ] **"Copy for Terminal" sanitization logic.**
- [ ] "Quit" and "Clear" utility buttons.
- [ ] Optional: Markdown rendering toggle.
- [ ] Optional: Dark/Light mode theme syncing.

## File Structure
- `TermiNotes/`
    - `TermiNotesApp.swift`
    - `ContentView.swift`
    - `Info.plist`
    - `Assets.xcassets`
