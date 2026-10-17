import AgentHUDSupport
import Foundation

/// What `get_panel_image` tells an agent: a picture of a screen's hover panel, or of its resting HUD.
extension PanelTools {
    // MARK: The panel

    /// The picture with what it shows: which screen and layout and its revision, the panel's size in points, whether it
    /// scrolls on its display, and the pixels a point it is drawn at, with a note that says the same in words, and that
    /// glass is a stand-in where the panel is drawn in it.
    func image(_ scope: PanelLayoutScope, among attached: [PanelScreen]) -> MCPToolReply {
        guard let picture else {
            return .failure("This copy of Agent HUD cannot draw the panel, so there is no picture of it here. "
                            + "get_panel reads the same panel as data.")
        }
        guard let drawn = picture(scope) else {
            return .failure("The panel's picture could not be drawn. Try again, or read the panel with get_panel.")
        }
        let fit = drawn.fit
        var note: String
        var display = "The main display"
        switch scope {
        case .shared:
            note = "The hover panel as \(layout.hasDraft ? "the unsaved draft" : "the saved layout") draws it"
        case .screen(let key):
            note = "The hover panel on \(name(of: key, among: attached)) as \(drawing(key)) draws it"
            if attached.contains(where: { $0.key == key }) { display = "That display" }
        }
        note += barNote(scope.screenKey)
        note += ", \(Self.points(drawn.width)) by \(Self.points(fit.height)) points, with account names masked, session titles "
            + "left out and any reading's reason or client's notice drawn as grey bars."
        if fit.scrolls {
            note += " \(display) opens it at most \(Self.points(fit.maximumHeight)) points tall, so a person scrolls to see "
                + "the rest; the picture shows all of it."
        }
        if drawn.isScaledDown {
            note += " It is drawn at \(Self.hundredths(drawn.scale)) pixels a point instead of \(Self.points(PanelPicture.pointScale)) "
                + "to stay within \(PanelPicture.pixelLimit) pixels tall."
        }
        // The shared layout is drawn in the main display's look, the first attached.
        let looked = scope.screenKey.flatMap { key in attached.first { $0.key == key } } ?? attached.first
        if let looked, looked.drawsGlass(store.settings.effectivePlacement(on: looked.key, hasNotch: looked.hasNotch)) {
            note += " " + Self.glassStandIn
        }
        let result: [String: JSONValue] = [
            "screen": .string(Self.name(of: scope)), "revision": .integer(revision), "unsaved": .bool(unsaved(scope)),
            "width": .integer(Int64(drawn.width.rounded())), "height": .integer(Int64(fit.height.rounded())),
            "scrolls": .bool(fit.scrolls), "pixelsPerPoint": .number(Self.hundredths(drawn.scale)), "note": .string(note),
        ]
        return .result(result, images: [MCPImage(mimeType: "image/png", data: drawn.png)])
    }

    /// What the bar above the panel's footer says waits unsaved beside the layout, which counts in the height, as the note
    /// names it after the layout the panel draws: a screen's style, and the app's settings, which every panel's bar shows.
    /// Nothing where nothing but a layout waits, which the layout named says, or nothing waits.
    /// - key: the screen's; nil for the shared layout's panel.
    private func barNote(_ key: String?) -> String {
        let style = key.map(layout.hasStyleDraft) ?? false, app = layout.appDraft != nil
        let laid = key.map { layout.draftScope(on: $0) != nil } ?? layout.hasDraft
        switch (style, app) {
        case (false, false):
            return ""
        case (true, false):
            return laid ? ", with the bar above its footer for the unsaved layout and its resting HUD's unsaved style"
                : ", with the bar above its footer that says its resting HUD's style is unsaved"
        case (true, true):
            return laid ? ", with the bar above its footer for the unsaved layout, its resting HUD's unsaved style and "
                + "the app's unsaved settings"
                : ", with the bar above its footer that says its resting HUD's style and the app's settings are unsaved"
        case (false, true):
            return laid ? ", with the bar above its footer for the unsaved layout and the app's unsaved settings"
                : ", with the bar above its footer that says the app's settings are unsaved"
        }
    }

    /// Which layout a screen's panel draws, in words.
    private func drawing(_ key: String) -> String {
        switch layout.draft(of: key) {
        case .own?: return "its own unsaved draft"
        case .shared?: return "the shared layout, in an unsaved draft that has it use the shared layout"
        case nil: break
        }
        if layout.ownLayout(of: key) != nil { return "its own saved layout" }
        return layout.hasDraft ? "the shared layout's unsaved draft" : "the saved shared layout"
    }

