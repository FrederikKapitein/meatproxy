import SwiftUI
import AppKit
import FactoryCore
import FactoryCollector
import FactoryScenes

/// The Mac window as the game HUD (D31, Spel+ D80): the world fills the window and everything floats over it in one
/// frame. One grid (E7): the location plate and the toolbar 48 high at 16 from the top; the quest log on the left and
/// the inspector on the right, both 360 wide on one top line (80); Up and zoom at the bottom centre. The terminal
/// drawer takes the bottom when it is open, and the side panels end 16 above it (E10).
struct HUDView: View {
    @EnvironmentObject private var model: AppModel
    /// the lockup on the loading screen
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
            if !loading { hud.allowsHitTesting(!model.settingsOpen) }   // under Settings it stays, dimmed and asleep, as under every sheet
            // D72: a right-click menu at the pointer, ⌘K search, Help and the factory picker; a click outside closes them
            if !model.settingsOpen && !loading {
                if let m = model.contextMenuState {
                    Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.contextMenuState = nil }
                    // its top left corner at the pointer, kept inside the window (an estimate of its height: rows of 30 pt)
                    GeometryReader { geo in
                        let h = CGFloat(m.items.count) * 30 + 44
                        ContextMenuView(menu: m)
                            .offset(x: min(m.at.x + 4, geo.size.width - 296), y: min(m.at.y + 4, geo.size.height - h - 8))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .ignoresSafeArea()
                    .onExitCommand { model.contextMenuState = nil }
                }
                if model.paletteOpen || model.commandsOpen || model.factoryPickerOpen {
                    Color.ink.opacity(0.5).ignoresSafeArea().contentShape(Rectangle())
                        .onTapGesture { model.paletteOpen = false; model.commandsOpen = false; model.factoryPickerOpen = false }.transition(.opacity)
                    // each its own view with a steady identity, so what you typed survives the world's refreshes
                    VStack {
                        if model.paletteOpen { CommandPalette(seed: model.paletteSeed).id("palette") }
                        else if model.factoryPickerOpen { FactoryPicker().id("picker") }
                        else { CommandSheet().id("commands") }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, Shell.top).padding(.horizontal, Shell.gutter).ignoresSafeArea()   // on the same top line as Settings
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            // what the pointer is on in the world, beside the pointer (one tooltip style for everything, D54)
            if !model.settingsOpen && !loading && model.contextMenuState == nil, let t = model.hoverTitle {
                GeometryReader { geo in HoverTip(title: t, bounds: geo.size) }.ignoresSafeArea().allowsHitTesting(false)
            }
            // Settings (E8): the same floating frame as every sheet, over the dimmed world; a click beside it closes it
            if model.settingsOpen {
                Color.ink.opacity(0.55).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { model.settingsOpen = false }.transition(.opacity)
                GeometryReader { geo in
                    SettingsView(page: model.settingsPage, atProjects: model.settingsAtProjects, atForm: model.settingsAtForm)
                        .frame(width: min(Shell.wideSheet, geo.size.width - 2 * Shell.gutter))
                        .frame(maxHeight: geo.size.height - Shell.top - Shell.gutter, alignment: .top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, Shell.top)
                }
                .ignoresSafeArea()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
            if loading {
                // the loading screen: the whole window, nothing of the HUD over it
                LoadingScreen(status: building ? model.status : nil, lockup: lockupSpace) { startupDone = true }.transition(.opacity)
            } else if let s = model.status {
                VStack {
                    Spacer()
                    Text(s).font(.s13m).foregroundStyle(Color.inkText).padding(.horizontal, 16).padding(.vertical, 10).spelFrame()
                        .padding(.bottom, 96)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.settingsOpen)
        .animation(reduceMotion ? nil : Motion.arrive, value: loading)
        .onChange(of: loading, initial: true) { _, now in if !now { hudShown = true } }
        .background(WindowShot.active ? Color.clear : Color.ink)
        .task { await runShotActions() }
        // the free area between the panels, for the world to frame things in (Shell's measures, the drawer's height)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in windowSize = size; updateFreeArea() }
        .onChange(of: model.selection.level) { _, _ in updateFreeArea() }
        .onChange(of: model.terminalShown) { _, _ in updateFreeArea() }
        .onReceive(model.terminals.$height) { _ in updateFreeArea() }
    }

    @State private var windowSize: CGSize = .zero
    private func updateFreeArea() {
        let g = Shell.gutter, w = windowSize.width, h = windowSize.height
        guard w > 0, h > 0 else { return }
        let left = g + Shell.side + g
        let right = w - (model.selection.level != .all ? g + Shell.side + g : g)
        let bottom = h - (model.terminalShown ? model.terminals.height + 2 * g : Shell.bar + 2 * g)
        let area = CGRect(x: left, y: Shell.top, width: max(0, right - left), height: max(0, bottom - Shell.top))
        if area != model.freeArea { model.freeArea = area; model.controller.setSafeArea(area) }
    }

    /// the campus is really being built
    private var building: Bool { model.status?.hasPrefix("Building the campus") ?? false }
    /// the factory's start-up is on screen until its last step is stamped and held (LoadingScreen decides)
    private var loading: Bool { building || !startupDone }
    @State private var startupDone = false

    /// The HUD over the world (hidden under Settings, so its key shortcuts never catch what you type there).
    private var hud: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Shell.gap) {
                LocationPlate().padding(.leading, Shell.lightsInset).arrive(hudShown, from: .top, order: 0)
                Spacer(minLength: 0)
                Toolbar().arrive(hudShown, from: .top, order: 0)
            }
            .frame(height: Shell.bar)
            .padding(.horizontal, Shell.gutter).padding(.top, Shell.gutter)
            .zIndex(2)
            .overlay(alignment: .bottom) { FieldNoteBanner().offset(y: Shell.gutter + 64).zIndex(3) }
            HStack(alignment: .top, spacing: 0) {
                QuestLog().frame(width: Shell.side).arrive(hudShown, from: .leading, order: 1)
                Spacer(minLength: Shell.gutter)
                if model.selection.level != .all {
                    InspectorPanel().frame(width: Shell.side)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .arrive(hudShown, from: .trailing, order: 2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Shell.gutter).padding(.top, Shell.gutter).padding(.bottom, Shell.gutter)
            if model.terminalShown {
                // the drawer is a panel like the others, on the shell's gutters; the side panels end 16 above it
                TerminalPanel(center: model.terminals)
                    .padding(.horizontal, Shell.gutter).padding(.bottom, Shell.gutter)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if model.walkStep != nil {
                    WalkCard().padding(.bottom, Shell.gap).transition(.move(edge: .bottom).combined(with: .opacity))
                }
                BottomBar().padding(.bottom, Shell.gutter).arrive(hudShown, from: .bottom, order: 3)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background { if !model.settingsOpen { KeyCatcher() } }   // Settings keeps its keys while it is open
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.selection.level)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.terminalShown)
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
            // "help:guide": Help on its Field guide tab
            else if step == "help:guide" { model.helpTab = .guide; model.commandsOpen = true }
            // "pick": the factory picker the walk's last quest opens (D1)
            else if step == "pick" { model.factoryPickerOpen = true }
            // "quest:<root>": the walk's factory quest landed on that floor (step 2 of 2)
            else if step.hasPrefix("quest:") { model.factoryQuest = String(step.dropFirst(6)) }
            else if step.hasPrefix("search:") { model.paletteSeed = String(step.dropFirst(7)); model.paletteOpen = true }
            else if step.hasPrefix("context:") {
                let xy = step.dropFirst(8).split(separator: ";").compactMap { Double($0) }
                if xy.count == 2 { WindowShot.mouse("right", x: xy[0], y: xy[1]) }
            }
            else if step.hasPrefix("building:") { model.controller.focusBuilding(String(step.dropFirst(9))) }
            // "tab:<overview|work|ceo|team>": that tab in the open floor's inspector
            else if step.hasPrefix("tab:"), let t = FactoryOverview.Tab(rawValue: String(step.dropFirst(4))) {
                if let id = model.selection.projectID { model.factoryTabs[id] = t } else { model.pendingTab = t }
            }
            // "group:<rhythm|wakes|autonomy|limits|models|contract>": that group open on the CEO tab
            else if step.hasPrefix("group:") { model.ceoGroup = String(step.dropFirst(6)) }
            else if step.hasPrefix("floor:") {
                let id = String(step.dropFirst(6))
                model.controller.enterFloor(id)
                if let t = model.pendingTab { model.factoryTabs[id] = t; model.pendingTab = nil }
            }
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
            else if step == "settings:projects" { model.settingsAtProjects = true; model.settingsOpen = true }
            // "settings:<general|sources|privacy|engine>": Settings on that tab (the same as settingspage:)
            else if step.hasPrefix("settings:"), ["general", "sources", "privacy", "engine"].contains(String(step.dropFirst(9))) {
                model.settingsPage = String(step.dropFirst(9)); model.settingsOpen = true
            }
            // "settingspage:<general|sources|privacy|engine|project:<root>|server:<id>>": Settings open on that page
            else if step.hasPrefix("settingspage:") { model.settingsPage = String(step.dropFirst(13)); model.settingsOpen = true }
            else if step.hasPrefix("walk:"), let k = Int(step.dropFirst(5)) { model.walkStep = k; model.walkGoalDone = false; if k == 1 { model.controller.focusBuilding("claude") } }
            // "walkdone": the open step's goal ticked off
            else if step == "walkdone" { model.walkGoalDone = true }
            else if step.hasPrefix("factory:") { model.setFactory(String(step.dropFirst(8)), on: true) }
            else if step.hasPrefix("view:") { model.debugViewFile = String(step.dropFirst(5)) }
            // "runnow:<project folder>": the same as pressing Run now on that factory
            else if step == "devops:runnow" { model.runDevOpsNow() }
            // "terminal:demo": a tab with made-up output (screenshots), nothing real runs in it
            else if step == "terminal:demo" {
                let text = "\\033[1;32m✓\\033[0m Pebble Puzzles · CEO run (taken over)\\n\\033[2m> Resuming the conversation where the CEO left it…\\033[0m\\n\\nW-003 timer keeps time after resume: the tester reports the timer resets on resume.\\nNext step: delegate the fix to the developer, then ask the tester again.\\n\\n\\033[1m>\\033[0m "
                model.terminals.open(TerminalCommand(title: "Pebble factory: CEO run", executable: "/bin/sh", args: ["-c", "printf '\(text)'; sleep 60"], cwd: nil),
                                     icon: "person.fill.checkmark")
            }
            else if step.hasPrefix("runnow:") { model.runNow(root: String(step.dropFirst(7))) }
            else if step.hasPrefix("settings:page:") { model.settingsPage = String(step.dropFirst(14)); model.settingsOpen = true }
            else if step.hasPrefix("settings:scroll:") { model.settingsScrollTo = String(step.dropFirst(16)) }
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
            // "key:<n|esc|1|2|k>": a key press as from the keyboard (⌘ with "cmd-" in front: "key:cmd-k")
            else if step.hasPrefix("key:") { WindowShot.key(String(step.dropFirst(4))) }
            else if step.hasPrefix("wait:"), let s = Double(step.dropFirst(5)) { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
        }
    }
}

/// The shell's measures (E7): 16 to the window edge, 12 between things, a 48 bar at 16 from the top, side panels 360
/// on the 80 top line; sheets 560, Settings and Help 760.
enum Shell {
    static let gutter: CGFloat = 16
    static let gap: CGFloat = 12
    static let bar: CGFloat = 48
    /// the side panels' shared top line
    static let top: CGFloat = 80
    static let side: CGFloat = 360
    static let sheet: CGFloat = 560
    static let wideSheet: CGFloat = 760
    /// the window's traffic lights sit at the top left of the title bar; the plate starts beside them
    static let lightsInset: CGFloat = 70
}

// MARK: keys

/// The HUD's plain keys in one place, so they work whatever panel is open: N (next that waits), Esc (up), ⌘K (search),
/// ? (Help), ⌘1 (Campus), ⌘2 (Server room), 1 and 2 (answer the open question). A text field, the terminal or an open
/// sheet keeps them.
private struct KeyCatcher: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let free = !(model.typing || model.terminalShown || model.overlayOpen)
        ZStack {
            Button("") { model.nextPulse += 1; model.nextPressed += 1; model.controller.nextWaiting() }
                .keyboardShortcut(free && !model.world.needsYou.isEmpty ? KeyboardShortcut("n", modifiers: []) : nil)
            Button("") { model.upPulse += 1; model.controller.up() }
                .keyboardShortcut(free ? KeyboardShortcut(.escape, modifiers: []) : nil)
            Button("") { model.commandsOpen = false; model.factoryPickerOpen = false; model.paletteOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
            Button("") { model.paletteOpen = false; model.commandsOpen.toggle() }
                .keyboardShortcut(model.typing || model.terminalShown || model.paletteOpen ? nil : KeyboardShortcut("/", modifiers: .shift))
            Button("") { model.controller.showOrbit(false); model.controller.focusBuilding(nil) }.keyboardShortcut("1", modifiers: .command)
            Button("") { model.controller.showOrbit(false); model.controller.focusBuilding("engine") }.keyboardShortcut("2", modifiers: .command)
            // the open question's answers (C4): 1 is yes, 2 is no; both still ask once more before anything is written
            Button("") { guard model.answerable else { return }; model.answerKey = AppModel.AnswerKey(count: model.answerKey.count + 1, yes: true) }
                .keyboardShortcut(free ? KeyboardShortcut("1", modifiers: []) : nil)
            Button("") { guard model.answerable else { return }; model.answerKey = AppModel.AnswerKey(count: model.answerKey.count + 1, yes: false) }
                .keyboardShortcut(free ? KeyboardShortcut("2", modifiers: []) : nil)
        }
        .opacity(0).accessibilityHidden(true)
    }
}

// MARK: the location plate

/// Top left (C3): the brand mark and where you are, in the world's words. Every part but the last takes you back up
/// there; Esc is Up, the one way back.
private struct LocationPlate: View {
    @EnvironmentObject private var model: AppModel
    struct Crumb { let icon: String; let name: String }
    var body: some View {
        let crumbs = Self.crumbs(model.selection, world: model.world, model: model)
        HStack(spacing: 4) {
            Button { Brand.showAbout() } label: {
                BrandMark().frame(width: 26, height: 26).padding(.horizontal, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("About \(Brand.name): \(Brand.productLine)").accessibilityLabel("About \(Brand.name)")
            Rectangle().fill(Color.divider).frame(width: 2, height: 28).padding(.horizontal, 6)
            ForEach(Array(crumbs.enumerated()), id: \.offset) { k, c in
                if k > 0 { PixelIcon("chev", color: .muted, size: 9).padding(.horizontal, 2) }
                if k == crumbs.count - 1 {
                    HStack(spacing: 6) { PixelIcon(c.icon, color: .muted); Text(c.name).font(.s15b).foregroundStyle(Color.inkText).lineLimit(1) }
                        .padding(.leading, 6)
                        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                } else {
                    let up = crumbs.count - 1 - k
                    CrumbButton(icon: c.icon, name: c.name) { for _ in 0..<up { model.controller.up() } }
                        .help(up == 1 ? "Back to \(c.name) (Esc)" : "Back to \(c.name)")
                }
            }
        }
        .padding(.leading, 6).padding(.trailing, 14)
        .frame(height: Shell.bar)
        .spelFrame()
        .accessibilityElement(children: .contain).accessibilityLabel("Where you are")
    }

    static func crumbs(_ s: WorldSelection, world: World, model: AppModel) -> [Crumb] {
        if s.orbit { return s.crumb.map { Crumb(icon: "star", name: $0) } }
        var c = [Crumb(icon: "campus", name: "Campus")]
        if s.engineRoom {
            c.append(Crumb(icon: "server", name: "Server room"))
            if let id = s.serverID, let sv = world.servers.first(where: { $0.id == id }) { c.append(Crumb(icon: "server", name: sv.name)) }
            if let d = s.decisionID { c.append(Crumb(icon: "bang", name: d)) }
            return c
        }
        if let p = s.provider { c.append(Crumb(icon: "tower", name: p.displayName)) }
        if let id = s.projectID, let p = world.project(id: id) { c.append(Crumb(icon: "floor", name: p.name)) }
        if let (_, session) = model.session(s.sessionID) { c.append(Crumb(icon: "person", name: session.persona.name)) }
        if let a = s.subAgentID, let sub = world.projects.flatMap(\.sessions).flatMap(\.subAgents).first(where: { $0.id == a }) { c.append(Crumb(icon: "person", name: sub.type)) }
        if let w = s.workstreamID { c.append(Crumb(icon: "branch", name: w)) }
        if let d = s.decisionID { c.append(Crumb(icon: "bang", name: d)) }
        return c
    }
}

private struct CrumbButton: View {
    let icon: String, name: String, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { PixelIcon(icon, color: .muted); Text(name).font(.s13m).lineLimit(1) }
                .foregroundStyle(hover ? Color.inkText : Color.muted)
                .padding(.horizontal, 8).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.raised : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

// MARK: the toolbar

/// Top right (C8): one toolbar, five buttons of one shape: icon, label and key. Open terminal tabs are a badge on the
/// terminal's button; the Status layer, when on, is lit white.
private struct Toolbar: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 6) {
            ToolButton(icon: "search", title: "Search", key: "⌘K", help: "Search projects, people, questions and servers (⌘K)") {
                model.commandsOpen = false; model.paletteOpen.toggle()
            }
            ToolButton(icon: "layers", title: "Status", key: "⌘L", on: model.statusLayer,
                       help: model.statusLayer ? "Hide the Status layer (⌘L)" : "Show the Status layer: status pages and CI on the campus (⌘L)") {
                model.setStatusLayer(!model.statusLayer)
            }
            .keyboardShortcut("l", modifiers: .command)
            TerminalButton(center: model.terminals)
            ToolButton(icon: "help", title: "Help", key: "?", help: "Every key, and the field guide (?)") {
                model.paletteOpen = false; model.commandsOpen.toggle()
            }
            ToolButton(icon: "gear", title: "Settings", key: "⌘,", help: "Settings (⌘,)") { model.settingsOpen = true }
            // the worlds switch, only while Orbit is on (D53)
            if WorldController.orbitEnabled {
                LiftedSegments(items: [.init(id: false, title: "Campus"), .init(id: true, title: "Orbit")], selected: model.selection.orbit) {
                    model.controller.showOrbit($0)
                }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: Shell.bar)
        .spelFrame()
        .accessibilityElement(children: .contain).accessibilityLabel("Tools")
    }
}

private struct ToolButton: View {
    let icon: String, title: String, key: String
    var on = false
    var badge: Int = 0
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                PixelIcon(icon, color: on ? .onSignal : .muted)
                Text(title).font(.s13b)
                KeyCap(key)
            }
            .padding(.leading, 9).padding(.trailing, 8).frame(height: 32)
        }
        .buttonStyle(ToolButtonStyle(on: on))
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text("\(badge)").font(.system(size: 11, weight: .heavy).monospacedDigit()).foregroundStyle(Color(hex: 0x0E1830))
                    .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.working))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.panel, lineWidth: 2))
                    .offset(x: 7, y: -7).allowsHitTesting(false)
            }
        }
        .help(help)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) open" : title)
        .accessibilityValue(on ? "On" : "")
    }
}

