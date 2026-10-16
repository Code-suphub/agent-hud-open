import AgentHUDSupport
import XCTest
@testable import AgentHUDCore

/// A screen's resting HUD style as an agent writes it (`HUDStyle`), and the panel's width a layout sets: what each field
/// changes in the settings, the ranges a proposal is held to, and what is refused with which sentence.
final class HUDStyleTests: XCTestCase {
    /// Every field set, in an agent's words.
    private let every: [String: JSONValue] = [
        "mode": .string("dynamic"), "edge": .string("left"), "position": .number(0.25), "logoSize": .integer(30),
        "logoGap": .number(0.5), "edgeDistance": .integer(6), "showLogos": .bool(false), "simpleSize": .integer(32),
        "ringWidth": .number(2.5), "showRings": .bool(false), "showNumbers": .bool(false),
        "separateAgents": .bool(true), "appearance": .string("light"), "material": .string("glass"),
        "transparency": .number(0.3),
        "glow": .object(["style": .string("dots"), "effect": .string("ripple"), "brightness": .number(0.5),
                         "range": .integer(20), "blur": .integer(4), "speed": .integer(6), "amplitude": .number(0.3),
                         "outwardOnly": .bool(false)]),
    ]

    // MARK: What a style changes

    /// Each field lands on the settings' own field, and a field left out leaves it as it was.
    func testEachFieldSetsItsSettingsField() {
        let style = HUDStyle(json: every)
        let placement = style.applied(to: .default(hasNotch: true))
        XCTAssertEqual(placement, ScreenPlacement(mode: .logos, edge: .left, offset: 0.25, logoSize: 30, logoEdgeDistance: 6,
                                                  gapScale: 0.5, showsLogos: false, simpleSize: 32, ringWidth: 2.5,
                                                  showsRings: false, showsNumbers: false, separatesAgents: true,
                                                  appearance: .light, material: .glass, glassTransparency: 0.3))
        var glow = GlowSettings()
        glow.style = .dots
        glow.effect = .ripple
        glow.brightness = 0.5
        glow.range = 20
        glow.blur = 4
        glow.breathSeconds = 6
        glow.breathAmplitude = 0.3
        glow.outwardOnly = false
        XCTAssertEqual(style.applied(to: GlowSettings()), glow, "speed is the working period and amplitude the breath's depth")
        XCTAssertEqual(style.applied(to: GlowSettings()).idleBreathSeconds, GlowSettings().idleBreathSeconds,
                       "what no field names is left as it was")

        let one = HUDStyle(logoSize: 24)
        XCTAssertEqual(one.applied(to: .default(hasNotch: false)), ScreenPlacement(logoSize: 24))
        XCTAssertEqual(one.applied(to: GlowSettings()), GlowSettings())
        XCTAssertTrue(HUDStyle().isEmpty)
        XCTAssertFalse(one.isEmpty)
    }

    /// A style is written back in an agent's words, the glow's under glow, and reads back as itself.
    func testAStyleIsWrittenInAnAgentsWordsAndReadsBack() {
        let style = HUDStyle(json: every)
        XCTAssertEqual(HUDStyle(json: style.json), style)
        XCTAssertEqual(style.json["mode"], .string("dynamic"), "a Dynamic dock is dynamic to an agent")
        XCTAssertEqual(HUDStyle(mode: .simple).json, ["mode": .string("simple")], "only what is set is written")
        XCTAssertEqual(HUDStyle().json, [:])
        XCTAssertEqual(HUDMode.allCases.map(\.agentName), ["notch", "dynamic", "simple"])
        XCTAssertEqual(HUDMode(agentName: "dynamic"), .logos)
        XCTAssertNil(HUDMode(agentName: "logos"), "the settings' own name is not an agent's")
        XCTAssertEqual(HUDStyle.names, ["mode", "edge", "position", "logoSize", "logoGap", "edgeDistance", "showLogos", "simpleSize",
                                        "ringWidth", "showRings", "showNumbers", "separateAgents", "appearance",
                                        "material", "transparency", "glow"])
        XCTAssertEqual(style.json["appearance"], .string("light"), "the look keeps the settings' own names")
        XCTAssertEqual(style.json["material"], .string("glass"))
        XCTAssertEqual(HUDStyle(appearance: .system).json, ["appearance": .string("system")])
        XCTAssertEqual(style.json["transparency"], .number(0.3), "the glass's transparency is transparency to an agent")
    }

