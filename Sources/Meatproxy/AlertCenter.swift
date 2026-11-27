import AppKit
import Foundation
import UserNotifications
import FactoryCollector

/// Alerts as notifications on this Mac (D49, D54). In Meatproxy.app (scripts/make-app.sh) they are the system's own: the
/// app's icon, grouped per server or site, with Open and Run DevOps now; a click opens that server in the app. They also
/// show while the app is in front. The bare debug build has no bundle, so there AppleScript shows them instead.
/// Push to the phone comes with the iPhone app.
@MainActor
final class AlertCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    /// a notification was clicked (or Open): the server id or site address it is about
    var onOpen: ((String) -> Void)?
    /// Run DevOps now was chosen on a notification
    var onRunDevOps: (() -> Void)?
    /// what macOS allows: nil while unknown or without a bundle (the AppleScript way needs no permission)
    @Published private(set) var permission: UNAuthorizationStatus?

    static let category = "meatproxy.alert"
    static let open = "meatproxy.open", runDevOps = "meatproxy.devops"

    var bundled: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    override init() {
        super.init()
        guard bundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(
            identifier: Self.category,
            actions: [UNNotificationAction(identifier: Self.open, title: "Open", options: [.foreground]),
                      UNNotificationAction(identifier: Self.runDevOps, title: "Run DevOps now", options: [.foreground])],
            intentIdentifiers: [], options: [])])
        Task { await readPermission() }
    }

    /// Reads what macOS allows now (System Settings may have changed it while the app was away).
    func readPermission() async {
        guard bundled else { return }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        permission = s.authorizationStatus
    }

    /// Asks once, when you switch notifications on or send a test (never inside `post`, where the first alert would
    /// be lost to the question). True when they may show.
    @discardableResult func askPermission() async -> Bool {
        guard bundled else { return true }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await readPermission()
        return permission == .authorized || permission == .provisional
    }

    /// macOS has notifications off for Meatproxy: only System Settings can switch them on again.
    var deniedBySystem: Bool { permission == .denied }

    /// System Settings › Notifications, at Meatproxy when it can.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier.map { "?id=" + $0 } ?? ""
        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension" + id) { NSWorkspace.shared.open(u) }
    }

    func post(_ e: AlertEvent) { post(title: e.title, body: e.text, key: e.key, kind: e.kind) }

    func test() {
        Task {
            guard await askPermission() else { return }
            post(title: "web-01 needs a look", body: "disk 91% full (a test from Meatproxy: nothing is wrong)", key: "test", kind: .warn)
        }
    }

    /// One notification per thing (its key is its id): a server that comes back replaces its own "down", and
    /// `remove` takes it away once it no longer holds.
    func post(title: String, body: String, key: String, kind: AlertEvent.Kind, subtitle: String? = nil) {
        if bundled {
            let center = UNUserNotificationCenter.current()
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body
            c.subtitle = subtitle ?? (kind == .down ? "Server room · down" : kind == .warn ? "Server room · needs a look" : "Server room · fine again")
            c.sound = kind == .recovered ? nil : .default
            c.threadIdentifier = key                       // grouped per server or site
            c.categoryIdentifier = Self.category
            c.userInfo = ["key": key]
            // time-sensitive needs an entitlement the ad-hoc signed app (scripts/make-app.sh) does not have
            c.interruptionLevel = .active
            center.add(UNNotificationRequest(identifier: key, content: c, trigger: nil))
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv) sound name \"Funk\"", "-e", "end run", title, body]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run()
        }
    }

    /// Takes notifications away that no longer hold (a question you answered).
    func remove(_ keys: [String]) {
        guard bundled, !keys.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: keys)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// While the app is in front, an alert still shows as a banner (and in the list).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let key = response.notification.request.content.userInfo["key"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            NSApp.activate()
            if action == Self.runDevOps { self.onRunDevOps?() }
            if let key { self.onOpen?(key) }
            completionHandler()
        }
    }
}
