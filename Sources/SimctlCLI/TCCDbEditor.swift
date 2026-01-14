//
//  TCCDbEditor.swift
//  SwiftSimctl
//
//  Created by dsmirnovigore on 13.01.2026.
//
import Foundation
import SQLite3
import SimctlShared

public class TCCDbEditor {
    let permissions = ["kTCCServiceUserTracking", "kTCCServiceFaceID"]
    
    public func execute(device: UUID, sql: String) -> String  {
        let dbPath = "~/Library/Developer/CoreSimulator/Devices/\(device.uuidString)/data/Library/TCC/TCC.db"

        let expandedDBPath = (dbPath as NSString).expandingTildeInPath

        if !FileManager.default.fileExists(atPath: expandedDBPath) {
            return "TCCPermissionManager: TCC.db not found at \(expandedDBPath)"
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(expandedDBPath, &db, flags, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            return "TCCPermissionManager: failed to open TCC.db. SQLite error: \(errorMessage)"
        }

        defer { sqlite3_close(db) }
        print("TCC database opened successfully!")
        
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            return "TCCPermissionManager SQLite error: \(error)"
        }
        
        return "Success"
    }
     
    private func getSql(_ action: PrivacyAction, needService: String, bundleIdentifier: String) -> String {
        let sql: String
        switch action {
            case .grant:
                sql = """
                REPLACE INTO access
                (service,
                client,
                client_type,
                auth_value,
                auth_reason,
                auth_version)
                VALUES
                ('\(needService)', '\(bundleIdentifier)', 0,
                2,
                2,
                1);
                """

            case .revoke:
                sql = """
                REPLACE INTO access
                (service,
                client,
                client_type,
                auth_value,
                auth_reason,
                auth_version)
                VALUES
                ('\(needService)', '\(bundleIdentifier)', 0,
                0,
                2,
                1);
                """

            case .reset:
                sql = """
                DELETE FROM access
                WHERE service = '\(needService)'
                AND client = '\(bundleIdentifier)';
                """
            }
        return sql
    }
    
    public func manage(_ action: PrivacyAction, permissionsFor service: PrivacyService, bundleIdentifier: String, device: UUID) -> String {
        let needService: String
        
        switch service {
            case .userTracking: needService = "kTCCServiceUserTracking"
            case .faceId: needService = "kTCCServiceFaceID"
            default: needService = "kTCCServiceUserTracking"
        }
        

        let sql = getSql(action, needService: needService, bundleIdentifier: bundleIdentifier)

        return execute(device: device, sql: sql)
    }
    
    public func all(_ action: PrivacyAction, bundleIdentifier: String, device: UUID) -> String {
        var results: [String] = []
        
        permissions.forEach { needService in
            switch action {
                case .grant:
                    sql = """
                        REPLACE INTO access
                        (service,
                        client,
                        client_type,
                        auth_value,
                        auth_reason,
                        auth_version)
                        VALUES
                        ('\(needService)', '\(bundleIdentifier)', 0,
                        2,
                        2,
                        1);
                        """
                    
                case .revoke:
                    sql = """
                        REPLACE INTO access
                        (service,
                        client,
                        client_type,
                        auth_value,
                        auth_reason,
                        auth_version)
                        VALUES
                        ('\(needService)', '\(bundleIdentifier)', 0,
                        0,
                        2,
                        1);
                        """
                    
                case .reset:
                    sql = """
                        DELETE FROM access
                        WHERE service = '\(needService)'
                        AND client = '\(bundleIdentifier)';
                        """
            }
            let sql = getSql(action, needService: needService, bundleIdentifier: bundleIdentifier)
            results.append(execute(device: device, sql: sql))
        }
        return results.joined(separator: ",")
    }
}
