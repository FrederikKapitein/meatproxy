import AppKit
import Foundation
import UserNotifications
import FactoryCollector

/// Alerts as notifications on this Mac (D49, D54). In Meatproxy.app (scripts/make-app.sh) they are the system's own: the
/// app's icon, grouped per server or site, with Open and Run DevOps now; a click opens that server in the app. They also
/// show while the app is in front. The bare debug build has no bundle, so there AppleScript shows them instead.
/// Push to the phone comes with the iPhone app.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    /// a notification was clicked (or Open): the server id or site address it is about
    var onOpen: ((String) -> Void)?
    /// Run DevOps now was chosen on a notification
    var onRunDevOps: (() -> Void)?
    private var asked = false

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
    }

    func post(_ e: AlertEvent) { post(title: e.title, body: e.text, key: e.key, kind: e.kind) }

    func test() { post(title: "web-01 needs a look", body: "disk 91% full (a test from Meatproxy: nothing is wrong)", key: "test", kind: .warn) }

    func post(title: String, body: String, key: String, kind: AlertEvent.Kind) {
        if bundled {
            let center = UNUserNotificationCenter.current()
            if !asked { asked = true; center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body
            c.subtitle = kind == .down ? "Engine room · down" : kind == .warn ? "Engine room · needs a look" : "Engine room · fine again"
            c.sound = kind == .recovered ? nil : .default
            c.threadIdentifier = key                       // grouped per server or site
            c.categoryIdentifier = Self.category
            c.userInfo = ["key": key]
            c.interruptionLevel = kind == .down ? .timeSensitive : .active
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv) sound name \"Funk\"", "-e", "end run", title, body]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run()
        }
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
