import AgentHUDSupport
import Foundation

/// Which layout a screen draws: the shared one, or one of its own.
public enum PanelScreenLayout: Hashable, Sendable {
    case shared
    case own(PanelLayout)

    /// The screen's own layout; nil while it uses the shared one.
    public var layout: PanelLayout? {
        if case .own(let layout) = self { return layout }
        return nil
    }

    /// The choice with its layout normalized.
    func normalized() -> PanelScreenLayout {
        switch self {
        case .shared: .shared
        case .own(let layout): .own(layout.normalized())
        }
    }
}

/// One screen's own layout document: the saved choice, the one saved before it, and a choice an agent proposed that no
/// person has saved yet. A screen without a document uses the shared layout.
struct PanelScreenDocument: Equatable, Sendable {
    var current: PanelScreenLayout = .shared
    var previous: PanelScreenLayout?
    var draft: PanelScreenLayout?

    /// Whether the document says nothing a screen without one would not: the shared layout, nothing before it, no draft.
    var isEmpty: Bool { current == .shared && previous == nil && draft == nil }
    /// Whether the document has anything to keep across launches.
    var isSaved: Bool { current != .shared || previous != nil }
}

/// How the saved layouts are kept in the defaults: one value, `{"shared": {"current": …, "previous": …}, "screens":
/// {"<screen key>": {"current": …, "previous": …}}}`. Each side is a layout's JSON; a screen's side is that or the
/// string `"shared"`, and a screen's `current` left out is the shared layout. `previous` is left out while there is
/// none, the shared side while it is the default layout with no previous one, a screen while it uses the shared layout
/// with no previous choice, and `screens` while no screen has a layout of its own.
///
/// Reading forgives side by side: a side that cannot be read is the default (`current` of the shared layout), the
/// shared layout (`current` of a screen) or none (`previous`), and a screen that is not an object is left out, so what
/// cannot be read never loses the rest.
enum PanelLayoutStorage {
    struct Saved: Equatable {
        var current = PanelLayout()
        var previous: PanelLayout?
        var screens: [String: PanelScreenDocument] = [:]
    }

    static func read(_ data: Data?) -> Saved {
        let root = data.flatMap { try? JSONValue.parse($0) }?.objectValue ?? [:]
        let shared = root["shared"]?.objectValue ?? [:]
        var saved = Saved(current: shared["current"].flatMap { PanelLayout(json: $0) }?.normalized() ?? PanelLayout(),
                          previous: shared["previous"].flatMap { PanelLayout(json: $0) }?.normalized())
        for (key, value) in root["screens"]?.objectValue ?? [:] where !key.isEmpty {
            guard let sides = value.objectValue else { continue }
            let document = PanelScreenDocument(current: sides["current"].flatMap(choice) ?? .shared,
                                               previous: sides["previous"].flatMap(choice))
            if document.isSaved { saved.screens[key] = document }
        }
        return saved
    }

    /// The value written for the saved layouts, sorted by key; nil when there is nothing to keep.
    static func write(_ saved: Saved) -> Data? {
        var root: [String: JSONValue] = [:]
        if saved.previous != nil || !saved.current.isDefault {
            var shared: [String: JSONValue] = ["current": json(saved.current)]
            if let previous = saved.previous { shared["previous"] = json(previous) }
            root["shared"] = .object(shared)
        }
        var screens: [String: JSONValue] = [:]
        for (key, document) in saved.screens where document.isSaved {
            var sides: [String: JSONValue] = [:]
            if let own = document.current.layout { sides["current"] = json(own) }
            if let previous = document.previous { sides["previous"] = json(previous) }
            screens[key] = .object(sides)
        }
        if !screens.isEmpty { root["screens"] = .object(screens) }
        guard !root.isEmpty else { return nil }
        return try? RecordCoding.encoder().encode(JSONValue.object(root))
    }

    /// A screen's side: a layout's object, or "shared"; nil for anything else.
    private static func choice(_ value: JSONValue) -> PanelScreenLayout? {
        if value.stringValue == "shared" { return .shared }
        return PanelLayout(json: value).map { .own($0.normalized()) }
    }

    private static func json(_ choice: PanelScreenLayout) -> JSONValue {
        switch choice {
        case .shared: .string("shared")
        case .own(let layout): json(layout)
        }
    }

    private static func json(_ layout: PanelLayout) -> JSONValue {
        (try? JSONValue.from(layout)) ?? .object([:])
    }
}
