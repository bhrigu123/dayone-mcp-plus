import Foundation
import SQLite3

struct DatabaseError: Error, CustomStringConvertible {
    let description: String
}

typealias Row = [String: Any]

/// Minimal read-only SQLite wrapper. All access is serialised through one lock.
final class Database {
    private var handle: OpaquePointer?
    private let path: String
    private let lock = NSLock()

    init(path: String) {
        self.path = path
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    private func openIfNeeded() throws {
        if handle != nil { return }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw DatabaseError(description: Self.accessHint(path))
        }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let db { sqlite3_close(db) }
            throw DatabaseError(description: "Could not open the Day One database (\(message)). " + Self.accessHint(path))
        }
        sqlite3_busy_timeout(db, 3000)
        handle = db
    }

    private static func accessHint(_ path: String) -> String {
        if FileManager.default.fileExists(atPath: path) || Config.databaseOverride != nil {
            return "Make sure \"Day One MCP Plus\" has Full Disk Access in System Settings → Privacy & Security, then restart it with: launchctl kickstart -k gui/\(getuid())/\(Config.label)"
        }
        return "No Day One database at \(path). Is Day One for Mac installed and opened at least once? (If Full Disk Access is missing, the file can also appear absent.)"
    }

    func query(_ sql: String, _ params: [Any?] = []) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        try openIfNeeded()

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError(description: "SQL error: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in params.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case nil: sqlite3_bind_null(statement, index)
            case let v as Int: sqlite3_bind_int64(statement, index, Int64(v))
            case let v as Int64: sqlite3_bind_int64(statement, index, v)
            case let v as Double: sqlite3_bind_double(statement, index, v)
            case let v as Bool: sqlite3_bind_int64(statement, index, v ? 1 : 0)
            case let v as String: sqlite3_bind_text(statement, index, v, -1, transient)
            default: throw DatabaseError(description: "Unsupported parameter type \(type(of: value!))")
            }
        }

        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                throw DatabaseError(description: "SQL error: \(String(cString: sqlite3_errmsg(handle)))")
            }
            var row: Row = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, column)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, column))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    if let bytes = sqlite3_column_blob(statement, column) {
                        row[name] = Data(bytes: bytes, count: count)
                    }
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }

    func tableExists(_ name: String) throws -> Bool {
        try !query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [name]).isEmpty
    }

    func columns(of table: String) throws -> [String] {
        // Table names come from sqlite_master, never from callers.
        try query("PRAGMA table_info(\"\(table)\")").compactMap { $0["name"] as? String }
    }
}
