import SwiftUI
import FactoryCore
import FactoryCollector

/// Settings (E8): a sheet in the same floating frame as every panel, 760 wide, over the dimmed world. Its tabs belong
/// to it (D10): General, Sources, Projects, Server room and Privacy. Every tab uses one row pattern: a title and a line
/// on the left, the control on the right, in cards of one width. What belongs to one factory is set on its floor (D2);
/// Settings keeps what holds for all of them. ⌘, or the toolbar opens it; Esc, the cross or a click beside it closes it.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var section: Section
    /// VoiceOver starts on the sheet's title: what is behind it is hidden while it is open (UX review 26 Nov, point 10)
    @AccessibilityFocusState private var titleFocus: Bool
    /// the page asked for (D10): its tab and page are the sheet's first state, so it opens on that page in one piece,
    /// with no list sliding out under a page that slides in while the sheet itself arrives
    private let page: String?
    private let atForm: Bool

    enum Section: String, CaseIterable, Identifiable {
        case general = "General", sources = "Sources", projects = "Projects", engine = "Server room", privacy = "Privacy"
        var id: String { rawValue }
    }

    /// "general", "sources", "privacy", "engine", "project:<root>", "server:<id>"; or the Projects list, or the form to add a server
    init(page: String? = nil, atProjects: Bool = false, atForm: Bool = false) {
        self.page = page; self.atForm = atForm
        _section = State(initialValue: Self.section(for: page, atProjects: atProjects, atForm: atForm))
    }

    static func section(for p: String?, atProjects: Bool, atForm: Bool) -> Section {
        if atForm { return .engine }
        if let p { return p.hasPrefix("server:") || p == "engine" ? .engine : p.hasPrefix("project:") ? .projects : p == "privacy" ? .privacy : p == "sources" ? .sources : .general }
        return atProjects ? .projects : .general
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Socket(size: 44) { PixelIcon("gear", color: .inkText) }
                Text("Settings").font(.s26).foregroundStyle(Color.inkText)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocus)
                if model.fixture { Tag("Demo data: nothing is saved") }
                Spacer()
                Text("Changes save as you go").font(.s13).foregroundStyle(Color.muted)
                CloseButton(action: close).keyboardShortcut(.cancelAction)
            }
            TabbedBox(items: Section.allCases.map { .init(id: $0, title: $0.rawValue) }, selected: section, stretch: false, pick: { section = $0 }) {
                ScrollFit {
                    Group {
                        switch section {
                        case .general: GeneralSettings()
                        case .sources: SourcesSettings()
                        case .engine: EngineRoomSettings(open: atForm ? "new" : page.flatMap { $0.hasPrefix("server:") ? String($0.dropFirst(7)) : nil })
                        case .projects: ProjectsSettings(open: page.flatMap { $0.hasPrefix("project:") ? String($0.dropFirst(8)) : nil })
                        case .privacy: PrivacySettings()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                    .id(section)
                }
            }
        }
        .padding(16)
        .spelFrame()
        .onAppear { openAsked(); DispatchQueue.main.async { titleFocus = true } }
    }

    /// Settings opened on a page: from a window shot, a card's link, a notification or the walk
    private func openAsked() {
        // the page asked for is read once, in init; the next time Settings opens on General
        model.settingsAtProjects = false; model.settingsPage = nil; model.settingsAtForm = false
    }

    private func close() { withAnimation(.easeOut(duration: 0.2)) { model.settingsOpen = false } }
}

// MARK: General

/// The switches that are not about one project, one source or one server.
private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RowCard(title: "Campus") {
                SwitchRow("Chats floor", "Chats outside a project share one floor.",
                          isOn: Binding(get: { model.projectSettings.showChats }, set: { model.setShowChats($0) }))
                RowDivider()
                SwitchRow("Meme mode", "Yes and No read LGTM and Not today.", isOn: $model.memeMode)
            }
            RowCard(title: "This Mac") {
                FieldRow(title: "Text size", text: "Larger moves every size one step up: easier to read, a little less fits.") {
                    LiftedSegments(items: [.init(id: false, title: "Default"), .init(id: true, title: "Larger")], selected: model.textLarger) { model.textLarger = $0 }
                        .accessibilityLabel("Text size")
                }
                RowDivider()
                SwitchRow("Single-key shortcuts (N, 1, 2, ?)", "Off for voice control, or when they get in your way. Esc and the ⌘ keys stay.", isOn: $model.singleKeys)
                RowDivider()
                LoginRow()
            }
            RowCard(title: "Heartbeat") {
                SwitchRow("Pause all factories", "Nothing starts; running CEOs and the DevOps agent stop.",
                          isOn: Binding(get: { model.projectSettings.pauseAll }, set: { model.setPauseAll($0) }))
                RowDivider()
                SwitchRow("Keep running when closed", "Off: a run is skipped while Meatproxy is closed.",
                          isOn: Binding(get: { model.projectSettings.heartbeatWhenClosed }, set: { model.setHeartbeatWhenClosed($0) }))
            }
            AlertsCard(alerts: model.alerts)
        }
    }
}

/// Open at login (UX review 26 Nov, round 3): the Mac's own Login Items, so System Settings shows it and the switch
/// always says what is true there. Only Meatproxy.app can be one; a development build says so.
private struct LoginRow: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let state = model.loginItem
        FieldRow(title: "Open at login", text: Self.line(state), disabled: state == .unavailable) {
            HStack(spacing: 8) {
                if state == .needsApproval {
                    Button { LoginItem.openSystemSettings() } label: { Text("Open System Settings") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                }
                Toggle("Open at login", isOn: Binding(get: { state == .on || state == .needsApproval }, set: { model.setOpenAtLogin($0) }))
                    .labelsHidden().toggleStyle(TactileToggleStyle()).disabled(state == .unavailable)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.readLoginItem() }
    }
    static func line(_ s: LoginItem.State) -> String {
        switch s {
        case .unavailable: "Only for Meatproxy.app (scripts/make-app.sh); this is a development build."
        case .off: "Opens Meatproxy when you log in. It shows in System Settings › Login Items."
        case .on: "In System Settings › Login Items; switch it off here or there."
        case .needsApproval: "Waits for your OK in System Settings › General › Login Items."
        }
    }
}

