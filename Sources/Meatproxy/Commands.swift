import SwiftUI
import AppKit
import FactoryCore
import FactoryScenes
import FactoryCollector

/// One list of everything you can do (D72). Help shows it with its keys and the mouse gestures, ⌘K searches it together
/// with your projects, people, questions and servers, and a right-click shows the part that fits what you clicked.
/// Icons are the kit's pixel icons.
struct AppCommand: Identifiable {
    enum Group: String, CaseIterable { case go = "Go", show = "Show", act = "Do", projects = "Projects", questions = "Needs you", sessions = "People and chats", servers = "Servers" }
    let id: String
    let title: String
    var detail = ""
    let icon: String
    let group: Group
    var keys: String? = nil
    /// how many wait for you there (a project's open questions): its yellow badge
    var waiting = 0
    /// a portrait or a logo instead of the icon
    var cast: CastKey? = nil
    var logo: String? = nil
    let run: @MainActor () -> Void
}

/// Help's two tabs (D7).
enum HelpTab: Hashable { case keys, guide }

/// A right-click menu: where it opens and what is in it.
struct ContextMenuState: Equatable {
    let at: CGPoint
    let title: String
    let items: [AppCommand]
    static func == (a: Self, b: Self) -> Bool { a.at == b.at && a.title == b.title && a.items.map(\.id) == b.items.map(\.id) }
}

extension AppModel {
    /// What you can do from anywhere, with its keys.
    var staticCommands: [AppCommand] {
        var c: [AppCommand] = [
            AppCommand(id: "go.campus", title: "Campus", detail: "The whole island", icon: "campus", group: .go, keys: "⌘1") { [weak self] in self?.controller.showOrbit(false); self?.controller.focusBuilding(nil) },
            AppCommand(id: "go.engine", title: "Server room", detail: "Servers, services, the DevOps agent", icon: "server", group: .go, keys: "⌘2") { [weak self] in self?.controller.focusBuilding("engine") },
            AppCommand(id: "go.next", title: "Next that needs you", detail: "Questions and chats that wait", icon: "bang", group: .go, keys: "N") { [weak self] in self?.controller.nextWaiting() },
            AppCommand(id: "go.up", title: "Up a level", detail: "Floor → building → campus", icon: "up", group: .go, keys: "esc") { [weak self] in self?.controller.up() },
            AppCommand(id: "go.zoomin", title: "Zoom in", icon: "plus", group: .go, keys: "+") { [weak self] in self?.controller.zoom(0.8) },
            AppCommand(id: "go.zoomout", title: "Zoom out", icon: "minus", group: .go, keys: "−") { [weak self] in self?.controller.zoom(1.25) },
            AppCommand(id: "show.search", title: "Search", icon: "search", group: .show, keys: "⌘K") { [weak self] in self?.paletteOpen = true },
            AppCommand(id: "show.status", title: statusLayer ? "Hide the Status layer" : "Status layer", detail: "Status pages and CI on the campus", icon: "layers", group: .show, keys: "⌘L") { [weak self] in guard let self else { return }; self.setStatusLayer(!self.statusLayer) },
            AppCommand(id: "show.terminal", title: "Terminal", icon: "terminal", group: .show, keys: "⌘J") { [weak self] in self?.terminals.toggle() },
            AppCommand(id: "show.settings", title: "Settings", icon: "gear", group: .show, keys: "⌘,") { [weak self] in self?.settingsOpen = true },
            AppCommand(id: "show.commands", title: "Help", detail: "Every key, and the field guide", icon: "help", group: .show, keys: "?") { [weak self] in self?.commandsOpen = true },
            AppCommand(id: "do.answer", title: "Answer yes or no", detail: "On an open question; it asks once more", icon: "check", group: .act, keys: "1 2") { [weak self] in self?.controller.nextWaiting() },
            AppCommand(id: "do.send", title: "Send the answer", icon: "send", group: .act, keys: "⌘↩") { [weak self] in self?.controller.nextWaiting() },
            AppCommand(id: "do.pause", title: projectSettings.pauseAll ? "Resume all factories" : "Pause all factories", detail: "The kill switch: nothing starts, running CEOs stop", icon: projectSettings.pauseAll ? "play" : "pause", group: .act) { [weak self] in guard let self else { return }; self.setPauseAll(!self.projectSettings.pauseAll) },
            AppCommand(id: "do.walk", title: "Take the walk", detail: "A minute round your campus", icon: "map", group: .act) { [weak self] in
                guard let self else { return }
                self.walkGoalDone = false; self.walkStep = 1; self.controller.showOrbit(false); self.controller.focusBuilding(nil)
            },
        ]
        if projectSettings.devops.enabled {
            c.append(AppCommand(id: "do.devops", title: "Run the DevOps agent now", icon: "hand", group: .act) { [weak self] in self?.runDevOpsNow() })
        }
        for p in world.projects where p.factory != nil {
            c.append(AppCommand(id: "do.run:" + p.id, title: "Run now · \(p.name)", detail: "Wake its CEO", icon: "play", group: .act) { [weak self] in self?.runNow(p) })
        }
        return c
    }

