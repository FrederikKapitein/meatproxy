import SwiftUI
import AppKit
import FactoryCore
import FactoryCollector
import FactoryScenes

/// The Mac window as the Game HUD (D31): the world fills the window and everything floats over it as glass panels.
/// Breadcrumb top-left, Campus/Orbit in the middle, the Server room top-right; Needs you as a quest log on the left,
/// the selection as character cards on the right; level chips, Up and zoom at the bottom, and the yellow counter (D25).
struct HUDView: View {
    @EnvironmentObject private var model: AppModel
    /// the lockup flies from the loading screen to the head of the left column
    @Namespace private var lockupSpace
    /// the HUD parts have arrived (after the loading screen)
    @State private var hudShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WorldView(controller: model.controller).ignoresSafeArea().allowsHitTesting(!model.settingsOpen)
            RadialGradient(colors: [.clear, Color.ink.opacity(0.55)], center: .center, startRadius: 380, endRadius: 980)
                .ignoresSafeArea().allowsHitTesting(false)
            // while the campus is first built, the window is the loading screen alone: no HUD over it
            if !model.settingsOpen && !loading { hud }
            // the terminal (D57): over the bottom of the world, on the shell's gutters
            if !model.settingsOpen && !loading && model.terminalShown {
                // it keeps clear of the inspector when one is open, so a card's buttons stay reachable
                VStack { Spacer(minLength: 0); TerminalPanel(center: model.terminals) }
                    .padding(.leading, Shell.gutter)
                    .padding(.trailing, Shell.gutter + (model.selection.level != .all ? 348 + Shell.gap : 0))
                    .padding(.bottom, Shell.gutter + 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // D72: a right-click menu at the pointer, ⌘K search and the ? sheet; a click outside closes them
            if !model.settingsOpen && !loading {
                if let m = model.contextMenuState {
                    Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.contextMenuState = nil }
                    // its top left corner at the pointer, kept inside the window (an estimate of its height: rows of 27 pt)
                    GeometryReader { geo in
                        let h = CGFloat(m.items.count) * 27 + 40
                        ContextMenuView(menu: m)
                            .offset(x: min(m.at.x + 4, geo.size.width - 276), y: min(m.at.y + 4, geo.size.height - h - 8))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .ignoresSafeArea()
                    .onExitCommand { model.contextMenuState = nil }
                }
                if model.paletteOpen || model.commandsOpen {
                    Color.ink.opacity(0.35).ignoresSafeArea().contentShape(Rectangle())
                        .onTapGesture { model.paletteOpen = false; model.commandsOpen = false }.transition(.opacity)
                    // each its own view with a steady identity, so what you typed survives the world's refreshes
                    VStack {
                        if model.paletteOpen { CommandPalette().id("palette").padding(.top, 96) }
                        else { CommandSheet().id("commands").padding(.top, 96) }
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            // what the pointer is on in the world, beside the pointer (one tooltip style for everything, D54)
            if !model.settingsOpen && !loading && model.contextMenuState == nil, let t = model.hoverTitle {
                GeometryReader { geo in HoverTip(title: t, bounds: geo.size) }.ignoresSafeArea().allowsHitTesting(false)
            }
            // the settings drawer slides in from the right over the dimmed world; a click on the world closes it
            if model.settingsOpen {
                Color.ink.opacity(0.45).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { model.settingsOpen = false }.transition(.opacity)
                GeometryReader { geo in
                    HStack(spacing: 0) { Spacer(minLength: 0); SettingsView().frame(width: SettingsView.width(geo.size.width)) }
                }
                .ignoresSafeArea().transition(.move(edge: .trailing))
            }
            if loading {
                // the loading screen: the whole window, nothing of the HUD over it
                LoadingScreen(status: building ? model.status : nil, lockup: lockupSpace) { startupDone = true }.transition(.opacity)
            } else if let s = model.status {
                do {
                    Text(s).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                        .glass(radius: 6)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.settingsOpen)
        .animation(reduceMotion ? nil : Motion.arrive, value: loading)
        .onChange(of: loading, initial: true) { _, now in if !now { hudShown = true } }
        .background(WindowShot.active ? Color.clear : Color.ink)
        .task { await runShotActions() }

    }

    /// the campus is really being built
    private var building: Bool { model.status?.hasPrefix("Building the campus") ?? false }
    /// the factory's start-up is on screen until its last step is stamped and held (LoadingScreen decides)
    private var loading: Bool { building || !startupDone }
    @State private var startupDone = false

    /// The HUD over the world (hidden under the settings, so its key shortcuts never catch what you type there).
    private var hud: some View {
            // one grid: a 52 pt bar level with the traffic lights, then two columns on 16 pt gutters with 12 pt gaps (the
            // lockup heads the left one), and the bottom bar on the same gutters; centred things sit on the window's axis
            VStack(spacing: 0) {
                TopBar().arrive(hudShown, from: .top, order: 0)
                    .zIndex(2)
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: Shell.gap) {
                        Button { Brand.showAbout() } label: {
                            BrandLockup(size: 26).contentShape(Rectangle())
                                .matchedGeometryEffect(id: "lockup", in: lockupSpace, anchor: .topLeading)
                        }
                        .buttonStyle(LockupButtonStyle()).help("About \(Brand.name): \(Brand.productLine)")
                        // the quest log is the overview's (campus, a building, Orbit's systems); on a floor the inspector
                        // has that floor's own questions, and N or the button bottom right still goes to the next one
                        if model.selection.level.rawValue < Level.project.rawValue {
                            NeedsYouPanel().arrive(hudShown, from: .leading, order: 1)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .frame(width: 300, alignment: .leading)
                    Spacer(minLength: Shell.gutter)
                    if model.selection.level != .all {
                        InspectorPanel().frame(width: 348)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .arrive(hudShown, from: .trailing, order: 2)
                    }
                }
                .padding(.horizontal, Shell.gutter).padding(.top, Shell.gap).padding(.bottom, Shell.gap)
                Spacer(minLength: 0)
                BottomBar().padding(.horizontal, Shell.gutter).padding(.bottom, Shell.gutter).arrive(hudShown, from: .bottom, order: 3)
            }
            .ignoresSafeArea(edges: .top)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.selection.level)
    }

    private func runShotActions() async {
            guard let action = WindowShot.action else { return }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            // "hover:x,y" and "click:x,y" carry a comma of their own
            var steps: [String] = []
            for t in action.split(separator: ",").map(String.init) {
                if Double(t) != nil, let last = steps.last, last.hasPrefix("hover:") || last.hasPrefix("click:") || last.hasPrefix("uiclick:") || last.hasPrefix("context:"), !last.contains(";") { steps[steps.count - 1] += ";" + t }
                else { steps.append(t) }
            }
            for (n, step) in steps.enumerated() {
                if n > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                if step == "next" { model.controller.nextWaiting() }
                else if step == "up" { model.controller.up() }
                // D65/D66 shots: "apart:<tower>" holds a tower apart, "mark:<k>" marks storey k, "life:demo" plays all
                // of the campus's life at night, "hour:<h>" sets the clock
                else if step.hasPrefix("apart:") { model.controller.campus.holdApart(String(step.dropFirst(6))) }
                else if step.hasPrefix("mark:"), let k = Int(step.dropFirst(5)) { model.controller.campus.mark(k) }
                else if step == "life:demo" { model.controller.campus.demoLife() }
                else if step.hasPrefix("hour:"), let h = Double(step.dropFirst(5)) { model.controller.campus.setHour(h) }
                else if step == "layer:status" { model.setStatusLayer(true) }
                else if step == "commands" { model.commandsOpen = true }
                else if step.hasPrefix("search:") { model.paletteOpen = true; model.paletteSeed = String(step.dropFirst(7)) }
                else if step.hasPrefix("context:") {
                    let xy = step.dropFirst(8).split(separator: ";").compactMap { Double($0) }
                    if xy.count == 2 { WindowShot.mouse("right", x: xy[0], y: xy[1]) }
                }
                else if step.hasPrefix("building:") { model.controller.focusBuilding(String(step.dropFirst(9))) }
                // "tab:<overview|work|ceo>": that tab in the open factory's inspector
                else if step.hasPrefix("tab:"), let id = model.selection.projectID, let t = FactoryOverview.Tab(rawValue: String(step.dropFirst(4))) { model.factoryTabs[id] = t }
                else if step.hasPrefix("floor:") { model.controller.enterFloor(String(step.dropFirst(6))) }
                else if step == "orbit" { model.controller.showOrbit(true) }
                // "decision:<project id>|<D-id>", "workstream:<project id>|<W-id>"
                else if step.hasPrefix("decision:") || step.hasPrefix("workstream:") {
                    let parts = step.drop { $0 != ":" }.dropFirst().split(separator: "|").map(String.init)
                    if parts.count == 2 {
                        if step.hasPrefix("decision:") { model.controller.select(decision: parts[1], in: parts[0]) }
                        else { model.controller.select(workstream: parts[1], in: parts[0]) }
                    }
                }
                else if step == "settings" { model.settingsOpen = true }
                else if step.hasPrefix("factory:") { model.setFactory(String(step.dropFirst(8)), on: true) }
                else if step.hasPrefix("view:") { model.debugViewFile = String(step.dropFirst(5)) }
                // "runnow:<project folder>": the same as pressing Run now on that factory
                else if step == "devops:runnow" { model.runDevOpsNow() }
                // "terminal:demo": a tab with made-up output (screenshots), nothing real runs in it
                else if step == "terminal:demo" {
                    let text = "\\033[1;33m✓\\033[0m Pebble Puzzles · CEO run (taken over)\\n\\n\\033[2m> Resuming the conversation where the CEO left it…\\033[0m\\n\\nW-003 timer keeps time after resume: the tester reports the timer resets on resume.\\nNext step: delegate the fix to the developer, then ask the tester again.\\n\\n\\033[1m>\\033[0m "
                    model.terminals.open(TerminalCommand(title: "Pebble factory: CEO run", executable: "/bin/sh", args: ["-c", "printf '\(text)'; sleep 60"], cwd: nil),
                                         icon: "person.fill.checkmark")
                }
                else if step.hasPrefix("runnow:") { model.runNow(root: String(step.dropFirst(7))) }
                else if step.hasPrefix("settings:page:") { model.settingsPage = String(step.dropFirst(14)); model.settingsOpen = true }
                else if step.hasPrefix("settings:scroll:") { model.settingsScrollTo = String(step.dropFirst(16)) }
                else if step == "settings:projects" { model.settingsAtProjects = true; model.settingsOpen = true }
                else if step.hasPrefix("settings:test:") { model.debugTestHost = String(step.dropFirst(14)); model.settingsAtForm = true; model.settingsOpen = true }
                else if step == "office" { model.controller.showOrbit(false) }
                else if step.hasPrefix("session:") { model.controller.select(session: String(step.dropFirst(8))) }
                else if step.hasPrefix("zoom:"), let f = Double(step.dropFirst(5)) { model.controller.zoom(CGFloat(f)) }
                else if step == "engine" { model.controller.focusBuilding("engine") }
                else if step.hasPrefix("server:") { model.controller.select(server: String(step.dropFirst(7))) }
                else if step.hasPrefix("walker:") || step.hasPrefix("clickwalker:"), let k = Int(step.drop { $0 != ":" }.dropFirst()),
                        let p = model.controller.campus.walkerViewPoint(k), let h = model.controller.campus.view?.bounds.height {
                    WindowShot.mouse(step.hasPrefix("walker:") ? "moved" : "click", x: p.x, y: h - p.y)
                }
                else if step.hasPrefix("person:") || step.hasPrefix("clickperson:"), let p = model.controller.personViewPoint(String(step.drop { $0 != ":" }.dropFirst())) {
                    WindowShot.mouse(step.hasPrefix("person:") ? "moved" : "click", x: p.x, y: p.y)
                }
                else if step.hasPrefix("move:") {
                    let parts = step.split(separator: ":").map(String.init)
                    if parts.count == 3 { model.controller.debugWalk(parts[1], to: parts[2]) }
                }
                else if step.hasPrefix("hover:") || step.hasPrefix("click:") || step.hasPrefix("uiclick:") {
                    let xy = step.drop { $0 != ":" }.dropFirst().split(separator: ";").compactMap { Double($0) }
                    if xy.count == 2 { WindowShot.mouse(step.hasPrefix("hover:") ? "moved" : step.hasPrefix("ui") ? "uiclick" : "click", x: xy[0], y: xy[1]) }
                }
                else if step.hasPrefix("wait:"), let s = Double(step.dropFirst(5)) { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
            }
    }
}

// MARK: top bar

/// The lockup opens About: on hover a quiet raised plate appears behind it, a press moves it a pixel.
private struct LockupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LockupBody(configuration: configuration) }
}
private struct LockupBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hover = false
    var body: some View {
        configuration.label.padding(6)
            .background(hover ? Color.raised.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .offset(y: configuration.isPressed ? 1 : 0).padding(-6)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

/// The shell's measures (tactile-utility spacing): 16 pt to the window edge, 12 pt between things.
enum Shell {
    static let gutter: CGFloat = 16
    static let gap: CGFloat = 12
    /// the bar is the window's title bar: as tall as a unified toolbar, so it sits level with the traffic lights
    static let barHeight: CGFloat = 52
    /// the traffic lights end here (unified toolbar: 20 pt in, three 14 pt buttons 6 pt apart)
    static let lightsWidth: CGFloat = 78
}

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ZStack {
            HStack(spacing: Shell.gap) {
                Color.clear.frame(width: Shell.lightsWidth - Shell.gutter, height: 1)          // the traffic lights
                Breadcrumb(crumb: model.selection.crumb, provider: model.selection.provider)
                Spacer(minLength: 0)
                StatusLayerToggle()
                TerminalToggle(center: model.terminals)
                Button { model.settingsOpen = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
                }.buttonStyle(TactileButtonStyle(kind: .neutral)).help("Settings (⌘,)")
                Button { model.controller.focusBuilding("engine") } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack").foregroundStyle(Color.muted)
                        Text("Server room").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.inkText)
                        ServerLine(summary: model.world.serverSummary)
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                }.buttonStyle(TactileButtonStyle(kind: .neutral))
            }
            // the worlds switch sits on the window's centre axis, whatever is left and right of it (only while Orbit is on, D53)
            if WorldController.orbitEnabled {
                LiftedSegments(items: [.init(id: false, title: "Campus"), .init(id: true, title: "Orbit")], selected: model.selection.orbit,
                               padding: EdgeInsets(top: 2.5, leading: 16, bottom: 2.5, trailing: 16)) {
                    model.controller.showOrbit($0)
                }
                .background {
                    // ⌘1 and ⌘2 switch worlds
                    Button("") { model.controller.showOrbit(false) }.keyboardShortcut("1", modifiers: .command).opacity(0)
                    Button("") { model.controller.showOrbit(true) }.keyboardShortcut("2", modifiers: .command).opacity(0)
                }
            }
        }
        .padding(.horizontal, Shell.gutter).frame(height: Shell.barHeight)
        .background(LinearGradient(colors: [Color.ink.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }
}

/// "not connected", "6 online", or the problems in their colours ("1 warning · 1 down").
private struct ServerLine: View {
    let summary: ServerSummary
    var body: some View {
        HStack(spacing: 0) {
            if !summary.connected || (summary.warn == 0 && summary.down == 0) {
                Text(summary.line.lowercased()).foregroundStyle(summary.connected ? Color.done : Color.muted)
            } else {
                if summary.down > 0 { Text("\(summary.down) down").foregroundStyle(Color.stuck) }
                if summary.warn > 0 && summary.down > 0 { Text(" · ").foregroundStyle(Color.muted) }
                if summary.warn > 0 { Text("\(summary.warn) warning").foregroundStyle(Color.warn) }
            }
        }
        .font(.system(size: 11.5, weight: .medium).monospacedDigit()).lineLimit(1)
    }
}



private struct Breadcrumb: View {
    let crumb: [String]; let provider: Provider?
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(crumb.enumerated()), id: \.offset) { k, part in
                if k > 0 { Text("›").foregroundStyle(Color.muted) }
                Text(part).font(.system(size: 12.5, weight: k == crumb.count - 1 ? .semibold : .regular))
                    .foregroundStyle(k == 1 && provider != nil ? Color.provider(provider!) : k == crumb.count - 1 ? Color.inkText : Color.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12).frame(height: 30).glass(radius: 6)
    }
}

// MARK: Needs you, a quest log

private struct NeedsYouPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // the dot says something waits; with nothing waiting it is not there
                if !model.world.needsYou.isEmpty { Circle().fill(Color.signal).frame(width: 9, height: 9) }
                Text("Needs you").font(.system(size: 15, weight: .bold))
                Spacer()
                HStack(spacing: 5) { KeyCap("N"); Text("next").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.muted) }
                    .help("Press N to go to the next one")
            }
            if model.world.needsYou.isEmpty {
                Text(Brand.emptyState).font(.system(size: 13)).foregroundStyle(Color.muted).padding(.vertical, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let shown = Array(model.world.needsYou.prefix(6))
            let groups = Set(shown.map(\.group))
            ForEach(Array(shown.enumerated()), id: \.element.id) { k, item in
                // a heading where a group starts, once there is more than one group
                if groups.count > 1, k == 0 || shown[k - 1].group != item.group {
                    Text(item.group.label.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                        .padding(.top, k == 0 ? 0 : 4)
                }
                Button { model.controller.open(item) } label: { NeedsYouRow(item: item, first: k == 0, number: k + 1) }.buttonStyle(CardPressStyle())
                    // a new one slides in from the edge; an answered one folds away
                    .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                                      removal: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)))
            }
        }
        .padding(14).glass(radius: 12)
        .animation(reduceMotion ? nil : Motion.arrive, value: model.world.needsYou.map(\.id))
    }
}