/// Notifications on this Mac (UX review 26 Nov, point 5): macOS's own say first (when it has them off, only System
/// Settings can switch them on), then what may notify. Switching one on asks macOS then, not at the first alert.
private struct AlertsCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var alerts: AlertCenter
    @State private var testSent = false
    var body: some View {
        let denied = alerts.deniedBySystem
        let any = model.projectSettings.devops.notify || model.notifyNeedsYou
        RowCard(title: "Notifications") {
            if denied {
                FieldRow(title: "Notifications on this Mac", text: "Off in System Settings: nothing below shows until you allow it there.") {
                    Button { AlertCenter.openSystemSettings() } label: { Text("Open System Settings") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                }
                RowDivider()
            }
            SwitchRow("Servers and sites", "Down, and fine again (that replaces the down alert).",
                      isOn: Binding(get: { model.projectSettings.devops.notify }, set: { v in model.updateDevOps { $0.notify = v }; if v { model.askToNotify() } }))
            RowDivider()
            SwitchRow("New in Needs you", "Questions and releases. Gone once you answer.",
                      isOn: Binding(get: { model.notifyNeedsYou }, set: { v in model.notifyNeedsYou = v; if v { model.askToNotify() } }))
            RowDivider()
            FieldRow(title: "Try it", text: testSent ? "Sent: look top right." : "See how an alert looks.") {
                Button { alerts.test(); testSent = true } label: { SpelLabel("Send a test", icon: "send", iconColor: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).disabled(!any || denied)
            }
        }
        // System Settings may have changed while the app was away
        .task { await alerts.readPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await alerts.readPermission() } }
    }
}

// MARK: Sources (D5)

/// Each source on one card (D5): its token, how it is, and which factories wake on it, with a switch each. Every
/// input row has the same shape: a label, the field, Save, and the status under it.
private struct SourcesSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var pagesOpen = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sentry
            tracker
            pages
        }
    }

    /// the factories that can wake on a source, with their switch
    private func factories(_ named: (Factory) -> Bool) -> [(Project, Factory)] {
        model.world.projects.compactMap { p in p.factory.map { (p, $0) } }.filter { model.isFactory($0.0) && $0.1.takesSources && named($0.1) }
    }

    private func status(_ key: Secrets.Key) -> (String, Tag.Tone) {
        guard model.connected(key) else { return ("Not connected", .neutral) }
        let health = model.sourceHealth.values.compactMap { key == .sentry ? $0.sentry : $0.tracker }
        if health.contains(where: { !$0.ok }) { return ("Failing", .warn) }
        return ("Connected", .done)
    }

    private var sentry: some View {
        let (word, tone) = status(.sentry)
        let list = factories { $0.sources.hasSentry }
        return VStack(alignment: .leading, spacing: 0) {
            sourceHead("pulse", "Sentry", word, tone)
            TokenRow(key: .sentry, placeholder: "Paste a token with read access to issues", reads: "reads issues")
            RowDivider()
            wakeRows(list, what: "wakes on a new error", connected: model.connected(.sentry), source: "Sentry",
                     empty: "No factory names a Sentry project yet: its CEO adds `sentry: org/project` to `factory/contract.yml`.") { $0.wakeOnSentry } set: { h, v in h.wakeOnSentry = v }
        }
        .spelCard(pad: 0)
    }

    private var tracker: some View {
        let (word, tone) = status(.tracker)
        let list = factories { $0.sources.tracker != nil }
        return VStack(alignment: .leading, spacing: 0) {
            sourceHead("map", "Tracker", word, tone)
            TrackerAddressRow()
            RowDivider()
            TokenRow(key: .tracker, placeholder: "Paste a read token", reads: "reads stories")
            RowDivider()
            wakeRows(list, what: "wakes on a story in Ready", connected: model.connected(.tracker), source: "Tracker", empty: "Then pick which factories wake on it: a factory's CEO names its project in `factory/contract.yml` (`tracker: <slug>`).") { $0.wakeOnTracker } set: { h, v in h.wakeOnTracker = v }
        }
        .spelCard(pad: 0)
    }

    private var pages: some View {
        let on = model.statusSources.filter(\.on).map(\.name)
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { pagesOpen.toggle() } } label: {
                HStack(spacing: 10) {
                    PixelIcon("layers", color: .inkText)
                    Text("Status pages").font(.s15b).foregroundStyle(Color.inkText)
                    Spacer(minLength: 6)
                    Text(on.isEmpty ? "None" : on.joined(separator: ", ")).font(.s13).foregroundStyle(Color.muted).lineLimit(1)
                    PixelIcon(pagesOpen ? "chevd" : "chev", color: .muted, size: 9)
                }
                .padding(.horizontal, 14).frame(height: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if pagesOpen {
                RowDivider()
                StatusSourcesRows()
            }
        }
        .spelCard(pad: 0)
    }

    private func sourceHead(_ icon: String, _ name: String, _ word: String, _ tone: Tag.Tone) -> some View {
        HStack(spacing: 10) {
            PixelIcon(icon, color: .inkText)
            Text(name).font(.s15b).foregroundStyle(Color.inkText)
            Spacer(minLength: 0)
            Tag(word, tone: tone)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
    }

    /// a factory's wake switch on a source: dimmed, saying so, until the source is connected (UX review 26 Nov, point 12)
    @ViewBuilder private func wakeRows(_ list: [(Project, Factory)], what: String, connected: Bool, source: String, empty: String,
                                       get: @escaping (Heartbeat) -> Bool, set: @escaping (inout Heartbeat, Bool) -> Void) -> some View {
        if list.isEmpty {
            Text(code(empty)).prose().padding(14)
        }
        ForEach(Array(list.enumerated()), id: \.element.0.id) { k, pf in
            let (p, _) = pf
            if k > 0 { RowDivider() }
            if let hb = model.projectSettings.entry(p.root)?.heartbeat {
                SwitchRow(p.name, connected ? what : "Connect \(source) first",
                          isOn: Binding(get: { connected && get(hb) }, set: { v in model.updateHeartbeat(p.root) { set(&$0, v) } }), disabled: !connected)
            }
        }
    }
}

