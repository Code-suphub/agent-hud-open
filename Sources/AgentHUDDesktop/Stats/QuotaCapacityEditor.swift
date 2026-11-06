import SwiftUI
import AgentHUDCore

/// An operational note, entered explicitly; observing a rise alone never creates one.
struct QuotaCapacityEditor: View {
    let record: QuotaCycleRecord
    let store: UsageStore
    let theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [QuotaCapacityCandidate] = []
    @State private var selected = Date.distantPast
    @State private var multiplier = "2"
    @State private var note = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("额度上限变更", "Capacity changes")).font(.ui(15, .semibold))
            Text(L10n.text("记录扩容等变更，按新上限计算消耗比例。", "Record a capacity increase to adjust the consumption calculation."))
                .font(.ui(12)).foregroundStyle(theme.secondary)
            if !candidates.isEmpty {
                Picker(L10n.text("变更时段", "Observed interval"), selection: $selected) {
                    ForEach(candidates) { candidate in
                        Text(label(candidate)).tag(candidate.id)
                    }
                }
                HStack {
                    Text(L10n.text("上限倍率", "Capacity multiplier"))
                    TextField("2", text: $multiplier).frame(width: 85)
                    Text(L10n.text("倍（2 = 上限翻倍）", "× (2 = double capacity)")).foregroundStyle(theme.secondary)
                }
                TextField(L10n.text("说明，例如运营活动临时扩容", "Note, e.g. temporary promotional increase"), text: $note)
                    .textFieldStyle(.roundedBorder)
                Text(L10n.text("倍率已预填，请核对后保存。", "Review the suggested multiplier before saving."))
                    .font(.ui(11)).foregroundStyle(theme.secondary)
            } else {
                Text(L10n.text("暂无可匹配的回升读数，或原始读数已过期。", "No matching rise was found, or the original readings have expired."))
                    .foregroundStyle(theme.secondary)
            }
            ForEach(record.capacityChanges ?? [], id: \.observedAt) { change in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(change.observedAt.formatted(date: .numeric, time: .shortened) + " · ×" + change.multiplier.formatted())
                        if let note = change.note { Text(note).foregroundStyle(theme.secondary) }
                    }
                    Spacer()
                    Button(L10n.text("撤销记录", "Remove")) { remove(change) }.disabled(saving)
                }.font(.ui(11))
            }
            if let error { Text(error).font(.ui(11)).foregroundStyle(theme.statusText(.critical)) }
            HStack {
                Spacer()
                Button(L10n.text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("保存记录", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || candidates.isEmpty || !(Double(multiplier).map { $0.isFinite && $0 > 1 } ?? false))
            }
        }
        .font(.ui(12)).padding(22).frame(width: 510).foregroundStyle(theme.text)
        .task {
            do {
                candidates = try await store.ledger?.quotaCapacityCandidates(recordID: record.id) ?? []
                selected = record.capacityChanges?.first?.observedAt ?? candidates.first?.id ?? .distantPast
                fill()
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: selected) { _, _ in fill() }
    }

    private func label(_ value: QuotaCapacityCandidate) -> String {
        value.after.timestamp.formatted(date: .numeric, time: .shortened) + " · " +
            value.before.remainingPct.formatted() + "% → " + value.after.remainingPct.formatted() + "%"
    }
    private func fill() {
        if let existing = record.capacityChanges?.first(where: { $0.observedAt == selected }) {
            multiplier = String(existing.multiplier); note = existing.note ?? ""
        } else if let candidate = candidates.first(where: { $0.id == selected }) {
            multiplier = String(candidate.suggestedMultiplier); note = ""
        }
    }
    private func save() {
        guard let candidate = candidates.first(where: { $0.id == selected }), let factor = Double(multiplier) else { return }
        saving = true
        Task {
            do {
                try await store.setQuotaCapacityIncrease(recordID: record.id,
                    change: .init(observedAfter: candidate.before.timestamp, observedAt: candidate.after.timestamp, multiplier: factor, note: note))
                dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
    private func remove(_ change: QuotaCapacityChange) {
        saving = true
        Task {
            do { try await store.removeQuotaCapacityIncrease(recordID: record.id, observedAt: change.observedAt); dismiss() }
            catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
