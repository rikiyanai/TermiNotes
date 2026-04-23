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

class TermiNotesController: NSViewController {
    let textView = NSTextView()
    let scrollView = NSScrollView()
    var currentFontSize: CGFloat = 13.0
    
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
        
        // ScrollView + TextView
        scrollView.frame = NSRect(x: 0, y: 40, width: 400, height: 230)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: currentFontSize, weight: .regular)
        
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
    }
    
    @objc func zoomIn() {
        currentFontSize += 1
        updateFont()
    }
    
    @objc func zoomOut() {
        if currentFontSize > 5 {
            currentFontSize -= 1
            updateFont()
        }
    }
    
    func updateFont() {
        textView.font = .monospacedSystemFont(ofSize: currentFontSize, weight: .regular)
    }

    @objc func copyForTerminal() {
        let sanitized = TerminalSanitizer.sanitize(textView.string)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }
    
    @objc func clearAll() { textView.string = "" }
    @objc func quitApp() { NSApplication.shared.terminate(nil) }
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
        
        let path2 = NSBezierPath()
        path2.move(to: NSPoint(x: bounds.width, y: 5))
        path2.line(to: NSPoint(x: 5, y: bounds.height))
        path2.lineWidth = 1.5
        path2.stroke()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window, let popover = (NSApp.delegate as? AppDelegate)?.popover else { return }
        
        var newSize = popover.contentSize
        newSize.width += event.deltaX
        newSize.height -= event.deltaY // Popovers measure from top, deltaY is screen-coord based
        
        // Constraints
        newSize.width = max(200, min(1000, newSize.width))
        newSize.height = max(150, min(800, newSize.height))
        
        popover.contentSize = newSize
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let popover = NSPopover()
    let controller = TermiNotesController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "TN"
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = controller
    }
    
    func setupMenu() {
        let mainMenu = NSMenu()
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
        
        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                controller.textView.window?.makeFirstResponder(controller.textView)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
