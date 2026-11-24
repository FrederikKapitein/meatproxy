import SpriteKit
import FactoryCore

/// Where you are in either world, for the level chips, the breadcrumb and the panels (D24).
public struct WorldSelection: Equatable, Sendable {
    public var orbit = false
    public var level: Level = .all
    public var crumb: [String] = ["Campus"]
    public var provider: Provider?
    public var engineRoom = false
    public var projectID: String?
    public var sessionID: String?
    public var subAgentID: String?
    /// The server, deploy or backup picked in the Server room (round the black hole in Orbit).
    public var serverID: String?
    /// A factory's question open in the inspector (D25, D11): the Project level of its factory, with the decision card.
    public var decisionID: String?
    /// A factory's workstream: its card in the inspector (Office, at the Project level) or its planet (Orbit, Session level).
    public var workstreamID: String?
    public init() {}
}

/// Owns the art engine and the three scenes, moves between them, and keeps one selection for the HUD (D24, D31).
/// Office: campus (All) → building (Provider) → floor (Project) → person (Session) → helper (Sub-agent).
/// Orbit: all galaxies → galaxy → solar system → planet → moon.
@MainActor
public final class WorldController {
    public let engine = ArtEngine()
    public private(set) var world: World = .empty
    public private(set) var selection = WorldSelection()
    public var onChange: ((WorldSelection) -> Void)?
    public var onStatus: ((String?) -> Void)?
    /// the campus's hover title, for the HUD's tooltip
    public var onHoverTitle: ((HoverTitle?) -> Void)?
    /// an effect shows on the campus: kind, title, meaning (D78)
    public var onEffect: ((String, String, String) -> Void)?

    public let campus = CampusScene(size: CGSize(width: 1200, height: 800))
    public private(set) var floor: FloorScene?
    public let orbit = OrbitScene(size: CGSize(width: 1200, height: 800))
    public private(set) var inOrbit = false
    private weak var view: SKView?
    private var figures: [String: Figure] = [:]
    private var campusSignature = ""
    private var orbitSignature = ""
    private var painting = false
    /// the campus is painted by moonlight (A8)
    private var campusNight = false
    private var needsRepaint = false
    private var needsIndex = -1
    /// the question you asked to see; it stays while you are at its project's level, so a fly there does not drop it
    private var decisionFocus: (project: String, id: String, workstream: Bool)?

    public init() {
        campus.onFocus = { [weak self] key in self?.focusChanged(key) }
        campus.onEnterFloor = { [weak self] id in self?.enterFloor(id) }
        campus.onNext = { [weak self] in self?.nextWaiting() }
        campus.onSelectSession = { [weak self] id in self?.select(session: id) }
        campus.onHoverTitle = { [weak self] t in self?.onHoverTitle?(t) }
        campus.onEffect = { [weak self] k, t, l in self?.onEffect?(k, t, l) }
        // A8: dusk and dawn repaint the campus by moonlight or by day
        campus.onNightChange = { [weak self] night in
            guard let self, self.campusNight != night else { return }
            self.campusNight = night
            Task { await self.repaintCampus() }
        }
        campus.onSelectServer = { [weak self] c in guard let self else { return }; self.select(server: self.world.racks.indices.contains(c) ? self.world.racks[c].id : nil) }
        orbit.engine = engine
        setSafeArea(Self.defaultSafeArea)
        orbit.onPath = { [weak self] p in self?.orbitPathChanged(p) }
        orbit.onNext = { [weak self] in self?.nextWaiting() }
    }

    public func attach(_ v: SKView) {
        view = v
        v.ignoresSiblingOrder = false
        if let f = pendingFree { pendingFree = nil; setSafeArea(f) }
        if v.scene == nil { v.presentScene(inOrbit ? orbit : (floor ?? campus)) }
    }

    public var animationsEnabled: Bool {
        get { campus.animationsEnabled }
        set { campus.animationsEnabled = newValue; floor?.animationsEnabled = newValue; orbit.animationsEnabled = newValue }
    }

    // MARK: the free area

