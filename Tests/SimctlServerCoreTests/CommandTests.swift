import Foundation
import SimctlShared
import XCTest
@testable import SimctlServerCore

final class CommandTests: XCTestCase {
    private let device = UUID()

    private func runArguments(_ command: SimctlCommand) throws -> ([String], Data?) {
        guard case let .run(arguments, input) = command.action else {
            throw CommandError("Expected process command")
        }
        return (arguments, input)
    }

    func testPushPreservesJSONBytesIncludingApostrophesAndNewlines() throws {
        let data = Data("{\n\"aps\":{\"alert\":\"It's an audit\"}}".utf8)
        let (arguments, input) = try runArguments(.simctlPush(to: device, pushContent: .jsonPayload(data), bundleIdentifier: "dev.test"))
        XCTAssertEqual(arguments, ["push", device.uuidString, "dev.test", "-"])
        XCTAssertEqual(input, data)
    }

    func testNamesPathsAndOperatorNamesAreSingleArguments() throws {
        let name = "Audit ' Device $(touch /tmp/should-not-exist)"
        XCTAssertEqual(try runArguments(.simctlRename(device: device, to: name)).0.last, name)
        let path = "/tmp/App With Spaces.app"
        XCTAssertEqual(try runArguments(.simctlInstallApp(device: device, path: path)).0.last, path)
        XCTAssertEqual(try runArguments(.simctlPush(to: device, pushContent: .file(URL(fileURLWithPath: path)))).0.last, path)
        let arguments = try runArguments(.simctlSetStatusBarOverrides(device: device, overrides: [.operatorName("Audit Carrier")])).0
        XCTAssertEqual(Array(arguments.suffix(2)), ["--operatorName", "Audit Carrier"])
    }

    func testActualProcessNeverEvaluatesShellMetacharacters() throws {
        let value = "a b ' \" $HOME $(echo injected); echo nope"
        let task = try ProcessTask(executable: "/usr/bin/printf", arguments: ["%s", value])
        try task.start()
        XCTAssertTrue(task.wait(timeout: 3))
        XCTAssertEqual(try task.checkedOutput(), value)
    }

    func testActualProcessPreservesStdinBytes() throws {
        let data = Data("{\n\"text\":\"It's a payload\"\n}".utf8)
        let task = try ProcessTask(executable: "/bin/cat", arguments: [], input: data)
        try task.start()
        XCTAssertTrue(task.wait(timeout: 3))
        XCTAssertEqual(task.output, String(decoding: data, as: UTF8.self))
    }

    func testProcessFailureRetainsExitCodeAndStderr() throws {
        let task = try ProcessTask(executable: "/bin/ls", arguments: ["/this-path-does-not-exist-swiftsimctl"])
        try task.start()
        XCTAssertTrue(task.wait(timeout: 3))
        XCTAssertThrowsError(try task.checkedOutput()) { error in
            XCTAssertEqual((error as? ProcessFailure)?.status, 1)
            XCTAssertTrue(error.localizedDescription.contains("status 1"))
            XCTAssertTrue(error.localizedDescription.contains("No such file"))
        }
    }

    func testTimedOutProcessCanBeCancelled() throws {
        let task = try ProcessTask(executable: "/bin/sleep", arguments: ["5"])
        try task.start()
        XCTAssertFalse(task.wait(timeout: 0.01))
        task.cancel()
        XCTAssertFalse(task.process.isRunning)
    }

    func testDeviceSetIsPassedAsSeparateArguments() {
        let runner = CommandRunner(deviceSet: "/tmp/Device Set With Spaces")
        XCTAssertEqual(runner.arguments(["list", "devices"]), ["simctl", "--set", "/tmp/Device Set With Spaces", "list", "devices"])
    }

    func testInvalidRecordingDirectoryFailsBeforeLaunchingProcess() {
        let runner = CommandRunner()
        XCTAssertThrowsError(try runner.execute(.simctlStartRecordVideo(device: device, path: "/does-not-exist-swiftsimctl/audit.mp4")))
    }

    func testStoppingUnknownDeviceDoesNotKillAnyProcess() throws {
        XCTAssertTrue(try CommandRunner().execute(.stopRecording(device: device)).contains("No recording"))
    }
}
