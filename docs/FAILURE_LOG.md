# Failure Log

## 2026-08-31 — FL-0002: terminal copy removed diagram indentation
- **Status:** VERIFIED
- **Category:** CORRECTNESS / TERMINAL UX
- **Requirement:** The explicit terminal-copy action must keep table and diagram indentation while still removing only trailing newline separators.
- **Observed mismatch:** `TerminalSanitizer` trimmed every line with `.trimmingCharacters(in: .whitespaces)`, then trimmed the final result with `.whitespacesAndNewlines`; the README and the supplied annotated screenshot promised indentation preservation that the implementation did not provide.
- **Fix:** Preserve each split line verbatim, remove only empty trailing newline components, and keep the existing smart-punctuation and shell-continuation transformations.
- **Verification:** `Tests/TermiNotesVerification.swift` now covers an indented table row with trailing spaces and asserts that the copied result has no final newline. `bash verify.sh` is the required full build/verification command.

## 2026-08-10 — FL-0001: Persistence and latency owners are explicit
- **Status:** VERIFIED
- **Category:** PERFORMANCE / MAINTAINABILITY
- **Overlay:** `adr`; source owners are `Package.swift`, `TermiNotesStorage`, `TextLineIndex`, and `ScreenshotWatcher`.
- **Requirement:** Preserve raw terminal structure, persist every accepted clipboard screenshot under Application Support, surface persistence failures, and keep the menu-bar process responsive.
- **Observed mismatch:** Note/toggle/screenshot writes used `try?`; the screenshot list silently deleted entries after 50; the hidden sidebar decoded all history; edits rescanned and laid out the whole document; four legacy entry points plus stale binaries and a SwiftUI specification competed with the AppKit runtime.
- **Attempt 1:** Split storage, line indexing, and screenshot work behind narrow interfaces. The first bundle verification found that `swift build --show-bin-path` does not build a release product; `build.sh` now uses `set -euo pipefail`, performs the release build, verifies the product exists, bundles it, and signs the app.
- **Attempt 2:** Moving Desktop enumeration off the main thread was insufficient. Live sampling showed both Foundation and POSIX directory opens could block indefinitely on macOS Desktop privacy control, which also prevented clipboard processing on the shared worker. Runtime capture is now clipboard-first; file-folder capture exists only when a caller supplies a user-authorized URL.
- **Fix:**
    - `TermiNotesStorage` atomically writes notes, toggle metadata, screenshots, and the screenshot fingerprint index. Errors reach the popover status and unified log; capture callbacks occur only after the image file exists.
    - Removed the silent 50-file deletion. Existing screenshot history is retained; only the rendered shelf is bounded to the newest 50 thumbnails.
    - `ScreenshotWatcher` hashes and writes on a utility queue. A validated fingerprint index avoids rereading unchanged history on every launch.
    - Hidden-sidebar startup performs no screenshot indexing or thumbnail decoding. ImageIO creates bounded thumbnails serially off-main and caches them.
    - `TextLineIndex` replaces repeated scans from document start with binary lookup and suffix-only repair. Per-edit full fold/width work is coalesced until a short typing pause; paste no longer forces immediate full layout.
    - Screenshot capture starts without constructing the editor. The 444 KB editor and its full layout are lazy until the user opens the popover.
    - `Package.swift` is the only source-list owner. Legacy Swift/AppKit test entry points were deleted; their ignored compiled binaries were moved to `/Users/r/.Trash/TermiNotes-legacy-binaries-20260810` for recovery.
- **Verification:** `bash verify.sh` passes terminal-text/toggle round trips, explicit failure paths, same-second screenshot uniqueness, isolated clipboard and authorized-folder capture, fingerprint indexing, and a 422,889-UTF-16-unit line-index benchmark (~2.1 ms for the sampled indexed traversal). `swift build`, the release bundle build, strict code-sign verification, and `Info.plist` validation pass. The live signed app idles at 0% CPU with a 12.3 MB physical footprint before the editor is opened. The real status item opens a horizontally rendered monospaced note. All 50 pre-existing screenshots remain, and the aggregate content hash of notes/toggles/screenshots is unchanged across the migration; the new fingerprint index contains 50 entries.
- **Rewrite decision:** Rust is not justified by current evidence. Native AppKit idles below the prior footprint; observed costs were ownership and execution-path defects in document layout and screenshot I/O. Reconsider only if post-fix interaction profiling falsifies this result.