/// One line of the quest log: a session that waits (its person and age), or a factory's question (its kind and age).
private struct NeedsYouRow: View {
    @EnvironmentObject private var model: AppModel
    let item: NeedsYou; let first: Bool; let number: Int
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(first ? Color.onSignal : Color.inkText)
                .frame(minWidth: 20, minHeight: 20)
                .background(first ? Color.signal : Color.divider, in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 13.5, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                // what a waiting session wants: the gist of its last words
                if case .session(_, let s) = item, let gist = s.lastSaidGist {
                    Text(gist).font(.system(size: 12)).foregroundStyle(Color.inkText.opacity(0.88)).lineLimit(2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                // the project gives way first (cut at its end), then nothing: who or what, and the age, always show
                HStack(spacing: 0) {
                    if isQuestion { Image(systemName: "questionmark.bubble").font(.system(size: 11, weight: .semibold)).padding(.trailing, 5) }
                    if item.project.logo != nil { ProjectLogoView(path: item.project.logo, size: 13).padding(.trailing, 5) }
                    Text(item.project.name).lineLimit(1).truncationMode(.tail)
                    Text(" · \(detail) · \(item.since.ago)").lineLimit(1).fixedSize().layoutPriority(1)
                }
                .font(.system(size: 12)).foregroundStyle(first ? Color.inkText : Color.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(first ? Color.signal : Color.divider))
        .contentShape(Rectangle())
    }
    private var isQuestion: Bool { if case .decision = item { return true }; return false }
    private var detail: String {
        switch item {
        case .session(_, let s): s.persona.name
        case .decision(_, let d): d.kind
        }
    }
}

// MARK: the selection, as character cards

private struct InspectorPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sel = model.selection
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow(sel)).font(.system(size: 11, weight: .semibold)).tracking(0.9)
                        .foregroundStyle(sel.provider.map(Color.provider) ?? Color.muted)
                    HStack(spacing: 9) {
                        // a project shows its own logo by its name (D55)
                        if sel.decisionID == nil, sel.workstreamID == nil, sel.sessionID == nil, let id = sel.projectID, let p = model.world.project(id: id) {
                            ProjectLogoView(path: p.logo, size: 26)
                        }
                        Text(title(sel)).font(.system(size: sel.decisionID != nil ? 19 : 24, weight: .bold)).lineLimit(sel.decisionID != nil || sel.workstreamID != nil ? 4 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button { model.controller.up() } label: {
                    HStack(spacing: 5) { KeyCap("esc"); Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }.padding(.horizontal, 6).frame(height: 26)
                }.buttonStyle(TactileButtonStyle(kind: .neutral)).help(sel.decisionID != nil || sel.workstreamID != nil ? "Back to the factory (Esc)" : "Up one level (Esc)")
            }
            // a factory says a lot: it scrolls when the window is short, and stays as small as it is otherwise
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 10) { content(sel) }
                ScrollView { VStack(alignment: .leading, spacing: 10) { content(sel) }.padding(.bottom, 18) }.scrollIndicators(.never)
                    .mask(VStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 22) })
            }
            .id(contentKey(sel))
            .transition(reduceMotion ? .identity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
        }
        .padding(16).glass(radius: 12)
        .animation(reduceMotion ? nil : Motion.arrive, value: contentKey(sel))
    }

    /// which card the inspector shows: a new one fades in, the old one out
    private func contentKey(_ s: WorldSelection) -> String {
        [s.engineRoom ? "engine" : "", s.projectID ?? "", s.sessionID ?? "", s.subAgentID ?? "", s.decisionID ?? "", s.workstreamID ?? ""].joined(separator: "|")
    }

    private func eyebrow(_ s: WorldSelection) -> String {
        if s.engineRoom, s.decisionID == nil, let id = s.serverID, let sv = model.world.servers.first(where: { $0.id == id }) { return "SERVER ROOM · \(sv.kind.label.uppercased())" }
        if s.engineRoom && s.decisionID == nil { return "SERVER ROOM" }
        if let id = s.decisionID, let pid = s.projectID, let (p, d) = model.world.decision(project: pid, id) {
            return "\(d.id) · \(p.name.uppercased()) · \(d.kind.uppercased())"
        }
        if let id = s.workstreamID, let pid = s.projectID, let p = model.world.project(id: pid), let w = p.factory?.workstreams.first(where: { $0.id == id }) {
            return "\(w.id) · \(p.name.uppercased()) · \(w.type.uppercased())"
        }
        if s.subAgentID != nil { return "SUB-AGENT" }
        if s.sessionID != nil { return "SESSION" }
        if let id = s.projectID, let p = model.world.project(id: id), let b = model.world.building(p.provider), let k = b.projects.firstIndex(where: { $0.id == id }) {
            let kind = p.factory != nil ? "FACTORY" : model.selection.orbit ? "SOLAR SYSTEM" : "FLOOR \(k + 1)"
            return "\(p.provider.displayName.uppercased()) · \(kind)"
        }
        return model.selection.orbit ? "GALAXY" : "BUILDING"
    }

    private func title(_ s: WorldSelection) -> String {
        if s.engineRoom, s.decisionID == nil, let id = s.serverID, let sv = model.world.servers.first(where: { $0.id == id }) { return sv.name }
        if s.engineRoom && s.decisionID == nil { return "Servers" }
        if let id = s.decisionID, let pid = s.projectID, let (_, d) = model.world.decision(project: pid, id) { return d.title }
        if let id = s.workstreamID, let pid = s.projectID, let w = model.world.project(id: pid)?.factory?.workstreams.first(where: { $0.id == id }) { return w.title }
        if let a = s.subAgentID, let sub = model.world.projects.flatMap(\.sessions).flatMap(\.subAgents).first(where: { $0.id == a }) { return sub.type }
        if let (_, session) = model.session(s.sessionID) { return session.title }
        if let id = s.projectID, let p = model.world.project(id: id) { return p.name }
        return s.provider?.displayName ?? ""
    }

    @ViewBuilder private func content(_ s: WorldSelection) -> some View {
        if s.engineRoom, s.decisionID == nil, let id = s.serverID, let server = model.world.servers.first(where: { $0.id == id }) {
            ServerDetail(server: server)
        } else if s.engineRoom && s.decisionID == nil {
            if model.projectSettings.devops.enabled { OpsCard() }
            ServicesCard()
            if model.world.servers.isEmpty {
                Text("No servers set up yet. Add yours in the settings: they are checked over SSH with your own keys, without a password.")
                    .font(.system(size: 13)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                Button { model.settingsAtForm = true; model.settingsOpen = true } label: {
                    Label("Set up servers", systemImage: "gearshape").font(.system(size: 12.5, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }.buttonStyle(TactileButtonStyle(kind: .primary)).padding(.bottom, 3)
            } else {
                ServerLine(summary: model.world.serverSummary)
                VStack(spacing: 6) {
                    ForEach(model.world.racks) { server in
                        Button { model.controller.select(server: server.id) } label: { ServerRow(server: server, picked: server.id == s.serverID).contentShape(Rectangle()) }
                            .buttonStyle(CardPressStyle())
                    }
                }
            }
        } else if let a = s.subAgentID, let (_, owner) = model.session(s.sessionID), let sub = owner.subAgents.first(where: { $0.id == a }) {
            Text(sub.summary.isEmpty ? "No description" : sub.summary).font(.system(size: 13)).foregroundStyle(Color.inkText)
            Label(sub.finished ? "Finished" : "Running", systemImage: sub.finished ? "checkmark.circle" : "circle.dotted")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(sub.finished ? Color.done : Color.working)
            Text("Helper of \(owner.persona.name) · \(owner.title)").font(.system(size: 12)).foregroundStyle(Color.muted)
            Text("\(sub.cast.role.label) · \(sub.persona.name)").font(.system(size: 12)).foregroundStyle(Color.muted)
        } else if let (_, session) = model.session(s.sessionID) {
            SessionCard(session: session, expanded: true, inInspector: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("LATELY").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                ForEach(Array(session.activities.suffix(6).reversed().enumerated()), id: \.offset) { _, a in
                    HStack(spacing: 8) {
                        Circle().fill(a.failed ? Color.stuck : Color.border).frame(width: 6, height: 6)
                        Text(a.text.prefix(1).uppercased() + a.text.dropFirst()).font(.system(size: 12)).foregroundStyle(a.failed ? Color.stuck : Color.inkText).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(a.at.ago).font(.system(size: 11)).foregroundStyle(Color.muted)
                    }
                }
            }
        } else if let id = s.decisionID, let pid = s.projectID, let (p, d) = model.world.decision(project: pid, id) {
            DecisionCard(project: p, decision: d)
        } else if let id = s.workstreamID, let pid = s.projectID, let p = model.world.project(id: pid), let w = p.factory?.workstreams.first(where: { $0.id == id }) {
            WorkstreamCard(project: p, workstream: w)
        } else if let id = s.projectID, let p = model.world.project(id: id) {
            if !p.isChat { FactorySwitch(project: p) }
            if let c = p.cost { CostLine(cost: c) }
            if let f = p.factory { FactoryOverview(project: p, factory: f).id(p.id) } else {
            if !p.isChat { Text(p.root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.muted).lineLimit(1) }
            if !p.sessions.isEmpty { StateBar(sessions: p.sessions, now: model.world.now) }
            else if p.factory != nil { Text("No session in the last 8 hours.").font(.system(size: 12)).foregroundStyle(Color.muted) }
            ForEach(p.sessions) { session in
                Button { model.controller.select(session: session.id) } label: { SessionCard(session: session, expanded: false) }.buttonStyle(CardPressStyle())
            }
            }
        } else if let prov = s.provider, let b = model.world.building(prov) {
            StateBar(sessions: b.projects.flatMap(\.sessions), now: model.world.now)
            if b.projects.isEmpty { Text("No sessions in the last 8 hours.").font(.system(size: 13)).foregroundStyle(Color.muted) }
            ForEach(Array(b.projects.enumerated().reversed()), id: \.element.id) { k, p in
                Button { model.controller.enterFloor(p.id) } label: {
                    HStack(spacing: 10) {
                        Text("\(k + 1)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(Color.muted).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                            // a factory says how its CEO stands, so a CEO that does not wake is seen from the building
                            if p.factory != nil, let line = model.factoryLine(p) {
                                Text(line.text).font(.system(size: 11)).foregroundStyle(line.warn ? Color.warn : Color.muted).lineLimit(1)
                            }
                        }
                        Spacer()
                        HStack(spacing: 3) { ForEach(p.sessions.prefix(8)) { Rectangle().fill(Color.state($0.state(now: model.world.now))).frame(width: 6, height: 6) } }
                            .help("One per session, coloured by what it is doing")
                        Text(p.cost.map { $0.today > 0 ? ProjectCost.format($0.today) : "" } ?? "").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Color.muted)
                            .frame(width: 52, alignment: .trailing).help("Today at API prices (an estimate)")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.divider)).contentShape(Rectangle())
                }.buttonStyle(CardPressStyle())
            }
        }
    }
}

