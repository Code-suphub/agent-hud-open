import Foundation

/// Finds where turns start in an append-only log of newline-ended lines, reading back from a position: the start of
/// the newest turn, from which a log is first read, and the start of the page before a position, from which its history
/// is read a page at a time. A line is judged from its first bytes; the whole line is read only when those say it may
/// start a turn, so a line holding a screenshot costs one short read.
public struct LogPager {
    /// Whether a line starts a turn, by the client's own mark: given its first `prefixLength` bytes, and a way to read the
    /// whole line when they are not enough to tell.
    public typealias StartsTurn = @Sendable (_ prefix: Data, _ line: () throws -> Data) throws -> Bool

    public static let prefixLength = 2048

    private let handle: FileHandle
    private let startsTurn: StartsTurn
    private let chunkSize: Int

    public init(handle: FileHandle, chunkSize: Int = 1 << 20, startsTurn: @escaping StartsTurn) {
        self.handle = handle
        self.chunkSize = chunkSize
        self.startsTurn = startsTurn
    }

    /// The start of the newest line before `end` that starts a turn; 0 when none does.
    /// - end: just past a newline, as a read that stops at the last complete line leaves it.
    public func lastTurnStart(before end: Int) throws -> Int {
        var lines = LinesBack(handle: handle, end: end, chunkSize: chunkSize)
        while let line = try lines.next() {
            if try starts(line) { return line.lowerBound }
        }
        return 0
    }

    /// The start of the page that ends at `end`: at least `minimumLines` lines back from it, then on to the line that
    /// starts a turn, or to the log's start.
    public func pageStart(before end: Int, minimumLines: Int) throws -> Int {
        var lines = LinesBack(handle: handle, end: end, chunkSize: chunkSize), count = 0
        while let line = try lines.next() {
            count += 1
            if count >= minimumLines, try starts(line) { return line.lowerBound }
        }
        return 0
    }

    /// Just past the last newline among a log's first `size` bytes: where its complete lines end.
    public func completeEnd(of size: Int) throws -> Int {
        var start = size
        while start > 0 {
            let from = max(0, start - chunkSize), data = try read(from..<start)
            if let newline = data.lastIndex(of: 0x0A) { return from + (newline - data.startIndex) + 1 }
            start = from
        }
        return 0
    }

    private func starts(_ line: Range<Int>) throws -> Bool {
        let prefix = try read(line.lowerBound..<min(line.upperBound, line.lowerBound + Self.prefixLength))
        return try startsTurn(prefix) { try read(line) }
    }

    private func read(_ range: Range<Int>) throws -> Data {
        try handle.seek(toOffset: UInt64(range.lowerBound))
        return try handle.read(upToCount: range.count) ?? Data()
    }
}

/// The lines of a log, newest first, from a position just past a newline back to the log's start; each range leaves
/// its newline out, and empty lines are passed over. Only the newlines are looked for, a chunk at a time, so a long
/// line is never held.
struct LinesBack {
    private let handle: FileHandle
    private let chunkSize: Int
    private var chunk = Data()
    private var chunkStart: Int
    /// Where the line still to be returned ends: the position of its newline.
    private var lineEnd: Int

    init(handle: FileHandle, end: Int, chunkSize: Int) {
        self.handle = handle
        self.chunkSize = chunkSize
        lineEnd = end > 0 ? end - 1 : -1
        chunkStart = max(lineEnd, 0)
    }

    mutating func next() throws -> Range<Int>? {
        while lineEnd >= 0 {
            var searchEnd = lineEnd
            var newline: Int?
            while newline == nil {
                if searchEnd <= chunkStart {
                    guard chunkStart > 0 else { break }
                    let start = max(0, chunkStart - chunkSize)
                    try handle.seek(toOffset: UInt64(start))
                    chunk = try handle.read(upToCount: chunkStart - start) ?? Data()
                    chunkStart = start
                }
                let count = min(searchEnd - chunkStart, chunk.count), offset = chunkStart
                newline = chunk.withUnsafeBytes { bytes in
                    UnsafeRawBufferPointer(rebasing: bytes[0..<count]).lastIndex(of: 0x0A).map { offset + $0 }
                }
                if newline == nil { searchEnd = chunkStart }
            }
            let start = newline.map { $0 + 1 } ?? 0
            let line = start..<lineEnd
            lineEnd = newline ?? -1
            if !line.isEmpty { return line }
        }
        return nil
    }
}
