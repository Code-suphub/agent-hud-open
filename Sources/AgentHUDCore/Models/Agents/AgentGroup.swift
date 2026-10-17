import Foundation

/// A display group derived from the ordered model list, which keeps its groups in the recorded provider order
/// (`groupedAgentOrder(following:)`).
public struct AgentGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let agents: [AgentDescriptor]
}

public extension Array where Element == AgentDescriptor {
    /// Preserve first appearance and model order, combining rows with the same displayed agent name.
    var agentGroups: [AgentGroup] {
        var order: [String] = []
        var groups: [String: [AgentDescriptor]] = [:]
        for agent in self {
            let group = agent.displayVendor
            if groups[group] == nil { order.append(group) }
            groups[group, default: []].append(agent)
        }
        return order.map { AgentGroup(id: $0, agents: groups[$0]!) }
    }

    /// Keep every agent's models together in the same flat order used by the glow.
    var groupedAgentOrder: [AgentDescriptor] { agentGroups.flatMap(\.agents) }

    /// `groupedAgentOrder` with the groups in the recorded provider order (`Settings.providerOrder`), as Settings → Agents
    /// lists them, so the HUD, the glow and the menu bar follow the page.
    func groupedAgentOrder(following providerOrder: [String]) -> [AgentDescriptor] {
        agentGroups.inProviderOrder(providerOrder, id: \.id).flatMap(\.agents)
    }

    func movingGroup(id: String, to targetID: String) -> [AgentDescriptor] {
        var groups = agentGroups
        guard let source = groups.firstIndex(where: { $0.id == id }),
              let target = groups.firstIndex(where: { $0.id == targetID }) else { return self }
        let group = groups.remove(at: source)
        groups.insert(group, at: target)
        return groups.flatMap(\.agents)
    }
}

extension Array {
    /// The one rule of the recorded provider order: the groups it names first, in its order, then the others in their own.
    /// Entries naming no group are passed over, and a repeated one counts where it first appears.
    func inProviderOrder(_ providerOrder: [String], id: (Element) -> String) -> [Element] {
        guard !providerOrder.isEmpty else { return self }
        let rank = Dictionary(providerOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return enumerated().sorted {
            (rank[id($0.element)] ?? providerOrder.count, $0.offset) < (rank[id($1.element)] ?? providerOrder.count, $1.offset)
        }.map(\.element)
    }
}