    /// What the HUD leaves free of the view, in view points: the quest log on the left, the inspector on the right, the
    /// top and bottom bars (Spel+: 360 + 16 a side, 64 top and bottom).
    public struct SafeArea: Equatable, Sendable {
        public var left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat
        public init(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) { self.left = left; self.right = right; self.top = top; self.bottom = bottom }
    }
    public static let defaultSafeArea = SafeArea(left: 376, right: 376, top: 64, bottom: 64)
    public private(set) var safeArea = WorldController.defaultSafeArea
    private var pendingFree: CGRect?

    /// The HUD says what it covers: every world frames itself inside the rest. The campus overview keeps no room on the
    /// right (no inspector there; the island runs out of the view on purpose, A4), its building levels and the floors do.
    /// The free area as the HUD keeps it (AppModel.freeArea): a rect in window points from the top left, measured
    /// against the world's view. Without an inspector open its right edge is near the window's; the building levels
    /// still keep room for the inspector they open.
    public func setSafeArea(_ free: CGRect) {
        guard free.width > 0, free.height > 0 else { return }
        // (before the view is attached: kept for then)
        guard let v = view else { pendingFree = free; return }
        let size = v.bounds.size
        setSafeArea(SafeArea(left: free.minX, right: max(0, size.width - free.maxX), top: free.minY, bottom: max(0, size.height - free.maxY)))
    }

    public func setSafeArea(_ a: SafeArea) {
        safeArea = a
        campus.insets = (a.left, 0); campus.bars = (a.top, a.bottom); campus.inspectorRight = max(a.right, Self.defaultSafeArea.right)
        orbit.insets = (a.left, 0); orbit.bars = (a.top, a.bottom)
        if let f = floor { f.insets = (a.left, a.right); f.bars = (a.top, a.bottom) }
    }

    // MARK: data

    public func show(_ w: World) {
        world = w
        let sig = Self.signature(w)
        if sig != campusSignature { campusSignature = sig; Task { await repaintCampus() } }
        else { campus.updateLife(w) }
        if sig != orbitSignature { orbitSignature = sig; Task { await repaintOrbit() } }
        if let f = floor, let p = w.project(id: f.projectID) { Task { await paintFloor(p.withStandingCEO, present: false) } }
        emit()
    }

    static func signature(_ w: World) -> String {
        w.buildings.map { b in b.provider.rawValue + ":" + b.projects.map { signature($0, now: w.now) }.joined(separator: ",") }.joined(separator: "|")
            + "|servers:" + w.servers.map { "\($0.id)=\($0.kind.rawValue)/\($0.state.rawValue)" }.joined(separator: ",")
            // what waits for you is painted into the campus (the pillar's count, a storey's yellow blade sign): a factory
            // question answered or asked, also the Server room's, repaints it, as a session that starts waiting does
            + "|waits:" + w.needsYou.map(\.id).joined(separator: ",")
    }
    static func signature(_ p: Project, now: Date) -> String {
        p.id + "=" + p.sessions.map { "\($0.id.prefix(8))\($0.state(now: now).rawValue.prefix(2))\($0.subAgents.count)\($0.subAgents.filter(\.finished).count)\($0.room(now: now).rawValue.prefix(3))" }.joined()
            + (p.team.map { t in "|t" + t.names.map { "\($0):\(t.count($0))" }.joined(separator: ",") } ?? "")
    }

    /// The people of a project, and their helpers, as cast keys.
    private func casts(_ p: Project) -> [CastKey] { p.sessions.flatMap { s in [p.cast(of: s)] + s.subAgents.map(\.cast) } + p.teamSlots.map(\.cast) }

    private func loadFigures(_ keys: [CastKey]) async {
        for k in keys where figures[k.key] == nil { if let f = try? await engine.figure(k) { figures[k.key] = f } }
    }

