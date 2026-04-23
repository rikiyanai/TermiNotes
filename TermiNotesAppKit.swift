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
    
    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        // Header
        let header = NSView(frame: NSRect(x: 0, y: 270, width: 400, height: 300))
        let label = NSTextField(labelWithString: "TermiNotes")
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 8, y: 275, width: 100, height: 20)
        container.addSubview(label)
        
        let copyButton = NSButton(title: "Copy for Terminal", target: self, action: #selector(copyForTerminal))
        copyButton.bezelStyle = .inline
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.frame = NSRect(x: 270, y: 275, width: 120, height: 20)
        copyButton.toolTip = "Sanitizes and copies (CMD+Shift+C)"
        container.addSubview(copyButton)
        
        // ScrollView + TextView
        scrollView.frame = NSRect(x: 0, y: 40, width: 400, height: 230)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        textView.minSize = NSSize(width: 0, height: 230)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = .width
        
        // Disable Line Wrapping
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        scrollView.documentView = textView
        container.addSubview(scrollView)
        
        // Footer
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded
        clearButton.frame = NSRect(x: 8, y: 8, width: 70, height: 25)
        container.addSubview(clearButton)
        
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: 322, y: 8, width: 70, height: 25)
        container.addSubview(quitButton)
        
        self.view = container
    }
    
    @objc func copyForTerminal() {
        let sanitized = TerminalSanitizer.sanitize(textView.string)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }
    
    @objc func clearAll() {
        textView.string = ""
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
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
    
    // CRITICAL: Setup the Edit menu so Copy/Paste shortcuts work
    func setupMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        // Add our custom shortcut
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
