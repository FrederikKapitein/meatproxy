import SwiftUI
import AppKit
import SwiftTerm
import FactoryCore
import FactoryCollector

/// Meatproxy's terminal (D57): tabs at the bottom of the window, each a real terminal (SwiftTerm, a pseudo-terminal) that
/// runs one checked command: a session taken over where its agent left it, ssh to a server, or a run's log followed as
/// it grows. ⌘J shows and hides it; closing a tab stops what runs in it.
@MainActor
final class TerminalCenter: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    struct Tab: Identifiable {
        let id = UUID()
        var title: String
        var icon: String
        let view: LocalProcessTerminalView
        /// nil while it runs; the exit code when it ended
        var exited: Int32?? = nil
        var onClose: (() -> Void)?
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selected: UUID?
    @Published var shown = false { didSet { onShown?(shown) } }
    /// the app hears when the panel opens or closes (its N and esc keys stay with the terminal then)
    var onShown: ((Bool) -> Void)?
    @Published var height: CGFloat = 320

    /// Opens a tab with a command and shows the panel. `onClose` runs when you close the tab (hand a factory back).
    func open(_ c: TerminalCommand, icon: String = "terminal", onClose: (() -> Void)? = nil) {
        let v = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        Self.style(v)
        v.processDelegate = self
        tabs.append(Tab(title: c.title, icon: icon, view: v, onClose: onClose))
        selected = tabs.last?.id
        shown = true
        v.startProcess(executable: c.executable, args: c.args, environment: TerminalCommand.environment(),
                       execName: (c.executable as NSString).lastPathComponent, currentDirectory: c.cwd)
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
    }

    func close(_ id: UUID) {
        guard let k = tabs.firstIndex(where: { $0.id == id }) else { return }
        let t = tabs.remove(at: k)
        if t.exited == nil { t.view.terminate() }
        t.onClose?()
        if selected == id { selected = tabs.last?.id }
        if tabs.isEmpty { shown = false }
    }

    func toggle() {
        shown.toggle()
        if shown, let t = tabs.first(where: { $0.id == selected }) { DispatchQueue.main.async { t.view.window?.makeFirstResponder(t.view) } }
    }

    /// Tuinstra Dark in the terminal: charcoal, warm white text, the yellow caret.
    static func style(_ v: LocalProcessTerminalView) {
        v.nativeBackgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
        v.nativeForegroundColor = NSColor(red: 0.953, green: 0.953, blue: 0.953, alpha: 1)
        v.caretColor = NSColor(red: 1, green: 0.847, blue: 0.239, alpha: 1)
        v.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    }

    private func index(of source: TerminalView) -> Int? { tabs.firstIndex { $0.view === source } }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in if let k = self.index(of: source) { self.tabs[k].exited = .some(exitCode) } }
    }
    nonisolated func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        Task { @MainActor in if let k = self.index(of: source) { self.tabs[k].exited = .some(-1) } }
    }
}

/// The terminal panel: a tab bar over the selected tab's terminal, its height dragged from the top edge.
struct TerminalPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var center: TerminalCenter
    @State private var dragStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            // the grip: drag to make it taller or shorter
            Capsule().fill(Color.border.opacity(0.6)).frame(width: 36, height: 4).padding(.vertical, 5)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .gesture(DragGesture().onChanged { g in
                    let start = dragStart ?? center.height
                    dragStart = start
                    center.height = min(max(start - g.translation.height, 160), 720)
                }.onEnded { _ in dragStart = nil })
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            HStack(spacing: 6) {
                Image(systemName: "terminal").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.muted).padding(.leading, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { ForEach(center.tabs) { tab in TabChip(center: center, tab: tab) } }
                }
                Spacer(minLength: 0)
                Button { center.toggle() } label: {
                    HStack(spacing: 6) { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)); KeyCap("⌘J") }
                        .padding(.horizontal, 8).frame(height: 24)
                }.buttonStyle(TactileButtonStyle(kind: .neutral)).help("Hide the terminal (⌘J)").padding(.trailing, 8)
            }
            .padding(.bottom, 6)
            Divider().overlay(Color.divider)
            ZStack {
                ForEach(center.tabs) { tab in
                    TerminalHost(view: tab.view).opacity(tab.id == center.selected ? 1 : 0).allowsHitTesting(tab.id == center.selected)
                }
                if center.tabs.isEmpty {
                    Text("Take over a session, follow a run or open a server from its card: it opens here.")
                        .font(.system(size: 12.5)).foregroundStyle(Color.muted)
                }
            }
            .padding(8)
        }
        .frame(height: center.height)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.divider))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
    }
}

/// One tab: its icon, title, a light while it runs (or how it ended), and its close cross.
private struct TabChip: View {
    @ObservedObject var center: TerminalCenter
    let tab: TerminalCenter.Tab
    var body: some View {
        let on = tab.id == center.selected
        HStack(spacing: 6) {
            Circle().fill(tab.exited == nil ? Color.done : Color.muted).frame(width: 6, height: 6)
            Image(systemName: tab.icon).font(.system(size: 10.5, weight: .semibold))
            Text(tab.title).font(.system(size: 11.5, weight: on ? .bold : .semibold)).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
            if let code = tab.exited { Text(code.map { "exit \($0)" } ?? "ended").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.muted) }
            Button { center.close(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.muted) }
                .buttonStyle(.plain).help(tab.exited == nil ? "Close and stop it" : "Close")
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(on ? Color.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Color.border.opacity(0.7) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { center.selected = tab.id; DispatchQueue.main.async { tab.view.window?.makeFirstResponder(tab.view) } }
    }
}

/// A tab's terminal view in SwiftUI (the view itself lives in the center, so a tab keeps its screen when hidden).
private struct TerminalHost: NSViewRepresentable {
    let view: LocalProcessTerminalView
    func makeNSView(context: Context) -> LocalProcessTerminalView { view }
    func updateNSView(_ v: LocalProcessTerminalView, context: Context) {}
}