    /// The look's two fields take part in a style as every other field does: set over the settings, read back from
    /// them, and reduced to what they change; the default placement is dark and solid, as Reset to Default gives it.
    func testTheLookIsAStyleFieldLikeAnyOther() {
        let saved = ScreenPlacement(mode: .simple, appearance: .light)
        XCTAssertEqual(HUDStyle(material: .glass).applied(to: saved),
                       ScreenPlacement(mode: .simple, appearance: .light, material: .glass), "the appearance stays as saved")
        XCTAssertEqual(HUDStyle(appearance: .system).applied(to: saved).appearance, .system)
        let whole = HUDStyle(every: saved, glow: GlowSettings())
        XCTAssertEqual(whole.appearance, .light)
        XCTAssertEqual(whole.material, .solid)
        XCTAssertEqual(HUDStyle(appearance: .light, material: .glass).reduced(placement: saved, glow: GlowSettings()),
                       HUDStyle(material: .glass), "an appearance that repeats what is saved changes nothing")
        XCTAssertEqual(HUDStyle(every: .default(hasNotch: true), glow: GlowSettings()).json["appearance"], .string("dark"))
        XCTAssertEqual(HUDStyle(every: .default(hasNotch: false), glow: GlowSettings()).json["material"], .string("solid"))
        XCTAssertEqual(HUDStyle(json: ["appearance": .string("sepia"), "material": .integer(1)]), HUDStyle(),
                       "nothing this build does not know is read")
    }

    /// The glass's transparency takes part in a style as the look's other fields do: set over the settings' own
    /// `glassTransparency`, read back from them, listed beside the material whatever it is, and reduced to what it
    /// changes; it is read up to the top both materials share, 1, the slider's 100 %.
    func testTheTransparencyIsAStyleFieldLikeAnyOther() {
        let saved = ScreenPlacement(mode: .simple, material: .glass, glassTransparency: 0.4)
        XCTAssertEqual(HUDStyle(transparency: 0.1).applied(to: saved),
                       ScreenPlacement(mode: .simple, material: .glass, glassTransparency: 0.1))
        XCTAssertEqual(HUDStyle(material: .solid).applied(to: saved).glassTransparency, 0.4, "the transparency stays as saved")
        XCTAssertEqual(HUDStyle(every: saved, glow: GlowSettings()).transparency, 0.4)
        XCTAssertEqual(HUDStyle(every: .default(hasNotch: true), glow: GlowSettings()).json["transparency"],
                       .number(0), "a solid HUD lists its own, opaque at first")
        XCTAssertEqual(HUDStyle(transparency: 0.3).applied(to: ScreenPlacement()).solidTransparency, 0.3,
                       "on a solid HUD it is solid's")
        XCTAssertEqual(HUDStyle(transparency: 0.4, glow: HUDStyle.Glow()).reduced(placement: saved, glow: GlowSettings()),
                       HUDStyle(), "a transparency that repeats what is saved changes nothing")
        XCTAssertEqual(HUDStyle(json: ["transparency": .integer(0)]), HUDStyle(transparency: 0), "a whole number is a number")
        XCTAssertEqual(HUDStyle(json: ["transparency": .number(0.9)]).json, ["transparency": .number(0.9)])
        XCTAssertEqual(HUDStyle(json: ["transparency": .number(0.95)]), HUDStyle(transparency: 0.95))
        XCTAssertEqual(HUDStyle(json: ["transparency": .integer(1)]), HUDStyle(transparency: 1), "the top is read")
        XCTAssertEqual(HUDStyle(json: ["transparency": .number(1.2)]), HUDStyle(), "nothing out of range is read")
        XCTAssertEqual(HUDStyle(json: ["transparency": .string("0.5")]), HUDStyle())
    }

