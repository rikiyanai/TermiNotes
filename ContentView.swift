import SwiftUI

struct ContentView: View {
    @AppStorage("termi_notes_content") private var noteText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimal Header
            HStack {
                Text("TermiNotes")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: copyForTerminal) {
                    Label("Copy for Terminal", systemImage: "terminal")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Sanitizes and copies for terminal (CMD+Shift+C)")
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // The Editor
            TextEditor(text: $noteText)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .focused($isFocused)
                .autocorrectionDisabled(true)
                .padding(4)
            
            Divider()
            
            // Footer Utilities
            HStack {
                Button("Clear") {
                    noteText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 400, height: 300)
        .onAppear {
            // Auto-focus on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
    
    private func copyForTerminal() {
        let sanitized = TerminalSanitizer.sanitize(noteText)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
