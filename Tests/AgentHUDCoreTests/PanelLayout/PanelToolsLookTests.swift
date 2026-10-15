import AgentHUDSupport
import Foundation
import XCTest
@testable import AgentHUDCore

/// A screen's look through the tools: its appearance and material are style fields like any other, a draft drawn over
/// the screen's settings that Save keeps, Discard drops, Revert to Previous undoes and the reset gives back as dark and
/// solid; a notch HUD at a notch takes neither; and what get_panel and the pictures say of the look drawn now.
final class PanelToolsLookTests: PanelToolsCase {
    /// How the Mac is set, which the host tells with each screen.
    private var systemIsLight = false
    private var reducesTransparency = false

    private var builtIn: PanelScreen {
        PanelScreen(key: "BUILT-IN-UUID", name: "Built-in display", mode: .notch, edge: .top, hasNotch: true,
                    agents: ["Claude", "Codex", "DeepSeek"],
                    otherModes: [.logos: ["Claude", "Codex", "Cursor"], .simple: ["Claude", "Codex", "Kimi"]],
                    systemIsLight: systemIsLight, reducesTransparency: reducesTransparency)
    }

    private var second: PanelScreen {
        PanelScreen(key: "SECOND-UUID", name: "Display 2", mode: .logos, edge: .right, hasNotch: false,
                    agents: ["Claude", "Codex", "Cursor"], systemIsLight: systemIsLight,
                    reducesTransparency: reducesTransparency)
    }

    private lazy var screenTools = PanelTools(store: store, launch: 0, screens: { [unowned self] in [builtIn, second] },
                                              picture: { _ in
        PanelPicture(png: Data([0x89]), width: 540, fit: PanelFit(height: 600, maximumHeight: 1_000), scale: 2)
    }, hud: { _ in HUDPicture(png: Data([0x89]), width: 120, height: 40, scale: 2, drawsGlow: true) })

    private func call(_ tool: String, _ arguments: [String: JSONValue] = [:], line: UInt = #line) throws -> [String: JSONValue] {
        guard case .result(let result, _) = screenTools.answer(MCPToolRequest(tool: tool, arguments: arguments)) else {
            XCTFail("\(tool) was refused", line: line)
            throw CancellationError()
        }
        return result
    }

    private func refused(_ arguments: [String: JSONValue], line: UInt = #line) throws -> String {
        let before = (layout.revision, settings.settings)
        guard case .failure(let sentence) = screenTools.answer(MCPToolRequest(tool: MCPTools.setPanelLayout, arguments: arguments)) else {
            XCTFail("the proposal was taken", line: line)
            throw CancellationError()
        }
        XCTAssertEqual(layout.revision, before.0, "a refused proposal changes nothing", line: line)
        XCTAssertEqual(settings.settings, before.1, line: line)
        XCTAssertTrue(sentence.hasPrefix("Nothing was changed. "), sentence, line: line)
        return sentence
    }

    private func listing(_ key: String, in panel: [String: JSONValue]) throws -> [String: JSONValue] {
        try XCTUnwrap((panel["screens"]?.arrayValue ?? []).compactMap(\.objectValue).first { $0["key"] == .string(key) })
    }

    private func look(_ appearance: String, _ material: String, note: String? = nil) -> JSONValue {
        var look: [String: JSONValue] = ["appearance": .string(appearance), "material": .string(material)]
        if let note { look["note"] = .string(note) }
        return .object(look)
    }

    // MARK: A draft like any other

    /// The look proposed for one screen is that screen's style draft, drawn over its settings and read back, and Save
    /// writes it into them as one version that Revert to Previous takes back; a tool writes nothing.
    func testTheLookIsADraftThatSaveKeepsAndRevertTakesBack() throws {
        let key = "SECOND-UUID"
        let panel = try call(MCPTools.setPanelLayout, ["screen": .string(key),
                                                       "hud": .object(["appearance": .string("light"), "material": .string("glass")])])
        XCTAssertEqual(layout.styleDraft(of: key), HUDStyle(appearance: .light, material: .glass))
        XCTAssertNil(layout.draft(of: key), "the look alone leaves the layout as it is")
        XCTAssertEqual(settings.effectivePlacement(on: key, hasNotch: false),
                       ScreenPlacement(appearance: .light, material: .glass))
        XCTAssertTrue(settings.settings.screens.isEmpty)
        XCTAssertEqual(changes, 0, "a tool never writes the settings")
        XCTAssertEqual(panel["layout"]?["hud"], .object(["appearance": .string("light"), "material": .string("glass")]))
        let listed = try listing(key, in: panel)
        XCTAssertEqual(listed["hud"]?["appearance"], .string("light"))
        XCTAssertEqual(listed["hud"]?["material"], .string("glass"))
        XCTAssertEqual(listed["look"], look("light", "glass"))
        XCTAssertEqual(listed["styleUnsaved"], .bool(true))

        // What was read back, sent back, keeps the draft as it is.
        let revision = layout.revision
        var again = try XCTUnwrap(panel["layout"]?.objectValue)
        again["screen"] = .string(key)
        _ = try call(MCPTools.setPanelLayout, again)
        XCTAssertEqual(layout.revision, revision)

        layout.savePanel(on: key)
        XCTAssertNil(layout.styleDraft(of: key))
        XCTAssertEqual(settings.settings.screens[key], ScreenPlacement(appearance: .light, material: .glass))
        XCTAssertEqual(changes, 1)
        layout.revert(.screen(key))
        XCTAssertNil(settings.settings.screens[key], "Revert gives back the dark, solid default")
        XCTAssertEqual(settings.effectivePlacement(on: key, hasNotch: false), .default(hasNotch: false))
    }