    /// A transparency proposed with a new material is that material's, so it is weighed against what that material has
    /// saved: one equal to the old material's is kept, from solid to glass and from glass to solid, and one equal to the
    /// new material's own is left out, the material kept. The style a draft draws, sent back whole, is that draft.
    func testATransparencyBesideANewMaterialIsWeighedAgainstThatMaterial() {
        let glow = GlowSettings()
        let solid = ScreenPlacement(mode: .simple)
        XCTAssertEqual(solid.solidTransparency, 0)
        XCTAssertEqual(solid.glassTransparency, ScreenPlacement.standardGlassTransparency)
        let toGlass = HUDStyle(material: .glass, transparency: 0)
        XCTAssertEqual(toGlass.reduced(placement: solid, glow: glow), toGlass, "solid's 0 is not glass's")
        XCTAssertEqual(toGlass.reduced(placement: solid, glow: glow).applied(to: solid),
                       ScreenPlacement(mode: .simple, material: .glass, glassTransparency: 0))
        XCTAssertEqual(HUDStyle(material: .glass, transparency: ScreenPlacement.standardGlassTransparency)
            .reduced(placement: solid, glow: glow), HUDStyle(material: .glass), "glass's own, as saved")
        XCTAssertEqual(HUDStyle(every: toGlass.applied(to: solid), glow: glow).reduced(placement: solid, glow: glow), toGlass,
                       "the style drawn, sent back whole")

        let glass = ScreenPlacement(mode: .simple, material: .glass, glassTransparency: 0.4, solidTransparency: 0.1)
        let toSolid = HUDStyle(material: .solid, transparency: 0.4)
        XCTAssertEqual(toSolid.reduced(placement: glass, glow: glow), toSolid, "glass's 0.4 is not solid's")
        XCTAssertEqual(toSolid.reduced(placement: glass, glow: glow).applied(to: glass).solidTransparency, 0.4)
        XCTAssertEqual(HUDStyle(material: .solid, transparency: 0.1).reduced(placement: glass, glow: glow),
                       HUDStyle(material: .solid), "solid's own, as saved")
        XCTAssertEqual(HUDStyle(every: toSolid.applied(to: glass), glow: glow).reduced(placement: glass, glow: glow), toSolid)
        XCTAssertEqual(HUDStyle(material: .glass, transparency: 0.4).reduced(placement: glass, glow: glow), HUDStyle(),
                       "the material as saved weighs its own")
        XCTAssertEqual(HUDStyle(transparency: 0.1).reduced(placement: glass, glow: glow), HUDStyle(transparency: 0.1),
                       "without a material, the one saved")
    }

    /// What glass is made of, clear or regular Liquid Glass or a material, is chosen in Settings alone: no style field
    /// names it, a style keeps the screen's own whatever it sets, the material and its transparency included, and an
    /// agent reads the same style from a screen whatever glass it has, so a style sent back whole changes nothing.
    func testTheGlassStyleIsNoStyleField() {
        XCTAssertFalse(HUDStyle.names.contains("glassStyle"))
        XCTAssertEqual(HUDStyle(json: ["glassStyle": .string("regular")]), HUDStyle(), "an agent's glassStyle is not read")
        let plain = ScreenPlacement(mode: .simple, material: .glass, glassTransparency: 0.4)
        for glassStyle in HUDGlassStyle.allCases {
            let glass = ScreenPlacement(mode: .simple, material: .glass, glassStyle: glassStyle, glassTransparency: 0.4)
            XCTAssertEqual(HUDStyle(material: .solid, transparency: 0.2).applied(to: glass).glassStyle, glassStyle,
                           "\(glassStyle) kept while solid")
            let solid = ScreenPlacement(mode: .simple, glassStyle: glassStyle)
            XCTAssertEqual(HUDStyle(material: .glass, transparency: 0.7).applied(to: solid).glassStyle, glassStyle,
                           "\(glassStyle) drawn once glass")
            let whole = HUDStyle(every: glass, glow: GlowSettings())
            XCTAssertEqual(whole, HUDStyle(every: plain, glow: GlowSettings()), "\(glassStyle) reads as any glass")
            XCTAssertTrue(whole.reduced(placement: glass, glow: GlowSettings()).isEmpty, "\(glassStyle)")
        }
    }

