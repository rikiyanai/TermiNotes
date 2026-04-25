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
