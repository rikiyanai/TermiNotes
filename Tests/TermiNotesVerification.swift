import Foundation
import AppKit

enum VerificationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct TermiNotesVerification {
    static func main() throws {
        try verifyStorageRoundTrip()
        try verifyStorageFailureIsSurfaced()
        try verifyScreenshotWatcherSources()
        try verifyLineIndexCorrectness()
        try verifyLargeDocumentLookupCost()
        print("TermiNotes verification passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw VerificationFailure.failed(message) }
    }

    private static func verifyStorageRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiNotesVerification-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = TermiNotesStorage(rootDirectory: root)
        let note = "┌─ terminal ─┐\n│  exact     │\n└────────────┘"
        let toggles = [ToggleEntry(titleLine: 1, collapsed: true)]

        try storage.saveNote(note)
        try storage.saveToggles(toggles)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let firstBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        let secondBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x02])
        let firstURL = try storage.persistScreenshot(data: firstBytes, fileExtension: "png", date: timestamp)
        let secondURL = try storage.persistScreenshot(data: secondBytes, fileExtension: "png", date: timestamp)

        let loadedNote = try storage.loadNote()
        let loadedToggles = try storage.loadToggles()
        let loadedFirstBytes = try Data(contentsOf: firstURL)
        let loadedSecondBytes = try Data(contentsOf: secondURL)
        let screenshotCount = try storage.screenshotFiles().count
        try expect(loadedNote == note, "note round-trip changed terminal text")
        try expect(loadedToggles.count == 1, "toggle count changed")
        try expect(loadedToggles[0].titleLine == 1 && loadedToggles[0].collapsed, "toggle state changed")
        try expect(loadedFirstBytes == firstBytes, "first screenshot bytes changed")
        try expect(loadedSecondBytes == secondBytes, "second screenshot bytes changed")
        try expect(firstURL != secondURL, "same-second screenshots overwrote each other")
        try expect(screenshotCount == 2, "not every screenshot was indexed")
    }

    private static func verifyStorageFailureIsSurfaced() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiNotesVerification-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        let storage = TermiNotesStorage(rootDirectory: root)

        do {
            try storage.saveNote("must fail")
            throw VerificationFailure.failed("invalid storage root pretended to save a note")
        } catch let failure as VerificationFailure {
            throw failure
        } catch {}

        do {
            _ = try storage.persistScreenshot(data: Data([1, 2, 3]), fileExtension: "png")
            throw VerificationFailure.failed("invalid storage root pretended to save a screenshot")
        } catch let failure as VerificationFailure {
            throw failure
        } catch {}
    }

    private static func verifyLineIndexCorrectness() throws {
        let index = TextLineIndex()
        let original = "alpha\nβeta\ngamma" as NSString
        index.rebuild(for: original)
        try expect(index.starts == [0, 6, 11], "UTF-16 line starts are wrong")
        try expect(index.lineNumber(at: 5) == 0 && index.lineNumber(at: 6) == 1, "line lookup is wrong")
        try expect(index.range(ofLine: 1, stringLength: original.length) == NSRange(location: 6, length: 5), "line range is wrong")

        let inserted = "alpha\nβe\nnewta\ngamma" as NSString
        index.update(afterEditAt: 8, in: inserted)
        try expect(index.starts == [0, 6, 9, 15], "inserted newline was not indexed")

        let deleted = "alphaβe\nnewta\ngamma" as NSString
        index.update(afterEditAt: 5, in: deleted)
        try expect(index.starts == [0, 8, 14], "deleted newline remained indexed")
    }

    private static func verifyScreenshotWatcherSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermiNotesWatcherVerification-\(UUID().uuidString)", isDirectory: true)
        let watchDirectory = root.appendingPathComponent("source", isDirectory: true)
        let historyDirectory = root.appendingPathComponent("history", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: watchDirectory, withIntermediateDirectories: true)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TermiNotesVerification-\(UUID().uuidString)"))
        let storage = TermiNotesStorage(rootDirectory: historyDirectory)
        let watcher = ScreenshotWatcher(storage: storage, pasteboard: pasteboard, watchDirectory: watchDirectory)
        var ready = false
        var captures: [URL] = []
        var watcherError: Error?
        watcher.onReady = { ready = true }
        watcher.onCapture = { captures.append($0) }
        watcher.onError = { watcherError = $0 }
        watcher.start()
        try runMainLoop(until: { ready || watcherError != nil }, timeout: 3)
        if let watcherError { throw watcherError }
        try expect(ready, "screenshot watcher did not become ready")

        let clipboardPNG = try makePNG(color: .systemRed)
        pasteboard.clearContents()
        pasteboard.setData(clipboardPNG, forType: .png)
        try runMainLoop(until: { captures.count == 1 || watcherError != nil }, timeout: 3)
        if let watcherError { throw watcherError }
        let capturedClipboardBytes = try Data(contentsOf: captures[0])
        try expect(captures.count == 1, "clipboard screenshot was not persisted")
        try expect(capturedClipboardBytes == clipboardPNG, "clipboard screenshot bytes changed")

        let filePNG = try makePNG(color: .systemBlue)
        let sourceURL = watchDirectory.appendingPathComponent("Screenshot verification.png")
        try filePNG.write(to: sourceURL, options: .atomic)
        try runMainLoop(until: { captures.count == 2 || watcherError != nil }, timeout: 4)
        if let watcherError { throw watcherError }
        let storedScreenshotCount = try storage.screenshotFiles().count
        let fingerprints = try storage.loadScreenshotIndex()
        try expect(captures.count == 2, "file screenshot was not persisted after becoming stable")
        try expect(storedScreenshotCount == 2, "watcher did not retain both screenshot sources")
        try expect(fingerprints.count == 2, "screenshot fingerprint index did not track persisted files")
    }

    private static func makePNG(color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw VerificationFailure.failed("could not create verification PNG")
        }
        return png
    }

    private static func runMainLoop(until condition: () -> Bool, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expect(condition(), "asynchronous verification timed out after \(timeout) seconds")
    }

    private static func verifyLargeDocumentLookupCost() throws {
        let document = (0..<8_000).map { "\($0): ├── terminal structure ──────────────────────┤" }.joined(separator: "\n") as NSString
        let index = TextLineIndex()
        index.rebuild(for: document)
        let start = CFAbsoluteTimeGetCurrent()
        var checksum = 0
        for offset in stride(from: 0, to: document.length, by: 7) {
            checksum &+= index.lineNumber(at: offset)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        try expect(checksum > 0, "large-document lookup was not exercised")
        try expect(elapsed < 0.25, "indexed line lookup exceeded 250 ms: \(elapsed)")

        let tailOffset = document.length - 1
        let indexedStart = CFAbsoluteTimeGetCurrent()
        let indexedIterations = 200_000
        for _ in 0..<indexedIterations { checksum &+= index.lineNumber(at: tailOffset) }
        let indexedTailElapsed = CFAbsoluteTimeGetCurrent() - indexedStart
        let linearStart = CFAbsoluteTimeGetCurrent()
        let linearIterations = 200
        for _ in 0..<linearIterations { checksum &+= linearLineNumber(at: tailOffset, in: document) }
        let linearTailElapsed = CFAbsoluteTimeGetCurrent() - linearStart
        let indexedPerLookup = indexedTailElapsed / Double(indexedIterations)
        let linearPerLookup = linearTailElapsed / Double(linearIterations)
        try expect(indexedPerLookup * 20 < linearPerLookup, "line index did not materially beat repeated full scans")
        print(String(format: "indexed %d UTF-16 units in %.3f ms; tail lookup beat full scan", document.length, elapsed * 1_000))
    }

    private static func linearLineNumber(at offset: Int, in string: NSString) -> Int {
        var line = 0
        var cursor = 0
        while cursor < offset {
            if string.character(at: cursor) == 0x0A { line += 1 }
            cursor += 1
        }
        return line
    }
}
