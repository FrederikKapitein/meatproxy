import Foundation
import ServiceManagement

/// Open at login (UX review 26 Nov, round 3): Meatproxy.app as one of the Mac's own Login Items, through
/// `SMAppService.mainApp`, so System Settings › Login Items lists it and the switch reads its state from there.
///
/// The heartbeat while the app is closed stays a LaunchAgent (LaunchAgent.swift) on purpose: `SMAppService.agent` wants
/// its plist inside the signed bundle and ties your approval to the bundle's signature. The bundle of
/// scripts/make-app.sh is signed ad hoc, without a Team ID, and gets a new signature with every build; `swift run` has
/// no bundle at all. Nothing promises an agent registered that way keeps running after a rebuild, so the heartbeat
/// stays the plain file the Settings switch writes and removes itself.
enum LoginItem {
    enum State: Equatable { case unavailable, off, on, needsApproval }

    /// only an app bundle can be a login item; a bare `swift build` executable cannot
    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    static var state: State {
        guard available else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
