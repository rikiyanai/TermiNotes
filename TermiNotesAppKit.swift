import AppKit

// MARK: - Toggle List Model

/// A Notion-style toggle: `titleLine` stays visible; EVERYTHING below it — down to the
/// next toggle's title (or end of document) — folds away. The body end is IMPLICIT, like
/// Notion's container: no boundary to maintain, and anything typed/pasted underneath the
/// title is automatically inside. Line numbers are 0-based global line indexes, adjusted
/// on every text edit by the ledger in TermiNotesController.textStorage(didProcessEditing:).
/// (Old toggles.json entries with an explicit bodyEndLine still decode — extra keys ignored.)
struct ToggleEntry: Codable {
    var titleLine: Int
    var collapsed: Bool
}

// MARK: - Toggle gutter

/// Left gutter pinned to the scroll view's left edge. Lives as a subview of the scroll view
/// (above the clip view) and redraws on scroll via bounds-change notifications; chevrons are
/// mapped document-y -> clip-y per draw. (Drawing markers inside NSTextView.draw was tried
/// first and is unreliable here — the text view's own rendering clips custom painting in the
/// margin. NSClipView.addFloatingSubview is unavailable in this SDK.)
class MarkerGutterView: NSView {
    weak var controller: TermiNotesController?

    override var isFlipped: Bool { true }

    private func lineRect(for toggle: ToggleEntry) -> NSRect? {
        guard let tc = controller,
              let lm = tc.textView.layoutManager,
              let range = tc.charRangeOfLine(toggle.titleLine) else { return nil }
        let gr = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return lm.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tc = controller else { return }
        let originY = tc.scrollView.contentView.bounds.origin.y // vertical scroll offset
        let insetY = tc.textView.textContainerInset.height
        NSColor.secondaryLabelColor.setStroke()
        for t in tc.toggles {
            guard let lineRect = lineRect(for: t) else { continue }
            let cy = lineRect.midY + insetY - originY
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if t.collapsed { // ">"
                path.move(to: NSPoint(x: 5, y: cy - 4))
                path.line(to: NSPoint(x: 10, y: cy))
                path.line(to: NSPoint(x: 5, y: cy + 4))
            } else { // "v"
                path.move(to: NSPoint(x: 4, y: cy - 2.5))
                path.line(to: NSPoint(x: 8, y: cy + 2.5))
                path.line(to: NSPoint(x: 12, y: cy - 2.5))
            }
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let tc = controller else { return }
        let originY = tc.scrollView.contentView.bounds.origin.y
        let y = convert(event.locationInWindow, from: nil).y + originY - tc.textView.textContainerInset.height
        for t in tc.toggles {
            guard let lineRect = lineRect(for: t) else { continue }
            if y >= lineRect.minY && y <= lineRect.maxY {
                _ = tc.flipToggle(atLine: t.titleLine, titleOnly: true)
                return
            }
        }
    }
}


class TermiTextView: NSTextView {
    weak var toggleController: TermiNotesController?
    /// Line that was right-clicked, captured in menu(for:) for the toggle context actions.
    var contextMenuLine: Int = -1

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let string = pb.string(forType: .string) else { return }

        let sanitized = string.replacingOccurrences(of: "\r\n", with: "\n")
                              .replacingOccurrences(of: "\r", with: "\n")