/// Your Tracker's MCP address: Tracker is anyone's, so it is yours to name. Empty: Tracker is off.
private struct TrackerAddressRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        let valid = WakeSources.trackerURL(text) != nil, saved = text == model.projectSettings.trackerURL
        InputRow(label: "Address", status: text.isEmpty ? nil : valid ? (saved ? (true, "Saved") : nil) : (false, "Use the full https:// address of the MCP endpoint.")) {
            TextField("", text: $text, prompt: Text("https://tracker.example.com/mcp").foregroundStyle(Color.muted)).focused($focused)
                .font(.mono).textFieldStyle(.plain)
                .onSubmit { if text.isEmpty || valid { model.setTrackerURL(text) } }
                .onChange(of: focused) { _, on in model.typing = on }
        } button: {
            Button { model.setTrackerURL(text) } label: { Text(saved && !text.isEmpty ? "In use" : "Use") }
                .buttonStyle(SpelButtonStyle(kind: .secondary, wide: true)).frame(width: 100).disabled(saved || !(text.isEmpty || valid))
        }
        .onAppear { text = model.projectSettings.trackerURL }
    }
}

/// A source's token (D61): typed once, kept in the macOS Keychain, shown only as saved.
private struct TokenRow: View {
    @EnvironmentObject private var model: AppModel
    let key: Secrets.Key
    let placeholder: String
    /// what a connection lets it read, for the status line ("reads issues")
    let reads: String
    @State private var saved = false
    @State private var value = ""
    @State private var testing = false
    @State private var result: (ok: Bool, line: String)?
    @FocusState private var focused: Bool
    var body: some View {
        InputRow(label: "Token", status: result.map { ($0.ok, $0.line) } ?? (saved ? (model.connected(key) ? (true, "Connected · \(reads)") : (true, "Saved in the Keychain · add the address above to connect")) : nil)) {
            if saved {
                Text("•••••••••••• in the Keychain").font(.mono).foregroundStyle(Color.muted).lineLimit(1)
            } else {
                SecureField("", text: $value, prompt: Text(placeholder).foregroundStyle(Color.muted)).focused($focused).font(.mono)
                    .textFieldStyle(.plain).onSubmit(save)
                    .onChange(of: focused) { _, on in model.typing = on }
            }
        } button: {
            if saved {
                HStack(spacing: 6) {
                    Button { test() } label: { Text(testing ? "Testing…" : "Test") }.buttonStyle(SpelButtonStyle(kind: .secondary)).disabled(testing)
                        .help("Reads what your factories name, once, to see that the token works")
                    Button { remove() } label: { Text("Remove") }.buttonStyle(SpelButtonStyle(kind: .ghost))
                }
            } else {
                Button(action: save) { Text("Connect") }.buttonStyle(SpelButtonStyle(kind: .secondary, wide: true)).frame(width: 100).disabled(value.isEmpty)
            }
        }
        .onAppear { saved = model.fixture ? model.demoTokens.contains(key) : Secrets.get(key) != nil }
    }
    private func test() {
        testing = true; result = nil
        Task { result = await model.testToken(key); testing = false }
    }
    private func remove() {
        if model.fixture { model.demoTokens.remove(key) } else { Secrets.set(key, nil) }
        saved = false; result = nil
    }
    /// demo data saves nothing, also not in the Keychain
    private func save() {
        guard !value.isEmpty else { return }
        if model.fixture { model.demoTokens.insert(key); saved = true } else { saved = Secrets.set(key, value) }
        value = ""
        if saved && !model.fixture { test() }   // a fresh token is tried right away
    }
}

