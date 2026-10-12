import Foundation

/// Read-only queries over Day One's Core Data store.
///
/// Core Data conventions: tables are `Z<ENTITY>`, primary keys `Z_PK`, to-one relationships
/// are integer columns holding the other row's `Z_PK`, and timestamps are seconds since
/// 2001-01-01 UTC.
final class Journal {
    private let db: Database
    private var tagLinkCache: TagLink??

    init(db: Database) {
        self.db = db
    }

    struct Filter {
        var journal: String?
        var startDate: String?
        var endDate: String?
        var tag: String?
        var starred: Bool?
        var query: String?
        var month: Int?
        var day: Int?
        var oldestFirst = false
        var limit = 20
        var offset = 0
    }

    private static let notTrashed =
        "e.ZJOURNAL NOT IN (SELECT Z_PK FROM ZJOURNAL WHERE COALESCE(ZISTRASHJOURNAL, 0) = 1)"

    // MARK: Journals

    func listJournals() throws -> [Row] {
        let rows = try db.query("""
            SELECT j.ZNAME AS name, j.ZJOURNALDESCRIPTION AS description, j.ZHIDDEN AS hidden,
                   COUNT(e.Z_PK) AS entries, MIN(e.ZCREATIONDATE) AS first, MAX(e.ZCREATIONDATE) AS last
            FROM ZJOURNAL j LEFT JOIN ZENTRY e ON e.ZJOURNAL = j.Z_PK
            WHERE COALESCE(j.ZISTRASHJOURNAL, 0) = 0 AND COALESCE(j.ZPLACEHOLDERFORENCRYPTEDJOURNAL, 0) = 0
            GROUP BY j.Z_PK
            ORDER BY j.ZSORTORDER, j.ZNAME
            """)
        return rows.map { row in
            var out: Row = ["name": row["name"] ?? "(untitled)", "entry_count": row["entries"] ?? 0]
            if let description = row["description"] as? String, !description.isEmpty { out["description"] = description }
            if (row["hidden"] as? Int) == 1 { out["hidden"] = true }
            if let first = Self.seconds(row["first"]) { out["first_entry"] = Self.dayString(first) }
            if let last = Self.seconds(row["last"]) { out["last_entry"] = Self.dayString(last) }
            return out
        }
    }

    func listTags() throws -> [Row] {
        guard let link = try tagLink() else { return [] }
        return try db.query("""
            SELECT t.ZNAME AS name, COUNT(*) AS entry_count
            FROM ZTAG t JOIN \(link.table) jt ON jt.\(link.tagColumn) = t.Z_PK
            JOIN ZENTRY e ON e.Z_PK = jt.\(link.entryColumn)
            WHERE \(Self.notTrashed)
            GROUP BY t.Z_PK ORDER BY entry_count DESC, t.ZNAME
            """)
    }

    // MARK: Entries

    func entries(_ filter: Filter, maxChars: Int?) throws -> [Row] {
        var conditions = [Self.notTrashed]
        var params: [Any?] = []

        if let journal = filter.journal {
            conditions.append("e.ZJOURNAL IN (SELECT Z_PK FROM ZJOURNAL WHERE ZNAME = ? COLLATE NOCASE)")
            params.append(journal)
        }
        if let start = filter.startDate {
            conditions.append("e.ZCREATIONDATE >= ?")
            params.append(try Self.referenceSeconds(start, field: "start_date"))
        }
        if let end = filter.endDate {
            conditions.append("e.ZCREATIONDATE < ?")
            params.append(try Self.referenceSeconds(end, field: "end_date") + 86_400)
        }
        if let starred = filter.starred {
            conditions.append("COALESCE(e.ZSTARRED, 0) = ?")
            params.append(starred ? 1 : 0)
        }
        if let month = filter.month, let day = filter.day {
            conditions.append("e.ZGREGORIANMONTH = ? AND e.ZGREGORIANDAY = ?")
            params.append(month)
            params.append(day)
        }
        if let tag = filter.tag {
            guard let link = try tagLink() else {
                throw DatabaseError(description: "Tag filtering is unavailable: couldn't find Day One's tag table.")
            }
            conditions.append("""
                e.Z_PK IN (SELECT jt.\(link.entryColumn) FROM \(link.table) jt
                           JOIN ZTAG t ON t.Z_PK = jt.\(link.tagColumn) WHERE t.ZNAME = ? COLLATE NOCASE)
                """)
            params.append(tag)
        }
        if let query = filter.query {
            // Every whitespace-separated term must appear (case-insensitive for ASCII).
            for term in query.split(whereSeparator: \.isWhitespace) {
                conditions.append("e.ZMARKDOWNTEXT LIKE ? ESCAPE '\\'")
                params.append("%" + Self.escapeLike(String(term)) + "%")
            }
        }

        let order = filter.oldestFirst ? "ASC" : "DESC"
        params.append(filter.limit)
        params.append(filter.offset)
        let rows = try db.query("""
            SELECT e.Z_PK AS pk, e.ZUUID AS id, e.ZCREATIONDATE AS created, e.ZMODIFIEDDATE AS modified,
                   e.ZTIMEZONE AS timezone, e.ZSTARRED AS starred, e.ZISPINNED AS pinned,
                   e.ZMARKDOWNTEXT AS text, j.ZNAME AS journal
            FROM ZENTRY e LEFT JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY e.ZCREATIONDATE \(order)
            LIMIT ? OFFSET ?
            """, params)
        return try format(rows, maxChars: maxChars)
    }

