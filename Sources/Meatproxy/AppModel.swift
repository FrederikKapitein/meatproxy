import SwiftUI
import FactoryCore
import FactoryCollector
import FactoryScenes

/// Polls the collector every 3 seconds on a background queue and feeds the world; checks the servers set up in the
/// settings once a minute over SSH (the Server room). With --fixture it shows fictional data instead, for demos and
/// screenshots that may be shared: made-up servers too, and nothing is read from or written to the real settings.
@MainActor
final class AppModel: ObservableObject {
    @Published var world: World = .empty
    @Published var selection = WorldSelection()
    @Published var status: String? = "Building the campus…"
    @Published var lastRead: Date?
    /// The settings page, inside the window over the world.
    @Published var settingsOpen = false
    /// D72: ⌘K search, the ? sheet of commands, and the open right-click menu
    @Published var paletteOpen = false
    /// window shots: what the search starts with
    var paletteSeed = ""
    @Published var commandsOpen = false
    @Published var contextMenuState: ContextMenuState?
    /// a panel of the HUD is open over the world: plain keys (N, Esc) belong to it, not to the world
    var overlayOpen: Bool { paletteOpen || commandsOpen || factoryPickerOpen || contextMenuState != nil }
    /// the walk's last quest (D1): which project gets a CEO
    @Published var factoryPickerOpen = false
    /// the floor that quest landed on: its Factory switch is step 2 of 2 until you switch it on
    @Published var factoryQuest: String?
    /// Help's tab: every key, or the field guide (D7)
    @Published var helpTab: HelpTab = .keys
    /// window shots: a tab to open on the next floor entered
    var pendingTab: FactoryOverview.Tab?
    /// the group open on a factory's CEO tab (D2): "rhythm", "wakes", "autonomy", "limits", "models", "contract"
    @Published var ceoGroup: String?
    /// the walk's open step: its goal is done, and one button takes you on (D8)
    @Published var walkGoalDone = false
    /// a key pressed the visible button's way: N on Next, Esc on Up
    @Published var nextPulse = 0
    @Published var upPulse = 0
    /// 1 or 2 pressed on an open question (C4, C9): its card shows the confirm step for that answer
    struct AnswerKey: Equatable { var count = 0; var yes = true }
    @Published var answerKey = AnswerKey()
    /// the open question the inspector shows: a factory's decision, or the question about the open server (C9)
    var openQuestion: (project: Project, decision: FactoryDecision)? {
        let s = selection
        if let d = s.decisionID, let pid = s.projectID, let q = world.decision(project: pid, d), q.decision.status == .open { return q }
        if s.decisionID == nil, s.engineRoom, let id = s.serverID, let sv = world.servers.first(where: { $0.id == id }),
           let ops = world.ops, let d = Self.question(about: sv.name, in: ops) { return (ops, d) }
        return nil
    }
    var answerable: Bool { openQuestion != nil }
    /// tokens "saved" in a demo: nothing reaches the Keychain
    @Published var demoTokens: Set<Secrets.Key> = []
    /// The world's free area between the HUD's panels, in window points from the top left: right of the quest log,
    /// left of the inspector (when one is open), below the top bar, above the bottom bar or the terminal drawer. The
    /// HUD keeps it current; the world frames what you open in it (once WorldController takes a safe area).
    @Published var freeArea: CGRect = .zero

