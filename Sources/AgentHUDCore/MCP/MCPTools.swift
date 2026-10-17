import AgentHUDSupport

/// The tools Agent HUD's MCP server offers: a fixed list, the same for every client and in the same order, so a
/// client may cache it. Four act on the hover panel's layouts, the shared one or a screen's own, and on one screen's
/// resting HUD style, and the fifth says an edit is done, which lets go of the panel an edit held open; none of them
/// saves: saving is the user's click in the panel. What a tool does with its arguments is the running application's
/// business; only the names and the shapes are known here.
public enum MCPTools {
    /// The tools' names, as a client calls them and as the application is handed them.
    public static let getPanel = "get_panel"
    public static let getPanelImage = "get_panel_image"
    public static let setPanelLayout = "set_panel_layout"
    public static let discardPanelDraft = "discard_panel_draft"
    public static let finishPanelEdit = "finish_panel_edit"
    static let names = [getPanel, getPanelImage, setPanelLayout, discardPanelDraft, finishPanelEdit]

    /// What a client's model is told about the server before it has called anything.
    static let instructions = """
        Agent HUD shows AI coding agents' quota, usage and sessions at the Mac's notch. \
        These tools read what its hover panel shows and rearrange it, for every screen or for one, \
        and restyle one screen's resting HUD. A change is a draft until the user presses Save in the panel. \
        A layout edit holds the panel open for two minutes; call finish_panel_edit when you are done.
        """

    /// The app's own settings are told so that an agent can foresee what its draft does beyond the HUD, and are told
    /// read only, since no tool writes the settings.
    private static let getPanelDescription = """
        Read what the Agent HUD hover panel shows now: its blocks (one per agent or API provider), each block's \
        accounts, with the id a layout names one by, its email or name and its plan, and its rows in the order shown \
        with their latest readings, the layout in effect, whether reset countdowns show, the panel's width and height \
        and whether it scrolls, and the widgets and measures each block accepts; how many sessions it lists and over \
        what period, and its token chart's period, the agents and models it can draw and its total; the attached \
        screens, each with its resting HUD's style, the look it draws now, the agents it can show, agentPanelWidth, \
        the width of one agent's own panel on a dock that separates its agents, and whether an edit holds its panel \
        open; and app, the whole app's settings, read only and changed in Settings alone: appearance; matchScreen, \
        with which a screen's style draft also restyles the app's windows and the menu-bar menu on that screen; \
        botLogos, whether marks turn into bots on a Dynamic dock, a Simple panel and reminders; language, and \
        writtenIn, the language names are written in; and hover: pressOptionToOpen, openAtTopEdge, and delayMs and \
        collapseDelayMs in milliseconds. Call it before changing the layout; block, row, account and screen keys come \
        from here. Names are written as the panel shows them, in the application's language.
        """

    /// Pictures are drawn off screen, where no desktop shows through glass, so a glass HUD is drawn as a stand-in, the
    /// same for every glass style.
    private static let getPanelImageDescription = """
        Show a picture of the Agent HUD hover panel as the layout in effect draws it, a draft included, account names \
        masked, session titles left out, or with show 'hud' a screen's resting HUD as it looks now; every glass style \
        is one stand-in. Use it to check how a change looks; get_panel reads it as data.
        """

    private static let setPanelLayoutDescription = """
        Propose a layout for the Agent HUD hover panel: its blocks, their rows' order and the accounts each shows, its \
        sections and reset countdowns, which are also the switches of Settings' Expanded panel, its session rows, \
        token chart and style, its width included, and the screen's resting HUD: which agents it shows and, for one \
        screen, its mode, edge, sizes, appearance, material, glass style and glow. Send the whole layout you want; \
        anything left out uses the default, and a HUD style field left out stays as saved. A call with only hud style \
        fields leaves the layout as it is. What the layout from get_panel holds for a block, a row, an account or an \
        agent not listed now can be sent back as it is. It shows at once as an unsaved draft: the user keeps it with \
        Save in the panel, and it is dropped when Agent HUD restarts. Pass from 'default' to propose the built-in \
        layout instead, 'previous' for the last saved one, for a screen with the resting HUD style that went with it, \
        or 'shared' to have a screen use the shared layout again; hud.reset proposes a screen's default HUD style. A \
        layout edit holds the panel open on screen for two minutes from the call, and a call with only hud style \
        fields closes it so the HUD shows; call finish_panel_edit when you are done.
        """

