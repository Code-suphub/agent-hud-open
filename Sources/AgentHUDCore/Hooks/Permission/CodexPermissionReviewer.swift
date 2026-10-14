import AgentHUDSupport
import Foundation

/// Codex's hook does not name the reviewer. The matching turn's persisted context is the available source;
/// permission_mode describes the approval policy and cannot distinguish automatic review from a user's decision.
/// Codex writes a turn's context when the turn begins, so it is looked for from the end of the log back: a request
/// reads what its own turn has written and none of the conversation before it, however long the log has grown.
enum CodexPermissionReviewer {
    static func isUser(payload: JSONValue) -> Bool {
        guard let path = payload["transcript_path"].stringValue, !path.isEmpty,
              let turn = payload["turn_id"].stringValue, !turn.isEmpty else { return false }
        var reviewer: String?
        do {
            try ProviderFiles.linesFromEnd(URL(fileURLWithPath: path), marker: Data("\"turn_context\"".utf8)) { record in
                guard record["type"].stringValue == "turn_context",
                      record["payload"]["turn_id"].stringValue == turn else { return true }
                // The turn's newest context is the one that counts, a context without a reviewer included.
                reviewer = record["payload"]["approvals_reviewer"].stringValue
                return false
            }
        } catch { return false }
        return reviewer == "user"
    }
}
