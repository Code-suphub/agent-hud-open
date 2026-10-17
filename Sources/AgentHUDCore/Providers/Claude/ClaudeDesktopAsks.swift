import AgentHUDSupport
import Foundation

/// The questions the Claude desktop app (its Code tab) asks through its own tools rather than a permission prompt, so that
/// no hook reports them: the next-step box a turn ends with (`mcp__ccd_turn__wrap_up` with an `ask`), and the card that
/// offers a task its own session (`mcp__ccd_session__start_session` with `initiation: "offer"`). The session log is the
/// only record: the call's input says what is asked, a result or the next prompt that it was answered.
///
/// The HUD shows them. The app takes a click in its own window; a box's answer can also be given here when the host can
/// send its words into the session as the user's next message (`Reply`), which is what a click on the box sends. An
/// offer's answer cannot be put in words, so an offer is only shown.
public enum ClaudeDesktopAsks {
    /// Sends `words` into the session `sessionID` as the user's next message: the host's way in, such as the private
    /// app's plugin. It throws when the words could not be left for the session.
    public typealias Reply = @MainActor (_ sessionID: String, _ words: String) async throws -> Void

    static let nextStepTool = "mcp__ccd_turn__wrap_up"
    static let offerTool = "mcp__ccd_session__start_session"
    /// The only calls whose input the transcript parser reads.
    static let tools: Set<String> = [nextStepTool, offerTool]

    /// The app's own buttons on an offer card, in its order.
    static let offerOptions = [SessionActivity.Ask.Option(label: "New session"), SessionActivity.Ask.Option(label: "Do it here")]
    /// The most buttons the next-step box draws.
    static let boxButtons = 2

    /// How long an ask keeps its session waiting without a newer line: as long as a turn in flight that the log has gone
    /// quiet on (`SessionPhase.Limits.abandoned`). The app's box itself stays; the HUD stops vouching that anyone is there.
    public static let standing = SessionPhase.Limits.abandoned

    /// What the call `id` of `tool`, made by `response` at `at`, asks the user; nil for a call that asks nothing: a box
    /// with only a recap, a session started without asking, or an input that names no question.
    ///
    /// The box shows its question by the app's own rules (Claude desktop 2.42304, read 2026-10-17): a call without a recap
    /// is refused; the question shows when the call says the user is blocked, or when its first button can be drawn; that
    /// is an app action, or a reply whose words the app sends as they are. The app reads the fields' earlier names too.
    static func ask(tool: String, input: [String: Any], id: String, response: String?, at: Date) -> SessionActivity.Ask? {
        switch tool {
        case nextStepTool:
            guard let recap = text(input["recap"]) ?? text(input["outcome"]),
                  let question = text(input["ask"]) ?? text(input["next_ask"]) ?? text(input["next_brief"]) else { return nil }
            let actions = (input["actions"] ?? input["next_actions"]) as? [Any] ?? []
            let blocked = input["blocked"] as? Bool == true || input["blocked"] as? String == "true" || text(input["needs_user"]) != nil
            guard blocked || (actions.first as? [String: Any]).flatMap(button) != nil else { return nil }
            // The buttons the app keeps, the first two; a reply it would not send is left out.
            let kept = actions.compactMap { $0 as? [String: Any] }.filter { action in
                guard let name = action["action"] as? String else { return text(action["label"]) != nil }
                return name == "new_session" || appAction(name) != nil
            }
            let options = kept.prefix(boxButtons).compactMap(button)
            return .init(id: id, response: response, kind: .nextStep, question: question, recap: recap, options: options, at: at)
        case offerTool:
            guard input["initiation"] as? String == "offer", let title = text(input["title"]) else { return nil }
            return .init(id: id, response: response, kind: .offer, question: title, options: offerOptions, at: at)
        default:
            return nil
        }
    }

    /// The button the box draws for one of its actions: an app action with the app's own words, or a reply the app sends
    /// as it is. Nil for one it drops: an unknown action, a session offered as an action, a reply without words, or one
    /// whose words would mention a file, run a command or hide what they send.
    static func button(_ action: [String: Any]) -> SessionActivity.Ask.Option? {
        if let name = action["action"] as? String { return appAction(name).map { .init(label: $0) } }
        guard let label = shown(action["label"]), !label.isEmpty, !sendsOtherwise(label) else { return nil }
        let message = shown(action["message"]).flatMap { $0.isEmpty ? nil : $0 }
        guard !(message.map(sendsOtherwise) ?? false) else { return nil }
        return .init(label: label, message: message)
    }