/// A toolbar button: 32 high, radius 10; lit white when its thing is on.
private struct ToolButtonStyle: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View { ToolButtonBody(configuration: configuration, on: on) }
}
private struct ToolButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let on: Bool
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        let pressed = configuration.isPressed
        let top: Color = on ? .lit : hover ? Color(hex: 0x3B3B3B) : Color(hex: 0x333333)
        let bottom: Color = on ? .lit2 : Color(hex: 0x292929)
        return configuration.label
            .foregroundStyle(on ? Color.onSignal : Color.inkText)
            .background(shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(on ? Color.white : Color.border, lineWidth: 2))
            .background(shape.fill(on ? Color.litLedge : Color.plinth).offset(y: pressed ? 0 : 3))
            .offset(y: pressed ? (reduceMotion ? 1 : 3) : 0)
            .animation(reduceMotion ? nil : pressed ? Motion.pressIn : Motion.springBack, value: pressed)
            .contentShape(shape)
            .onHover { hover = $0 }
    }
}

/// The terminal's button: its tabs as a badge, ⌘J to show or hide the drawer.
private struct TerminalButton: View {
    @ObservedObject var center: TerminalCenter
    var body: some View {
        ToolButton(icon: "terminal", title: "Terminal", key: "⌘J", on: center.shown, badge: center.tabs.count,
                   help: center.shown ? "Hide the terminal (⌘J)" : "Terminal (⌘J)") {
            withAnimation(.easeOut(duration: 0.2)) { center.toggle() }
        }
        .keyboardShortcut("j", modifiers: .command)
    }
}

