import Foundation
import XCTest
@testable import SimctlServerCore

final class RecordingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func runner(script: String) throws -> CommandRunner {
        let executable = directory.appendingPathComponent(UUID().uuidString)
        try ("#!/bin/sh\n" + script).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return CommandRunner(executable: executable.path)
    }

    func testEarlyRecordingFailureIsNotSuccess() throws {
        let runner = try self.runner(script: "echo 'cannot start recording' >&2\nexit 7\n")
        XCTAssertThrowsError(try runner.execute(.simctlStartRecordVideo(device: UUID(), path: directory.appendingPathComponent("audit.mp4").path))) { error in
            XCTAssertTrue(error.localizedDescription.contains("cannot start recording"))
        }
    }

    func testStoppingOneRecordingDoesNotStopAnother() throws {
        let script = """
        trap 'exit 0' INT TERM
        printf '%s' "$5" > "$5"
        echo 'Recording started' >&2
        while :; do /bin/sleep 0.1; done
        """
        let first = try runner(script: script)
        let second = try runner(script: script)
        let device = UUID()
        let firstPath = directory.appendingPathComponent("video with spaces.mp4").path
        let secondPath = directory.appendingPathComponent("other.mp4").path
        XCTAssertEqual(try first.execute(.simctlStartRecordVideo(device: device, path: firstPath)), "Recording started")
        XCTAssertEqual(try second.execute(.simctlStartRecordVideo(device: device, path: secondPath)), "Recording started")
        XCTAssertEqual(try String(contentsOfFile: firstPath), firstPath)
        XCTAssertEqual(try first.execute(.stopRecording(device: device)), "Recording stopped")
        // A still-running second recording rejects another start; a global pkill would break this assertion.
        XCTAssertThrowsError(try second.execute(.simctlStartRecordVideo(device: device, path: directory.appendingPathComponent("third.mp4").path))) { error in
            XCTAssertTrue(error.localizedDescription.contains("already running"))
        }
        XCTAssertEqual(try second.execute(.stopRecording(device: device)), "Recording stopped")
    }
}
