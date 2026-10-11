import Foundation

/// Reads Desktop's app approvals and unanswered mid-turn questions. Engine approvals continue through their hook.
@MainActor
public final class CodexDesktopPermissionObserver {
    private let requests: PermissionRequests
    private let client: CodexDesktopPermissions
    private var task: Task<Void, Never>?
    private var sessionIDs: Set<String> = []
    /// Retained across failed readings, so a disconnect does not settle a dismissed native prompt.
    private var pending: [String: CodexDesktopPermissions.Pending] = [:]

    public init() {
        requests = .shared
        client = CodexDesktopPermissions()
    }

    init(requests: PermissionRequests, client: CodexDesktopPermissions) {
        self.requests = requests
        self.client = client
    }

    public func updateSessions(_ sessions: [LiveSession]) {
        sessionIDs = Self.threadIDs(in: sessions)
    }

    static func threadIDs(in sessions: [LiveSession]) -> Set<String> {
        Set(sessions.flatMap { [$0] + $0.descendantSessions }.compactMap { session in
            guard session.isLive, case .codexThread(let id) = session.navigationTarget else { return nil }
            return id
        })
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled else { return stop() }
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let ids = sessionIDs.union(pending.values.map(\.threadID))
                do {
                    let snapshot = try await client.fetch(threadIDs: ids)
                    try Task.checkCancellation()
                    reconcile(snapshot)
                } catch {
                    if Task.isCancelled { return }
                    requests.removeNativeRequests(source: .codex)
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func reconcile(_ snapshot: CodexDesktopPermissions.Snapshot) {
        let current = Dictionary(snapshot.pending.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in pending.values where snapshot.observedThreadIDs.contains(item.threadID) && current[item.id] == nil {
            requests.settleNativeRequest(item.id, source: .codex)
            pending.removeValue(forKey: item.id)
        }
        for item in snapshot.pending { pending[item.id] = item }
        requests.updateNativeRequests(snapshot.pending.map(\.request), source: .codex, preservesDismissals: true) { [client] request, decision in
            guard let item = current[request.id] else { return }
            try await client.resolve(decision, for: item)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        pending.removeAll()
        requests.stopNativeRequests(source: .codex)
    }
}