    /// Everything ⌘K searches (D3): your projects, what waits for you, people and chats, servers, and the commands;
    /// never Search itself.
    var searchable: [AppCommand] {
        var c: [AppCommand] = []
        for b in world.buildings {
            for (k, p) in b.projects.enumerated() {
                let kind = p.factory != nil ? "factory" : p.isChat ? "chats" : "\(p.sessions.count) chat\(p.sessions.count == 1 ? "" : "s")"
                c.append(AppCommand(id: "p:" + p.id, title: p.name, detail: "\(p.provider.displayName) tower · floor \(k + 1) · \(kind)", icon: p.isChat ? "chat" : "floor",
                                    group: .projects, waiting: world.needsYou.filter { $0.project.id == p.id }.count, logo: p.logo) { [weak self] in self?.controller.enterFloor(p.id) })
                if !p.isChat {
                    c.append(AppCommand(id: "ps:" + p.id, title: "Settings · \(p.name)", detail: "Folder, place and Factory", icon: "gear", group: .show) { [weak self] in self?.openProjectSettings(p.root) })
                }
            }
        }
        for n in world.needsYou {
            switch n {
            case .decision(let p, let d):
                c.append(AppCommand(id: "d:" + p.id + d.id, title: d.title, detail: "\(p.name) · \(d.kind) · \(d.asked?.ago ?? "")", icon: p.id == World.opsID ? "server" : "bang", group: .questions) { [weak self] in self?.controller.open(n) })
            case .session(let p, let s):
                c.append(AppCommand(id: "w:" + s.id, title: s.title, detail: "\(p.name) · \(s.persona.name) · \(s.lastAt.ago)", icon: "help", group: .questions) { [weak self] in self?.controller.open(n) })
            }
        }
        for p in world.projects {
            for s in p.sessions.sorted(by: { $0.lastAt > $1.lastAt }).prefix(12) {
                c.append(AppCommand(id: "s:" + s.id, title: "\(s.persona.name) · \(s.title)", detail: "\(p.name) · \(s.state(now: world.now).label.lowercased())", icon: "person",
                                    group: .sessions, cast: cast(of: s)) { [weak self] in self?.controller.select(session: s.id) })
            }
        }
        for s in world.servers {
            c.append(AppCommand(id: "sv:" + s.id, title: s.name, detail: "\(s.kind.label) · \(s.state.label)" + (s.detail.map { " · \($0)" } ?? ""), icon: "server", group: .servers) { [weak self] in self?.controller.select(server: s.id) })
        }
        return c + staticCommands.filter { $0.id != "show.search" && !$0.id.hasPrefix("do.answer") && !$0.id.hasPrefix("do.send") }
    }

    func openProjectSettings(_ root: String) { settingsPage = "project:" + root; settingsOpen = true }

