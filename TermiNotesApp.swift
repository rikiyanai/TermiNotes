import SwiftUI
import AppKit

@main
class TermiNotesApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    
    // This is the manual entry point
    static func main() {
        let app = NSApplication.shared
        let delegate = TermiNotesApp() // Retain the delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        print("TermiNotes: App starting...")
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        print("TermiNotes: Finished launching, setting up UI...")
        
        // Create the Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = ">_N"
            button.action = #selector(togglePopover)
            print("TermiNotes: Status item created with title '>_N'")
        } else {
            print("TermiNotes: Failed to create status item button")
        }

        // Create the SwiftUI View
        let contentView = ContentView()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        print("TermiNotes: Popover initialized")
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
        print("TermiNotes: Toggle popover requested")
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
                print("TermiNotes: Popover closed")
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                print("TermiNotes: Popover shown")
            }
        }
    }
}
