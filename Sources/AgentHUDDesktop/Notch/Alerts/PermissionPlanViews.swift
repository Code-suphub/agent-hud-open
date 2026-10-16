import AgentHUDCore
import SwiftUI

/// Whether the user is writing what a plan should change, and what they wrote so far. It lives apart from the card for
/// the reason a question's draft does: the island redraws its cards as the pointer comes and goes.
@MainActor
@Observable
final class PlanDraft {
    var noting = false
    var note = ""

    private static var drafts: [String: PlanDraft] = [:]

    static func draft(for id: String) -> PlanDraft {
        if let draft = drafts[id] { return draft }
        let draft = PlanDraft()
        drafts[id] = draft
        return draft
    }

    /// Keeps the drafts of the requests still waiting and forgets the rest.
    static func keep(_ ids: Set<String>) {
        drafts = drafts.filter { ids.contains($0.key) }
    }
}

/// A plan to read and answer with the choices its client offers: approve it, approve it and let the session accept
/// edits without asking, or send it back with what should change. The plan is on the card, so nothing is approved
/// unread; keeping on planning is no refusal and is drawn as plainly as skipping a question.
struct PermissionPlanCard: View {
    let request: PermissionRequest
    let onDecide: (PermissionDecision) -> Void
    var planHeight: CGFloat = 150
    @Environment(\.islandTyping) private var islandTyping
    @Environment(\.permissionColor) private var color

    private var draft: PlanDraft { PlanDraft.draft(for: request.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A short plan sits in a box its own size; a longer one scrolls within the height the card allows.
            ViewThatFits(in: .vertical) {
                planText
                ScrollView { planText }.frame(height: planHeight)
            }
            .frame(maxHeight: planHeight, alignment: .top)
            .background(color.inset, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityIdentifier("island-plan-text")
            if draft.noting { noteRow } else { answers }
        }
    }

    private var planText: some View {
        Text(Self.rendered(request.plan ?? request.summary))
            .font(.ui(11)).foregroundStyle(color.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(9)
    }

    private var answers: some View {
        HStack(spacing: 6) {
            QuestionButton(title: L10n.text("继续规划", "Keep planning"), symbol: nil, identifier: "island-plan-keep",
                           fill: .clear, stroke: color.border, foreground: color.secondary) {
                draft.noting = true
            }
            Spacer(minLength: 8)
            QuestionButton(title: L10n.text("批准并自动接受编辑", "Approve, accept edits"), symbol: "checkmark",
                           identifier: "island-plan-approve-edits", fill: .clear, stroke: color.allow.opacity(0.4),
                           foreground: color.allowText) {
                onDecide(.approvePlan(acceptEdits: true))
            }
            QuestionButton(title: L10n.text("批准", "Approve"), symbol: "checkmark", identifier: "island-plan-approve",
                           fill: color.allow, stroke: .clear, foreground: color.onAllow) {
                onDecide(.approvePlan(acceptEdits: false))
            }
        }
    }

    /// What should change, in the user's words; sending with nothing written still keeps the agent planning.
    private var noteRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            IslandTextField(
                text: draft.note,
                placeholder: L10n.text("要改什么（可不填）", "What should change? (optional)"),
                onChange: { draft.note = $0 },
                onSubmit: send,
                onTyping: islandTyping
            )
            .frame(height: 15)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(color.inset, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityIdentifier("island-plan-note")
            HStack(spacing: 6) {
                QuestionButton(title: L10n.text("返回", "Back"), symbol: "chevron.left", identifier: "island-plan-back",
                               fill: .clear, stroke: color.border, foreground: color.secondary) {
                    draft.noting = false
                }
                Spacer(minLength: 8)
                QuestionButton(title: L10n.text("发送", "Send"), symbol: "arrow.up", identifier: "island-plan-send",
                               fill: color.highlight, stroke: color.border, foreground: color.text, action: send)
            }
        }
    }

    private func send() {
        onDecide(.keepPlanning(draft.note))
    }

    /// The plan's Markdown as the card can draw it: emphasis, code and links inline, its lines as written, and a
    /// heading in bold without its marks.
    static func rendered(_ text: String) -> AttributedString {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let marks = line.prefix { $0 == "#" }
            guard !marks.isEmpty, marks.count <= 6, line.dropFirst(marks.count).first == " " else { return String(line) }
            let title = line.dropFirst(marks.count).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? "" : "**" + title + "**"
        }
        let markdown = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