/// One input row (D5): the label, the field in its well, the button, and the status under the field.
private struct InputRow<Field: View, B: View>: View {
    let label: String
    let status: (ok: Bool, line: String)?
    @ViewBuilder var field: () -> Field
    @ViewBuilder var button: () -> B
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(label).font(.s15).foregroundStyle(Color.inkText).frame(width: 90, alignment: .leading)
                field().padding(.horizontal, 10).frame(height: 34).frame(maxWidth: .infinity, alignment: .leading).lifted(focused: false)
                button().fixedSize()
            }
            if let status {
                HStack(spacing: 6) {
                    PixelIcon(status.ok ? "check" : "warn", color: status.ok ? .done : .warn, size: 9)
                    Text(status.line).font(.s13).foregroundStyle(status.ok ? Color.done : Color.warn).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 102)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// The status pages you watch (D69): the providers, GitHub, and any Statuspage of your own. Public pages, no tokens.
private struct StatusSourcesRows: View {
    @EnvironmentObject private var model: AppModel
    @State private var address = ""
    @FocusState private var focused: Bool
    var body: some View {
        ForEach(model.statusSources) { s in row(s); RowDivider() }
        InputRow(label: "Add a page", status: nil) {
            TextField("", text: $address, prompt: Text("status.example.com").foregroundStyle(Color.muted)).focused($focused)
                .font(.mono).textFieldStyle(.plain).onSubmit(add)
                .onChange(of: focused) { _, on in model.typing = on }
        } button: {
            Button(action: add) { Text("Add") }.buttonStyle(SpelButtonStyle(kind: .secondary, wide: true)).frame(width: 100).disabled(StatusSource.custom(address) == nil)
        }
    }

    private func row(_ s: StatusSource) -> some View {
        let builtIn = StatusSource.defaults.contains { $0.id == s.id }
        let line = s.runtime.map { "Factories on \($0 == "codex" ? "Codex" : "Claude") wait while it is down. " } ?? ""
        return FieldRow(title: s.name, text: line + s.page.replacingOccurrences(of: "https://", with: "")) {
            HStack(spacing: 8) {
                if !builtIn {
                    Button { model.updateStatusSources { $0.removeAll { $0.id == s.id } } } label: { Text("Remove") }.buttonStyle(SpelButtonStyle(kind: .ghost, size: .s))
                }
                Toggle(s.name, isOn: Binding(get: { s.on }, set: { v in model.updateStatusSources { l in if let k = l.firstIndex(where: { $0.id == s.id }) { l[k].on = v } } }))
                    .labelsHidden().toggleStyle(TactileToggleStyle())
            }
        }
    }

    private func add() {
        guard let s = StatusSource.custom(address), !model.statusSources.contains(where: { $0.id == s.id }) else { return }
        model.updateStatusSources { $0.append(s) }
        address = ""
    }
}

// MARK: Server room (D6)

/// How each server is reached and what it may fix itself (D6); its live state lives in the Server room building.
private struct EngineRoomSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// the server open on its page ("new" for adding one)
    @State private var open: String?
    @State private var importing = false
    init(open: String? = nil) { _open = State(initialValue: open) }

    var body: some View { content }

    @ViewBuilder private var content: some View {
        if let open {
            ServerPage(id: open == "new" ? nil : open) { withAnimation(.easeOut(duration: 0.2)) { self.open = nil } }
                .transition(.slide(from: .trailing, reduce: reduceMotion))
        } else {
            list.transition(.slide(from: .leading, reduce: reduceMotion))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                PixelIcon("layers", color: .muted)
                Text("Load, disk and alerts live in the Server room building.").font(.s13).foregroundStyle(Color.muted)
                Spacer(minLength: 0)
                Button { model.settingsOpen = false; model.controller.focusBuilding("engine") } label: { SpelLabel("Go to Server room", icon: "chev", iconColor: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
            }
            DevOpsCard()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    PixelIcon("server", color: .inkText)
                    Text("Servers · \(model.serverConfigs.count)").font(.s15b).foregroundStyle(Color.inkText)
                    Spacer(minLength: 0)
                    if !model.sshAliases.isEmpty {
                        Button { withAnimation(.easeOut(duration: 0.2)) { importing.toggle() } } label: { SpelLabel("From ~/.ssh/config", icon: "file", iconColor: .inkText) }
                            .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).help("Add the hosts of your ssh config in one go")
                    }
                    Button { withAnimation(.easeOut(duration: 0.2)) { open = "new" } } label: { SpelLabel("Add", icon: "plus", iconColor: .inkText) }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                }
                .padding(14)
                if importing { SSHImportCard { importing = false }.padding(.horizontal, 14).padding(.bottom, 12) }
                if model.serverConfigs.isEmpty {
                    Text("No servers yet: the Server room says “not connected”.").font(.s13).foregroundStyle(Color.muted).padding(.horizontal, 14).padding(.bottom, 14)
                } else {
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 18, height: 1)
                        Eyebrow("Name").frame(width: 110, alignment: .leading)
                        Eyebrow("Kind").frame(width: 76, alignment: .leading)
                        Eyebrow("Reached as").frame(maxWidth: .infinity, alignment: .leading)
                        Eyebrow("May fix itself").frame(width: 110, alignment: .leading)
                        Color.clear.frame(width: 28, height: 1)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 4)
                    ForEach(model.serverConfigs) { c in
                        RowDivider()
                        ServerListRow(config: c) { withAnimation(.easeOut(duration: 0.2)) { open = c.id } }
                    }
                }
            }
            .spelCard(pad: 0)
            WhatWeCheckCard()
        }
    }
}

/// The DevOps agent: on or off, its runtime and rhythm, and what wakes it.
private struct DevOpsCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let d = model.projectSettings.devops
        VStack(alignment: .leading, spacing: 0) {
            // the same row as every switch in Settings (Henk)
            SwitchRow("DevOps agent", "Fixes what you allow on your servers, and asks the rest.",
                      isOn: Binding(get: { d.enabled }, set: { v in model.updateDevOps { $0.enabled = v } }))
            if d.enabled {
                RowDivider()
                FieldRow(title: "Runtime") {
                    LiftedSegments(items: Heartbeat.Runtime.allCases.map { .init(id: $0, title: $0.label) }, selected: d.heartbeat.runtime) { r in model.updateDevOps { $0.heartbeat.runtime = r } }
                }
                if d.heartbeat.runtime == .codex {
                    HStack(alignment: .top, spacing: 8) {
                        PixelIcon("warn", color: .warn, size: 9).padding(.top, 4)
                        Text("Codex has no allowlist, only its sandbox with network: it could ssh to a server itself and skip what that server allows. Claude Code is held to the ops tool.")
                            .font(.s13).foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
                RowDivider()
                FieldRow(title: "Look round", text: "Every day at these times.") { TimesField(times: d.heartbeat.times) { t in model.updateDevOps { $0.heartbeat.times = t } } }
                RowDivider()
                SwitchRow("Wake on an alert", "A server or site that goes down or warns wakes it at once; your answers wake it too.",
                          isOn: Binding(get: { d.wakeOnAlert }, set: { v in model.updateDevOps { $0.wakeOnAlert = v } }))
            }
        }
        .spelCard(pad: 0)
    }
}

/// One server in the list (D6): how it is reached and what it may fix itself; no live state here.
private struct ServerListRow: View {
    @EnvironmentObject private var model: AppModel
    let config: ServerConfig
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                PixelIcon("server", color: .muted)
                HStack(spacing: 4) {
                    Text(config.name).font(.spel(13, weight: .bold, design: .monospaced)).foregroundStyle(Color.inkText).lineLimit(1)
                    if !config.alertsOn { PixelIcon("close", color: .muted, size: 9).help("Alerts off") }
                }
                .frame(width: 110, alignment: .leading)
                Tag(config.kind.label).frame(width: 76, alignment: .leading)
                Text(config.host).font(.mono).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                Text(model.projectSettings.devops.enabled ? config.opsAutonomy.label : "Nothing").font(.s13).foregroundStyle(Color.inkText).lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                PixelIcon("chev", color: .inkText, size: 9).frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.raised)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.border, lineWidth: 2))
            }
            .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("\(config.name), \(config.kind.label), \(config.host)")
    }
}