/// What a floor's work would have cost at API list prices (D61): today, the last 7 days and the last 30. An estimate,
/// also for work under a subscription; tokens of a model without a known price are said, never counted as free.
struct CostLine: View {
    let cost: ProjectCost
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("API PRICE").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                Text(ProjectCost.format(cost.today)).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                Text("today").font(.system(size: 11.5)).foregroundStyle(Color.muted)
                if cost.unpricedTokens > 0 {
                    Image(systemName: "questionmark.circle").font(.system(size: 11)).foregroundStyle(Color.muted)
                        .help("\(cost.unpricedTokens.formatted()) tokens of a model without a known price are not in these sums")
                }
            }
            Text("\(ProjectCost.format(cost.week)) last 7 days · \(ProjectCost.format(cost.month)) last 30 days")
                .font(.system(size: 11.5)).foregroundStyle(Color.muted).lineLimit(1)
        }
        .help("What these sessions would have cost through the API, at list prices of \(ApiPrices.asOf). An estimate, not an invoice: under a subscription you pay the plan.")
    }
}

/// One server, deploy or backup: its state as a light, its name and kind.
private struct ServerRow: View {
    let server: Server
    /// picked in Orbit: the row lights up in the selection colour
    var picked = false
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).shadow(color: color.opacity(0.7), radius: 4)
            Image(systemName: server.kind == .server ? "server.rack" : server.kind == .deploy ? "shippingbox" : "externaldrive")
                .font(.system(size: 11)).foregroundStyle(Color.muted).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(1).help(server.kind.label)
                if let d = server.detail {
                    Text(d).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(server.state == .ok ? Color.muted : color).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            // a problem says so in words; OK is the green light alone, so what the check saw has the room
            if server.state != .ok { Text(server.state.label).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(color).lineLimit(1) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(picked ? Color.inkText : server.state == .ok ? Color.divider : color.opacity(0.35), lineWidth: picked ? 1.5 : 1))
    }
    private var color: Color { server.state == .down ? .stuck : server.state == .warn ? .warn : .done }
}

