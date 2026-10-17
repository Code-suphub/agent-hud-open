import Foundation

/// One block as the hover panel draws it under a layout.
public struct PanelBlockPlan: Hashable, Sendable {
    public let key: String
    public let kind: PanelBlockKind
    /// The widget that draws the block: the one the layout asks for where the block's kind accepts it, else the kind's
    /// default.
    public let widget: PanelWidget
    /// The measures the block's picker offers, in picker order: those the layout lists that `widget` offers, else every
    /// one it offers. A block with one measure has no picker.
    public let measures: [PanelMeasure]
    /// The rows of the block that are left out, by row key. Never all of them: such a block is left out whole.
    public let hiddenRows: Set<String>
    /// The keys of the block's rows the layout puts first, in that order; the others keep their order after them
    /// (`ordered(_:key:)`). Empty for the rows' own order.
    public let rowOrder: [String]
    /// The accounts the block shows, by id (`PanelBlockInfo.Account.id`); empty for every account (`shows(account:)`).
    public let accounts: Set<String>
    /// Whether the block shows its reset times: a quota block's own countdown, else the layout's. True for a block
    /// without one.
    public let countdown: Bool
    /// How many cells stand on a line where the block is drawn in cells: the layout's columns, else four, and in half a
    /// line the layout's, else two, never more than fit there (`PanelLines`). Four for a block without cells.
    public let columns: Int
    /// The size of the block's rings where it is drawn with rings: the layout's, else medium. Medium for a block without
    /// rings.
    public let ringSize: PanelRingSize
    /// How much of its line the block takes: half only beside another half block, where the panel has room for two;
    /// else the whole line. A block the panel leaves out is told the span the layout asks for, where it can take it.
    public let span: PanelSpan
    /// The period the block covers where it covers one (`PanelBlockKind.takesPeriod(under:)`): the layout's, else the
    /// latest 24 hours on a chart and the period the token chart starts from on a balance. A day for a block that covers
    /// none.
    public let period: PanelTokenPeriod

    /// The measure shown first when the panel opens: the first one offered.
    public var measure: PanelMeasure { measures.first ?? .quota }

    public init(key: String, kind: PanelBlockKind, widget: PanelWidget, measures: [PanelMeasure], hiddenRows: Set<String> = [],
                rowOrder: [String] = [], accounts: Set<String> = [], countdown: Bool = true, columns: Int = 4,
                ringSize: PanelRingSize = .medium, span: PanelSpan = .full, period: PanelTokenPeriod = .day) {
        self.key = key
        self.kind = kind
        self.widget = widget
        self.measures = measures
        self.hiddenRows = hiddenRows
        self.rowOrder = rowOrder
        self.accounts = accounts
        self.countdown = countdown
        self.columns = columns
        self.ringSize = ringSize
        self.span = span
        self.period = period
    }

    /// Whether the block shows the rows or the balance of the account with this id: every account where the layout
    /// names none, else those it names. Rows of no account, under the empty id, only where it names none.
    public func shows(account id: String) -> Bool { accounts.isEmpty || accounts.contains(id) }

    /// Rows in the block's order: those `rowOrder` names first, in its order, then the others in the order given.
    /// - key: a row's key (`AgentDescriptor.windowKey`).
    public func ordered<Row>(_ rows: [Row], key: (Row) -> String) -> [Row] {
        guard !rowOrder.isEmpty else { return rows }
        let named = rowOrder.flatMap { name in rows.filter { key($0) == name } }
        return named + rows.filter { !rowOrder.contains(key($0)) }
    }
}

/// A layout resolved against the blocks the hover panel has now: what the panel shows, in order, and how it is set. A
/// layout can only hide, choose among and reorder what exists and choose how it is drawn; what it names that does not
/// exist is passed over here and stays in the document.
///
/// With the default layout the plan is the default view: every block in the order given, across the whole line, each
/// with its kind's default widget and every measure that widget offers, the three sections in their default order, the
/// default style, five session rows of every session of the last day, and the token chart of every model over the latest
/// 24 hours.
public struct PanelLayoutPlan: Hashable, Sendable {
    /// The blocks shown, in order: those `PanelLayout.order` names first, in that order, then the others in default
    /// order, each with the span it takes (`lines`). A block is left out when the layout hides it, keeps none of its
    /// accounts, or hides every row of those it keeps.
    public let blocks: [PanelBlockPlan]
    /// Whether two half blocks can share a line: the panel lays its blocks out wide enough for two halves of at least
    /// `PanelLines.narrowestHalf`, and is not one agent's own panel.
    public let halvesFit: Bool
    /// The sections shown, in order: those `PanelLayout.sections` names first, in that order, then the others in default
    /// order, without the hidden ones.
    public let sections: [PanelSection]
    /// How the whole panel is set: the layout's style.
    public let style: PanelStyle
    /// Which sessions the session rows list, and how many: the layout's, which the panel's own agent narrows further on
    /// a dock that separates its agents.
    public let sessions: PanelSessionFilter
    /// The period the token chart starts from and whose tokens it draws: the layout's, joined with the panel's own agent
    /// on a dock that separates its agents.
    public let tokens: PanelTokenFilter