    /// The right-click menu for what you clicked (nil: the empty world).
    func contextMenu(for t: ContextTarget?, at point: CGPoint) -> ContextMenuState {
        var items: [AppCommand] = [], title = "Campus"
        switch t {
        case .building(let k)?:
            if k == "engine" {
                title = "Server room"
                items = [AppCommand(id: "c.open", title: "Open the Server room", icon: "server", group: .go, keys: "⌘2") { [weak self] in self?.controller.focusBuilding("engine") },
                         AppCommand(id: "c.layer", title: statusLayer ? "Hide the Status layer" : "Show the Status layer", icon: "layers", group: .show, keys: "⌘L") { [weak self] in guard let self else { return }; self.setStatusLayer(!self.statusLayer) }]
                if projectSettings.devops.enabled { items.append(AppCommand(id: "c.devops", title: "Run the DevOps agent now", icon: "hand", group: .act) { [weak self] in self?.runDevOpsNow() }) }
                items.append(AppCommand(id: "c.servers", title: "Server settings", icon: "gear", group: .show) { [weak self] in self?.settingsPage = "engine"; self?.settingsOpen = true })
            } else {
                title = Provider(rawValue: k)?.displayName ?? k
                items = [AppCommand(id: "c.focus", title: "Open \(title)", icon: "tower", group: .go) { [weak self] in self?.controller.focusBuilding(k) }]
            }
        case .project(let id)?:
            guard let p = world.project(id: id) else { break }
            title = p.name
            items.append(AppCommand(id: "c.floor", title: "Open the floor", icon: "floor", group: .go) { [weak self] in self?.controller.enterFloor(id) })
            if p.factory != nil {
                items.append(AppCommand(id: "c.run", title: "Run now", detail: "Wake its CEO", icon: "play", group: .act) { [weak self] in self?.runNow(p) })
            }
            if !p.isChat {
                if p.factory == nil {
                    let pinned = isPinned(p)
                    items.append(AppCommand(id: "c.pin", title: pinned ? "Don't keep on campus" : "Keep on campus", icon: "map", group: .act) { [weak self] in self?.setPinned(p.root, on: !pinned) })
                    items.append(AppCommand(id: "c.hide", title: "Hide from campus", detail: "Nothing is deleted", icon: "eye", group: .act) { [weak self] in self?.setHidden(p.root, on: true) })
                }
                items.append(AppCommand(id: "c.reveal", title: "Show in Finder", icon: "folder", group: .act) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.root)]) })
                items.append(AppCommand(id: "c.copy", title: "Copy path", icon: "copy", group: .act) { Self.copy(p.root) })
                items.append(AppCommand(id: "c.settings", title: "Project settings", icon: "gear", group: .show) { [weak self] in self?.openProjectSettings(p.root) })
            }
        case .session(let id)?:
            guard let (p, s) = session(id) else { break }
            title = "\(s.persona.name) · \(p.name)"
            items = [AppCommand(id: "c.show", title: "Show the session", detail: s.title, icon: "person", group: .go) { [weak self] in self?.controller.select(session: id) },
                     AppCommand(id: "c.take", title: "Take over in the terminal", detail: "Resume it yourself", icon: "terminal", group: .act) { [weak self] in self?.takeOver(s) },
                     AppCommand(id: "c.resume", title: "Copy the resume command", icon: "copy", group: .act) { Self.copy(s.resumeCommand) },
                     AppCommand(id: "c.its-floor", title: "Open \(p.name)'s floor", icon: "floor", group: .go) { [weak self] in self?.controller.enterFloor(p.id) }]
        case .server(let c)?:
            guard c < world.racks.count else { break }
            let s = world.racks[c]
            title = s.name
            items = [AppCommand(id: "c.server", title: "Show the server", detail: s.state.label, icon: "server", group: .go) { [weak self] in self?.controller.select(server: s.id) },
                     AppCommand(id: "c.settings", title: "Server settings", icon: "gear", group: .show) { [weak self] in self?.settingsPage = "server:" + s.id; self?.settingsOpen = true }]
        case .fountain?:
            title = "Needs you"
            items = [AppCommand(id: "c.next", title: "Next that needs you", icon: "bang", group: .go, keys: "N") { [weak self] in self?.controller.nextWaiting() }]
        case nil: break
        }
        // always at the bottom: search and Help
        items.append(AppCommand(id: "c.search", title: "Search", icon: "search", group: .show, keys: "⌘K") { [weak self] in self?.paletteOpen = true })
        items.append(AppCommand(id: "c.all", title: "Help", icon: "help", group: .show, keys: "?") { [weak self] in self?.commandsOpen = true })
        return ContextMenuState(at: point, title: title, items: items)
    }

    static func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }

    /// What the campus shows, for Help's field guide (D74, D78): its kind (what you have seen is kept), a title, what it
    /// means, and its pixel icon and colour on the collector's card.
    static let legend: [(kind: String, title: String, text: String, icon: String, color: UInt32)] = [
        ("alarm", "Alarm light", "That project is broken: CI on main is red, or a session ended with a failed test, push or deploy (clears after 12 hours)", "warn", 0xFF6B6B),
        ("drone", "Drone", "A pull request was merged (without GitHub: a factory pushed or deployed)", "send", 0x6EA8FE),
        ("helper", "Lit floor", "A floor's windows light up: a chat there started a helper (a sub-agent)", "person", 0x4FE0F5),
        ("packets", "Packets", "A deploy is running", "box", 0xFF9F43),
        ("smoke", "Smoke", "A factory works in that tower; more while its CEO runs", "pulse", 0xD6D6D6),
        ("dark", "Dark floor", "A factory's mandate: lights on is Assistant, dimmed Hybrid, lights out Dark", "floor", 0x6EA8FE),
        ("night", "Night", "The sky follows your Mac's clock. Nothing is wrong", "moon", 0x8F74EA),
    ]

    /// What the mouse and trackpad do, for Help.
    static let gestures: [(String, String)] = [
        ("Click", "opens it"), ("Right-click", "a menu"), ("Drag", "moves"),
        ("Scroll or + −", "zooms"), ("Hover a tower", "opens it up"), ("Wheel on a tower", "walks floors"),
    ]
}

