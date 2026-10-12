import Foundation
import LocalAuthentication

/// Time-boxed unlock backed by Touch ID (falling back to the Mac login password).
/// One unlock is shared by every agent session until it expires or the screen locks.
final class Gate {
    private let lock = NSLock()
    private var unlockedUntil: Date?
    let window: TimeInterval

    init(window: TimeInterval) {
        self.window = window
    }

    var status: (unlocked: Bool, until: Date?) {
        lock.lock(); defer { lock.unlock() }
        if let until = unlockedUntil, until > Date() { return (true, until) }
        return (false, nil)
    }

    func lockNow() {
        lock.lock(); unlockedUntil = nil; lock.unlock()
    }

    /// Returns nil once access is granted, otherwise a message explaining why not.
    /// Holding the lock while prompting means concurrent callers share a single prompt.
    func requireUnlock() -> String? {
        if Config.skipAuth { return nil }
        lock.lock(); defer { lock.unlock() }
        if let until = unlockedUntil, until > Date() { return nil }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            return "Authentication is unavailable: \(policyError?.localizedDescription ?? "unknown error")"
        }

        let done = DispatchSemaphore(value: 0)
        var granted = false
        var failure: Error?
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "give AI agents access to your journals"
        ) { success, error in
            granted = success
            failure = error
            done.signal()
        }
        if done.wait(timeout: .now() + 120) == .timedOut {
            context.invalidate()
            return "Timed out waiting for Touch ID approval."
        }
        guard granted else {
            return "Journal access was not approved (\(failure?.localizedDescription ?? "cancelled"))."
        }
        unlockedUntil = Date().addingTimeInterval(window)
        log("unlocked until \(unlockedUntil!)")
        return nil
    }
}