struct SessionCard: View {
    @EnvironmentObject private var model: AppModel
    let session: Session; let expanded: Bool
    /// in the inspector the header already has the title
    var inInspector = false
    var body: some View {
        let st = session.state(now: model.world.now), persona = session.persona
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(cg: model.controller.portrait(model.cast(of: session))).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    if !inInspector { Text(session.title).font(.system(size: 14, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading) }
                    Text("\(persona.name) · \(model.cast(of: session).role.label) · \(session.room(now: model.world.now).name)\(session.wentBack(now: model.world.now) ? " ↩" : "")")
                        .font(.system(size: 12)).foregroundStyle(Color.muted).lineLimit(1)
                    Text(stateLine(st)).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.state(st)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if expanded || !session.subAgents.isEmpty {
                ViewThatFits(in: .horizontal) {
                    ForEach([4, 3, 2, 1], id: \.self) { n in
                        HStack(spacing: 6) {
                            ForEach(session.subAgents.prefix(n)) { a in
                                Button { model.controller.select(session: session.id, subAgent: a.id) } label: {
                                    Text("\(a.type)\(a.finished ? " · done" : "")").font(.system(size: 10.5, design: .monospaced)).lineLimit(1).fixedSize()
                                        .foregroundStyle(a.finished ? Color.muted : Color.inkText).padding(.horizontal, 8).padding(.vertical, 3)
                                }.buttonStyle(TactileButtonStyle(kind: .neutral)).padding(.bottom, 2)
                            }
                            if session.subAgents.count > n {
                                Text("+\(session.subAgents.count - n)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.muted).fixedSize()
                                    .padding(.horizontal, 8).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.divider))
                            }
                        }
                    }
                }
            }
            if expanded, let said = session.lastSaid?.trimmingCharacters(in: .whitespacesAndNewlines), !said.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(st == .waiting ? "IT ASKS" : "LAST SAID").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                    Text(said.count > 1200 ? "…" + said.suffix(1199) : said).font(.system(size: 12.5)).lineLimit(14)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            if expanded {
                HStack(spacing: 8) {
                    // take over in the app's terminal (D57): the conversation goes on where the agent left it
                    Button { model.takeOver(session) } label: {
                        Label("Take over", systemImage: "terminal").font(.system(size: 12.5, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                    }.buttonStyle(TactileButtonStyle(kind: .neutral))
                    .help(session.heartbeatRun == true ? "Stop the CEO's run and continue it yourself in the terminal" : "Continue this conversation in the terminal")
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.resumeCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 28)
                    }.buttonStyle(TactileButtonStyle(kind: .neutral)).help("Copy: \(session.resumeCommand)")
                }.padding(.bottom, 3)
            }
        }
        .padding(12)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(st == .waiting ? Color.signal : Color.divider))
        .contentShape(Rectangle())
    }

    private func lower(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    private func stateLine(_ st: SessionState) -> String {
        switch st {
        case .waiting: "Waiting for you · \(session.lastAt.ago)"
        case .working: "Working · \(lower(session.lastAction))"
        case .stuck: "Stuck · \(lower(session.lastAction))"
        case .done: "Done · \(session.lastAt.ago)"
        }
    }
}