    /// Reduced against what a screen has saved, a style keeps only what it changes: the style a screen has in effect,
    /// sent back whole, changes nothing.
    func testAStyleIsReducedToWhatItChanges() {
        let saved = ScreenPlacement(mode: .logos, logoSize: 24), glow = GlowSettings()
        let whole = HUDStyle(every: saved, glow: glow)
        XCTAssertTrue(whole.reduced(placement: saved, glow: glow).isEmpty)
        var asked = whole
        asked.logoSize = 30
        asked.glow.range = 20
        XCTAssertEqual(asked.reduced(placement: saved, glow: glow), HUDStyle(logoSize: 30, glow: HUDStyle.Glow(range: 20)))
    }

    /// A dock that leaves the notch for the top edge, never moved from the centre and with no position given, starts at
    /// the top left, as Settings' own change of mode places it, clear of the hardware.
    func testADockLeavingTheNotchStartsClearOfIt() {
        let notch = ScreenPlacement.default(hasNotch: true)
        XCTAssertEqual(HUDStyle(mode: .simple).placedClearOfTheNotch(from: notch, hasNotch: true), HUDStyle(mode: .simple, position: 0))
        XCTAssertEqual(HUDStyle(mode: .simple, position: 0.7).placedClearOfTheNotch(from: notch, hasNotch: true),
                       HUDStyle(mode: .simple, position: 0.7), "a position given is kept")
        XCTAssertEqual(HUDStyle(mode: .logos, edge: .left).placedClearOfTheNotch(from: notch, hasNotch: true),
                       HUDStyle(mode: .logos, edge: .left), "another edge is clear of it")
        XCTAssertEqual(HUDStyle(mode: .logos).placedClearOfTheNotch(from: ScreenPlacement(mode: .notch), hasNotch: false),
                       HUDStyle(mode: .logos), "a screen without a notch has nothing to clear")
    }

    // MARK: What is refused

    /// Every number is held to the range Settings keeps it in, written in the sentence; a bound itself is taken.
    func testEveryNumberIsHeldToItsSettingsRange() {
        let ranges: [(String, ClosedRange<Double>)] = [
            ("position", 0...1), ("logoSize", ScreenPlacement.logoSizeRange), ("logoGap", ScreenPlacement.gapScaleRange),
            ("edgeDistance", ScreenPlacement.logoEdgeDistanceRange), ("simpleSize", ScreenPlacement.simpleSizeRange),
            ("ringWidth", ScreenPlacement.ringWidthRange), ("transparency", ScreenPlacement.glassTransparencyRange),
        ]
        for (name, range) in ranges {
            XCTAssertEqual(HUDStyle.misreadings(ofField: name, .number(range.lowerBound)), [], name)
            XCTAssertEqual(HUDStyle.misreadings(ofField: name, .number(range.upperBound)), [], name)
            let sentence = "hud.\(name) is a number from \(HUDStyle.written(range.lowerBound)) to \(HUDStyle.written(range.upperBound))."
            XCTAssertEqual(HUDStyle.misreadings(ofField: name, .number(range.upperBound + 0.5)), [sentence])
            XCTAssertEqual(HUDStyle.misreadings(ofField: name, .number(range.lowerBound - 0.05)), [sentence])
            XCTAssertEqual(HUDStyle.misreadings(ofField: name, .string("12")), [sentence], "a number written as text")
            XCTAssertEqual(HUDStyle(json: [name: .number(range.upperBound + 1)]), HUDStyle(), "nothing out of range is read")
        }
        XCTAssertEqual(HUDStyle.misreadings(ofField: "logoSize", .number(37)), ["hud.logoSize is a number from 12 to 36."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "logoGap", .number(0.05)), ["hud.logoGap is a number from 0.1 to 0.6."])
        XCTAssertEqual(ScreenPlacement.glassTransparencyRange, ScreenPlacement.solidTransparencyRange,
                       "one range for glass and solid")
        XCTAssertEqual(HUDStyle.misreadings(ofField: "transparency", .number(1)), [], "the top is in range")
        XCTAssertEqual(HUDStyle.misreadings(ofField: "transparency", .number(1.2)),
                       ["hud.transparency is a number from 0 to 1."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "transparency", .bool(true)),
                       ["hud.transparency is a number from 0 to 1."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "transparency", .integer(0)), [])

        let glow: [(String, ClosedRange<Double>)] = [
            ("brightness", GlowSettings.brightnessRange), ("range", GlowSettings.sizeRange), ("blur", GlowSettings.sizeRange),
            ("speed", GlowSettings.workingPeriodRange), ("amplitude", GlowSettings.amplitudeRange),
        ]
        for (name, range) in glow {
            XCTAssertEqual(HUDStyle.misreadings(ofField: "glow", .object([name: .number(range.upperBound)])), [], name)
            XCTAssertEqual(HUDStyle.misreadings(ofField: "glow", .object([name: .number(range.upperBound + 1)])),
                           ["hud.glow.\(name) is a number from \(HUDStyle.written(range.lowerBound)) to "
                            + "\(HUDStyle.written(range.upperBound))."])
        }
        XCTAssertEqual(HUDStyle.misreadings(ofField: "glow", .object(["speed": .integer(20)])),
                       ["hud.glow.speed is a number from 1 to 12."], "the working period Settings offers")
        XCTAssertEqual(HUDStyle.misreadings(ofField: "glow", .object(["brightness": .number(0.1)])),
                       ["hud.glow.brightness is a number from 0.2 to 1."])
    }

