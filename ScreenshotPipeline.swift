import AppKit
import CryptoKit
import Darwin
import ImageIO

/// Owns screenshot source observation and persistence. Pasteboard access stays on the
/// main thread; hashing, directory scans, and writes run on one utility queue.
final class ScreenshotWatcher {
    static let imageExtensions = TermiNotesStorage.screenshotExtensions

    var onCapture: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    var onReady: (() -> Void)?

    private let storage: TermiNotesStorage
    private let pasteboard: NSPasteboard
    private let suppliedWatchDirectory: URL?
    private let worker = DispatchQueue(label: "TermiNotes.ScreenshotWatcher", qos: .utility)
    private var timer: Timer?
    private var lastPasteboardChangeCount: Int

    // Accessed only on worker.
    private var watchDirectory: URL?
    private var knownFiles: Set<String> = []
    private var pendingSizes: [String: UInt64] = [:]
    private var knownHashes = Set<Data>()
    private var fingerprintIndex: [String: ScreenshotFingerprint] = [:]

    init(storage: TermiNotesStorage) {
        self.storage = storage
        self.pasteboard = .general
        self.suppliedWatchDirectory = nil
        self.lastPasteboardChangeCount = NSPasteboard.general.changeCount
    }

    /// Verification seam: a named pasteboard and temporary watch directory exercise
    /// the production pipeline without mutating the user's clipboard or Desktop.
    init(storage: TermiNotesStorage, pasteboard: NSPasteboard, watchDirectory: URL?) {
        self.storage = storage
        self.pasteboard = pasteboard
        self.suppliedWatchDirectory = watchDirectory
        self.lastPasteboardChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        worker.async { [weak self] in
            guard let self else { return }
            do {
                try self.storage.prepare()
                // Desktop is privacy-controlled and may block even open(2) indefinitely
                // for an accessory app. Runtime capture is clipboard-first; a file folder
                // is watched only when a caller supplies a user-authorized URL.
                self.watchDirectory = self.suppliedWatchDirectory
                if let watchDirectory = self.watchDirectory {
                    do {
                        self.knownFiles = Set(try Self.directoryNames(at: watchDirectory))
                    } catch {
                        // Clipboard capture remains available if the configured screenshot
                        // folder is missing or denied.
                        self.watchDirectory = nil
                        self.emit(error: error)
                    }
                }
                try self.loadKnownHashes()
                DispatchQueue.main.async { [weak self] in self?.startTimer() }
            } catch {
                self.emit(error: error)
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
            self?.worker.async { [weak self] in self?.checkWatchDirectory() }
        }
        onReady?()
    }

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount

        var pngData = pasteboard.data(forType: .png)
        if pngData == nil,
           let tiffData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiffData) {
            pngData = bitmap.representation(using: .png, properties: [:])
        }
        guard let pngData else { return }

