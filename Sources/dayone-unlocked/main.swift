import Foundation

/// `mcp`: what MCP clients launch. It pipes stdio to the agent's socket and touches no
/// journal data itself, so it needs no special permissions.
func runProxy() -> Never {
    signal(SIGPIPE, SIG_IGN)
    guard let sock = Socket.connect(to: Config.socketPath) else {
        log("can't reach the DayOne Unlocked agent at \(Config.socketPath). Run scripts/install.sh, or check: launchctl print gui/\(getuid())/\(Config.label)")
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
    dayone-unlocked \(Config.version) — read-only MCP access to Day One, gated by Touch ID

    Usage:
      dayone-unlocked mcp                         Run as an MCP server over stdio (what MCP clients launch)
      dayone-unlocked agent [--unlock-minutes N]  Run the background agent (started by launchd)
    """

var arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "mcp":
    runProxy()
case "agent":
    var minutes = 30.0
    if let index = arguments.firstIndex(of: "--unlock-minutes"), index + 1 < arguments.count,
       let value = Double(arguments[index + 1]), value > 0 {
        minutes = value
    }
    Agent.run(unlockMinutes: minutes)
case "--version", "version":
    print(Config.version)
default:
    print(usage)
    exit(arguments.isEmpty || arguments.first == "help" || arguments.first == "--help" ? 0 : 1)
}