private struct Avatar: View {
    let cg: CGImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.raised)
            if let cg {
                Image(decorative: cg, scale: 1).resizable().scaledToFit().padding(.top, 4).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

struct StateBar: View {
    let sessions: [Session]; let now: Date
    var body: some View {
        let counts = SessionState.allCases.map { st in (st, sessions.filter { $0.state(now: now) == st }.count) }.filter { $0.1 > 0 }
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(counts, id: \.0) { st, n in Rectangle().fill(Color.state(st)).frame(width: g.size.width * CGFloat(n) / CGFloat(max(sessions.count, 1))) }
            }
        }
        .frame(height: 8).background(Color.raised).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: bottom bar

private struct BottomBar: View {
    @EnvironmentObject private var model: AppModel
    /// every control down here is this tall, so their faces and ledges share one line
    static let height: CGFloat = 40
    /// a keyboard shortcut presses its key visibly, as a click does
    @State private var nextPulse = 0
    @State private var upPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: Shell.gap) {
                // the levels you are below take you up there; the ones below you only say where you are
                let cur = model.selection.level
                LiftedSegments(items: Level.allCases.map { l in
                    .init(id: l, title: l.name, enabled: l.rawValue < cur.rawValue, help: l.rawValue < cur.rawValue ? "Up to \(l.name)" : nil)
                }, selected: cur, fontSize: 11, padding: EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10)) { l in
                    for _ in 0..<max(0, cur.rawValue - l.rawValue) { model.controller.up() }
                }
                Spacer(minLength: 0)
                let n = model.world.needsYou.count
                // the way to the next Yes: a lifted yellow key with the mark; nothing waiting is a quiet, flat key
                Button { model.controller.nextWaiting() } label: {
                    HStack(spacing: 9) {
                        if n > 0 { BrandMark(face: .onSignal, ledge: false).frame(width: 16, height: 16) }
                        Text(Brand.counter(n)).font(.system(size: 15, weight: .bold))
                            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(n))).animation(reduceMotion ? nil : Motion.slide, value: n)
                        if n > 0 { KeyCap("N", onYellow: true) }
                    }
                    .padding(.horizontal, 18).frame(height: Self.height)

                }
                .buttonStyle(TactileButtonStyle(kind: n == 0 ? .neutral : .primary, pulse: nextPulse)).disabled(n == 0)
                .background {
                    Button("") { nextPulse += 1; model.controller.nextWaiting() }.disabled(n == 0).opacity(0)
                        .keyboardShortcut(model.typing || model.terminalShown || model.overlayOpen ? nil : KeyboardShortcut("n", modifiers: []))
                    // D72: ⌘K searches everything, ? lists every command
                    Button("") { model.commandsOpen = false; model.paletteOpen.toggle() }.opacity(0).keyboardShortcut("k", modifiers: .command)
                    Button("") { model.paletteOpen = false; model.commandsOpen.toggle() }.opacity(0)
                        .keyboardShortcut(model.typing || model.terminalShown || model.paletteOpen ? nil : KeyboardShortcut("/", modifiers: .shift))
                }
                // something new waits: the key presses itself once, like a key pressed for you
                .onChange(of: n) { old, new in if new > old { nextPulse += 1 } }
            }
            // up and zoom on the window's centre axis
            HStack(spacing: 8) {
                Button { model.controller.up() } label: {
                    HStack(spacing: 7) { Text("↑ Up").font(.system(size: 13, weight: .bold)); KeyCap("esc") }.padding(.horizontal, 12).frame(height: Self.height)
                }
                    .buttonStyle(TactileButtonStyle(kind: .neutral, pulse: upPulse)).help("Up one level (Esc)")
                    .disabled(model.selection.level == .all && !model.selection.engineRoom)
                    .background {
                        Button("") { upPulse += 1; model.controller.up() }.opacity(0)
                            .keyboardShortcut(model.typing || model.terminalShown || model.overlayOpen ? nil : KeyboardShortcut(.escape, modifiers: []))
                    }
                Button { model.controller.zoom(1.25) } label: { Text("−").font(.system(size: 17, weight: .semibold)).frame(width: Self.height, height: Self.height) }
                    .buttonStyle(HUDButton()).help("Zoom out (−)")
                Button { model.controller.zoom(0.8) } label: { Text("+").font(.system(size: 17, weight: .semibold)).frame(width: Self.height, height: Self.height) }
                    .buttonStyle(HUDButton()).help("Zoom in (+)")
            }
        }
        .padding(.bottom, 3)     // room for the ledges
    }
}

