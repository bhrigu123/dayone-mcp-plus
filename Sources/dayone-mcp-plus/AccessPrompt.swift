import AppKit

/// Full Disk Access can't be requested programmatically, so, like other apps that need it,
/// we explain what's needed in a dialog and deep-link to the right Settings pane.
enum AccessPrompt {
    enum State {
        case ok
        case noPermission
        case missing
    }

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    private static let lock = NSLock()
    private static var showing = false
    private static var lastShown: Date?

    /// Probes the database with a real open(2): macOS privacy checks only bite on open,
    /// and a denied attempt is also what makes the app appear in the Full Disk Access list.
    static func check(_ path: String) -> State {
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return .ok
        }
        return errno == ENOENT ? .missing : .noPermission
    }

    /// Shows the dialog unless it's already up or was shown in the last minute.
    static func showIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if showing { return }
        if let lastShown, Date().timeIntervalSince(lastShown) < 60 { return }
        showing = true
        lastShown = Date()
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Day One MCP Plus needs Full Disk Access"
            alert.informativeText = "Turn it on in Privacy & Security → Full Disk Access to let AI agents read your journals."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(settingsURL)
            }
            lock.lock(); showing = false; lock.unlock()
        }
    }
}
