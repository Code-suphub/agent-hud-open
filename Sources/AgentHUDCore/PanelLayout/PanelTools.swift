import AgentHUDSupport
import Foundation

/// What Agent HUD's MCP tools do in the running application: read what the hover panel shows, draw a picture of it,
/// propose a layout for it, and drop a proposal, for the shared layout or for one screen's own.
///
/// Every answer comes from what the application holds: the last report, the settings and the layout store, the
/// attached screens, and the panel's own views, which the host measures and draws off screen through the closures it
/// passes in. Nothing here starts a provider read, opens the panel or writes the agent list or the settings, and nothing
/// here saves: a proposal is a draft until a person presses Save in the panel. A proposal is checked as an agent sent
/// it, and one the panel cannot do as asked is refused whole, with every reason, so an agent never believes a change
/// that fell back. What the layout already holds for a block, a row or an agent that is away may come back with it, so
/// the layout that was read can be sent again, and a proposal is kept as what it changes, so one that draws what is
/// saved leaves no draft. Screens are named by role and agents by vendor; nothing names an account.
@MainActor
public struct PanelTools {
    let store: UsageStore
    /// The number the revisions an agent is given are counted from.
    let launch: Int64
    /// Lists the attached screens; nil where the host has none to tell.
    let screens: (@MainActor () -> [PanelScreen])?
    /// Draws a scope's panel as `get_panel_image` returns it; nil where nothing can draw it.
    let picture: (@MainActor (PanelLayoutScope) -> PanelPicture?)?
    /// Measures a scope's panel without drawing it; nil where nothing can.
    let fit: (@MainActor (PanelLayoutScope) -> PanelFit?)?

    /// Drawn once a launch. The layout store counts its changes from 0 at every launch, so counted from 0 a revision
    /// an agent read before a relaunch would pass for the current one after it.
    private static let drawnAtLaunch = Int64.random(in: 1...999_999) * 1_000

    /// - screens: the attached displays, in the system's order, as `get_panel` lists them; without it no screen is
    ///   listed and only the shared layout, or a screen the store already keeps a layout for, can be addressed.
    /// - picture: draws the hover panel of a scope off screen, as the layout in effect there draws it, at that screen's
    ///   width and insets (the main display's for the shared layout), with account names masked, session titles left
    ///   out and what providers and clients wrote as placeholder bars; without it `get_panel_image` is refused.
    /// - fit: measures that panel off screen; without it `get_panel` leaves out the panel's height and whether it
    ///   scrolls.
    public init(store: UsageStore, screens: (@MainActor () -> [PanelScreen])? = nil,
                picture: (@MainActor (PanelLayoutScope) -> PanelPicture?)? = nil,
                fit: (@MainActor (PanelLayoutScope) -> PanelFit?)? = nil) {
        self.init(store: store, launch: Self.drawnAtLaunch, screens: screens, picture: picture, fit: fit)
    }

    /// - launch: the number revisions are counted from, where a test names its own.
    init(store: UsageStore, launch: Int64, screens: (@MainActor () -> [PanelScreen])? = nil,
         picture: (@MainActor (PanelLayoutScope) -> PanelPicture?)? = nil,
         fit: (@MainActor (PanelLayoutScope) -> PanelFit?)? = nil) {
        self.store = store
        self.launch = launch
        self.screens = screens
        self.picture = picture
        self.fit = fit
    }

    var layout: PanelLayoutStore { store.settings.panelLayout }

    /// The layouts' revision as an agent is given it: one number for every document.
    var revision: Int64 { launch + Int64(layout.revision) }

    public func answer(_ request: MCPToolRequest) -> MCPToolReply {
        let attached = screens?() ?? []
        let arguments = request.arguments
        switch request.tool {
        case MCPTools.getPanel:
            if let unknown = Self.unknown(arguments, taking: ["screen"]) {
                return .failure("get_panel takes only screen. \(unknown)")
            }
            do { return .result(panel(try scope(of: arguments, among: attached), among: attached)) }
            catch { return .failure(Self.sentence(error)) }
        case MCPTools.getPanelImage:
            if let unknown = Self.unknown(arguments, taking: ["screen"]) {
                return .failure("get_panel_image takes only screen. \(unknown)")
            }
            do { return image(try scope(of: arguments, among: attached), among: attached) }
            catch { return .failure(Self.sentence(error)) }
        case MCPTools.setPanelLayout:
            return propose(arguments, among: attached)
        case MCPTools.discardPanelDraft:
            if let unknown = Self.unknown(arguments, taking: ["screen"]) {
                return .failure("Nothing was changed. discard_panel_draft takes only screen. \(unknown)")
            }
            do {
                let scope = try scope(of: arguments, among: attached)
                layout.discard(scope)
                return .result(panel(scope, among: attached, note: discardNote(scope, among: attached)))
            } catch {
                return .failure("Nothing was changed. " + Self.sentence(error))
            }
        default:
            return .failure("Agent HUD has no tool named \"\(request.tool)\".")
        }
    }