/// Up and zoom: neutral Tuinstra buttons.
private struct HUDButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TactileButtonStyle(kind: .neutral).makeBody(configuration: configuration) }
}

// MARK: style

extension View {
    /// A HUD panel over the world: Tuinstra charcoal surface over a little material, a divider edge. Panels and sheets
    /// round at 12, controls at 6 (tactile-utility).
    func glass(radius: CGFloat, tint: Color = .surface) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: radius).fill(tint.opacity(0.86)))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.divider, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
    // Tuinstra Dark (tactile-utility): neutral charcoal, equal RGB channels, no blue or olive cast
    static let ink = Color(hex: 0x121212)          // page / behind the world
    static let surface = Color(hex: 0x1A1A1A)      // panels
    static let raised = Color(hex: 0x242424)       // cards, neutral buttons, selected surface
    static let divider = Color(hex: 0x3A3A3A)      // quiet separators
    static let border = Color(hex: 0x858585)       // identifying control edge
    static let inkText = Color(hex: 0xF3F3F3)      // main text
    // two text levels only (D45): main and secondary; quiet metadata is secondary at a smaller size
    static let muted = Color(hex: 0xAEAEAE)        // secondary text
    // Tuinstra yellow: the primary action (Yes) and what waits for you; ink on yellow; the yellow-brown ledge
    static let signal = Color(hex: 0xFFD83D)
    static let onSignal = Color(hex: 0x10100E)
    static let ledge = Color(hex: 0x675412)
    static let neutralLedge = Color(hex: 0x080808)
    static let dangerLedge = Color(hex: 0x6E1A1A)  // under a destructive (red) confirm
    /// a server's warning: amber, always with the word (yellow is the primary action and what waits for you)
    static let warn = Color(hex: 0xFF9F43)
    static let working = Color(hex: 0x8ab4ff)
    static let stuck = Color(hex: 0xff4a4a)
    static let done = Color(hex: 0x5fd08f)
    /// selection and hover in the worlds (D24)
    static let selection = Color(hex: 0x4fe0f5)
    static func provider(_ p: Provider) -> Color { p == .claude ? Color(hex: 0xe8916b) : Color(hex: 0x6fd3b8) }
    static func state(_ s: SessionState) -> Color {
        switch s { case .working: .working; case .waiting: .signal; case .stuck: .stuck; case .done: .done }
    }
}

