import SwiftUI
import AppKit
import FactoryCore
import FactoryScenes
import FactoryCollector

/// One list of everything you can do (D72). `?` shows it with its keys and the mouse gestures, ⌘K searches it together
/// with your projects, sessions, questions and servers, and a right-click shows the part that fits what you clicked.
struct AppCommand: Identifiable {
    enum Group: String, CaseIterable { case go = "Go", show = "Show", act = "Do", projects = "Projects", sessions = "Sessions", questions = "Questions", servers = "Servers" }
    let id: String
    let title: String
    var detail = ""
    let icon: String
    let group: Group
    var keys: String? = nil
    let run: @MainActor () -> Void
}

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
            AppCommand(id: "go.campus", title: "Campus", detail: "The whole island", icon: "map", group: .go, keys: "⌘1") { [weak self] in self?.controller.showOrbit(false); self?.controller.focusBuilding(nil) },
            AppCommand(id: "go.next", title: "Next that needs you", detail: "Answers, questions, stuck sessions", icon: "exclamationmark.bubble", group: .go, keys: "N") { [weak self] in self?.controller.nextWaiting() },
            AppCommand(id: "go.up", title: "Up a level", detail: "Floor → building → campus", icon: "arrow.up", group: .go, keys: "Esc") { [weak self] in self?.controller.up() },
            AppCommand(id: "go.engine", title: "Server room", detail: "Servers, services, the DevOps agent", icon: "server.rack", group: .go) { [weak self] in self?.controller.focusBuilding("engine") },
            AppCommand(id: "go.zoomin", title: "Zoom in", icon: "plus.magnifyingglass", group: .go, keys: "+") { [weak self] in self?.controller.zoom(0.8) },
            AppCommand(id: "go.zoomout", title: "Zoom out", icon: "minus.magnifyingglass", group: .go, keys: "−") { [weak self] in self?.controller.zoom(1.25) },
            AppCommand(id: "show.search", title: "Search", detail: "Projects, sessions, questions, servers and every command", icon: "magnifyingglass", group: .show, keys: "⌘K") { [weak self] in self?.paletteOpen = true },
            AppCommand(id: "show.commands", title: "All commands and keys", icon: "keyboard", group: .show, keys: "?") { [weak self] in self?.commandsOpen = true },
            AppCommand(id: "show.status", title: statusLayer ? "Hide the Status layer" : "Show the Status layer", detail: "Status pages and CI on the campus", icon: "square.3.layers.3d", group: .show, keys: "⌘L") { [weak self] in guard let self else { return }; self.setStatusLayer(!self.statusLayer) },
            AppCommand(id: "show.terminal", title: "Terminal", icon: "terminal", group: .show, keys: "⌘J") { [weak self] in self?.terminals.toggle() },
            AppCommand(id: "show.settings", title: "Settings", icon: "gearshape", group: .show, keys: "⌘,") { [weak self] in self?.settingsOpen = true },
            AppCommand(id: "do.pause", title: projectSettings.pauseAll ? "Resume all factories" : "Pause all factories", detail: "The kill switch: nothing starts, running CEOs stop", icon: projectSettings.pauseAll ? "play.fill" : "pause.fill", group: .act) { [weak self] in guard let self else { return }; self.setPauseAll(!self.projectSettings.pauseAll) },
        ]
        if projectSettings.devops.enabled {
            c.append(AppCommand(id: "do.devops", title: "Run the DevOps agent now", icon: "wrench.and.screwdriver", group: .act) { [weak self] in self?.runDevOpsNow() })
        }
        for p in world.projects where p.factory != nil {
            c.append(AppCommand(id: "do.run:" + p.id, title: "Run now · \(p.name)", detail: "Wake its CEO", icon: "play.circle", group: .act) { [weak self] in self?.runNow(p) })
        }
        return c
    }

    /// Everything ⌘K searches: the commands, then your projects, sessions, open questions and servers.
    var searchable: [AppCommand] {
        var c = staticCommands
        for p in world.projects {
            let kind = p.factory != nil ? "Factory" : p.isChat ? "Chats" : "Project"
            c.append(AppCommand(id: "p:" + p.id, title: p.name, detail: "\(kind) · \(p.provider.displayName) · \(p.sessions.count) session\(p.sessions.count == 1 ? "" : "s")", icon: p.factory != nil ? "building.2.fill" : "building.2", group: .projects) { [weak self] in self?.controller.enterFloor(p.id) })
            if !p.isChat {
                c.append(AppCommand(id: "ps:" + p.id, title: "Settings · \(p.name)", icon: "slider.horizontal.3", group: .projects) { [weak self] in self?.openProjectSettings(p.root) })
            }
            for s in p.sessions.sorted(by: { $0.lastAt > $1.lastAt }).prefix(12) {
                c.append(AppCommand(id: "s:" + s.id, title: s.title, detail: "\(s.persona.name) · \(p.name) · \(s.state(now: world.now).label)", icon: "person", group: .sessions) { [weak self] in self?.controller.select(session: s.id) })
            }
            for d in p.factory?.openDecisions ?? [] {
                c.append(AppCommand(id: "d:" + p.id + d.id, title: d.title, detail: "\(d.id) · \(p.name)", icon: "questionmark.bubble", group: .questions) { [weak self] in self?.controller.select(decision: d.id, in: p.id) })
            }
        }
        for s in world.servers {
            c.append(AppCommand(id: "sv:" + s.id, title: s.name, detail: "\(s.kind.label) · \(s.state.label)" + (s.detail.map { " · \($0)" } ?? ""), icon: "server.rack", group: .servers) { [weak self] in self?.controller.select(server: s.id) })
        }
        return c
    }

    func openProjectSettings(_ root: String) { settingsPage = "project:" + root; settingsOpen = true }

    /// The right-click menu for what you clicked (nil: the empty world).
    func contextMenu(for t: ContextTarget?, at point: CGPoint) -> ContextMenuState {
        var items: [AppCommand] = [], title = "Campus"
        switch t {
        case .building(let k)?:
            if k == "engine" {
                title = "Server room"
                items = [AppCommand(id: "c.open", title: "Open the Server room", icon: "server.rack", group: .go) { [weak self] in self?.controller.focusBuilding("engine") },
                         AppCommand(id: "c.layer", title: statusLayer ? "Hide the Status layer" : "Show the Status layer", icon: "square.3.layers.3d", group: .show, keys: "⌘L") { [weak self] in guard let self else { return }; self.setStatusLayer(!self.statusLayer) }]
                if projectSettings.devops.enabled { items.append(AppCommand(id: "c.devops", title: "Run the DevOps agent now", icon: "wrench.and.screwdriver", group: .act) { [weak self] in self?.runDevOpsNow() }) }
                items.append(AppCommand(id: "c.servers", title: "Server settings", icon: "gearshape", group: .show) { [weak self] in self?.settingsPage = "engine"; self?.settingsOpen = true })
            } else {
                title = Provider(rawValue: k)?.displayName ?? k
                items = [AppCommand(id: "c.focus", title: "Open \(title)", icon: "building.2", group: .go) { [weak self] in self?.controller.focusBuilding(k) }]
            }
        case .project(let id)?:
            guard let p = world.project(id: id) else { break }
            title = p.name
            items.append(AppCommand(id: "c.floor", title: "Open the floor", icon: "door.left.hand.open", group: .go) { [weak self] in self?.controller.enterFloor(id) })
            if p.factory != nil {
                items.append(AppCommand(id: "c.run", title: "Run now", detail: "Wake its CEO", icon: "play.circle", group: .act) { [weak self] in self?.runNow(p) })
            }
            if !p.isChat {
                if p.factory == nil {
                    let pinned = isPinned(p)
                    items.append(AppCommand(id: "c.pin", title: pinned ? "Don't keep on campus" : "Keep on campus", icon: pinned ? "pin.slash" : "pin", group: .act) { [weak self] in self?.setPinned(p.root, on: !pinned) })
                    items.append(AppCommand(id: "c.hide", title: "Hide from campus", detail: "Nothing is deleted", icon: "eye.slash", group: .act) { [weak self] in self?.setHidden(p.root, on: true) })
                }
                items.append(AppCommand(id: "c.reveal", title: "Show in Finder", icon: "folder", group: .act) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.root)]) })
                items.append(AppCommand(id: "c.copy", title: "Copy path", icon: "doc.on.doc", group: .act) { Self.copy(p.root) })
                items.append(AppCommand(id: "c.settings", title: "Project settings", icon: "slider.horizontal.3", group: .show) { [weak self] in self?.openProjectSettings(p.root) })
            }
        case .session(let id)?:
            guard let (p, s) = session(id) else { break }
            title = "\(s.persona.name) · \(p.name)"
            items = [AppCommand(id: "c.show", title: "Show the session", detail: s.title, icon: "person", group: .go) { [weak self] in self?.controller.select(session: id) },
                     AppCommand(id: "c.take", title: "Take over in the terminal", detail: "Resume it yourself", icon: "terminal", group: .act) { [weak self] in self?.takeOver(s) },
                     AppCommand(id: "c.resume", title: "Copy the resume command", icon: "doc.on.doc", group: .act) { Self.copy(s.resumeCommand) },
                     AppCommand(id: "c.its-floor", title: "Open \(p.name)'s floor", icon: "door.left.hand.open", group: .go) { [weak self] in self?.controller.enterFloor(p.id) }]
        case .server(let c)?:
            guard c < world.racks.count else { break }
            let s = world.racks[c]
            title = s.name
            items = [AppCommand(id: "c.server", title: "Show the server", detail: s.state.label, icon: "server.rack", group: .go) { [weak self] in self?.controller.select(server: s.id) },
                     AppCommand(id: "c.settings", title: "Server settings", icon: "gearshape", group: .show) { [weak self] in self?.settingsPage = "server:" + s.id; self?.settingsOpen = true }]
        case .fountain?:
            title = "Needs you"
            items = [AppCommand(id: "c.next", title: "Next that needs you", icon: "exclamationmark.bubble", group: .go, keys: "N") { [weak self] in self?.controller.nextWaiting() }]
        case nil: break
        }
        // always at the bottom: search and the list of commands
        items.append(AppCommand(id: "c.search", title: "Search", icon: "magnifyingglass", group: .show, keys: "⌘K") { [weak self] in self?.paletteOpen = true })
        items.append(AppCommand(id: "c.all", title: "All commands and keys", icon: "keyboard", group: .show, keys: "?") { [weak self] in self?.commandsOpen = true })
        return ContextMenuState(at: point, title: title, items: items)
    }

    static func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }

    /// What the campus shows, for the `?` sheet (D74). Hover any of them for what it means right now.
    static let legend: [(String, String)] = [
        ("Rain", "CI on main is red in a project of that tower"),
        ("Clouds over the Server room", "A server warns; rain when one is down"),
        ("Drone to the fountain", "A pull request was merged"),
        ("Crane and scaffolding", "A new project: its first session is still running"),
        ("Glass lift", "A session started a sub-agent"),
        ("Packets on the road", "A deploy is running"),
        ("Smoke", "A factory works in that tower"),
        ("Night", "The sky follows your Mac's clock"),
    ]

    /// What the mouse and trackpad do, for the `?` sheet.
    static let gestures: [(String, String)] = [
        ("Click", "Open what is under the pointer: a building, a floor, someone, a server"),
        ("Right-click", "A menu for what is under the pointer"),
        ("Hover a tower", "It comes apart: browse its floors"),
        ("Wheel over an open tower", "Walk the mark through its floors; click opens the marked one"),
        ("Scroll or pinch", "Zoom"),
        ("Drag", "Move around"),
    ]
}

