import AppKit
import ServiceManagement
import SwiftUI

/// The window people see when they open the app: turns on the background helper, checks
/// Full Disk Access, and shows how to connect an MCP client.
enum Setup {
    private static let showNotification = Notification.Name(Config.bundleID + ".showSetup")

    static func run() -> Never {
        // One setup window at a time: if another instance holds the lock, bring it forward instead.
        try? FileManager.default.createDirectory(atPath: Config.supportDir, withIntermediateDirectories: true)
        let lockFD = open(Config.supportDir + "/setup.lock", O_CREAT | O_RDWR, 0o600)
        if lockFD >= 0 && flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            DistributedNotificationCenter.default().postNotificationName(showNotification, object: nil, deliverImmediately: true)
            exit(0)
        }

        if Service.isOff {
            do {
                try Service.register()
            } catch {
                log("couldn't register the background helper: \(error.localizedDescription)")
            }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = SetupDelegate()
        app.delegate = delegate
        DistributedNotificationCenter.default().addObserver(forName: showNotification, object: nil, queue: .main) { _ in
            delegate.bringForward()
        }
        app.run()
        exit(0)
    }
}

extension Setup {
    /// Developer aid: renders the setup window to a PNG without registering anything.
    static func snapshot(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let view = NSHostingView(rootView: SetupView(model: SetupModel()))
        view.frame.size = view.fittingSize
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

private final class SetupDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Day One MCP Plus"
        window.contentView = NSHostingView(rootView: SetupView(model: SetupModel()))
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        bringForward()
    }

    func bringForward() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringForward()
        return false
    }
}

final class SetupModel: ObservableObject {
    @Published var helper: SMAppService.Status = Service.status
    @Published var hasAccess = false
    @Published var message: String?
    @Published var copied: String?
    private var timer: Timer?
    private var hadAccess: Bool?

    let executable = Bundle.main.executablePath ?? "dayone-mcp-plus"
    var claudeCommand: String { "claude mcp add dayone -s user -- \"\(executable)\" mcp" }
    var codexCommand: String { "codex mcp add dayone -- \"\(executable)\" mcp" }
    var codexTOML: String { "[mcp_servers.dayone]\ncommand = \"\(executable)\"\nargs = [\"mcp\"]" }
    var jsonConfig: String { "\"dayone\": { \"command\": \"\(executable)\", \"args\": [\"mcp\"] }" }

    /// For pasting into an AI agent so it adds the server to its own MCP config.
    var agentInstructions: String {
        """
        Add the "Day One MCP Plus" MCP server to your MCP configuration. It's a local stdio server \
        giving read-only, Touch ID–gated access to my Day One journals.

        - Name: dayone
        - Command: \(executable)
        - Arguments: mcp

        Use your usual way of adding a user-level MCP server, for example:
        - Claude Code: \(claudeCommand)
        - ChatGPT or Codex: \(codexCommand)
          If the codex command isn't available, add this to ~/.codex/config.toml instead:
          \(codexTOML.replacingOccurrences(of: "\n", with: "\n  "))
        - Others: add \(jsonConfig) under "mcpServers" in your MCP config file

        Don't change anything else. Then tell me to restart you so it loads. After the restart, call \
        its access_status tool to confirm it works (that never prompts); reading entries will ask me for Touch ID.
        """
    }

    init() {
        // Initial values are set directly (not published) so creating the model never triggers a view update.
        let access = Service.hasAccessInFreshProcess()
        _hasAccess = Published(initialValue: access)
        hadAccess = access
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let status = Service.status
        if status != helper { helper = status }
        let access = Service.hasAccessInFreshProcess()
        // Access was just granted: restart the helper so it picks it up.
        if hadAccess == false && access && status == .enabled { Service.restartAgent() }
        hadAccess = access
        if access != hasAccess { hasAccess = access }
    }

    func turnOnHelper() {
        do {
            try Service.register()
            message = nil
        } catch {
            message = "Couldn't turn on the background helper: \(error.localizedDescription)"
        }
        if Service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refresh()
    }

    func removeHelper() {
        do {
            try Service.unregister()
            message = "Background helper removed. You can now move the app to the Trash."
        } catch {
            message = "Couldn't remove the background helper: \(error.localizedDescription)"
        }
        refresh()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copied == text { self?.copied = nil }
        }
    }
}

struct SetupView: View {
    // Created by the caller, outside SwiftUI's update pass (see SetupModel.init).
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day One MCP Plus").font(.title2.bold())
                    Text("Lets AI agents read your Day One journals, with your Touch ID.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            step(1, "Background helper", done: model.helper == .enabled, detail: helperDetail) {
                switch model.helper {
                case .enabled: EmptyView()
                case .requiresApproval: Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                default: Button("Turn On") { model.turnOnHelper() }
                }
            }

            step(2, "Full Disk Access", done: model.hasAccess, detail: "Needed to read Day One's journal.") {
                if !model.hasAccess {
                    Button("Open Settings") { NSWorkspace.shared.open(Service.fullDiskAccessSettings) }
                }
            }

            step(3, "Connect your AI app", done: nil, detail: "Let your agent do it, or use a command below.") {
                Button(model.copied == model.agentInstructions ? "Copied" : "Copy Agent Instructions") {
                    model.copy(model.agentInstructions)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                copyRow("Claude Code", model.claudeCommand)
                copyRow("ChatGPT / Codex", model.codexCommand)
                copyRow("Other apps", model.jsonConfig)
            }
            .padding(.leading, 34)

            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Agents need your Touch ID first. Access stays open \(Config.unlockMinutes) min.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.helper == .enabled {
                    Button("Remove Helper…") { model.removeHelper() }
                        .controlSize(.small)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private var helperDetail: String {
        switch model.helper {
        case .enabled: return "Running."
        case .requiresApproval: return "Turned off in Login Items."
        default: return "Runs in the background so agents can connect."
        }
    }

    private func step<Accessory: View>(
        _ number: Int, _ title: String, done: Bool?, detail: String, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if done == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "\(number).circle").foregroundStyle(.secondary)
                }
            }
            .font(.title2)
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    private func copyRow(_ label: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.callout).frame(width: 118, alignment: .leading)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            Button(model.copied == text ? "Copied" : "Copy") { model.copy(text) }
                .controlSize(.small)
        }
    }
}
