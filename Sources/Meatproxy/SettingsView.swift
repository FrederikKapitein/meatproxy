import SwiftUI
import FactoryCore
import FactoryCollector

/// The settings: a drawer from the right edge of the window, over the dimmed world (not a window of their own), the
/// full height. The Server room's servers, and what the app reads and keeps. ⌘, or the gear in the top bar opens it;
/// Esc, the cross or a click on the world beside it closes it.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general = "General", projects = "Projects", engine = "Server room", privacy = "Privacy"
        var id: String { rawValue }
        var icon: String {
            switch self { case .general: "slider.horizontal.3"; case .projects: "building.2"; case .engine: "server.rack"; case .privacy: "lock.shield" }
        }
    }

    /// The drawer's width: room for a server row and the form, never more than half the window plus a bit.
    static func width(_ window: CGFloat) -> CGFloat { min(600, max(460, window * 0.42)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Settings").font(.system(size: 20, weight: .bold))
                if model.fixture { Text("Demo data: nothing is saved").font(.system(size: 11)).foregroundStyle(Color.muted).padding(.leading, 8) }
                Spacer()
                Button { close() } label: {
                    HStack(spacing: 5) { KeyCap("esc"); Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }.padding(.horizontal, 6).frame(height: 26)
                }
                .buttonStyle(TactileButtonStyle(kind: .neutral))
                .keyboardShortcut(.cancelAction).help("Close (Esc)")
            }
            .padding(.horizontal, 24).padding(.top, 44)
            HStack(spacing: 12) {
                LiftedSegments(items: Section.allCases.map { .init(id: $0, title: $0.rawValue, icon: $0.icon) }, selected: section,
                               fontSize: 12.5, padding: EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11)) { section = $0 }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
            Divider().overlay(Color.raised)
            ScrollViewReader { scroll in
                ScrollView {
                    Group {
                        switch section {
                        case .general: GeneralSettings()
                        case .engine: EngineRoomSettings()
                        case .projects: ProjectsSettings()
                        case .privacy: PrivacySettings()
                        }
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .id(section)
                }
                .onChange(of: section) { _, new in DispatchQueue.main.async { scroll.scrollTo(new, anchor: .top) } }
                .onChange(of: model.settingsScrollTo) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation { scroll.scrollTo(id, anchor: .top) }; model.settingsScrollTo = nil }
                }
                .onAppear {
                    if model.settingsAtProjects { section = .projects; model.settingsAtProjects = false }
                    if let p = model.settingsPage {
                        section = p.hasPrefix("server:") || p == "engine" ? .engine : p.hasPrefix("project:") ? .projects : .general
                        if p == "engine" || p == "general" { model.settingsPage = nil }
                    }
                    if model.settingsAtForm { section = .engine }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Rectangle().fill(.ultraThinMaterial))
        .background(Color.surface.opacity(0.92))
        .overlay(alignment: .leading) { Rectangle().fill(Color.raised).frame(width: 1) }
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
    }

    private func close() { withAnimation(.easeOut(duration: 0.2)) { model.settingsOpen = false } }
}

// MARK: General

/// The switches that are not about one project or one server.
private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var testSent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle("General", "The campus, the heartbeat of every factory, and how alerts reach you.")
            SettingsCard("Campus") {
                SwitchRow("Chats floor", "Sessions outside a project share one floor, Chats.",
                          isOn: Binding(get: { model.projectSettings.showChats }, set: { model.setShowChats($0) }))
                SwitchRow("Meme mode", "Yes and No read LGTM and Not today. Send yes and Send no stay as they are.", isOn: $model.memeMode)
            }
            SettingsCard("Heartbeat") {
                SwitchRow("Pause all factories", "The kill switch: no heartbeat starts a CEO or the DevOps agent, and running ones are stopped.",
                          isOn: Binding(get: { model.projectSettings.pauseAll }, set: { model.setPauseAll($0) }))
                SwitchRow("Heartbeat when closed", "A launch agent keeps the heartbeat going while Meatproxy is closed. Off: only while the app runs.",
                          isOn: Binding(get: { model.projectSettings.heartbeatWhenClosed }, set: { model.setHeartbeatWhenClosed($0) }))
            }
            SettingsCard("Wake-up sources") {
                TokenRow(key: .sentry, text: "A token with read access to issues (Sentry › Settings › Auth tokens). Factories name their project in contract.yml.")
                TokenRow(key: .tracker, text: "A read token from Tracker › Account settings › MCP access. Kept in the Keychain, never in a file.")
            }
            SettingsCard("Status pages") {
                StatusSourcesRows()
            }
            SettingsCard("Alerts") {
                SwitchRow("Notifications on this Mac", "A server or site that goes down or warns, and comes back. Push to your phone comes with the iPhone app.",
                          isOn: Binding(get: { model.projectSettings.devops.notify }, set: { v in model.updateDevOps { $0.notify = v } }))
                HStack {
                    Text(testSent ? "Sent: look top right." : "See how an alert looks.").font(.system(size: 12)).foregroundStyle(Color.muted)
                    Spacer()
                    Button { model.alerts.test(); testSent = true } label: { Label("Send a test", systemImage: "bell") }
                        .buttonStyle(SettingsButton()).disabled(!model.projectSettings.devops.notify)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }
}

// MARK: Server room

/// The DevOps agent on top, then the servers as a short list; a server opens on a page of its own.
private struct EngineRoomSettings: View {
    @EnvironmentObject private var model: AppModel
    /// the server open on its page ("new" for adding one)
    @State private var open: String?

