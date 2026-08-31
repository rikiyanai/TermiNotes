import Foundation

struct TerminalSanitizer {
    /// Sanitizes text for safe pasting into a terminal.
    /// - Converts smart quotes and dashes to ASCII.
    /// - Preserves leading and trailing spaces on every retained line.
    /// - Joins multiple lines with " \" to prevent immediate execution.
    /// - Removes only trailing newline separators.
    static func sanitize(_ text: String) -> String {
        var result = text
        
        // 1. Replace Smart Quotes
        result = result.replacingOccurrences(of: "[\u{201C}\u{201D}]", with: "\"", options: .regularExpression)
        result = result.replacingOccurrences(of: "[\u{2018}\u{2019}]", with: "'", options: .regularExpression)
        
        // 2. Replace Smart Dashes/Ellipses
        result = result.replacingOccurrences(of: "\u{2014}", with: "--") // Em dash
        result = result.replacingOccurrences(of: "\u{2013}", with: "-")  // En dash
        result = result.replacingOccurrences(of: "\u{2026}", with: "...") // Ellipsis
        
        // 3. Handle Multiline Commands
        var lines = result.components(separatedBy: .newlines)
        while lines.last == "" { lines.removeLast() }

        guard !lines.isEmpty else { return "" }
        
        if lines.count > 1 {
            // Join with backslash for line continuation
            result = lines.joined(separator: " \\\n")
        } else {
            result = lines.first ?? ""
        }
        
        // 4. The line split removed trailing newline separators without touching
        // indentation or intentional spaces inside the retained lines.
        return result
    }
}