    public func repaintCampus() async {
        if painting { needsRepaint = true; return }
        painting = true
        if !campus.isPainted { onStatus?("Building the campus…") }
        do {
            let started = Date()
            let art = try await engine.campus(world, night: campusNight)
            if WindowShotLog.on { print("campus painted in \(Int(Date().timeIntervalSince(started) * 1000)) ms (art engine \(art.timing))\(art.night ? ", by moonlight" : "")") }
            // a few of the team walk the roads: the most recent sessions
            let walkers = world.projects.flatMap { p in p.sessions.map { (p, $0) } }.sorted { $0.1.lastAt > $1.1.lastAt }.prefix(CampusScene.walkerCount).map { $0.0.cast(of: $0.1) }
            await loadFigures(walkers)
            var fig: [CastKey: Figure] = [:]
            for k in walkers { if let f = figures[k.key] { fig[k] = f } }
            campus.apply(art, world: world, figures: fig)
            // the campus was drawn anew: the open slot comes back where its server now sits (racks go problems first)
            if !inOrbit, let id = selection.serverID, let k = world.racks.firstIndex(where: { $0.id == id }) {
                campus.showSlot(k, name: world.racks[k].name, state: world.racks[k].state.rawValue, animated: false)
            }
            onStatus?(nil)
        } catch { onStatus?("The art engine did not answer: \(error.localizedDescription)") }
        // the flag goes down first: a repaint asked for meanwhile (new data, a night that fell) must not find it still up
        // and be lost
        painting = false
        if needsRepaint { needsRepaint = false; await repaintCampus() }
    }

    private func repaintOrbit() async {
        guard Self.orbitEnabled else { return }      // switched off (D53): no universe is generated
        let keys = OrbitScene.bodyKeys(world)
        do {
            let layout = try await engine.orbitLayout(galaxies: world.buildings.map { ($0.provider.rawValue, $0.projects.count) }, bodies: keys)
            orbit.apply(world, layout: layout)
        } catch { onStatus?("The art engine did not answer: \(error.localizedDescription)") }
    }

    private func paintFloor(_ p: Project, present: Bool) async {
        do {
            let art = try await engine.floor(p.provider)
            // the room first; people step in as their figures are painted (the first time takes a moment)
            let missing = casts(p).filter { figures[$0.key] == nil }
            if !missing.isEmpty {
                Task { @MainActor in
                    await self.loadFigures(missing)
                    if let f = self.floor, f.projectID == p.id, let fresh = self.world.project(id: p.id) { f.apply(art, project: fresh.withStandingCEO, figures: self.figures, now: self.world.now) }
                }
            }
            let scene = floor ?? FloorScene(size: view?.bounds.size ?? CGSize(width: 1200, height: 800))
            scene.engine = engine
            scene.animationsEnabled = campus.animationsEnabled
            scene.insets = (safeArea.left, safeArea.right); scene.bars = (safeArea.top, safeArea.bottom)
            scene.onSelect = { [weak self] s, a in self?.selectInFloor(s, a) }
            scene.onExit = { [weak self] in self?.exitFloor() }
            scene.onNext = { [weak self] in self?.nextWaiting() }
            scene.onContext = onContext
            scene.apply(art, project: p, figures: figures, now: world.now)
            if present {
                floor = scene
                guard !inOrbit else { return }
                if self.present(scene, fade: 0.35) { scene.arrive() }
                else { scene.cam.setScale(scene.homeScale); scene.cam.position = scene.homeCenter }
            }
        } catch { onStatus?("The art engine did not answer: \(error.localizedDescription)") }
    }

    // MARK: the two worlds

    /// Office or Orbit (⌘1 / ⌘2): the same selection carries over where it can.
    /// Orbit is switched off for now (D53): it is to be judged again later. The code stays; this is its one switch.
    public static let orbitEnabled = false

