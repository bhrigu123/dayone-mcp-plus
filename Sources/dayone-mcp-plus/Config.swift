import Foundation

enum Config {
    static let label = "com.bhrigu.dayone-mcp-plus"
    static let version = "0.1.0"

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
