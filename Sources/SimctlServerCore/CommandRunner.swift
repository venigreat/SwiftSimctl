import Foundation
import SimctlShared

/// Executes simulator commands and owns the recordings it starts.
public final class CommandRunner {
    let deviceSet: String?
    private let timeout: TimeInterval
    private let executable: String
    private let recordingLock = NSLock()
    private var recordings: [UUID: ProcessTask] = [:]

    public convenience init(deviceSet: String? = nil, timeout: TimeInterval = 30) {
        self.init(deviceSet: deviceSet, timeout: timeout, executable: "/usr/bin/xcrun")
    }

    init(deviceSet: String? = nil, timeout: TimeInterval = 30, executable: String) {
        self.deviceSet = deviceSet
        self.timeout = timeout
        self.executable = executable
    }

    deinit { stopAllRecordings() }

    public func execute(_ command: SimctlCommand) throws -> String {
        switch command.action {
        case let .run(arguments, input):
            return try run(arguments, input: input)
        case let .sequence(commands):
            return try commands.map { try run($0) }.joined(separator: "\n")
        case let .privacy(action, service, device, bundleIdentifier):
            return try privacy(action, service: service, device: device, bundleIdentifier: bundleIdentifier)
        case let .record(device, path):
            return try startRecording(device: device, path: path)
        case let .stopRecording(device):
            recordingLock.lock()
            defer { recordingLock.unlock() }
            return try stopRecording(device: device)
        }
    }

    /// Stops only processes owned by this runner, including on server shutdown.
    public func stopAllRecordings() {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        for device in Array(recordings.keys) {
            if (try? stopRecording(device: device)) == nil {
                recordings[device]?.cancel()
                recordings.removeValue(forKey: device)
            }
        }
    }

    func arguments(_ arguments: [String]) -> [String] {
        ["simctl"] + (deviceSet.map { ["--set", $0] } ?? []) + arguments
    }

    private func run(_ arguments: [String], input: Data? = nil) throws -> String {
        let task = try ProcessTask(executable: executable, arguments: self.arguments(arguments), input: input)
        try task.start()
        guard task.wait(timeout: timeout) else {
            task.cancel()
            throw CommandError("Command timed out after \(timeout) seconds. \(task.errors)")
        }
        return try task.checkedOutput()
    }

    private func privacy(_ action: PrivacyAction, service: PrivacyService, device: UUID, bundleIdentifier: String?) throws -> String {
        guard action == .reset || !(bundleIdentifier ?? "").isEmpty else {
            throw CommandError("Bundle Id is required for grant and revoke.")
        }
        var output = ""
        if ![.userTracking, .faceId].contains(service) {
            let args = ["privacy", device.uuidString, action.rawValue, service.rawValue] + (bundleIdentifier.map { [$0] } ?? [])
            output = try run(args)
        }
        if [.all, .userTracking, .faceId].contains(service) {
            // Resolve the actual data path through the same device set as every other command.
            let data = Data(try run(["list", "devices", device.uuidString, "--json"]).utf8)
            let listing = try JSONDecoder().decode(SimulatorDeviceListing.self, from: data)
            guard let simulator = listing.devices.first(where: { $0.udid == device }) else {
                throw CommandError("Simulator \(device) not found in the selected device set.")
            }
            let services = service == .all ? ["kTCCServiceUserTracking", "kTCCServiceFaceID"] :
                [service == .faceId ? "kTCCServiceFaceID" : "kTCCServiceUserTracking"]
            let databaseURL = simulator.dataPath.appendingPathComponent("Library/TCC/TCC.db")
            let affected = try TCCDbEditor(databaseURL: databaseURL).manage(action, services: services, bundleIdentifier: bundleIdentifier)
            // ATT caches its status in the app process. Native privacy changes can also terminate apps.
            // Leave relaunching to the test; never restart another app or the simulator's privacy daemon.
            if service != .faceId {
                for bundle in affected {
                    do {
                        _ = try run(["terminate", device.uuidString, bundle])
                    } catch let failure as ProcessFailure where failure.status == 3 && failure.errors.contains("found nothing to terminate") {
                        // An installed app may already be stopped, including by native `privacy all`.
                    }
                }
            }
            return output.isEmpty ? "Success" : output
        }
        return output
    }

    private func startRecording(device: UUID, path: String) throws -> String {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        if let current = recordings[device], current.process.isRunning {
            throw CommandError("A recording is already running for \(device).")
        }
        recordings.removeValue(forKey: device)
        guard path.hasPrefix("/") else { throw CommandError("Recording path must be absolute.") }
        let url = URL(fileURLWithPath: path)
        var directory: ObjCBool = false
        let parent = url.deletingLastPathComponent().path
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &directory), directory.boolValue,
              FileManager.default.isWritableFile(atPath: parent) else {
            throw CommandError("Recording directory does not exist or is not writable: \(parent)")
        }
        guard !FileManager.default.fileExists(atPath: path) else {
            throw CommandError("Recording output already exists: \(path)")
        }
        let task = try ProcessTask(executable: executable, arguments: arguments(["io", device.uuidString, "recordVideo", path]))
        try task.start()
        let deadline = Date().addingTimeInterval(min(timeout, 10))
        while Date() < deadline {
            if !task.process.isRunning {
                _ = try task.checkedOutput()
                throw CommandError("Recording stopped before it was ready. \(task.errors)")
            }
            if task.errors.contains("Recording started") && FileManager.default.fileExists(atPath: path) {
                recordings[device] = task
                return "Recording started"
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        task.cancel()
        throw CommandError("Recording did not become ready. \(task.errors)")
    }

    private func stopRecording(device: UUID) throws -> String {
        guard let task = recordings[device] else { return "No recording for \(device)." }
        if task.process.isRunning { task.process.interrupt() }
        guard task.wait(timeout: 10) else {
            throw CommandError("Recording did not stop for \(device).")
        }
        defer { recordings.removeValue(forKey: device) }
        _ = try task.checkedOutput()
        return "Recording stopped"
    }
}