// MARK: Needs you, a quest log

/// Needs you as a quest log (C2), on every level. On a floor it starts on "This floor", with the rest one click away;
/// Next (N) goes to the next one wherever it is.
private struct QuestLog: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var all = false

    /// the place the log can narrow to: this floor, or the Server room
    private var here: (label: String, match: (NeedsYou) -> Bool)? {
        let s = model.selection
        if s.engineRoom { return ("Server room", { $0.group == .serverRoom }) }
        if let id = s.projectID, id != World.opsID { return ("This floor", { $0.project.id == id }) }
        return nil
    }

    var body: some View {
        let items = model.world.needsYou
        let here = self.here
        let mine = here.map { h in items.filter(h.match) } ?? items
        let narrowed = here != nil && !all
        let shown = narrowed ? mine : items
        let step = model.walkStep ?? 0
        let walking = step >= 1 && step != 3 && step <= WalkCard.steps.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Socket(size: 36) { PixelIcon("scroll", color: items.isEmpty ? .muted : .signal) }
                Text("Needs you").font(.s19).foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                Button { model.nextPressed += 1; model.controller.nextWaiting() } label: { SpelLabel("Next", key: "N") }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, pulse: model.nextPulse))
                    .disabled(items.isEmpty)
                    .help("Go to the next one that waits for you (N)")
            }
            // while the walk runs, the log says so in a line of its own, never over a card
            if walking { Tag("Waits until the walk is done", icon: "pause").padding(.top, 12).zIndex(1) }
            if let here, !items.isEmpty {
                LiftedSegments(items: [.init(id: false, title: "\(here.label) · \(mine.count)"), .init(id: true, title: "All · \(items.count)")],
                               selected: all, fontSize: 13, padding: EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9)) { all = $0 }
                    .padding(.top, 12)
            }
            if items.isEmpty {
                Text(Brand.emptyState).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            } else {
                ScrollFit {
                    VStack(alignment: .leading, spacing: 8) {
                        if narrowed, let here { Eyebrow("On \(here.label.lowercased())") }
                        ForEach(Array(shown.prefix(16).enumerated()), id: \.element.id) { k, item in
                            if !narrowed && (k == 0 || shown[k - 1].group != item.group) {
                                Eyebrow(item.group.label).padding(.top, k == 0 ? 0 : 6)
                            }
                            Button { model.controller.open(item) } label: { QuestItem(item: item, selected: isOpen(item)) }
                                .buttonStyle(CardPressStyle())
                                // a new one slides in from the edge; an answered one folds away
                                .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                                                  removal: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)))
                        }
                        if narrowed, let here {
                            if mine.isEmpty { Text("Nothing waits on \(here.label.lowercased()).").font(.s13).foregroundStyle(Color.muted) }
                            if items.count > mine.count { moreRow(items.count - mine.count) }
                        }
                    }
                    .padding(.top, 14).padding(.bottom, 4)
                }
            }
        }
        .padding(16)
        .spelFrame()
        // while the walk runs, the log waits for it (D9): its cards dim, the line above them stays readable; its own
        // step (Needs you) lights it again
        .overlay(alignment: .bottom) {
            if walking {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 0)
                    .fill(Color.ink.opacity(0.62))
                    .padding(.top, 96)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : Motion.arrive, value: model.world.needsYou.map(\.id))
        .onChange(of: model.selection.projectID) { _, _ in all = false }
        .onChange(of: model.selection.engineRoom) { _, _ in all = false }
        .accessibilityElement(children: .contain).accessibilityLabel("Needs you")
    }

    private func moreRow(_ n: Int) -> some View {
        Button { all = true } label: {
            HStack(spacing: 6) {
                PixelIcon("chevd", color: .muted, size: 9)
                Text("\(n) more \(model.selection.engineRoom ? "elsewhere" : "on other floors")").font(.s13m)
            }
            .foregroundStyle(Color.muted).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).frame(height: 30)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func isOpen(_ item: NeedsYou) -> Bool {
        let s = model.selection
        switch item {
        case .decision(let p, let d): return s.decisionID == d.id && s.projectID == p.id
        case .session(_, let x): return s.sessionID == x.id
        case .release(let p, _): return s.projectID == p.id && s.decisionID == nil && s.sessionID == nil && s.workstreamID == nil
        }
    }
}