    /// A name this build does not know, a value of the wrong type and a property the glow does not have are each told.
    func testNamesTypesAndPropertiesAreTold() {
        XCTAssertEqual(HUDStyle.misreadings(ofField: "mode", .string("logos")),
                       ["hud.mode is one of \"notch\", \"dynamic\", \"simple\"."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "edge", .string("centre")),
                       ["hud.edge is one of \"top\", \"right\", \"bottom\", \"left\"."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "appearance", .string("auto")),
                       ["hud.appearance is one of \"dark\", \"light\", \"system\"."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "appearance", .bool(true)),
                       ["hud.appearance is one of \"dark\", \"light\", \"system\"."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "material", .string("frosted")),
                       ["hud.material is one of \"solid\", \"glass\"."])
        for name in HUDAppearance.allCases.map(\.rawValue) {
            XCTAssertEqual(HUDStyle.misreadings(ofField: "appearance", .string(name)), [], name)
        }
        for name in HUDMaterial.allCases.map(\.rawValue) {
            XCTAssertEqual(HUDStyle.misreadings(ofField: "material", .string(name)), [], name)
        }
        XCTAssertEqual(HUDStyle.misreadings(ofField: "material", .null), [])
        XCTAssertEqual(PanelLayout.misreadings(of: .object(["style": .object(["appearance": .string("light")])])),
                       ["style has no property \"appearance\"; the style takes spacing, separators and width. The HUD's "
                        + "appearance is hud.appearance, for one screen."], "the panel's style points to the hud's")
        XCTAssertEqual(PanelLayout.misreadings(of: .object(["style": .object(["transparency": .number(0.3)])])),
                       ["style has no property \"transparency\"; the style takes spacing, separators and width. The HUD's "
                        + "transparency is hud.transparency, for one screen."])
        for name in ["showLogos", "showRings", "showNumbers", "separateAgents"] {
            XCTAssertEqual(HUDStyle.misreadings(ofField: name, .string("yes")), ["hud.\(name) is true or false."])
            XCTAssertEqual(HUDStyle.misreadings(ofField: name, .bool(true)), [])
        }
        XCTAssertEqual(HUDStyle.misreadings(ofField: "glow", .string("dots")), ["hud.glow is an object."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "glow", .object(["style": .string("neon"), "effect": .string("spin"),
                                                                      "outwardOnly": .integer(1), "colour": .string("red")])), [
            "hud.glow has no property \"colour\"; the glow takes style, effect, brightness, range, blur, speed, amplitude "
                + "and outwardOnly.",
            "hud.glow.effect is one of \"breathe\", \"flow\", \"scan\", \"ripple\", \"shimmer\", \"boot\".",
            "hud.glow.outwardOnly is true or false.",
            "hud.glow.style is one of \"blur\", \"dots\", \"ascii\", \"blocks\", \"braille\", \"binary\".",
        ])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "mode", .null), [], "a value given as null is not given")
        XCTAssertNil(HUDStyle.misreadings(ofField: "background", .string("blue")), "a key that names no field is the caller's")
        XCTAssertEqual(PanelLayout.misreadings(of: .object(["hud": .object(["background": .string("blue")])])),
                       ["hud has no property \"background\"; the hud takes agents, mode, edge, position, logoSize, logoGap, "
                        + "edgeDistance, showLogos, simpleSize, ringWidth, showRings, showNumbers, separateAgents, "
                        + "appearance, material, transparency, glow and reset."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "reset", .string("yes")), ["hud.reset is true or false."])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "reset", .bool(false)), [])
        XCTAssertEqual(HUDStyle.misreadings(ofField: "reset", .null), [])
        XCTAssertEqual(HUDStyle(json: ["reset": .bool(true)]), HUDStyle(), "reset is no field of a style")
    }

    /// What the screen's HUD would not draw as asked is refused: the notch on a screen without one, and a field the mode
    /// it would have does not draw, as Settings shows each only for its modes.
    func testWhatTheHUDWouldNotDrawIsAnIssue() {
        let notch = ScreenPlacement.default(hasNotch: true), dock = ScreenPlacement.default(hasNotch: false), glow = GlowSettings()
        func issues(_ style: HUDStyle, _ placement: ScreenPlacement, hasNotch: Bool = true) -> [String] {
            style.issues(placement: placement, glow: glow, hasNotch: hasNotch, screen: "\"Display 2\"").map { "\($0.path): \($0.message)" }
        }
        XCTAssertEqual(issues(HUDStyle(mode: .notch), dock, hasNotch: false),
                       ["hud.mode: \"Display 2\" has no notch, so its HUD cannot be \"notch\". It can be \"dynamic\" or \"simple\"."])
        XCTAssertEqual(issues(HUDStyle(mode: .notch), dock), [])
        XCTAssertEqual(issues(HUDStyle(logoSize: 30), notch),
                       ["hud.logoSize: logoSize sets a \"dynamic\" HUD, and the HUD of \"Display 2\" would be \"notch\". "
                        + "Leave it out, or set mode to \"dynamic\"."])
        XCTAssertEqual(issues(HUDStyle(mode: .logos, logoSize: 30), notch), [], "with the mode that draws it")
        XCTAssertEqual(issues(HUDStyle(edge: .left), notch).count, 1, "beside the notch there is no edge to choose")
        XCTAssertEqual(issues(HUDStyle(mode: .simple, logoSize: 30), dock).first?.hasPrefix("hud.logoSize: "), true)
        XCTAssertEqual(issues(HUDStyle(simpleSize: 30, separateAgents: true), dock).count, 1, "a dock separates; it has no rings")
        XCTAssertEqual(issues(HUDStyle(mode: .simple, glow: HUDStyle.Glow(style: .dots)), dock),
                       ["hud.glow.style: A \"simple\" HUD draws no glow, and the HUD of \"Display 2\" would be \"simple\"."])
        XCTAssertEqual(issues(HUDStyle(glow: HUDStyle.Glow(style: .dots, range: 20)), notch),
                       ["hud.glow.range: range sets the \"blur\" glow style, and the glow of \"Display 2\" would be \"dots\"."])
        XCTAssertEqual(issues(HUDStyle(glow: HUDStyle.Glow(effect: .scan, amplitude: 0.2)), notch),
                       ["hud.glow.amplitude: amplitude sets the \"breathe\" effect, and the glow of \"Display 2\" would play \"scan\"."])
        XCTAssertEqual(issues(HUDStyle(glow: HUDStyle.Glow(style: .dots, effect: .ripple, brightness: 0.4, speed: 5)), notch), [])
    }

    /// The look is drawn in every mode, the notch's on a display that has one too, whose row stays dark while its panel
    /// and its cards take the look: there the appearance and the material are taken as on any other screen.
    func testANotchAtANotchTakesTheLook() {
        let notch = ScreenPlacement.default(hasNotch: true), glow = GlowSettings()
        func issues(_ style: HUDStyle, _ placement: ScreenPlacement, hasNotch: Bool) -> [String] {
            style.issues(placement: placement, glow: glow, hasNotch: hasNotch, screen: "\"Built-in display\"")
                .map { "\($0.path): \($0.message)" }
        }
        XCTAssertEqual(issues(HUDStyle(appearance: .light, material: .glass), notch, hasNotch: true), [])
        XCTAssertEqual(issues(HUDStyle(appearance: .light, material: .glass, transparency: 0.2), notch, hasNotch: true), [],
                       "with the glass's transparency too")
        XCTAssertEqual(issues(HUDStyle(mode: .simple, appearance: .light, material: .glass), notch, hasNotch: true), [],
                       "a dock on a notched display draws its look")
        XCTAssertEqual(issues(HUDStyle(appearance: .system), ScreenPlacement(mode: .notch), hasNotch: false), [],
                       "the bar that stands in for a notch draws it")
        XCTAssertEqual(issues(HUDStyle(mode: .notch, material: .glass), ScreenPlacement(mode: .simple), hasNotch: true), [],
                       "back to the notch, the glass is kept")
        for mode in HUDMode.allCases {
            for hasNotch in [true, false] where mode != .notch || hasNotch {
                XCTAssertEqual(issues(HUDStyle(appearance: .light, material: .glass), ScreenPlacement(mode: mode),
                                      hasNotch: hasNotch), [], "\(mode) \(hasNotch)")
            }
        }
    }

    /// A transparency is taken on any screen and in any mode, for the material in effect, the style's own or the one
    /// saved, as Settings offers it beside Solid and Glass alike, up to the 1 both share, the slider's 100 %: no HUD
    /// refuses one within that range, solid included, and a number past it is the field's to refuse (`misreadings`), as
    /// any number is. The style keeps the number sent, and the screen scales what it draws of it
    /// (`ScreenPlacement.drawsTransparency(reducesTransparency:)`).
    func testATransparencyIsTakenForEitherMaterial() {
        let glow = GlowSettings()
        func issues(_ style: HUDStyle, _ placement: ScreenPlacement, hasNotch: Bool = false) -> [String] {
            style.issues(placement: placement, glow: glow, hasNotch: hasNotch, screen: "\"Display 2\"")
                .map { "\($0.path): \($0.message)" }
        }
        for mode in HUDMode.allCases {
            XCTAssertEqual(issues(HUDStyle(transparency: 0.2), ScreenPlacement(mode: mode), hasNotch: true), [], "\(mode)")
        }
        let solid = ScreenPlacement(mode: .logos), glass = ScreenPlacement(mode: .logos, material: .glass)
        XCTAssertEqual(HUDStyle(transparency: 0.2).applied(to: solid).solidTransparency, 0.2)
        XCTAssertEqual(HUDStyle(transparency: 0.2).applied(to: glass).glassTransparency, 0.2)
        XCTAssertEqual(HUDStyle(material: .glass, transparency: 0.2).applied(to: solid).glassTransparency, 0.2,
                       "with the glass it sets")
        XCTAssertEqual(HUDStyle(material: .solid, transparency: 0.2).applied(to: glass).solidTransparency, 0.2,
                       "with the solid it sets")
        XCTAssertEqual(HUDStyle(material: .solid, transparency: 0.2).applied(to: glass).glassTransparency,
                       ScreenPlacement.standardGlassTransparency, "glass's kept as saved")

        let top = ScreenPlacement.glassTransparencyRange.upperBound
        XCTAssertEqual(top, 1)
        XCTAssertEqual(issues(HUDStyle(transparency: top), glass), [], "glass's top")
        XCTAssertEqual(HUDStyle(transparency: top).applied(to: glass).glassTransparency, top)
        XCTAssertEqual(issues(HUDStyle(material: .glass, transparency: top), solid), [], "where the style makes it glass")
        XCTAssertEqual(HUDStyle(material: .glass, transparency: top).applied(to: solid).glassTransparency, top)
        XCTAssertEqual(issues(HUDStyle(transparency: top), solid), [], "solid's top, the same")
        XCTAssertEqual(HUDStyle(transparency: top).applied(to: solid).solidTransparency, top)
        XCTAssertEqual(issues(HUDStyle(material: .solid, transparency: top), glass), [], "where the style makes it solid")
        XCTAssertEqual(HUDStyle(material: .solid, transparency: top).applied(to: glass).solidTransparency, top)
        for material in HUDMaterial.allCases {
            XCTAssertEqual(issues(HUDStyle(appearance: .light, material: material, transparency: top),
                                  .default(hasNotch: true), hasNotch: true), [], "\(material): a notch HUD at a notch too")
        }
        XCTAssertEqual(HUDStyle.misreadings(ofField: "transparency", .number(1.2)),
                       ["hud.transparency is a number from 0 to 1."], "past the top, refused as any number is")
    }

    // MARK: The panel's width

    /// A layout's width is a whole number from 480 to 720; left out, or at 540, it is today's panel, which is not
    /// written. An agent's own panel on a separated dock is 100 points narrower and never below 440.
    func testThePanelsWidthIsReadNormalizedAndNarrowedForOneAgent() throws {
        XCTAssertEqual(PanelStyle().panelWidth, 540)
        XCTAssertEqual(PanelStyle().agentPanelWidth, 440, "as before layouts had a width")
        for (width, agent) in [(480, 440), (540, 440), (541, 441), (600, 500), (720, 620)] {
            let style = PanelStyle(width: width)
            XCTAssertEqual(style.panelWidth, width)
            XCTAssertEqual(style.agentPanelWidth, agent, "\(width)")
        }
        XCTAssertEqual(PanelStyle(width: 479).panelWidth, 540, "a width out of range is none")
        XCTAssertEqual(PanelStyle(width: 721).panelWidth, 540)
        XCTAssertEqual(PanelStyle(width: 540).normalized(), PanelStyle())
        XCTAssertEqual(PanelLayout(style: PanelStyle(width: 540)).normalized(), PanelLayout())
        XCTAssertTrue(PanelLayout(style: PanelStyle(width: 540)).isDefault)

        func read(_ json: String) throws -> PanelLayout { try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8)) }
        XCTAssertEqual(try read(#"{"style":{"width":720}}"#).style.width, 720)
        XCTAssertNil(try read(#"{"style":{"width":900}}"#).style.width, "a stored width out of range is forgiven as none")
        XCTAssertNil(try read(#"{"style":{"width":"wide"}}"#).style.width)
        let written = String(decoding: try RecordCoding.encoder().encode(PanelLayout(style: PanelStyle(width: 600))), as: UTF8.self)
        XCTAssertEqual(written, #"{"style":{"width":600}}"#)
        XCTAssertEqual(String(decoding: try RecordCoding.encoder().encode(PanelLayout(style: PanelStyle(width: 540))), as: UTF8.self),
                       "{}", "the default width is not written")

        let sentence = "style.width is a whole number from 480 to 720."
        for wrong in [JSONValue.integer(479), .integer(721), .number(600.5), .string("600"), .bool(true)] {
            XCTAssertEqual(PanelLayout.misreadings(of: .object(["style": .object(["width": wrong])])), [sentence], "\(wrong)")
        }
        XCTAssertEqual(PanelLayout.misreadings(of: .object(["style": .object(["width": .integer(480)])])), [])
        XCTAssertEqual(PanelLayout.misreadings(of: .object(["style": .object(["width": .number(720)])])), [])
    }
}
