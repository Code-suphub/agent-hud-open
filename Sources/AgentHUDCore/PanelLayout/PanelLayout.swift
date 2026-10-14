import AgentHUDSupport
import Foundation

/// What draws a block of the hover panel: rows of bars, a ring, a number or a chart.
public enum PanelWidget: String, Codable, CaseIterable, Sendable { case bar, ring, number, chart }

/// What a block shows, the reading its picker flips in place: a quota window's share, or an API account's balance
/// (`quota`), how fast that goes (`burnRate`, written `burn`), tokens, or cost.
public enum PanelMeasure: String, Codable, CaseIterable, Sendable { case quota, burnRate = "burn", tokens, cost }

/// A part of the hover panel, in the panel's default order: the agents' blocks, the token chart, the sessions.
public enum PanelSection: String, Codable, CaseIterable, Sendable { case blocks, tokens, sessions }

/// How this Mac's hover panel differs from its default view. The default view is a built-in rule, so a layout records
/// only what was changed: `PanelLayout()` is the default view and its JSON is `{}`.
///
/// A block is one agent's quota windows or one API account's balance, under the key `PanelBlockInfo` gives it; a row of
/// a block is a quota window, under its `AgentDescriptor.windowKey`. A key that names nothing the panel has now stays
/// in the document and applies again when its block or row returns.
///
/// The JSON is also what an agent sends, so reading forgives field by field: a widget or measure name this build does
/// not know leaves that field unset, a section it does not know is left out, a block that is not an object is left
/// out, a value of the wrong type counts as not given, and keys it does not know are ignored. Only JSON that is not an
/// object fails. Writing leaves out what is unset or empty, so with sorted keys (`RecordCoding.encoder()`) equal
/// layouts are the same bytes.
public struct PanelLayout: Hashable, Codable, Sendable {
    /// What a layout changes about one block.
    public struct Block: Hashable, Codable, Sendable {
        /// The widget that draws the block; nil for its kind's default.
        public var widget: PanelWidget?
        /// The measure the block shows first; nil for its widget's default.
        public var measure: PanelMeasure?
        /// Whether the block is left out of the panel.
        public var hidden: Bool
        /// The rows left out of the block, by row key.
        public var hiddenRows: [String]

        public init(widget: PanelWidget? = nil, measure: PanelMeasure? = nil, hidden: Bool = false, hiddenRows: [String] = []) {
            self.widget = widget
            self.measure = measure
            self.hidden = hidden
            self.hiddenRows = hiddenRows
        }

        /// Whether the block changes nothing: no widget, no measure, not hidden, and no row hidden.
        public var isEmpty: Bool { widget == nil && measure == nil && !hidden && hiddenRows.isEmpty }

        /// The block with each hidden row named once, in key order, and no empty key among them: which rows are hidden
        /// matters, not the order they were named in.
        public func normalized() -> Block {
            Block(widget: widget, measure: measure, hidden: hidden,
                  hiddenRows: hiddenRows.filter { !$0.isEmpty }.withoutRepeats.sorted())
        }

        private enum CodingKeys: String, CodingKey { case widget, measure, hidden, hiddenRows }

        /// Nil when the value is not an object.
        init?(json: JSONValue) {
            guard let fields = json.objectValue else { return nil }
            self.init(widget: fields["widget"]?.stringValue.flatMap(PanelWidget.init(rawValue:)),
                      measure: fields["measure"]?.stringValue.flatMap(PanelMeasure.init(rawValue:)),
                      hidden: fields["hidden"]?.boolValue ?? false,
                      hiddenRows: PanelLayout.strings(fields["hiddenRows"]))
        }

        public init(from decoder: Decoder) throws {
            guard let block = Block(json: try decoder.singleValueContainer().decode(JSONValue.self)) else {
                throw DecodingError.typeMismatch(Block.self, DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "A block of a panel layout is a JSON object."))
            }
            self = block
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(widget, forKey: .widget)
            try c.encodeIfPresent(measure, forKey: .measure)
            if hidden { try c.encode(true, forKey: .hidden) }
            if !hiddenRows.isEmpty { try c.encode(hiddenRows, forKey: .hiddenRows) }
        }
    }

    /// What differs about each block, by block key.
    public var blocks: [String: Block]
    /// Block keys in the order their blocks come; blocks not named follow in default order.
    public var order: [String]
    /// Sections in the order they come; sections not named follow in default order.
    public var sections: [PanelSection]
    /// The sections left out of the panel.
    public var hiddenSections: [PanelSection]

    public init(blocks: [String: Block] = [:], order: [String] = [], sections: [PanelSection] = [],
                hiddenSections: [PanelSection] = []) {
        self.blocks = blocks
        self.order = order
        self.sections = sections
        self.hiddenSections = hiddenSections
    }

    // MARK: The same layout

    /// The layout written one way, so that two layouts are the same layout when their normalized values are equal: no
    /// block that changes nothing; each key in `order` once, the first time it is named, and none empty; each block's
    /// hidden rows once, in key order; `sections` as the whole order it gives, or empty when that is the default
    /// order; and `hiddenSections` once each, in default order. A hidden section keeps its place in `sections`, which
    /// it takes again when it is shown.
    public func normalized() -> PanelLayout {
        var kept: [String: Block] = [:]
        for (key, block) in blocks {
            let block = block.normalized()
            if !block.isEmpty { kept[key] = block }
        }
        let sectionOrder = (sections + PanelSection.allCases).withoutRepeats
        return PanelLayout(blocks: kept, order: order.filter { !$0.isEmpty }.withoutRepeats,
                           sections: sectionOrder == PanelSection.allCases ? [] : sectionOrder,
                           hiddenSections: PanelSection.allCases.filter(hiddenSections.contains))
    }

    /// Whether the layout is the default view: nothing is left of it once normalized.
    public var isDefault: Bool { normalized() == PanelLayout() }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey { case blocks, order, sections, hiddenSections }

    /// Nil when the value is not an object.
    init?(json: JSONValue) {
        guard let fields = json.objectValue else { return nil }
        var blocks: [String: Block] = [:]
        for (key, value) in fields["blocks"]?.objectValue ?? [:] {
            if let block = Block(json: value) { blocks[key] = block }
        }
        self.init(blocks: blocks, order: Self.strings(fields["order"]),
                  sections: Self.strings(fields["sections"]).compactMap(PanelSection.init(rawValue:)),
                  hiddenSections: Self.strings(fields["hiddenSections"]).compactMap(PanelSection.init(rawValue:)))
    }

    public init(from decoder: Decoder) throws {
        guard let layout = PanelLayout(json: try decoder.singleValueContainer().decode(JSONValue.self)) else {
            throw DecodingError.typeMismatch(PanelLayout.self, DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "A panel layout is a JSON object."))
        }
        self = layout
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !blocks.isEmpty { try c.encode(blocks, forKey: .blocks) }
        if !order.isEmpty { try c.encode(order, forKey: .order) }
        if !sections.isEmpty { try c.encode(sections, forKey: .sections) }
        if !hiddenSections.isEmpty { try c.encode(hiddenSections, forKey: .hiddenSections) }
    }

    /// The strings of a list, in its order; what is not a string is left out, and what is not a list gives none.
    private static func strings(_ value: JSONValue?) -> [String] {
        (value?.arrayValue ?? []).compactMap(\.stringValue)
    }
}

extension Array where Element: Hashable {
    /// The elements in order, each kept the first time it comes.
    var withoutRepeats: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
