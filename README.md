# TermiNotes

A lightweight macOS menu bar markdown/text editor designed for developers. TermiNotes lives in your top bar and focuses on preserving the visual integrity of terminal diagrams and code snippets.

## Features

- **Menu Bar Resident:** Zero-latency access from the macOS menu bar.
- **Diagram Preservation:** Uses a monospaced font with line-wrapping disabled to ensure ASCII art and terminal graphs (like `git log --graph`) stay perfectly aligned.
- **Terminal Sanitizer:** A specialized "Copy for Terminal" feature that:
    - Escapes newlines with ` \` for safe multi-line pasting.
    - Converts "smart" quotes and dashes back to ASCII.
    - Trims trailing newlines to prevent accidental command execution.
- **Interactive Zoom:** Use `CMD +` and `CMD -` to adjust text size on the fly.
- **Resizable Window:** Drag the bottom-right corner to expand your workspace.
- **Persistent:** Automatically saves your notes.

## Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `CMD + V` | Paste diagram or command |
| `CMD + Shift + C` | **Safe Copy** for Terminal (Sanitized) |
| `CMD + =` | Zoom In |
| `CMD + -` | Zoom Out |
| `CMD + A` | Select All |

## Installation (From Source)

If you have Swift installed, you can build and run the app directly:

```bash
swiftc TermiNotesAppKit.swift -o TermiNotes
./TermiNotes
```

## Tech Stack

- **Language:** Swift
- **Framework:** AppKit (Pure)
- **Architecture:** Lightweight `NSStatusItem` + `NSPopover`