    /// - blocks: the blocks the panel has, in default order (`ReportView.panelBlocks`).
    /// - contentWidth: the width the panel lays its blocks out in, inside its insets; nil for beside the notch at the
    ///   layout's width.
    /// - pairs: false for one agent's own panel on a dock that separates its agents, which shows one block and sets
    ///   every block across the whole line.
    public init(layout: PanelLayout, blocks: [PanelBlockInfo], contentWidth: Double? = nil, pairs: Bool = true) {
        var existing: [String: PanelBlockInfo] = [:]
        for block in blocks where existing[block.key] == nil { existing[block.key] = block }
        let named = layout.order.filter { existing[$0] != nil }
        let keys = (named + blocks.map(\.key)).withoutRepeats
        let planned = keys.compactMap { key in existing[key].flatMap { Self.plan(of: $0, in: layout) } }
        let width = contentWidth ?? Double(layout.style.panelWidth) - PanelLines.sideInsets
        let half = PanelLines.halfWidth(in: width, spacing: layout.style.spacing)
        halvesFit = pairs && half >= PanelLines.narrowestHalf
        self.blocks = Self.paired(planned, changes: layout.blocks, halfWidth: halvesFit ? half : nil)
        let hidden = Set(layout.hiddenSections)
        sections = (layout.sections + PanelSection.allCases).withoutRepeats.filter { !hidden.contains($0) }
        style = layout.style
        sessions = PanelSessionFilter(layout.sessions)
        tokens = PanelTokenFilter(layout.tokens)
    }

    /// A block as a layout draws it; nil when the layout leaves it out: where it hides the block, where its accounts
    /// keep none of the block's accounts, and where it hides every row those accounts have. A block without rows, such
    /// as a balance, is never left out for its hidden rows.
    private static func plan(of block: PanelBlockInfo, in layout: PanelLayout) -> PanelBlockPlan? {
        let drawn = PanelBlockPlan(block, in: layout)
        if layout.blocks[block.key]?.hidden == true { return nil }
        let kept = block.accounts.filter { drawn.shows(account: $0.id) }
        if !drawn.accounts.isEmpty && kept.isEmpty { return nil }
        let rows = drawn.accounts.isEmpty ? Set(block.rowKeys) : Set(kept.flatMap(\.rowKeys))
        if !block.rowKeys.isEmpty && rows.subtracting(drawn.hiddenRows).isEmpty { return nil }
        return drawn
    }
}

extension PanelBlockPlan {
    /// How a layout draws a block, whether or not it also leaves the block out of the panel: what an agent is told of a
    /// block it has hidden. What the block has nothing to set for is its default, a countdown it does not set is the
    /// layout's, a balance covers the period the layout's token chart starts from where it gives none, and a span is the
    /// one asked for where the block can take it, before the panel sets its blocks in lines.
    init(_ block: PanelBlockInfo, in layout: PanelLayout) {
        let change = layout.blocks[block.key] ?? PanelLayout.Block(), tokenPeriod = layout.tokens.chartPeriod
        let kind = block.kind
        let widget = kind.widget(for: change.widget)
        var columns: Int = PanelLayout.Block.defaultColumns
        if kind.takesColumns(under: widget), let asked = change.columns, PanelLayout.Block.columnRange.contains(asked) {
            columns = asked
        }
        var ringSize: PanelRingSize = .medium
        if kind.takesRingSize(under: widget), let asked = change.ringSize { ringSize = asked }
        let span: PanelSpan = change.span == .half && kind.takesHalf(under: widget) ? .half : .full
        var period: PanelTokenPeriod = .day
        if kind.takesPeriod(under: widget) { period = change.period ?? kind.defaultPeriod(tokens: tokenPeriod) }
        self.init(key: block.key, kind: kind, widget: widget, measures: kind.measures(change.measures, under: widget),
                  hiddenRows: Set(block.rowKeys).intersection(change.hiddenRows),
                  rowOrder: change.rows.filter(block.rowKeys.contains).withoutRepeats,
                  accounts: Set(change.accounts.filter { !$0.isEmpty }),
                  countdown: !kind.takesCountdown || (change.countdown ?? layout.countdown), columns: columns,
                  ringSize: ringSize, span: span, period: period)
    }
}