extension Date {
    /// "14 min ago", "just now"
    var ago: String {
        let s = Date().timeIntervalSince(self)
        if s < 45 { return "just now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; f.locale = Locale(identifier: "en_US")
        return f.localizedString(for: self, relativeTo: Date())
    }
}

/// The hover title: a small dark card beside the pointer, its title bold and one line under it; it stays inside the
/// window and never takes a click.
private struct HoverTip: View {
    let title: HoverTitle
    let bounds: CGSize
    var body: some View {
        let w: CGFloat = 240
        // worked out step by step: as one expression it takes the CI compiler too long to type-check
        // beside the pointer, never on the plaques: over a tower it sits to the left (the plaques hang to the right)
        let beside: CGFloat = title.left ? title.at.x - 16 - w / 2 : title.at.x + 16 + w / 2
        let x: CGFloat = min(max(beside, w / 2 + 8), bounds.width - w / 2 - 8)
        let y: CGFloat = min(max(title.at.y + (title.left ? 0 : 30), 24), bounds.height - 24)
        VStack(alignment: .leading, spacing: 2) {
            Text(title.title).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
            if !title.line.isEmpty { Text(title.line).font(.system(size: 11.5)).foregroundStyle(Color.muted).lineLimit(2) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.divider))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .fixedSize()
        .frame(width: w, alignment: title.left ? .trailing : .leading)
        .position(x: x, y: y)
    }
}

/// The terminal's key in the top bar: how many tabs it has, ⌘J to show or hide it.
private struct TerminalToggle: View {
    @ObservedObject var center: TerminalCenter
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { center.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal").font(.system(size: 12.5, weight: .semibold))
                // the count sits in a fixed slot, so the bar does not shift when a tab opens
                Text(center.tabs.isEmpty ? "" : "\(center.tabs.count)").font(.system(size: 12, weight: .bold).monospacedDigit()).frame(width: 10)
                KeyCap("⌘J")
            }
            .padding(.horizontal, 9).frame(height: 30)
        }
        .buttonStyle(TactileButtonStyle(kind: .neutral)).help("Terminal (⌘J)")
        .keyboardShortcut("j", modifiers: .command)
    }
}

