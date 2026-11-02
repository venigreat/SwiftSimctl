//
//  File.swift
//
//
//  Created by Christian Treffs on 18.03.20.
//
import Foundation
import SimctlShared
import Swifter

/// The server used to receive commands from an app and
/// translate them into commands on the local machine.
public final class SimctlServer {
    let server: HttpServer

    public init() {
        server = HttpServer()
        server.listenAddressIPv4 = "127.0.0.1"
        server.listenAddressIPv6 = "::1"
    }

    /// Start a server that listens to library requests from your app and executes simctl commands on your machine.
    /// - Parameter port: the port on which to listen.
    public func startServer(on port: SimctlShared.Port) throws {
        try server.start(port, forceIPv4: true)
    }

    /// Stop the server.
    public func stop() {
        server.stop()
    }

    /// Callback to be executed on push notifcation send request.
    /// - Parameter closure: The closure to be executed.
    public func onPushNotification(_ closure: @escaping (UUID, String?, PushNotificationContent) -> Result<String, Swift.Error>) {
        server.POST[ServerPath.pushNotification.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let bodyData = Data(request.body)
            let decoder = JSONDecoder()
            do {
                let pushContent: PushNotificationContent = try decoder.decode(PushNotificationContent.self, from: bodyData)

                let result = closure(deviceId, bundleId, pushContent)

                switch result {
                case let .success(output):
                    return .ok(.text(output))

                case let .failure(error):
                    return .badRequest(.text(error.localizedDescription))
                }
            } catch {
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on privacy change request.
    /// - Parameter closure: The closure to be executed.
    public func onPrivacy(_ closure: @escaping (UUID, String?, PrivacyAction, PrivacyService) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.privacy.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            let bundleId = request.headerValue(for: .bundleIdentifier)

            guard let action: PrivacyAction = request.headerValue(for: .privacyAction) else {
                return .badRequest(.text("Privacy action missing or corrupt."))
            }

            let rawService = request.headerValue(for: .privacyService)
            let service = rawService.flatMap { PrivacyService(rawValue: $0 == "media" ? "media-library" : $0) }
            guard let service = service else {
                return .badRequest(.text("Privacy service missing or corrupt."))
            }

            guard action == .reset || !(bundleId ?? "").isEmpty else {
                return .badRequest(.text("Bundle Id is required for grant and revoke."))
            }

            let result = closure(deviceId, bundleId, action, service)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on rename device request.
    /// - Parameter closure: The closure to be executed.
    public func onRename(_ closure: @escaping (UUID, String?, String) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.renameDevice.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            guard let deviceName: String = request.headerValue(for: .deviceName) else {
                return .badRequest(.text("No device name parameter provided."))
            }

            let result = closure(deviceId, bundleId, deviceName)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on terminate app device request.
    /// - Parameter closure: The closure to be executed.
    public func onTerminateApp(_ closure: @escaping (UUID, String?, String) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.terminateApp.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            guard let targetAppBundleId: String = request.headerValue(for: .targetBundleIdentifier) else {
                return .badRequest(.text("No target app bundle id parameter provided."))
            }

            let result = closure(deviceId, bundleId, targetAppBundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onErase(_ closure: @escaping (UUID) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.erase.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            let result = closure(deviceId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onSetDeviceAppearance(_ closure: @escaping (UUID, String?, DeviceAppearance) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.deviceAppearance.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            guard let appearance: DeviceAppearance = request.headerValue(for: .deviceAppearance) else {
                return .badRequest(.text("Device appearance missing or corrupt."))
            }

            let result = closure(deviceId, bundleId, appearance)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onTriggerICloudSync(_ closure: @escaping (UUID, String?) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.iCloudSync.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let result = closure(deviceId, bundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on uninstall app device request.
    /// - Parameter closure: The closure to be executed.
    public func onInstallApp(_ closure: @escaping (UUID, String?, String) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.installApp.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            guard let path = request.headerValue(for: .path) ?? request.headerValue(for: .targetBundleIdentifier) else {
                return .badRequest(.text("No path parameter provided."))
            }

            let result = closure(deviceId, bundleId, path)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on uninstall app device request.
    /// - Parameter closure: The closure to be executed.
    public func onUninstallApp(_ closure: @escaping (UUID, String?, String) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.uninstallApp.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            guard let targetAppBundleId: String = request.headerValue(for: .targetBundleIdentifier) else {
                return .badRequest(.text("No target app bundle id parameter provided."))
            }

            let result = closure(deviceId, bundleId, targetAppBundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on start recording screen request.
    /// - Parameter closure: The closure to be executed.
    public func onStartRecordVideo(_ closure: @escaping (UUID, String?, String) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.startRecordVideo.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            guard let path: String = request.headerValue(for: .path) else {
                return .badRequest(.text("No path parameter provided."))
            }

            let result = closure(deviceId, bundleId, path)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on set status bar override request.
    /// - Parameter closure: The closure to be executed.
    public func onSetStatusBarOverride(_ closure: @escaping (UUID, String?, Set<StatusBarOverride>) -> Result<String, Swift.Error>) {
        server.POST[ServerPath.statusBarOverrides.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let bodyData = Data(request.body)
            let decoder = JSONDecoder()
            do {
                let overrides: Set<StatusBarOverride> = try decoder.decode(Set<StatusBarOverride>.self, from: bodyData)

                let result = closure(deviceId, bundleId, overrides)

                switch result {
                case let .success(output):
                    return .ok(.text(output))

                case let .failure(error):
                    return .badRequest(.text(error.localizedDescription))
                }
            } catch {
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on clear status bar override request.
    /// - Parameter closure: The closure to be executed.
    public func onClearStatusBarOverrides(_ closure: @escaping (UUID, String?) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.statusBarOverrides.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let result = closure(deviceId, bundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    /// Callback to be executed on open url request.
    /// - Parameter closure: The closure to be executed.
    public func onOpenUrl(_ closure: @escaping (UUID, String?, URL) -> Result<String, Swift.Error>) {
        server.POST[ServerPath.openURL.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let bodyData = Data(request.body)
            let urlContainer: URLContainer

            do {
                urlContainer = try JSONDecoder().decode(URLContainer.self, from: bodyData)
            } catch {
                return .badRequest(.text(error.localizedDescription))
            }

            let result = closure(deviceId, bundleId, urlContainer.url)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onGetAppContainer(_ closure: @escaping (UUID, String, AppContainer) -> Result<String, Swift.Error>) {
        server.POST[ServerPath.getAppContainer.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let bodyData = Data(request.body)

            let appContainer: AppContainer
            do {
                appContainer = try JSONDecoder().decode(AppContainer?.self, from: bodyData) ?? .app
            } catch {
                return .badRequest(.text(error.localizedDescription))
            }

            let result = closure(deviceId, bundleId, appContainer)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }


    public func onTriggerEnrollingChange(_ closure: @escaping (UUID, String?, EnrollingType) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.enrollmentChanged.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            guard let type: EnrollingType = request.headerValue(for: .enrollingType) else {
                return .badRequest(.text("Enrolling type missing or corrupt."))
            }

            let result = closure(deviceId, bundleId, type)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onTriggerTouchIdMatch(_ closure: @escaping (UUID, String?) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.touchIdMatch.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let result = closure(deviceId, bundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onTriggerTouchIdNomatch(_ closure: @escaping (UUID, String?) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.touchIdNomatch.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let result = closure(deviceId, bundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onTriggerShake(_ closure: @escaping (UUID, String?) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.shake.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let result = closure(deviceId, bundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }

    public func onKillSimctl(_ closure: @escaping (UUID, String?) -> Result<String, Swift.Error>) {
        server.GET[ServerPath.kill.rawValue] = { request in
            guard let deviceId = request.headerValue(for: .deviceUdid, UUID.init) else {
                return .badRequest(.text("Device Udid missing or corrupt."))
            }

            guard let bundleId = request.headerValue(for: .bundleIdentifier) else {
                return .badRequest(.text("Bundle Id missing or corrupt."))
            }

            let result = closure(deviceId, bundleId)

            switch result {
            case let .success(output):
                return .ok(.text(output))

            case let .failure(error):
                return .badRequest(.text(error.localizedDescription))
            }
        }
    }
}
