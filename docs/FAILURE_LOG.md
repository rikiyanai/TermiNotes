# Failure Log

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