    public func showOrbit(_ on: Bool) {
        guard on != inOrbit, !on || Self.orbitEnabled else { return }
        inOrbit = on
        let sel = selection
        if on {
            present(orbit)
            if let w = sel.workstreamID, let p = sel.projectID { orbit.fly(toSession: Project.workstreamPlanetID(p, w)) }
            else if let a = sel.subAgentID, let s = sel.sessionID { orbit.fly(toSession: s, subAgent: a) }
            else if let s = sel.sessionID { orbit.fly(toSession: s) }
            else if let p = sel.projectID { orbit.fly(toProject: p) }
            else if sel.engineRoom { orbit.fly(toProvider: "engine") }
            else if let p = sel.provider { orbit.fly(toProvider: p.rawValue) }
            orbitPathChanged(orbit.path)
        } else {
            selection = WorldSelection()
            present(floor ?? campus)
            if let s = sel.sessionID { select(session: s, subAgent: sel.subAgentID) }
            else if let w = sel.workstreamID, let p = sel.projectID { select(workstream: w, in: p) }
            else if let d = sel.decisionID, let p = sel.projectID { select(decision: d, in: p) }
            else if let p = sel.projectID { enterFloor(p) }
            else if floor == nil { campus.focus(on: sel.engineRoom ? "engine" : sel.provider?.rawValue); focusChanged(sel.engineRoom ? "engine" : sel.provider?.rawValue) }
            emit()
        }
    }

    /// The scene that should be on screen: what the HUD says, so the view, its input and the breadcrumb never part.
    private var current: SKScene { inOrbit ? orbit : (floor ?? campus) }
    /// The scene a fade is on its way to (cleared once it is on screen).
    private weak var fading: SKScene?