/// One quest: the marker, what it asks, and where and when, quietly.
private struct QuestItem: View {
    let item: NeedsYou
    let selected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            QuestMarker(glyph: glyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.s15).foregroundStyle(Color.inkText).lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if case .session(_, let s) = item, let gist = s.lastSaidGist {
                    Text(gist).font(.s13).foregroundStyle(Color.muted).lineLimit(2).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    PixelIcon(metaIcon, color: .muted, size: 9)
                    Text(item.project.name).lineLimit(1).truncationMode(.tail)
                    Text("· \(detail) · \(item.since.ago)").lineLimit(1).fixedSize().layoutPriority(1)
                }
                .font(.s11n).foregroundStyle(Color.muted).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.selection : Color.divider, lineWidth: 2))
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.plinth).offset(y: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
    private var glyph: String {
        switch item {
        case .session: "help"
        case .decision(let p, let d): p.id == World.opsID ? "server" : d.isTodo ? "check" : "bang"
        case .release: "ship"
        }
    }
    private var metaIcon: String {
        switch item { case .session: "chat"; case .decision(let p, _): p.id == World.opsID ? "server" : "floor"; case .release: "floor" }
    }
    private var detail: String {
        switch item {
        case .session(_, let s): s.persona.name
        case .decision(_, let d): d.isTodo ? "to-do" : d.kind
        case .release(_, let ws): ws.count == 1 ? "ready to release" : "\(ws.count) ready to release"
        }
    }
}