        if self.shouldChangeText(in: self.selectedRange(), replacementString: sanitized) {
            self.textStorage?.replaceCharacters(in: self.selectedRange(), with: sanitized)
            self.didChangeText()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        guard let tc = toggleController else { return menu }

        let point = convert(event.locationInWindow, from: nil)
        contextMenuLine = tc.lineIndex(ofChar: characterIndexForInsertion(at: point))

        // Top section: toggle actions for the clicked line's toggle (if any)
        if tc.toggle(containing: contextMenuLine) != nil {
            let removeItem = NSMenuItem(title: "Remove Toggle", action: #selector(TermiNotesController.removeContextToggle(_:)), keyEquivalent: "")
            removeItem.target = tc
            menu.insertItem(removeItem, at: 0)

            let flipItem = NSMenuItem(title: "Expand / Collapse Toggle", action: #selector(TermiNotesController.flipContextToggle(_:)), keyEquivalent: "")
            flipItem.target = tc
            menu.insertItem(flipItem, at: 0)
        }

        let createItem = NSMenuItem(title: "Toggle List", action: #selector(TermiNotesController.createToggleFromSelection(_:)), keyEquivalent: "")
        createItem.target = tc
        createItem.isEnabled = tc.hasSelection()
        menu.insertItem(createItem, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)
        return menu
    }

    /// Option-click on a toggle title line flips it (clicking the gutter chevron is the primary way).
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let tc = toggleController {
            let point = convert(event.locationInWindow, from: nil)
            let line = tc.lineIndex(ofChar: characterIndexForInsertion(at: point))
            if tc.flipToggle(atLine: line, titleOnly: true) { return }
        }
        super.mouseDown(with: event)
    }
}

class TermiNotesController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    let textView = TermiTextView()
    let scrollView = NSScrollView()
    var currentFontSize: CGFloat = 13.0

    // MARK: Durable state
    let storage: TermiNotesStorage
    private let persistenceQueue = DispatchQueue(label: "TermiNotes.Persistence", qos: .utility)
    private let textLines = TextLineIndex()
    private let statusLabel = NSTextField(labelWithString: "")

    // MARK: Toggle list state
    var toggles: [ToggleEntry] = []
    var foldsRendered = false

    // MARK: Toggle gutter
    let gutter = MarkerGutterView()

    // MARK: Screenshot sidebar state
    static let sidebarWidth: CGFloat = 180
    static let sidebarDisplayLimit = 50
    let sidebarContainer = NSView()
    let thumbsStack = NSStackView()
    let emptyLabel = NSTextField(labelWithString: "No screenshots yet")
    let screenshotHeader = NSTextField(labelWithString: "Screenshots")
    var screenshotFiles: [URL] = []
    private var totalScreenshotCount = 0
    private let thumbnailLoader = ScreenshotThumbnailLoader()
    private let screenshotIndexQueue = DispatchQueue(label: "TermiNotes.ScreenshotIndex", qos: .utility)
    private var screenshotsNeedReload = true
    private var screenshotLoadGeneration = 0
    var sidebarVisible: Bool = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? false

    init(storage: TermiNotesStorage) {
        self.storage = storage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        // Header
        let label = NSTextField(labelWithString: "TermiNotes")
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 8, y: 275, width: 100, height: 20)
        label.autoresizingMask = [.minYMargin]
        container.addSubview(label)

        let findButton = NSButton(title: "Find", target: nil, action: #selector(NSTextView.performFindPanelAction(_:)))
        findButton.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        findButton.bezelStyle = .inline
        findButton.font = .systemFont(ofSize: 11)
        findButton.frame = NSRect(x: 152, y: 275, width: 55, height: 20)
        findButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(findButton)

        let copyButton = NSButton(title: "Copy for Terminal", target: self, action: #selector(copyForTerminal))
        copyButton.bezelStyle = .inline
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.frame = NSRect(x: 212, y: 275, width: 120, height: 20)
        copyButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(copyButton)

        let shotsButton = NSButton(title: "Shots", target: self, action: #selector(toggleSidebar(_:)))
        shotsButton.bezelStyle = .inline
        shotsButton.font = .systemFont(ofSize: 11)
        shotsButton.frame = NSRect(x: 337, y: 275, width: 55, height: 20)
        shotsButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(shotsButton)

        // ScrollView Setup (frame owned by viewDidLayout, not autoresizing)
        let sideW = sidebarVisible ? TermiNotesController.sidebarWidth : 0
        scrollView.frame = NSRect(x: 0, y: 40, width: 400 - sideW, height: 230)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = []

        // TextView Setup - The "Canonical No-Wrap" Recipe
        let contentSize = scrollView.contentSize
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true

        // IMPORTANT: No .width autoresizing mask for no-wrap
        textView.autoresizingMask = []

        // IMPORTANT: tracking must be disabled BEFORE setting containerSize — if
        // widthTracksTextView is still true (AppKit flips it during early lazy setup,
        // timing-dependent), the width assignment is silently discarded and the
        // container clamps to a ~10pt floor: every line wraps at one character.
        // See docs/FAILURE_LOG.md 2026-07-21.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineBreakMode = .byClipping

        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.delegate = self
        textView.font = .monospacedSystemFont(ofSize: currentFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 0) // left margin for toggle "> " markers

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        scrollView.documentView = textView
        container.addSubview(scrollView)

        // Gutter lives in the CONTAINER, above the scroll view: NSScrollView does not
        // reliably hit-test custom subviews, and this keeps z-order under our control.
        // Its frame is synced in viewDidLayout; scroll mapping comes from the clip bounds.
        gutter.controller = self
        container.addSubview(gutter)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsDidChange),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        // Screenshot sidebar (hidable), pinned right
        sidebarContainer.frame = NSRect(x: 400 - sideW, y: 40, width: max(sideW, 1), height: 230)
        sidebarContainer.autoresizingMask = []
        sidebarContainer.isHidden = !sidebarVisible

        screenshotHeader.font = .systemFont(ofSize: 11, weight: .bold)
        screenshotHeader.textColor = .secondaryLabelColor
        screenshotHeader.frame = NSRect(x: 8, y: 206, width: 164, height: 20)
        screenshotHeader.autoresizingMask = [.minYMargin]
        sidebarContainer.addSubview(screenshotHeader)

        let sideScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: sideW, height: 202))
        sideScroll.borderType = .noBorder
        sideScroll.hasVerticalScroller = true
        sideScroll.autohidesScrollers = true
        sideScroll.drawsBackground = false
        sideScroll.autoresizingMask = [.width, .height]
        thumbsStack.orientation = .vertical
        thumbsStack.alignment = .centerX
        thumbsStack.spacing = 8
        thumbsStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        thumbsStack.translatesAutoresizingMaskIntoConstraints = false
        sideScroll.documentView = thumbsStack
        NSLayoutConstraint.activate([
            thumbsStack.leadingAnchor.constraint(equalTo: sideScroll.contentView.leadingAnchor),
            thumbsStack.trailingAnchor.constraint(equalTo: sideScroll.contentView.trailingAnchor),
            thumbsStack.topAnchor.constraint(equalTo: sideScroll.contentView.topAnchor)
        ])
        sidebarContainer.addSubview(sideScroll)

        emptyLabel.font = .systemFont(ofSize: 10)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: 90, width: sideW, height: 30)
        emptyLabel.autoresizingMask = [.minYMargin, .maxYMargin]
        sidebarContainer.addSubview(emptyLabel)

