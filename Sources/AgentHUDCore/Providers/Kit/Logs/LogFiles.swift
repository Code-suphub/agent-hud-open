import Foundation

/// The log files under a set of roots with their modification times and sizes. With a directory watch, a poll looks
/// only at the paths reported changed, and lists only the subtree of a reported directory; without one, or every five
/// minutes and whenever events were dropped, it lists every file again. A listing that stops at its limit keeps the
/// files it did not reach that are still there.
final class LogFiles {
    struct File: Equatable {
        let modified: Date
        let size: Int
    }

    /// What a listing could not cover, for a notice: entries it could not read, and whether it stopped at its limit.
    /// Until the next full listing, a poll reports the last one's gaps along with those of the subtrees it listed.
    struct Gaps {
        var unreadable = 0
        var truncated = false
    }

    static let fullScanInterval: TimeInterval = 300

    private let roots: [URL]
    /// Each root's path as a listing names the files under it, by `listedPath(_:)`.
    private var listedRoots: [String]
    private let limit: Int
    private let skips: (URL) -> Bool
    private let accepts: (URL) -> Bool
    private var monitor: FileChangeMonitor?
    private(set) var files: [String: File] = [:]
    private var scannedAt: Date?
    private var scanGaps = Gaps()
    /// The outer collector's event paths. Once it supplies them, it owns the watch for this listing; its paths must
    /// reach the index even when this listing's independent FSEvents stream has not delivered the same event yet.
    private var usesExternalChanges = false
    private var reportedPaths: Set<String>? = []

    /// - limit: entries a full listing visits before it stops.
    /// - skips: an entry the listing neither accepts nor descends into.
    init(roots: [URL], watchesChanges: Bool, limit: Int = .max, skips: @escaping (URL) -> Bool = { _ in false },
         accepts: @escaping (URL) -> Bool) {
        self.roots = roots
        listedRoots = roots.map(Self.listedPath)
        self.limit = limit
        self.skips = skips
        self.accepts = accepts
        monitor = watchesChanges ? FileChangeMonitor(directories: roots) : nil
    }

    /// Called before a collection read with paths from the collector's watch. Nil means events were dropped and a full
    /// listing is required. Repeated signals accumulate until the next read.
    func noteChanges(_ paths: Set<String>?) {
        usesExternalChanges = true
        monitor = nil
        if let paths, reportedPaths != nil { reportedPaths?.formUnion(paths.filter { canonical($0) != nil }) }
        else { reportedPaths = nil }
    }

    /// Brings `files` up to date.
    @discardableResult
    func refresh(now: Date) -> Gaps {
        let changed: Set<String>?
        if usesExternalChanges {
            changed = reportedPaths
            reportedPaths = []
        } else {
            monitor?.update()
            changed = monitor?.consumePaths()
        }
        guard let changed, let scannedAt, now.timeIntervalSince(scannedAt) < Self.fullScanInterval else { return scan(now: now) }
        // FSEvents can name a directory when it is created or removed, and its children cannot be inferred from that
        // one path. A path that is a directory, or is gone and was no known file, is listed as a subtree.
        var directories: Set<String> = [], paths: [String] = []
        for path in Set(changed.compactMap(canonical)) {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if exists ? isDirectory.boolValue : files[path] == nil { directories.insert(path) } else { paths.append(path) }
        }
        // A directory inside another reported one is covered by that one's listing, and so is a file.
        let outermost = directories.filter { !Self.ancestors($0).contains(where: directories.contains) }
        var gaps = scanGaps
        for directory in outermost.sorted() { relist(directory, gaps: &gaps) }
        for path in paths where !Self.ancestors(path).contains(where: outermost.contains) {
            let url = URL(fileURLWithPath: path)
            guard accepts(url) else { continue }
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true, let modified = values.contentModificationDate, let size = values.fileSize {
                files[path] = File(modified: modified, size: size)
            } else if !FileManager.default.fileExists(atPath: path) {
                files.removeValue(forKey: path)
            }
        }
        return gaps
    }

    private func scan(now: Date) -> Gaps {
        listedRoots = roots.map(Self.listedPath)
        var listing = Listing(limit: limit, skips: skips, accepts: accepts)
        for root in roots { guard listing.add(root) else { break } }
        // Files past the limit were not seen, which does not mean they are gone.
        if listing.gaps.truncated {
            for (path, file) in files where listing.files[path] == nil && FileManager.default.fileExists(atPath: path) { listing.files[path] = file }
        }
        files = listing.files
        scannedAt = now
        scanGaps = listing.gaps
        return listing.gaps
    }

