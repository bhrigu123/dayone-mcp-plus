import Foundation

enum Config {
    static let bundleID = "com.bhrigu.dayone-mcp-plus"
    /// launchd label of the background agent; its plist ships in Contents/Library/LaunchAgents.
    static let agentLabel = "com.bhrigu.dayone-mcp-plus.agent"
    static let version = "0.2.0"

    /// How long one Touch ID approval lasts. `defaults write com.bhrigu.dayone-mcp-plus unlockMinutes 60`
    static var unlockMinutes: Int {
        // Inside the app bundle the standard defaults are this domain; elsewhere (dev builds) read it by name.
        let defaults = Bundle.main.bundleIdentifier == bundleID ? .standard : UserDefaults(suiteName: bundleID)
        let value = defaults?.integer(forKey: "unlockMinutes") ?? 0
        return value > 0 ? value : 30
    }

    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    static var supportDir: String { home + "/Library/Application Support/DayOneMCPPlus" }

    /// Unix socket the background agent listens on. Overridable for tests.
    static var socketPath: String {
        ProcessInfo.processInfo.environment["DAYONE_MCP_PLUS_SOCKET"] ?? supportDir + "/agent.sock"
    }

    static let defaultDatabasePath =
        "/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite"

    /// Test-only override, pointing the agent at a fixture database.
    static var databaseOverride: String? { ProcessInfo.processInfo.environment["DAYONE_MCP_PLUS_DB"] }

    static var databasePath: String { databaseOverride ?? home + defaultDatabasePath }

    /// Skipping Touch ID is only honoured against a fixture database, never the real journal.
    static var skipAuth: Bool {
        databaseOverride != nil && ProcessInfo.processInfo.environment["DAYONE_MCP_PLUS_SKIP_AUTH"] == "1"
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("[dayone-mcp-plus] \(message)\n".utf8))
}