/// As tall as its content when that fits; otherwise it scrolls in the room it has, and says that there is more.
struct ScrollFit<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ViewThatFits(in: .vertical) {
            content()
            // the "more" line has a row of its own under the list, so it never prints over the last row's text
            VStack(spacing: 4) {
                ScrollView { content() }.scrollIndicators(.automatic)
                    .mask(VStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16) })
                HStack(spacing: 5) { PixelIcon("chevd", color: .muted, size: 9); Text("More · scroll").font(.s11n) }
                    .foregroundStyle(Color.muted).frame(maxWidth: .infinity).frame(height: 16)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: the bottom bar

/// Up and zoom on the window's centre axis (C3): Up with its key is the one way back; the level segments are gone.
private struct BottomBar: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Button { model.controller.up() } label: { SpelLabel("Up", icon: "up", key: "esc", iconColor: .inkText) }
                .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, pulse: model.upPulse))
                .help("Up one level (Esc)")
                .disabled(model.selection.level == .all && !model.selection.engineRoom)
            Button { model.controller.zoom(1.25) } label: { PixelIcon("minus", color: .inkText) }
                .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: true)).help("Zoom out (−)").accessibilityLabel("Zoom out")
            Button { model.controller.zoom(0.8) } label: { PixelIcon("plus", color: .inkText) }
                .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: true)).help("Zoom in (+)").accessibilityLabel("Zoom in")
        }
        .padding(.horizontal, 8).frame(height: Shell.bar)
        .spelFrame()
    }
}