    var body: some View {
        content.onAppear {
            if model.settingsAtForm { model.settingsAtForm = false; open = "new" }
            if let s = model.settingsPage, s.hasPrefix("server:") { open = String(s.dropFirst(7)); model.settingsPage = nil }
        }
    }

    @ViewBuilder private var content: some View {
        if let open {
            ServerPage(id: open == "new" ? nil : open) { self.open = nil }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            list.transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle("Server room", "Your servers and sites, checked over SSH every minute, with alerts and a DevOps agent that keeps an eye on them.")
            DevOpsCard()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow("Servers · \(model.serverConfigs.count)")
                    Spacer()
                    if !model.serverConfigs.isEmpty && !model.fixture {
                        Button { model.checkServers() } label: {
                            HStack(spacing: 6) {
                                if model.checkingServers { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise") }
                                Text(model.checkingServers ? "Checking…" : "Check now")
                            }
                        }.buttonStyle(SettingsButton()).disabled(model.checkingServers)
                    }
                    Button { withAnimation(.easeOut(duration: 0.2)) { open = "new" } } label: { Label("Add server", systemImage: "plus") }.buttonStyle(SettingsButton())
                }
                if model.serverConfigs.isEmpty {
                    Text("No servers yet: the Server room says “not connected”.").font(.system(size: 13)).foregroundStyle(Color.muted).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(spacing: 0) {
                    ForEach(Array(model.serverConfigs.enumerated()), id: \.element.id) { k, c in
                        if k > 0 { Divider().overlay(Color.divider) }
                        Button { withAnimation(.easeOut(duration: 0.2)) { open = c.id } } label: { ServerListRow(config: c) }.buttonStyle(.plain)
                    }
                }
                .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
            }
            SettingsCard("Backups") {
                HStack {
                    Text("Watching the backup jobs on your backup server comes later.").font(.system(size: 12.5)).foregroundStyle(Color.muted)
                    Spacer()
                    Text("LATER").font(.system(size: 9.5, weight: .bold)).tracking(0.8).padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.border)).foregroundStyle(Color.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
    }
}

/// The DevOps agent: on or off, its runtime and rhythm, and what wakes it.
private struct DevOpsCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let d = model.projectSettings.devops
        SettingsCard("DevOps agent") {
            SwitchRow("DevOps agent", "Watches servers, uptime and certificates. What it may fix on its own is set per server.",
                      isOn: Binding(get: { d.enabled }, set: { v in model.updateDevOps { $0.enabled = v } }))
            if d.enabled {
                ChoiceRow("Runtime") {
                    LiftedSegments(items: Heartbeat.Runtime.allCases.map { .init(id: $0, title: $0.label) }, selected: d.heartbeat.runtime,
                                   fontSize: 11.5, padding: segInset) { r in model.updateDevOps { $0.heartbeat.runtime = r } }
                }
                if d.heartbeat.runtime == .codex {
                    Label("Codex has no allowlist, only its sandbox with network: it could ssh to a server itself and skip what that server allows. Claude Code is held to the ops tool.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
                ChoiceRow("Look round") {
                    TimesField(times: d.heartbeat.times) { t in model.updateDevOps { $0.heartbeat.times = t } }
                    Text("every day").font(.system(size: 12)).foregroundStyle(Color.muted)
                }
                SwitchRow("Wake on an alert", "A server or site that goes down or warns wakes it at once; your answers wake it too.",
                          isOn: Binding(get: { d.wakeOnAlert }, set: { v in model.updateDevOps { $0.wakeOnAlert = v } }))
            }
        }
    }
}

/// One server in the list: its light, name, kind and what the last check saw.
private struct ServerListRow: View {
    @EnvironmentObject private var model: AppModel
    let config: ServerConfig
    var body: some View {
        let s = model.server(config.id)
        let color: Color = s.map { $0.state == .down ? .stuck : $0.state == .warn ? .warn : .done } ?? .muted
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 9, height: 9).shadow(color: color.opacity(s == nil ? 0 : 0.7), radius: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(config.name).font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    Badge(config.kind.label)
                    if !config.alertsOn { Image(systemName: "bell.slash").font(.system(size: 10)).foregroundStyle(Color.muted).help("Alerts off") }
                }
                Text(s?.detail ?? (model.checkingServers ? "checking…" : "not checked yet")).font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(s?.state == .ok ? Color.muted : color).lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.projectSettings.devops.enabled { Text(config.opsAutonomy.label).font(.system(size: 11)).foregroundStyle(Color.muted) }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
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
        VStack(alignment: .leading, spacing: 18) {
            BackButton("Server room", action: back)
            PageTitle(config?.name ?? "Add a server", config?.host ?? "Any server you reach with ssh without a password.")
            if config == nil {
                Note(icon: "key.horizontal", title: "Password-free SSH only") {
                    Text("The app runs ssh with your own keys and ~/.ssh/config, in batch mode: it never asks for a password or passphrase, and stores none. Host keys are checked as in Terminal. The built-in check only reads load, disk and memory.")
                }
            }
            ServerForm(editing: .constant(config), onSaved: { saved in if config == nil { back() } else { _ = saved } }).id(config?.id ?? "new")
            if let c = config {
                SettingsCard("Alerts") {
                    SwitchRow("Alerts for \(c.name)", "A notification when it goes down or warns (twice in a row), and when it is back.",
                              isOn: Binding(get: { c.alertsOn }, set: { v in model.updateServer(c.id) { $0.alerts = v } }))
                }
                SettingsCard("Uptime and certificates") {
                    URLList(urls: c.siteURLs, checks: model.siteChecks) { urls in model.updateServer(c.id) { $0.urls = urls.isEmpty ? nil : urls } }
                }
                SettingsCard("DevOps agent on \(c.name)") {
                    ChoiceRow("May") {
                        LiftedSegments(items: OpsAutonomy.allCases.map { .init(id: $0, title: $0.label) }, selected: c.opsAutonomy,
                                       fontSize: 11.5, padding: segInset) { a in model.updateServer(c.id) { $0.autonomy = a } }
                    }
                    Text(c.opsAutonomy.explanation).font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.bottom, 12)
                }
                HStack {
                    Spacer()
                    if removing {
                        Text("Remove \(c.name)?").font(.system(size: 12)).foregroundStyle(Color.muted)
                        Button("Keep") { removing = false }.buttonStyle(SettingsButton())
                        Button("Remove") { model.remove(c.id); back() }.buttonStyle(SettingsButton(tint: .stuck))
                    } else {
                        Button { removing = true } label: { Label("Remove server", systemImage: "trash") }.buttonStyle(SettingsButton())
                    }
                }
            }
        }
    }
}