    /// Names the arguments a tool was sent and does not take; nil when it takes them all. An argument a tool does not
    /// take is something its caller believes was heeded, so it is refused, not passed over.
    private static func unknown(_ arguments: [String: JSONValue], taking taken: [String]) -> String? {
        let unknown = arguments.keys.filter { !taken.contains($0) }.sorted()
        return unknown.isEmpty ? nil : "Unknown: \(PanelLayout.quoted(unknown))."
    }

    // MARK: Screens

    /// Why a call cannot be answered as asked, as a sentence for the agent.
    private struct Refusal: Error { let sentence: String }

    private static func sentence(_ error: Error) -> String { (error as? Refusal)?.sentence ?? "The call could not be read." }

    /// The document a call's `screen` names: the shared layout for "all" or none, else that screen's own. A key must
    /// name an attached screen or one the store keeps a layout for, which may be away.
    private func scope(of arguments: [String: JSONValue], among attached: [PanelScreen]) throws -> PanelLayoutScope {
        guard let given = arguments["screen"], given != .null else { return .shared }
        guard let key = given.stringValue else {
            throw Refusal(sentence: "screen is a screen key from get_panel's screens, or \"all\" for the shared layout.")
        }
        if key == "all" { return .shared }
        guard attached.contains(where: { $0.key == key }) || layout.screenKeys.contains(key) else {
            throw Refusal(sentence: "No screen has the key \"\(key)\". \(Self.attachedList(attached)) "
                          + "Use \"all\" for the shared layout.")
        }
        return .screen(key)
    }

    static func attachedList(_ attached: [PanelScreen]) -> String {
        guard !attached.isEmpty else { return "No screen is attached now." }
        return "The screens attached now: " + attached.map { "\"\($0.key)\" (\($0.name))" }.joined(separator: ", ") + "."
    }

    /// A screen as a sentence names it: its role in quotes, or its key where it is not attached now.
    /// - starting: whether the name starts the sentence.
    func name(of key: String, among attached: [PanelScreen], starting: Bool = false) -> String {
        if let screen = attached.first(where: { $0.key == key }) { return "\"\(screen.name)\"" }
        return (starting ? "The" : "the") + " screen \"\(key)\", which is not attached now,"
    }

    // MARK: Proposing

    private static let layoutKeys = ["blocks", "order", "sections", "hiddenSections", "style", "hud"]
    private static let draftNote = "Shown in the panel as an unsaved draft. The user keeps it by hovering the Agent HUD and "
        + "pressing Save in the panel; it is dropped when Agent HUD restarts."
    private static let savedNote = "This is the layout already saved, so there is no draft."

    private func propose(_ arguments: [String: JSONValue], among attached: [PanelScreen]) -> MCPToolReply {
        let taken = Self.layoutKeys + ["from", "revision", "screen"]
        if let unknown = Self.unknown(arguments, taking: taken) {
            return .failure("Nothing was changed. \(unknown) It takes: \(PanelLayout.quoted(taken)).")
        }
        let scope: PanelLayoutScope
        do { scope = try self.scope(of: arguments, among: attached) } catch {
            return .failure("Nothing was changed. " + Self.sentence(error))
        }
        if let given = arguments["revision"], given != .null {
            guard case .integer(let read) = given else {
                return .failure("Nothing was changed. revision is the whole number get_panel returned.")
            }
            guard read == revision else {
                return .failure("Nothing was changed. The layout changed since you read it: its revision is now "
                                + "\(revision). Call get_panel again, then propose.")
            }
        }
        if let from = arguments["from"], from != .null {
            // A key given as null is not given, here as everywhere.
            guard Self.layoutKeys.allSatisfy({ (arguments[$0] ?? .null) == .null }) else {
                return .failure("Nothing was changed. Pass either from or a layout, not both.")
            }
            switch from.stringValue {
            case "default":
                layout.proposeDefault(scope)
            case "previous":
                guard layout.canRevert(scope) else {
                    if case .screen(let key) = scope {
                        let name = name(of: key, among: attached, starting: true)
                        return .failure("Nothing was changed. \(name) has no previous saved layout.")
                    }
                    return .failure("Nothing was changed. There is no previous saved layout.")
                }
                layout.proposePrevious(scope)
            case "shared":
                guard case .screen(let key) = scope else {
                    return .failure("Nothing was changed. from \"shared\" is for a screen: it proposes that the screen "
                                    + "use the shared layout, which is screen \"all\".")
                }
                layout.propose(.shared, for: key)
            default:
                return .failure("Nothing was changed. from is \"default\", \"previous\" or \"shared\".")
            }
            return .result(panel(scope, among: attached, note: proposalNote(scope, among: attached)))
        }
        let document = JSONValue.object(arguments.filter { Self.layoutKeys.contains($0.key) })
        let existing = store.view.panelBlocks
        let saved = savedLayout(scope)
        let held = [effective(scope), saved]
        // Every reason at once: what the reading would forgive, then what the rest of the layout asks that the panel
        // cannot do. What the layout already holds for a block, a row or an agent that is away may come back with it.
        var reasons = PanelLayout.misreadings(of: document)
        let proposal = PanelLayout(json: document) ?? PanelLayout()
        reasons += proposal.issues(against: existing, holding: held).map { "\($0.path): \($0.message)" }
        reasons += proposal.hudIssues(against: agents(for: scope, among: attached), whose: whose(scope, among: attached),
                                      holding: held).map { "\($0.path): \($0.message)" }
        guard reasons.isEmpty else { return .failure("Nothing was changed. " + reasons.joined(separator: " ")) }
        // A proposal that draws what the saved layout draws is the saved layout, however it is spelled out: it leaves
        // no draft, and nothing a person could save that changes nothing.
        let asked = proposal.reduced(against: existing)
        switch scope {
        case .shared:
            layout.propose(asked == layout.current.reduced(against: existing) ? layout.current : asked)
        case .screen(let key):
            layout.propose(choice(asked, for: key, against: existing), for: key)
        }
        return .result(panel(scope, among: attached, note: proposalNote(scope, among: attached)))
    }

