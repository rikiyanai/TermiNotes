import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = ">_N"
            button.action = #selector(showTestWindow)
            button.target = self
        }
        
        showTestWindow()
    }

    @objc func showTestWindow() {
        if window == nil {
            let rect = NSRect(x: 0, y: 0, width: 400, height: 300)
            window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window?.center()
            window?.title = "AppKit Test"
            
            let textView = NSTextView(frame: rect)
            textView.string = "If you see this, AppKit is working."
            textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            
            window?.contentView = textView
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // Show in Dock for testing
app.run()
