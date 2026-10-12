import AppKit
import ServiceManagement

/// Registration and control of the background agent, which ships inside the app bundle at
/// Contents/Library/LaunchAgents and is managed by macOS (System Settings → Login Items).
enum Service {
    static var agent: SMAppService { SMAppService.agent(plistName: Config.agentLabel + ".plist") }

    static var status: SMAppService.Status { agent.status }

    /// Never turned on. macOS reports a never-registered agent as `.notFound`, not `.notRegistered`.
    static var isOff: Bool { status == .notRegistered || status == .notFound }

    static func register() throws {
        try agent.register()
    }

    static func unregister() throws {
        try agent.unregister()
    }

    /// Restarts the agent so it picks up a new binary or a newly granted Full Disk Access.
    static func restartAgent() {
        run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(Config.agentLabel)"])
    }

    /// macOS may not apply a new Full Disk Access grant to an already-running process, so ask a
    /// fresh child process (same app identity) whether the database is readable.
    static func hasAccessInFreshProcess() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        return run(executable, ["check-access"]) == 0
    }

    /// Opens the setup window in its own process, so restarting the agent never closes it.
    static func openSetup() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["setup"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { log("couldn't open setup window: \(error.localizedDescription)") }
        }
    }

    static let fullDiskAccessSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