/// A server on its own page: its connection (tested before saving), its alerts, the sites it serves, and what the
/// DevOps agent may do there.
private struct ServerPage: View {
    @EnvironmentObject private var model: AppModel
    let id: String?
    let back: () -> Void
    @State private var removing = false
    var body: some View {
        let config = id.flatMap { i in model.serverConfigs.first { $0.id == i } }
        VStack(alignment: .leading, spacing: 16) {
            PageCrumb(parent: "Server room", title: config?.name ?? "Add a server", icon: "server", back: back)
            if config == nil {
                HStack(alignment: .top, spacing: 10) {
                    PixelIcon("key", color: .inkText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password-free SSH only").font(.s15b).foregroundStyle(Color.inkText)
                        Text(code("The app runs ssh with your own keys and `~/.ssh/config`, in batch mode: it never asks for a password or passphrase, and stores none. Host keys are checked as in Terminal. The built-in check only reads load, disk and memory.")).prose()
                    }
                }
                .spelCard()
            }
            ServerForm(editing: .constant(config), onSaved: { saved in if config == nil { back() } else { _ = saved } }).id(config?.id ?? "new")
            if let c = config {
                RowCard(title: "Alerts") {
                    SwitchRow("Alerts for \(c.name)", "A notification when it goes down or warns (twice in a row), and when it is back.",
                              isOn: Binding(get: { c.alertsOn }, set: { v in model.updateServer(c.id) { $0.alerts = v } }))
                }
                RowCard(title: "Uptime and certificates") {
                    URLList(urls: c.siteURLs, checks: model.siteChecks) { urls in model.updateServer(c.id) { $0.urls = urls.isEmpty ? nil : urls } }
                }
                RowCard(title: "What the DevOps agent may fix itself") {
                    FieldRow(title: "May", text: c.opsAutonomy.explanation) {
                        LiftedSegments(items: OpsAutonomy.allCases.map { .init(id: $0, title: $0.label) }, selected: c.opsAutonomy) { a in model.updateServer(c.id) { $0.autonomy = a } }
                    }
                }
                HStack(spacing: 8) {
                    Spacer()
                    if removing {
                        Text("Remove \(c.name)?").font(.s13).foregroundStyle(Color.muted)
                        Button("Keep") { removing = false }.buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                        Button("Remove") { model.remove(c.id); back() }.buttonStyle(SpelButtonStyle(kind: .danger, size: .s))
                    } else {
                        Button { removing = true } label: { Text("Remove server") }.buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                    }
                }
            }
        }
    }
}

/// The public addresses a server serves: each is checked for an answer and for its TLS certificate.
private struct URLList: View {
    @EnvironmentObject private var model: AppModel
    let urls: [String]
    var checks: [String: SiteCheck] = [:]
    let change: ([String]) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(urls, id: \.self) { u in
                let c = checks[u]
                FieldRow(title: u, text: c.map { "\($0.detail) · \($0.checkedAt.ago)" } ?? "not checked yet") {
                    Button { change(urls.filter { $0 != u }) } label: { Text("Stop") }.buttonStyle(SpelButtonStyle(kind: .ghost, size: .s)).help("Stop checking \(u)")
                }
                RowDivider()
            }
            // the server page's one form style: the label above its field, as in Connection (Henk)
            VStack(alignment: .leading, spacing: 6) {
                Text("Add an address").font(.s13m).foregroundStyle(Color.inkText)
                HStack(spacing: 10) {
                    TextField("https://example.com/health", text: $draft).focused($focused).textFieldStyle(.plain).font(.mono).onSubmit(add)
                        .onChange(of: focused) { _, on in model.typing = on }
                        .padding(.horizontal, 10).frame(height: 34).lifted(focused: focused)
                    Button("Add") { add() }.buttonStyle(SpelButtonStyle(kind: .secondary, wide: true)).frame(width: 100).disabled(normalized == nil)
                }
                Text("An address that does not answer, or a certificate that expires within 14 days, is an alert.").prose()
            }
            .padding(14)
        }
    }
    private var normalized: String? {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: t.contains("://") ? t : "https://" + t), u.scheme == "https" || u.scheme == "http", u.host != nil else { return nil }
        return u.absoluteString
    }
    private func add() {
        guard let n = normalized, !urls.contains(n) else { return }
        change(urls + [n]); draft = ""
    }
}

