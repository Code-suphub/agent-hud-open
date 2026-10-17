import AgentHUDSupport
import Foundation

/// What WorkBuddy's app keeps of its sessions in `workbuddy.db`, beside `projects`: the name it gives each session, a
/// rename from its sidebar included, and what its own metering (`session_usage`) charged it. Both are read for the
/// sessions a pass reports, on every pass, through one connection: a rename shows without reparsing transcripts.
enum WorkBuddyMetering {
    struct Reading: Sendable {
        /// Each session's name in the app, by session id: the name the user gave, else the generated one.
        var titles: [String: String] = [:]
        /// What the metering charged each session, by session id; empty when the pass has no session's models.
        var credits: [String: SessionCredits] = [:]
    }

    /// `models` is each session's models as its transcript logged them; without them no credit is read.
    static func read(sessions: [ProviderSession], models: [String: Set<String>]) -> Reading {
        let prefix = "\(AdditionalSource.workbuddy.rawValue):"
        guard let database = database(beside: sessions),
              let list = try? JSONSerialization.data(withJSONObject: sessions.map { String($0.id.dropFirst(prefix.count)) }),
              let ids = String(data: list, encoding: .utf8) else { return Reading() }
        return Reading(titles: titles(ids: ids, in: database),
                       credits: models.isEmpty ? [:] : credits(ids: ids, models: models, in: database))
    }

    /// The app's database, found by walking up from a session's transcript to its `projects` folder.
    private static func database(beside sessions: [ProviderSession]) -> ReadOnlySQLite? {
        guard let path = sessions.lazy.compactMap(\.path).first,
              let projects = sequence(first: URL(fileURLWithPath: path).deletingLastPathComponent(), next: {
                  $0.pathComponents.count > 1 ? $0.deletingLastPathComponent() : nil
              }).first(where: { $0.lastPathComponent == "projects" }) else { return nil }
        return try? ReadOnlySQLite(projects.deletingLastPathComponent().appendingPathComponent("workbuddy.db"))
    }

    /// `ids` is a JSON list of the sessions' ids as the app keys them.
    private static func titles(ids: String, in database: ReadOnlySQLite) -> [String: String] {
        let prefix = "\(AdditionalSource.workbuddy.rawValue):"
        var titles: [String: String] = [:]
        try? database.rows("SELECT id, custom_title, title FROM sessions WHERE id IN (SELECT value FROM json_each(?))", strings: [ids]) { row in
            if let id = ReadOnlySQLite.text(row, 0),
               let title = SessionTitle.named(ReadOnlySQLite.text(row, 1)) ?? SessionTitle.named(ReadOnlySQLite.text(row, 2)) { titles[prefix + id] = title }
        }
        return titles
    }

    /// The credits the metering's per-model entries add up to for each session, attributed to the one model every
    /// listed session carrying an entry called, with the rest reported as unattributed rather than guessed. Its
    /// `used`/`size` are the context size and limit it metered, in tokens. Only the sessions this pass lists are read:
    /// the table holds every session the app ever recorded, and a pass pays for the rows it reports.
    private static func credits(ids: String, models: [String: Set<String>], in database: ReadOnlySQLite) -> [String: SessionCredits] {
        let prefix = "\(AdditionalSource.workbuddy.rawValue):"
        // The metering's entries, keyed as the transcripts key their sessions.
        var entries: [String: (used: Int, size: Int, credits: [String: Double])] = [:]
        do {
            try database.rows("SELECT session_id, used, size, credit_json FROM session_usage WHERE credit_json IS NOT NULL AND credit_json != '' AND session_id IN (SELECT value FROM json_each(?))",
                              strings: [ids]) { row in
                guard let raw = ReadOnlySQLite.text(row, 0), let used = ReadOnlySQLite.text(row, 1).flatMap(Int.init),
                      let size = ReadOnlySQLite.text(row, 2).flatMap(Int.init), let json = ReadOnlySQLite.text(row, 3),
                      let credits = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Double] else { return }
                entries[prefix + raw] = (used, size, credits)
            }
        } catch { return [:] }
        guard !entries.isEmpty else { return [:] }
        let keyed = entryModels(entries: entries.mapValues(\.credits), models: models)
        var result: [String: SessionCredits] = [:]
        for (id, record) in entries {
            var byModel: [String: Double] = [:], unattributed = 0.0
            for (key, value) in record.credits {
                if let model = keyed[key] { byModel["\(AdditionalSource.workbuddy.rawValue)-model:\(model)", default: 0] += value }
                else { unattributed += value }
            }
            result[id] = SessionCredits(total: record.credits.values.reduce(0, +), unattributed: unattributed,
                                        byModel: byModel, used: record.used, size: record.size)
        }
        return result
    }

    /// Names the model each metering entry charges, when one model can be the only one behind it: the model every
    /// session the entry appears in called, once those sessions are intersected. Entries whose sessions disagree,
    /// and entries no session's models explain, are left unnamed rather than guessed. Both dictionaries are keyed
    /// as the transcripts key their sessions.
    static func entryModels(entries: [String: [String: Double]], models: [String: Set<String>]) -> [String: String] {
        var keyed: [String: String] = [:]
        // The entry keys are the metering's own ids; each is looked for in every session's entries.
        for key in Set(entries.values.flatMap(\.keys)) {
            var shared: Set<String>? = nil
            for (id, record) in entries where record[key] != nil {
                guard let called = models[id] else { continue }
                shared = shared == nil ? called : shared!.intersection(called)
                if shared?.isEmpty == true { break }
            }
            if let only = shared, only.count == 1 { keyed[key] = only.first! }
        }
        return keyed
    }
}
