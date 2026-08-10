import Foundation

/// A UTF-16 line-start index matching NSTextView/NSRange offsets. It turns caret and
/// toggle lookups into binary searches and rescans only from the edited line onward.
final class TextLineIndex {
    private(set) var starts: [Int] = [0]

    var lastLine: Int { max(0, starts.count - 1) }

    func rebuild(for string: NSString) {
        starts = [0]
        appendLineStarts(in: string, from: 0)
    }

    func update(afterEditAt location: Int, in string: NSString) {
        let anchorLine = lineNumber(at: location)
        let anchorOffset = starts[anchorLine]
        if anchorLine + 1 < starts.count {
            starts.removeSubrange((anchorLine + 1)..<starts.count)
        }
        appendLineStarts(in: string, from: anchorOffset)
    }

    func lineNumber(at offset: Int) -> Int {
        Self.lineNumber(at: offset, starts: starts)
    }

    func range(ofLine line: Int, stringLength: Int) -> NSRange? {
        guard line >= 0, line < starts.count else { return nil }
        let start = min(starts[line], stringLength)
        let end = line + 1 < starts.count ? min(starts[line + 1], stringLength) : stringLength
        return NSRange(location: start, length: max(0, end - start))
    }

    func start(ofLine line: Int) -> Int? {
        guard line >= 0, line < starts.count else { return nil }
        return starts[line]
    }

    static func lineNumber(at offset: Int, starts: [Int]) -> Int {
        let target = max(0, offset)
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= target {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return max(0, low - 1)
    }

    private func appendLineStarts(in string: NSString, from offset: Int) {
        guard offset < string.length else { return }
        var cursor = max(0, offset)
        while cursor < string.length {
            if string.character(at: cursor) == 0x0A {
                starts.append(cursor + 1)
            }
            cursor += 1
        }
    }
}