// MARK: shared bits

extension Date {
    /// "14 min. ago", "just now"
    var ago: String {
        let s = Date().timeIntervalSince(self)
        if s < 45 { return "just now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; f.locale = Locale(identifier: "en_US")
        return f.localizedString(for: self, relativeTo: Date())
    }
}

/// The hover title: a small frame beside the pointer, its title bold and one line under it; it stays inside the
/// window and never takes a click.
private struct HoverTip: View {
    let title: HoverTitle
    let bounds: CGSize
    var body: some View {
        let w: CGFloat = 260
        // worked out step by step: as one expression it takes the CI compiler too long to type-check
        // beside the pointer, never on the plaques: over a tower it sits to the left (the plaques hang to the right)
        let beside: CGFloat = title.left ? title.at.x - 16 - w / 2 : title.at.x + 16 + w / 2
        let x: CGFloat = min(max(beside, w / 2 + 8), bounds.width - w / 2 - 8)
        let y: CGFloat = min(max(title.at.y + (title.left ? 0 : 30), 24), bounds.height - 24)
        VStack(alignment: .leading, spacing: 2) {
            Text(title.title).font(.s13b).foregroundStyle(Color.inkText).lineLimit(1)
            if !title.line.isEmpty { Text(title.line).font(.s11n).foregroundStyle(Color.muted).lineLimit(2) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .spelFrame()
        .fixedSize()
        .frame(width: w, alignment: title.left ? .trailing : .leading)
        .position(x: x, y: y)
    }
}

/// The Server room's Services (D69): every status page you watch, and the projects whose CI on main is red.
struct ServicesCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let now = model.world.now, red = model.world.projects.filter { $0.github?.ciFailing == true }
        VStack(alignment: .leading, spacing: 8) {
            SectionHead("Services", icon: "layers")
            VStack(spacing: 0) {
                ForEach(Array(model.world.services.enumerated()), id: \.element.id) { k, s in
                    if k > 0 { RowDivider() }
                    ServiceRow(name: s.name, state: s.shown(now: now), detail: Self.detail(s, now: now), checked: s.checkedAt.map { "Checked " + $0.ago }, page: s.page)
                }
                ForEach(red, id: \.id) { p in
                    RowDivider()
                    ServiceRow(name: p.name, state: .down, detail: "CI on main is red: " + (p.github?.failing.joined(separator: ", ") ?? ""), checked: p.github.map { "Checked " + $0.checkedAt.ago }, page: nil)
                }
                if model.world.services.isEmpty && red.isEmpty {
                    Text("No status pages watched. Add them in Settings › Sources.").font(.s13).foregroundStyle(Color.muted).padding(12)
                }
            }
            .spelCard(pad: 0)
        }
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
        HStack(spacing: 10) {
            StateLight(state: state == .ok ? .ok : state == .degraded ? .warn : state == .down ? .down : .unknown)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.s13m).foregroundStyle(Color.inkText).lineLimit(1)
                Text([detail, checked].compactMap { $0 }.joined(separator: " · ")).font(.s11n).foregroundStyle(Color.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let page, let u = URL(string: page) {
                Link(destination: u) { PixelIcon("chev", color: .muted, size: 9).frame(width: 20, height: 20) }.help("Open the status page").accessibilityLabel("Open the status page of \(name)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// A state as shape and colour, never colour alone: a green dot, an amber triangle, a red square, a grey ring.
struct StateLight: View {
    enum S { case ok, warn, down, unknown, busy }
    let state: S
    var body: some View {
        switch state {
        case .ok: PixelIcon("dot", color: .done, size: 9).accessibilityLabel("OK")
        case .warn: PixelIcon("warn", color: .warn, size: 9).accessibilityLabel("Warning")
        case .down: PixelIcon("sq", color: .stuck, size: 9).accessibilityLabel("Down")
        case .busy: PixelIcon("dot", color: .working, size: 9).accessibilityLabel("Busy")
        case .unknown: PixelIcon("ring", color: .muted, size: 9).accessibilityLabel("Unknown")
        }
    }
}

// MARK: the first walk and the field notes (D78)

/// The first time an effect shows on the campus: what it is, for a few seconds under the top bar.
struct FieldNoteBanner: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let n = model.fieldNote {
            HStack(alignment: .top, spacing: 10) {
                Socket(size: 36) { PixelIcon("star", color: .inkText) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("New on the campus: " + n.title).font(.s15).foregroundStyle(Color.inkText)
                    Text(n.line).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Kept in the field guide (Help › Field guide)").font(.s11n).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                CloseButton(action: { model.fieldNote = nil }, help: "Close")
            }
            .padding(12).frame(width: 460, alignment: .leading).spelFrame()
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}

/// The guided first walk (D78, D8, D9): offered once, on the campus, without yellow; it goes away as soon as you open
/// something yourself. Each step has one goal: while it is open there is no Next; when you do it, it ticks off and
/// one button takes you on.
struct WalkCard: View {
    @EnvironmentObject private var model: AppModel
    static let steps: [(title: String, text: String, goal: String)] = [
        ("Your campus", "Every Claude Code and Codex chat from the last 8 hours lives here. One tower per tool: Claude and ChatGPT (Codex). One floor per project.", "Open a floor: click one, or scroll in"),
        ("People are your chats", "The room someone is in is what that chat does now: research, development, testing, or waiting at the front desk for you.", "Click someone to see their last step"),
        ("Needs you", "Chats that stopped to ask you something, and the factories' questions, line up on the left. N takes you to the next one.", "Press N"),
        ("Everything explains itself", "Hover anything that moves to see why it moves. Help keeps every key and a field guide of what you have seen.", "Open Help: press ?"),
    ]
    static let guideKey = CastKey(role: .lead, seed: "walk-guide-sol")

    var body: some View {
        let step = model.walkStep ?? 0
        Group {
            if step == 0 { offer }
            else if step <= Self.steps.count { stepCard(step) }
            else { finish }
        }
        // each step's goal ticks off by itself when you do what it says
        .onChange(of: model.selection.level) { _, l in
            if model.walkStep == 0, l != .all { model.endWalk() }
            if model.walkStep == 1, l.rawValue >= Level.project.rawValue { model.walkGoalDone = true }
        }
        .onChange(of: model.selection.engineRoom) { _, on in if model.walkStep == 0, on { model.endWalk() } }
        .onChange(of: model.selection.sessionID) { _, s in if model.walkStep == 2, s != nil { model.walkGoalDone = true } }
        .onChange(of: model.nextPressed) { _, _ in if model.walkStep == 3 { model.walkGoalDone = true } }
        .onChange(of: model.commandsOpen) { _, on in if model.walkStep == 4, on { model.walkGoalDone = true } }
    }

    private var guide: some View {
        Portrait(image: model.controller.portrait(WalkCard.guideKey), role: .lead, size: 48)
            .task { await model.controller.ensurePortraits([WalkCard.guideKey]) }
    }

    /// the offer, once: quiet, no yellow (D9)
    private var offer: some View {
        HStack(spacing: 12) {
            guide
            Text("New here? Sol walks you round in a minute.").font(.s15b).foregroundStyle(Color.inkText)
            Spacer(minLength: 8)
            Button { start() } label: { Text("Take the walk") }.buttonStyle(SpelButtonStyle(kind: .secondary))
            Button { model.endWalk() } label: { Text("Not now") }.buttonStyle(SpelButtonStyle(kind: .ghost))
                .help("You can start it later from Help (?)")
        }
        .padding(12).frame(width: Shell.sheet + 40).spelFrame()
    }

    private func stepCard(_ step: Int) -> some View {
        let s = Self.steps[step - 1]
        // step 3 with nothing waiting has nothing to press: it is done as it stands
        let done = model.walkGoalDone || (step == 3 && model.world.needsYou.isEmpty)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                guide
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Eyebrow("Step \(step) of \(Self.steps.count)")
                        Pips(count: Self.steps.count, current: done ? -1 : step - 1, done: done ? step : step - 1)
                    }
                    Text(s.title).font(.s19).foregroundStyle(Color.inkText)
                }
                Spacer(minLength: 0)
            }
            Text(s.text).font(.s13).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
            goalRow(step, s.goal, done: done)
            HStack(spacing: 10) {
                if done {
                    let next = step < Self.steps.count ? "Next: " + Self.steps[step].title.lowercased() : "Finish the walk"
                    Button { model.walkGoalDone = false; model.walkStep = step + 1 } label: { SpelLabel(next, key: "↩", onYellow: true) }
                        .buttonStyle(SpelButtonStyle(kind: .primary)).keyboardShortcut(.return, modifiers: [])
                } else {
                    Text("The walk goes on as soon as you do it.").font(.s13).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                Button { model.endWalk() } label: { Text("Skip the walk") }.buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
            }
        }
        .padding(16).frame(width: Shell.sheet).spelFrame()
        .accessibilityElement(children: .contain)
    }

    private func goalRow(_ step: Int, _ goal: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            if done {
                RoundedRectangle(cornerRadius: 4).fill(Color.done).overlay(PixelIcon("check", color: Color(hex: 0x0B2A1A), size: 9)).frame(width: 18, height: 18)
            } else {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.muted, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 18, height: 18)
            }
            Text(step == 3 && model.world.needsYou.isEmpty ? "Nothing waits for you now: when a chat asks, it shows there" : goal)
                .font(.s13m).foregroundStyle(Color.inkText)
            Spacer(minLength: 0)
            Text(done ? "Done" : "Your move").font(.s13m).foregroundStyle(done ? Color.done : Color.muted)
        }
        .spelWell(pad: 10)
    }

    /// the end: two things you can add; Start a factory asks which project first (D1)
    private var finish: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                guide
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("The walk is done")
                    Text("That is your campus").font(.s19).foregroundStyle(Color.inkText)
                }
                Spacer(minLength: 0)
                CloseButton(action: { model.endWalk() }, help: "Done")
            }
            Text("Two things you can add when you like:").font(.s13).foregroundStyle(Color.muted)
            HStack(spacing: 10) {
                quest("floor", "Start a factory", "An AI CEO works on one project on a schedule, and asks you here.") {
                    model.endWalk(); model.factoryPickerOpen = true
                }
                quest("server", "Connect a server", "The Server room watches it over SSH, with your own keys.") {
                    model.endWalk(); model.settingsAtForm = true; model.settingsOpen = true
                }
            }
        }
        .padding(16).frame(width: Shell.sheet).spelFrame()
    }

    private func start() {
        model.walkStep = 1; model.walkGoalDone = false
        if let b = model.world.buildings.first(where: { !$0.projects.isEmpty }) { model.controller.focusBuilding(b.provider.rawValue) }
    }

    private func quest(_ icon: String, _ title: String, _ text: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack(alignment: .top, spacing: 10) {
                PixelIcon(icon, color: .inkText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.s15).foregroundStyle(Color.inkText)
                    Text(text).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                PixelIcon("chev", color: .muted, size: 9).padding(.top, 4)
            }
            .spelCard()
            .contentShape(Rectangle())
        }.buttonStyle(CardPressStyle())
    }
}