    /// Text as the app reads a button's: composed, without control, format or line-separator characters other than the
    /// joiners, its spaces collapsed.
    static func shown(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let kept = text.precomposedStringWithCanonicalMapping.unicodeScalars.filter { scalar in
            if scalar == "\u{200C}" || scalar == "\u{200D}" { return true }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return false
            default: return !["\u{115F}", "\u{1160}", "\u{3164}", "\u{FFA0}", "\u{2800}", "\u{FFFC}", "\u{1D159}", "\u{13441}",
                              "\u{13442}", "\u{16910}"].contains(scalar)
            }
        }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Words the app will not send as a reply: a mention, a command, or an invisible character.
    static func sendsOtherwise(_ words: String) -> Bool {
        words.contains("@") || words.hasPrefix("/") || words.hasPrefix("!")
            || words.unicodeScalars.contains { $0.properties.isDefaultIgnorableCodePoint }
    }

    /// The words on the button of an app action the next-step box offers; nil for one this does not know.
    static func appAction(_ action: String) -> String? {
        switch action {
        case "commit": "Commit"
        case "create_pr": "Create PR"
        case "merge": "Merge"
        case "fix_ci": "Fix CI"
        case "address_comments": "Address comments"
        case "resolve_conflicts": "Resolve conflicts"
        case "verify": "Verify"
        case "archive": "Archive"
        default: nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Whether `ask` still keeps its session waiting at `now`.
    public static func stands(_ ask: SessionActivity.Ask, at now: Date) -> Bool {
        now.timeIntervalSince(ask.at) < standing
    }

    // MARK: Requests

    /// Puts the questions `sessions` ask in the app's window at `now` among the requests the user is asked about, in place
    /// of the ones they asked before. Only the sessions whose live status is on are passed. With `reply`, a box's answer
    /// sends the words it stands for; without it, or for an offer, the card has no answers to give, and putting it away
    /// or leaving a question unanswered only hides it.
    @MainActor
    public static func show(_ sessions: [LiveSession], now: Date, in queue: PermissionRequests = .shared, reply: Reply? = nil) {
        queue.updateNativeRequests(requests(for: sessions, now: now, replies: reply != nil), source: .claude) { request, decision in
            guard let reply, request.nativeApproval == .clientReply, case .answer(let answers) = decision,
                  let words = words(answering: request, with: answers) else { return }
            try await reply(request.sessionID, words)
        }
    }

    /// The cards for the questions `sessions` ask in the app's window at `now`. Each is shown until the session's log
    /// says it was answered; with `replies` a box can be answered here, else answering it is left to the app. A question
    /// whose words were not read in this run, one the ledger kept across a relaunch, has no card: its session still waits.
    public static func requests(for sessions: [LiveSession], now: Date, replies: Bool = false) -> [PermissionRequest] {
        sessions.compactMap { session in
            guard let ask = session.activity?.ask, ask.isWorded, stands(ask, at: now) else { return nil }
            return request(ask, session: session, replies: replies)
        }
    }

    /// The words an answer to a box stands for, as a click on the box would send them: the user's own, else the chosen
    /// button's message, else its label. Nil for a box left unanswered.
    static func words(answering request: PermissionRequest, with answers: [String: PermissionQuestion.Answer]) -> String? {
        guard let question = request.questions.first, let answer = answers[question.answerKey] else { return nil }
        if let own = answer.custom?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty { return own }
        guard let label = answer.selected.first, let option = question.options.first(where: { $0.label == label }) else { return nil }
        return option.description ?? option.label
    }

    static func request(_ ask: SessionActivity.Ask, session: LiveSession, replies: Bool = false) -> PermissionRequest {
        let tool = ask.kind == .offer ? offerTool : nextStepTool
        let header = ask.kind == .offer ? L10n.text("新任务", "New task") : L10n.text("下一步", "Next step")
        let question = PermissionQuestion(id: ask.id, question: ask.question, header: header,
                                          options: ask.options.map { .init(label: $0.label, description: $0.message) })
        // A card that can be answered is another card than one that cannot: a host that starts or stops sending replaces it.
        let answerable = replies && ask.kind == .nextStep
        return PermissionRequest(id: "claude-desktop-ask:" + (answerable ? "reply:" : "") + RecordCoding.hash([session.id, ask.id]),
                                 source: .claude, sessionID: session.id, toolName: tool, summary: ask.question, detail: ask.recap,
                                 cwd: session.workingDirectory, questions: [question],
                                 nativeApproval: answerable ? .clientReply : .clientWindow, at: ask.at)
    }
}
