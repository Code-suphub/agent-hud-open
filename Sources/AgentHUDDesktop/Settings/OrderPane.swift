import SwiftUI
import UniformTypeIdentifiers
import AgentHUDCore

struct AgentOrderRow: View {
    let agent: AgentDescriptor
    let theme: Theme
    var accountVisible = true
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            OrderDragHandle(theme: theme)
            Text(agent.shortName)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(agent.name)
            Toggle(L10n.text("显示", "Show") + " " + agent.displayName, isOn: Binding(get: { agent.enabled }, set: { onToggle($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(!accountVisible)
                .accessibilityIdentifier("agent-display-\(agent.id)")
        }
        .font(.ui(13))
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .foregroundStyle(agent.enabled ? theme.text : theme.secondary)
        .contentShape(Rectangle())
    }
}

struct OrderDragHandle: View {
    let theme: Theme

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.ui(11, .medium))
            .foregroundStyle(theme.tertiary)
            .frame(width: 16, alignment: .leading)
            .accessibilityHidden(true)
    }
}

enum AgentOrderDrag: Equatable {
    case group(String)
    case model(String)
}

/// Provider handles move entire groups; window rows reorder within their account, keeping other accounts' slots.
struct ReorderDropDelegate: DropDelegate {
    let target: AgentOrderDrag
    @Binding var dragging: AgentOrderDrag?
    let settings: SettingsStore
    /// Every group id the settings page lists, in the order it lists them. A group without quota windows is
    /// draggable too, so the check cannot rely on `settings.agents` containing rows for both ends of a move; the
    /// order matters as well, because a move rebuilds the recorded order from these ids, and a set's order would
    /// reshuffle every group on the first drag.
    var knownGroups: [String] = []
    /// The groups of `knownGroups` a drag can move and land on: those detected on this Mac. The page lists the others after
    /// them whatever the recorded order says, so a move into or out of that part would snap back.
    var movableGroups: Set<String> = []

    func validateDrop(info: DropInfo) -> Bool {
        switch (dragging, target) {
        case let (.group(sourceID), .group(targetID)):
            // The dragged group's own row is a valid place to drop: the live reorder leaves it under the pointer.
            return movableGroups.contains(sourceID) && movableGroups.contains(targetID)
        case let (.model(sourceID), .model(targetID)):
            guard let source = settings.agents.first(where: { $0.id == sourceID }),
                  let destination = settings.agents.first(where: { $0.id == targetID }) else { return false }
            return source.displayVendor == destination.displayVendor && source.displayAccountID == destination.displayAccountID
        default: return false
        }
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info), dragging != target else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            switch (dragging, target) {
            case let (.group(sourceID), .group(targetID)):
                settings.moveProviderGroup(id: sourceID, to: targetID, known: knownGroups)
            case let (.model(sourceID), .model(targetID)):
                settings.moveAccountWindow(id: sourceID, to: targetID)
            default: break
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        let accepted = validateDrop(info: info)
        dragging = nil
        return accepted
    }
}