// MARK: - search

/// ⌘K (D3): search everything and open it. What you type filters every group, projects first; without a query, what
/// waits for you comes first, then your projects. Arrows pick, Return opens, Esc closes.
struct CommandPalette: View {
    @EnvironmentObject private var model: AppModel
    @State private var query: String
    @State private var picked = 0
    @State private var faces = 0
    @FocusState private var focused: Bool

    /// what the search starts with (window shots): read once, when it opens
    init(seed: String = "") { _query = State(initialValue: seed) }

    static let typedOrder: [AppCommand.Group] = [.projects, .questions, .sessions, .servers, .go, .show, .act]
    static let emptyOrder: [AppCommand.Group] = [.questions, .projects, .go]

    var body: some View {
        let groups = FuzzyMatch.rankGrouped(query, model.searchable, groups: query.isEmpty ? Self.emptyOrder : Self.typedOrder, limit: query.isEmpty ? 6 : 8,
                                            group: { $0.group }, text: { $0.title + " " + $0.detail })
        let flat = groups.flatMap(\.items); let _ = faces
        let commandsMatch = groups.contains { [.go, .show, .act].contains($0.group) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                PixelIcon("search", color: .muted)
                TextField("", text: $query, prompt: Text("Search projects, people, questions, servers").foregroundStyle(Color.muted))
                    .textFieldStyle(.plain).font(.s19).focused($focused)
                    .onSubmit { run(flat) }
                KeyCap("esc")
            }
            .padding(.horizontal, 12).frame(height: 52)
            .lifted(focused: focused)
            .padding(16)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(groups, id: \.group) { g in
                            Eyebrow(g.group == .go || g.group == .show || g.group == .act ? "Commands · \(g.group.rawValue)" : g.group.rawValue)
                                .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 2)
                            ForEach(g.items) { c in
                                let i = flat.firstIndex { $0.id == c.id } ?? 0
                                CommandRow(command: c, picked: i == picked, query: query)
                                    .id(i)
                                    .onTapGesture { model.paletteOpen = false; c.run() }
                            }
                        }
                        if flat.isEmpty {
                            Text("Nothing matches “\(query)”").font(.s13).foregroundStyle(Color.muted).padding(14)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
                .frame(maxHeight: 420)
                .onChange(of: picked) { _, p in proxy.scrollTo(p) }
            }
            RowDivider()
            HStack(spacing: 6) {
                KeyCap("↑"); KeyCap("↓"); Text("move").font(.s13).foregroundStyle(Color.muted).padding(.trailing, 8)
                KeyCap("↩"); Text("open").font(.s13).foregroundStyle(Color.muted).padding(.trailing, 8)
                KeyCap("esc"); Text("close").font(.s13).foregroundStyle(Color.muted)
                Spacer(minLength: 0)
                if !query.isEmpty && !commandsMatch { Text("No commands match ‘\(query)’").font(.s13).foregroundStyle(Color.muted) }
            }
            .padding(.horizontal, 16).frame(height: 44)
        }
        .frame(width: Shell.sheet)
        .spelFrame()
        .onAppear { model.paletteSeed = ""; DispatchQueue.main.async { focused = true } }
        // the people's portraits, drawn once (a person in the list shows their face, not an empty socket)
        .task { await model.controller.ensurePortraits(model.searchable.compactMap(\.cast)); faces += 1 }
        .onChange(of: query) { _, _ in picked = 0 }
        .onKeyPress(.downArrow) { picked = min(picked + 1, max(0, flat.count - 1)); return .handled }
        .onKeyPress(.upArrow) { picked = max(picked - 1, 0); return .handled }
        .onExitCommand { model.paletteOpen = false }
    }

    private func run(_ results: [AppCommand]) {
        guard results.indices.contains(picked) else { return }
        model.paletteOpen = false
        results[picked].run()
    }
}