/// The Status layer's switch (D69): the outside on the campus, or the calm campus.
private struct StatusLayerToggle: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let on = model.statusLayer
        Button { model.setStatusLayer(!on) } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d").font(.system(size: 12.5, weight: .semibold))
                Text("Status").font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                KeyCap("⌘L")
            }
            .padding(.horizontal, 9).frame(height: 30)
        }
        .buttonStyle(TactileButtonStyle(kind: on ? .primary : .neutral))
        .help(on ? "Hide the Status layer (⌘L)" : "Show the Status layer: status pages and CI on the campus (⌘L)")
        .keyboardShortcut("l", modifiers: .command)
    }
}

/// The Server room's Services (D69): every status page you watch, and the projects whose CI on main is red.
struct ServicesCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let now = model.world.now, red = model.world.projects.filter { $0.github?.ciFailing == true }
        VStack(alignment: .leading, spacing: 6) {
            Text("SERVICES").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
            ForEach(model.world.services) { s in ServiceRow(name: s.name, state: s.shown(now: now), detail: Self.detail(s, now: now), checked: s.checkedAt.map { "Checked " + $0.ago }, page: s.page) }
            ForEach(red, id: \.id) { p in ServiceRow(name: p.name, state: .down, detail: "CI on main is red: " + (p.github?.failing.joined(separator: ", ") ?? ""), checked: p.github.map { "Checked " + $0.checkedAt.ago }, page: nil) }
            if model.world.services.isEmpty && red.isEmpty {
                Text("No status pages watched. Add them in Settings › General.").font(.system(size: 12)).foregroundStyle(Color.muted)
            }
        }
        .padding(.bottom, 4)
    }
    static func detail(_ s: ServiceStatus, now: Date) -> String {
        guard s.checkedAt != nil else { return "Not read yet" }
        if s.shown(now: now) == .unknown { return "Not read for a while" }
        return s.detail.isEmpty ? s.state.rawValue.capitalized : s.detail
    }
}

private struct ServiceRow: View {
    let name: String, state: ServiceStatus.State, detail: String, checked: String?, page: String?
    var body: some View {
        HStack(spacing: 9) {
            Rectangle().fill(colour).frame(width: 9, height: 9).overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Color.muted).lineLimit(1)
                if let checked { Text(checked).font(.system(size: 11)).foregroundStyle(Color.muted.opacity(0.8)).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let page, let u = URL(string: page) {
                Link(destination: u) { Image(systemName: "arrow.up.right.square").font(.system(size: 12)) }.foregroundStyle(Color.muted).help("Open the status page")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 6))
    }
    private var colour: Color {
        switch state {
        case .ok: return Color(hex: 0x7DFF99)
        case .degraded: return Color.warn
        case .down: return Color(hex: 0xFF4A4A)
        case .unknown: return Color(hex: 0x8C8C8C)
        }
    }
}
