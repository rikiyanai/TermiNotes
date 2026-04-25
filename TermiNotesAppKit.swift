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

class TermiTextView: NSTextView {
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
}

class TermiNotesController: NSViewController, NSTextViewDelegate {
    let textView = TermiTextView()
    let scrollView = NSScrollView()
    var currentFontSize: CGFloat = 13.0
    
    var saveURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("TermiNotes")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("notes.txt")
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
        
        let copyButton = NSButton(title: "Copy for Terminal", target: self, action: #selector(copyForTerminal))
        copyButton.bezelStyle = .inline
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.frame = NSRect(x: 270, y: 275, width: 120, height: 20)
        copyButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(copyButton)
        
        // ScrollView Setup
        scrollView.frame = NSRect(x: 0, y: 40, width: 400, height: 230)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        
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
        loadSavedContent()
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
        updateWidth()
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
        textView.string = ""
        saveContent()
    }
    @objc func quitApp() { 
        saveContent()
        NSApplication.shared.terminate(nil) 
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
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = controller
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
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
