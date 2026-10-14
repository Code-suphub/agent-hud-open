import AgentHUDSupport

/// The tools Agent HUD's MCP server offers: a fixed list, the same for every client and in the same order, so a
/// client may cache it. All four act on the hover panel, and none of them saves a layout: saving is the user's click
/// in the panel. What a tool does with its arguments is the running application's business; only the names and the
/// shapes are known here.
public enum MCPTools {
    /// The tools' names, as a client calls them and as the application is handed them.
    public static let getPanel = "get_panel"
    public static let getPanelImage = "get_panel_image"
    public static let setPanelLayout = "set_panel_layout"
    public static let discardPanelDraft = "discard_panel_draft"
    static let names = [getPanel, getPanelImage, setPanelLayout, discardPanelDraft]

    /// What a client's model is told about the server before it has called anything.
    static let instructions = """
        Agent HUD shows AI coding agents' quota, usage and sessions at the Mac's notch. \
        These tools read what its hover panel shows and rearrange it. \
        A layout change is a draft until the user presses Save in the panel.
        """

    private static let getPanelDescription = """
        Read what the Agent HUD hover panel shows now: its blocks (one per agent or API account), each block's rows \
        with their latest readings, the layout in effect, the panel's height and whether it scrolls on the main \
        display, and the widgets and measures each block accepts. Call it before changing the layout; block and row \
        keys come from here. Names are written as the panel shows them, in the application's language.
        """

    private static let getPanelImageDescription = """
        Show a picture of the Agent HUD hover panel as the layout in effect draws it, an unsaved draft included, with \
        account names masked and session titles left out. Use it to check how a layout looks; get_panel reads the \
        same panel as data.
        """

    private static let setPanelLayoutDescription = """
        Propose a layout for the Agent HUD hover panel. Send the whole layout you want; anything left out uses the \
        default. What the layout from get_panel holds for a block or a row the panel does not list now can be sent \
        back as it is, and applies again when that returns. It shows in the panel at once as an unsaved draft: the \
        user keeps it with Save in the panel, and it is dropped when Agent HUD restarts. Pass from 'default' or \
        'previous' to propose the built-in layout or the last saved one instead.
        """

    private static let discardPanelDraftDescription = "Drop the unsaved draft so the Agent HUD panel returns to the saved layout."

    /// The definitions `tools/list` returns.
    static let definitions: [JSONValue] = [
        tool(getPanel, getPanelDescription, input: object([:]), changes: false),
        tool(getPanelImage, getPanelImageDescription, input: object([:]), changes: false),
        tool(setPanelLayout, setPanelLayoutDescription, input: layout, changes: true),
        tool(discardPanelDraft, discardPanelDraftDescription, input: object([:]), changes: true),
    ]

    /// What `set_panel_layout` takes: every property optional, and no others.
    private static var layout: JSONValue {
        let key: JSONValue = .object(["type": .string("string")])
        let section = text("One of the panel's sections.", oneOf: ["blocks", "tokens", "sessions"])
        let measure: JSONValue = .object(["type": .string("string"), "enum": names(PanelMeasure.allCases.map(\.rawValue))])
        let block = object([
            "widget": text("How the block is drawn: bar rows, a ring, a number or a chart.",
                           oneOf: ["bar", "ring", "number", "chart"]),
            "measures": list("What its picker offers, in order, the first shown first: quota (an API account's balance), burn, "
                             + "tokens, cost. One means no picker; none means all its widget offers.", of: measure),
            "hidden": described("boolean", "True hides the block."),
            "hiddenRows": list("Keys of the block's rows to hide, from get_panel.", of: key),
            "countdown": described("boolean", "False hides a quota block's reset times."),
            "columns": described("integer", "Cells on a line for the ring and number widgets, 2 to 6; 4 if left out."),
            "ringSize": text("Ring size for the ring widget; medium if left out.", oneOf: ["small", "medium", "large"]),
        ])
        let blocks: [String: JSONValue] = [
            "type": .string("object"),
            "additionalProperties": block,
            "description": .string("What differs from the default for each block, by block key from get_panel."),
        ]
        let style = object([
            "spacing": text("Room between sections, blocks and rows; regular if left out.", oneOf: ["compact", "regular", "roomy"]),
            "separators": described("boolean", "False drops the lines between blocks and sections."),
        ], description: "How the whole panel is set.")
        return object([
            "blocks": .object(blocks),
            "order": list("Block keys from get_panel, in the order the panel shows them.", of: key),
            "sections": list("The panel's sections, in the order it shows them.", of: section),
            "hiddenSections": list("The panel's sections to hide.", of: section),
            "style": style,
            "from": text("Propose the built-in layout or the last saved one instead of the one described here.",
                         oneOf: ["default", "previous"]),
            "revision": described("integer", "The revision get_panel returned; when given and no longer current the call is refused."),
        ])
    }

    /// A tool's definition. Every hint is spelled out because a client assumes the worst of one left out: a tool
    /// that changes nothing says so, and one that changes the draft says it destroys nothing, may be repeated, and
    /// reaches nothing beyond this Mac.
    private static func tool(_ name: String, _ description: String, input: JSONValue, changes: Bool) -> JSONValue {
        var hints: [String: JSONValue] = ["readOnlyHint": .bool(!changes), "openWorldHint": .bool(false)]
        if changes {
            hints["destructiveHint"] = .bool(false)
            hints["idempotentHint"] = .bool(true)
        }
        return .object(["name": .string(name), "description": .string(description), "inputSchema": input,
                        "annotations": .object(hints)])
    }

    /// The schema of an object that has `properties`, all optional, and no others.
    private static func object(_ properties: [String: JSONValue], description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("object"), "additionalProperties": .bool(false)]
        if !properties.isEmpty { schema["properties"] = .object(properties) }
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    private static func described(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    private static func text(_ description: String, oneOf values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": names(values), "description": .string(description)])
    }

    private static func names(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }

    private static func list(_ description: String, of items: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": items, "description": .string(description)])
    }
}
