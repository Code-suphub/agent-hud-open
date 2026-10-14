import Foundation

/// What a block of the hover panel holds: one agent's quota windows, readings with a ceiling, or one API account's
/// balance, money without one.
public enum PanelBlockKind: String, Sendable { case quota, billing }

public extension PanelBlockKind {
    /// The widgets the kind accepts, its default first. A bar and a ring draw a share of a ceiling, and a balance has
    /// none, so a balance is a number; a chart of money is not drawn yet.
    var widgets: [PanelWidget] {
        switch self {
        case .quota: [.bar, .ring, .number, .chart]
        case .billing: [.number]
        }
    }

    /// The widget of the default view: bars for quota windows, a number for a balance.
    var defaultWidget: PanelWidget {
        switch self {
        case .quota: .bar
        case .billing: .number
        }
    }

    /// The measures the kind offers under a widget, in picker order; none under a widget it does not accept. A chart of
    /// quota windows draws what has a history here, tokens and cost. A balance's number offers `quota` alone: its card
    /// shows the balance and the estimated cost together.
    func measures(under widget: PanelWidget) -> [PanelMeasure] {
        switch (self, widget) {
        case (.quota, .bar), (.quota, .ring), (.quota, .number): [.quota, .burnRate, .tokens, .cost]
        case (.quota, .chart): [.tokens, .cost]
        case (.billing, .number): [.quota]
        case (.billing, _): []
        }
    }

    /// The measure shown first under a widget: the first one offered.
    func defaultMeasure(under widget: PanelWidget) -> PanelMeasure { measures(under: widget).first ?? .quota }

    /// The widget that draws a block a layout asks to draw with `asked`: that one where the kind accepts it, else the
    /// kind's default.
    func widget(for asked: PanelWidget?) -> PanelWidget {
        guard let asked, widgets.contains(asked) else { return defaultWidget }
        return asked
    }

    /// The measure a block shows first under `widget` when a layout asks for `asked`: that one where it is offered, else
    /// the widget's default.
    func measure(for asked: PanelMeasure?, under widget: PanelWidget) -> PanelMeasure {
        guard let asked, measures(under: widget).contains(asked) else { return defaultMeasure(under: widget) }
        return asked
    }
}

/// One block the hover panel has now. A list of them is in the panel's default order.
public struct PanelBlockInfo: Hashable, Sendable {
    /// A quota block's vendor id (`AgentDescriptor.displayVendor`), an API account's `APIBilling.panelBlockKey`.
    public let key: String
    public let kind: PanelBlockKind
    /// The block's rows in default order: each quota window's `AgentDescriptor.windowKey`, once however many accounts
    /// have that window. A balance has no rows.
    public let rowKeys: [String]

    public init(key: String, kind: PanelBlockKind, rowKeys: [String] = []) {
        self.key = key
        self.kind = kind
        self.rowKeys = rowKeys
    }
}

public extension APIBilling {
    /// The key of the block that shows this account's balance: `api:` and the provider that bills it, which no vendor
    /// id is. Accounts of one provider share a block.
    var panelBlockKey: String { "api:" + (billingPool?.provider ?? vendor) }
}

public extension ReportView {
    /// The blocks the panel has, in default order: a quota block for each vendor's rows in row order, then a billing
    /// block for each API provider whose balance is shown, in the order of the balances.
    var panelBlocks: [PanelBlockInfo] {
        var blocks = rowGroups.map { group in
            PanelBlockInfo(key: group.vendor, kind: .quota, rowKeys: group.rows.map(\.agent.windowKey).withoutRepeats)
        }
        var keys = Set(blocks.map(\.key))
        for account in billing where keys.insert(account.panelBlockKey).inserted {
            blocks.append(PanelBlockInfo(key: account.panelBlockKey, kind: .billing))
        }
        return blocks
    }
}

