# Failure Log

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