/// The walk's last quest (D1): which project gets a CEO? Then you land on that floor, where the Factory switch is
/// step 2 of 2. No Settings, no team steppers: the team comes once the factory runs.
struct FactoryPicker: View {
    @EnvironmentObject private var model: AppModel
    @State private var picked: String?
    private struct Floor: Identifiable { let project: Project; let provider: Provider; let number: Int; var id: String { project.id } }
    private var floors: [Floor] {
        model.world.buildings.flatMap { b in b.projects.enumerated().map { Floor(project: $0.element, provider: b.provider, number: $0.offset + 1) } }
            .filter { !$0.project.isChat }
    }
    var body: some View {
        let floors = self.floors
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Portrait(image: model.controller.portrait(WalkCard.guideKey), role: .lead, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) { Eyebrow("Quest · step 1 of 2"); Pips(count: 2, current: 0) }
                    Text("Start a factory").font(.s19).foregroundStyle(Color.inkText)
                }
                Spacer(minLength: 0)
                CloseButton(action: { model.factoryPickerOpen = false })
            }
            Text("Which project should get a CEO? It works on that floor; you answer its questions.").font(.s13).foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            ScrollFit {
                VStack(spacing: 8) { ForEach(floors) { f in row(f) } }.padding(.bottom, 4)
            }
            HStack(spacing: 10) {
                let name = floors.first { $0.id == picked }?.project.name
                Button { go() } label: { SpelLabel(name.map { "Go to \($0)" } ?? "Pick a project", key: "↩", onYellow: name != nil) }
                    .buttonStyle(SpelButtonStyle(kind: .primary)).disabled(picked == nil).keyboardShortcut(.return, modifiers: [])
                Button { model.factoryPickerOpen = false } label: { Text("Later") }.buttonStyle(SpelButtonStyle(kind: .secondary))
                Spacer(minLength: 0)
            }
        }
        .padding(16).frame(width: Shell.sheet).spelFrame()
        .onExitCommand { model.factoryPickerOpen = false }
        .onAppear { picked = floors.first { !model.isFactory($0.project) }?.id }
    }

    private func row(_ f: Floor) -> some View {
        let p = f.project, factory = model.isFactory(p), chats = p.sessions.count
        return Button { picked = p.id } label: {
            HStack(spacing: 12) {
                Socket(size: 36) {
                    if p.logo != nil { ProjectLogoView(path: p.logo, size: 22) } else { PixelIcon("floor", color: .muted) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.s15).foregroundStyle(factory ? Color.muted : Color.inkText)
                    Text("\(f.provider.displayName) · floor \(f.number) · \(chats == 0 ? "quiet" : "\(chats) chat\(chats == 1 ? "" : "s") today")")
                        .font(.s13).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                if factory { Tag(factory ? "Factory already" : "", tone: .done) }
                else if picked == p.id { PixelIcon("check", color: .selection) }
            }
            .spelCard(selected: picked == p.id, pad: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle()).disabled(factory)
        .accessibilityAddTraits(picked == p.id ? .isSelected : [])
    }

    private func go() {
        guard let id = picked, let p = model.world.project(id: id) else { return }
        model.factoryPickerOpen = false
        model.factoryQuest = p.root
        model.factoryTabs[p.id] = .overview
        model.controller.enterFloor(id)
    }
}