/// The public addresses a server serves: each is checked for an answer and for its TLS certificate.
private struct URLList: View {
    let urls: [String]
    var checks: [String: SiteCheck] = [:]
    let change: ([String]) -> Void
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(urls, id: \.self) { u in
                HStack(spacing: 10) {
                    let c = checks[u]
                    let color: Color = c.map { $0.state == .down ? .stuck : $0.state == .warn ? .warn : .done } ?? .muted
                    Circle().fill(color).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Text(c.map { "\($0.detail) · \($0.checkedAt.ago)" } ?? "not checked yet").font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(c?.state == .ok || c == nil ? Color.muted : color).lineLimit(1)
                    }
                    Spacer()
                    IconButton(icon: "minus", help: "Stop checking \(u)") { change(urls.filter { $0 != u }) }
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                Divider().overlay(Color.divider)
            }
            HStack(spacing: 8) {
                TextField("https://example.com/health", text: $draft).textFieldStyle(.plain).font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 6).lifted(focused: false).onSubmit(add)
                Button("Add") { add() }.buttonStyle(SettingsButton()).disabled(normalized == nil)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Text("An address that does not answer, or a certificate that expires within 14 days, is an alert.")
                .font(.system(size: 11.5)).foregroundStyle(Color.muted).padding(.horizontal, 14).padding(.bottom, 12)
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
            field("Host", focused: .host, hint: "What you would type after ssh: user@host, or a Host alias from ~/.ssh/config.") {
                TextField("deploy@web-01.example.com", text: $host).focused($focus, equals: .host).font(.system(size: 13, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 14) {
                field("Name", focused: .name, hint: "On its rack in the Server room.") {
                    TextField(suggestedName.isEmpty ? "web-01" : suggestedName, text: $name).focused($focus, equals: .name).font(.system(size: 13, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kind").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.inkText)
                    LiftedSegments(items: ServerKind.allCases.map { .init(id: $0, title: $0.label) }, selected: kind, fontSize: 12.5,
                                   padding: EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14)) { kind = $0 }
                    Text(kind == .server ? "A machine you run." : kind == .deploy ? "A site or app you ship to." : "Something that runs at night: a backup.")
                        .font(.system(size: 11.5)).foregroundStyle(Color.muted)
                }
            }
            field("Own check (optional)", focused: .check, hint: "Runs instead of the built-in check. Exit 0 is OK, 1 a warning, anything else down; its first line is shown.") {
                TextField("systemctl is-active --quiet nginx && echo nginx up", text: $check).focused($focus, equals: .check).font(.system(size: 13, design: .monospaced))
            }
            HStack(spacing: 10) {
                Button { runTest() } label: {
                    HStack(spacing: 6) {
                        if testing { ProgressView().controlSize(.mini) } else { Image(systemName: "bolt.horizontal") }
                        Text(testing ? "Testing…" : "Test connection")
                    }.font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(SettingsButton()).disabled(testing || !ServerConfig.validHost(host))
                Button { save() } label: {
                    Text(editing == nil ? "Add server" : "Save changes").font(.system(size: 12.5, weight: .bold))
                }
                .buttonStyle(SettingsButton(primary: true)).disabled(!canSave)
                .help(canSave ? "" : "Test the connection first: it must log in without a password.")
                Spacer()
            }
            if let r = result, testIsCurrent { TestResult(result: r, host: trimmedHost) }
            else if !trimmedHost.isEmpty, !ServerConfig.validHost(host) {
                Label("A host has no spaces and does not start with a dash.", systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Color.stuck)
            }
        }
        .padding(18).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.divider))
        .textFieldStyle(.plain)
        .onAppear {
            if let h = model.debugTestHost { model.debugTestHost = nil; host = h; runTest() }
            guard let e = editing else { return }
            host = e.host; name = e.name; kind = e.kind; check = e.check ?? ""
        }
    }

