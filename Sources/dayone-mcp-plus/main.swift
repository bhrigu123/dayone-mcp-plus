import Foundation
import ServiceManagement

/// `mcp`: what MCP clients launch. It pipes stdio to the agent's socket and touches no
/// journal data itself, so it needs no special permissions.
func runProxy() -> Never {
    signal(SIGPIPE, SIG_IGN)
    guard let sock = Socket.connect(to: Config.socketPath) else {
        log("can't reach the Day One MCP Plus background helper. Open the Day One MCP Plus app to set it up.")
        exit(1)
    }
    Thread.detachNewThread {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(STDIN_FILENO, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 || !Socket.writeAll(sock, Data(buffer[0..<n])) { break }
        }
        shutdown(sock, SHUT_WR)
    }
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
        let n = read(sock, &buffer, buffer.count)
        if n < 0 && errno == EINTR { continue }
        if n <= 0 || !Socket.writeAll(STDOUT_FILENO, Data(buffer[0..<n])) { break }
    }
    exit(0)
}

let usage = """
    dayone-mcp-plus \(Config.version) — read-only MCP access to Day One, gated by Touch ID

    Usage:
      dayone-mcp-plus mcp          Run as an MCP server over stdio (what MCP clients launch)
      dayone-mcp-plus setup        Open the setup window (also what opening the app does)
      dayone-mcp-plus register     Turn on the background helper, or restart it if it's on
      dayone-mcp-plus unregister   Turn off the background helper
      dayone-mcp-plus status       Show whether the helper is on and can read the journal
      dayone-mcp-plus agent        Run the background helper (started by macOS)
    """

func statusText(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled: return "on"
    case .requiresApproval: return "turned off in System Settings → General → Login Items"
    case .notRegistered, .notFound: return "off"
    @unknown default: return "unknown"
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
// Opening the app from Finder passes no arguments (or a legacy -psn_ one).
let command = arguments.first(where: { !$0.hasPrefix("-psn_") && !$0.hasPrefix("-NS") }) ?? "setup"

switch command {
case "mcp":
    runProxy()
case "setup":
    Setup.run()
case "agent":
    var minutes = Double(Config.unlockMinutes)
    if let index = arguments.firstIndex(of: "--unlock-minutes"), index + 1 < arguments.count,
       let value = Double(arguments[index + 1]), value > 0 {
        minutes = value
    }
    Agent.run(unlockMinutes: minutes)
case "register":
    if Service.status == .enabled {
        Service.restartAgent()
        print("Background helper restarted.")
    } else {
        do {
            try Service.register()
        } catch {
            print("Couldn't turn on the background helper: \(error.localizedDescription)")
            exit(1)
        }
        print("Background helper: \(statusText(Service.status))")
    }
case "unregister":
    do {
        try Service.unregister()
        print("Background helper turned off.")
    } catch {
        print("Couldn't turn off the background helper: \(error.localizedDescription)")
        exit(1)
    }
case "status":
    print("Background helper: \(statusText(Service.status))")
    print("Full Disk Access: \(Service.hasAccessInFreshProcess() ? "granted" : "not granted")")
    print("Unlock window: \(Config.unlockMinutes) min")
case "snapshot-setup":
    Setup.snapshot(to: arguments.count > 1 ? arguments[1] : "setup.png")
case "check-access":
    exit(AccessPrompt.check(Config.databasePath) == .ok ? 0 : 1)
case "--version", "version":
    print(Config.version)
case "help", "--help", "-h":
    print(usage)
default:
    print(usage)
    exit(1)
}