// MARK: - the panels

/// ⌘K: search everything and run it (D72). Arrows pick, Return runs, Esc closes.
struct CommandPalette: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = FuzzyMatch.rank(query, model.searchable, limit: 40) { $0.title + " " + $0.detail }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.muted)
                TextField("", text: $query, prompt: Text("Search projects, sessions, questions, servers, commands").foregroundStyle(Color.muted))
                    .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                    .onSubmit { run(results) }
                KeyCap("Esc")
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Rectangle().fill(Color.divider).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, c in
                            CommandRow(command: c, picked: i == picked, showGroup: true)
                                .id(i)
                                .onTapGesture { model.paletteOpen = false; c.run() }
                        }
                        if results.isEmpty {
                            Text("Nothing matches “\(query)”").font(.system(size: 12.5)).foregroundStyle(Color.muted).padding(14)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)
                .onChange(of: picked) { _, p in proxy.scrollTo(p) }
            }
        }
        .frame(width: 560)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.divider))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .onAppear { focused = true; if !model.paletteSeed.isEmpty { query = model.paletteSeed; model.paletteSeed = "" } }
        .onChange(of: query) { _, _ in picked = 0 }
        .onKeyPress(.downArrow) { picked = min(picked + 1, max(0, results.count - 1)); return .handled }
        .onKeyPress(.upArrow) { picked = max(picked - 1, 0); return .handled }
        .onExitCommand { model.paletteOpen = false }
    }

    private func run(_ results: [AppCommand]) {
        guard results.indices.contains(picked) else { return }
        model.paletteOpen = false
        results[picked].run()
    }
}

