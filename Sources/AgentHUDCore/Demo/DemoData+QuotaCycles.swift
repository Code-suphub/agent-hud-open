import Foundation

extension DemoData {
    /// Illustrative values for the demo and snapshots, never written to the real ledger.
    public static var quotaCycles: [QuotaCycleRecord] {
        let now = DemoClock.now
        return (0..<3).map { index in
            let start = now.addingTimeInterval(-Double(4 + 7 * index) * 86400)
            let end = start.addingTimeInterval(7 * 86400)
            let remaining = [18.0, 8.0, 24.0][index]
            var record = QuotaCycleRecord(
                id: "demo-cycle-\(index)", windowID: codexAccount.windowID("codex"), accountID: codexAccount.id,
                vendor: "Codex", window: "Weekly limit", accountLabel: L10n.text("演示账户", "Demo account"), plan: "Pro x5",
                start: start, firstObserved: index == 2 ? start.addingTimeInterval(86400) : start,
                initialRemaining: index == 2 ? 50 : 100, beganBy: .firstObservation,
                lastObserved: index == 0 ? now : end.addingTimeInterval(-60), remaining: remaining,
                resetAt: end, duration: 7 * 86400)
            var usage = QuotaCycleUsage()
            usage.tokens = [18_300_000, 21_400_000, 16_100_000][index]
            usage.amounts = ["USD": [Decimal(413), Decimal(462), Decimal(351)][index]]
            record.usageDays = ["demo": usage]
            record.observedDays = ["demo": usage]
            record.usageUnavailable = index == 2
            if index > 0 { record.endedAt = end; record.endedBy = index == 1 ? .restored : .naturalReset }
            return record
        }
    }
}