        container.addSubview(sidebarContainer)

        // Footer
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded
        clearButton.frame = NSRect(x: 8, y: 8, width: 70, height: 25)
        clearButton.autoresizingMask = [.maxYMargin]
        container.addSubview(clearButton)

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: 322, y: 8, width: 70, height: 25)
        quitButton.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(quitButton)

        statusLabel.font = .systemFont(ofSize: 9)
        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.frame = NSRect(x: 84, y: 11, width: 232, height: 18)
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        statusLabel.isHidden = true
        container.addSubview(statusLabel)

        // Resize Handle
        let resizeHandle = ResizeHandleView(frame: NSRect(x: 385, y: 0, width: 15, height: 15))
        resizeHandle.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(resizeHandle)

        self.view = container

        textView.toggleController = self
        textView.textStorage?.delegate = self
        do {
            try storage.prepare()
        } catch {
            reportPersistenceError(error, operation: "Prepare storage")
        }
        loadSavedContent()
        loadToggles()
        renderToggles(reconcileWidth: false)
        if sidebarVisible { loadScreenshots() }
    }

    /// Editor and sidebar share the band y=40...h-30; frames are owned here so the
    /// sidebar can appear/disappear without fighting autoresizing.
    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        let h = view.bounds.height
        let sideW: CGFloat = sidebarVisible ? TermiNotesController.sidebarWidth : 0
        sidebarContainer.isHidden = !sidebarVisible
        sidebarContainer.frame = NSRect(x: w - sideW, y: 40, width: max(sideW, 1), height: h - 70)
        scrollView.frame = NSRect(x: 0, y: 40, width: w - sideW, height: h - 70)
        gutter.frame = NSRect(x: 0, y: 40, width: 16, height: h - 70)
    }

    func loadSavedContent() {
        do {
            if let content = try storage.loadNote() {
                textView.string = content
            }
            textLines.rebuild(for: textView.string as NSString)
        } catch {
            textLines.rebuild(for: textView.string as NSString)
            reportPersistenceError(error, operation: "Load note")
        }
    }

    func textDidChange(_ notification: Notification) {
        scheduleSave()
        scheduleLayoutRefresh()
    }

    /// Coalesce per-keystroke writes: the canvas is saved at most once per second
    /// instead of on every keystroke (rewriting a 430KB+ file per keystroke was the
    /// real performance cost). Flushed synchronously via flushSave() on quit.
    private var saveWorkItem: DispatchWorkItem?
    private var layoutWorkItem: DispatchWorkItem?

    func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveContent() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        persistCurrentState(synchronously: true)
    }

    /// NSTextView lays out the visible edit immediately. Expensive full-document width
    /// and fold reconciliation waits for a short typing pause instead of blocking each key.
    func scheduleLayoutRefresh() {
        layoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.toggles.isEmpty || self.foldsRendered { self.renderToggles() }
            else { self.updateWidth() }
        }
        layoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func updateWidth() {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        // Self-healing guard (FAILURE_LOG 2026-07-21): if anything ever re-enables
        // width tracking, the container width collapses and all text wraps vertically.
        if textContainer.containerSize.width != CGFloat.greatestFiniteMagnitude {
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedSize = layoutManager.usedRect(for: textContainer).size

        // Ensure the text view is at least as wide as the scroll view,
        // but can grow much wider for long lines.
        let minWidth = scrollView.contentSize.width
        let newWidth = max(minWidth, usedSize.width + 100)

        if abs(textView.frame.width - newWidth) > 1 {
            textView.frame = NSRect(x: 0, y: 0, width: newWidth, height: max(textView.frame.height, usedSize.height))
        }
    }

    func saveContent() {
        persistCurrentState(synchronously: false)
    }

    private func persistCurrentState(synchronously: Bool) {
        let note = textView.string
        let toggleSnapshot = toggles
        let operation = { [storage] in
            do {
                try storage.saveNote(note)
                try storage.saveToggles(toggleSnapshot)
                DispatchQueue.main.async { [weak self] in self?.clearPersistenceError() }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.reportPersistenceError(error, operation: "Save note")
                }
            }
        }
        if synchronously { persistenceQueue.sync(execute: operation) }
        else { persistenceQueue.async(execute: operation) }
    }

    func reportPersistenceError(_ error: Error, operation: String) {
        let message = "\(operation) failed: \(error.localizedDescription)"
        NSLog("TermiNotes: %@", message)
        statusLabel.stringValue = "Not saved"
        statusLabel.toolTip = message
        statusLabel.isHidden = false
        (NSApp.delegate as? AppDelegate)?.statusItem?.button?.toolTip = message
    }

    private func clearPersistenceError() {
        statusLabel.stringValue = ""
        statusLabel.toolTip = nil
        statusLabel.isHidden = true
        (NSApp.delegate as? AppDelegate)?.statusItem?.button?.toolTip = "TermiNotes"
    }

    @objc func zoomIn() { currentFontSize += 1; updateFont() }
    @objc func zoomOut() { if currentFontSize > 5 { currentFontSize -= 1; updateFont() } }
    func updateFont() { textView.font = .monospacedSystemFont(ofSize: currentFontSize, weight: .regular) }

    @objc func copyForTerminal() {
        let sanitized = TerminalSanitizer.sanitize(textView.string)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }

    @objc func clearAll() {
        let range = NSRange(location: 0, length: (textView.string as NSString).length)
        if textView.shouldChangeText(in: range, replacementString: "") {
            textView.textStorage?.replaceCharacters(in: range, with: "")
            textView.didChangeText()
            flushSave()
        }
    }
    @objc func quitApp() {
        flushSave()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Toggle lists

    func lineIndex(ofChar idx: Int) -> Int {
        textLines.lineNumber(at: min(idx, (textView.string as NSString).length))
    }

    func charRangeOfLine(_ line: Int) -> NSRange? {
        textLines.range(ofLine: line, stringLength: (textView.string as NSString).length)
    }

    func charRange(fromLine a: Int, throughLine b: Int) -> NSRange? {
        let length = (textView.string as NSString).length
        guard let start = textLines.start(ofLine: a),
              let endRange = textLines.range(ofLine: b, stringLength: length) else { return nil }
        return NSRange(location: start, length: max(0, endRange.upperBound - start))
    }

    /// The implicit body end (inclusive): the line before the next toggle's title,
    /// or the last line of the document. `i` is the index into `toggles` (sorted).
    func bodyEnd(forToggleAt i: Int) -> Int {
        let lastLine = textLines.lastLine
        guard i >= 0, i < toggles.count else { return lastLine }
        let next = i + 1 < toggles.count ? toggles[i + 1].titleLine - 1 : lastLine
        return min(next, lastLine)
    }

    func toggle(containing line: Int) -> ToggleEntry? {
        guard line >= 0 else { return nil }
        for (i, t) in toggles.enumerated() where line >= t.titleLine {
            if line <= bodyEnd(forToggleAt: i) { return t }
        }
        return nil
    }

    func hasSelection() -> Bool {
        textView.selectedRange().length > 0
    }

    /// Notion-style: the selection becomes the toggle BODY. The title is the non-empty line
    /// directly above it; if there isn't one, a "New Toggle List" title line is inserted.
    @objc func createToggleFromSelection(_ sender: Any?) {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { return }

        var s = textView.string as NSString
        var firstBodyLine = lineIndex(ofChar: sel.location)
        var lastBodyLine = lineIndex(ofChar: max(sel.location, sel.upperBound - 1))

        var title = firstBodyLine - 1
        var aboveIsUsable = false
        if title >= 0, let r = charRangeOfLine(title) {
            aboveIsUsable = !s.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !aboveIsUsable {
            textView.insertText("Toggle\n", replacementRange: NSRange(location: sel.location, length: 0))
            s = textView.string as NSString
            title = lineIndex(ofChar: sel.location)
            firstBodyLine = title + 1
            lastBodyLine += 1
        }

        guard lastBodyLine > title else { return }
        // Same-line titles replace; a new title inside another toggle's body simply
        // splits it (the body above now ends at this title — implicit ends).
        toggles.removeAll { $0.titleLine == title }
        // Created expanded (Notion behavior): the body stays visible until the user collapses it.
        toggles.append(ToggleEntry(titleLine: title, collapsed: false))
        toggles.sort { $0.titleLine < $1.titleLine }
        saveToggles()
        renderToggles()
        // Park the caret on the title line so it isn't left inside hidden text.
        if let tr = charRangeOfLine(title) {
            textView.setSelectedRange(NSRange(location: max(tr.location, tr.upperBound - 1), length: 0))
        }
    }

    @discardableResult
    func flipToggle(atLine line: Int, titleOnly: Bool = false) -> Bool {
        guard line >= 0 else { return false }
        for (i, t) in toggles.enumerated() {
            let inRange = titleOnly ? (line == t.titleLine) : (line >= t.titleLine && line <= bodyEnd(forToggleAt: i))
            if inRange {
                toggles[i].collapsed.toggle()
                saveToggles()
                renderToggles()
                return true
            }
        }
        return false
    }

    @objc func flipContextToggle(_ sender: Any?) {
        _ = flipToggle(atLine: textView.contextMenuLine)
    }

    @objc func removeContextToggle(_ sender: Any?) {
        let line = textView.contextMenuLine
        guard let t = toggle(containing: line) else { return }
        toggles.removeAll { $0.titleLine == t.titleLine }
        saveToggles()
        renderToggles()
    }

    /// Cmd+\ — flip the toggle containing the caret, if any.
    @objc func toggleFold(_ sender: Any?) {
        _ = flipToggle(atLine: lineIndex(ofChar: textView.selectedRange().location))
    }

    /// Line-number ledger: shift toggle TITLE lines on every edit so folds track the text.
    /// Body ends are implicit (next title / EOF), so the only state to maintain is the
    /// title line itself — no per-edit boundary bookkeeping. Runs in didProcessEditing
    /// (pre-save), against lastString (pre-edit snapshot).
    func adjustToggles(editedRange: NSRange, changeInLength delta: Int, oldLineStarts: [Int], oldTextLength: Int) {
        let newS = textView.string as NSString
        let preLocation = min(editedRange.location, oldTextLength)
        let preLength = max(0, min(editedRange.length - delta, oldTextLength - preLocation))
        let preRange = NSRange(location: preLocation, length: preLength)
        let isInsertion = preRange.length == 0
        let editStartLine = textLines.lineNumber(at: editedRange.location)
        let oldEditEndLine = TextLineIndex.lineNumber(at: preRange.upperBound, starts: oldLineStarts)
        let newEditEndLine = textLines.lineNumber(at: min(editedRange.upperBound, newS.length))
        let shift = newEditEndLine - oldEditEndLine
        let lastLine = textLines.lastLine

        var out: [ToggleEntry] = []
        out.reserveCapacity(toggles.count)
        for var t in toggles {
            if isInsertion {
                // Nothing destroyed: shift the title only if the insertion lands
                // at or before the title line's first character. Anything below the
                // title is automatically inside the toggle (implicit end).
                let titleStart = t.titleLine >= 0 && t.titleLine < oldLineStarts.count
                    ? oldLineStarts[t.titleLine]
                    : Int.max
                if editedRange.location <= titleStart {
                    t.titleLine += shift
                }
                out.append(t)
            } else if t.titleLine > oldEditEndLine {
                t.titleLine += shift // entirely after the replaced region
                out.append(t)
            } else if t.titleLine >= editStartLine {
                // Title line was inside the replaced region — re-anchor, don't drop:
                // the line now at editStartLine becomes the title. (newS.length == 0
                // means the whole document was deleted — then the toggle dies too.)
                t.titleLine = editStartLine
                if t.titleLine <= lastLine && newS.length > 0 { out.append(t) }
            } else {
                out.append(t) // edit below the title: nothing to maintain
            }
        }
        // Re-anchoring can collapse ordering or merge two titles onto one line.
        out.sort { $0.titleLine < $1.titleLine }
        var seen = Set<Int>()
        toggles = out.filter { seen.insert($0.titleLine).inserted }
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let oldLineStarts = textLines.starts
        let oldTextLength = max(0, textStorage.length - delta)
        textLines.update(afterEditAt: editedRange.location, in: textStorage.string as NSString)
        if !toggles.isEmpty {
            adjustToggles(
                editedRange: editedRange,
                changeInLength: delta,
                oldLineStarts: oldLineStarts,
                oldTextLength: oldTextLength
            )
        }
    }

    /// Keep the caret out of collapsed (invisible) body text.
    func textViewDidChangeSelection(_ notification: Notification) {
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return }
        let line = lineIndex(ofChar: sel.location)
        for (i, t) in toggles.enumerated() where t.collapsed {
            if line > t.titleLine && line <= bodyEnd(forToggleAt: i) {
                if let tr = charRangeOfLine(t.titleLine) {
                    let pos = max(tr.location, tr.upperBound - 1)
                    if pos != sel.location {
                        textView.setSelectedRange(NSRange(location: pos, length: 0))
                    }
                }
                return
            }
        }
    }

    func loadToggles() {
        do {
            let savedToggles = try storage.loadToggles()
            var seen = Set<Int>()
            toggles = savedToggles.compactMap { toggle in
                guard toggle.titleLine >= 0,
                      toggle.titleLine <= textLines.lastLine,
                      seen.insert(toggle.titleLine).inserted else { return nil }
                return ToggleEntry(titleLine: toggle.titleLine, collapsed: toggle.collapsed)
            }.sorted { $0.titleLine < $1.titleLine }
        } catch {
            reportPersistenceError(error, operation: "Load toggles")
        }
    }

    func saveToggles() {
        let snapshot = toggles
        persistenceQueue.async { [weak self, storage] in
            do {
                try storage.saveToggles(snapshot)
            } catch {
                DispatchQueue.main.async {
                    self?.reportPersistenceError(error, operation: "Save toggles")
                }
            }
        }
    }

    /// Fold rendering never touches the string: collapsed body lines get a 0.1pt font +
    /// clear color as *temporary* layout attributes, so copy/save/undo are unaffected.
    func renderToggles(reconcileWidth: Bool = true) {
        guard let lm = textView.layoutManager else { return }
        let s = textView.string as NSString
        let full = NSRange(location: 0, length: s.length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.font, forCharacterRange: full)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        foldsRendered = !toggles.isEmpty
        for (i, t) in toggles.enumerated() {
            guard let titleRange = charRangeOfLine(t.titleLine) else { continue }
            let tint = NSRange(location: titleRange.location, length: max(0, titleRange.length - 1))
            lm.addTemporaryAttribute(.backgroundColor,
                                     value: NSColor.labelColor.withAlphaComponent(t.collapsed ? 0.14 : 0.07),
                                     forCharacterRange: tint)
            let end = bodyEnd(forToggleAt: i)
            if t.collapsed, end > t.titleLine,
               let bodyRange = charRange(fromLine: t.titleLine + 1, throughLine: end), bodyRange.length > 0 {
                lm.addTemporaryAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), forCharacterRange: bodyRange)
                lm.addTemporaryAttribute(.foregroundColor, value: NSColor.clear, forCharacterRange: bodyRange)
            }
        }
        if reconcileWidth { updateWidth() }
        gutter.needsDisplay = true
    }

    @objc func clipBoundsDidChange() {
        gutter.needsDisplay = true
    }

    // MARK: - Screenshot sidebar

    func noteScreenshotCapture() {
        screenshotsNeedReload = true
        if sidebarVisible { loadScreenshots() }
    }

    @objc func toggleSidebar(_ sender: Any?) {
        sidebarVisible.toggle()
        UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible")
        if let popover = (NSApp.delegate as? AppDelegate)?.popover {
            var size = popover.contentSize
            size.width += sidebarVisible ? TermiNotesController.sidebarWidth : -TermiNotesController.sidebarWidth
            size.width = max(300, min(1200, size.width))
            popover.contentSize = size
        }
        view.needsLayout = true
        if sidebarVisible { loadScreenshots() }
    }

    func loadScreenshots() {
        guard sidebarVisible else {
            screenshotsNeedReload = true
            return
        }
        guard screenshotsNeedReload else { return }
        screenshotLoadGeneration += 1
        let generation = screenshotLoadGeneration
        screenshotIndexQueue.async { [weak self, storage] in
            do {
                let files = try storage.screenshotFiles()
                DispatchQueue.main.async {
                    guard let self, generation == self.screenshotLoadGeneration else { return }
                    self.totalScreenshotCount = files.count
                    self.screenshotFiles = Array(files.prefix(Self.sidebarDisplayLimit))
                    self.screenshotsNeedReload = false
                    self.rebuildThumbs()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.reportPersistenceError(error, operation: "Load screenshots")
                }
            }
        }
    }

    func rebuildThumbs() {
        thumbsStack.arrangedSubviews.forEach { thumbsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        emptyLabel.isHidden = !screenshotFiles.isEmpty
        screenshotHeader.stringValue = totalScreenshotCount > Self.sidebarDisplayLimit
            ? "Latest \(Self.sidebarDisplayLimit) of \(totalScreenshotCount)"
            : "Screenshots (\(totalScreenshotCount))"
        for url in screenshotFiles {
            let view = ThumbnailView(frame: NSRect(x: 0, y: 0, width: 160, height: 116))
            view.fileURL = url
            view.setImage(NSImage(systemSymbolName: "photo", accessibilityDescription: "Loading screenshot") ?? NSImage())
            view.setPath(url.path)
            view.toolTip = url.path
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: 160),
                view.heightAnchor.constraint(equalToConstant: 116)
            ])
            view.onClick = { [weak self] v, count in self?.thumbClicked(v, clickCount: count) }
            thumbsStack.addArrangedSubview(view)
            thumbnailLoader.load(url) { [weak view] image in
                guard let view, view.fileURL == url, let image else { return }
                view.setImage(image)
            }
        }
    }

    /// Single click copies the screenshot's file PATH (text) — the watcher ignores
    /// non-image pasteboard content, so it can't boomerang into the history.
    /// Double click inserts a markdown image link at the caret.
    func thumbClicked(_ view: ThumbnailView, clickCount: Int) {
        guard let url = view.fileURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
        if clickCount == 2 {
            textView.insertText("![](<\(url.path)>)", replacementRange: textView.selectedRange())
        }
    }
}

class ResizeHandleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor.tertiaryLabelColor
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.width, y: 0))
        path.line(to: NSPoint(x: 0, y: bounds.height))
        path.lineWidth = 1.5
        path.stroke()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let popover = (NSApp.delegate as? AppDelegate)?.popover else { return }
        var newSize = popover.contentSize
        newSize.width += event.deltaX
        newSize.height += event.deltaY
        newSize.width = max(200, min(1000, newSize.width))
        newSize.height = max(150, min(800, newSize.height))
        popover.contentSize = newSize
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let popover = NSPopover()
    let storage = TermiNotesStorage()
    lazy var watcher = ScreenshotWatcher(storage: storage)
    private var controller: TermiNotesController?
    private var pendingPersistenceError: Error?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // Prefer the bundled resource if available
            if let iconPath = Bundle.main.path(forResource: "appicon", ofType: "png"),
               let iconImage = NSImage(contentsOfFile: iconPath) {
                iconImage.isTemplate = false
                iconImage.size = NSSize(width: 18, height: 18)
                button.image = iconImage
            } else if let iconImage = NSImage(contentsOfFile: "appicon.png") {
                // Fallback for running from source/CWD
                iconImage.isTemplate = false
                iconImage.size = NSSize(width: 18, height: 18)
                button.image = iconImage
            } else {
                button.title = ">_N"
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        let sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? false
        popover.contentSize = NSSize(width: sidebarVisible ? 400 + TermiNotesController.sidebarWidth : 400, height: 300)
        popover.behavior = .semitransient // stays up during sidebar drag-out / clicks
        watcher.onCapture = { [weak self] _ in self?.controller?.noteScreenshotCapture() }
        watcher.onError = { [weak self] error in
            guard let self else { return }
            if let controller = self.controller {
                controller.reportPersistenceError(error, operation: "Screenshot persistence")
            } else {
                self.pendingPersistenceError = error
                let message = "Screenshot persistence failed: \(error.localizedDescription)"
                NSLog("TermiNotes: %@", message)
                self.statusItem?.button?.toolTip = message
            }
        }
        watcher.start()
    }
    
    func setupMenu() {
        let mainMenu = NSMenu()
        
        // 1. Application Menu (Required for standard shortcuts)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About TermiNotes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit TermiNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        
        // 2. Edit Menu (Where Paste lives)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        let findMenu = NSMenu(title: "Find")
        let findItem = NSMenuItem(title: "Find...", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        findItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        findMenu.addItem(findItem)
        let findNextItem = NSMenuItem(title: "Find Next", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g")
        findNextItem.tag = Int(NSFindPanelAction.next.rawValue)
        findMenu.addItem(findNextItem)
        let findPrevItem = NSMenuItem(title: "Find Previous", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "G")
        findPrevItem.tag = Int(NSFindPanelAction.previous.rawValue)
        findMenu.addItem(findPrevItem)
        
        let findMainItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findMainItem.submenu = findMenu
        editMenu.addItem(findMainItem)

        editMenu.addItem(NSMenuItem.separator())
        
        let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(TermiNotesController.zoomIn), keyEquivalent: "=")
        zoomIn.keyEquivalentModifierMask = [.command]
        editMenu.addItem(zoomIn)
        let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(TermiNotesController.zoomOut), keyEquivalent: "-")
        zoomOut.keyEquivalentModifierMask = [.command]
        editMenu.addItem(zoomOut)
        
        let termCopy = NSMenuItem(title: "Copy for Terminal", action: #selector(TermiNotesController.copyForTerminal), keyEquivalent: "C")
        termCopy.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(termCopy)

        let foldItem = NSMenuItem(title: "Toggle Fold", action: #selector(TermiNotesController.toggleFold(_:)), keyEquivalent: "\\")
        editMenu.addItem(foldItem)
        let sideItem = NSMenuItem(title: "Screenshot Sidebar", action: #selector(TermiNotesController.toggleSidebar(_:)), keyEquivalent: "s")
        sideItem.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(sideItem)
        
        editMenu.addItem(NSMenuItem.separator())
        let launchToggle = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchToggle.state = isLaunchAtLoginEnabled() ? .on : .off
        editMenu.addItem(launchToggle)

        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    var launchAgentURL: URL {
        let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("LaunchAgents/com.rikiyanai.terminotes.plist")
    }

    func isLaunchAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if isLaunchAtLoginEnabled() {
            try? FileManager.default.removeItem(at: launchAgentURL)
            sender.state = .off
        } else {
            // For a raw binary, we need the absolute path. 
            // Since we're running from CWD usually, let's get the absolute path of the executable.
            let execPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
            
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.rikiyanai.terminotes</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            try? plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            sender.state = .on
        }
    }

    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover.isShown { popover.performClose(nil) }
            else {
                let controller = ensureController()
                if controller.sidebarVisible { controller.loadScreenshots() }
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                if let window = controller.textView.window {
                    window.makeKey()
                    window.makeFirstResponder(controller.textView)
                }
                controller.scheduleLayoutRefresh()
            }
        }
    }

    private func ensureController() -> TermiNotesController {
        if let controller { return controller }
        let created = TermiNotesController(storage: storage)
        controller = created
        popover.contentViewController = created
        popover.contentSize = NSSize(
            width: created.sidebarVisible ? 400 + TermiNotesController.sidebarWidth : 400,
            height: 300
        )
        _ = created.view
        if let pendingPersistenceError {
            created.reportPersistenceError(pendingPersistenceError, operation: "Screenshot persistence")
            self.pendingPersistenceError = nil
        }
        return created
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.flushSave()
    }
}

