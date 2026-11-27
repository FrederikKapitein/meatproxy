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

    /// ⌘W with a terminal focused closes its tab, as in every terminal, and not the window (closing the last tab hides
    /// the drawer); anywhere else ⌘W is the window's.
    private var keyMonitor: Any?
    override init() {
        super.init()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let cmdW = e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && e.charactersIgnoringModifiers == "w"
            guard cmdW else { return e }
            let closed = MainActor.assumeIsolated { self?.closeFocusedTab() == true }
            return closed ? nil : e
        }
    }
    private func closeFocusedTab() -> Bool {
        guard shown, let id = selected, let t = tabs.first(where: { $0.id == id }),
              let responder = t.view.window?.firstResponder as? NSView, responder === t.view || responder.isDescendant(of: t.view) else { return false }
        close(id)
        if let next = tabs.first(where: { $0.id == selected }) { DispatchQueue.main.async { next.view.window?.makeFirstResponder(next.view) } }
        return true
    }

    /// Opens a tab with a command and shows the panel. `onClose` runs when you close the tab (hand a factory back).
    func open(_ c: TerminalCommand, icon: String = "terminal", onClose: (() -> Void)? = nil) {
        let v = FocusingTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        // the keyboard goes to the new tab once its view is in the window (the drawer may still be arriving)
        v.focusInWindow = true
        Self.style(v)
        v.processDelegate = self
        tabs.append(Tab(title: c.title, icon: icon, view: v, onClose: onClose))
        selected = tabs.last?.id
        shown = true
        v.startProcess(executable: c.executable, args: c.args, environment: TerminalCommand.environment(),
                       execName: (c.executable as NSString).lastPathComponent, currentDirectory: c.cwd)
        if let w = v.window { v.focusInWindow = false; w.makeFirstResponder(v) }
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

/// A terminal that takes the keyboard when it lands in the window, if asked: a new tab's view is not in the window yet
/// when the tab opens, so making it first responder then did nothing (UX review 26 Nov).
final class FocusingTerminalView: LocalProcessTerminalView {
    var focusInWindow = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusInWindow, let w = window else { return }
        focusInWindow = false
        DispatchQueue.main.async { [weak self] in if let self { w.makeFirstResponder(self) } }
    }
}

/// The terminal drawer (E10): a panel in the same frame as the others, its tabs as folder tabs over the selected tab's
/// terminal, its height dragged from the top edge. The side panels end 16 above it.
struct TerminalPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var center: TerminalCenter
    @State private var dragStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            // the grip: drag to make it taller or shorter
            RoundedRectangle(cornerRadius: 2).fill(Color.border).frame(width: 36, height: 4).padding(.vertical, 6)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .gesture(DragGesture().onChanged { g in
                    let start = dragStart ?? center.height
                    dragStart = start
                    center.height = min(max(start - g.translation.height, 160), 720)
                }.onEnded { _ in dragStart = nil })
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                .accessibilityLabel("Drag to resize the terminal")
            HStack(alignment: .bottom, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 2) { ForEach(center.tabs) { tab in TabChip(center: center, tab: tab) } }
                }
                .frame(height: 36)
                Spacer(minLength: 0)
                Button { center.toggle() } label: { SpelLabel(icon: "chevd", key: "⌘J", iconColor: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).help("Hide the terminal (⌘J)").accessibilityLabel("Hide the terminal")
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 12)
            ZStack {
                ForEach(center.tabs) { tab in
                    TerminalHost(view: tab.view).opacity(tab.id == center.selected ? 1 : 0).allowsHitTesting(tab.id == center.selected)
                }
                if center.tabs.isEmpty {
                    Text("Take over a session, follow a run or open a server from its card: it opens here.")
                        .font(.s13).foregroundStyle(Color.muted)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 10).fill(Color(red: 0.07, green: 0.07, blue: 0.07)))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 10).strokeBorder(Color.divider, lineWidth: 2))
            .padding(.horizontal, 12).padding(.top, -2).padding(.bottom, 12)
        }
        .frame(height: center.height)
        .spelFrame()
    }
}

/// One tab as a folder tab: a light while it runs (or how it ended), its title, and its close cross.
private struct TabChip: View {
    @ObservedObject var center: TerminalCenter
    let tab: TerminalCenter.Tab
    var body: some View {
        let on = tab.id == center.selected
        HStack(spacing: 6) {
            PixelIcon(tab.exited == nil ? "dot" : "ring", color: tab.exited == nil ? .done : .muted).frame(width: 18, height: 18)
                .accessibilityElement(children: .ignore).accessibilityLabel(tab.exited == nil ? "Running" : "Ended")
            Text(tab.title).font(.spel(13, weight: on ? .bold : .semibold)).foregroundStyle(on ? Color.inkText : Color.muted)
                .lineLimit(1).frame(maxWidth: 240, alignment: .leading)
            if let code = tab.exited { Text(code.map { "exit \($0)" } ?? "ended").font(.mono12).foregroundStyle(Color.muted) }
            Button { center.close(tab.id) } label: { PixelIcon("close", color: .muted, size: 9).frame(width: 24, height: 24).contentShape(Rectangle()) }
                .buttonStyle(.plain).help(tab.exited == nil ? "Close and stop it" : "Close").accessibilityLabel("Close \(tab.title)")
        }
        .padding(.horizontal, 12)
        .frame(height: on ? 36 : 30)
        .background(TabShape().fill(on ? Color(red: 0.07, green: 0.07, blue: 0.07) : Color.rail))
        .overlay(TabShape().stroke(Color.divider, lineWidth: 2).padding(.horizontal, 1).padding(.top, 1))
        .padding(.bottom, on ? 0 : 2)
        .contentShape(Rectangle())
        .zIndex(on ? 2 : 0)
        .onTapGesture { center.selected = tab.id; DispatchQueue.main.async { tab.view.window?.makeFirstResponder(tab.view) } }
        .accessibilityElement(children: .contain).accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/// A tab's terminal view in SwiftUI (the view itself lives in the center, so a tab keeps its screen when hidden).
private struct TerminalHost: NSViewRepresentable {
    let view: LocalProcessTerminalView
    func makeNSView(context: Context) -> LocalProcessTerminalView { view }
    func updateNSView(_ v: LocalProcessTerminalView, context: Context) {}
}
