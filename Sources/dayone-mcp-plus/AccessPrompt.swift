import Foundation

/// Full Disk Access can't be requested programmatically, so, like other apps that need it,
/// we open our setup window, which explains it and links to the right Settings pane.
enum AccessPrompt {
    enum State {
        case ok
        case noPermission
        case missing
    }

    private static let lock = NSLock()
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

    /// Opens the setup window, at most once a minute.
    static func showIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if let lastShown, Date().timeIntervalSince(lastShown) < 60 { return }
        lastShown = Date()
        DispatchQueue.main.async { Service.openSetup() }
    }
}