// MARK: - Screenshot sidebar views

/// A screenshot thumbnail: click to copy back to the clipboard, drag out to other apps.
/// Shows the stored file path underneath the image.
class ThumbnailView: NSView, NSDraggingSource {
    var fileURL: URL?
    var onClick: ((ThumbnailView, Int) -> Void)?
    private let imageView = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private var downPoint: NSPoint?
    private var dragStarted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(x: 0, y: 16, width: frame.width, height: frame.height - 16)
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        pathLabel.font = .systemFont(ofSize: 8)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.frame = NSRect(x: 2, y: 1, width: frame.width - 4, height: 13)
        pathLabel.autoresizingMask = [.width, .maxYMargin]
        addSubview(pathLabel)

        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setImage(_ image: NSImage) { imageView.image = image }
    func setPath(_ path: String) { pathLabel.stringValue = path }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragStarted
        downPoint = nil
        dragStarted = false
        if !wasDragging, bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?(self, event.clickCount)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Threshold: a real click often jitters a pixel or two — without this, every
        // slightly imperfect click became a 1px drag session and the click was lost.
        guard let url = fileURL, let down = downPoint, !dragStarted else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard abs(p.x - down.x) > 4 || abs(p.y - down.y) > 4 else { return }
        dragStarted = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        if let img = imageView.image {
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 80, height: 50), contents: img)
        }
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

#if !TERMINOTES_VERIFICATION
@main
struct TermiNotesApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
#endif
