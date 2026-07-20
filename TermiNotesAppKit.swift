import AppKit

class TerminalSanitizer {
    static func sanitize(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "[\u{201C}\u{201D}]", with: "\"", options: .regularExpression)
        result = result.replacingOccurrences(of: "[\u{2018}\u{2019}]", with: "'", options: .regularExpression)
        result = result.replacingOccurrences(of: "\u{2014}", with: "--")
        result = result.replacingOccurrences(of: "\u{2013}", with: "-")
        result = result.replacingOccurrences(of: "\u{2026}", with: "...")
        let lines = result.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1 {
            result = lines.joined(separator: " \\\n")
        } else {
            result = lines.first ?? ""
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Toggle List Model

/// A Notion-style toggle: `titleLine` stays visible, lines titleLine+1...bodyEndLine fold away.
/// Line numbers are 0-based global line indexes into the canvas; adjusted on every text edit
/// by the ledger in TermiNotesController.textStorage(didProcessEditing:).
struct ToggleEntry: Codable {
    var titleLine: Int
    var bodyEndLine: Int
    var collapsed: Bool
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

            // Force layout update to ensure all lines are rendered
            self.layoutManager?.ensureLayout(for: self.textContainer!)
            print("TermiNotes: Paste Success. Length: \(sanitized.count)")
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
        createItem.isEnabled = tc.selectionSpansMultipleLines()
        menu.insertItem(createItem, at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        // Option-click a toggle title line flips it, Notion-style chevron substitute.
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

    // MARK: Toggle list state
    var toggles: [ToggleEntry] = []
    var lastString: String = ""
    var foldsRendered = false

    // MARK: Screenshot sidebar state
    static let sidebarWidth: CGFloat = 180
    let sidebarContainer = NSView()
    let thumbsStack = NSStackView()
    let emptyLabel = NSTextField(labelWithString: "No screenshots yet")
    var screenshotFiles: [URL] = []
    let watcher = ScreenshotWatcher()
    var sidebarVisible: Bool = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true

    var appSupportDir: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("TermiNotes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    var saveURL: URL { appSupportDir.appendingPathComponent("notes.txt") }
    var togglesURL: URL { appSupportDir.appendingPathComponent("toggles.json") }
    var screenshotsDir: URL {
        let dir = appSupportDir.appendingPathComponent("screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
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

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        scrollView.documentView = textView
        container.addSubview(scrollView)

        // Screenshot sidebar (hidable), pinned right
        sidebarContainer.frame = NSRect(x: 400 - sideW, y: 40, width: max(sideW, 1), height: 230)
        sidebarContainer.autoresizingMask = []
        sidebarContainer.isHidden = !sidebarVisible

        let sideHeader = NSTextField(labelWithString: "Screenshots")
        sideHeader.font = .systemFont(ofSize: 11, weight: .bold)
        sideHeader.textColor = .secondaryLabelColor
        sideHeader.frame = NSRect(x: 8, y: 206, width: 120, height: 20)
        sideHeader.autoresizingMask = [.minYMargin]
        sidebarContainer.addSubview(sideHeader)

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

        // Resize Handle
        let resizeHandle = ResizeHandleView(frame: NSRect(x: 385, y: 0, width: 15, height: 15))
        resizeHandle.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(resizeHandle)

        self.view = container

        textView.toggleController = self
        textView.textStorage?.delegate = self
        loadSavedContent()
        lastString = textView.string
        loadToggles()
        renderToggles()

        // Screenshot clipboard watcher (runs from app launch, popover closed or not)
        watcher.screenshotsDir = screenshotsDir
        watcher.onCapture = { [weak self] _ in self?.loadScreenshots() }
        watcher.start()
        loadScreenshots()
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
    }

    func loadSavedContent() {
        if let content = try? String(contentsOf: saveURL, encoding: .utf8) {
            textView.string = content
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            updateWidth()
        }
    }

    func textDidChange(_ notification: Notification) {
        saveContent()
        if !toggles.isEmpty || foldsRendered {
            saveToggles()
            renderToggles()
        } else {
            updateWidth()
        }
    }

    func updateWidth() {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

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
        try? textView.string.write(to: saveURL, atomically: true, encoding: .utf8)
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
        let range = NSRange(location: 0, length: textView.string.count)
        if textView.shouldChangeText(in: range, replacementString: "") {
            textView.textStorage?.replaceCharacters(in: range, with: "")
            textView.didChangeText()
            saveContent()
        }
    }
    @objc func quitApp() {
        saveContent()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Toggle lists

    func lineIndex(ofChar idx: Int) -> Int {
        lineIndex(ofChar: idx, in: textView.string as NSString)
    }

    /// 0-based line index = number of newlines strictly before `idx`.
    func lineIndex(ofChar idx: Int, in s: NSString) -> Int {
        var line = 0
        var i = 0
        let limit = max(0, min(idx, s.length))
        while i < limit {
            if s.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        return line
    }

    func charRangeOfLine(_ line: Int) -> NSRange? {
        let s = textView.string as NSString
        if line < 0 { return nil }
        var current = 0
        var start = 0
        while start <= s.length {
            let r = s.lineRange(for: NSRange(location: start, length: 0))
            if current == line { return r }
            if r.upperBound <= start { return nil }
            start = r.upperBound
            current += 1
        }
        return nil
    }

    func charRange(fromLine a: Int, throughLine b: Int) -> NSRange? {
        guard let ra = charRangeOfLine(a), let rb = charRangeOfLine(b), rb.upperBound >= ra.location else { return nil }
        return NSRange(location: ra.location, length: rb.upperBound - ra.location)
    }

    func toggle(containing line: Int) -> ToggleEntry? {
        guard line >= 0 else { return nil }
        return toggles.first { line >= $0.titleLine && line <= $0.bodyEndLine }
    }

    func selectionSpansMultipleLines() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { return false }
        let s = textView.string as NSString
        return lineIndex(ofChar: max(sel.location, sel.upperBound - 1), in: s) > lineIndex(ofChar: sel.location, in: s)
    }

    @objc func createToggleFromSelection(_ sender: Any?) {
        let sel = textView.selectedRange()
        let s = textView.string as NSString
        guard sel.length > 0 else { return }
        let title = lineIndex(ofChar: sel.location, in: s)
        let end = lineIndex(ofChar: max(sel.location, sel.upperBound - 1), in: s)
        guard end > title else { return }
        // v1: no nesting — a new toggle flattens any it overlaps.
        toggles.removeAll { $0.titleLine <= end && $0.bodyEndLine >= title }
        toggles.append(ToggleEntry(titleLine: title, bodyEndLine: end, collapsed: true))
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
        guard line >= 0, let i = toggles.firstIndex(where: {
            line >= $0.titleLine && line <= $0.bodyEndLine && (!titleOnly || line == $0.titleLine)
        }) else { return false }
        toggles[i].collapsed.toggle()
        saveToggles()
        renderToggles()
        return true
    }

    @objc func flipContextToggle(_ sender: Any?) {
        _ = flipToggle(atLine: textView.contextMenuLine)
    }

    @objc func removeContextToggle(_ sender: Any?) {
        let line = textView.contextMenuLine
        let before = toggles.count
        toggles.removeAll { $0.titleLine <= line && $0.bodyEndLine >= line }
        if toggles.count != before {
            saveToggles()
            renderToggles()
        }
    }

    /// Cmd+\ — flip the toggle containing the caret, if any.
    @objc func toggleFold(_ sender: Any?) {
        _ = flipToggle(atLine: lineIndex(ofChar: textView.selectedRange().location))
    }

    /// Line-number ledger: shift toggle boundaries on every edit so folds track the text.
    /// Runs in didProcessEditing (pre-save), against lastString (pre-edit snapshot).
    func adjustToggles(editedRange: NSRange, changeInLength delta: Int) {
        let newS = textView.string as NSString
        let oldS = lastString as NSString
        let preLocation = min(editedRange.location, oldS.length)
        let preLength = max(0, min(editedRange.length - delta, oldS.length - preLocation))
        let preRange = NSRange(location: preLocation, length: preLength)
        let isInsertion = preRange.length == 0
        let editStartLine = lineIndex(ofChar: editedRange.location, in: newS)
        let oldEditEndLine = lineIndex(ofChar: preRange.upperBound, in: oldS)
        let newEditEndLine = lineIndex(ofChar: min(editedRange.upperBound, newS.length), in: newS)
        let shift = newEditEndLine - oldEditEndLine

        var out: [ToggleEntry] = []
        out.reserveCapacity(toggles.count)
        for var t in toggles {
            if t.bodyEndLine < editStartLine {
                out.append(t) // entirely before the edit
            } else if isInsertion {
                // Nothing destroyed: shift the toggle only if the insertion lands
                // at or before the title line's first character.
                let titleStart = charRangeOfLine(t.titleLine)?.location ?? Int.max
                if editedRange.location <= titleStart {
                    t.titleLine += shift
                    t.bodyEndLine += shift
                } else {
                    t.bodyEndLine += shift
                }
                out.append(t)
            } else if t.titleLine > oldEditEndLine {
                t.titleLine += shift // entirely after the replaced region
                t.bodyEndLine += shift
                out.append(t)
            } else if t.titleLine >= editStartLine {
                continue // title line destroyed — drop the toggle
            } else {
                // Body partially eaten: clamp or shift the body end.
                t.bodyEndLine = t.bodyEndLine > oldEditEndLine ? t.bodyEndLine + shift : newEditEndLine
                if t.bodyEndLine > t.titleLine { out.append(t) }
            }
        }
        toggles = out
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        if !toggles.isEmpty {
            adjustToggles(editedRange: editedRange, changeInLength: delta)
        }
        lastString = textView.string
    }

    /// Keep the caret out of collapsed (invisible) body text.
    func textViewDidChangeSelection(_ notification: Notification) {
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return }
        let line = lineIndex(ofChar: sel.location)
        for t in toggles where t.collapsed {
            if line > t.titleLine && line <= t.bodyEndLine {
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
        guard let data = try? Data(contentsOf: togglesURL),
              let arr = try? JSONDecoder().decode([ToggleEntry].self, from: data) else { return }
        let s = textView.string as NSString
        let maxLine = lineIndex(ofChar: s.length, in: s)
        toggles = arr.compactMap { t in
            guard t.titleLine >= 0, t.bodyEndLine > t.titleLine, t.titleLine <= maxLine else { return nil }
            return ToggleEntry(titleLine: t.titleLine, bodyEndLine: min(t.bodyEndLine, maxLine), collapsed: t.collapsed)
        }.sorted { $0.titleLine < $1.titleLine }
    }

    func saveToggles() {
        guard let data = try? JSONEncoder().encode(toggles) else { return }
        try? data.write(to: togglesURL, options: .atomic)
    }

    /// Fold rendering never touches the string: collapsed body lines get a 0.1pt font +
    /// clear color as *temporary* layout attributes, so copy/save/undo are unaffected.
    func renderToggles() {
        guard let lm = textView.layoutManager else { return }
        let s = textView.string as NSString
        let full = NSRange(location: 0, length: s.length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        lm.removeTemporaryAttribute(.font, forCharacterRange: full)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        foldsRendered = !toggles.isEmpty
        for t in toggles {
            guard let titleRange = charRangeOfLine(t.titleLine) else { continue }
            let tint = NSRange(location: titleRange.location, length: max(0, titleRange.length - 1))
            lm.addTemporaryAttribute(.backgroundColor,
                                     value: NSColor.labelColor.withAlphaComponent(t.collapsed ? 0.14 : 0.07),
                                     forCharacterRange: tint)
            if t.collapsed, let bodyRange = charRange(fromLine: t.titleLine + 1, throughLine: t.bodyEndLine), bodyRange.length > 0 {
                lm.addTemporaryAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), forCharacterRange: bodyRange)
                lm.addTemporaryAttribute(.foregroundColor, value: NSColor.clear, forCharacterRange: bodyRange)
            }
        }
        updateWidth()
    }

    // MARK: - Screenshot sidebar

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
    }

    func loadScreenshots() {
        let files = (try? FileManager.default.contentsOfDirectory(at: screenshotsDir, includingPropertiesForKeys: nil)) ?? []
        var pngs = files.filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        if pngs.count > 50 {
            for url in pngs.dropFirst(50) { try? FileManager.default.removeItem(at: url) }
            pngs = Array(pngs.prefix(50))
        }
        screenshotFiles = pngs
        rebuildThumbs()
    }

    func makeThumb(from url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else { return nil }
        let scale = min(320 / img.size.width, 200 / img.size.height, 1.0)
        let target = NSSize(width: floor(img.size.width * scale), height: floor(img.size.height * scale))
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: target), from: NSRect(origin: .zero, size: img.size), operation: .sourceOver, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    func rebuildThumbs() {
        thumbsStack.arrangedSubviews.forEach { thumbsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        emptyLabel.isHidden = !screenshotFiles.isEmpty
        for url in screenshotFiles {
            guard let thumb = makeThumb(from: url) else { continue }
            let view = ThumbnailView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
            view.fileURL = url
            view.setImage(thumb)
            view.toolTip = url.lastPathComponent
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: 160),
                view.heightAnchor.constraint(equalToConstant: 100)
            ])
            view.onClick = { [weak self] v in self?.thumbClicked(v) }
            thumbsStack.addArrangedSubview(view)
        }
    }

    /// Single click copies the image back to the clipboard (Maccy-style);
    /// double click additionally inserts a markdown image link at the caret.
    func thumbClicked(_ view: ThumbnailView) {
        guard let url = view.fileURL, let img = NSImage(contentsOf: url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let tiff = img.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        if let data = try? Data(contentsOf: url) { pb.setData(data, forType: .png) }
        watcher.ignoreCurrentPasteboard() // don't re-capture our own copy
        if NSApp.currentEvent?.clickCount == 2 {
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
    let controller = TermiNotesController()

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
        popover.contentSize = NSSize(width: controller.sidebarVisible ? 400 + TermiNotesController.sidebarWidth : 400, height: 300)
        popover.behavior = .semitransient // stays up during sidebar drag-out / clicks
        popover.contentViewController = controller
        _ = controller.view // force loadView so the screenshot watcher starts at launch
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
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                if let window = controller.textView.window {
                    window.makeKey()
                    window.makeFirstResponder(controller.textView)
                }
            }
        }
    }
}

// MARK: - Screenshot sidebar views

/// A screenshot thumbnail: click to copy back to the clipboard, drag out to other apps.
class ThumbnailView: NSView, NSDraggingSource {
    var fileURL: URL?
    var onClick: ((ThumbnailView) -> Void)?
    private let imageView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setImage(_ image: NSImage) { imageView.image = image }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url = fileURL else { return }
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

// MARK: - Screenshot clipboard watcher

/// Polls the general pasteboard (~1s) and snapshots image content (screenshots) to disk.
/// Images only — text and file copies are ignored.
class ScreenshotWatcher: NSObject {
    var screenshotsDir: URL?
    var onCapture: ((URL) -> Void)?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    /// Call after WE write to the pasteboard (thumbnail click-copy) so it isn't re-captured.
    func ignoreCurrentPasteboard() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        var png = pb.data(forType: .png)
        if png == nil, let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            png = rep.representation(using: .png, properties: [:])
        }
        guard let data = png, let dir = screenshotsDir else { return }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = fmt.string(from: Date())
        var url = dir.appendingPathComponent("\(stamp).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stamp)-\(n).png")
            n += 1
        }
        try? data.write(to: url)
        onCapture?(url)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