/// One thing a proposed layout asks for that the panel cannot do as asked, worded for the agent that proposed it.
public struct PanelLayoutIssue: Hashable, Sendable {
    /// Where in the layout's JSON: its keys from the root joined by dots, a list's element by its index in brackets,
    /// such as `blocks.Claude.widget` or `order[2]`.
    public let path: String
    /// An English sentence an agent can relay: what is wrong, and what the panel has or accepts instead.
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public extension PanelLayout {
    /// Every issue of the layout against the blocks the panel has now, blocks by key and then `order` by position: a
    /// block key or an order entry that names no block, a widget its block's kind does not accept, a measure that is
    /// not offered under the widget the block is drawn with, and a hidden row its block does not have. A layout with
    /// issues still resolves (`PanelLayoutPlan`): what cannot be done as asked falls back or waits.
    func issues(against existing: [PanelBlockInfo]) -> [PanelLayoutIssue] {
        var known: [String: PanelBlockInfo] = [:]
        for block in existing where known[block.key] == nil { known[block.key] = block }
        let unknownKey = existing.isEmpty ? "The panel has no blocks now."
            : "The panel's blocks now: \(Self.quoted(existing.map(\.key).withoutRepeats))."
        var issues: [PanelLayoutIssue] = []
        for key in blocks.keys.sorted() {
            guard let block = known[key] else {
                issues.append(PanelLayoutIssue(path: "blocks.\(key)", message: "No block has the key \"\(key)\". \(unknownKey)"))
                continue
            }
            issues += Self.issues(of: blocks[key] ?? Block(), in: block)
        }
        for (index, key) in order.enumerated() where known[key] == nil {
            issues.append(PanelLayoutIssue(path: "order[\(index)]", message: "No block has the key \"\(key)\". \(unknownKey)"))
        }
        return issues
    }

    private static func issues(of change: Block, in block: PanelBlockInfo) -> [PanelLayoutIssue] {
        let kind = block.kind, path = "blocks.\(block.key)"
        var issues: [PanelLayoutIssue] = []
        if let widget = change.widget, !kind.widgets.contains(widget) {
            let accepted = "It accepts: \(quoted(kind.widgets.map(\.rawValue)))."
            issues.append(PanelLayoutIssue(path: path + ".widget", message: "\(refusal(of: widget, by: block)) \(accepted)"))
        }
        let widget = kind.widget(for: change.widget)
        let offered = kind.measures(under: widget)
        if let measure = change.measure, !offered.contains(measure) {
            let reason = kind == .billing ? " An API balance shows its balance and its estimated cost together, as \"quota\"." : ""
            let message = "The \"\(widget.rawValue)\" widget of \"\(block.key)\" does not offer the measure \"\(measure.rawValue)\".\(reason)"
            issues.append(PanelLayoutIssue(path: path + ".measure", message: "\(message) It offers: \(quoted(offered.map(\.rawValue)))."))
        }
        let rows = block.rowKeys.isEmpty ? "It has no rows to hide." : "Its rows: \(quoted(block.rowKeys))."
        for (index, row) in change.hiddenRows.enumerated() where !block.rowKeys.contains(row) {
            issues.append(PanelLayoutIssue(path: path + ".hiddenRows[\(index)]",
                                           message: "\"\(block.key)\" has no row \"\(row)\". \(rows)"))
        }
        return issues
    }

    /// Why a block's kind does not accept a widget, in plain words.
    private static func refusal(of widget: PanelWidget, by block: PanelBlockInfo) -> String {
        switch (block.kind, widget) {
        case (.billing, .bar), (.billing, .ring):
            "\"\(block.key)\" is an API balance, which has no ceiling, so the \"\(widget.rawValue)\" widget has nothing to measure it against."
        case (.billing, .chart):
            "\"\(block.key)\" is an API balance, and a chart of money is not drawn yet."
        default:
            "\"\(block.key)\" does not accept the \"\(widget.rawValue)\" widget."
        }
    }

    /// Names in quotes, separated by commas.
    private static func quoted(_ names: [String]) -> String {
        names.map { "\"\($0)\"" }.joined(separator: ", ")
    }
}