        worker.async { [weak self] in
            guard let self else { return }
            do {
                let hash = Self.digest(pngData)
                guard self.knownHashes.insert(hash).inserted else { return }
                do {
                    let destination = try self.storage.persistScreenshot(data: pngData, fileExtension: "png")
                    do { try self.recordFingerprint(for: destination, hash: hash) }
                    catch { self.emit(error: error) }
                    self.emit(capture: destination)
                } catch {
                    self.knownHashes.remove(hash)
                    throw error
                }
            } catch {
                self.emit(error: error)
            }
        }
    }

    private func checkWatchDirectory() {
        guard let watchDirectory else { return }
        do {
            let files = try Self.directoryNames(at: watchDirectory)
            knownFiles.formIntersection(files)
            for name in files where !knownFiles.contains(name) {
                let fileExtension = (name as NSString).pathExtension.lowercased()
                guard Self.imageExtensions.contains(fileExtension) else {
                    knownFiles.insert(name)
                    continue
                }
                let source = watchDirectory.appendingPathComponent(name)
                let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                if let priorSize = pendingSizes[name], priorSize == size, size > 0 {
                    knownFiles.insert(name)
                    pendingSizes.removeValue(forKey: name)
                    try importFile(source, attributes: attributes)
                } else {
                    pendingSizes[name] = size
                }
            }
            pendingSizes = pendingSizes.filter { files.contains($0.key) }
        } catch {
            self.watchDirectory = nil
            emit(error: error)
        }
    }

    private func importFile(_ source: URL, attributes: [FileAttributeKey: Any]) throws {
        let data = try Data(contentsOf: source, options: [.mappedIfSafe])
        let hash = Self.digest(data)
        guard knownHashes.insert(hash).inserted else { return }
        do {
            let creationDate = (attributes[.creationDate] as? Date) ?? Date()
            let destination = try storage.persistScreenshot(
                data: data,
                fileExtension: source.pathExtension,
                date: creationDate
            )
            do { try recordFingerprint(for: destination, hash: hash) }
            catch { emit(error: error) }
            emit(capture: destination)
        } catch {
            knownHashes.remove(hash)
            throw error
        }
    }

    /// Desktop may contain aliases or cloud-managed entries that make Foundation's
    /// coordinated directory listing block for tens of seconds. Screenshot discovery
    /// needs names only, so use the direct directory interface and fetch metadata solely
    /// for new image candidates.
    private static func directoryNames(at directoryURL: URL) throws -> [String] {
        guard let directory = opendir(directoryURL.path) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func digest(of url: URL) throws -> Data {
        digest(try Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    private func loadKnownHashes() throws {
        let files = try storage.screenshotFiles()
        do {
            fingerprintIndex = try storage.loadScreenshotIndex()
        } catch {
            // The index is a rebuildable cache, never the screenshot truth. Surface the
            // corruption, then rebuild from the files rather than disabling capture.
            fingerprintIndex = [:]
            emit(error: error)
        }

        var refreshed: [String: ScreenshotFingerprint] = [:]
        refreshed.reserveCapacity(files.count)
        var changed = fingerprintIndex.count != files.count
        for file in files {
            do {
                let values = try storage.resourceValues(forScreenshot: file)
                let name = file.lastPathComponent
                if let cached = fingerprintIndex[name], cached.matches(values) {
                    refreshed[name] = cached
                    knownHashes.insert(cached.sha256)
                    continue
                }
                let hash = try autoreleasepool { try Self.digest(of: file) }
                let fingerprint = ScreenshotFingerprint(
                    byteCount: values.fileSize ?? 0,
                    modificationTime: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0,
                    sha256: hash
                )
                refreshed[name] = fingerprint
                knownHashes.insert(hash)
                changed = true
            } catch {
                emit(error: error)
            }
        }
        fingerprintIndex = refreshed
        if changed {
            do { try storage.saveScreenshotIndex(fingerprintIndex) }
            catch { emit(error: error) }
        }
    }

    private func recordFingerprint(for url: URL, hash: Data) throws {
        let values = try storage.resourceValues(forScreenshot: url)
        fingerprintIndex[url.lastPathComponent] = ScreenshotFingerprint(
            byteCount: values.fileSize ?? 0,
            modificationTime: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0,
            sha256: hash
        )
        try storage.saveScreenshotIndex(fingerprintIndex)
    }

    private func emit(capture url: URL) {
        DispatchQueue.main.async { [weak self] in self?.onCapture?(url) }
    }

    private func emit(error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onError?(error) }
    }
}

/// Generates bounded thumbnails without decoding full-resolution images on the main
/// thread. Immutable screenshot URLs make the path-keyed cache safe.
final class ScreenshotThumbnailLoader {
    private let cache = NSCache<NSURL, NSImage>()
    // Serial decoding avoids a burst of 50 full image-source reads when the shelf opens.
    private let worker = DispatchQueue(label: "TermiNotes.ThumbnailLoader", qos: .userInitiated)

    func load(_ url: URL, maximumPixelSize: Int = 320, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        worker.async { [weak self] in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ]
            let image: NSImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                image = NSImage(cgImage: thumbnail, size: .zero)
            } else {
                image = nil
            }
            if let image { self?.cache.setObject(image, forKey: url as NSURL) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
