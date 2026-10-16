import Foundation

/// Where Clawd's sprites come from: the Claude app installed on this Mac. Its archive holds the game's script, and the
/// script holds the sprite table; only that one file is read out of the archive, and nothing of it is written anywhere.
///
/// The table is decoded once a launch, away from the main thread, for each version of the app. Anything that does
/// not read the way it should gives no sheet at all, and Clawd is drawn the way Agent HUD draws it.
final class ClawdSheetSource: Sendable {
    static let shared = ClawdSheetSource()

    /// The places the Claude app is installed in, in the order they are looked at.
    static let installed = [URL(fileURLWithPath: "/Applications/Claude.app"),
                            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Claude.app")]
    /// The folder of the app's archive the game's script is in, and how its hashed name starts and ends.
    static let scriptFolder = ".vite/renderer/main_window/assets"
    static let scriptPrefix = "clawdQuestEngine-", scriptSuffix = ".js"
    /// A script bigger than this is not the game.
    private static let largestScript = 32 << 20

    private let apps: [URL]
    private let store = Store()

    init(apps: [URL] = ClawdSheetSource.installed) {
        self.apps = apps
    }

    /// The sprites of the first Claude app installed, decoded once for each version of it; nil when there is no
    /// app, or its sprites do not read or do not fit `clips`.
    func sheet(fitting clips: ClawdClips = .standard) async -> ClawdSheet? {
        guard let app = apps.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let version = Self.version(of: app)
        else { return nil }
        let sheet = await store.sheet(for: "\(app.path)#\(version)") { Self.sheet(app: app, version: version) }
        return sheet.flatMap { clips.fit($0) ? $0 : nil }
    }

    /// The decoded sprites of the app at `app`, read here and now.
    static func sheet(app: URL, version: String? = nil) -> ClawdSheet? {
        guard let version = version ?? Self.version(of: app),
              let archive = AsarArchive(url: app.appendingPathComponent("Contents/Resources/app.asar"))
        else { return nil }
        let names = archive.names(in: scriptFolder).filter { $0.hasPrefix(scriptPrefix) && $0.hasSuffix(scriptSuffix) }
        for name in names {
            guard let entry = archive.entry(at: "\(scriptFolder)/\(name)"), entry.size <= largestScript,
                  let script = archive.contents(of: entry)
            else { continue }
            let sprites = ClawdSpriteTable.sprites(in: [UInt8](script))
            if !sprites.isEmpty { return ClawdSheet(version: version, sprites: sprites) }
        }
        return nil
    }

    /// The app's version and build, which change whenever its archive does.
    static func version(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let short = info["CFBundleShortVersionString"] as? String, build = info["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return short == build ? short : "\(short) (\(build))"
        case let (version?, nil), let (nil, version?): return version
        case (nil, nil): return nil
        }
    }

    /// One decoding per version, shared by everyone who asks while it runs.
    private actor Store {
        private var decoded: [String: Task<ClawdSheet?, Never>] = [:]

        func sheet(for key: String, decode: @escaping @Sendable () -> ClawdSheet?) async -> ClawdSheet? {
            if let task = decoded[key] { return await task.value }
            let task = Task.detached(priority: .utility) { decode() }
            // Only the version that is installed now is worth keeping.
            decoded = [key: task]
            return await task.value
        }
    }
}