    /// A labelled, lifted input (tactile-utility): an edge, a 2 px neutral ledge, a focus ring; it never travels.
    private func field<C: View>(_ label: String, focused: Field, hint: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.inkText)
            content().padding(.horizontal, 10).padding(.vertical, 8)
                .lifted(focused: focus == focused)
                .padding(.bottom, 2)
            Text(hint).font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
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
                Label { Text("Logged in without a password · \(result.detail)") } icon: { Image(systemName: "checkmark.circle.fill") }
                    .foregroundStyle(result.state == .ok ? Color.done : result.state == .warn ? Color.warn : Color.stuck)
            } else {
                Label { Text(result.detail.prefix(1).uppercased() + result.detail.dropFirst()) } icon: { Image(systemName: "xmark.octagon.fill") }
                    .foregroundStyle(Color.stuck)
                if result.needsKey {
                    Text("Put your public key on the server once, from Terminal (it asks for the password there, not here):")
                        .font(.system(size: 12)).foregroundStyle(Color.muted)
                    Text("ssh-copy-id \(host)").font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Color.ink, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.divider))
                }
            }
        }
        .font(.system(size: 12.5, weight: .semibold))
    }
}

// MARK: Projects

/// The projects as a short list (factories first); a project opens on a page of its own.
private struct ProjectsSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var open: String?

    var body: some View {
        content.onAppear {
            if let s = model.settingsPage, s.hasPrefix("project:") { open = String(s.dropFirst(8)); model.settingsPage = nil }
        }
    }

    @ViewBuilder private var content: some View {
        if let open {
            ProjectPage(root: open) { withAnimation(.easeOut(duration: 0.2)) { self.open = nil } }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            list.transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private var list: some View {
        let all = model.projectCandidates
        return VStack(alignment: .leading, spacing: 18) {
            PageTitle("Projects", "Every project folder with recent sessions gets a floor. Keep one there, or switch it on as a Dark Software Factory with a CEO on a heartbeat.")
            HStack {
                Spacer()
                Button { choose() } label: { Label("Add folder…", systemImage: "folder.badge.plus") }.buttonStyle(SettingsButton())
            }
            group("Factories", all.filter(\.factory))
            group("On campus", all.filter { $0.pinned && !$0.factory })
            group("Recent", all.filter { !$0.pinned && !$0.factory })
            group("Hidden", model.projectSettings.hidden.filter { r in !all.contains { $0.root == r } }
                .map { (root: $0, name: WorldBuilder.pretty(($0 as NSString).lastPathComponent), pinned: false, factory: false) })
        }
    }

    @ViewBuilder private func group(_ title: String, _ items: [(root: String, name: String, pinned: Bool, factory: Bool)]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("\(title) · \(items.count)")
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.root) { k, c in
                        if k > 0 { Divider().overlay(Color.divider) }
                        Button { withAnimation(.easeOut(duration: 0.2)) { open = c.root } } label: {
                            HStack(spacing: 10) {
                                ProjectLogoView(path: model.world.projects.first { $0.root == c.root }?.logo ?? ProjectLogo.find(root: c.root), size: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(.system(size: 13.5, weight: .semibold))
                                    Text(c.root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                if c.factory, let hb = model.projectSettings.entry(c.root)?.heartbeat { Text(hb.summary).font(.system(size: 11)).foregroundStyle(Color.muted) }
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
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

/// One project on its own page: on the campus or not, a factory or not, and a factory's heartbeat, wakes and limits.
private struct ProjectPage: View {
    @EnvironmentObject private var model: AppModel
    let root: String
    let back: () -> Void
    var body: some View {
        let e = model.projectSettings.entry(root), factory = e?.factory ?? false, pinned = (e?.pinned ?? false) || factory
        let name = model.projectCandidates.first { $0.root == root }?.name ?? WorldBuilder.pretty((root as NSString).lastPathComponent)
        let contract = model.world.projects.first { $0.root == root }?.factory?.contractVersion
        VStack(alignment: .leading, spacing: 18) {
            BackButton("Projects", action: back)
            PageTitle(name, root.replacingOccurrences(of: NSHomeDirectory(), with: "~"), mono: true)
            SettingsCard("On the campus") {
                SwitchRow("Dark Software Factory", "Its CEO's queue in factory/ shows on its floor, and its CEO runs on a heartbeat. Switching on creates no files.",
                          isOn: Binding(get: { factory }, set: { model.setFactory(root, on: $0) }))
                SwitchRow("Keep on campus", factory ? "A factory always stays on the campus." : "Its floor stays without recent sessions.",
                          isOn: Binding(get: { pinned }, set: { v in if v { model.setHidden(root, on: false) }; model.setPinned(root, on: v) }), disabled: factory)
                SwitchRow("Hide from campus", factory ? "A factory is never hidden: its questions must reach you." : "Its floor and sessions stay off the campus until you show it again. Nothing is deleted.",
                          isOn: Binding(get: { model.projectSettings.hidden.contains(root) }, set: { model.setHidden(root, on: $0) }), disabled: factory)
            }
            if factory {
                SettingsCard("Limits") {
                    SwitchRow("Allow Dark", "Off: its CEO runs Assistant or Hybrid at most, whatever the mandate says.",
                              isOn: Binding(get: { model.projectSettings.darkAllowed(root) }, set: { model.setDarkAllowed(root, on: $0) }))
                }
            }
            if factory, let f = model.world.projects.first(where: { $0.root == root })?.factory {
                if f.takesMandate { MandateCards(root: root) }
                else {
                    Note(icon: "doc.text", title: "Mandate needs contract v3") {
                        Text("This factory follows meatproxy-factory v\(f.contractVersion). Once its CEO declares version 3 in factory/contract.yml, you set here what it may do on its own, its role and your preferences.")
                    }
                }
            }
            if factory, let hb = e?.heartbeat {
                HeartbeatCards(hb: hb, factoryWakes: true, factory: model.world.projects.first { $0.root == root }?.factory) { change in model.updateHeartbeat(root, change) }
                HStack(spacing: 6) {
                    Eyebrow("Contract")
                    Text(contract.map { "meatproxy-factory v\($0)" } ?? "read when its floor is on the campus").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.muted)
                }
            }
        }
    }
}

/// A heartbeat as cards: when it beats, what else wakes it, and its limits (D47, D48).
private struct HeartbeatCards: View {
    let hb: Heartbeat
    /// a factory also wakes on your answers, ideas and a failed CI run
    let factoryWakes: Bool
    /// the factory, for its wake-up sources (contract v4, D61)
    var factory: Factory? = nil
    let update: (@escaping (inout Heartbeat) -> Void) -> Void

    private static let rhythms: [(Int, String)] = [(0, "At times"), (60, "Hourly"), (120, "Every 2 h"), (240, "Every 4 h")]
    /// the API-price caps a day (D61); spelled out, so the CI compiler need not infer them
    private static let capItems: [LiftedSegments<Int>.Item] = [
        .init(id: 0, title: "No cap"), .init(id: 5, title: "$5"), .init(id: 10, title: "$10"), .init(id: 20, title: "$20"), .init(id: 50, title: "$50"),
    ]

    var body: some View {
        SettingsCard("Heartbeat", trailing: AnyView(HStack(spacing: 6) {
            Text("Paused").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.muted)
            Toggle("Paused", isOn: Binding(get: { hb.paused }, set: { v in update { $0.paused = v } })).labelsHidden().toggleStyle(TactileToggleStyle())
        })) {
            ChoiceRow("Days") {
                LiftedSegments(items: [.init(id: Heartbeat.Days.weekdays, title: "Weekdays"), .init(id: .everyDay, title: "Every day")],
                               selected: hb.days, fontSize: 11.5, padding: segInset) { d in update { $0.days = d } }
            }
            ChoiceRow("Rhythm") {
                LiftedSegments(items: Self.rhythms.map { .init(id: $0.0, title: $0.1) }, selected: hb.everyMinutes ?? 0, fontSize: 11.5, padding: segInset) { m in
                    update { $0.everyMinutes = m == 0 ? nil : m }
                }
            }
            if hb.everyMinutes == nil {
                ChoiceRow("Times") { TimesField(times: hb.times) { t in update { $0.times = t } } }
            }
            ChoiceRow("Runtime") {
                LiftedSegments(items: Heartbeat.Runtime.allCases.map { .init(id: $0, title: $0.label) }, selected: hb.runtime, fontSize: 11.5, padding: segInset) { r in
                    update { $0.runtime = r }
                }
            }
        }
        if factoryWakes {
            SettingsCard("Also wakes on") {
                SwitchRow("Your answers and ideas", "A few minutes after you answer a question or send an idea.",
                          isOn: Binding(get: { hb.wakeOnAnswer }, set: { v in update { $0.wakeOnAnswer = v } }))
                SwitchRow("A failed CI run", "A new failed run on main, master or develop, read with your own gh.",
                          isOn: Binding(get: { hb.wakeOnCI }, set: { v in update { $0.wakeOnCI = v } }))
                if let f = factory {
                    let src = f.sources, v4 = f.takesSources
                    SwitchRow("A new Sentry error", !v4 ? "Needs factory contract v4: the CEO names its Sentry project in factory/contract.yml."
                              : src.hasSentry ? "New or returning errors (error, fatal) in \(src.sentryOrg!)/\(src.sentryProject!), every 15 minutes. Not when the mandate has bugs off."
                              : "Name the project in factory/contract.yml: sentry: org/project.",
                              isOn: Binding(get: { hb.wakeOnSentry }, set: { v in update { $0.wakeOnSentry = v } }), disabled: !v4 || !src.hasSentry)
                    SwitchRow("A Tracker story", !v4 ? "Needs factory contract v4: the CEO names its Tracker project in factory/contract.yml."
                              : src.tracker.map { "A story in \($0) that is rejected or ready to pick up, every 15 minutes." }
                              ?? "Name the project in factory/contract.yml: tracker: <slug>.",
                              isOn: Binding(get: { hb.wakeOnTracker }, set: { v in update { $0.wakeOnTracker = v } }), disabled: !v4 || src.tracker == nil)
                }
            }.id("wakes")
        }
        SettingsCard("Limits on automatic runs") {
            ChoiceRow("Per day") {
                LiftedSegments(items: [3, 6, 12].map { .init(id: $0, title: "\($0) runs") }, selected: hb.runsPerDay, fontSize: 11.5, padding: segInset) { n in
                    update { $0.runsPerDay = n }
                }
            }
            ChoiceRow("Between runs") {
                LiftedSegments(items: [10, 20, 60].map { .init(id: $0, title: $0 == 60 ? "1 h" : "\($0) min") }, selected: hb.cooldownMinutes, fontSize: 11.5, padding: segInset) { m in
                    update { $0.cooldownMinutes = m }
                }
            }
            ChoiceRow("API price per day") {
                // D61: a cap on what the factory's work costs today at API list prices; 0 means no cap
                LiftedSegments(items: Self.capItems, selected: Int(hb.maxCostPerDay ?? 0), fontSize: 11.5, padding: segInset) { v in
                    update { $0.maxCostPerDay = v == 0 ? nil : Double(v) }
                }
            }
            Text("A run is one wake of the CEO: its heartbeat, your answers or ideas, a failed CI run. One run can handle several stories or bugs. Run now is yours and does not count. The API price is what this floor's sessions would have cost at list prices today, also under a subscription.")
                .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14).padding(.bottom, 12)
        }
        ModelCard(hb: hb, update: update)
    }
}

/// Which model and effort a run gets, by why it woke (D70). Default keeps the runtime's own choice.
private struct ModelCard: View {
    let hb: Heartbeat
    let update: (@escaping (inout Heartbeat) -> Void) -> Void

    private static let titles: [String: String] = [
        "haiku": "Haiku", "sonnet": "Sonnet", "opus": "Opus",
        "gpt-6-luna": "Luna", "gpt-6.1-sol": "Sol", "gpt-6-astra": "Astra", "gpt-5.3-codex": "5.3 Codex",
        "low": "Low", "medium": "Med", "high": "High", "xhigh": "XHigh", "max": "Max",
    ]
    private func items(_ ids: [String]) -> [LiftedSegments<String>.Item] {
        [LiftedSegments<String>.Item(id: "", title: "Default")] + ids.map { LiftedSegments<String>.Item(id: $0, title: Self.titles[$0] ?? $0) }
    }

    var body: some View {
        SettingsCard("Models") {
            ForEach(ModelPolicy.Kind.allCases, id: \.self) { k in row(k) }.id("models")
            Text("Default leaves the choice to \(hb.runtime.label). A run's log says what it ran with. The routine heartbeat is the run that happens most: a smaller model there saves the most.")
                .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14).padding(.bottom, 12)
        }
    }

    private func row(_ k: ModelPolicy.Kind) -> some View {
        let c = hb.models[k]
        let models = items(ModelPolicy.models[hb.runtime] ?? [])
        let efforts = items(ModelPolicy.efforts[hb.runtime] ?? [])
        return VStack(alignment: .leading, spacing: 6) {
            Text(k.label).font(.system(size: 13.5, weight: .semibold))
            HStack(spacing: 8) {
                LiftedSegments(items: models, selected: c.model ?? "", fontSize: 10.5, padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { m in
                    update { $0.models[k].model = m.isEmpty ? nil : m }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                LiftedSegments(items: efforts, selected: c.effort ?? "", fontSize: 10.5, padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { e in
                    update { $0.models[k].effort = e.isEmpty ? nil : e }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// "07:10, 13:00": wall-clock times; anything that is not a time is dropped, and an empty list keeps the old one.
private struct TimesField: View {
    let times: [String]
    let change: ([String]) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("07:10, 13:00", text: $text).focused($focused).font(.system(size: 12.5, design: .monospaced))
            .textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 6).frame(width: 160)
            .lifted(focused: focused)
            .onSubmit(save).onChange(of: focused) { _, f in if !f { save() } }
            .onAppear { text = times.joined(separator: ", ") }
            .onChange(of: times) { _, t in if !focused { text = t.joined(separator: ", ") } }
    }
    private func save() {
        let parsed = text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { part -> String? in
            let p = part.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
            return String(format: "%02d:%02d", p[0], p[1])
        }
        let unique = Array(Set(parsed)).sorted()
        if unique.isEmpty || unique == times { text = times.joined(separator: ", "); return }
        change(unique)
    }
}

// MARK: Data & privacy

private struct PrivacySettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Data & privacy").font(.system(size: 22, weight: .bold))
            Text("Everything stays on this Mac. Nothing is sent anywhere.").font(.system(size: 13)).foregroundStyle(Color.muted)
            item("doc.text.magnifyingglass", "Sessions", "Read-only from the files Claude Code and Codex already keep: ~/.claude/projects and ~/.codex/sessions. The app never writes there.")
            item("server.rack", "Servers", "Host names and kinds only, in ~/Library/Application Support/Meatproxy/servers.json. No passwords, no keys: ssh uses yours.")
            item("building.2", "Projects", "The projects you keep on the campus and switched on as factories, with their heartbeats, in ~/Library/Application Support/Meatproxy/projects.json. The app reads a factory's factory/ folder and writes only your answer into an open question.")
            item("waveform.path.ecg", "Heartbeat", "A factory's CEO runs as claude -p or codex exec in its own folder, with that project's allowlist. Logs and run state stay in ~/Library/Application Support/Meatproxy/heartbeats. CI is read with your own gh login.")
            item("terminal", "Checks", "ssh in batch mode, with your keys and ~/.ssh/config. The built-in check reads load, disk and memory and changes nothing.")
            item("photo", "Screenshots", "Start the app with --fixture to show made-up data, safe to share.")
        }
    }
    private func item(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.muted).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text).font(.system(size: 12.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: parts

private struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
    }
}

private struct Note<C: View>: View {
    let icon: String, title: String
    @ViewBuilder let content: () -> C
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.inkText).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13.5, weight: .bold))
                content().font(.system(size: 12.5)).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.divider))
    }
}

