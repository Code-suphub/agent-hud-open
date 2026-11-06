import Foundation
import AgentHUDSupport

/// A source independent of local model logs. Only configured queries run, at the collector's account cadence.
public actor CustomBalanceUsageProvider: UsageProvider {
    private let profiles: @Sendable () async -> [CustomBalanceProfile]
    private let read: @Sendable (CustomBalanceProfile) async throws -> [BalanceField]
    private let clock: @Sendable () -> Date
    private let ledger: UsageLedger
    private var readings: [String: (profile: CustomBalanceProfile, value: AccountBalance?, at: Date?, notice: String?, authentication: Bool)] = [:]

    public init(profiles: @escaping @Sendable () async -> [CustomBalanceProfile], ledger: UsageLedger = .inMemory(),
                read: @escaping @Sendable (CustomBalanceProfile) async throws -> [BalanceField] = {
                    try await BalanceRequestClient.fetch(BalanceRequestStore.load(id: $0.id))
                }, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.profiles = profiles; self.ledger = ledger; self.read = read; self.clock = clock
    }

    public nonisolated var watchedDirectories: [URL]? { [] }
    public nonisolated var seesLocalWork: Bool { false }

    public func refreshAccountUsage(historyHours: Int) async {
        let active = await profiles().filter(\.enabled)
        readings = readings.filter { id, _ in active.contains { $0.id == id } }
        for profile in active {
            guard !Task.isCancelled else { return }
            // Failed authentication is not retried in the background until the user replaces the credentials.
            if let previous = readings[profile.id], Self.sameRequest(previous.profile, profile), previous.authentication { continue }
            let now = clock()
            do {
                let fields = try await read(profile)
                let amounts = try profile.amounts(in: fields)
                let initialBalance = AccountBalance(currency: profile.currency, total: amounts.balance, granted: 0, toppedUp: 0,
                                             limit: amounts.total)
                let billing = Self.pool(profile).id
                _ = try? await ledger.write { try $0.appendBalances([initialBalance], billing: billing, at: now) }
                let samples = (try? await ledger.balanceSamples(billing: billing, currency: profile.currency,
                    since: now.addingTimeInterval(-BalanceTrend.lookback))) ?? []
                let balance = AccountBalance(currency: profile.currency, total: amounts.balance, granted: 0, toppedUp: 0,
                                         runsOutAt: BalanceTrend.runsOutAt(samples, at: now), limit: amounts.total)
                readings[profile.id] = (profile, balance, now, nil, false)
            } catch {
                if Task.isCancelled { return }
                // A changed unit or mapping invalidates the former figure; a transient read failure does not.
                let old = readings[profile.id].flatMap { Self.pool($0.profile) == Self.pool(profile) ? $0 : nil }
                readings[profile.id] = (profile, old?.value, old?.at,
                    (error as? BalanceRequestFailure)?.localizedDescription ?? (error as? UsageProviderError)?.message ??
                        L10n.text("余额查询失败", "Balance query failed"), error is BalanceRequestFailure)
            }
        }
    }

    public func fetchUsage(agents: [AgentDescriptor], historyHours: Int) async throws -> UsageReport {
        let active = await profiles().filter(\.enabled)
        let descriptors = active.map { profile in
            AgentDescriptor(id: "custom-balance:\(profile.id)", vendor: profile.name, model: "Balance",
                source: L10n.text("自定义余额接口", "Custom balance endpoint"), enabled: true, billingPool: Self.pool(profile))
        }
        let billing = active.map { profile in
            let reading = readings[profile.id].flatMap { Self.sameRequest($0.profile, profile) ? $0 : nil }
            return APIBilling(vendor: profile.name, balances: reading?.value.map { [$0] } ?? [],
                isAvailable: reading?.value.map { $0.total > 0 }, updatedAt: reading?.at,
                notice: reading?.notice, readingIssue: reading?.notice.map(ReadingIssue.readFailed), billingPool: Self.pool(profile),
                requiresAuthentication: reading?.authentication)
        }
        return UsageReport(generatedAt: clock(), snapshots: [], sessions: [], discoveredAgents: descriptors, usage: [], billing: billing)
    }

    public nonisolated static func pool(_ profile: CustomBalanceProfile) -> BillingPool {
        BillingPool(provider: profile.name, realm: "custom-balance", product: .api, scope: profile.id,
            evidence: .account, entitlement: RecordCoding.hash([profile.currency, profile.balancePath, profile.totalPath ?? "",
                NSDecimalNumber(decimal: profile.divisor).stringValue, profile.valueKind.rawValue]))
    }

    private static func sameRequest(_ left: CustomBalanceProfile, _ right: CustomBalanceProfile) -> Bool {
        pool(left) == pool(right) && left.credentialRevision == right.credentialRevision
    }
}

public extension APIBilling {
    var isCustomBalance: Bool { billingPool?.realm == "custom-balance" }
}
