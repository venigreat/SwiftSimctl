import Foundation
import SimctlShared
import SQLite3
import XCTest
@testable import SimctlServerCore

final class TCCTests: XCTestCase {
    private var directory: URL!
    private var databaseURL: URL { directory.appendingPathComponent("TCC.db") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func sql(_ sql: String) throws -> [[String]] {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else { throw CommandError("test database") }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw CommandError("test query") }
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { String(cString: sqlite3_column_text(statement, $0)) })
        }
        return rows
    }

    private func createSchema() throws {
        _ = try sql("""
        CREATE TABLE access (
          service TEXT NOT NULL CHECK(service != 'broken'), client TEXT NOT NULL,
          client_type INTEGER, auth_value INTEGER, auth_reason INTEGER, auth_version INTEGER,
          PRIMARY KEY(service,client)
        )
        """)
    }

    func testBoundBundleIdentifierCannotChangeOtherRows() throws {
        try createSchema()
        let editor = TCCDbEditor(databaseURL: databaseURL)
        let bundle = "dev.test'; DELETE FROM access; --"
        try editor.manage(.grant, services: ["tracking"], bundleIdentifier: "other.app")
        try editor.manage(.grant, services: ["tracking"], bundleIdentifier: bundle)
        XCTAssertEqual(try sql("SELECT client,auth_value FROM access ORDER BY client"), [[bundle, "2"], ["other.app", "2"]])
        try editor.manage(.revoke, services: ["tracking"], bundleIdentifier: bundle)
        XCTAssertEqual(try sql("SELECT auth_value FROM access WHERE client != 'other.app'"), [["0"]])
        try editor.manage(.reset, services: ["tracking"], bundleIdentifier: bundle)
        XCTAssertEqual(try sql("SELECT client FROM access"), [["other.app"]])
    }

    func testResetWithoutBundleClearsOnlySelectedServices() throws {
        try createSchema()
        let editor = TCCDbEditor(databaseURL: databaseURL)
        for bundle in ["one", "two"] { try editor.manage(.grant, services: ["tracking", "camera"], bundleIdentifier: bundle) }
        let affected = try editor.manage(.reset, services: ["tracking"], bundleIdentifier: nil)
        XCTAssertEqual(affected, ["one", "two"])
        XCTAssertEqual(try sql("SELECT DISTINCT service FROM access"), [["camera"]])
        XCTAssertThrowsError(try editor.manage(.grant, services: ["tracking"], bundleIdentifier: nil))
    }

    func testMissingDatabaseIsFailureAndIsNotCreated() {
        XCTAssertThrowsError(try TCCDbEditor(databaseURL: databaseURL).manage(.grant, services: ["tracking"], bundleIdentifier: "dev.test"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testMultiServiceUpdateRollsBackOnFailure() throws {
        try createSchema()
        XCTAssertThrowsError(try TCCDbEditor(databaseURL: databaseURL).manage(.grant, services: ["tracking", "broken"], bundleIdentifier: "dev.test"))
        XCTAssertEqual(try sql("SELECT count(*) FROM access"), [["0"]])
    }

    func testRunnerUsesDataPathFromSelectedDeviceSet() throws {
        try runPermissionFixture(terminationStatus: 0)
    }

    func testAlreadyStoppedAppIsNotAPrivacyFailure() throws {
        try runPermissionFixture(terminationStatus: 3)
    }

    func testUnexpectedTerminationFailureIsNotIgnored() {
        XCTAssertThrowsError(try runPermissionFixture(terminationStatus: 2))
    }

    func testUnrelatedStatusThreeFailureIsNotIgnored() {
        XCTAssertThrowsError(try runPermissionFixture(terminationStatus: 3, missingApp: false))
    }

    func testFaceIDChangeDoesNotIntroduceAppTermination() throws {
        try runPermissionFixture(terminationStatus: 2, service: .faceId)
    }

    private func runPermissionFixture(terminationStatus: Int32, missingApp: Bool = true, service: PrivacyService = .userTracking) throws {
        try createSchema()
        let device = UUID()
        let dataDirectory = directory.appendingPathComponent("Selected Device/data")
        let tccDirectory = dataDirectory.appendingPathComponent("Library/TCC")
        try FileManager.default.createDirectory(at: tccDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: databaseURL, to: tccDirectory.appendingPathComponent("TCC.db"))
        let listing: [String: Any] = ["devices": ["runtime": [[
            "udid": device.uuidString, "name": "test", "isAvailable": true, "deviceTypeIdentifier": "test",
            "state": "Booted", "logPath": directory.path, "dataPath": dataDirectory.path
        ]]]]
        let listingURL = directory.appendingPathComponent("listing.json")
        try JSONSerialization.data(withJSONObject: listing).write(to: listingURL)
        let executable = directory.appendingPathComponent("xcrun-fixture")
        // All paths are generated UUID temp paths. No host simulator is accessed.
        let terminated = directory.appendingPathComponent("terminated-bundle")
        let script = """
        #!/bin/sh
        [ "$2" = '--set' ] && [ "$3" = 'testing' ] || exit 9
        if [ "$4" = list ]; then
            /bin/cat '\(listingURL.path)'
        elif [ "$4" = terminate ]; then
            printf '%s' "$6" > '\(terminated.path)'
            echo '\(missingApp ? "found nothing to terminate" : "unrelated termination error")' >&2
            exit \(terminationStatus)
        else
            exit 9
        fi
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let runner = CommandRunner(deviceSet: "testing", executable: executable.path)
        let result = try runner.execute(.simctlPrivacy(.grant, permissionsFor: service, on: device, bundleIdentifier: "dev.test"))
        XCTAssertEqual(result, "Success")
        if service == .faceId {
            XCTAssertFalse(FileManager.default.fileExists(atPath: terminated.path))
        } else {
            XCTAssertEqual(try String(contentsOf: terminated), "dev.test")
        }
        // The default database must remain untouched; only the listed device path receives a row.
        XCTAssertEqual(try sql("SELECT count(*) FROM access"), [["0"]])
        let moved = directory.appendingPathComponent("original.db")
        try FileManager.default.moveItem(at: databaseURL, to: moved)
        try FileManager.default.copyItem(at: tccDirectory.appendingPathComponent("TCC.db"), to: databaseURL)
        XCTAssertEqual(try sql("SELECT service,client,auth_value FROM access"), [[service == .faceId ? "kTCCServiceFaceID" : "kTCCServiceUserTracking", "dev.test", "2"]])
    }
}