private struct IconButton: View {
    let icon: String, help: String, action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
        }.buttonStyle(TactileButtonStyle(kind: .neutral)).help(help)
    }
}

private struct SettingsButton: ButtonStyle {
    var primary = false
    /// a tint marks the destructive confirmation (Remove)
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        TactileButtonStyle(kind: primary ? .primary : tint != nil ? .destructive : .neutral,
                           inset: EdgeInsets(top: 6, leading: primary ? 14 : 10, bottom: 6, trailing: primary ? 14 : 10))
            .makeBody(configuration: configuration)
            .font(.system(size: 12, weight: .semibold))
    }
}

private var segInset: EdgeInsets { EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9) }

/// A page's title and one line under it.
private struct PageTitle: View {
    let title: String, text: String, mono: Bool
    init(_ title: String, _ text: String, mono: Bool = false) { self.title = title; self.text = text; self.mono = mono }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(text).font(.system(size: mono ? 12 : 13, design: mono ? .monospaced : .default)).foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Back to the list a page came from.
private struct BackButton: View {
    let title: String, action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) { HStack(spacing: 6) { Label(title, systemImage: "chevron.left"); KeyCap("⌘[") } }.buttonStyle(SettingsButton()).keyboardShortcut("[", modifiers: .command)
    }
}