/// `?`: every command with its keys, and what the mouse does.
struct CommandSheet: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let groups: [AppCommand.Group] = [.go, .show, .act]
        let all = model.staticCommands.filter { !$0.id.hasPrefix("do.run:") }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Commands and keys").font(.system(size: 18, weight: .bold))
                Spacer()
                KeyCap("Esc")
            }
            HStack(alignment: .top, spacing: 22) {
                ForEach(groups, id: \.self) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(g.rawValue.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted).padding(.bottom, 2)
                        ForEach(all.filter { $0.group == g }) { c in
                            CommandRow(command: c, picked: false, showGroup: false).onTapGesture { model.commandsOpen = false; c.run() }
                        }
                    }
                    .frame(width: 250, alignment: .topLeading)
                }
            }
            HStack(alignment: .top, spacing: 22) {
                LegendColumn(title: "MOUSE AND TRACKPAD", rows: AppModel.gestures)
                LegendColumn(title: "ON THE CAMPUS · HOVER ONE FOR WHAT IT MEANS NOW", rows: AppModel.legend)
            }
        }
        .padding(20)
        .frame(width: 860)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.divider))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .onExitCommand { model.commandsOpen = false }
    }
}

/// The right-click menu (D72): HUD-styled, at the pointer. Click outside or Esc closes it.
struct ContextMenuView: View {
    @EnvironmentObject private var model: AppModel
    let menu: ContextMenuState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(menu.title).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.muted).lineLimit(1)
                .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
            ForEach(menu.items) { c in
                if c.id == "c.search" { Rectangle().fill(Color.divider).frame(height: 1).padding(.vertical, 3) }
                CommandRow(command: c, picked: false, showGroup: false, compact: true)
                    .onTapGesture { model.contextMenuState = nil; c.run() }
            }
        }
        .padding(5)
        .frame(width: 270)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.divider))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}

private struct CommandRow: View {
    let command: AppCommand
    let picked: Bool
    let showGroup: Bool
    var compact = false
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon).font(.system(size: 12, weight: .semibold)).frame(width: 18).foregroundStyle(Color.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title).font(.system(size: compact ? 12.5 : 13, weight: .semibold)).lineLimit(1)
                if !command.detail.isEmpty && !compact {
                    Text(command.detail).font(.system(size: 11.5)).foregroundStyle(Color.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if showGroup { Text(command.group.rawValue).font(.system(size: 11)).foregroundStyle(Color.muted) }
            if let k = command.keys { KeyCap(k) }
        }
        .padding(.horizontal, 10).padding(.vertical, compact ? 5 : 7)
        .background(picked || hover ? Color.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { if picked { Rectangle().fill(Color.signal).frame(width: 2).padding(.vertical, 6) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct LegendColumn: View {
    let title: String
    let rows: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
            ForEach(rows, id: \.0) { r in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(r.0).font(.system(size: 12.5, weight: .semibold)).frame(width: 160, alignment: .leading)
                    Text(r.1).font(.system(size: 12.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
