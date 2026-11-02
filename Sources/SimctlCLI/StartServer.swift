//
//  StartServer.swift
//
//
//  Created by Christian Treffs on 18.03.20.
//

import ArgumentParser
import Darwin
import Foundation
import SimctlServerCore
import SimctlShared

struct StartServer: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Start the server that will be called by your test code to run the commands")

    @Option(name: .shortAndLong, help: "The port to listen on")
    var port: SimctlShared.Port = Port(8080)

    @Flag(name: .shortAndLong, help: "Show command results and errors")
    var verbose = false
    
    @Flag(name: .shortAndLong, help: "Start with or without clones of simulators")
    var testing = false

    mutating func run() throws {
        let server = SimctlServer()
        let v = verbose
        let runner = CommandRunner(deviceSet: testing ? "testing" : nil)
        func runCommand(_ command: SimctlCommand, verbose: Bool = false) -> Result<String, Swift.Error> {
            let result = Result { try runner.execute(command) }
            if verbose {
                switch result {
                case let .success(output): print("Success: \(output)")
                case let .failure(error): print("Failure: \(error.localizedDescription)")
                }
            }
            return result
        }

        server.onPushNotification { deviceId, bundleId, pushContent -> Result<String, Swift.Error> in
            runCommand(.simctlPush(to: deviceId, pushContent: pushContent, bundleIdentifier: bundleId), verbose: v)
        }

        server.onPrivacy { deviceId, bundleId, action, service -> Result<String, Swift.Error> in
            runCommand(.simctlPrivacy(action, permissionsFor: service, on: deviceId, bundleIdentifier: bundleId), verbose: v)
        }

        server.onRename { deviceId, _, newName -> Result<String, Swift.Error> in
            runCommand(.simctlRename(device: deviceId, to: newName), verbose: v)
        }

        server.onTerminateApp { deviceId, _, appBundleId -> Result<String, Swift.Error> in
            runCommand(.simctlTerminateApp(device: deviceId, appBundleIdentifier: appBundleId), verbose: v)
        }

        server.onErase { deviceId -> Result<String, Swift.Error> in
            runCommand(.simctlErase(device: deviceId), verbose: v)
        }

        server.onSetDeviceAppearance { deviceId, _, appearance -> Result<String, Swift.Error> in
            runCommand(.simctlSetUI(appearance: appearance, on: deviceId), verbose: v)
        }

        server.onTriggerICloudSync { deviceId, _ -> Result<String, Swift.Error> in
            runCommand(.simctlTriggerICloudSync(device: deviceId), verbose: v)
        }
        
        server.onInstallApp { deviceId, _, path -> Result<String, Swift.Error> in
            runCommand(.simctlInstallApp(device: deviceId, path: path), verbose: v)
        }

        server.onUninstallApp { deviceId, _, appBundleId -> Result<String, Swift.Error> in
            runCommand(.simctlUninstallApp(device: deviceId, appBundleIdentifier: appBundleId), verbose: v)
        }

        server.onSetStatusBarOverride { deviceId, _, overrides -> Result<String, Swift.Error> in
            runCommand(.simctlSetStatusBarOverrides(device: deviceId, overrides: overrides), verbose: v)
        }

        server.onClearStatusBarOverrides { deviceId, _ -> Result<String, Swift.Error> in
            runCommand(.simctlClearStatusBarOverrides(device: deviceId), verbose: v)
        }

        server.onOpenUrl { deviceId, _, url -> Result<String, Swift.Error> in
            runCommand(.simctlOpen(url: url, on: deviceId), verbose: v)
        }

        server.onGetAppContainer { deviceId, appBundleId, container -> Result<String, Swift.Error> in
            runCommand(.simctlGetAppContainer(device: deviceId, appBundleIdentifier: appBundleId, container: container), verbose: v)
        }
        
        server.onTriggerEnrollingChange { deviceId, _, type -> Result<String, Swift.Error> in
            runCommand(.simctlEnrollingChange(device: deviceId, type: type), verbose: v)
        }

        server.onTriggerTouchIdMatch { deviceId, _ -> Result<String, Swift.Error> in
            runCommand(.simctlTouchIdMatch(device: deviceId), verbose: v)
        }
        
        server.onTriggerTouchIdNomatch { deviceId, _ -> Result<String, Swift.Error> in
            runCommand(.simctlTouchIdNomatch(device: deviceId), verbose: v)
        }
        
        server.onTriggerShake { deviceId, _ -> Result<String, Swift.Error> in
            runCommand(.simctlShake(device: deviceId), verbose: v)
        }

        server.onStartRecordVideo { deviceId, _, path -> Result<String, Swift.Error> in
            runCommand(.simctlStartRecordVideo(device: deviceId, path: path), verbose: v)
        }
        
        server.onKillSimctl { device, _ -> Result<String, Swift.Error> in
            runCommand(.stopRecording(device: device), verbose: v)
        }

        try server.startServer(on: port)
        print("Server listening on 127.0.0.1:\(port)...")
        let signalCodes: [Int32] = [SIGINT, SIGTERM]
        let signals = signalCodes.map { code -> DispatchSourceSignal in
            Darwin.signal(code, { _ in })
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler {
                runner.stopAllRecordings()
                server.stop()
                Darwin.exit(0)
            }
            source.resume()
            return source
        }
        withExtendedLifetime((server, runner, signals)) {
            RunLoop.main.run()
        }
    }
}