/// A group of settings: its name above, its rows in one card, divided by hairlines.
private struct SettingsCard<C: View>: View {
    let title: String, trailing: AnyView?
    @ViewBuilder let content: () -> C
    init(_ title: String, trailing: AnyView? = nil, @ViewBuilder _ content: @escaping () -> C) { self.title = title; self.trailing = trailing; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Eyebrow(title); Spacer(); if let trailing { trailing } }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// A switch with its name and one line on what it does.
/// A token for a wake-up source (D61): typed once, kept in the macOS Keychain, shown only as saved.
private struct TokenRow: View {
    @EnvironmentObject private var model: AppModel
    let key: Secrets.Key
    let text: String
    @State private var saved = false
    @State private var value = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(key.label) token").font(.system(size: 13.5, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if saved {
                Label("In the Keychain", systemImage: "checkmark.seal").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.done)
                Button { if !model.fixture { Secrets.set(key, nil) }; saved = false } label: { Text("Remove") }.buttonStyle(SettingsButton())
            } else {
                SecureField("Paste token", text: $value).focused($focused).font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 6).frame(width: 170).lifted(focused: focused)
                    .onSubmit(save)
                Button(action: save) { Text("Save") }.buttonStyle(SettingsButton()).disabled(value.isEmpty)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .onAppear { saved = !model.fixture && Secrets.get(key) != nil }
    }
    /// demo data saves nothing, also not in the Keychain
    private func save() {
        guard !value.isEmpty else { return }
        saved = model.fixture ? true : Secrets.set(key, value); value = ""
    }
}