    /// Lists one reported directory as a full listing would reach it, and drops the known files under it that the
    /// listing did not find. A directory that is gone, or that the full listing skips, adds nothing.
    private func relist(_ directory: String, gaps: inout Gaps) {
        var listing = Listing(limit: limit, skips: skips, accepts: accepts)
        if let url = reachable(directory) { listing.add(url) }
        let prefix = directory + "/"
        var gone: [String] = []
        for path in files.keys where path.hasPrefix(prefix) && listing.files[path] == nil {
            if listing.gaps.truncated && FileManager.default.fileExists(atPath: path) { continue }
            gone.append(path)
        }
        for path in gone { files.removeValue(forKey: path) }
        files.merge(listing.files) { $1 }
        gaps.unreadable += listing.gaps.unreadable
        gaps.truncated = gaps.truncated || listing.gaps.truncated
    }

    /// The directory's URL when the full listing would descend into it: under a root, with no hidden or skipped
    /// directory on the way, and still there. The URL is built from the root's, so listed files are keyed alike.
    private func reachable(_ path: String) -> URL? {
        guard let index = listedRoots.firstIndex(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return nil }
        var url = roots[index]
        for component in path.dropFirst(listedRoots[index].count).split(separator: "/") {
            guard !component.hasPrefix(".") else { return nil }
            url.appendPathComponent(String(component))
            guard !skips(url) else { return nil }
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : nil
    }

    /// The directories that contain a path, nearest first.
    private static func ancestors(_ path: String) -> UnfoldFirstSequence<String> {
        sequence(first: (path as NSString).deletingLastPathComponent) { parent in
            parent.count > 1 ? (parent as NSString).deletingLastPathComponent : nil
        }
    }

    /// Change events can name a root by its own path, its resolved path or its real one; files are keyed as the listing
    /// names them.
    private func canonical(_ path: String) -> String? {
        for (root, listed) in zip(roots, listedRoots) {
            for name in [listed, root.path, root.resolvingSymlinksInPath().path] where path == name || path.hasPrefix(name + "/") {
                return listed + path.dropFirst(name.count)
            }
        }
        return nil
    }

    /// The enumerator names a directory's files under its real path, `/private` included, which neither the root's own
    /// path nor `resolvingSymlinksInPath()` gives; a root that is one file is listed by its own path.
    private static func listedPath(_ root: URL) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let real = realpath(root.path, nil) else { return root.path }
        defer { free(real) }
        return String(cString: real)
    }
}

/// One listing of roots or reported directories: the accepted files it found and what it could not cover. Its entries
/// count against the limit together.
private struct Listing {
    private static let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]

    let limit: Int
    let skips: (URL) -> Bool
    let accepts: (URL) -> Bool
    var files: [String: LogFiles.File] = [:]
    var gaps = LogFiles.Gaps()
    private var visited = 0

    init(limit: Int, skips: @escaping (URL) -> Bool, accepts: @escaping (URL) -> Bool) {
        self.limit = limit
        self.skips = skips
        self.accepts = accepts
    }

    /// Adds the accepted files at or under `url`; false once the limit stopped the listing.
    @discardableResult
    mutating func add(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return true }
        guard isDirectory.boolValue else {
            // A root can name one file; a new URL does not answer from values cached by an earlier listing.
            let file = URL(fileURLWithPath: url.path)
            if accepts(file) { list(file) }
            return true
        }
        var unreadable = 0
        defer { gaps.unreadable += unreadable }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in
            unreadable += 1
            return true
        }) else {
            unreadable += 1
            return true
        }
        for case let url as URL in enumerator {
            visited += 1
            guard visited <= limit else { gaps.truncated = true; return false }
            if skips(url) { enumerator.skipDescendants(); continue }
            if accepts(url) { list(url) }
        }
        return true
    }

    private mutating func list(_ url: URL) {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)), let modified = values.contentModificationDate,
              let size = values.fileSize, values.isRegularFile != nil else { gaps.unreadable += 1; return }
        if values.isRegularFile == true { files[url.path] = LogFiles.File(modified: modified, size: size) }
    }
}