// MARK: - Help

/// Help (D7): two tabs. Keys: three columns, Go, Show and Do, each line a button with its key, and the mouse in one
/// strip. Field guide: a card for each thing on the campus; what you have not seen yet is an empty card.
struct CommandSheet: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let seen = AppModel.legend.filter { model.seenEffects.contains($0.kind) }.count
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Socket(size: 44) { PixelIcon("help", color: .inkText) }
                Text("Help").font(.s26).foregroundStyle(Color.inkText)
                Spacer()
                CloseButton(action: { model.commandsOpen = false })
            }
            TabbedBox(items: [.init(id: HelpTab.keys, title: "Keys"), .init(id: .guide, title: "Field guide · \(seen) of \(AppModel.legend.count)")],
                      selected: model.helpTab, stretch: false, pick: { model.helpTab = $0 }) {
                if model.helpTab == .keys { KeysTab() } else { FieldGuideTab() }
            }
        }
        .padding(16)
        .frame(width: Shell.wideSheet)
        .spelFrame()
        .onExitCommand { model.commandsOpen = false }
    }
}

private struct KeysTab: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let all = model.staticCommands.filter { !$0.id.hasPrefix("do.run:") && $0.id != "show.commands" }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                ForEach([AppCommand.Group.go, .show, .act], id: \.self) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(g.rawValue).padding(.bottom, 4).padding(.leading, 8)
                        ForEach(all.filter { $0.group == g }) { c in
                            CommandRow(command: c, picked: false, compact: true).onTapGesture { model.commandsOpen = false; c.run() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            RowDivider()
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Mouse and trackpad")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 6) {
                    ForEach(AppModel.gestures, id: \.0) { g in
                        (Text(g.0).font(.s13b).foregroundColor(.inkText) + Text(" " + g.1).font(.s13).foregroundColor(.muted))
                    }
                }
            }
        }
    }
}