    /// What a screen is proposed for a layout sent for it: its saved own layout where the layout draws that; the shared
    /// layout where the screen draws the shared layout, saved or as its draft, and the layout draws what that draws, so
    /// the layout `get_panel` returned for such a screen, sent back, changes nothing; else the layout as its own.
    private func choice(_ asked: PanelLayout, for key: String, against existing: [PanelBlockInfo]) -> PanelScreenLayout {
        let own = layout.ownLayout(of: key)
        if let own, asked == own.reduced(against: existing) { return .own(own) }
        if own == nil || layout.usesShared(key), asked == layout.effective.reduced(against: existing) { return .shared }
        return .own(asked)
    }

    /// The layout a scope's panel draws now, a draft included.
    func effective(_ scope: PanelLayoutScope) -> PanelLayout {
        guard case .screen(let key) = scope else { return layout.effective }
        return layout.effective(for: key)
    }

    /// The layout a scope keeps saved: the shared one, or the screen's own, else the shared one it uses.
    private func savedLayout(_ scope: PanelLayoutScope) -> PanelLayout {
        guard case .screen(let key) = scope else { return layout.current }
        return layout.ownLayout(of: key) ?? layout.current
    }

    /// The agents a scope's layout can list now: an attached screen's own, else what any attached screen can show.
    func agents(for scope: PanelLayoutScope, among attached: [PanelScreen]) -> [String] {
        if case .screen(let key) = scope, let screen = attached.first(where: { $0.key == key }) { return screen.agents }
        return VendorMark.merged(attached.flatMap(\.agents))
    }

    private func whose(_ scope: PanelLayoutScope, among attached: [PanelScreen]) -> String {
        if case .screen(let key) = scope, attached.contains(where: { $0.key == key }) {
            return "the resting HUD of \(name(of: key, among: attached))"
        }
        return "any attached screen's resting HUD"
    }

    private func proposalNote(_ scope: PanelLayoutScope, among attached: [PanelScreen]) -> String {
        switch scope {
        case .shared:
            guard layout.hasDraft else { return Self.savedNote }
            let own = attached.filter { !layout.usesShared($0.key) }.map(\.name)
            return own.isEmpty ? Self.draftNote
                : Self.draftNote + " Screens with a layout of their own do not show it: \(PanelLayout.quoted(own))."
        case .screen(let key):
            let name = name(of: key, among: attached)
            guard let draft = layout.draft(of: key) else {
                return "This is what \(name) already has saved, so there is no draft for it."
            }
            let what = draft == .shared ? "an unsaved draft that uses the shared layout" : "an unsaved draft of its own"
            guard attached.contains(where: { $0.key == key }) else {
                return "Kept for \(name) as \(what). It shows in that display's panel if it returns before Agent HUD "
                    + "restarts, which drops it; the user keeps it with Save in that panel."
            }
            return "Shown in the panel on \(name) as \(what). The user keeps it by hovering the Agent HUD on that display "
                + "and pressing Save in the panel; it is dropped when Agent HUD restarts."
        }
    }

    private func discardNote(_ scope: PanelLayoutScope, among attached: [PanelScreen]) -> String {
        guard case .screen(let key) = scope else {
            // The screens' own drafts are theirs: dropping the shared draft leaves them, so the note names them.
            let kept = layout.screenKeys.filter { layout.hasDraft(.screen($0)) }.map { key in
                attached.first { $0.key == key }?.name ?? key
            }
            guard !kept.isEmpty else { return "There is no draft now. The panel shows the saved layout." }
            return "The shared layout has no draft now. Screens with a draft of their own keep it: "
                + "\(PanelLayout.quoted(kept)); drop one with that screen's key."
        }
        let name = name(of: key, among: attached, starting: true)
        guard layout.usesShared(key) else { return "\(name) has no draft now. Its panel shows its own saved layout." }
        guard layout.hasDraft else { return "\(name) has no draft now. Its panel shows the saved shared layout." }
        return "\(name) has no draft of its own now. It uses the shared layout, whose unsaved draft it still shows; "
            + "drop that with screen \"all\"."
    }
}
