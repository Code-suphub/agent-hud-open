import Foundation

/// The archive an Electron app keeps its own files in (`app.asar`): a table of contents in JSON, then every file's
/// bytes back to back. Only the table is read up front; a file is read on its own, by its place in the archive.
///
/// The table sits in two Chromium pickles. The first holds one number, the size of the second; the second holds
/// the JSON as a length-prefixed string. File offsets count from the end of the second pickle.
struct AsarArchive {
    struct Entry: Equatable {
        /// Where the file starts, from the end of the table.
        let offset: UInt64
        let size: Int
        /// Files the app keeps beside the archive, in `app.asar.unpacked`, have no bytes in it.
        let unpacked: Bool
    }

    let url: URL
    /// Where the files' bytes start, from the start of the archive.
    private let base: UInt64
    private let length: UInt64
    private let root: [String: Any]

    /// A table bigger than this is not an app's table of contents.
    private static let largestTable = 64 << 20

    /// Reads the table of contents of the archive at `url`, or nil if it is not an archive this can read.
    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd(), (try? handle.seek(toOffset: 0)) != nil else { return nil }
        let head = [UInt8]((try? handle.read(upToCount: 16)) ?? Data())
        guard head.count == 16 else { return nil }
        func word(_ at: Int) -> Int { (0..<4).reduce(0) { $0 | Int(head[at + $1]) << (8 * $1) } }
        // The size pickle holds four bytes; the header pickle's own size, then its string's length, then the string.
        let tableSize = word(4), jsonLength = word(12)
        guard word(0) == 4, jsonLength > 0, jsonLength <= Self.largestTable, jsonLength + 8 <= tableSize,
              UInt64(8 + tableSize) <= length,
              let json = try? handle.read(upToCount: jsonLength), json.count == jsonLength,
              let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        else { return nil }
        self.url = url
        self.length = length
        base = UInt64(8 + tableSize)
        self.root = root
    }

    /// The file at `path`, written with slashes from the archive's root.
    func entry(at path: String) -> Entry? {
        guard let node = node(at: path), node["files"] == nil else { return nil }
        let unpacked = node["unpacked"] as? Bool ?? false
        guard let size = Self.number(node["size"]), size >= 0 else { return nil }
        if unpacked { return Entry(offset: 0, size: size, unpacked: true) }
        guard let offset = Self.number(node["offset"]), offset >= 0 else { return nil }
        return Entry(offset: UInt64(offset), size: size, unpacked: false)
    }

    /// The names of the files and folders directly in `directory`.
    func names(in directory: String) -> [String] {
        guard let files = node(at: directory)?["files"] as? [String: Any] else { return [] }
        return files.keys.sorted()
    }

    /// The bytes of a file kept in the archive, if they are all there.
    func contents(of entry: Entry) -> Data? {
        guard !entry.unpacked, base + entry.offset + UInt64(entry.size) <= length,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: base + entry.offset)) != nil else { return nil }
        let data = entry.size == 0 ? Data() : (try? handle.read(upToCount: entry.size)) ?? Data()
        return data.count == entry.size ? data : nil
    }

    private func node(at path: String) -> [String: Any]? {
        var node = root
        for part in path.split(separator: "/") where !part.isEmpty {
            guard let files = node["files"] as? [String: Any], let next = files[String(part)] as? [String: Any]
            else { return nil }
            node = next
        }
        return node
    }

    /// Sizes are numbers in the table; offsets are strings, so that one past 2^53 survives JavaScript.
    private static func number(_ value: Any?) -> Int? {
        switch value {
        case let text as String: Int(text)
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            Double(number.int64Value) == number.doubleValue ? Int(exactly: number.int64Value) : nil
        default: nil
        }
    }
}
