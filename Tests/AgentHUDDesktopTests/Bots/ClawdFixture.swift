import Foundation
@testable import AgentHUDDesktop

/// A made-up sprite table in the game's own format, and a made-up Claude app around it. No art of the real game is
/// ever in the tests.
enum ClawdFixture {
    /// Three sprites, written the three ways the game writes them, among code that is not a sprite.
    ///
    /// - Walking, 4×3: deltas as an array of strings; its box stands it on its bottom row.
    /// - Thinking, 3×2: deltas as one string split by `(`.
    /// - Waving, 2×1: a quoted name, keys out of order, deltas split by `.`, and an empty box.
    static let script = """
    var a=1,b={w:3,h:"x"};function c(e){return e+1}const te={Walking:{cat:"Core",w:4,h:3,fps:12,\
    palette:["#d97757","#141413"],base:"0110100100..",deltas:["","0.,51","b0"],a0:[0,1,4,2],standMatch:1},\
    Thinking:{cat:"Reactive",w:3,h:2,fps:12,palette:["#d97757","#141413","#699acb"],base:"0122.1",\
    deltas:"(12,2.(".split("("),a0:[0,0,3,2],standMatch:!0},\
    "Waving":{h:1,w:2,base:"0.",palette:["#fff"],deltas:"10..00".split("."),cat:"Core",a0:[0,0,0,0],fps:6,extra:f(1,[2]),standMatch:!1},\
    Broken:{cat:"Core",w:2,h:1,fps:12,palette:["#000"],base:"05",deltas:[],a0:[0,0,2,1],standMatch:1}};\
    function ne(e){let t=te[e];if(!t)throw Error(`no sprite data for "${e}"`)}
    """

    /// Walking's four frames, row by row, `clear` where nothing is drawn: an empty delta repeats a frame.
    static let walking: [[UInt8]] = {
        let clear = ClawdSprite.clear
        let first: [UInt8] = [0, 1, 1, 0, 1, 0, 0, 1, 0, 0, clear, clear]
        var second = first
        second[0] = clear
        second[5] = 1
        var third = second
        third[11] = 0
        return [first, first, second, third]
    }()

    /// The sprites of `script`, decoded.
    static func sheet(version: String = "test") -> ClawdSheet {
        ClawdSheet(version: version, sprites: ClawdSpriteTable.sprites(in: Array(script.utf8)))
    }

    /// Every sprite of the game, as many frames long as the real ones, so the clips fit it, and every frame a picture of
    /// its own: one pixel, a row lower each frame, in a colour of the sprite's own. A frame in `sameAs` repeats another.
    static func everySprite(sameAs: [(ClawdFrame, ClawdFrame)] = []) -> ClawdSheet {
        var sprites: [String: ClawdSprite] = [:]
        for (name, count) in ClawdClipsTests.realFrameCounts {
            let color = ClawdSprite.Color(red: UInt8(ClawdSpriteName.allCases.firstIndex(of: name)!), green: 0, blue: 0, alpha: 255)
            var frames = (0..<count).map { index in (0..<count).map { $0 == index ? UInt8(0) : ClawdSprite.clear } }
            for (frame, original) in sameAs where frame.sprite == name { frames[frame.index] = frames[original.index] }
            sprites[name.rawValue] = ClawdSprite(name: name.rawValue, category: "", width: 1, height: count, fps: 12,
                                                 palette: [color], frames: frames, anchor: (0, count), standMatch: true)
        }
        return ClawdSheet(version: "", sprites: sprites)
    }

    /// An Electron archive holding `files`, by their paths from its root.
    static func archive(_ files: [String: Data], unpacked: Set<String> = []) -> Data {
        var tree: [String: Any] = [:], bytes = Data()
        for (path, data) in files.sorted(by: { $0.key < $1.key }) {
            var entry: [String: Any] = ["size": data.count]
            if unpacked.contains(path) {
                entry["unpacked"] = true
            } else {
                entry["offset"] = String(bytes.count)
                bytes += data
            }
            insert(entry, at: path.split(separator: "/").map(String.init), into: &tree)
        }
        let json = try! JSONSerialization.data(withJSONObject: ["files": tree], options: [.sortedKeys])
        let padded = (json.count + 3) / 4 * 4
        func word(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        // The size pickle, then the header pickle: its payload's size, the string's length, the string padded to four.
        var archive = word(4) + word(padded + 8) + word(padded + 4) + word(json.count) + json
        archive += Data(count: padded - json.count)
        return archive + bytes
    }

    private static func insert(_ entry: [String: Any], at path: [String], into tree: inout [String: Any]) {
        guard let name = path.first else { return }
        if path.count == 1 {
            tree[name] = entry
            return
        }
        var folder = tree[name] as? [String: Any] ?? ["files": [String: Any]()]
        var files = folder["files"] as? [String: Any] ?? [:]
        insert(entry, at: Array(path.dropFirst()), into: &files)
        folder["files"] = files
        tree[name] = folder
    }

    /// A Claude app in `folder` whose archive holds the game's script among other files.
    @discardableResult
    static func app(in folder: URL, version: String = "9.9.9", script: String = script) throws -> URL {
        let app = folder.appendingPathComponent("Claude.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleShortVersionString": version, "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let assets = ClawdSheetSource.scriptFolder
        try archive([
            "package.json": Data("{}".utf8),
            "\(assets)/clawdQuestEngine-C2Z1.css": Data(".a{}".utf8),
            "\(assets)/clawdQuestEngine-D01k.js": Data(script.utf8),
            "\(assets)/index-AAAA.js": Data("console.log(1)".utf8),
        ]).write(to: resources.appendingPathComponent("app.asar"))
        return app
    }

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClawdFixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
