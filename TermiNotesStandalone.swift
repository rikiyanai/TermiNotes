import SwiftUI
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

struct ContentView: View {
    @Environment(\.undoManager) var undoManager
    @AppStorage("termi_notes_content") private var noteText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TermiNotes").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Button(action: copyForTerminal) {
                    Label("Copy for Terminal", systemImage: "terminal").font(.caption)
                }.buttonStyle(.plain).keyboardShortcut("c", modifiers: [.command, .shift])
            }.padding(8).background(Color(NSColor.windowBackgroundColor))
            Divider()
            TextEditor(text: $noteText)
                .font(.system(size: 13, design: .monospaced))
                .focused($isFocused)
                .autocorrectionDisabled(true)
                .padding(4)
            Divider()
            HStack {
                Button("Clear") {
                    let oldText = noteText
                    undoManager?.registerUndo(withTarget: NSApp) { _ in
                        noteText = oldText
                    }
                    noteText = ""
                }.buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.bordered).controlSize(.small)
            }.padding(8).background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 400, height: 300)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
    
    private func copyForTerminal() {
        let sanitized = TerminalSanitizer.sanitize(noteText)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = ">_N"
            button.action = #selector(togglePopover)
            button.target = self
        }
        let contentView = ContentView()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Force show it once to prove it works
        togglePopover()
    }

    func setupMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About TermiNotes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit TermiNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
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
            }
        }
    }
}

// Manual Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
