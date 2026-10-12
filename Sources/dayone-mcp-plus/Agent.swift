import AppKit

/// The long-running helper, started by macOS from Contents/Library/LaunchAgents. Its privacy
/// identity is the app's, so Full Disk Access granted to the app covers it and nothing else.
enum Agent {
    static func run(unlockMinutes: Double) -> Never {
        signal(SIGPIPE, SIG_IGN)
        try? FileManager.default.createDirectory(atPath: Config.supportDir, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == Config.agentLabel {
            freopen(Config.supportDir + "/agent.log", "a", stderr)
        }

        let gate = Gate(window: unlockMinutes * 60)
        let tools = Tools(journal: Journal(db: Database(path: Config.databasePath)), gate: gate, databasePath: Config.databasePath)

        // A UI-less app (no Dock icon), so it can present Touch ID and handle reopen events.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AgentDelegate()
        app.delegate = delegate

        let listener: Int32
        do {
            listener = try Socket.listen(at: Config.socketPath)
        } catch {
            log("\(error)")
            exit(1)
        }
        log("agent \(Config.version) listening on \(Config.socketPath); unlock window \(Int(unlockMinutes)) min")

        // Re-lock whenever the Mac's screen locks.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: nil
        ) { _ in
            gate.lockNow()
            log("screen locked; journal access locked")
        }

        Thread.detachNewThread {
            while true {
                let client = accept(listener, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    log("accept failed: errno \(errno)")
                    continue
                }
                // Only processes running as this same user may connect.
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                    close(client)
                    continue
                }
                Thread.detachNewThread { MCPSession(fd: client, tools: tools).run() }
            }
        }

        switch AccessPrompt.check(Config.databasePath) {
        case .ok: log("Day One database is readable")
        case .missing: log("no Day One database at \(Config.databasePath)")
        case .noPermission: log("no Full Disk Access yet")
        }

        app.run()
        exit(0)
    }
}

private final class AgentDelegate: NSObject, NSApplicationDelegate {
    /// If macOS routes "open the app" to this running agent, show the setup window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Service.openSetup()
        return false
    }
}
