import Foundation

/// `CODEBUDDY_CONFIG_DIR` naming WorkBuddy's own folder, `~/.workbuddy`: CodeBuddy Code then runs from WorkBuddy's
/// installation, and what is in that folder is WorkBuddy's. Its transcripts are read once, by the WorkBuddy source, and
/// its `settings.json` holds WorkBuddy's approval and completion handlers, which answer CodeBuddy Code's sessions there
/// too. The CodeBuddy source keeps `~/.codebuddy` (`CodeBuddySessions.home`).
enum CodeBuddySharedHome {
    /// WorkBuddy's folder when the variable names it, else nil.
    static func folder(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let value = ClientHome.variable("CODEBUDDY_CONFIG_DIR", in: environment) else { return nil }
        let workBuddy = home.appendingPathComponent(".workbuddy")
        return URL(fileURLWithPath: value).standardizedFileURL.path == workBuddy.standardizedFileURL.path ? workBuddy : nil
    }

    /// Takes CodeBuddy's approval and completion handlers out of WorkBuddy's `settings.json`, where an earlier version,
    /// which read the variable as CodeBuddy's own home, wrote them: beside WorkBuddy's own they would ask the HUD twice
    /// for one request and report one turn twice. Every other entry is left alone, and a missing file stays missing.
    static func removeHandlers(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment, executable: URL) throws {
        guard let folder = folder(home: home, environment: environment) else { return }
        let settings = folder.appendingPathComponent("settings.json")
        try HookInstaller(configuration: settings, arguments: PermissionHooks.arguments(.codebuddy))
            .configure(enabled: false, executable: executable) { try PermissionHooks.updating($0, source: .codebuddy, command: $1) }
        try HookInstaller(configuration: settings, arguments: CompletionHooks.arguments(.codebuddy))
            .configure(enabled: false, executable: executable) { try CodeBuddyHookFormat.updating($0, command: $1) }
    }
}