## 2026-07-21
- **Issue:** All text renders one character per line ("vertical text") — the canvas wraps at ~1 character width.
- **Root Cause Identified:** `textContainer.containerSize.width = greatestFiniteMagnitude` was silently discarded because `widthTracksTextView` was still `true` at assignment time. AppKit flips that flag during early lazy text-system setup, so whether it is already set when `loadView` runs is **timing-dependent** — the same line order worked in the pre-feature app and in isolated harnesses, and failed in this build. With tracking on, the container width follows the (at that moment effectively zero-width) text view and clamps to the ~10pt floor, so every line wraps at one character. Diagnosed via a debug build logging `containerSize` after each `loadView` step: read `(10.0, GFM)` immediately after the setup block; after the fix it reads `(GFM, GFM)` and the text view frame normalized (7407×120823pt for 7534 lines vs 220×4.87M broken).
- **Should Happen:** The container must keep infinite width so lines never wrap (see 2026-04-22 no-wrap constraints).
- **Fix:**
    -   Set `widthTracksTextView = false` (and `heightTracksTextView = false`) **before** assigning `containerSize` in `loadView`.
    -   Added a self-healing guard in `updateWidth()`: if the container width is ever finite again, re-assert tracking-off and infinite size (runs on every text change).
- **Follow-up UX fixes shipped in the same build:**
    -   Toggle lists now start **expanded** on creation (Notion behavior — previously the body vanished instantly, which read as "my text disappeared"); the inserted placeholder title is `Toggle`.
    -   Toggle collapse chevrons (`>` / `v`, click to flip) are drawn by a `MarkerGutterView` in the left margin. Two hard-won lessons here: (1) custom painting inside `NSTextView.draw(_:)` is clipped by the text view's own rendering (proven with live probe screenshots); (2) `NSScrollView` does **not** hit-test custom subviews reliably, so chevron clicks were silently lost — the gutter now lives in the popover's container view above the scroll view, with its frame synced in `viewDidLayout` and chevrons mapped through the clip-bounds scroll offset. Verified end-to-end via synthetic `NSApp.sendEvent` clicks (event delivered, toggle flips). `NSClipView.addFloatingSubview` is unavailable in this SDK.
    -   Screenshot thumbnail single-click now copies the entry's **file path** (the image copy was silent and indistinguishable from failure; text copy also can't boomerang into the image watcher). Double-click still inserts a markdown image link.
    -   Thumbnail clicks were being swallowed: `mouseDragged` started a drag session with **zero movement threshold**, so any click with even 1-2px of hand jitter became a micro-drag and `mouseUp` never fired. Fixed with a 4px drag threshold plus explicit down/drag state; verified with synthetic wobble-click (fires) vs real-drag (doesn't) through `NSApp.sendEvent`.
    -   Crash vector removed: `NSApp.currentEvent?.clickCount` throws `NSInternalInconsistencyException` when the current event is not a mouse event (reproduced with a synthetic `KeyUp`). Click count is now passed from the actual `mouseUp` event.
    -   Pasting with a selection that covers a toggle's title line **dropped the toggle** (chevron "disappears" while the title text remains): the ledger's only drop path fired on any title-touching edit. Replaced with re-anchoring — the line at the edit position becomes the title (first pasted line on replace, first surviving body line on delete); the toggle now dies only when title *and* body are both deleted. Locked by 13 replica ledger cases.
    -   Notion container semantics for the body: an insertion at the toggle's tail (Enter at the end of the last body line, or a paste on the line right after the body) now **joins the toggle** instead of falling outside it; replacements/deletions below never grow it. Locked by 17 replica ledger cases.
    -   **Implicit body end (the actual Notion model):** the explicit `bodyEndLine` is gone — a toggle's body is now *everything under its title down to the next toggle's title (or EOF)*. Anything typed/pasted underneath is automatically inside; the ledger maintains only title lines (shift on edits above, re-anchor on title edit, dedupe on merge), which removes the entire class of boundary bugs. Old `toggles.json` entries decode transparently (unknown keys ignored). Locked by 8 new-model replica cases.
    -   **Performance:** the canvas was being rewritten to disk on *every keystroke* (430KB+). Saves are now debounced/coalesced to at most once per second (`DispatchWorkItem`), flushed synchronously on quit / Clear / `applicationWillTerminate`.
    -   The reported "app dies when clicking Toggle List" was **not a crash**: the unified log shows `termination reported by launchd (0, 0, 0)` — a clean exit via the app's own Quit path (Quit button / `Cmd+Q`). All toggle logic paths (create/flip/ledger/containment/clear) were verified headlessly against the real 7534-line document.
    -   Toggle title is now the non-empty line directly above the selection; if none exists, a `Toggle` line is inserted. Previously the first selected line was consumed as the title.
    -   Screenshots taken with `Cmd+Shift+3/4` (save-to-file) were never captured because they bypass the pasteboard; the watcher now also polls the macOS screenshot save folder (`com.apple.screencapture location`, default `~/Desktop`) and imports new image files once their size is stable across two polls.
    -   Screenshot history is now content-hash deduplicated (FNV-1a over image bytes): click-copying an entry, clipboard-manager echoes, or the same file arriving twice no longer creates duplicate entries. The pre-dedup build had stored one identical screenshot three times (confirmed via matching MD5s). Sidebar is hidden by default and each entry shows its stored file path.

## 2026-07-20 — Roadmap (deferred)
Full feature set proposed on 2026-07-20; user approved only two items for now (Notion-style toggle lists + screenshot clipboard sidebar). The rest is deferred here as the roadmap:
- **Colored line highlights (tags/bookmarks):** color-tint lines, user-named colors (e.g. red = "bug"), search-within-highlights panel.
- **Markdown `#` header folding:** collapse sections under ATX headers.
- **Manual pages:** insert/remove slice boundaries in the single endless canvas.
- **Midnight day-slices:** invisible boundary registered at each midnight (live timer + on launch), collapse/expand per day, on/off toggle in settings.
- **History view:** read-only paged browsing of past days (`Cmd+[` / `Cmd+]`).
- **tmux-style auto-copy:** drag-selecting text copies it to the clipboard on mouse-up (toggleable).
- **Restructure:** split `TermiNotesAppKit.swift` into `Sources/` multi-file build; move legacy entry-point experiments and stray binaries to `dumpster/legacy/`.
- **Nested toggle lists:** v1 toggle lists flatten overlapping toggles; nesting deferred.

## 2026-04-22
- **Issue:** Multi-line ASCII tables truncate to a single line or render as a "compressed" block.
- **Root Cause Identified:** `textView.autoresizingMask = .width` was conflicting with the "no-wrap" configuration (`widthTracksTextView = false`). In AppKit, if the autoresizing mask is set to `.width` inside a scroll view, the view's frame is constantly reset to the visible width, which prevents the `NSTextContainer` from correctly expanding horizontally. This often breaks the `NSLayoutManager`'s ability to calculate vertical line breaks for raw text.
- **Should Happen:** The `NSTextView` should be allowed to grow to any width and height required by its content. The `NSScrollView` should then handle the viewport.
- **Fix:** 
    -   Remove `.width` from the `textView` autoresizing mask.
    -   Explicitly set `textView.textContainer?.widthTracksTextView = false`.
    -   Set `textView.textContainer?.containerSize` to a massive width.
    -   Manually synchronize the `textView` and `textContainer` frames to ensure they are large enough to hold all pasted text immediately.
    -   Added `isTemplate = true` to the icon to fix visibility in Dark/Light modes.
