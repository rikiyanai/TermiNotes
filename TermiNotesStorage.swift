import Foundation

struct ScreenshotFingerprint: Codable {
    let byteCount: Int
    let modificationTime: TimeInterval
    let sha256: Data

    func matches(_ values: URLResourceValues) -> Bool {
        byteCount == values.fileSize &&
            modificationTime == values.contentModificationDate?.timeIntervalSinceReferenceDate
    }
}

/// The sole owner of TermiNotes' durable files. Callers provide values and receive
/// explicit errors; path creation and atomic replacement stay behind this interface.
final class TermiNotesStorage {
    static let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "heic", "gif", "bmp"]

    let rootDirectory: URL
    let screenshotsDirectory: URL

    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TermiNotes", isDirectory: true)
        self.rootDirectory = rootDirectory ?? defaultRoot
        self.screenshotsDirectory = self.rootDirectory.appendingPathComponent("screenshots", isDirectory: true)
    }

    var notesURL: URL { rootDirectory.appendingPathComponent("notes.txt") }
    var togglesURL: URL { rootDirectory.appendingPathComponent("toggles.json") }
    var screenshotIndexURL: URL { rootDirectory.appendingPathComponent("screenshot-index.json") }

    func prepare() throws {
        try fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
    }

    func loadNote() throws -> String? {
        guard fileManager.fileExists(atPath: notesURL.path) else { return nil }
        return try String(contentsOf: notesURL, encoding: .utf8)
    }

    func saveNote(_ text: String) throws {
        try prepare()
        try text.write(to: notesURL, atomically: true, encoding: .utf8)
    }

    func loadToggles() throws -> [ToggleEntry] {
        guard fileManager.fileExists(atPath: togglesURL.path) else { return [] }
        return try JSONDecoder().decode([ToggleEntry].self, from: Data(contentsOf: togglesURL))
    }

    func saveToggles(_ toggles: [ToggleEntry]) throws {
        try prepare()
        try JSONEncoder().encode(toggles).write(to: togglesURL, options: .atomic)
    }

    func loadScreenshotIndex() throws -> [String: ScreenshotFingerprint] {
        guard fileManager.fileExists(atPath: screenshotIndexURL.path) else { return [:] }
        return try JSONDecoder().decode(
            [String: ScreenshotFingerprint].self,
            from: Data(contentsOf: screenshotIndexURL)
        )
    }

    func saveScreenshotIndex(_ index: [String: ScreenshotFingerprint]) throws {
        try prepare()
        try JSONEncoder().encode(index).write(to: screenshotIndexURL, options: .atomic)
    }

    func resourceValues(forScreenshot url: URL) throws -> URLResourceValues {
        try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    }

    func screenshotFiles() throws -> [URL] {
        try prepare()
        return try fileManager.contentsOfDirectory(
            at: screenshotsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { Self.screenshotExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Publishes a complete image with an atomic write. The callback path is returned
    /// only after the bytes are durably visible at the final Application Support URL.
    func persistScreenshot(data: Data, fileExtension: String, date: Date = Date()) throws -> URL {
        try prepare()
        let normalizedExtension = fileExtension.lowercased().isEmpty ? "png" : fileExtension.lowercased()
        let baseName = Self.timestamp(for: date)
        var destination = screenshotsDirectory.appendingPathComponent("\(baseName).\(normalizedExtension)")
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = screenshotsDirectory.appendingPathComponent("\(baseName)-\(suffix).\(normalizedExtension)")
            suffix += 1
        }
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}