    /// Discard drops the look with the rest of the draft, and a proposal that leaves it out drops it too.
    func testDiscardDropsTheLook() throws {
        let key = "SECOND-UUID"
        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key), "hud": .object(["appearance": .string("system")])])
        XCTAssertEqual(settings.effectivePlacement(on: key, hasNotch: false).appearance, .system)
        _ = try call(MCPTools.discardPanelDraft, ["screen": .string(key)])
        XCTAssertNil(layout.styleDraft(of: key))
        XCTAssertEqual(settings.effectivePlacement(on: key, hasNotch: false).appearance, .dark)

        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key), "hud": .object(["material": .string("glass")])])
        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key), "hiddenSections": .array([.string("tokens")])])
        XCTAssertNil(layout.styleDraft(of: key), "a proposal is whole")
        XCTAssertEqual(settings.effectivePlacement(on: key, hasNotch: false).material, .solid)
        XCTAssertEqual(changes, 0)
    }

    /// hud.reset proposes dark and solid with the rest of the default style, the HUD style's Reset to Default gives them
    /// at once, and Revert to Previous brings the screen's own look back after either.
    func testTheResetsGiveDarkAndSolid() throws {
        let key = "SECOND-UUID"
        settings.update { $0.screens[key] = ScreenPlacement(mode: .simple, appearance: .light, material: .glass) }
        changes = 0
        let saved = settings.settings
        let panel = try call(MCPTools.setPanelLayout, ["screen": .string(key), "hud": .object(["reset": .bool(true)])])
        XCTAssertEqual(settings.effectivePlacement(on: key, hasNotch: false), .default(hasNotch: false))
        XCTAssertEqual(panel["layout"]?["hud"]["appearance"], .string("dark"), "listed by the fields that differ")
        XCTAssertEqual(panel["layout"]?["hud"]["material"], .string("solid"))
        XCTAssertEqual(try listing(key, in: panel)["look"], look("dark", "solid"))
        layout.savePanel(on: key)
        XCTAssertNil(settings.settings.screens[key])
        layout.revert(.screen(key))
        XCTAssertEqual(settings.settings, saved)

        layout.resetLook(key)
        XCTAssertNil(settings.settings.screens[key], "Reset to Default in Settings")
        layout.revert(.screen(key))
        XCTAssertEqual(settings.settings.screens[key], ScreenPlacement(mode: .simple, appearance: .light, material: .glass))
    }

    /// From "previous" brings a version's look back with its layout, as a draft.
    func testFromPreviousBringsTheLookBack() throws {
        let key = "SECOND-UUID"
        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key), "hud": .object(["appearance": .string("light")])])
        layout.savePanel(on: key)
        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key), "from": .string("previous")])
        XCTAssertEqual(settings.effectivePlacement(on: key, hasNotch: false).appearance, .dark)
        XCTAssertEqual(settings.settings.screens[key]?.appearance, .light, "as a draft, the settings as saved")
    }

    // MARK: What is refused

    /// A name this build does not know is refused with the names it takes; the panel's style has no look.
    func testAnUnknownLookIsRefused() throws {
        let appearance = try refused(["screen": .string("SECOND-UUID"), "hud": .object(["appearance": .string("auto")])])
        XCTAssertTrue(appearance.contains("hud.appearance is one of \"dark\", \"light\", \"system\"."), appearance)
        let material = try refused(["screen": .string("SECOND-UUID"), "hud": .object(["material": .string("frosted")])])
        XCTAssertTrue(material.contains("hud.material is one of \"solid\", \"glass\"."), material)
        let style = try refused(["screen": .string("SECOND-UUID"), "style": .object(["material": .string("glass")])])
        XCTAssertTrue(style.contains("The HUD's material is hud.material, for one screen."), style)
        let shared = try refused(["hud": .object(["appearance": .string("light")])])
        XCTAssertTrue(shared.contains("hud.appearance sets the resting HUD of one screen"), shared)
    }

    /// The notch at a notch stays black: its look is refused there, and taken with a mode that draws it.
    func testANotchAtANotchTakesNoLook() throws {
        let key = "BUILT-IN-UUID"
        let sentence = try refused(["screen": .string(key), "hud": .object(["appearance": .string("light")])])
        XCTAssertTrue(sentence.contains("hud.appearance: \"Built-in display\" has a notch, where a \"notch\" HUD stays black, "
                                        + "dark and solid, whatever its appearance. Leave it out, or set mode to "
                                        + "\"dynamic\" or \"simple\"."), sentence)
        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key),
                                                "hud": .object(["mode": .string("simple"), "material": .string("glass")])])
        XCTAssertEqual(layout.styleDraft(of: key), HUDStyle(mode: .simple, position: 0, material: .glass))

        // The look in effect sent back changes nothing, the notch's included.
        _ = try call(MCPTools.discardPanelDraft, ["screen": .string(key)])
        let hud = try XCTUnwrap(try listing(key, in: try call(MCPTools.getPanel))["hud"]?.objectValue)
        XCTAssertEqual(hud["appearance"], .string("dark"))
        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key), "hud": .object(hud)])
        XCTAssertNil(layout.styleDraft(of: key))
    }

    // MARK: What is read

    /// get_panel says what each screen draws now: a notch at a notch black whatever its look, `system` as macOS is
    /// set, and glass solid under Reduce Transparency, with a note where it draws other than its style asks.
    func testTheListingSaysWhatEachScreenDraws() throws {
        settings.update {
            $0.screens["BUILT-IN-UUID"] = ScreenPlacement(mode: .notch, appearance: .light, material: .glass)
            $0.screens["SECOND-UUID"] = ScreenPlacement(appearance: .system, material: .glass)
        }
        var panel = try call(MCPTools.getPanel)
        XCTAssertEqual(try listing("BUILT-IN-UUID", in: panel)["look"], look("dark", "solid", note: "A notch HUD on a screen "
            + "with a notch stays black, dark and solid, whatever its appearance and material; they show in \"dynamic\" or "
            + "\"simple\" mode."))
        XCTAssertEqual(try listing("BUILT-IN-UUID", in: panel)["hud"]?["appearance"], .string("light"), "as saved")
        XCTAssertEqual(try listing("SECOND-UUID", in: panel)["look"], look("dark", "glass"))

        systemIsLight = true
        reducesTransparency = true
        panel = try call(MCPTools.getPanel)
        XCTAssertEqual(try listing("SECOND-UUID", in: panel)["look"],
                       look("light", "solid", note: "This Mac has Reduce Transparency on, so its glass is drawn solid."))
        XCTAssertEqual(try listing("SECOND-UUID", in: panel)["hud"]?["material"], .string("glass"))
    }

    /// The pictures say glass is a stand-in where they draw it, and the resting HUD's says the look it is drawn in.
    func testThePicturesSayGlassIsAStandIn() throws {
        let key = "SECOND-UUID"
        var hud = try call(MCPTools.getPanelImage, ["screen": .string(key), "show": .string("hud")])
        XCTAssertEqual(hud["appearance"], .string("dark"))
        XCTAssertEqual(hud["material"], .string("solid"))
        XCTAssertFalse(hud["note"]?.stringValue?.contains("stand-in") == true, "\(hud["note"] ?? .null)")
        XCTAssertTrue(hud["note"]?.stringValue?.contains(", dark and solid, on a dark backdrop") == true, "\(hud["note"] ?? .null)")

        _ = try call(MCPTools.setPanelLayout, ["screen": .string(key),
                                                "hud": .object(["appearance": .string("light"), "material": .string("glass")])])
        hud = try call(MCPTools.getPanelImage, ["screen": .string(key), "show": .string("hud")])
        XCTAssertEqual(hud["appearance"], .string("light"))
        XCTAssertEqual(hud["material"], .string("glass"))
        let note = try XCTUnwrap(hud["note"]?.stringValue)
        XCTAssertTrue(note.contains(", light and glass, on a dark backdrop"), note)
        XCTAssertTrue(note.contains(PanelTools.glassStandIn), note)
        let panel = try call(MCPTools.getPanelImage, ["screen": .string(key)])
        XCTAssertTrue(panel["note"]?.stringValue?.contains(PanelTools.glassStandIn) == true, "\(panel["note"] ?? .null)")
        XCTAssertFalse(try call(MCPTools.getPanelImage)["note"]?.stringValue?.contains(PanelTools.glassStandIn) == true,
                       "the shared layout is drawn in the main display's look, solid")

        reducesTransparency = true
        hud = try call(MCPTools.getPanelImage, ["screen": .string(key), "show": .string("hud")])
        XCTAssertEqual(hud["material"], .string("solid"), "Reduce Transparency draws it solid")
        XCTAssertFalse(hud["note"]?.stringValue?.contains(PanelTools.glassStandIn) == true)

        let notch = try call(MCPTools.getPanelImage, ["screen": .string("BUILT-IN-UUID"), "show": .string("hud")])
        XCTAssertTrue(notch["note"]?.stringValue?.contains(": the island at its notch, black, as an island at a notch always is")
                      == true, "\(notch["note"] ?? .null)")
    }
}
