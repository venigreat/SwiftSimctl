import Darwin
import Foundation

struct CommandError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

struct ProcessFailure: LocalizedError {
    let status: Int32
    let output: String
    let errors: String

    var errorDescription: String? { "Command exited with status \(status): \(errors)\n\(output)" }
}

/// File-backed IO avoids pipe deadlocks and preserves stdin bytes without shell interpolation.
final class ProcessTask {
    let process = Process()
    private let directory: URL
    private let outputURL: URL
    private let errorURL: URL
    private var handles: [FileHandle] = []
    private let terminated = DispatchSemaphore(value: 0)

    init(executable: String, arguments: [String], input: Data? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        outputURL = directory.appendingPathComponent("stdout")
        errorURL = directory.appendingPathComponent("stderr")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            for url in [outputURL, errorURL] {
                try Data().write(to: url)
            }
            let output = try FileHandle(forWritingTo: outputURL)
            handles.append(output)
            let errors = try FileHandle(forWritingTo: errorURL)
            handles.append(errors)
            process.standardOutput = output
            process.standardError = errors
            process.launchPath = executable
            process.arguments = arguments
            if let input = input {
                let inputURL = directory.appendingPathComponent("stdin")
                try input.write(to: inputURL)
                let handle = try FileHandle(forReadingFrom: inputURL)
                handles.append(handle)
                process.standardInput = handle
            } else {
                process.standardInput = FileHandle.nullDevice
            }
            process.terminationHandler = { [terminated] _ in terminated.signal() }
        } catch {
            handles.forEach { $0.closeFile() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        cancel()
        handles.forEach { $0.closeFile() }
        try? FileManager.default.removeItem(at: directory)
    }

    func start() throws {
        if #available(macOS 10.13, *) {
            try process.run()
        } else {
            process.launch()
        }
    }

    func wait(timeout: TimeInterval) -> Bool {
        if !process.isRunning { return true }
        return terminated.wait(timeout: .now() + timeout) == .success
    }

    func cancel() {
        guard process.isRunning else { return }
        process.terminate()
        if !wait(timeout: 1) {
            Darwin.kill(process.processIdentifier, SIGKILL)
            _ = wait(timeout: 1)
        }
    }

    var output: String { read(outputURL) }
    var errors: String { read(errorURL) }

    func checkedOutput() throws -> String {
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ProcessFailure(status: process.terminationStatus, output: output, errors: errors)
        }
        return output.trimmingCharacters(in: .newlines)
    }

    private func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
