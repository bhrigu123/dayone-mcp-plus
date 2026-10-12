import Foundation

/// One MCP client connection: newline-delimited JSON-RPC 2.0, as in MCP's stdio transport.
final class MCPSession {
    private let fd: Int32
    private let tools: Tools

    private static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    init(fd: Int32, tools: Tools) {
        self.fd = fd
        self.tools = tools
    }

    func run() {
        defer { close(fd) }
        var reader = LineReader(fd: fd)
        while let line = reader.next() {
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) { continue }
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            // Notifications (no id) need no reply.
            guard let id = message["id"] else { continue }
            let method = message["method"] as? String ?? ""
            let params = message["params"] as? [String: Any] ?? [:]
            if let reply = handle(method, params) {
                send(["jsonrpc": "2.0", "id": id, "result": reply])
            } else {
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
            }
        }
    }

    private func handle(_ method: String, _ params: [String: Any]) -> Any? {
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            return [
                "protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "dayone-unlocked", "version": Config.version],
                "instructions": "Read-only access to the user's Day One journals. The first read in a while asks the user to approve with Touch ID; if they decline, the tool returns an error, so don't retry in a loop.",
            ] as [String: Any]
        case "ping":
            return [String: Any]()
        case "tools/list":
            return ["tools": tools.definitions]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let result = try tools.call(name, args)
                return ["content": [["type": "text", "text": Self.json(result)]]]
            } catch let error as ToolError {
                return Self.toolError(error.message)
            } catch {
                return Self.toolError(String(describing: error))
            }
        default:
            return nil
        }
    }

    private static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return "\(value)"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        _ = Socket.writeAll(fd, data)
    }
}
