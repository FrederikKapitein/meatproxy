import SwiftUI

struct MeatproxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel(fixture: AppModel.demo, firstRun: AppModel.firstRunDemo)

    init() { Brand.registerFonts() }     // the wordmark's Inter, before the first view draws

    var body: some Scene {
        WindowGroup(Brand.name) {
            HUDView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        // the settings open inside the window, not as a window of their own
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Brand.shortName)") { Brand.showAbout() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.settingsOpen = true }.keyboardShortcut(",", modifiers: .command)
            }
        }
        .defaultSize(width: 1440, height: 900)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)     // a SwiftPM executable starts as a background process
        if let icon = Brand.appIcon { NSApp.applicationIconImage = icon }     // the Dock icon (D45)
        NSApp.activate(ignoringOtherApps: true)
        WindowShot.scheduleIfAsked()
        // the window's title bar is the HUD's top bar: an empty unified toolbar makes it 52 pt, with the traffic lights
        // centred in it, level with the bar's controls (Shell.barHeight); the world shows through, nothing is drawn
        DispatchQueue.main.async { for w in NSApp.windows where w.frame.width > 400 { Self.shell(w) } }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            if let w = note.object as? NSWindow { MainActor.assumeIsolated { Self.shell(w) } }
        }
    }
    @MainActor static func shell(_ w: NSWindow) {
        guard w.toolbar == nil, w.styleMask.contains(.titled), w.frame.width > 400 else { return }
        w.toolbar = NSToolbar(identifier: "meatproxy.shell")
        w.toolbarStyle = .unified
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.titlebarSeparatorStyle = .none
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
