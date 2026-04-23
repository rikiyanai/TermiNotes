# Failure Log

## 2026-04-22
- **Issue:** Manual `NSStatusItem` and `NSPopover` approach also failing to show.
- **Hypothesis:** Entry point or event loop is not starting correctly when compiled with `swiftc`.
- **Action:** Retained `AppDelegate` in `static func main()`, added debug prints, but logs are empty.
- **Next Step:** Simplify to a single file binary without bundle to isolate the issue.
