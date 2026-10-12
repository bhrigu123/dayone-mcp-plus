import AppKit

/// The helper's menu bar icon: a closed book while journals are locked, an open book while
/// unlocked. Its menu shows the state and offers Lock Now and Open Setup. Hidden when the
/// `showMenuBarIcon` default is false (toggled from the setup window).
final class MenuBar: NSObject, NSMenuDelegate {
    static let preferenceChanged = Notification.Name(Config.bundleID + ".menuBarIconChanged")

    private let gate: Gate
    private var item: NSStatusItem?
    private var expiryTimer: Timer?

    init(gate: Gate) {
        self.gate = gate
        super.init()
        gate.onChange = { [weak self] in self?.refresh() }
        DistributedNotificationCenter.default().addObserver(
            forName: Self.preferenceChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.applyPreference() }
        applyPreference()
    }

    static var isEnabled: Bool {
        // Read straight from the preferences store: the setup window changes it from another process.
        CFPreferencesAppSynchronize(Config.bundleID as CFString)
        let value = CFPreferencesCopyAppValue("showMenuBarIcon" as CFString, Config.bundleID as CFString)
        return (value as? Bool) ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        CFPreferencesSetAppValue("showMenuBarIcon" as CFString, enabled as CFBoolean, Config.bundleID as CFString)
        CFPreferencesAppSynchronize(Config.bundleID as CFString)
        DistributedNotificationCenter.default().postNotificationName(preferenceChanged, object: nil, deliverImmediately: true)
    }

    private func applyPreference() {
        if Self.isEnabled, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
            refresh()
        } else if !Self.isEnabled, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func refresh() {
        let status = gate.status
        let symbol = status.unlocked ? "book" : "book.closed"
        let label = status.unlocked ? "Day One journals unlocked" : "Day One journals locked"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image?.isTemplate = true
        item?.button?.image = image
        item?.button?.toolTip = "Day One MCP Plus: " + (status.unlocked ? "unlocked" : "locked")

        // Flip back to the locked icon when the unlock window runs out.
        expiryTimer?.invalidate()
        if let until = status.until {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow + 0.5, repeats: false) {
                [weak self] _ in self?.refresh()
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = gate.status
        let title: String
        if let until = status.until {
            title = "Unlocked until " + until.formatted(date: .omitted, time: .shortened)
        } else {
            title = "Journals locked"
        }
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let lockItem = NSMenuItem(title: "Lock Now", action: status.unlocked ? #selector(lockNow) : nil, keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)
        let setupItem = NSMenuItem(title: "Open Setup…", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
    }

    @objc private func lockNow() {
        gate.lockNow()
    }

    @objc private func openSetup() {
        Service.openSetup()
    }
}
