# Failure Log

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
