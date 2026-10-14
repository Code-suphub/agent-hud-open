import Foundation

/// One block as the hover panel draws it under a layout.
public struct PanelBlockPlan: Hashable, Sendable, Identifiable {
    public let key: String
    public let kind: PanelBlockKind
    /// The widget that draws the block: the one the layout asks for where the block's kind accepts it, else the kind's
    /// default.
    public let widget: PanelWidget
    /// The measure the block shows first: the one the layout asks for where `widget` offers it, else the widget's
    /// default.
    public let measure: PanelMeasure
    /// The measures the block's picker offers under `widget`, in picker order.
    public let measures: [PanelMeasure]
    /// The rows of the block that are left out, by row key. Never all of them: such a block is left out whole.
    public let hiddenRows: Set<String>

    public var id: String { key }

    public init(key: String, kind: PanelBlockKind, widget: PanelWidget, measure: PanelMeasure, measures: [PanelMeasure],
                hiddenRows: Set<String> = []) {
        self.key = key
        self.kind = kind
        self.widget = widget
        self.measure = measure
        self.measures = measures
        self.hiddenRows = hiddenRows
    }
}

/// A layout resolved against the blocks the hover panel has now: what the panel shows, in order. A layout can only
/// hide and reorder what exists and choose how it is drawn; what it names that does not exist is passed over here and
/// stays in the document.
///
/// With the default layout the plan is the default view: every block in the order given, each with its kind's default
/// widget and measure, and the three sections in their default order.
public struct PanelLayoutPlan: Hashable, Sendable {
    /// The blocks shown, in order: those `PanelLayout.order` names first, in that order, then the others in default
    /// order. A block is left out when the layout hides it, or hides every row it has.
    public let blocks: [PanelBlockPlan]
    /// The sections shown, in order: those `PanelLayout.sections` names first, in that order, then the others in default
    /// order, without the hidden ones.
    public let sections: [PanelSection]

    /// - blocks: the blocks the panel has, in default order (`ReportView.panelBlocks`).
    public init(layout: PanelLayout, blocks: [PanelBlockInfo]) {
        var existing: [String: PanelBlockInfo] = [:]
        for block in blocks where existing[block.key] == nil { existing[block.key] = block }
        let named = layout.order.filter { existing[$0] != nil }
        let keys = (named + blocks.map(\.key)).withoutRepeats
        self.blocks = keys.compactMap { key in
            existing[key].flatMap { Self.plan(of: $0, changed: layout.blocks[key] ?? PanelLayout.Block()) }
        }
        let hidden = Set(layout.hiddenSections)
        sections = (layout.sections + PanelSection.allCases).withoutRepeats.filter { !hidden.contains($0) }
    }

    /// A block as a layout's change draws it; nil when the change leaves it out. A block without rows, such as a
    /// balance, is never left out for its hidden rows.
    private static func plan(of block: PanelBlockInfo, changed change: PanelLayout.Block) -> PanelBlockPlan? {
        let drawn = PanelBlockPlan(block, changed: change)
        if change.hidden { return nil }
        if !block.rowKeys.isEmpty && drawn.hiddenRows.count == Set(block.rowKeys).count { return nil }
        return drawn
    }
}

extension PanelBlockPlan {
    /// How a layout's change draws a block, whether or not the change also leaves it out of the panel: what an agent
    /// is told of a block it has hidden.
    init(_ block: PanelBlockInfo, changed change: PanelLayout.Block) {
        let widget = block.kind.widget(for: change.widget)
        self.init(key: block.key, kind: block.kind, widget: widget,
                  measure: block.kind.measure(for: change.measure, under: widget),
                  measures: block.kind.measures(under: widget), hiddenRows: Set(block.rowKeys).intersection(change.hiddenRows))
    }
}