    /// What a picture says of glass: it is drawn off screen, where no desktop is behind it to show through, so every
    /// glass style is drawn as the same stand-in, at the transparency the style draws, and a picture shows no
    /// difference between them but that.
    static let glassStandIn = "Its glass is drawn as a stand-in, the same for clear, regular and material glass but "
        + "for the transparency each draws: a picture is drawn off screen, with no desktop behind it to show through."

    // MARK: The resting HUD

    /// A picture of one attached screen's resting HUD as it looks now, its style draft included, drawn off screen without
    /// opening anything: which screen, its mode and edge, the appearance and material it is drawn in, whether a style
    /// draft waits, whether the glow is in the picture, its size in points and the pixels a point it is drawn at, with a
    /// note that says the same in words, and that glass is a stand-in.
    func hudImage(_ scope: PanelLayoutScope, among attached: [PanelScreen]) -> MCPToolReply {
        guard case .screen(let key) = scope else {
            return .failure("show \"hud\" draws one screen's resting HUD, so it needs that screen's key. "
                            + Self.attachedList(attached))
        }
        guard let screen = attached.first(where: { $0.key == key }) else {
            return .failure("\(name(of: key, among: attached, starting: true)) has no resting HUD to draw. "
                            + Self.attachedList(attached))
        }
        guard let hud else {
            return .failure("This copy of Agent HUD cannot draw a resting HUD, so there is no picture of it here. "
                            + "get_panel reads its style as data.")
        }
        guard let drawn = hud(key) else {
            return .failure("The resting HUD's picture could not be drawn. Try again, or read its style with get_panel.")
        }
        let placement = store.settings.effectivePlacement(on: key, hasNotch: screen.hasNotch)
        let draft = layout.hasStyleDraft(key)
        // At a hardware notch the island at rest is black whatever the look; the look shows on what it opens into.
        let atNotch = placement.mode == .notch && screen.hasNotch
        let lookAppearance: HUDAppearance = screen.drawsLight(placement) ? .light : .dark
        let lookMaterial: HUDMaterial = screen.drawsGlass(placement) ? .glass : .solid
        let appearance: HUDAppearance = atNotch ? .dark : lookAppearance
        let material: HUDMaterial = atNotch ? .solid : lookMaterial
        var note = "The resting HUD of \"\(screen.name)\" as it looks now, " + (draft ? "with its unsaved style draft" : "as saved")
        switch placement.mode {
        case .notch:
            note += screen.hasNotch ? ": the island at its notch" : ": the bar that stands in for a notch at its top centre"
        case .logos, .simple:
            note += ": a \"\(placement.mode.agentName)\" HUD on its \(placement.edge.rawValue) edge"
            if placement.edge != .top { note += ", drawn here along a top edge as Settings previews it" }
        }
        if atNotch {
            note += ", black at rest, as the notch is; a reminder's wings are dark and \(lookMaterial.rawValue), and the "
                + "panel and the cards it opens into \(lookAppearance.rawValue) and \(lookMaterial.rawValue)"
        } else {
            note += ", \(appearance.rawValue) and \(material.rawValue)"
        }
        note += ", on a dark backdrop, \(Self.points(drawn.width)) by \(Self.points(drawn.height)) points"
        if placement.mode == .simple {
            note += "; a simple HUD draws no glow."
        } else {
            note += drawn.drawsGlow ? ", with its glow." : ", without its glow, which only its window on the display draws."
        }
        if material == .glass { note += " " + Self.glassStandIn }
        note += " It shows marks and figures, and no account or session."
        let result: [String: JSONValue] = [
            "screen": .string(key), "show": .string("hud"), "revision": .integer(revision), "unsaved": .bool(draft),
            "mode": .string(placement.mode.agentName), "edge": .string(placement.mode.isDocked ? placement.edge.rawValue : "top"),
            "appearance": .string(appearance.rawValue), "material": .string(material.rawValue),
            "glow": .bool(drawn.drawsGlow), "width": .integer(Int64(drawn.width.rounded())),
            "height": .integer(Int64(drawn.height.rounded())), "pixelsPerPoint": .number(Self.hundredths(drawn.scale)),
            "note": .string(note),
        ]
        return .result(result, images: [MCPImage(mimeType: "image/png", data: drawn.png)])
    }
}
