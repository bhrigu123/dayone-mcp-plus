import Foundation

struct ToolError: Error {
    let message: String
}

/// MCP tool definitions and their handlers.
final class Tools {
    private let journal: Journal
    private let gate: Gate
    private let databasePath: String

    init(journal: Journal, gate: Gate, databasePath: String) {
        self.journal = journal
        self.gate = gate
        self.databasePath = databasePath
    }

    private static let filterProperties: [String: Any] = [
        "journal": ["type": "string", "description": "Only entries from this journal (name, case-insensitive)."],
        "start_date": ["type": "string", "description": "Earliest entry date, YYYY-MM-DD (inclusive)."],
        "end_date": ["type": "string", "description": "Latest entry date, YYYY-MM-DD (inclusive)."],
        "tag": ["type": "string", "description": "Only entries with this tag."],
        "starred": ["type": "boolean", "description": "Only starred (true) or unstarred (false) entries."],
        "order": ["type": "string", "enum": ["newest", "oldest"], "description": "Sort order. Default newest."],
        "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Max entries to return. Default 20."],
        "offset": ["type": "integer", "minimum": 0, "description": "Entries to skip, for paging."],
        "max_chars": [
            "type": "integer", "minimum": 0,
            "description": "Truncate each entry's text to this many characters (default 4000, 0 = no limit). Use get_entry for the full text.",
        ],
    ]

    var definitions: [[String: Any]] {
        [
            [
                "name": "list_journals",
                "description": "List the Day One journals with entry counts and date ranges.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
                "annotations": ["readOnlyHint": true],
            ],
            [
                "name": "list_tags",
                "description": "List tags used in Day One entries, with how many entries use each.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
                "annotations": ["readOnlyHint": true],
            ],
            [
                "name": "get_entries",
                "description": "Get Day One entries, newest first, optionally filtered by journal, date range, tag or starred.",
                "inputSchema": ["type": "object", "properties": Self.filterProperties],
                "annotations": ["readOnlyHint": true],
            ],
            [
                "name": "search_entries",
                "description": "Full-text search of Day One entries. Every word in the query must appear in the entry. Accepts the same filters as get_entries.",
                "inputSchema": [
                    "type": "object",
                    "properties": Self.filterProperties.merging(
                        ["query": ["type": "string", "description": "Words to search for."]]) { a, _ in a },
                    "required": ["query"],
                ],
                "annotations": ["readOnlyHint": true],
            ],
            [
                "name": "get_entry",
                "description": "Get one Day One entry with its full text, by the id returned from other tools.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["id": ["type": "string", "description": "Entry id."]],
                    "required": ["id"],
                ],
                "annotations": ["readOnlyHint": true],
            ],
            [
                "name": "on_this_day",
                "description": "Entries written on a given calendar day across all years (default: today).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "date": ["type": "string", "description": "A date (YYYY-MM-DD or MM-DD) whose month and day to use. Default today."],
                        "journal": Self.filterProperties["journal"]!,
                        "limit": Self.filterProperties["limit"]!,
                        "max_chars": Self.filterProperties["max_chars"]!,
                    ],
                ],
                "annotations": ["readOnlyHint": true],
            ],
            [
                "name": "access_status",
                "description": "Whether journal access is currently unlocked, and until when. Never prompts.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
                "annotations": ["readOnlyHint": true],
            ],
            [
                "name": "lock_journals",
                "description": "Lock journal access now. The next read will ask the user for Touch ID again.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
            ],
        ]
    }

    func call(_ name: String, _ args: [String: Any]) throws -> Any {
        switch name {
        case "access_status":
            let status = gate.status
            var out: Row = ["unlocked": status.unlocked, "unlock_window_minutes": Int(gate.window / 60)]
            if let until = status.until { out["unlocked_until"] = ISO8601DateFormatter().string(from: until) }
            return out
        case "lock_journals":
            gate.lockNow()
            return ["locked": true]
        default:
            break
        }

        guard definitions.contains(where: { $0["name"] as? String == name }) else {
            throw ToolError(message: "Unknown tool: \(name)")
        }
        // Check access first, so nobody approves Touch ID only to hit a permissions error.
        switch AccessPrompt.check(databasePath) {
        case .ok:
            break
        case .noPermission:
            AccessPrompt.showIfNeeded()
            throw ToolError(message: "DayOne Unlocked doesn't have Full Disk Access yet, so it can't read the journal. A dialog on the user's Mac explains how to grant it (System Settings → Privacy & Security → Full Disk Access). Ask the user to do that, then try again.")
        case .missing:
            throw ToolError(message: "No Day One database found at \(databasePath). Is Day One for Mac installed and opened at least once?")
        }
        if let denied = gate.requireUnlock() {
            throw ToolError(message: denied)
        }

        switch name {
        case "list_journals":
            return ["journals": try journal.listJournals()]
        case "list_tags":
            return ["tags": try journal.listTags()]
        case "get_entries":
            return try entries(filter(args), args)
        case "search_entries":
            guard let query = string(args, "query"), !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ToolError(message: "query is required.")
            }
            var f = try filter(args)
            f.query = query
            return try entries(f, args)
        case "get_entry":
            guard let id = string(args, "id") else { throw ToolError(message: "id is required.") }
            guard let entry = try journal.entry(id: id) else { throw ToolError(message: "No entry with id \(id).") }
            return entry
        case "on_this_day":
            var f = try filter(args)
            (f.month, f.day) = try monthDay(string(args, "date"))
            return try entries(f, args)
        default:
            throw ToolError(message: "Unknown tool: \(name)")
        }
    }

    private func entries(_ filter: Journal.Filter, _ args: [String: Any]) throws -> Any {
        let maxChars = int(args, "max_chars") ?? 4000
        let rows = try journal.entries(filter, maxChars: maxChars > 0 ? maxChars : nil)
        var out: Row = ["count": rows.count, "entries": rows]
        if rows.count == filter.limit { out["next_offset"] = filter.offset + filter.limit }
        return out
    }

    private func filter(_ args: [String: Any]) throws -> Journal.Filter {
        var f = Journal.Filter()
        f.journal = string(args, "journal")
        f.startDate = string(args, "start_date")
        f.endDate = string(args, "end_date")
        f.tag = string(args, "tag")
        f.starred = args["starred"] as? Bool
        f.oldestFirst = string(args, "order") == "oldest"
        f.limit = min(max(int(args, "limit") ?? 20, 1), 100)
        f.offset = max(int(args, "offset") ?? 0, 0)
        return f
    }

    private func monthDay(_ value: String?) throws -> (Int, Int) {
        guard let value else {
            let today = Calendar.current.dateComponents([.month, .day], from: Date())
            return (today.month!, today.day!)
        }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        let (month, day) = parts.count == 3 ? (parts[1], parts[2]) : parts.count == 2 ? (parts[0], parts[1]) : (0, 0)
        guard (1...12).contains(month), (1...31).contains(day) else {
            throw ToolError(message: "date must be YYYY-MM-DD or MM-DD, got \"\(value)\".")
        }
        return (month, day)
    }

    private func string(_ args: [String: Any], _ key: String) -> String? {
        guard let value = args[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private func int(_ args: [String: Any], _ key: String) -> Int? {
        if let value = args[key] as? Int { return value }
        if let value = args[key] as? Double { return Int(value) }
        if let value = args[key] as? String { return Int(value) }
        return nil
    }
}
