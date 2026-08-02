import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Persistent catalog of shoot folders across a backlog root.
actor CatalogStore {
    static let shared = CatalogStore()

    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        openDatabase()
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    // MARK: - Meta

    func loadBrief() -> JobBrief? {
        guard let json = metaValue(for: "job_brief"),
              let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(JobBrief.self, from: data)
    }

    func saveBrief(_ brief: JobBrief) throws {
        let data = try encoder.encode(brief)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try setMeta(key: "job_brief", value: json)
    }

    func loadRootPath() -> String? {
        metaValue(for: "root_path")
    }

    func saveRootPath(_ path: String) throws {
        try setMeta(key: "root_path", value: path)
    }

    // MARK: - Folders

    func upsertFolder(_ folder: CatalogFolder) throws {
        let sql = """
        INSERT INTO folders (
            id, path, name, project_name, status, photo_count, needs_you_count,
            keep_count, set_count, queue_rank, error_message, indexed_at, cleared_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            name = excluded.name,
            project_name = excluded.project_name,
            status = excluded.status,
            photo_count = excluded.photo_count,
            needs_you_count = excluded.needs_you_count,
            keep_count = excluded.keep_count,
            set_count = excluded.set_count,
            queue_rank = excluded.queue_rank,
            error_message = excluded.error_message,
            indexed_at = excluded.indexed_at,
            cleared_at = excluded.cleared_at
        """
        try exec(sql) { stmt in
            sqlite3_bind_text(stmt, 1, folder.id.uuidString, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 2, folder.path, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 3, folder.name, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 4, folder.projectName, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 5, folder.status.rawValue, -1, sqliteTransient)
            sqlite3_bind_int(stmt, 6, Int32(folder.photoCount))
            sqlite3_bind_int(stmt, 7, Int32(folder.needsYouCount))
            sqlite3_bind_int(stmt, 8, Int32(folder.keepCount))
            sqlite3_bind_int(stmt, 9, Int32(folder.setCount))
            sqlite3_bind_int(stmt, 10, Int32(folder.queueRank))
            if let err = folder.errorMessage {
                sqlite3_bind_text(stmt, 11, err, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(stmt, 11)
            }
            self.bindOptionalDate(stmt, 12, folder.indexedAt)
            self.bindOptionalDate(stmt, 13, folder.clearedAt)
        }
    }

    func upsertFolders(_ folders: [CatalogFolder]) throws {
        for folder in folders {
            try upsertFolder(folder)
        }
    }

    func allFolders() throws -> [CatalogFolder] {
        try queryFolders(sql: "SELECT * FROM folders ORDER BY queue_rank ASC, name ASC")
    }

    func folder(id: UUID) throws -> CatalogFolder? {
        try queryFolders(sql: "SELECT * FROM folders WHERE id = ?", bind: { stmt in
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransient)
        }).first
    }

    func folder(path: String) throws -> CatalogFolder? {
        try queryFolders(sql: "SELECT * FROM folders WHERE path = ?", bind: { stmt in
            sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)
        }).first
    }

    func updateStatus(id: UUID, status: CatalogFolderStatus, error: String? = nil) throws {
        try exec("UPDATE folders SET status = ?, error_message = ? WHERE id = ?") { stmt in
            sqlite3_bind_text(stmt, 1, status.rawValue, -1, sqliteTransient)
            if let error {
                sqlite3_bind_text(stmt, 2, error, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, id.uuidString, -1, sqliteTransient)
        }
    }

    func updateStats(
        id: UUID,
        photoCount: Int,
        needsYouCount: Int,
        keepCount: Int,
        setCount: Int,
        status: CatalogFolderStatus? = nil
    ) throws {
        if let status {
            try exec("""
            UPDATE folders SET photo_count = ?, needs_you_count = ?, keep_count = ?,
            set_count = ?, status = ? WHERE id = ?
            """) { stmt in
                sqlite3_bind_int(stmt, 1, Int32(photoCount))
                sqlite3_bind_int(stmt, 2, Int32(needsYouCount))
                sqlite3_bind_int(stmt, 3, Int32(keepCount))
                sqlite3_bind_int(stmt, 4, Int32(setCount))
                sqlite3_bind_text(stmt, 5, status.rawValue, -1, sqliteTransient)
                sqlite3_bind_text(stmt, 6, id.uuidString, -1, sqliteTransient)
            }
        } else {
            try exec("""
            UPDATE folders SET photo_count = ?, needs_you_count = ?, keep_count = ?, set_count = ?
            WHERE id = ?
            """) { stmt in
                sqlite3_bind_int(stmt, 1, Int32(photoCount))
                sqlite3_bind_int(stmt, 2, Int32(needsYouCount))
                sqlite3_bind_int(stmt, 3, Int32(keepCount))
                sqlite3_bind_int(stmt, 4, Int32(setCount))
                sqlite3_bind_text(stmt, 5, id.uuidString, -1, sqliteTransient)
            }
        }
    }

    func markCleared(id: UUID) throws {
        let now = Date().timeIntervalSince1970
        try exec("UPDATE folders SET status = ?, cleared_at = ? WHERE id = ?") { stmt in
            sqlite3_bind_text(stmt, 1, CatalogFolderStatus.cleared.rawValue, -1, sqliteTransient)
            sqlite3_bind_double(stmt, 2, now)
            sqlite3_bind_text(stmt, 3, id.uuidString, -1, sqliteTransient)
        }
    }

    func execIndexedAt(id: UUID) throws {
        let now = Date().timeIntervalSince1970
        try exec("UPDATE folders SET indexed_at = ? WHERE id = ?") { stmt in
            sqlite3_bind_double(stmt, 1, now)
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, sqliteTransient)
        }
    }

    func clearAll() throws {
        try exec("DELETE FROM folders")
        try exec("DELETE FROM catalog_meta")
    }

    // MARK: - Private

    private func openDatabase() {
        guard let support = try? ProjectStore.supportDirectory() else { return }
        let url = support.appendingPathComponent("catalog.sqlite")
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            db = nil
            return
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        let ddl = """
        CREATE TABLE IF NOT EXISTS catalog_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            project_name TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            photo_count INTEGER NOT NULL DEFAULT 0,
            needs_you_count INTEGER NOT NULL DEFAULT 0,
            keep_count INTEGER NOT NULL DEFAULT 0,
            set_count INTEGER NOT NULL DEFAULT 0,
            queue_rank INTEGER NOT NULL DEFAULT 0,
            error_message TEXT,
            indexed_at REAL,
            cleared_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_folders_status ON folders(status);
        CREATE INDEX IF NOT EXISTS idx_folders_queue ON folders(queue_rank);
        """
        sqlite3_exec(db, ddl, nil, nil, nil)
    }

    private func metaValue(for key: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM catalog_meta WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    private func setMeta(key: String, value: String) throws {
        try exec("""
        INSERT INTO catalog_meta (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """) { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 2, value, -1, sqliteTransient)
        }
    }

    private func queryFolders(sql: String, bind: ((OpaquePointer?) -> Void)? = nil) throws -> [CatalogFolder] {
        guard db != nil else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CatalogStoreError.prepareFailed
        }
        bind?(stmt)
        var folders: [CatalogFolder] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            folders.append(readFolder(from: stmt))
        }
        return folders
    }

    private func readFolder(from stmt: OpaquePointer?) -> CatalogFolder {
        let idStr = String(cString: sqlite3_column_text(stmt, 0))
        let path = String(cString: sqlite3_column_text(stmt, 1))
        let name = String(cString: sqlite3_column_text(stmt, 2))
        let projectName = String(cString: sqlite3_column_text(stmt, 3))
        let statusRaw = String(cString: sqlite3_column_text(stmt, 4))
        let photoCount = Int(sqlite3_column_int(stmt, 5))
        let needsYou = Int(sqlite3_column_int(stmt, 6))
        let keepCount = Int(sqlite3_column_int(stmt, 7))
        let setCount = Int(sqlite3_column_int(stmt, 8))
        let queueRank = Int(sqlite3_column_int(stmt, 9))
        let error: String? = sqlite3_column_type(stmt, 10) == SQLITE_NULL
            ? nil
            : String(cString: sqlite3_column_text(stmt, 10))
        let indexedAt = dateColumn(stmt, 11)
        let clearedAt = dateColumn(stmt, 12)
        return CatalogFolder(
            id: UUID(uuidString: idStr) ?? UUID(),
            path: path,
            name: name,
            projectName: projectName,
            status: CatalogFolderStatus(rawValue: statusRaw) ?? .pending,
            photoCount: photoCount,
            needsYouCount: needsYou,
            keepCount: keepCount,
            setCount: setCount,
            queueRank: queueRank,
            errorMessage: error,
            indexedAt: indexedAt,
            clearedAt: clearedAt
        )
    }

    private func dateColumn(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    private func bindOptionalDate(_ stmt: OpaquePointer?, _ index: Int32, _ date: Date?) {
        if let date {
            sqlite3_bind_double(stmt, index, date.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func exec(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) throws {
        guard let db else { throw CatalogStoreError.noDatabase }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CatalogStoreError.prepareFailed
        }
        bind?(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CatalogStoreError.stepFailed
        }
    }
}

enum CatalogStoreError: Error {
    case noDatabase
    case prepareFailed
    case stepFailed
}