    /// A resume command that first prints what the chat asked (C5). The question goes in as an argument of sh, never
    /// into the script, so nothing in it is run.
    static func withQuestion(_ c: TerminalCommand, _ said: String?) -> TerminalCommand {
        guard let q = said?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return c }
        let shown = q.count > 1200 ? "…" + String(q.suffix(1199)) : q
        return TerminalCommand(title: c.title, executable: "/bin/sh",
                               args: ["-c", "printf '\\033[2mIt asked:\\033[0m\\n%s\\n\\n' \"$1\"; shift; exec \"$@\"", "sh", shown, c.executable] + c.args, cwd: c.cwd)
    }
    /// the DevOps agent's open question about a server: the first that names it as a word
    static func question(about server: String, in ops: Project) -> FactoryDecision? {
        let word = try? NSRegularExpression(pattern: "(^|[^A-Za-z0-9_-])" + NSRegularExpression.escapedPattern(for: server) + "($|[^A-Za-z0-9_-])")
        return ops.factory?.openDecisions.first { d in
            let text = d.title + " " + d.why
            return word?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }
    /// the Status layer on the campus (D69), remembered between launches
    @Published var statusLayer = !AppModel.demo && UserDefaults.standard.bool(forKey: "statusLayer")
    /// the status pages you watch (D69)
    @Published var statusSources: [StatusSource] = StatusSourcesStore.load()
    /// Open the settings at the form to add a server (and, for window shots, test this host there at once).
    @Published var settingsAtForm = false
    /// a card in settings to scroll to, by its id ("wakes": a factory's "Also wakes on")
    @Published var settingsScrollTo: String?
    @Published var settingsAtProjects = false
    /// what the pointer is on in the world, for the tooltip
    @Published var hoverTitle: HoverTitle?
    /// a settings page to open (window shots): "general", "engine", "project:<root>", "server:<id>"
    @Published var settingsPage: String?
    /// the tab open in each factory's inspector (kept here: the inspector draws its content twice, scrolling or not)
    @Published var factoryTabs: [String: FactoryOverview.Tab] = [:]
    var debugTestHost: String?
    /// window shots: the starter file whose text the setup card shows
    @Published var debugViewFile: String?
    /// A text field in the HUD has focus (a note for the CEO): the one-key shortcuts (N, Esc) stay out of its way.
    @Published var typing = false
    /// the terminal (D57) and whether its panel is open: the HUD's N and esc stay with the terminal then
    let terminals = TerminalCenter()
    @Published var terminalShown = false
    /// Meme mode (D45): Yes and No read LGTM and Not today. The confirm step stays literal. Kept in the preferences,
    /// except with --fixture, which saves nothing.
    @Published var memeMode: Bool {
        didSet { if !fixture { UserDefaults.standard.set(memeMode, forKey: "memeMode") } }
    }
    /// The fixture's factory lives in a temporary folder, written fresh at every start, so answering a made-up
    /// question writes a made-up file and nothing else.
    private var fixtureFactory: String?
    /// The projects you keep on the campus and which are factories, with their heartbeats (D44, D46, D47).
    @Published private(set) var projectSettings: ProjectSettings
    private let projectStore: ProjectSettingsStore?
    private var projectStamp: Date?
    var factoryRoots: [String] { projectSettings.factoryRoots }
    /// Wakes each factory's CEO (D47). With --fixture its runtime is a stand-in that only waits, so a demo never runs a CEO.
    let heartbeats: HeartbeatCenter
    /// alerts as notifications (D49), from server checks and site checks, without crying wolf
    let alerts = AlertCenter()
    private let alertTracker = AlertTracker()
    /// One server check kept for the detail screen's history.
    struct ServerSample { let at: Date; let metrics: ServerMetrics }
    /// the last two hours of each server's numbers (one check a minute)
    @Published private(set) var serverHistory: [String: [ServerSample]] = [:]
    /// the last look at each public address the servers serve
    @Published private(set) var siteChecks: [String: SiteCheck] = [:]
    private var siteTimer: Timer?
    private var heartbeatTimer: Timer?, ciTimer: Timer?
    /// The servers set up for the Server room, in the order you added them.
    @Published private(set) var serverConfigs: [ServerConfig]
    @Published private(set) var checkingServers = false
    let controller = WorldController()
    let fixture: Bool
    private let collector: Collector?
    private let store: ServerSettingsStore?
    private let monitor: ServerMonitor
    /// how ssh is run: the real one, or for the fixture a made-up healthy server
    let probeRunner: ServerProbe.Runner
    private let queue = DispatchQueue(label: "dev.tuinstra.meatproxy.collector", qos: .utility)
    private var timer: Timer?, serverTimer: Timer?, costTimer: Timer?
    /// the cost ledger reads on its own queue: the first pass reads weeks of session files
    private let costQueue = DispatchQueue(label: "dev.tuinstra.meatproxy.costs", qos: .background)
    private var costing = false
    /// Sentry and Tracker, every 15 minutes (D61)
    private let wakeSources = WakeSources()
    private var sourcesTimer: Timer?, sourcesChecking = false
    private var statusTimer: Timer?, statusChecking = false
    private var reading = false
    /// the settings file as last read or written by the app: a newer one was edited outside it
    private var settingsStamp: Date?

    /// The fixture's ssh: every server a healthy one, without touching the network.
    nonisolated static let demoRunner: ServerProbe.Runner = { _, _ in
        ServerProbe.Output(status: 0, stdout: "cores 4\nload 0.31\ndisk 48%\nmem 8000000000 5100000000\n", stderr: "")
    }

    /// How often the servers are checked.
    static let serverInterval: TimeInterval = 60

    /// --fixture shows made-up data; --first-run is the same without anything set up yet (no factory, servers or
    /// tokens), the campus a newcomer sees, for walkthroughs. Neither saves anything.
    static let demo = CommandLine.arguments.contains("--fixture") || CommandLine.arguments.contains("--first-run")
    static let firstRunDemo = CommandLine.arguments.contains("--first-run")
    let firstRun: Bool

    init(fixture: Bool, firstRun: Bool = false) {
        self.fixture = fixture
        self.firstRun = fixture && firstRun
        if !fixture { AppSupport.migrateLegacyFolder() }
        memeMode = !fixture && UserDefaults.standard.bool(forKey: "memeMode")
        collector = fixture ? nil : Collector()
        store = fixture ? nil : ServerSettingsStore()
        probeRunner = fixture ? Self.demoRunner : ServerProbe.run
        let configs = self.firstRun ? [] : fixture ? Fixture.servers.map { ServerConfig(id: $0.id, name: $0.name, host: "deploy@\($0.name).example.com", kind: $0.kind) } : (store?.load() ?? [])
        serverConfigs = configs
        settingsStamp = store?.modified
        projectStore = fixture ? nil : ProjectSettingsStore()
        projectSettings = self.firstRun ? ProjectSettings() : fixture ? ProjectSettings(projects: [.init(root: Fixture.factoryRoot, pinned: true, factory: true)])
            : (projectStore?.load() ?? ProjectSettings())
        projectStamp = projectStore?.modified
        heartbeats = HeartbeatCenter(runner: fixture ? Self.demoHeartbeat : HeartbeatRunner())
        if fixture && !self.firstRun { fixtureFactory = Self.writeFixtureFactory() }
        monitor = ServerMonitor(configs: configs, run: fixture ? Self.demoRunner : ServerProbe.run)
        controller.onChange = { [weak self] s in self?.selection = s }
        controller.onStatus = { [weak self] s in self?.status = s }
        terminals.onShown = { [weak self] on in self?.terminalShown = on }
        // a notification opens its server (a site's alert opens the server that serves it)
        alerts.onOpen = { [weak self] key in
            guard let self else { return }
            // a factory's notification (a failed run, a source that stopped) opens its floor at the CEO tab
            for prefix in ["ceo:", "source:"] where key.hasPrefix(prefix) {
                let root = String(key.dropFirst(prefix.count)).components(separatedBy: ":").first ?? ""
                if let p = self.world.projects.first(where: { $0.root == root }) {
                    self.settingsOpen = false; self.factoryTabs[p.id] = .ceo; self.controller.enterFloor(p.id)
                }
                return
            }
            let id = self.serverConfigs.first(where: { $0.id == key || $0.siteURLs.contains(key) })?.id
            if let id { self.settingsOpen = false; self.controller.select(server: id) }
        }
        alerts.onRunDevOps = { [weak self] in self?.runDevOpsNow() }
        controller.onHoverTitle = { [weak self] t in if self?.hoverTitle != t { self?.hoverTitle = t } }
        controller.onEffect = { [weak self] kind, title, line in MainActor.assumeIsolated { self?.effectAppeared(kind, title, line) } }
        controller.onContext = { [weak self] t, p in
            MainActor.assumeIsolated { guard let self else { return }; self.contextMenuState = self.contextMenu(for: t, at: p) }
        }
        // a factory's cost cap (D61) reads today's API price of its floors (the CEO may run on either provider)
        // a factory waits while its provider is down on its status page (D69)
        heartbeats.providerDown = { [weak self] runtime in
            MainActor.assumeIsolated { self?.collector?.status.down(runtime.rawValue) }
        }
        // a factory without its starter files does not run (D76); the demo's are in memory
        heartbeats.isSetUp = { [weak self] root in
            if root == EngineRoom.folder.path { return true }
            if fixture { return MainActor.assumeIsolated { root == Fixture.factoryRoot || self?.demoSetUp.contains(root) == true } }
            return FactoryScaffold.isSetUp(root)
        }
        heartbeats.costToday = { [weak self] root in
            MainActor.assumeIsolated { self?.world.projects.filter { $0.root == root }.compactMap { $0.cost?.today }.reduce(0, +) ?? 0 }
        }
        controller.setStatusLayer(statusLayer)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // the heartbeat: every few seconds, see who should wake; every five minutes, look at CI
        if fixture && !firstRun { demoHistory() }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        if !fixture {
            checkSites()
            siteTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkSites() }
            }
            heartbeats.checkCI(projectSettings)
            ciTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; self.heartbeats.checkCI(self.projectSettings); self.checkGitHub() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkGitHub() }
            checkStatusPages()
            statusTimer = Timer.scheduledTimer(withTimeInterval: StatusPages.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkStatusPages() }
            }
        }
        if !fixture {
            sourcesTimer = Timer.scheduledTimer(withTimeInterval: WakeSources.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkSources() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkSources() }
        }
        if !fixture {
            updateCosts()
            costTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateCosts() }
            }
        }
        if !fixture {
            checkServers()
            serverTimer = Timer.scheduledTimer(withTimeInterval: Self.serverInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkServers() }
            }
        }
    }

    func refresh() {
        guard let collector else {
            // the made-up servers, as the settings have them (one added in a demo shows as healthy)
            var w = Fixture.world()
            if firstRun { firstRunWorld(&w); return }
            // the demo shows the DevOps agent at the black hole without reading any real workspace
            w.opsState = .working
            // and one made-up question of the DevOps agent's, answered like any other (nothing is written in the demo)
            w.ops = Project(id: World.opsID, provider: .claude, root: "/demo/engine-room", name: "Server room", isChat: false, sessions: [],
                            factory: FactoryText.factory(root: "/demo/engine-room", files: ["factory/decisions/D-0001-prune-api-01.md": """
                            ---
                            id: D-0001
                            title: Prune Docker images older than a week on api-01?
                            kind: fix
                            status: open
                            asked: \(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600)))
                            ---

                            ## Why
                            api-01's disk is 91% full; old images take 9 GB of it. api-01 allows diagnosing only, so the prune needs your yes.

                            ## Evidence
                            - `--ops api-01 disk` → / 91% (36 of 40 GB)
                            - `--ops api-01 docker` → 14 images, 9 of them unused for more than a week

                            ## On yes
                            `--ops api-01 docker-prune` once, then `--ops api-01 disk` to check.

                            ## On no
                            The alert stays; it asks again when the disk reaches 95%.
                            """]))
            // and a made-up logo on the demo factory (a pebble), so the logo shows in screenshots
            for b in w.buildings.indices { for p in w.buildings[b].projects.indices where w.buildings[b].projects[p].root == Fixture.factoryRoot {
                w.buildings[b].projects[p].logo = Self.demoLogo
            } }
            // made-up costs at API prices (D61), from the floor's name, so every floor shows one
            for b in w.buildings.indices { for p in w.buildings[b].projects.indices {
                let seed = Double(w.buildings[b].projects[p].name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 97)
                w.buildings[b].projects[p].cost = ProjectCost(today: seed / 9, week: seed * 0.8, month: seed * 3.1)
            } }
            // the project settings shape the demo campus as they shape the real one: the Chats floor, pinned projects
            if !projectSettings.showChats { for b in w.buildings.indices { w.buildings[b].projects.removeAll(where: \.isChat) } }
            WorldBuilder.pin(projectSettings.pinnedRoots, to: &w)
            WorldBuilder.hide(projectSettings.hidden, in: &w)
            // the made-up factory is read from its temporary folder; any other demo project you switch on is an empty one
            for b in w.buildings.indices {
                for k in w.buildings[b].projects.indices where !w.buildings[b].projects[k].isChat {
                    let root = w.buildings[b].projects[k].root
                    w.buildings[b].projects[k].factory = !factoryRoots.contains(root) ? nil
                        : root == Fixture.factoryRoot ? fixtureFactory.map { FactoryFinder.read(root: $0) } : Factory(root: root)
                }
            }
            w.servers = serverConfigs.map { c in
                w.servers.first { $0.id == c.id }.map { var s = $0; s.name = c.name; s.kind = c.kind; s.checkedAt = s.checkedAt ?? w.now.addingTimeInterval(-24); return s }
                    ?? Server(id: c.id, name: c.name, kind: c.kind, state: .ok, detail: "load 0.31 · disk 48% · memory 36%", checkedAt: w.now)
            }
            apply(w); return
        }
        reloadSettingsIfEdited()
        reloadProjectsIfEdited()
        guard !reading else { return }
        reading = true
        let settings = projectSettings
        queue.async {
            var w = collector.world(settings: settings)
            DispatchQueue.main.async {
                self.reading = false
                w.servers = self.monitor.servers
                w.ops = self.opsProject()
                w.opsState = self.opsOrbitState(w.ops)
                self.markLiveRuns(&w)
                self.apply(w)
            }
        }
    }

    /// How each factory's Sentry and Tracker did at their last check (root → health).
    @Published var sourceHealth: [String: FactoryHealth] = [:]
    /// Your Tracker's MCP address (https); empty switches Tracker off.
    func setTrackerURL(_ text: String) { changeProjects { $0.trackerURL = text.trimmingCharacters(in: .whitespacesAndNewlines) } }

    /// Asks each factory's Sentry and Tracker project what is new (D61), off the main queue, and wakes its CEO.
    private func checkSources() {
        guard !sourcesChecking else { return }
        let factories: [(root: String, sources: FactorySources, heartbeat: Heartbeat, bugsAllowed: Bool)] = projectSettings.projects.filter(\.factory).compactMap { e in
            guard let f = world.projects.first(where: { $0.root == e.root })?.factory, f.takesSources,
                  f.sources.hasSentry || f.sources.tracker != nil else { return nil }
            return (e.root, f.sources, e.heartbeat, (f.mandate?.mode(.bugs) ?? .ask) != .off)
        }
        guard !factories.isEmpty, !projectSettings.pauseAll else { return }
        let trackerURL = WakeSources.trackerURL(projectSettings.trackerURL)
        sourcesChecking = true
        let sources = wakeSources
        DispatchQueue.global(qos: .utility).async {
            let wakes = sources.check(factories, tokens: (Secrets.get(.sentry), Secrets.get(.tracker)), trackerURL: trackerURL)
            let health = sources.health
            DispatchQueue.main.async {
                self.sourcesChecking = false
                self.sourceHealth = health
                // a source that just stopped working: say so once, naming the factory
                for (root, h) in health {
                    let name = self.world.projects.first { $0.root == root }?.name ?? (root as NSString).lastPathComponent
                    for (label, s) in [("Sentry", h.sentry), ("Tracker", h.tracker)] where s?.isNewFailure == true {
                        self.alerts.post(title: "\(name): \(label) stopped working", body: (s?.line ?? "") + ". The CEO is not woken by \(label) until it works again.",
                                         key: "source:\(root):\(label)", kind: .warn)
                    }
                }
                for (root, reason) in wakes { self.heartbeats.wake(root, reason) }
            }
        }
    }

    /// Reads what the session files added since the last pass and prices it (D61); the next refresh shows it.
    private func updateCosts() {
        guard let collector, !costing else { return }
        costing = true
        costQueue.async {
            collector.costs.update()
            DispatchQueue.main.async { self.costing = false }
        }
    }

    /// Tries a saved token (the Test button): one read of what the factories name. Off the main queue.
    func testToken(_ key: Secrets.Key) async -> (ok: Bool, line: String) {
        if fixture { return (true, "Demo data: nothing is sent") }
        let sources = world.projects.compactMap { $0.factory }.filter(\.takesSources).map(\.sources)
        let ws = wakeSources, trackerURL = WakeSources.trackerURL(projectSettings.trackerURL)
        return await Task.detached(priority: .userInitiated) {
            guard let token = Secrets.get(key) else { return (false, "No token saved") }
            switch key {
            case .sentry: return ws.testSentry(token: token, projects: sources)
            case .tracker: return ws.testTracker(token: token, slugs: sources.compactMap(\.tracker), url: trackerURL)
            }
        }.value
    }

    /// The status pages (D69), every five minutes, off the main queue.
    func checkStatusPages() {
        guard let collector, !statusChecking else { return }
        statusChecking = true
        let list = statusSources
        costQueue.async {
            collector.status.update(list)
            DispatchQueue.main.async { self.statusChecking = false; self.refresh() }
        }
    }
    func setStatusLayer(_ on: Bool) {
        statusLayer = on
        if !fixture { UserDefaults.standard.set(on, forKey: "statusLayer") }
        controller.setStatusLayer(on)
    }
    func updateStatusSources(_ change: (inout [StatusSource]) -> Void) {
        change(&statusSources)
        if !fixture { StatusSourcesStore.save(statusSources); checkStatusPages() }
    }

    /// CI and merged pull requests per project (D67), every five minutes, off the main queue.
    private var githubChecking = false
    private func checkGitHub() {
        guard let collector, !githubChecking else { return }
        let roots = world.projects.filter { !$0.isChat }.map(\.root)
        guard !roots.isEmpty else { return }
        githubChecking = true
        costQueue.async {
            collector.github.update(roots: roots)
            DispatchQueue.main.async { self.githubChecking = false }
        }
    }

    private func apply(_ w: World) {
        world = withTeams(w).withUniqueNames()
        lastRead = w.now
        controller.show(world)
        Task { await controller.ensurePortraits(w.projects.flatMap { p in p.sessions.map { p.cast(of: $0) } }); objectWillChange.send() }
    }

    // MARK: servers

    /// The settings file was changed outside the app (by hand, or by another copy of it): take it over and check.
    private func reloadSettingsIfEdited() {
        guard let store, let m = store.modified, m != settingsStamp else { return }
        settingsStamp = m
        let configs = store.load()
        guard configs != serverConfigs else { return }
        serverConfigs = configs
        monitor.update(configs)
        world.servers.removeAll { s in !configs.contains { $0.id == s.id } }
        checkServers()
    }

    /// Checks every server now (the fixture's are made up and never checked).
    func checkServers() {
        guard !fixture, !serverConfigs.isEmpty, !checkingServers else { return }
        checkingServers = true
        monitor.checkAll { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.checkingServers = false
                self.world.servers = self.monitor.servers
                self.apply(self.world)
                self.noteServerAlerts()
                self.recordHistory()
            }
        }
    }

    /// Server checks to alerts: twice bad before it alerts, and back up after (servers with alerts off say nothing).
    private func noteServerAlerts() {
        for s in world.servers {
            guard let c = serverConfigs.first(where: { $0.id == s.id }), c.alertsOn else { continue }
            if let e = alertTracker.observe(s.id, name: s.name, state: s.state, detail: s.detail) { raise(e) }
        }
    }

    private func recordHistory(now: Date = Date()) {
        for s in world.servers {
            guard let m = s.metrics else { continue }
            var h = serverHistory[s.id] ?? []
            h.append(ServerSample(at: s.checkedAt ?? now, metrics: m))
            serverHistory[s.id] = Array(h.filter { now.timeIntervalSince($0.at) < 2 * 3600 }.suffix(150))
        }
    }

    /// The demo's history: two made-up hours round each server's numbers (nothing real, safe to show).
    /// The first-run demo: the made-up sessions as a newcomer's own, with nothing switched on yet.
    private func firstRunWorld(_ w: inout World) {
        for b in w.buildings.indices { for p in w.buildings[b].projects.indices {
            w.buildings[b].projects[p].factory = factoryRoots.contains(w.buildings[b].projects[p].root) ? Factory(root: w.buildings[b].projects[p].root) : nil
            let seed = Double(w.buildings[b].projects[p].name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 97)
            w.buildings[b].projects[p].cost = ProjectCost(today: seed / 9, week: seed * 0.8, month: seed * 3.1)
        } }
        if !projectSettings.showChats { for b in w.buildings.indices { w.buildings[b].projects.removeAll(where: \.isChat) } }
        WorldBuilder.pin(projectSettings.pinnedRoots, to: &w)
        WorldBuilder.hide(projectSettings.hidden, in: &w)
        w.servers = serverConfigs.map { Server(id: $0.id, name: $0.name, kind: $0.kind, state: .ok, detail: "load 0.31 · disk 48% · memory 36%", checkedAt: w.now) }
        apply(w)
    }

    private func demoHistory(now: Date = Date()) {
        for (k, s) in Fixture.servers.enumerated() {
            guard let m = s.metrics else { continue }
            serverHistory[s.id] = (0..<60).map { i in
                let t = Double(i), w = sin(t / 7 + Double(k)) * 0.5 + sin(t / 2.3) * 0.2
                let disk = m.disk.map { max(1, min(99, $0 - (59 - i) / 12)) }
                let mem = m.memory.map { max(1, min(99, $0 + Int(w * 8))) }
                let load = m.load.map { max(0.01, $0 * (1 + w * 0.6)) }
                return ServerSample(at: now.addingTimeInterval(-Double(59 - i) * 120), metrics: ServerMetrics(load: load, cores: m.cores, disk: disk, memory: mem))
            }
        }
    }

    /// ssh to a server in the app's terminal (your own keys and config; the host is checked to be a plain name).
    func openSSH(_ c: ServerConfig) {
        guard let cmd = TerminalCommand.ssh(c.host, name: c.name) else { status = "That host is not a plain name; open it yourself."; return }
        terminals.open(cmd, icon: "server.rack")
    }

    /// Takes over a session in the app's terminal (D57): `claude --resume` (or `codex resume`) where it started. A CEO's
    /// heartbeat run that is still going stops first (it is yours now), and that factory's heartbeat waits until you
    /// close the tab.
    func takeOver(_ s: Session) {
        guard let resume = TerminalCommand.resume(s) else { status = "This session cannot be resumed here (no \(s.provider == .claude ? "claude" : "codex") CLI found)."; return }
        // a chat that waits shows what it asked above the conversation (C5): answering happens there, not in the app
        let cmd = s.state(now: world.now) == .waiting ? Self.withQuestion(resume, s.lastSaid) : resume
        let root = world.projects.first { $0.sessions.contains { $0.id == s.id } }?.root
        let ceo = s.heartbeatRun == true && root != nil
        if ceo, let root { heartbeats.takeOver(root) }
        let open = { [weak self] in
            self?.terminals.open(cmd, icon: "person.fill.checkmark") { [weak self] in
                if ceo, let root { self?.heartbeats.handBack(root) }
                self?.refresh()
            }
            self?.refresh()
        }
        // a run that was going needs a moment to stop before its conversation is resumed
        if ceo { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: open) } else { open() }
    }

    /// Follows a factory's (or the DevOps agent's) last run log in the terminal, as it grows.
    func watchRun(root: String, name: String) {
        guard let last = heartbeats.runner.lastRun(root),
              let cmd = TerminalCommand.follow(heartbeats.runner.logURL(root, started: last.started).path, title: "\(name) run log") else {
            status = "No run log to follow yet."; return
        }
        terminals.open(cmd, icon: "doc.text.magnifyingglass")
    }

    /// Looks at every public address of every server: does it answer, and its certificate.
    func checkSites() {
        let urls = serverConfigs.filter(\.alertsOn).flatMap(\.siteURLs)
        alertTracker.forget(except: Set(serverConfigs.map(\.id) + urls))
        guard !fixture, !urls.isEmpty else { return }
        Task {
            for u in urls {
                let r = await SiteProbe.check(u)
                siteChecks[u] = r
                let host = URL(string: u)?.host ?? u
                if let e = alertTracker.observe(u, name: host, state: r.state, detail: r.detail) { raise(e) }
            }
        }
    }

    /// An alert: a notification (when on), and the DevOps agent wakes for it (D49).
    private func raise(_ e: AlertEvent) {
        if projectSettings.devops.notify { alerts.post(e) }
        devopsAlert(e)
    }

    /// An alert for the DevOps agent: filed in its workspace, and it wakes at once (when it is on and wakes on alerts).
    func devopsAlert(_ e: AlertEvent) {
        guard !fixture, projectSettings.devops.enabled else { return }
        prepareEngineRoom()
        guard let id = try? EngineRoom.file(e) else { return }
        if projectSettings.devops.wakeOnAlert, e.kind != .recovered { heartbeats.wake(EngineRoom.folder.path, .alert([id])); beat() }
    }

    /// Writes what the DevOps agent reads: the servers and their last checks, and its allowlist.
    func prepareEngineRoom() {
        guard !fixture, projectSettings.devops.enabled else { return }
        do { try EngineRoom.prepare(servers: serverConfigs, checks: world.servers, sites: siteChecks, opsTool: HeartbeatRunner.opsToolPath) }
        catch { status = "Could not prepare the Server room: \(error.localizedDescription)" }
    }

    /// A factory whose CEO run is going (here or in the launch agent): its CEO works on the floor, whatever the session
    /// file looks like between turns.
    private func markLiveRuns(_ w: inout World) {
        for b in w.buildings.indices {
            for p in w.buildings[b].projects.indices {
                let pr = w.buildings[b].projects[p]
                guard pr.factory != nil, heartbeats.runner.lastRun(pr.root)?.outcome == .running,
                      let k = pr.sessions.firstIndex(where: { $0.heartbeatRun == true }) else { continue }
                w.buildings[b].projects[p].sessions[k].liveRun = true
            }
        }
    }

    /// The DevOps agent as the world holds it: its questions in Needs you, its journal in the Server room.
    func opsProject() -> Project? {
        guard projectSettings.devops.enabled, !fixture else { return nil }
        return Project(id: World.opsID, provider: .claude, root: EngineRoom.folder.path, name: EngineRoom.displayName, isChat: false,
                       sessions: [], factory: EngineRoom.read())
    }

    private func opsOrbitState(_ ops: Project?) -> SessionState? {
        guard projectSettings.devops.enabled else { return nil }
        if !(ops?.factory?.openDecisions.isEmpty ?? true) { return .waiting }
        return devopsState?.running == true ? .working : .done
    }

    /// The DevOps agent's heartbeat, for the Server room's card.
    var devopsState: HeartbeatState? {
        guard projectSettings.devops.enabled else { return nil }
        return heartbeats.state(EngineRoom.folder.path, heartbeat: projectSettings.devops.heartbeat, pauseAll: projectSettings.pauseAll)
    }

    func runDevOpsNow() {
        prepareEngineRoom()
        heartbeats.wake(EngineRoom.folder.path, .runNow)
        beat()
    }

    private var engineRoomPrepared: Date?
    /// The workspace is refreshed at most every minute from the heartbeat (and always right before an alert or Run now).
    private func prepareEngineRoomIfStale() {
        if let at = engineRoomPrepared, Date().timeIntervalSince(at) < 60 { return }
        engineRoomPrepared = Date()
        prepareEngineRoom()
    }

    /// Changes one server's settings (alerts, sites, what the DevOps agent may do there).
    func updateServer(_ id: String, _ change: (inout ServerConfig) -> Void) {
        guard let k = serverConfigs.firstIndex(where: { $0.id == id }) else { return }
        change(&serverConfigs[k])
        persist()
        checkSites()
    }

    func updateDevOps(_ change: @escaping (inout DevOpsSettings) -> Void) { changeProjects { change(&$0.devops) } }

    /// The last check of a server as the settings show it.
    func server(_ id: String) -> Server? { world.servers.first { $0.id == id } }

    /// Adds a server, or replaces the one with the same id; saved at once, then checked.
    /// The Host aliases in ~/.ssh/config (the demo has made-up ones: nothing real shows in a screenshot).
    var sshAliases: [String] { fixture ? ["web-02", "db-02", "staging"] : SSHHosts.fromUserConfig() }
    /// Adds each alias as a server named after it, then checks them all.
    func importServers(_ aliases: [String]) {
        for a in aliases where !serverConfigs.contains(where: { $0.host == a }) {
            save(ServerConfig(id: UUID().uuidString, name: a, host: a, kind: .server))
        }
        if !fixture { checkServers() }
    }

    func save(_ config: ServerConfig) {
        if let k = serverConfigs.firstIndex(where: { $0.id == config.id }) { serverConfigs[k] = config } else { serverConfigs.append(config) }
        persist()
    }

    func remove(_ id: String) {
        serverConfigs.removeAll { $0.id == id }
        world.servers.removeAll { $0.id == id }
        persist()
        controller.show(world)
    }

    private func persist() {
        monitor.update(serverConfigs)
        if fixture { return }
        do { try store?.save(serverConfigs); settingsStamp = store?.modified } catch { status = "Could not save the settings: \(error.localizedDescription)" }
        checkServers()
    }

    /// One check of a server that is not saved yet (the settings' Test button), off the main thread.
    func test(_ config: ServerConfig) async -> ServerProbe.Result {
        let run = probeRunner
        return await Task.detached(priority: .userInitiated) { ServerProbe.check(config, run: run) }.value
    }

    // MARK: factories

    func isFactory(_ project: Project) -> Bool { projectSettings.entry(project.root)?.factory ?? false }
    func isPinned(_ project: Project) -> Bool { projectSettings.entry(project.root).map { $0.pinned || $0.factory } ?? false }

    /// Switches a project on or off as a Dark Software Factory. Nothing in the project changes: the factory's files are
    /// its CEO's; the app only reads them (and writes your answers). A factory stays on the campus.
    func setFactory(_ root: String, on: Bool) {
        changeProjects { $0.update(root) { e in e.factory = on; if on { e.pinned = true } } }
        if on, factoryQuest == root { factoryQuest = nil }
    }
    /// Keeps a project on the campus without a recent session (D46).
    func setPinned(_ root: String, on: Bool) { changeProjects { $0.update(root) { $0.pinned = on } } }
    func setShowChats(_ on: Bool) { changeProjects { $0.showChats = on } }
    /// Hides a floor from the campus, or shows it again; a hidden project is not kept on the campus either.
    func setHidden(_ root: String, on: Bool) {
        changeProjects { s in
            s.hidden.removeAll { $0 == root }
            if on { s.update(root) { $0.pinned = false }; s.hidden.append(root) }
        }
    }
    /// Allows a factory's CEO to run Dark, or caps it at Hybrid (D68).
    func setDarkAllowed(_ root: String, on: Bool) {
        changeProjects { s in s.darkOff.removeAll { $0 == root }; if !on { s.darkOff.append(root) } }
        if !on { capMandate(root) }
    }
    /// A mandate that is Dark where Dark is off steps down to Hybrid.
    private func capMandate(_ root: String) {
        if mandate(root).level == .dark { setMandate(root) { $0.set(level: .hybrid) } }
    }
    func updateHeartbeat(_ root: String, _ change: @escaping (inout Heartbeat) -> Void) { changeProjects { $0.update(root) { change(&$0.heartbeat) } } }

    /// The heartbeat beats while the app is closed, through a launch agent (D47), or only while it runs.
    func setHeartbeatWhenClosed(_ on: Bool) {
        if fixture { projectSettings.heartbeatWhenClosed = on; return }
        do {
            if on { try LaunchAgent.install() } else { try LaunchAgent.remove() }
            changeProjects { $0.heartbeatWhenClosed = on }
        } catch { status = "Could not \(on ? "set up" : "remove") the launch agent: \(error.localizedDescription)" }
    }

    private func changeProjects(_ change: (inout ProjectSettings) -> Void) {
        change(&projectSettings)
        if let projectStore {
            do { try projectStore.save(projectSettings); projectStamp = projectStore.modified }
            catch { status = "Could not save the projects: \(error.localizedDescription)" }
        }
        refresh()
    }

    /// The projects file was changed outside the app: take it over.
    private func reloadProjectsIfEdited() {
        guard let projectStore, let m = projectStore.modified, m != projectStamp else { return }
        projectStamp = m
        let s = projectStore.load()
        if s != projectSettings { projectSettings = s }
    }

    /// Every project in the settings list: the ones on the campus now, then the pinned ones without a floor.
    var projectCandidates: [(root: String, name: String, pinned: Bool, factory: Bool)] {
        var seen = Set<String>(), out: [(String, String, Bool, Bool)] = []
        func add(_ root: String, _ name: String) {
            let e = projectSettings.entry(root)
            out.append((root, name, e.map { $0.pinned || $0.factory } ?? false, e?.factory ?? false))
        }
        for p in world.projects where !p.isChat && seen.insert(p.root).inserted { add(p.root, p.name) }
        for e in projectSettings.projects where seen.insert(e.root).inserted { add(e.root, WorldBuilder.pretty((e.root as NSString).lastPathComponent)) }
        return out.sorted { ($0.3 ? 0 : $0.2 ? 1 : 2, $0.1.lowercased()) < ($1.3 ? 0 : $1.2 ? 1 : 2, $1.1.lowercased()) }
    }

    // MARK: heartbeat

    /// What the HUD shows about a factory's heartbeat.
    func heartbeat(_ project: Project) -> HeartbeatState? {
        guard let e = projectSettings.entry(project.root), e.factory else { return nil }
        return heartbeats.state(project.root, heartbeat: e.heartbeat, pauseAll: projectSettings.pauseAll)
    }

    /// in the demo, mandates stay in memory (nothing is written)
    private var demoMandates: [String: FactoryMandate] = [:]

    /// A factory's mandate as it is now (its file, or the default when it has none yet).
    func mandate(_ root: String) -> FactoryMandate {
        if fixture, let m = demoMandates[root] { return m }
        return world.projects.first { $0.root == root }?.factory?.mandate ?? FactoryMandate()
    }

    /// Changes a factory's mandate and writes it (contract v3, D56); the CEO follows it from its next run. A floor that
    /// follows the campus team gets the campus default's numbers written out.
    func setMandate(_ root: String, _ change: (inout FactoryMandate) -> Void) {
        var m = mandate(root)
        change(&m)
        if !m.ownTeam { m.team = projectSettings.defaultTeam }
        if fixture { demoMandates[root] = m; objectWillChange.send(); return }
        do { try MandateFile.write(m, root: root); refresh() }
        catch { status = "Could not write the mandate: \(error.localizedDescription)" }
    }

    // MARK: the team (D79)

    /// The team a floor works with: its own, or the campus default.
    func team(_ root: String) -> (team: AgentTeam, own: Bool) {
        let m = mandate(root)
        return m.ownTeam ? (m.team, true) : (projectSettings.defaultTeam, false)
    }

    /// Gives a floor its own team (starting from the one it has) and changes it.
    func setTeam(_ root: String, _ change: (inout AgentTeam) -> Void) {
        let start = team(root).team
        setMandate(root) { m in m.ownTeam = true; m.team = start; change(&m.team) }
        showTeams()
    }

    /// Back to the campus default, or its own team starting from the default's numbers.
    func followCampusTeam(_ root: String, _ follow: Bool) {
        let start = team(root).team
        setMandate(root) { m in m.ownTeam = !follow; m.team = start }
        showTeams()
    }

    /// Changes the campus default and writes it into every factory floor that follows it.
    func setDefaultTeam(_ change: (inout AgentTeam) -> Void) {
        changeProjects { change(&$0.defaultTeam) }
        for root in projectSettings.factoryRoots where isSetUp(root) && !mandate(root).ownTeam { setMandate(root) { _ in } }
        showTeams()
    }

    /// Every factory floor knows its team and the look of each profile, so all of them are on the floor (D79).
    private func withTeams(_ w: World) -> World {
        var w = w
        let roles = Dictionary(projectSettings.customProfiles.map { ($0.name, $0.look) }, uniquingKeysWith: { a, _ in a })
        for b in w.buildings.indices {
            for k in w.buildings[b].projects.indices where w.buildings[b].projects[k].factory != nil {
                let root = w.buildings[b].projects[k].root
                guard isSetUp(root) else { continue }
                w.buildings[b].projects[k].team = team(root).team
                w.buildings[b].projects[k].teamRoles = roles
            }
        }
        return w
    }
    /// the floor follows a team change at once
    private func showTeams() { world = withTeams(world); controller.show(world) }

    /// Adds a profile of your own; it is offered on every floor.
    func addProfile(_ p: CustomProfile) {
        changeProjects { $0.customProfiles.append(p) }
        showTeams()
    }
    /// Removes a profile of your own: from the list and from every team (its agent files stay where they are).
    func removeProfile(_ name: String) {
        changeProjects { $0.customProfiles.removeAll { $0.name == name }; $0.defaultTeam.set(name, 0) }
        for root in projectSettings.factoryRoots where isSetUp(root) && mandate(root).ownTeam && mandate(root).team.count(name) > 0 {
            setMandate(root) { $0.team.set(name, 0) }
        }
        showTeams()
    }

    /// The profiles a roster shows: Meatproxy's, the ones you made, then other agent files in the project.
    func profiles(_ root: String?) -> [AgentProfile] {
        let mine = AgentProfile.standard + projectSettings.customProfiles.map(\.profile)
        guard let root, !fixture else { return mine }
        let own = TeamFiles.existing(root: root).filter { e in !mine.contains { $0.name == e.key } }
        return mine + own.keys.sorted().map { AgentProfile.own($0, model: own[$0] ?? nil) }
    }
    func isCustom(_ name: String) -> Bool { projectSettings.customProfiles.contains { $0.name == name } }

    /// The model a profile runs on in this project: its agent file's, or the one Meatproxy writes.
    func model(_ p: AgentProfile, root: String?) -> String {
        guard let root, !fixture, let m = TeamFiles.existing(root: root)[p.name] else { return p.model }
        return m ?? "inherit"
    }

    /// The agent files a floor's team still needs (none on a Codex floor: Codex has no agent files).
    func teamFiles(_ project: Project) -> [StarterFile] {
        guard project.provider == .claude else { return [] }
        var plan = TeamFiles.plan(root: project.root, project: project.name, team: team(project.root).team, profiles: profiles(project.root))
        if fixture { for k in plan.indices { plan[k].exists = demoTeamFiles.contains(project.root + plan[k].path) } }
        return plan
    }
    private var demoTeamFiles: Set<String> = []

    /// Writes the missing agent files you approved; never replaces one. The demo only pretends.
    func createTeamFiles(_ project: Project, files: [StarterFile]) {
        if fixture { for f in files { demoTeamFiles.insert(project.root + f.path) }; objectWillChange.send(); return }
        do {
            let written = try FactoryScaffold.create(files, root: project.root)
            status = "Wrote \(written.count) agent file\(written.count == 1 ? "" : "s") in \(project.name)"
            objectWillChange.send()
        } catch { status = "Could not write the agent files: \(error.localizedDescription)" }
    }

    /// Sends the factory's CEO an idea (factory/ideas/), and wakes it a few minutes later like an answer does.
    func sendIdea(_ project: Project, text: String) async -> String? {
        let root = project.root
        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            Result { try IdeaInbox.send(root: root, text: text) }
        }.value
        switch result {
        case .success(let id):
            heartbeats.wake(root, .idea([id]))
            refresh()
            return nil
        case .failure(let e): return e.localizedDescription
        }
    }

    /// The last run's log, if it is there.
    func heartbeatLog(_ project: Project) -> URL? {
        guard let last = heartbeats.runner.lastRun(project.root) else { return nil }
        let u = heartbeats.runner.logURL(project.root, started: last.started)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// The kill switch (D48): nothing starts, and running CEOs are stopped.
    func setPauseAll(_ on: Bool) {
        changeProjects { $0.pauseAll = on }
        if on { heartbeats.runner.stopAll() }
    }

    /// Lifts a hold (the CI breaker) and wakes the CEO.
    func resume(_ project: Project) {
        heartbeats.resume(project.root)
        beat()
    }

    /// Wakes a factory's CEO now.
    // MARK: setting a factory up (D76)

    /// the factory you just set up: its panel offers the first beat
    @Published var justSetUp: String?
    /// factories set up in the demo (nothing is written there)
    private var demoSetUp: Set<String> = []
    func isSetUp(_ root: String) -> Bool {
        fixture ? (root == Fixture.factoryRoot || demoSetUp.contains(root)) : FactoryScaffold.isSetUp(root)
    }
    func setupPlan(_ project: Project) -> [StarterFile] {
        var plan = FactoryScaffold.plan(root: project.root, name: project.name)
        if fixture { for k in plan.indices { plan[k].exists = false } }
        return plan
    }
    /// Creates the starter files you ticked that are missing; never overwrites. The demo only pretends.
    func setUp(_ project: Project, files: [StarterFile]) -> Bool {
        if fixture { demoSetUp.insert(project.root); objectWillChange.send(); return true }
        do {
            let written = try FactoryScaffold.create(files, root: project.root)
            status = "Set up \(project.name): wrote \(written.count) file\(written.count == 1 ? "" : "s") in its folder"
            refresh(); return true
        } catch {
            status = "Could not set up \(project.name): \(error.localizedDescription)"
            return false
        }
    }

    /// What a factory's CEO can run without asking. The demo's factory has the standard allowlist.
    func allowlist(_ root: String) -> Allowlist {
        if fixture { return demoAllowlist.contains(root) || root == Fixture.factoryRoot ? Allowlist(json: FactoryScaffold.allowlist(tests: ["swift test", "swift build"])) : Allowlist(json: nil) }
        return Allowlist(root: root)
    }
    private var demoAllowlist: Set<String> = []
    func standardAllowlist(_ root: String) -> String {
        FactoryScaffold.plan(root: root, name: "").first { $0.path == ".claude/settings.json" }?.text ?? ""
    }
    /// Writes the standard allowlist when the project has none; never replaces one.
    func addAllowlist(_ project: Project) {
        if fixture { demoAllowlist.insert(project.root); objectWillChange.send(); return }
        let file = FactoryScaffold.plan(root: project.root, name: project.name).filter { $0.path == ".claude/settings.json" }
        do { let w = try FactoryScaffold.create(file, root: project.root); status = w.isEmpty ? "\(project.name) already has an allowlist" : "Wrote .claude/settings.json in \(project.name)"; objectWillChange.send() }
        catch { status = "Could not write the allowlist: \(error.localizedDescription)" }
    }

    /// A factory's one line on a building's floor list: not set up, its CEO running, held or blocked (amber), the last
    /// run failed (amber), or when it beats next.
    func factoryLine(_ p: Project) -> (text: String, warn: Bool)? {
        guard p.factory != nil else { return nil }
        if !isSetUp(p.root) { return ("Factory · not set up yet", true) }
        guard let hb = heartbeat(p) else { return nil }
        if hb.running { return ("CEO at work", false) }
        if let b = hb.blocked { return (b.text, b.waitsForYou || b == .notSetUp) }
        if let last = hb.last, last.outcome == .failed || last.outcome == .timedOut { return ("Last CEO run failed", true) }
        if let n = hb.next { return ("Next beat " + HeartbeatCard.when(n), false) }
        return ("Heartbeat paused: Run now only", false)
    }

    // MARK: a question in words (D77)

    /// What brought the question up now: your yeses in a row (a promote), your idea, or where its work came from.
    func trigger(for d: FactoryDecision, in p: Project) -> String? {
        let f = p.factory
        if d.kind == "promote", let gates = f?.autonomy?.gates,
           let g = gates.first(where: { $0.name.lowercased() == d.gate?.lowercased() && $0.streak > 0 })
                ?? gates.first(where: { d.title.lowercased().contains($0.name.lowercased()) && $0.streak > 0 })
                ?? gates.max(by: { $0.streak < $1.streak }), g.streak > 0 {
            return "You said yes \(g.streak) times in a row to \(g.name.lowercased()): it asks to stop asking"
        }
        if let w = d.workstream {
            if let idea = f?.ideas.first(where: { $0.workstream == w || $0.decision == d.id }) { return "From your idea: \(idea.title)" }
            if let src = f?.workstreams.first(where: { $0.id == w })?.source, !src.isEmpty { return "Its work came from \(src)" }
        }
        if let idea = f?.ideas.first(where: { $0.decision == d.id }) { return "From your idea: \(idea.title)" }
        return p.id == World.opsID ? "Found by the DevOps agent on its round" : nil
    }

    /// When the CEO picks an answer up: a few minutes after it, or at its next beat.
    func pickUp(_ p: Project) -> String {
        let wakes = p.id == World.opsID ? projectSettings.devops.heartbeat.wakeOnAnswer : projectSettings.entry(p.root)?.heartbeat.wakeOnAnswer ?? false
        if wakes { return "about \(Int(Heartbeat.answerWindow / 60)) minutes after you answer" }
        if let n = heartbeat(p)?.next { return "at its next beat, " + HeartbeatCard.when(n) }
        return "at its next run"
    }

    /// What happens on your answer, from the question's own On yes / On no, and when.
    func consequence(of d: FactoryDecision, yes: Bool, in p: Project) -> String {
        let who = p.id == World.opsID ? "The DevOps agent" : "The CEO"
        if d.isTodo {
            return yes ? "\(who) checks it \(pickUp(p)), and asks again if it is still missing."
                       : "\(who) leaves it until something changes."
        }
        let plan = (yes ? d.onYes : d.onNo).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-*• ").union(.whitespaces)) }
            .first { !$0.isEmpty }
        let what = plan.map { ": " + $0.prefix(1).lowercased() + $0.dropFirst() } ?? (yes ? " goes ahead" : " drops it, or asks again with another way")
        return "\(who) acts on it \(pickUp(p))\(what)"
    }

    /// After you answered: whether the CEO has taken it up yet, and where its work stands.
    func receipt(for d: FactoryDecision, in p: Project) -> String {
        guard let at = d.answered else { return "The CEO acts on it at its next run." }
        let phase = d.workstream.flatMap { w in p.factory?.workstreams.first { $0.id == w } }.map { " \($0.id) is now in \($0.phase.label.lowercased())." } ?? ""
        if let run = heartbeat(p)?.last, run.started > at {
            return "Taken up in the run of \(HeartbeatCard.when(run.started)).\(phase)"
        }
        return "Waiting for the CEO: it acts on it \(pickUp(p))."
    }

    // MARK: the field guide and the walk (D78)

    /// The campus effects you have seen (kept between launches, except in a demo).
    @Published var seenEffects: Set<String> = Set(AppModel.demo ? [] : UserDefaults.standard.stringArray(forKey: "seenEffects") ?? [])
    /// The first time an effect shows: what it is, for a few seconds at the top of the campus.
    @Published var fieldNote: (title: String, line: String)?
    private var fieldNoteToken = 0
    func effectAppeared(_ kind: String, _ title: String, _ line: String) {
        guard !seenEffects.contains(kind) else { return }
        seenEffects.insert(kind)
        if !fixture { UserDefaults.standard.set(Array(seenEffects), forKey: "seenEffects") }
        fieldNote = (title, line)
        fieldNoteToken += 1
        let token = fieldNoteToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in if self?.fieldNoteToken == token { self?.fieldNote = nil } }
    }

    /// The guided first walk: nil when not walking; 0 offers it, 1…4 its steps, 5 done. Offered once, at the first launch.
    @Published var walkStep: Int? = {
        if AppModel.firstRunDemo { return 0 }
        if AppModel.demo { return nil }
        return UserDefaults.standard.bool(forKey: "walkDone") ? nil : 0
    }()
    /// times N (or the yellow key) took you to the next that waits, for the walk's third step
    @Published var nextPressed = 0
    func endWalk() {
        walkStep = nil
        walkGoalDone = false
        if !fixture { UserDefaults.standard.set(true, forKey: "walkDone") }
    }

    func runNow(_ project: Project) { runNow(root: project.root) }
    func runNow(root: String) {
        heartbeats.wake(root, .runNow)
        beat()
    }

    /// One tick of the heartbeat: start whoever is due, and redraw (last run, next beat, a countdown).
    func beat() {
        if projectSettings.devops.enabled, heartbeats.state(EngineRoom.folder.path, heartbeat: projectSettings.devops.heartbeat).next != nil { prepareEngineRoomIfStale() }
        let names = Dictionary(world.projects.map { ($0.root, $0.name) }, uniquingKeysWith: { a, _ in a })
        heartbeats.tick(projectSettings, names: names) { [weak self] root, run in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                // a CEO run that failed says so, naming the factory; the notification opens its CEO tab
                if run.outcome == .failed || run.outcome == .timedOut, root != EngineRoom.folder.path {
                    let name = names[root] ?? (root as NSString).lastPathComponent
                    self.alerts.post(title: "\(name): the CEO run \(run.outcome == .timedOut ? "timed out" : "failed")",
                                     body: (run.detail ?? "See the log") + ". Its CEO tab has the log.", key: "ceo:\(root)", kind: .warn)
                }
            }
        }
        objectWillChange.send()
    }

    /// The fixture's runtime: it waits half a minute and succeeds, so the demo shows a run without running anything.
    nonisolated static let demoHeartbeat = HeartbeatRunner(
        folder: FileManager.default.temporaryDirectory.appendingPathComponent("meatproxy-fixture/heartbeats"),
        resolve: { _ in HeartbeatRunner.Launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) },
        directory: { _ in FileManager.default.temporaryDirectory })

    /// Writes your answer into the question's file, off the main thread, then reads the world again.
    /// Returns why it failed, or nil.
    func answer(_ decision: FactoryDecision, in project: Project, yes: Bool, note: String) async -> String? {
        guard let root = project.factory?.root, !decision.file.isEmpty else { return "This question has no file." }
        let url = URL(fileURLWithPath: root).appendingPathComponent(decision.file)
        let result: String? = await Task.detached(priority: .userInitiated) {
            do { try DecisionAnswer.answer(url, yes: yes, note: note); return nil } catch { return error.localizedDescription }
        }.value
        // your answer wakes the CEO a few minutes later (D47), unless the factory says otherwise
        let wakes = project.id == World.opsID ? projectSettings.devops.heartbeat.wakeOnAnswer : projectSettings.entry(project.root)?.heartbeat.wakeOnAnswer ?? false
        if result == nil, wakes {
            heartbeats.wake(project.root, .answered([decision.id]))
        }
        refresh()
        return result
    }

    /// Your release of finished work (D81): writes it into the factory's decisions off the main thread, wakes the CEO
    /// like an answer does, then reads the world again. Returns why it failed, or nil.
    func release(_ workstreams: [Workstream], in project: Project) async -> String? {
        guard let root = project.factory?.root else { return "This floor is no factory." }
        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            Result { try ReleaseRequest.send(root: root, workstreams: workstreams) }
        }.value
        if case .success(let id) = result, projectSettings.entry(project.root)?.heartbeat.wakeOnAnswer ?? false {
            heartbeats.wake(project.root, .answered([id]))
        }
        refresh()
        if case .failure(let e) = result { return e.localizedDescription }
        return nil
    }

    /// The demo factory's logo: a pebble, written once to a temporary file.
    nonisolated static let demoLogo: String? = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("meatproxy-fixture/pebble-logo.svg")
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#2f6f8f"/><ellipse cx="32" cy="36" rx="20" ry="15" fill="#9fd3e6"/><ellipse cx="27" cy="31" rx="7" ry="4" fill="#e9f6fb"/></svg>"##
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? svg.write(to: u, atomically: true, encoding: .utf8)) == nil ? nil : u.path
    }()

    nonisolated static func writeFixtureFactory() -> String? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meatproxy-fixture/pebble-puzzles")
        try? FileManager.default.removeItem(at: root)
        for (rel, text) in Fixture.factoryFiles() {
            let u = root.appendingPathComponent(rel)
            do {
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: u, atomically: true, encoding: .utf8)
            } catch { return nil }
        }
        return root.path
    }

    // MARK: sessions

    /// How a session is drawn: its role in its project (the CEO is the project's main chat, D41) and its id.
    /// A person's look, as the floor casts it: the project with its standing CEO (`withStandingCEO`), exactly as the
    /// world paints the floor, so the HUD and the floor never disagree on who the CEO is.
    func cast(of s: Session) -> CastKey {
        world.projects.first { $0.sessions.contains { $0.id == s.id } }?.withStandingCEO.cast(of: s) ?? CastKey(role: s.workRole, seed: s.id)
    }

    /// A project's CEO as the floor shows it: the person of `ceoID` on the floor's project (with its standing CEO).
    /// One source for the briefing, the Team tab and anything else that names the CEO.
    func ceo(of p: Project) -> (name: String, cast: CastKey) {
        let floor = p.withStandingCEO
        if let id = floor.ceoID, let s = floor.sessions.first(where: { $0.id == id }) { return (s.persona.name, floor.cast(of: s)) }
        return (Persona(id: "ceo:" + p.root).name, CastKey(role: .ceo, seed: "ceo:" + p.root))
    }

    func session(_ id: String?) -> (project: Project, session: Session)? {
        guard let id else { return nil }
        for p in world.projects { if let s = p.sessions.first(where: { $0.id == id }) { return (p, s) } }
        return nil
    }
}
