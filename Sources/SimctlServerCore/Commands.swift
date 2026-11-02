import Foundation
import SimctlShared

/// A host operation with separate arguments and optional stdin; never evaluated by a shell.
public struct SimctlCommand {
    enum Action {
        case run([String], Data?)
        case sequence([[String]])
        case privacy(PrivacyAction, PrivacyService, UUID, String?)
        case record(UUID, String)
        case stopRecording(UUID)
    }

    let action: Action

    public static func simctlList() -> SimctlCommand {
        .init(action: .run(["list", "devices", "--json"], nil))
    }

    public static func simctlOpen(url: URL, on device: UUID) -> SimctlCommand {
        .init(action: .run(["openurl", device.uuidString, url.absoluteString], nil))
    }

    public static func simctlSetUI(appearance: DeviceAppearance, on device: UUID) -> SimctlCommand {
        .init(action: .run(["ui", device.uuidString, "appearance", appearance.rawValue], nil))
    }

    public static func simctlPush(to device: UUID, pushContent: PushNotificationContent, bundleIdentifier: String? = nil) -> SimctlCommand {
        let arguments = ["push", device.uuidString] + (bundleIdentifier.map { [$0] } ?? [])
        switch pushContent {
        case let .file(url): return .init(action: .run(arguments + [url.path], nil))
        case let .jsonPayload(data): return .init(action: .run(arguments + ["-"], data))
        }
    }

    public static func simctlPrivacy(_ action: PrivacyAction, permissionsFor service: PrivacyService, on device: UUID, bundleIdentifier: String?) -> SimctlCommand {
        .init(action: .privacy(action, service, device, bundleIdentifier))
    }

    public static func simctlRename(device: UUID, to name: String) -> SimctlCommand {
        .init(action: .run(["rename", device.uuidString, name], nil))
    }

    public static func simctlTerminateApp(device: UUID, appBundleIdentifier: String) -> SimctlCommand {
        .init(action: .run(["terminate", device.uuidString, appBundleIdentifier], nil))
    }

    public static func simctlErase(device: UUID) -> SimctlCommand {
        .init(action: .run(["erase", device.uuidString], nil))
    }

    public static func simctlTriggerICloudSync(device: UUID) -> SimctlCommand {
        .init(action: .run(["icloud_sync", device.uuidString], nil))
    }

    public static func simctlInstallApp(device: UUID, path: String) -> SimctlCommand {
        .init(action: .run(["install", device.uuidString, path], nil))
    }

    public static func simctlUninstallApp(device: UUID, appBundleIdentifier: String) -> SimctlCommand {
        .init(action: .run(["uninstall", device.uuidString, appBundleIdentifier], nil))
    }

    public static func simctlClearStatusBarOverrides(device: UUID) -> SimctlCommand {
        .init(action: .run(["status_bar", device.uuidString, "clear"], nil))
    }

    public static func simctlSetStatusBarOverrides(device: UUID, overrides: Set<StatusBarOverride>) -> SimctlCommand {
        // Keep flag/value pairs separate even when a value includes spaces or shell metacharacters.
        let arguments = overrides.sorted { $0.command < $1.command }.flatMap { $0.arguments }
        return .init(action: .run(["status_bar", device.uuidString, "override"] + arguments, nil))
    }

    public static func simctlGetAppContainer(device: UUID, appBundleIdentifier: String, container: AppContainer? = nil) -> SimctlCommand {
        .init(action: .run(["get_app_container", device.uuidString, appBundleIdentifier, (container ?? .app).container], nil))
    }

    public static func simctlEnrollingChange(device: UUID, type: EnrollingType) -> SimctlCommand {
        let prefix = ["spawn", device.uuidString, "notifyutil"]
        return .init(action: .sequence([
            prefix + ["-s", "com.apple.BiometricKit.enrollmentChanged", type.rawValue],
            prefix + ["-p", "com.apple.BiometricKit.enrollmentChanged"]
        ]))
    }

    public static func simctlTouchIdMatch(device: UUID) -> SimctlCommand {
        .init(action: .run(["spawn", device.uuidString, "notifyutil", "-p", "com.apple.BiometricKit_Sim.fingerTouch.match"], nil))
    }

    public static func simctlTouchIdNomatch(device: UUID) -> SimctlCommand {
        .init(action: .run(["spawn", device.uuidString, "notifyutil", "-p", "com.apple.BiometricKit_Sim.fingerTouch.nomatch"], nil))
    }

    public static func simctlShake(device: UUID) -> SimctlCommand {
        .init(action: .run(["notify_post", device.uuidString, "com.apple.UIKit.SimulatorShake"], nil))
    }

    public static func simctlStartRecordVideo(device: UUID, path: String) -> SimctlCommand {
        .init(action: .record(device, path))
    }

    /// Stops only the recording started by this runner for this device.
    public static func stopRecording(device: UUID) -> SimctlCommand {
        .init(action: .stopRecording(device))
    }
}