/// The field guide (D78): a collector's card for everything that moves on the campus; what you have not seen is an
/// empty card with a question mark. Hover one for what it means.
private struct FieldGuideTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovered: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(AppModel.legend, id: \.kind) { r in
                    let on = model.seenEffects.contains(r.kind)
                    VStack(spacing: 6) {
                        if on {
                            PixelIcon(r.icon, color: Color(hex: r.color), size: 27)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 8).fill(RadialGradient(colors: [Color(hex: r.color).opacity(0.28), Color.well], center: .center, startRadius: 0, endRadius: 40)))
                        } else {
                            PixelIcon("help", color: .muted, size: 27).frame(maxWidth: .infinity).frame(height: 44)
                        }
                        Text(r.title).font(.s13m).foregroundStyle(on ? Color.inkText : Color.muted).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.raised : Color.clear))
                    .overlay {
                        if on { RoundedRectangle(cornerRadius: 10).strokeBorder(hovered == r.kind ? Color.selection : Color.border, lineWidth: 2) }
                        else { RoundedRectangle(cornerRadius: 10).strokeBorder(hovered == r.kind ? Color.selection : Color.border, style: StrokeStyle(lineWidth: 2, dash: [4, 3])) }
                    }
                    .onHover { hovered = $0 ? r.kind : (hovered == r.kind ? nil : hovered) }
                    .help(r.text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(on ? "\(r.title): \(r.text)" : "\(r.title), not seen yet")
                }
            }
            let shown = AppModel.legend.first { $0.kind == hovered }
            Group {
                if let s = shown {
                    (Text(s.title + ": ").font(.s13b).foregroundColor(.inkText) + Text(model.seenEffects.contains(s.kind) ? s.text : "Not seen yet. " + s.text).font(.s13).foregroundColor(.muted))
                } else {
                    Text("Hover a card for what it means. On the campus, hover the thing itself for what it means right now.").font(.s13).foregroundStyle(Color.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 36, alignment: .topLeading)
        }
    }
}

// MARK: - rows and menus

/// The right-click menu (D72): a small frame at the pointer. Click outside or Esc closes it.
struct ContextMenuView: View {
    @EnvironmentObject private var model: AppModel
    let menu: ContextMenuState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(menu.title).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
            ForEach(menu.items) { c in
                if c.id == "c.search" { RowDivider().padding(.vertical, 3) }
                CommandRow(command: c, picked: false, compact: true)
                    .onTapGesture { model.contextMenuState = nil; c.run() }
            }
        }
        .padding(6)
        .frame(width: 290)
        .spelFrame()
    }
}

/// One line in search, Help and the right-click menu: an icon (or a portrait or logo), the name with what you typed
/// marked, where it lives, and on the right a yellow badge when something waits there and the key when it has one.
private struct CommandRow: View {
    @EnvironmentObject private var model: AppModel
    let command: AppCommand
    let picked: Bool
    var query = ""
    var compact = false
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            if compact {
                PixelIcon(command.icon, color: hover ? .inkText : .muted).frame(width: 18)
            } else {
                Socket(size: 36) { icon }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(marked(command.title)).font(compact ? .s13m : .s15).foregroundStyle(Color.inkText).lineLimit(1)
                if !command.detail.isEmpty && !compact {
                    Text(marked(command.detail)).font(.s13).foregroundStyle(Color.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if command.waiting > 0 { QuestBadge(count: command.waiting) }
            if let k = command.keys { KeyCap(k) }
        }
        .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 5 : 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(picked ? Color.surface : hover ? Color.raised : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(picked ? Color.selection : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var icon: some View {
        if let key = command.cast {
            Portrait(image: model.controller.portrait(key), role: key.role, size: 32)
        } else if command.logo != nil {
            ProjectLogoView(path: command.logo, size: 22)
        } else if command.group == .questions {
            QuestMarker(glyph: command.icon, size: 22)
        } else {
            PixelIcon(command.icon, color: .inkText)
        }
    }

    /// what you typed, underlined in the selection colour
    private func marked(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        guard !query.isEmpty, let pos = FuzzyMatch.positions(query, s) else { return a }
        let chars = Array(s)
        for p in pos where p < chars.count {
            let start = a.index(a.startIndex, offsetByCharacters: p)
            let end = a.index(start, offsetByCharacters: 1)
            a[start..<end].underlineStyle = .single
            a[start..<end].underlineColor = NSColor(Color.selection)
            a[start..<end].backgroundColor = Color.selection.opacity(0.18)
        }
        return a
    }
}