private struct SwitchRow: View {
    let title: String, text: String
    @Binding var isOn: Bool
    var disabled = false
    init(_ title: String, _ text: String, isOn: Binding<Bool>, disabled: Bool = false) { self.title = title; self.text = text; self._isOn = isOn; self.disabled = disabled }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(TactileToggleStyle()).disabled(disabled)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .opacity(disabled ? 0.6 : 1)
    }
}

/// A label on the left and a choice (segments, a field) beside it.
private struct ChoiceRow<C: View>: View {
    let label: String
    @ViewBuilder let content: () -> C
    init(_ label: String, @ViewBuilder _ content: @escaping () -> C) { self.label = label; self.content = content }
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted).frame(width: 84, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// A small outlined word: a server's kind.
private struct Badge: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.8)
            .padding(.horizontal, 6).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.border)).foregroundStyle(Color.muted)
    }
}

/// Your mandate for a factory (D56): how much its CEO may do on its own (a level, or Custom per item), its role, and your
/// preferences. Written to factory/mandate.yml; the CEO follows it from its next run.
private struct MandateCards: View {
    @EnvironmentObject private var model: AppModel
    let root: String
    @State private var notes = ""
    @State private var quiet = ""
    @FocusState private var focus: Field?
    enum Field { case notes, quiet }

    private static let levelText: [FactoryMandate.Level: String] = [
        .assistant: "It asks before everything: a yes/no question for each step. Your ideas it always handles.",
        .hybrid: "It fixes bugs, updates dependencies and merges its tested PRs, and tells you in the briefing. Its own ideas, shipping, store releases, spending and its own gates it asks first. Your ideas it always handles.",
        .dark: "It does everything and tells you, its own ideas included, except spending money and store releases: those it asks.",
        .custom: "You set each item yourself below.",
    ]

    /// Dark is switched off where you capped the factory (D68)
    private var levelItems: [LiftedSegments<FactoryMandate.Level>.Item] {
        let dark = model.projectSettings.darkAllowed(root)
        return FactoryMandate.Level.allCases.map { l in
            LiftedSegments<FactoryMandate.Level>.Item(id: l, title: l.rawValue.capitalized, enabled: l != .dark || dark,
                                                      help: l == .dark && !dark ? "Dark is off for this factory (Allow Dark, above)" : nil)
        }
    }

