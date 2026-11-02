import Foundation
import SQLite3
import SimctlShared

/// Updates simulator-only TCC permissions using bound SQL parameters.
final class TCCDbEditor {
    let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    @discardableResult
    func manage(_ action: PrivacyAction, services: [String], bundleIdentifier: String?) throws -> [String] {
        guard action == .reset || !(bundleIdentifier ?? "").isEmpty else {
            throw CommandError("Bundle Id is required for grant and revoke.")
        }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CommandError("TCC.db not found at \(databaseURL.path)")
        }
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        defer { sqlite3_close(connection) }
        guard status == SQLITE_OK, let database = connection else {
            throw CommandError("Unable to open TCC.db: \(message(connection))")
        }
        sqlite3_busy_timeout(database, 5_000)
        try execute("BEGIN IMMEDIATE", database: database)
        do {
            let affected = try bundleIdentifier.map { [$0] } ?? clients(services: services, database: database)
            for service in services {
                try update(action, service: service, bundleIdentifier: bundleIdentifier, database: database)
            }
            try execute("COMMIT", database: database)
            return affected
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }
    }

    private func clients(services: [String], database: OpaquePointer) throws -> [String] {
        var clients = Set<String>()
        for service in services {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT DISTINCT client FROM access WHERE service = ? AND client_type = 0", -1, &statement, nil) == SQLITE_OK else {
                throw CommandError("TCC SQLite error: \(message(database))")
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(statement, 1, service, -1, transient) == SQLITE_OK else {
                throw CommandError("TCC SQLite bind error: \(message(database))")
            }
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                if let value = sqlite3_column_text(statement, 0) { clients.insert(String(cString: value)) }
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw CommandError("TCC SQLite error: \(message(database))") }
        }
        return clients.sorted()
    }

    private func update(_ action: PrivacyAction, service: String, bundleIdentifier: String?, database: OpaquePointer) throws {
        let sql: String
        if action == .reset {
            sql = "DELETE FROM access WHERE service = ? AND client_type = 0" + (bundleIdentifier == nil ? "" : " AND client = ?")
        } else {
            sql = """
            REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version)
            VALUES (?, ?, 0, ?, 2, 1)
            """
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CommandError("TCC SQLite error: \(message(database))")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, service, -1, transient) == SQLITE_OK else {
            throw CommandError("TCC SQLite bind error: \(message(database))")
        }
        if let bundleIdentifier = bundleIdentifier {
            guard sqlite3_bind_text(statement, 2, bundleIdentifier, -1, transient) == SQLITE_OK else {
                throw CommandError("TCC SQLite bind error: \(message(database))")
            }
        }
        if action != .reset {
            guard sqlite3_bind_int(statement, 3, action == .grant ? 2 : 0) == SQLITE_OK else {
                throw CommandError("TCC SQLite bind error: \(message(database))")
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CommandError("TCC SQLite error: \(message(database))")
        }
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw CommandError("TCC SQLite error: \(message(database))")
        }
    }

    private func message(_ database: OpaquePointer?) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}