/// Add a server, or edit one. It can only be saved once a test has logged in without a password, with exactly what
/// is in the form.
private struct ServerForm: View {
    @EnvironmentObject private var model: AppModel
    @Binding var editing: ServerConfig?
    var onSaved: ((ServerConfig) -> Void)? = nil
    @State private var host = ""
    @State private var name = ""
    @State private var check = ""
    @State private var kind: ServerKind = .server
    @State private var testing = false
    @State private var result: ServerProbe.Result?
    /// host and check the result belongs to: change either and it needs a new test
    @State private var tested: (host: String, check: String)?
    @FocusState private var focus: Field?
    enum Field { case host, name, check }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var trimmedCheck: String { check.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// a name from the host: "deploy@web-01.example.com" → "web-01"
    private var suggestedName: String {
        let h = trimmedHost.split(separator: "@").last.map(String.init) ?? trimmedHost
        return h.split(separator: ".").first.map(String.init) ?? h
    }
    private var testIsCurrent: Bool { tested.map { $0.host == trimmedHost && $0.check == trimmedCheck } ?? false }
    private var canSave: Bool { testIsCurrent && result?.reached == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Connection")
            field("Host", focused: .host, hint: "What you would type after `ssh`: `user@host`, or a Host alias from `~/.ssh/config`.") {
                TextField("deploy@web-01.example.com", text: $host).focused($focus, equals: .host).font(.mono)
            }
            field("Name", focused: .name, hint: "On its rack in the Server room.") {
                TextField(suggestedName.isEmpty ? "web-01" : suggestedName, text: $name).focused($focus, equals: .name).font(.mono)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Kind").font(.s13m).foregroundStyle(Color.inkText)
                LiftedSegments(items: ServerKind.allCases.map { .init(id: $0, title: $0.label) }, selected: kind) { kind = $0 }
                Text(kind == .server ? "A machine you run." : kind == .deploy ? "A site or app you ship to." : "Something that runs at night: a backup.")
                    .font(.s13).foregroundStyle(Color.muted)
            }
            field("Own check (optional)", focused: .check, hint: "Runs instead of the built-in check. Exit 0 is OK, 1 a warning, anything else down; its first line is shown.") {
                TextField("systemctl is-active --quiet nginx && echo nginx up", text: $check).focused($focus, equals: .check).font(.mono)
            }
            HStack(spacing: 10) {
                Button { runTest() } label: { SpelLabel(testing ? "Testing…" : "Test connection", icon: "pulse", iconColor: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).disabled(testing || !ServerConfig.validHost(host))
                Button { save() } label: { Text(editing == nil ? "Add server" : "Save changes") }
                    .buttonStyle(SpelButtonStyle(kind: .primary, size: .s)).disabled(!canSave)
                    .help(canSave ? "" : "Test the connection first: it must log in without a password.")
                Spacer()
            }
            if let r = result, testIsCurrent { TestResult(result: r, host: trimmedHost) }
            else if !trimmedHost.isEmpty, !ServerConfig.validHost(host) {
                HStack(spacing: 6) { PixelIcon("sq", color: .stuck, size: 9); Text("A host has no spaces and does not start with a dash.").font(.s13).foregroundStyle(Color.stuck) }
            }
        }
        .spelCard(pad: 16)
        .textFieldStyle(.plain)
        .onChange(of: focus) { _, f in model.typing = f != nil }
        .onAppear {
            if let h = model.debugTestHost { model.debugTestHost = nil; host = h; runTest() }
            guard let e = editing else { return }
            host = e.host; name = e.name; kind = e.kind; check = e.check ?? ""
        }
    }

    /// A labelled input in its well; focus shows a white edge.
    private func field<C: View>(_ label: String, focused: Field, hint: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.s13m).foregroundStyle(Color.inkText)
            content().padding(.horizontal, 10).frame(height: 34).lifted(focused: focus == focused)
            Text(code(hint)).prose()
        }
    }

    private var config: ServerConfig {
        let n = name.trimmingCharacters(in: .whitespaces)
        return ServerConfig(id: editing?.id ?? UUID().uuidString, name: n.isEmpty ? suggestedName : n, host: trimmedHost, kind: kind,
                            check: trimmedCheck.isEmpty ? nil : trimmedCheck,
                            alerts: editing?.alerts, autonomy: editing?.autonomy, urls: editing?.urls)
    }

    private func runTest() {
        let c = config, key = (host: trimmedHost, check: trimmedCheck)
        testing = true; result = nil
        Task {
            let r = await model.test(c)
            testing = false
            result = r; tested = key
        }
    }

    private func save() {
        guard canSave else { return }
        let c = config
        model.save(c)
        result = nil; tested = nil
        onSaved?(c)
    }
}

/// What a test found: logged in (and what the check saw), or why not and what to do about it.
private struct TestResult: View {
    let result: ServerProbe.Result
    let host: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.reached {
                let c: Color = result.state == .ok ? .done : result.state == .warn ? .warn : .stuck
                HStack(spacing: 6) { PixelIcon(result.state == .ok ? "check" : "warn", color: c, size: 9); Text("Logged in without a password · \(result.detail)").foregroundStyle(c) }
            } else {
                HStack(spacing: 6) { PixelIcon("sq", color: .stuck, size: 9); Text(result.detail.prefix(1).uppercased() + result.detail.dropFirst()).foregroundStyle(Color.stuck) }
                if result.needsKey {
                    Text("Put your public key on the server once, from Terminal (it asks for the password there, not here):")
                        .font(.s13).foregroundStyle(Color.muted)
                    Text("ssh-copy-id \(host)").font(.mono).textSelection(.enabled).spelWell(pad: 8)
                }
            }
        }
        .font(.s13m)
    }
}

/// What the Server room checks, how often, and when it alerts: said once, plainly.
private struct WhatWeCheckCard: View {
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    PixelIcon("eye", color: .inkText)
                    Text("What we check").font(.s15b).foregroundStyle(Color.inkText)
                    Spacer(minLength: 0)
                    PixelIcon(open ? "chevd" : "chev", color: .muted, size: 9)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 5) {
                    bullet("Every minute, over ssh in batch mode with your own keys and `~/.ssh/config`. No passwords; nothing is installed.")
                    bullet("The built-in check only reads: a warning at a root disk \(ServerProbe.diskWarn)% full, a load of \(String(format: "%.1f", ServerProbe.loadWarn)) per core, or under \(Int(ServerProbe.memoryFreeWarn * 100))% memory free. No answer is down.")
                    bullet("An alert after two bad checks in a row, so a hiccup stays quiet; another when it is fine again.")
                    bullet("A check of your own: exit 0 is fine, 1 a warning, anything else down; its first line is the detail.")
                    bullet("Sites every 5 minutes: no answer, or a certificate that expires within \(SiteCheck.certWarnDays) days, is an alert.")
                }
                .font(.s13).foregroundStyle(Color.muted)
            }
        }
        .spelCard()
    }
    private func bullet(_ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("·"); Text(code(t)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 560, alignment: .leading) }
    }
}

