import AgentHUDSupport
import Foundation

extension ReportView {
    /// One mark of a logo queue, as the vendors that share its artwork make it up (`VendorMark.key`): whether any of
    /// their sessions works, and what each of those sessions is doing, for the mark's bot to choose from.
    public struct QueueMark: Hashable, Sendable, Identifiable {
        /// The mark the vendors share.
        public let key: String
        /// The first of its vendors in queue order, the one the mark is drawn as.
        public let vendor: String
        /// Any of its vendors has a session in flight, as `queueVendors` says.
        public let isWorking: Bool
        /// Its vendors' sessions whose last event is at most `queueRecency` old, newest first, live status on.
        public let sessions: [SessionLiveFacts]
        /// When the last of the vendor's quota windows that ran out resets; nil while none has.
        public let exhaustedUntil: Date?

        public init(key: String, vendor: String, isWorking: Bool, sessions: [SessionLiveFacts], exhaustedUntil: Date?) {
            self.key = key; self.vendor = vendor; self.isWorking = isWorking; self.sessions = sessions
            self.exhaustedUntil = exhaustedUntil
        }

        public var id: String { key }

        /// Every request its sessions wait on, waited longest first.
        public var requests: [AttentionRequest] { sessions.flatMap(\.requests).sorted(by: AttentionRequest.waitedLonger) }

        /// The request that has waited longest; nil when none waits.
        public var waitedLongest: AttentionRequest? { requests.first }
    }

    /// The logo queue's marks, in its order: `queueVendors` collapsed onto the marks they are drawn with, as the queue
    /// draws them, each with its vendors' recent sessions and what each is doing. A mark's `isWorking` is `queueVendors`'
    /// own, so a mark works exactly when a vendor of it does.
    public var queueMarks: [QueueMark] {
        var order: [String] = [], vendors: [String: String] = [:], working: [String: Bool] = [:]
        for row in queueVendors {
            let key = VendorMark.key(row.vendor)
            if vendors[key] == nil {
                order.append(key)
                vendors[key] = row.vendor
            }
            working[key] = (working[key] ?? false) || row.isWorking
        }
        let cutoff = now.addingTimeInterval(-Self.queueRecency)
        var exhausted: [String: Date] = [:]
        for row in rows where row.assessment.showsLevel {
            guard let remaining = row.remainingPct, remaining <= AlertPolicy.exhaustedRemaining,
                  let reset = row.resetAt, reset > now else { continue }
            let key = VendorMark.key(row.agent.vendor)
            exhausted[key] = max(exhausted[key] ?? reset, reset)
        }
        var sessions: [String: [SessionLiveFacts]] = [:]
        for session in self.sessions where session.liveStatus && session.lastEventAt >= cutoff {
            guard let vendor = session.source.agentVendor else { continue }
            let key = VendorMark.key(vendor)
            sessions[key, default: []].append(facts(of: session, exhaustedUntil: exhausted[key]))
        }
        return order.map { key in
            QueueMark(key: key, vendor: vendors[key] ?? key, isWorking: working[key] ?? false, sessions: sessions[key] ?? [],
                      exhaustedUntil: exhausted[key])
        }
    }

    /// What a session is doing now, as its mark's bot reads it.
    /// - exhaustedUntil: when the session's vendor's windows that ran out reset, which a limit its client gave no reset
    ///   for lasts until.
    public func facts(of session: Session, exhaustedUntil: Date? = nil) -> SessionLiveFacts {
        let turn = session.turn
        let ended = turn.map { !$0.state.isInFlight } == true
        let outcome = ended ? turn?.outcome : nil
        var limitedUntil: Date?
        if case .limited(let resetsAt) = outcome { limitedUntil = resetsAt ?? exhaustedUntil }
        return SessionLiveFacts(
            sessionID: session.id, vendor: session.source.agentVendor, phase: session.phase,
            activity: session.session.activity, turnID: turn?.turnID,
            turnStartedAt: turn?.startedAtMs.map(RecordCoding.date), outcome: outcome,
            endedAt: ended ? turn.map { RecordCoding.date($0.observedAtMs) } : nil, limitedUntil: limitedUntil,
            observedAt: session.session.lastActivityAt ?? session.session.observedAt, lastEventAt: session.lastEventAt,
            requests: requests(of: session))
    }
}