    private static let discardPanelDraftDescription = "Drop the unsaved draft so the Agent HUD panel returns to the saved "
        + "layout and, for a screen, its resting HUD to its saved style. Like a layout edit it holds the panel open, "
        + "unless it drops a HUD style alone."

    private static let finishPanelEditDescription = "Say your edit of the Agent HUD panel is done, so the panel an edit "
        + "held open closes unless the user's pointer is on it. Drafts stay as they are, waiting for the user's Save."

    /// What the look's fields leave as it is: the row of a hardware notch, which the island is one with.
    private static let housingStaysBlack = "At a hardware notch a notch HUD stays dark in the notch's row, black or black "
        + "glass; the panel and the cards it opens into take the look."

    /// What every tool takes to name the layout it acts on.
    private static let screenDescription = "A screen key from get_panel for that screen's own layout; 'all', the default, "
        + "for the shared layout the other screens use."

    /// The definitions `tools/list` returns.
    static let definitions: [JSONValue] = [
        tool(getPanel, getPanelDescription, input: object(["screen": described("string", screenDescription)]), changes: false),
        tool(getPanelImage, getPanelImageDescription, input: object([
            "screen": described("string", screenDescription),
            "show": text("What to draw: the hover panel, the default, or the screen's resting HUD, which needs a screen key.",
                         oneOf: ["panel", "hud"]),
        ]), changes: false),
        tool(setPanelLayout, setPanelLayoutDescription, input: layout, changes: true),
        tool(discardPanelDraft, discardPanelDraftDescription, input: object(["screen": described("string", screenDescription)]),
             changes: true),
        tool(finishPanelEdit, finishPanelEditDescription, input: object([
            "screen": described("string", "A screen key from get_panel to let go of that screen's panel; 'all', the default, "
                                + "for every screen's."),
        ]), changes: true),
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
            "rows": list("Keys of the block's rows, from get_panel, in the order to show them; rows left out keep their "
                         + "order after them.", of: key),
            "accounts": list("Ids of the accounts to show, from the block's accounts in get_panel; none for every account.",
                             of: key),
            "countdown": described("boolean", "Whether this quota block shows its reset times, whatever the layout's "
                                   + "countdown says; the layout's if left out."),
            "columns": described("integer", "Cells on a line for the ring and number widgets, 2 to 6; 4 if left out."),
            "ringSize": text("Ring size for the ring widget; medium if left out.", oneOf: ["small", "medium", "large"]),
            "span": text("The whole line, the default, or half of it beside the next block if that is half too. Not for bar "
                         + "rows.", oneOf: PanelSpan.allCases.map(\.rawValue)),
            "period": text("For the chart widget, the last 24 hours, 7 days or 30 days its bars cover, day if left out; for an "
                           + "API balance, what its estimated cost covers, the token chart's period if left out. For no other "
                           + "block.", oneOf: PanelTokenPeriod.allCases.map(\.rawValue)),
        ])
        let blocks: [String: JSONValue] = [
            "type": .string("object"),
            "additionalProperties": block,
            "description": .string("What differs from the default for each block, by block key from get_panel."),
        ]
        let style = object([
            "spacing": text("Room between sections, blocks and rows; regular if left out.", oneOf: ["compact", "regular", "roomy"]),
            "separators": described("boolean", "False drops the lines between blocks and sections."),
            "width": described("integer", "The whole panel's width, \(PanelStyle.widthRange.lowerBound) to "
                               + "\(PanelStyle.widthRange.upperBound) points; \(PanelStyle.defaultWidth) if left out."),
        ], description: "How the whole panel is set.")
        let limits = PanelLayout.Sessions.limitRange
        let sessions = object([
            "limit": described("integer", "Rows at most, \(limits.lowerBound) to \(limits.upperBound); "
                               + "\(PanelLayout.Sessions.defaultLimit) if left out."),
            "period": text("How long after its last activity an ended session is still listed, 1 hour to 7 days; 24h if "
                           + "left out. Sessions at work are listed whatever the period.",
                           oneOf: PanelSessionPeriod.allCases.map(\.rawValue)),
            "agents": list("Only these agents' sessions, names from get_panel's sessions.offeredAgents; none for every "
                           + "agent.", of: key),
            "states": list("Only sessions in these states; none for all.",
                           of: text("A session's state.", oneOf: PanelSessionState.allCases.map(\.rawValue))),
        ], description: "Which sessions the session rows list.")
        let tokens = object([
            "period": text("What the token chart shows when the panel opens: the last 24 hours, 7 days or 30 days; day if "
                           + "left out.", oneOf: PanelTokenPeriod.allCases.map(\.rawValue)),
            "agents": list("Only these agents' tokens, names from get_panel's tokens.offeredAgents; none for every "
                           + "agent.", of: key),
            "models": list("Only these models' tokens, ids from get_panel's tokens.offeredModels, of the agents named if "
                           + "any are; none for every model.", of: key),
        ], description: "The token chart's period, agents and models.")
        let hud = object([
            "agents": list("Agents it shows, in order, by name from get_panel's screens; none shows every agent.", of: key),
            "mode": text("For one screen only, as is every field but agents. notch needs a screen with a notch.",
                         oneOf: HUDMode.allCases.map(\.agentName)),
            "edge": text("Dynamic or simple: the edge it is parked on.", oneOf: HUDEdge.allCases.map(\.rawValue)),
            "position": described("number", "Dynamic or simple: its centre along that edge, \(bounds(HUDStyle.Field.position.range)) "
                                  + "A notch HUD made a dock at the top centre starts at 0, clear of the notch."),
            "logoSize": number("Dynamic: logo size in points,", .logoSize),
            "logoGap": number("Dynamic: gap between logos, as a share of a logo,", .logoGap),
            "edgeDistance": number("Dynamic: logos' distance from the edge in points,", .edgeDistance),
            "showLogos": described("boolean", "Dynamic: false leaves the backdrop alone."),
            "simpleSize": number("Simple: ring diameter in points,", .simpleSize),
            "ringWidth": number("Simple: ring stroke in points,", .ringWidth),
            "showRings": described("boolean", "Simple: a ring round each mark."),
            "showNumbers": described("boolean", "Simple: the percentage beside each mark."),
            "separateAgents": described("boolean", "Dynamic or simple: hovering a mark opens that agent's own panel."),
            "appearance": text("Its colours, its panel's and its cards' too: dark, light, or system to follow macOS's light "
                               + "or dark setting. \(housingStaysBlack)", oneOf: HUDAppearance.allCases.map(\.rawValue)),
            "material": text("Solid, or the system's glass, which shows the desktop through it blurred, light or dark as "
                             + "the appearance and the desktop make it; solid while Reduce Transparency is on. "
                             + "\(housingStaysBlack)",
                             oneOf: HUDMaterial.allCases.map(\.rawValue)),
            "glassStyle": text("What glass is made of: clear or regular Liquid Glass, which the HUD draws alike, "
                               + "as clear, and a window that matches its screen as regular, or material, an even "
                               + "frosted blur; Clear and Regular are a frosted blur before macOS 26. Kept while the "
                               + "material is solid, as Settings keeps it.",
                               oneOf: HUDGlassStyle.allCases.map(\.rawValue)),
            "transparency": described("number", "How much of the desktop shows through, glass's or solid's as the "
                                      + "material is: glass lays less of the appearance's colour beneath it, solid "
                                      + "draws less of its fill, all of it at 0; Solid, Clear and Regular draw three "
                                      + "fifths of it, 0.6 at 1, and Material all of it; "
                                      + "\(bounds(HUDStyle.Field.transparency.range)) It sets the transparency of "
                                      + "the material the HUD would have; get_panel lists what each keeps as "
                                      + "solidTransparency and glassTransparency."),
            "solidTransparency": kept("solid's"),
            "glassTransparency": kept("glass's"),
            "glow": object([
                "style": text("Glow style.", oneOf: GlowStyle.allCases.map(\.rawValue)),
                "effect": text("What it plays.", oneOf: GlowEffect.allCases.map(\.rawValue)),
                "brightness": number("Its strength,", glow: .brightness),
                "range": number("Blur style: reach in points,", glow: .range),
                "blur": number("Blur style: feather in points,", glow: .blur),
                "speed": number("Seconds a cycle takes while an agent works,", glow: .speed),
                "idleSpeed": number("Seconds a cycle takes while every agent is idle,", glow: .idleSpeed),
                "amplitude": number("Breathe effect: how deep a breath dips,", glow: .amplitude),
                "outwardOnly": described("boolean", "Blur style: fade outward from the rim only."),
                "gridPitch": number("Grid styles, all but blur: spacing between cells in points,", glow: .gridPitch),
                "gridDensity": number("Grid styles: how much of its cell a mark fills, past 1 into its neighbours,",
                                      glow: .gridDensity),
                "gridCore": number("Grid styles: rows held at full strength,", glow: .gridCore),
                "gridFade": number("Grid styles: rows it fades over after them,", glow: .gridFade),
            ], description: "Notch or dynamic: the glow."),
            HUDStyle.resetName: described("boolean", "True proposes the screen's default style, the placement its "
                                          + "hardware is given, dark and solid, and the default glow, with no other style "
                                          + "field."),
        ], description: "The resting HUD: the marks of a Dynamic dock, the items of a Simple panel, the glow, its colours "
            + "and its material; a style field left out stays as saved.")
        return object([
            "screen": described("string", screenDescription),
            "blocks": .object(blocks),
            "order": list("Block keys from get_panel, in the order the panel shows them.", of: key),
            "sections": list("The panel's sections, in the order it shows them.", of: section),
            "hiddenSections": list("The panel's sections to hide; Settings' Session list, Quota details and Token usage "
                                   + "switch sessions, blocks and tokens.", of: section),
            "countdown": described("boolean", "Whether the quota blocks show their reset times where a block gives no "
                                   + "countdown of its own; Settings' Reset countdown. True if left out."),
            "style": style,
            "sessions": sessions,
            "tokens": tokens,
            "hud": hud,
            "from": text("Propose the built-in layout, the last saved one, or for a screen the shared layout, instead of "
                         + "the one described here. Only 'previous' brings a screen's HUD style with it.",
                         oneOf: ["default", "previous", "shared"]),
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

    /// A number field of a screen's placement, described with the range it keeps within.
    private static func number(_ description: String, _ field: HUDStyle.Field) -> JSONValue {
        described("number", description + " " + bounds(field.range))
    }

    /// A number field of a screen's glow, described with the range it keeps within and the step it keeps to.
    private static func number(_ description: String, glow field: HUDStyle.GlowField) -> JSONValue {
        described("number", description + " " + bounds(field.range, step: field.step))
    }

    /// A transparency a screen keeps for one material, which get_panel lists and no proposal sets
    /// (`HUDStyle.KeptTransparency`).
    private static func kept(_ material: String) -> JSONValue {
        described("number", "Read only: \(material) transparency as get_panel lists it, which can be sent back as "
                  + "listed; transparency sets the material's own.")
    }

    private static func bounds(_ range: ClosedRange<Double>?, step: Double? = nil) -> String {
        guard let range else { return "" }
        let steps = step.map { $0 == 1 ? " in whole steps" : " in steps of \(HUDStyle.written($0))" } ?? ""
        return "\(HUDStyle.written(range.lowerBound)) to \(HUDStyle.written(range.upperBound))\(steps)."
    }

    private static func text(_ description: String, oneOf values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": names(values), "description": .string(description)])
    }

    private static func names(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }

    private static func list(_ description: String, of items: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": items, "description": .string(description)])
    }
}