    /// Puts a scene on screen: with a short fade while SpriteKit draws frames, else at once. A fade waits on frames, and
    /// frames were seen to stop with the view none the wiser (the outgoing scene then sat there, paused, taking the
    /// input): so a moment after the fade should have ended, a scene that is still not on screen is put there at once.
    /// Returns whether it fades.
    @discardableResult
    private func present(_ scene: SKScene, fade: TimeInterval = 0.3) -> Bool {
        guard let v = view else { return false }
        if v.scene === scene { fading = nil; scene.isPaused = false; return false }
        if fading === scene { return true }
        guard campus.animationsEnabled, v.drawsFrames else { fading = nil; v.presentScene(scene); scene.isPaused = false; return false }
        fading = scene
        v.presentScene(scene, transition: .crossFade(withDuration: fade))
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.35) { [weak self, weak scene] in
            guard let self, let scene, let v = self.view else { return }
            if self.fading === scene { self.fading = nil }
            guard self.current === scene, v.scene !== scene else { scene.isPaused = false; return }
            v.presentScene(scene)
            scene.isPaused = false
        }
        return true
    }

    private func orbitPathChanged(_ p: OrbitPath) {
        guard inOrbit else { return }
        var s = WorldSelection()
        s.orbit = true; s.level = p.level; s.provider = p.provider; s.engineRoom = p.engineRoom
        s.projectID = p.projectID; s.sessionID = p.sessionID; s.subAgentID = p.subAgentID; s.serverID = p.serverID
        // a workstream's planet is no session
        if let id = p.sessionID, let ws = Project.workstream(fromPlanetID: id) { s.sessionID = nil; s.workstreamID = ws.workstream }
        // an idea's body opens its factory (its Ideas are in the inspector)
        if let id = p.sessionID, Project.isIdeaPlanet(id) { s.sessionID = nil; s.level = .project }
        selection = s
        keepDecision()
        emit()
    }

    // MARK: navigation in the Office

    private func focusChanged(_ key: String?) {
        // the campus speaks only for itself: never over Orbit's selection
        guard !inOrbit else { return }
        campus.showSlot(nil)
        selection = WorldSelection()
        decisionFocus = nil
        if let key {
            if key == "engine" { selection.engineRoom = true; selection.level = .provider }
            else if let p = Provider(rawValue: key) { selection.provider = p; selection.level = .provider }
        }
        emit()
    }

    /// A right-click in any world (D72): what it was on and where, for the HUD's menu.
    public var onContext: ((ContextTarget?, CGPoint) -> Void)? {
        didSet { campus.onContext = onContext; floor?.onContext = onContext }
    }

    /// The Status layer on the campus (D69).
    public func setStatusLayer(_ on: Bool) { campus.setStatusLayer(on) }

    public func focusBuilding(_ key: String?) {
        if inOrbit { orbit.fly(toProvider: key); return }
        if floor != nil { exitFloor() }
        campus.focus(on: key); focusChanged(key)
    }

    public func enterFloor(_ projectID: String) {
        guard let p = world.project(id: projectID) else { return }
        if inOrbit { orbit.fly(toProject: projectID); return }
        selection = WorldSelection(); selection.provider = p.provider; selection.projectID = p.id; selection.level = .project
        emit()
        if view?.scene === campus {
            campus.flyIntoFloor(projectID) { [weak self] in Task { await self?.paintFloor(p.withStandingCEO, present: true) } }
        } else {
            Task { await paintFloor(p.withStandingCEO, present: true) }
        }
    }

    public func exitFloor() {
        guard let f = floor else { return }
        let building = world.project(id: f.projectID)?.provider.rawValue
        floor = nil
        present(campus)
        campus.focus(on: building)
        focusChanged(building)
    }

    private func selectInFloor(_ session: String?, _ subAgent: String?) {
        guard !inOrbit else { return }
        // the resting CEO is no session of its own: a click on it shows the factory
        if let s = session, s.hasPrefix(Project.standingCEOPrefix) { selectInFloor(nil, nil); return }
        selection.sessionID = session; selection.subAgentID = subAgent
        selection.level = subAgent != nil ? .subAgent : session != nil ? .session : .project
        keepDecision()
        emit()
    }

    /// Shows a factory's question: its floor (or solar system) with the decision card in the inspector.
    public func select(decision id: String, in projectID: String) {
        guard world.decision(project: projectID, id) != nil else { return }
        decisionFocus = (projectID, id, false)
        showDetail(in: projectID)
    }

    /// Shows a factory's workstream: its card in the Office, its planet in Orbit.
    public func select(workstream id: String, in projectID: String) {
        guard world.project(id: projectID)?.factory?.workstreams.contains(where: { $0.id == id }) == true else { return }
        if inOrbit { orbit.fly(toSession: Project.workstreamPlanetID(projectID, id)); return }
        decisionFocus = (projectID, id, true)
        showDetail(in: projectID)
    }

    private func showDetail(in projectID: String) {
        // the DevOps agent's questions belong to the Server room: no floor to fly into
        if projectID == World.opsID {
            if !inOrbit { if floor != nil { exitFloor() }; campus.focus(on: "engine") }
            selection = WorldSelection(); selection.engineRoom = true; selection.level = .provider; selection.projectID = projectID
            // the Server room sits at the building level, so the question is kept here, not by keepDecision's project rule
            selection.decisionID = decisionFocus.flatMap { $0.project == projectID && !$0.workstream ? $0.id : nil }
            emit()
            return
        }
        if inOrbit {
            if selection.projectID == projectID && selection.level == .project { keepDecision(); emit() } else { orbit.fly(toProject: projectID) }
            return
        }
        if floor?.projectID == projectID, view?.scene === floor {
            floor?.select(session: nil, subAgent: nil)
            selection.sessionID = nil; selection.subAgentID = nil; selection.level = .project
        } else {
            enterFloor(projectID)
        }
        keepDecision()
        emit()
    }

    /// Back from the question to its project.
    public func closeDecision() {
        decisionFocus = nil
        selection.decisionID = nil; selection.workstreamID = nil
        emit()
    }

    /// The question stays on screen while you are at its project's level; another project, or a person, lets it go.
    private func keepDecision() {
        // (in Orbit a workstream is a planet, which the path itself says)
        guard let f = decisionFocus else { selection.decisionID = nil; if !inOrbit { selection.workstreamID = nil }; return }
        if selection.projectID == f.project && selection.level == .project {
            selection.decisionID = f.workstream ? nil : f.id
            selection.workstreamID = f.workstream ? f.id : nil
            return
        }
        selection.decisionID = nil
        if !inOrbit { selection.workstreamID = nil }
        // still on the way there (Orbit flies through the levels above): keep it for when it arrives
        if selection.projectID != nil || selection.level.rawValue > Level.project.rawValue { decisionFocus = nil }
    }

    /// A server (D52): in the Office its slot slides out of its rack in the Server room, in Orbit its body round the
    /// black hole is picked; the inspector shows its detail. nil closes it (the slot slides back in).
    public func select(server id: String?) {
        if inOrbit { orbit.select(infra: id); return }
        if floor != nil { exitFloor() }
        if !(selection.engineRoom && selection.projectID == nil) { campus.focus(on: "engine") }
        selection = WorldSelection(); selection.engineRoom = true; selection.level = .provider; selection.serverID = id
        decisionFocus = nil
        let k = id.flatMap { i in world.racks.firstIndex { $0.id == i } }
        campus.showSlot(k, name: k.map { world.racks[$0].name } ?? "", state: k.map { world.racks[$0].state.rawValue } ?? "ok")
        emit()
    }

    public func select(session id: String, subAgent: String? = nil) {
        guard let p = world.projects.first(where: { $0.sessions.contains { $0.id == id } }) else { return }
        if inOrbit { orbit.fly(toSession: id, subAgent: subAgent); return }
        if floor?.projectID == p.id {
            floor?.select(session: id, subAgent: subAgent); selectInFloor(id, subAgent)
        } else {
            enterFloor(p.id)
            Task { @MainActor in
                for _ in 0..<100 { if floor?.projectID == p.id, view?.scene === floor { break }; try? await Task.sleep(nanoseconds: 50_000_000) }
                floor?.select(session: id, subAgent: subAgent); selectInFloor(id, subAgent)
            }
        }
    }

    // the scene the HUD says is current, not whatever the view shows (they can part while a fade waits on frames)
    public func up() {
        if !inOrbit, selection.serverID != nil, selection.decisionID == nil { select(server: nil); return }
        if selection.decisionID != nil || (!inOrbit && selection.workstreamID != nil) { closeDecision(); return }
        (current as? WorldScene)?.up()
    }
    /// Debug aid for window shots: a person on the open floor walks to another room.
    public func debugWalk(_ session: String, to room: String) { floor?.debugWalk(session, to: room) }
    public func zoom(_ factor: CGFloat) { (current as? WorldScene)?.zoom(by: factor) }
    /// Debug aid for window shots: where a person on the open floor is, in view points from the top left.
    public func personViewPoint(_ id: String) -> CGPoint? { floor?.personViewPoint(id) }

    /// The Needs-you counter (D25): the next thing that waits, a session on its floor or as its planet, or a factory's
    /// question in the inspector.
    public func nextWaiting() {
        let list = world.needsYou
        guard !list.isEmpty else { return }
        needsIndex = (needsIndex + 1) % list.count
        open(list[needsIndex])
    }

    public func open(_ item: NeedsYou) {
        switch item {
        case .session(_, let s): select(session: s.id)
        case .decision(let p, let d): select(decision: d.id, in: p.id)
        case .release(let p, _): enterFloor(p.id)
        }
    }

    /// The head and shoulders of a session's person, for the HUD cards.
    public func portrait(_ cast: CastKey) -> CGImage? { figures[cast.key]?.portrait }
    public func ensurePortraits(_ keys: [CastKey]) async { await loadFigures(keys) }

    private func emit() {
        var crumb = [selection.orbit ? "Universe" : "Campus"]
        if selection.engineRoom { crumb.append("Server room") }
        if let p = selection.provider { crumb.append(p.displayName) }
        if let id = selection.projectID, id != World.opsID, let p = world.project(id: id) { crumb.append(p.name) }
        if let id = selection.sessionID, let s = world.projects.flatMap(\.sessions).first(where: { $0.id == id }) { crumb.append(selection.orbit ? s.title : s.persona.name) }
        if let id = selection.subAgentID, let a = world.projects.flatMap(\.sessions).flatMap(\.subAgents).first(where: { $0.id == id }) { crumb.append(a.type) }
        if let id = selection.workstreamID { crumb.append(id) }
        if let id = selection.decisionID { crumb.append(id) }
        selection.crumb = crumb
        onChange?(selection)
    }
}

/// Window shots print a few timings (debug aid).
enum WindowShotLog { static let on = ProcessInfo.processInfo.environment["SF_WINDOW_SHOT"] != nil }
