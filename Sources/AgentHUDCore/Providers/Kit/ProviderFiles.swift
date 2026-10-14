import Foundation

/// How providers read the files of a client: a JSON file whole, a JSON Lines file line by line, and the end of a log.
enum ProviderFiles {
    /// The largest JSON file read whole, and the longest line a JSON Lines file may hold.
    static let jsonLimit = 16 * 1024 * 1024
    /// The largest JSON Lines file read, and how long reading it may take.
    static let linesLimit = 256 * 1024 * 1024
    static let linesTime: TimeInterval = 3
    private static let chunk = 256 * 1024

    static func json(_ url: URL) throws -> ProviderJSON {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= jsonLimit else { throw ProviderFailure.limit }
        return try ProviderJSON.read(Data(contentsOf: url))
    }

    /// Decodes a JSON Lines file line by line, numbering lines from 1. Given `markers`, a line holding none of them is
    /// numbered but not decoded, so a reader passes them only when every line it uses holds one.
    static func lines(_ url: URL, markers: [Data] = [], consume: (ProviderJSON, Int) throws -> Void) throws {
        try lines(url, wanted: { line in markers.isEmpty || markers.contains { line.range(of: $0) != nil } }, consume: consume)
    }

    /// Decodes the lines `wanted` accepts, numbering every line from 1. A line longer than `jsonLimit` that is not wanted,
    /// such as a large tool result, is skipped; a wanted one, or a file over `linesLimit` or `linesTime`, throws.
    static func lines(_ url: URL, wanted: (Data) -> Bool, consume: (ProviderJSON, Int) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var carry = Data(), read = 0, ordinal = 0, skipping = false
        let deadline = Date().addingTimeInterval(linesTime)
        while let chunk = try handle.read(upToCount: chunk), !chunk.isEmpty {
            try Task.checkCancellation()
            read += chunk.count
            guard read <= linesLimit, Date() <= deadline else { throw ProviderFailure.limit }
            carry.append(chunk)
            // Lines are cut from a moving start, and what they took is dropped once per chunk.
            var start = carry.startIndex
            while let newline = carry[start...].firstIndex(of: 10) {
                let line = carry[start..<newline]
                ordinal += 1
                if !skipping, !line.isEmpty, wanted(line) { try consume(ProviderJSON.read(Data(line)), ordinal) }
                skipping = false
                start = newline + 1
            }
            carry.removeSubrange(carry.startIndex..<start)
            if carry.count > jsonLimit {
                guard !wanted(carry) else { throw ProviderFailure.limit }
                carry.removeAll(); skipping = true
            }
        }
        // Accept a complete last JSON value without a newline; retry a torn tail on the next changed-file scan.
        if !skipping, !carry.isEmpty, wanted(carry), let value = try? ProviderJSON.read(carry) { try consume(value, ordinal + 1) }
    }

    /// Decodes the lines holding `marker` from the end of a JSON Lines file back, newest first, until `consume` returns
    /// false. Only as much of the file is read as that takes: a reader after a recent line of a long log passes none of
    /// what came before it. A line longer than `jsonLimit`, and one that is no JSON such as a tail still being written,
    /// is passed over; reading back further than `linesLimit`, or for longer than `linesTime`, throws.
    static func linesFromEnd(_ url: URL, marker: Data, consume: (ProviderJSON) throws -> Bool) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let newline = Data([10])
        let deadline = Date().addingTimeInterval(linesTime)
        var position = try handle.seekToEnd(), read = 0
        // The end of a line whose start is still to be read, and whether that line already proved too long to keep.
        var head = Data(), skipping = false
        while position > 0 {
            try Task.checkCancellation()
            let count = min(UInt64(chunk), position)
            position -= count
            read += Int(count)
            guard read <= linesLimit, Date() <= deadline else { throw ProviderFailure.limit }
            try handle.seek(toOffset: position)
            guard let block = try handle.read(upToCount: Int(count)), block.count == Int(count) else {
                throw CocoaError(.fileReadUnknown)
            }
            var window: Data
            if skipping {
                // The line being passed over starts after the block's last newline; what is before it is kept.
                guard let cut = block.range(of: newline, options: .backwards) else { continue }
                window = Data(block[..<cut.lowerBound])
                skipping = false
            } else {
                window = block
                window.append(head)
            }
            // Whole lines start after the window's first newline; before it is the end of a line that starts earlier.
            guard let first = position > 0 ? window.range(of: newline)?.upperBound : window.startIndex else {
                skipping = window.count > jsonLimit
                head = skipping ? Data() : window
                continue
            }
            var end = window.endIndex
            while let hit = window.range(of: marker, options: .backwards, in: first..<end) {
                let start = window.range(of: newline, options: .backwards, in: first..<hit.lowerBound)?.upperBound ?? first
                let stop = window.range(of: newline, in: hit.upperBound..<end)?.lowerBound ?? end
                if stop - start <= jsonLimit, let value = try? ProviderJSON.read(Data(window[start..<stop])) {
                    guard try consume(value) else { return }
                }
                end = start
            }
            head = first > window.startIndex ? Data(window[..<(first - 1)]) : Data()
        }
    }

    /// The last `bytes` of the file open in `handle`, from the first line that starts inside them, since a read that
    /// starts inside a line cannot parse it; `handle` is left at the end of the file.
    static func tail(_ handle: FileHandle, bytes: UInt64) throws -> Data {
        let end = try handle.seekToEnd()
        let start = end > bytes ? end - bytes : 0
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()
        guard start > 0 else { return data }
        guard let newline = data.firstIndex(of: 10) else { return Data() }
        return Data(data[data.index(after: newline)...])
    }
}
