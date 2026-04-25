# TermiNotes

<table>
  <tr>
    <td><img src="screenshot.png" alt="TermiNotes Screenshot" width="600"></td>
    <td><img src="appicon_display.png" alt="TermiNotes Icon" width="100"></td>
  </tr>
</table>

A hyper-lightweight macOS menu bar utility for developers who need to store and sanitize terminal outputs, ASCII diagrams, and multi-line commands without them "breaking."

## Installation

### 1. Build
The easiest way to build is using the provided build script, which creates a proper macOS `.app` bundle:
```bash
chmod +x build.sh
./build.sh
```

### 2. Install (Global Command)
To launch TermiNotes from your terminal and have it **persist** even after you close the terminal window, add this alias or script to your path:
```bash
# Add to your .zshrc or .bash_profile
alias terminotes='open -a "/Applications/TermiNotes.app"'
```
*(Note: Move the built `TermiNotes.app` to your `/Applications` folder first.)*

Alternatively, to run the binary directly and detach it from the terminal:
```bash
nohup ./TermiNotes.app/Contents/MacOS/TermiNotes > /dev/null 2>&1 &
```

## Why TermiNotes?

Standard note apps often "help" you by converting straight quotes to smart quotes, dashes to em-dashes, and wrapping long lines. This destroys terminal diagrams and breaks code snippets. TermiNotes is built to be a "dumb" raw buffer that preserves everything exactly as it was in the terminal.

## Key Features

- **Menu Bar Resident:** Lives in your top bar (look for the `>_N` icon).
- **Canonical No-Wrap:** ASCII art and terminal graphs (like `git log --graph`) never wrap. They scroll horizontally, preserving their visual structure.
- **Terminal Sanitizer:** Copy text back to the terminal safely with `CMD + Shift + C`. It automatically:
    - Escapes newlines with ` \` for safe multi-line pasting.
    - Converts "smart" quotes and dashes back to ASCII.
    - Trims trailing newlines to prevent accidental command execution.
- **Zoom & Resize:** On-the-fly font scaling (`CMD +/-`) and a custom corner dragger for window expansion.
- **Pure AppKit:** Built with native macOS APIs for near-zero memory footprint and maximum responsiveness.

## Usage

1. **Launch:** Run `terminotes` from your terminal (if aliased) or open the `TermiNotes.app`.
2. **Persistence:** Your notes are automatically saved to `~/Library/Application Support/TermiNotes/notes.txt`.
3. **Shortcuts:**
    - `CMD + V`: Paste (Raw, no-wrap).
    - `CMD + Shift + C`: **Safe Copy** for Terminal (Sanitized for multi-line pasting).
    - `CMD + = / -`: Zoom text.
4. **Launch at Login:** Toggle this in the menu to have TermiNotes start automatically when you log in.