    func entry(id: String) throws -> Row? {
        let rows = try db.query("""
            SELECT e.Z_PK AS pk, e.ZUUID AS id, e.ZCREATIONDATE AS created, e.ZMODIFIEDDATE AS modified,
                   e.ZTIMEZONE AS timezone, e.ZSTARRED AS starred, e.ZISPINNED AS pinned,
                   e.ZMARKDOWNTEXT AS text, j.ZNAME AS journal
            FROM ZENTRY e LEFT JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
            WHERE e.ZUUID = ? COLLATE NOCASE AND \(Self.notTrashed)
            """, [id])
        return try format(rows, maxChars: nil).first
    }

    private func format(_ rows: [Row], maxChars: Int?) throws -> [Row] {
        let tags = try tagsByEntry(rows.compactMap { $0["pk"] as? Int })
        return rows.map { row in
            let zone = (row["timezone"] as? Data).flatMap(Self.decodeTimeZone) ?? TimeZone.current
            var out: Row = ["id": row["id"] ?? "", "journal": row["journal"] ?? "(unknown)"]
            if let created = Self.seconds(row["created"]) { out["date"] = Self.isoString(created, zone) }
            if let modified = Self.seconds(row["modified"]) { out["modified"] = Self.isoString(modified, zone) }
            if (row["starred"] as? Int) == 1 { out["starred"] = true }
            if (row["pinned"] as? Int) == 1 { out["pinned"] = true }
            if let pk = row["pk"] as? Int, let entryTags = tags[pk] { out["tags"] = entryTags }

            let text = row["text"] as? String ?? ""
            if let maxChars, text.count > maxChars {
                out["text"] = String(text.prefix(maxChars))
                out["truncated"] = true
                out["full_length"] = text.count
            } else {
                out["text"] = text
            }
            return out
        }
    }

    // MARK: Tags

    private struct TagLink {
        let table: String
        let entryColumn: String
        let tagColumn: String
    }

    /// Finds the entry↔tag join table. Core Data names it `Z_<n>TAGS` with columns
    /// `Z_<entity number><relationship>`, so we map entity numbers via Z_PRIMARYKEY.
    private func tagLink() throws -> TagLink? {
        if let cached = tagLinkCache { return cached }
        var found: TagLink?
        defer { tagLinkCache = .some(found) }

        var entityNames: [Int: String] = [:]
        for row in try db.query("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY") {
            if let ent = row["Z_ENT"] as? Int, let name = row["Z_NAME"] as? String { entityNames[ent] = name }
        }
        let candidates = try db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name GLOB 'Z_[0-9]*TAGS'")
        for case let table as String in candidates.map({ $0["name"] }) {
            var entryColumn: String?, tagColumn: String?
            for column in try db.columns(of: table) {
                let digits = column.dropFirst(2).prefix(while: \.isNumber)
                guard column.hasPrefix("Z_"), let ent = Int(digits) else { continue }
                switch entityNames[ent] {
                case "Entry": entryColumn = column
                case "Tag": tagColumn = column
                default: break
                }
            }
            if let entryColumn, let tagColumn {
                found = TagLink(table: table, entryColumn: entryColumn, tagColumn: tagColumn)
                break
            }
        }
        if found == nil { log("could not locate the entry/tag join table; tags disabled") }
        return found
    }

    private func tagsByEntry(_ pks: [Int]) throws -> [Int: [String]] {
        guard !pks.isEmpty, let link = try tagLink() else { return [:] }
        let placeholders = Array(repeating: "?", count: pks.count).joined(separator: ",")
        var result: [Int: [String]] = [:]
        for row in try db.query("""
            SELECT jt.\(link.entryColumn) AS pk, t.ZNAME AS name
            FROM \(link.table) jt JOIN ZTAG t ON t.Z_PK = jt.\(link.tagColumn)
            WHERE jt.\(link.entryColumn) IN (\(placeholders))
            ORDER BY t.ZNAME
            """, pks) {
            if let pk = row["pk"] as? Int, let name = row["name"] as? String { result[pk, default: []].append(name) }
        }
        return result
    }

    // MARK: Dates

    /// SQLite stores whole-second timestamps as integers, so accept either.
    private static func seconds(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func referenceSeconds(_ day: String, field: String) throws -> Double {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else {
            throw DatabaseError(description: "\(field) must be in YYYY-MM-DD format, got \"\(day)\".")
        }
        return date.timeIntervalSinceReferenceDate
    }

    private static func isoString(_ seconds: Double, _ zone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = zone
        return formatter.string(from: Date(timeIntervalSinceReferenceDate: seconds))
    }

    private static func dayString(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSinceReferenceDate: seconds))
    }

    /// ZTIMEZONE holds a keyed-archived NSTimeZone.
    private static func decodeTimeZone(_ data: Data) -> TimeZone? {
        (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSTimeZone.self, from: data)) as TimeZone?
    }

    private static func escapeLike(_ term: String) -> String {
        term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
