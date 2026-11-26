import SwiftUI
import Combine
import FactoryCore

struct MeatproxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel(fixture: AppModel.demo, firstRun: AppModel.firstRunDemo)

    init() { Brand.registerFonts() }     // the wordmark's Inter, before the first view draws

    var body: some Scene {
        // one window (UX review 26 Nov, point 6): a second one would take the world from the first, so there is no
        // File › New Window; closing it quits, after asking when something still runs
        Window(Brand.name, id: AppDelegate.windowID) {
            HUDView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
                .background(DelegateLink(delegate: delegate, model: model))
        }
        .windowStyle(.hiddenTitleBar)
        .commands { MenuBar(model: model, menu: model.menu) }
        .defaultSize(width: 1440, height: 900)
    }
}

/// Hands the app delegate the model and a way to open the window again (the quit alert's Cancel, the Dock menu).
private struct DelegateLink: View {
    @Environment(\.openWindow) private var openWindow
    let delegate: AppDelegate
    let model: AppModel
    var body: some View {
        Color.clear.onAppear {
            delegate.model = model
            delegate.reopen = { openWindow(id: AppDelegate.windowID) }
        }
    }
}

/// The menu bar (UX review 26 Nov, point 9): Go, View, Factories and Help, built from the same commands as ⌘K and
/// Help (`AppModel.staticCommands`), so menu, search and Help never tell it two ways. The menu holds the ⌘ keys; the
/// HUD keeps only the keys a menu cannot (Esc, ?, and 1 and 2 on an open question).
struct MenuBar: Commands {
    let model: AppModel
    /// what the menus show changes with these, and only these (the model itself changes many times a second)
    @ObservedObject var menu: MenuState

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(Brand.shortName)") { Brand.showAbout() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.settingsOpen = true }.keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Go") { items(.go) }
        CommandGroup(before: .toolbar) {
            items(.view)
            Divider()
        }
        CommandMenu("Factories") {
            Button("Pause All") { model.setPauseAll(true) }.disabled(menu.state.pauseAll)
            Button("Resume All") { model.setPauseAll(false) }.disabled(!menu.state.pauseAll)
            if !menu.state.factories.isEmpty {
                Divider()
                Menu("Run Now") {
                    ForEach(model.staticCommands.filter { $0.id.hasPrefix("do.run:") }) { c in
                        Button(c.title.replacingOccurrences(of: "Run now · ", with: "")) { c.run() }
                    }
                }
            }
        }
        CommandGroup(replacing: .help) { items(.help) }
    }

    @ViewBuilder private func items(_ place: AppCommand.MenuPlace) -> some View {
        let _ = menu.state
        ForEach(model.staticCommands.filter { $0.menu == place }) { c in
            Button(c.menuTitle ?? c.title) { c.run() }.keyboardShortcut(c.shortcut)
        }
    }
}

/// The few things the menu bar shows, apart from the model, so the menus are rebuilt only when one of them changes.
@MainActor
final class MenuState: ObservableObject {
    struct State: Equatable {
        var plainKeys = false, waiting = false, statusLayer = false, terminal = false, pauseAll = false
        var factories: [String] = []
    }
    @Published private(set) var state = State()
    func set(_ s: State) { if s != state { state = s } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let windowID = "main"
    /// set once the window appears
    var model: AppModel?
    var reopen: (() -> Void)?

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

    /// Quitting stops what runs in the app (UX review 26 Nov, point 6): when something does, it asks first and names
    /// it. On the window as a sheet; when you closed the window, on its own, and Cancel brings the window back.
    @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !WindowShot.active, let line = model?.runningWork else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit \(Brand.shortName)?"
        alert.informativeText = line
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) {
            alert.beginSheetModal(for: w) { r in NSApp.reply(toApplicationShouldTerminate: r == .alertFirstButtonReturn) }
            return .terminateLater
        }
        if alert.runModal() == .alertFirstButtonReturn { return .terminateNow }
        reopen?()
        return .terminateCancel
    }

    /// Right-click on the Dock icon: the three things you most often come for.
    @MainActor func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let model else { return nil }
        let m = NSMenu()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let i = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            i.target = self
            m.addItem(i)
        }
        add("Next That Needs You", #selector(dockNext), enabled: !model.world.needsYou.isEmpty)
        add(model.projectSettings.pauseAll ? "Resume All Factories" : "Pause All Factories", #selector(dockPause))
        add("Server Room", #selector(dockServerRoom))
        return m
    }
    @MainActor @objc private func dockNext() { front(); model?.goNext() }
    @MainActor @objc private func dockPause() { guard let model else { return }; model.setPauseAll(!model.projectSettings.pauseAll) }
    @MainActor @objc private func dockServerRoom() { front(); model?.goServerRoom() }
    @MainActor private func front() {
        NSApp.activate()
        if !NSApp.windows.contains(where: { $0.isVisible && $0.frame.width > 400 }) { reopen?() }
    }
}