/// The hosts of your ssh config that are not on the Server room yet, ticked; Add makes each a server (checked at once).
private struct SSHImportCard: View {
    @EnvironmentObject private var model: AppModel
    let done: () -> Void
    @State private var ticked: Set<String> = []
    var body: some View {
        let known = Set(model.serverConfigs.map(\.host))
        let fresh = model.sshAliases.filter { !known.contains($0) }
        VStack(alignment: .leading, spacing: 8) {
            Text(fresh.isEmpty ? "Every host in ~/.ssh/config is on the Server room already." : "Hosts in ~/.ssh/config: switch on the ones to watch. Each is checked with your keys straight away.").prose()
            ForEach(fresh, id: \.self) { h in
                HStack {
                    Text(h).font(.mono).foregroundStyle(Color.inkText)
                    Spacer()
                    Toggle(h, isOn: Binding(get: { ticked.contains(h) }, set: { on in if on { ticked.insert(h) } else { ticked.remove(h) } }))
                        .labelsHidden().toggleStyle(TactileToggleStyle())
                }
            }
            HStack(spacing: 8) {
                Button { model.importServers(fresh.filter { ticked.contains($0) }); done() } label: { Text("Add \(ticked.count) server\(ticked.count == 1 ? "" : "s")") }
                    .buttonStyle(SpelButtonStyle(kind: .primary, size: .s)).disabled(ticked.isEmpty)
                Button("Cancel", action: done).buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
            }
        }
        .spelWell(pad: 12)
    }
}

// MARK: Projects (D10, D1)

/// The projects as a short list (factories first); a project opens on a short page of its own. The default team, for
/// every factory that does not have its own, is at the end (D1: it comes after you have a factory).
private struct ProjectsSettings: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: String?
    init(open: String? = nil) { _open = State(initialValue: open) }

    var body: some View { content }

    @ViewBuilder private var content: some View {
        if let open {
            ProjectPage(root: open) { withAnimation(.easeOut(duration: 0.2)) { self.open = nil } }
                .transition(.slide(from: .trailing, reduce: reduceMotion))
        } else {
            list.transition(.slide(from: .leading, reduce: reduceMotion))
        }
    }

    private var list: some View {
        let all = model.projectCandidates
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("Every project folder with recent chats gets a floor. Keep one there, or switch it on as a factory on its floor.").prose()
                Spacer(minLength: 8)
                Button { choose() } label: { SpelLabel("Add folder…", icon: "folder", iconColor: .inkText) }.buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
            }
            group("Factories", all.filter(\.factory))
            group("On campus", all.filter { $0.pinned && !$0.factory })
            group("Recent", all.filter { !$0.pinned && !$0.factory })
            group("Hidden", model.projectSettings.hidden.filter { r in !all.contains { $0.root == r } }
                .map { (root: $0, name: WorldBuilder.pretty(($0 as NSString).lastPathComponent), pinned: false, factory: false) })
            VStack(alignment: .leading, spacing: 8) {
                Text("Who a factory's CEO may call in, and how many of each at once. Every factory follows this team until you give its floor its own, on its Team tab.").prose()
                TeamRoster(project: nil)
            }
            .id("team")
        }
    }

    @ViewBuilder private func group(_ title: String, _ items: [(root: String, name: String, pinned: Bool, factory: Bool)]) -> some View {
        if !items.isEmpty {
            RowCard(title: "\(title) · \(items.count)") {
                ForEach(Array(items.enumerated()), id: \.element.root) { k, c in
                    if k > 0 { RowDivider() }
                    Button { withAnimation(.easeOut(duration: 0.2)) { open = c.root } } label: {
                        HStack(spacing: 12) {
                            Socket(size: 32) {
                                if let logo = model.world.projects.first(where: { $0.root == c.root })?.logo ?? ProjectLogo.find(root: c.root) { ProjectLogoView(path: logo, size: 20) }
                                else { PixelIcon("floor", color: .muted) }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.s15).foregroundStyle(Color.inkText)
                                Text(c.root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.mono12).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            if c.factory, let hb = model.projectSettings.entry(c.root)?.heartbeat { Text(hb.summary).font(.s13).foregroundStyle(Color.muted) }
                            PixelIcon("chev", color: .muted, size: 9)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(CardPressStyle())
                    .contextMenu { PathMenu(path: c.root) }
                }
            }
        }
    }

    /// A project that is not on the campus right now: pick its folder (or one inside it; the project is the folder under
    /// ~/Projects or the git root, as everywhere, D37). It is kept on the campus.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Add"; panel.message = "Choose a project folder to keep on the campus"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Projects")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let key = ProjectResolver().resolve(url.path)
        guard !key.isChat else { model.status = "That folder is not a project."; return }
        model.setPinned(key.root, on: true)
        withAnimation(.easeOut(duration: 0.2)) { open = key.root }
    }
}

/// One project on its own page (D10): short. Its folder, where it lives, Factory on or off, and a way to the floor for
/// the rest (rhythm, autonomy and team live there, D2).
private struct ProjectPage: View {
    @EnvironmentObject private var model: AppModel
    let root: String
    let back: () -> Void
    var body: some View {
        let e = model.projectSettings.entry(root), factory = e?.factory ?? false, pinned = (e?.pinned ?? false) || factory
        let hidden = model.projectSettings.hidden.contains(root)
        let name = model.projectCandidates.first { $0.root == root }?.name ?? WorldBuilder.pretty((root as NSString).lastPathComponent)
        let project = model.world.projects.first { $0.root == root }
        let place = project.flatMap { p in model.world.building(p.provider).flatMap { b in b.projects.firstIndex { $0.id == p.id }.map { "\(p.provider.displayName) tower · floor \($0 + 1)" } } }
        VStack(alignment: .leading, spacing: 16) {
            PageCrumb(parent: "Projects", title: name, icon: "floor", logo: project?.logo ?? ProjectLogo.find(root: root), back: back)
            VStack(alignment: .leading, spacing: 0) {
                FieldRow(title: "Folder") {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)]) } label: { SpelLabel("Show in Finder", icon: "folder", iconColor: .inkText) }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                }
                Text(root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.mono).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.top, -6).padding(.bottom, 10)
                    .contextMenu { PathMenu(path: root) }
                RowDivider()
                FieldRow(title: "Lives in", text: place ?? (hidden ? "Hidden from the campus" : "Not on the campus now: no recent chats")) {
                    Button { go(project, tab: nil) } label: { SpelLabel("Go there", icon: "chev", iconColor: .inkText) }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).disabled(project == nil)
                }
                RowDivider()
                SwitchRow("Factory", "A CEO runs this floor on a schedule. Switching on writes nothing; setting it up shows each file first.",
                          isOn: Binding(get: { factory }, set: { model.setFactory(root, on: $0) }))
                if !factory {
                    RowDivider()
                    SwitchRow("Keep when quiet", "Its floor stays after 8 hours without chats.",
                              isOn: Binding(get: { pinned }, set: { v in if v { model.setHidden(root, on: false) }; model.setPinned(root, on: v) }))
                }
            }
            .spelCard(pad: 0)
            if factory {
                HStack(spacing: 12) {
                    PixelIcon("pulse", color: .inkText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rhythm, autonomy and team").font(.s15b).foregroundStyle(Color.inkText)
                        Text("Set them on the floor itself, on the CEO and Team tabs.").font(.s13).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 8)
                    Button { go(project, tab: .ceo) } label: { SpelLabel("Open the floor", icon: "chev", iconColor: .inkText) }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).disabled(project == nil)
                }
                .spelCard()
            }
            // a factory has no Remove: one sentence says how, instead of a button that never works (UX review 26 Nov)
            if factory && !hidden {
                Text("A factory always has a floor. Switch Factory off to remove it.").font(.s13).foregroundStyle(Color.muted)
            } else {
                HStack(spacing: 10) {
                    Button { model.setHidden(root, on: !hidden) } label: { Text(hidden ? "Show on campus again" : "Remove from campus") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                    Text("The folder and its chats stay on your Mac.").font(.s13).foregroundStyle(Color.muted)
                }
            }
        }
    }

    private func go(_ p: Project?, tab: FactoryOverview.Tab?) {
        guard let p else { return }
        if let tab { model.factoryTabs[p.id] = tab }
        model.settingsOpen = false
        model.controller.enterFloor(p.id)
    }
}