    var body: some View {
        let m = model.mandate(root)
        SettingsCard("Autonomy") {
            ChoiceRow("Level") {
                LiftedSegments(items: levelItems, selected: m.level,
                               fontSize: 11.5, padding: segInset) { l in model.setMandate(root) { $0.set(level: l) } }
            }
            Text(Self.levelText[m.level] ?? "").font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.bottom, 6)
            ForEach(FactoryMandate.Item.allCases, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(i.label).font(.system(size: 12)).foregroundStyle(m.level == .custom ? Color.inkText : Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    // changing an item makes the mandate Custom
                    LiftedSegments(items: [.init(id: FactoryMandate.Mode.ask, title: "Ask"), .init(id: .notify, title: "Tell me"), .init(id: .off, title: "Off")],
                                   selected: m.mode(i), fontSize: 10.5, padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { v in
                        model.setMandate(root) { $0.level = .custom; $0.items[i] = v }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 5)
            }
            Color.clear.frame(height: 6)
        }
        SettingsCard("Role") {
            ChoiceRow("The CEO") {
                LiftedSegments(items: [.init(id: FactoryMandate.Role.orchestrator, title: "Orchestrates only"), .init(id: .handsOn, title: "Works along")],
                               selected: m.role, fontSize: 11.5, padding: segInset) { r in model.setMandate(root) { $0.role = r } }
            }
            Text(m.role == .orchestrator ? "It hands every piece of work to its team (product, developer, tester, designer, devops) and touches no code itself."
                                         : "It may do small things itself, such as a one-line fix or a doc; the rest goes to its team.")
                .font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14).padding(.bottom, 12)
        }
        SettingsCard("Preferences") {
            ChoiceRow("Quiet hours") {
                TextField("22:00-07:00", text: $quiet).focused($focus, equals: .quiet).font(.system(size: 12.5, design: .monospaced))
                    .textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 6).frame(width: 140).lifted(focused: focus == .quiet)
                    .onSubmit { save() }
                Text("no runs or questions then").font(.system(size: 11.5)).foregroundStyle(Color.muted)
            }
            ChoiceRow("Briefing in") {
                LiftedSegments(items: [.init(id: "en", title: "English"), .init(id: "nl", title: "Dutch")], selected: m.briefingLanguage,
                               fontSize: 11.5, padding: segInset) { v in model.setMandate(root) { $0.briefingLanguage = v } }
            }
            ChoiceRow("Proposals") {
                LiftedSegments(items: [1, 2, 3].map { .init(id: $0, title: "\($0) a run") }, selected: m.proposalsPerRun,
                               fontSize: 11.5, padding: segInset) { v in model.setMandate(root) { $0.proposalsPerRun = v } }
            }
            ChoiceRow("PR size") {
                LiftedSegments(items: ["small", "medium", "large"].map { .init(id: $0, title: $0.capitalized) }, selected: m.prSize,
                               fontSize: 11.5, padding: segInset) { v in model.setMandate(root) { $0.prSize = v } }
            }
            SwitchRow("Batch small fixes", "Several small fixes go out as one PR instead of one each.",
                      isOn: Binding(get: { m.batchSmallFixes }, set: { v in model.setMandate(root) { $0.batchSmallFixes = v } }))
            VStack(alignment: .leading, spacing: 6) {
                Text("Anything else, in your words").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
                TextField("", text: $notes, prompt: Text("Never touch the payment code. Ask before any change to onboarding.").foregroundStyle(Color.muted), axis: .vertical)
                    .lineLimit(3...8).focused($focus, equals: .notes).font(.system(size: 12.5)).textFieldStyle(.plain)
                    .padding(8).lifted(focused: focus == .notes)
                Text("Part of the mandate: the CEO follows it like the rest.").font(.system(size: 11.5)).foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .onAppear { notes = m.notes; quiet = m.quietHours }
        .onChange(of: focus) { old, _ in if old != nil { save() } }
    }

    private func save() {
        let m = model.mandate(root)
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines), q = quiet.trimmingCharacters(in: .whitespaces)
        guard n != m.notes || q != m.quietHours else { return }
        model.setMandate(root) { $0.notes = n; $0.quietHours = q }
    }
}

/// The status pages you watch (D69): the providers, GitHub, and any Statuspage of your own. Public pages, no tokens.
private struct StatusSourcesRows: View {
    @EnvironmentObject private var model: AppModel
    @State private var address = ""
    @FocusState private var focused: Bool
    var body: some View {
        ForEach(model.statusSources) { s in row(s) }
        HStack(spacing: 10) {
            TextField("", text: $address, prompt: Text("status.example.com").foregroundStyle(Color.muted)).focused($focused)
                .font(.system(size: 12, design: .monospaced)).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 6).lifted(focused: focused).onSubmit(add)
            Button(action: add) { Text("Add page") }.buttonStyle(SettingsButton()).disabled(StatusSource.custom(address) == nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func row(_ s: StatusSource) -> some View {
        let builtIn = StatusSource.defaults.contains { $0.id == s.id }
        let line = s.runtime.map { "Factories on \($0 == "codex" ? "Codex" : "Claude") wait while it is down. " } ?? ""
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.system(size: 13.5, weight: .semibold))
                Text(line + s.page.replacingOccurrences(of: "https://", with: "")).font(.system(size: 12)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
            if !builtIn {
                Button { model.updateStatusSources { $0.removeAll { $0.id == s.id } } } label: { Text("Remove") }.buttonStyle(SettingsButton())
            }
            Toggle(s.name, isOn: Binding(get: { s.on }, set: { v in model.updateStatusSources { l in if let k = l.firstIndex(where: { $0.id == s.id }) { l[k].on = v } } }))
                .labelsHidden().toggleStyle(TactileToggleStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func add() {
        guard let s = StatusSource.custom(address), !model.statusSources.contains(where: { $0.id == s.id }) else { return }
        model.updateStatusSources { $0.append(s) }
        address = ""
    }
}
