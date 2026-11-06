/// The statistics window's pages: token charts, sessions and persisted quota cycles. The store keeps
/// the page with the other selections that move it (`UsageStore.statsTab`); the window names it.
public enum StatsTab: Hashable, Sendable {
    case tokens, sessions, quotaCycles
}