// MARK: Privacy

private struct PrivacySettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What Meatproxy reads, what it contacts, and what your agents send. Nothing goes to Tuinstra or anyone else: there is no analytics and no account.").prose()
            RowCard(title: "Read on this Mac") {
                item("chat", "Sessions", "Read-only from the files Claude Code and Codex already keep: `~/.claude/projects` and `~/.codex/sessions`. The app never writes there.")
                RowDivider()
                item("floor", "Projects", "Your campus and factory settings, in `~/Library/Application Support/Meatproxy/projects.json`. The app reads a factory's `factory/` folder; it writes only your answers and ideas there, and the starter files you approve.")
                RowDivider()
                item("server", "Servers", "Host names and kinds only, in `~/Library/Application Support/Meatproxy/servers.json`. No passwords, no keys: ssh uses yours.")
            }
            RowCard(title: "Contacted over the network") {
                item("layers", "Status pages", "Every few minutes: the status pages in Sources (Claude, OpenAI and GitHub by default). Only a read of their public status.")
                RowDivider()
                item("branch", "GitHub", "With your own `gh` login: the newest CI run on main and merged pull requests of each project's repo. Read only.")
                RowDivider()
                item("pulse", "Sentry and Tracker", "Only when you add a token and a factory names a project: new issues and stories, read with that token.")
                RowDivider()
                item("terminal", "Your servers", "ssh in batch mode, with your keys and `~/.ssh/config`. The built-in check reads load, disk and memory and changes nothing.")
            }
            RowCard(title: "Sent to the model") {
                item("person", "A factory's CEO", "Runs as `claude -p` or `codex exec` in the project's folder. What it reads there (code, files, your answers) goes to Anthropic or OpenAI, as with any Claude Code or Codex session. Logs stay in `~/Library/Application Support/Meatproxy/heartbeats`.")
            }
            RowCard(title: "Tokens and screenshots") {
                item("key", "In the Keychain", "Sentry and Tracker tokens are kept in your login Keychain, never in a file or a log.")
                RowDivider()
                item("eye", "Screenshots", "Start the app with `--fixture` to show made-up data, safe to share.")
            }
        }
    }
    private func item(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PixelIcon(icon, color: .muted).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.s15).foregroundStyle(Color.inkText)
                Text(code(text)).prose()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: parts

extension View {
    /// Settings prose: muted 13, wrapping, at most 560 wide so a line stays readable (Henk)
    func prose() -> some View {
        font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 560, alignment: .leading)
    }
}

/// Prose with its `paths` and commands in mono, each kept on one line: a path never breaks in the middle (Henk).
func code(_ s: String) -> AttributedString {
    var out = AttributedString()
    for (k, part) in s.components(separatedBy: "`").enumerated() {
        if k % 2 == 1 {
            // no break inside: a no-break space for a space, a word joiner after every / . and -
            var glued = ""
            for ch in part {
                glued.append(ch == " " ? "\u{00A0}" : ch)
                if "/.-".contains(ch) { glued.append("\u{2060}") }
            }
            var a = AttributedString(glued); a.font = .mono; out += a
        } else { out += AttributedString(part) }
    }
    return out
}

/// A path's own right-click menu: where it is, and the path itself.
struct PathMenu: View {
    let path: String
    var body: some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        Button("Copy Path") { AppModel.copy(path) }
    }
}

/// Back to the list a page came from, and where you are: "‹ Projects / Pebble Puzzles".
private struct PageCrumb: View {
    let parent: String, title: String, icon: String
    var logo: String? = nil
    let back: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: back) { SpelLabel(parent, icon: "back", key: "⌘[", iconColor: .inkText) }
                .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).keyboardShortcut("[", modifiers: .command)
            Text("/").font(.s15).foregroundStyle(Color.muted)
            Socket(size: 32) {
                if let logo { ProjectLogoView(path: logo, size: 20) } else { PixelIcon(icon, color: .inkText) }
            }
            Text(title).font(.s19).foregroundStyle(Color.inkText).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// A switch with its name and one line on what it does.
private struct SwitchRow: View {
    let title: String, text: String
    @Binding var isOn: Bool
    var disabled = false
    init(_ title: String, _ text: String, isOn: Binding<Bool>, disabled: Bool = false) { self.title = title; self.text = text; self._isOn = isOn; self.disabled = disabled }
    var body: some View {
        FieldRow(title: title, text: text, disabled: disabled) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(TactileToggleStyle()).disabled(disabled)
        }
    }
}
