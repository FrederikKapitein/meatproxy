import SpriteKit
import FactoryCore

/// Where you are in Orbit, by zoom and what is nearest (the level follows the zoom, D24).
public struct OrbitPath: Equatable, Sendable {
    public var level: Level = .all
    public var provider: Provider?
    public var engineRoom = false
    public var projectID: String?
    public var sessionID: String?
    public var subAgentID: String?
    /// The server, deploy or backup picked round the black hole (Engine room level only).
    public var serverID: String?
}

/// Orbit (D6, D14, D42): galaxy = provider, solar system = project, planet = session, moon = sub-agent, and the Engine
/// room as the black hole at the top, with its servers round it (D26). One continuous zoom from all galaxies to a single
/// moon, with the wheel or a pinch, and a click flies there. The universe lives in its own coordinates (doubles, y down,
/// as on the board); every frame places the bodies on screen, so SpriteKit never has to zoom a thousand times. Every body
/// comes from the generator, as an image per size step and light direction; state is a hairline hexagon round a body,
/// never on it. Galaxies turn slowly while you look at them from afar; the black hole's disk always turns.
public final class OrbitScene: WorldScene {
    var onPath: ((OrbitPath) -> Void)?
    var onNext: (() -> Void)?
    weak var engine: ArtEngine?
    /// The width the HUD's inspector takes on the right once anything is picked (it shows from the Provider level on).
    public var inspectorWidth: CGFloat = 384

    struct Moon { var sub: SubAgent; var body: OrbitBodyKey; var scale: CGFloat; var extent: CGFloat }
    struct Planet { var session: Session; var state: SessionState; var body: OrbitBodyKey; var scale: CGFloat; var extent: CGFloat; var moons: [Moon]; var workstream: Workstream? = nil; var idea: FactoryIdea? = nil }
    /// px, py: where the system sits in its galaxy's own plane (face on, in galaxy radii); x, y: where it is now.
    struct System { var project: Project; var px: CGFloat; var py: CGFloat; var x: CGFloat; var y: CGFloat; var phase: CGFloat; var star: OrbitBodyKey; var scale: CGFloat; var extent: CGFloat; var planets: [Planet]; var waits: Bool }
    /// pa in degrees, incl in radians and the sense the arms wind (twist's sign): what turns the plane like the generator.
    struct Galaxy { var provider: Provider; var x: CGFloat; var y: CGFloat; var r: CGFloat; var pa: CGFloat; var incl: CGFloat; var sgn: CGFloat; var body: OrbitBodyKey; var systems: [System] }
    /// A server, deploy or backup on its orbit round the hole: a0 its slot's angle, d the orbit in shadow radii.
    struct Infra { var server: Server; var body: OrbitBodyKey; var a0: CGFloat; var d: CGFloat }
    private var galaxies: [Galaxy] = []
    private var infra: [Infra] = []
    private var summary = ServerSummary([])
    private let hole = (x: CGFloat(0), y: CGFloat(-600), r: CGFloat(34))
    private let holeBody = OrbitBodyKey(kind: "blackHole", id: "engine-room", opts: [:])
    private var holeLook = (pa: CGFloat(0), sy: CGFloat(0.2), inner: CGFloat(1.5), outer: CGFloat(3.5), spin: CGFloat(0))
    private var holeShading: HoleShading?
    private var holeNode: SKSpriteNode?
    private var holeLoading = false

    // the camera: centre (cx, cy) in universe units, cs screen points per unit
    private var cx: CGFloat = 0, cy: CGFloat = -120, cs: CGFloat = 0.27
    private var FIT: CGFloat = 0.27, MINS: CGFloat = 0.2
    private let MAXS: CGFloat = 240
    private var flight: (fx: CGFloat, fy: CGFloat, fls: CGFloat, get: () -> CGPoint, ls: CGFloat, t0: TimeInterval, dur: TimeInterval)?
    private var follow: (() -> CGPoint)?
    private var flightSeq = 0
    private var t: Double = 0
    /// galaxy time: runs only while you look from afar (it stops before the Project level, so a system never drifts)
    private var tg: CGFloat = 0
    /// spin time: how far planets and moons have turned on their axes; it stops deep in, at the Sub-agent level, where a
    /// planet fills the view (every step would be a large new image)
    private var ts: CGFloat = 0
    /// the black hole's disk: how far it has turned
    private var holeTurn: CGFloat = 0
    private var now: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var frameDT: CGFloat = 0
    /// when update last ran (wall clock): frames run while it keeps coming
    private var lastFrameWall: CFTimeInterval = 0
    private(set) var path = OrbitPath()
    private var started = false
    private var selectedInfra: String?
    /// the DevOps agent at the hole (nil: off)
    private var opsState: SessionState?
    /// the camera's sideways shift for the HUD panels, eased when the inspector comes or goes
    private var shiftNow: CGFloat?

    /// one turn in 12 minutes (D18: slow, but alive)
    private static let galaxyOmega: CGFloat = .pi * 2 / 720
    /// the disk's inner edge turns once in 24 s (its streaks are mostly rings along the orbit, so slower reads as still)
    private static let holeOmega: CGFloat = .pi * 2 / 24

    // node pools, reused every frame
    private var sprites: [String: SKSpriteNode] = [:], labels: [String: SKLabelNode] = [:], shapes: [String: SKShapeNode] = [:]
    private var planes: [String: (tilt: SKNode, plane: SKSpriteNode)] = [:]
    private var used = Set<String>()
    private let layer = SKNode()
    private var skyNode: SKSpriteNode?
    private var skySize: CGSize = .zero

    // body images: the best one we have per body and light, and what is on its way
    private var textures: [String: (tex: SKTexture, r: CGFloat, w: CGFloat, h: CGFloat)] = [:]
    private var pending = Set<String>()
    /// spin steps' images: when each was last drawn (scene time), so old ones can go
    private var texUsed: [String: TimeInterval] = [:]
    private var lastEvict: TimeInterval = 0
    private var queue: [(key: String, base: String, body: OrbitBodyKey, r: Int, light: Double?)] = []
    private var inflight = 0
    public var isLoading: Bool { !pending.isEmpty || holeLoading }

    enum Target: Equatable { case galaxy(Int), hole, system(Int, Int), planet(Int, Int, Int), moon(Int, Int, Int, Int), infra(Int), ops }
    /// What a click there would pick: x, y, r on screen; hr is the radius of the hover hexagon round it.
    private struct Hit { var x: CGFloat; var y: CGFloat; var r: CGFloat; var pri: Int; var target: Target; var hr: CGFloat; var selected: Bool }
    private var hits: [Hit] = []
    /// where the Engine room's beacon and its mark are this frame (tags keep off it)
    private var beaconRect: CGRect?

    // hover (D24: what lights up is exactly what a click picks)
    private var hoverPoint: CGPoint?
    private var hoverTarget: Target?
    private var hoverShown: Target?
    private var hoverK: CGFloat = 0

    // tags: asked for while drawing, placed at the end so they never print over each other or under the HUD
    private struct TagReq { var id: String; var name: String; var sub: String?; var subColor: SKColor; var anchor: CGPoint; var r0: CGFloat; var alpha: CGFloat; var pri: CGFloat; var below: Bool; var target: Target? }
    private var tagQueue: [TagReq] = []
    private var tagSide: [String: Bool] = [:]
    private var tagVis: [String: CGFloat] = [:]
    private var tagDy: [String: CGFloat] = [:]
    private var tagBelow: [String: Int] = [:]

    public override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = SKColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1)
        content.addChild(layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var dpr: CGFloat { view?.window?.backingScaleFactor ?? 2 }
    /// Frames are running: animation is on and SpriteKit draws (not paused, the window on screen, its display awake).
    /// Without frames a flight, a fade or a hover would wait for the next frame, so they happen at once instead.
    private var frames: Bool {
        guard animationsEnabled, let v = view else { return false }
        return CACurrentMediaTime() - lastFrameWall < 0.25 || v.drawsFrames
    }
    /// the HUD on the right: the inspector shows from the Provider level on
    private func hudRight(_ level: Level) -> CGFloat { max(insets.right, level == .all ? 0 : inspectorWidth) }
    private var shiftGoal: CGFloat { (insets.left - hudRight(path.level)) / 2 }
    private var shift: CGFloat { shiftNow ?? shiftGoal }

    // MARK: the universe from the world

    /// The bodies to ask the generator about, in a fixed order (apply reads the answers in the same order).
    static func bodyKeys(_ world: World) -> [OrbitBodyKey] {
        world.buildings.flatMap { b in b.projects.flatMap { p -> [OrbitBodyKey] in
            [starKey(p)] + p.sessions.flatMap { s -> [OrbitBodyKey] in
                [planetKey(s, p, world.now)] + s.subAgents.map { moonKey($0) }
            } + workstreamPlanets(p).map(\.key) + ideaPlanets(p).map(\.key)
        } }
    }
    static func planetKey(_ s: Session, _ p: Project, _ now: Date) -> OrbitBodyKey {
        // the CEO's runs are one person: one planet that keeps its look from run to run (D47)
        OrbitBodyKey(kind: "planet", id: s.personaSeed, opts: ["role": p.role(of: s).rawValue, "state": s.state(now: now).rawValue])
    }
    /// A project's star. A factory's burns brighter the darker (more autonomous) it runs, and low while paused.
    static func starKey(_ p: Project) -> OrbitBodyKey {
        guard let f = p.factory else { return OrbitBodyKey(kind: "star", id: p.id, opts: [:]) }
        let level = f.autonomy?.level ?? .assistant
        let activity = f.paused ? 0.2 : level == .assistant ? 0.55 : level == .hybrid ? 0.8 : 1
        return OrbitBodyKey(kind: "star", id: p.id, opts: ["activity": String(activity)])
    }

    /// A factory's workstreams as planets round its star: the landscape says the phase (a gas cloud while planned, lava
    /// while built, ice in test, ocean on its way out, jungle when done), the hexagon says it waits for you.
    static func workstreamPlanets(_ p: Project) -> [(body: Session, workstream: Workstream, state: SessionState, key: OrbitBodyKey)] {
        (p.factory?.activeWorkstreams ?? []).map { w in
            let id = Project.workstreamPlanetID(p.id, w.id)
            let state: SessionState = p.waits(w) ? .waiting : w.phase == .done ? .done : .working
            let kind = [WorkPhase.plan: "gas", .build: "lava", .test: "ice", .ship: "ocean", .done: "jungle", .dropped: "rocky"][w.phase]!
            let body = Session(id: id, provider: p.provider, cwd: p.root, title: "\(w.id) \(w.title)",
                               lastAt: w.updated.flatMap { FactoryText.date($0) } ?? .distantPast, turnOpen: false)
            return (body, w, state, OrbitBodyKey(kind: "planet", id: id, opts: ["kind": kind, "state": state.rawValue]))
        }
    }
    /// Your new ideas as small rocky bodies round the factory's star: still forming, with the CEO, until it takes one
    /// (then it is a workstream's planet).
    static func ideaPlanets(_ p: Project) -> [(body: Session, idea: FactoryIdea, key: OrbitBodyKey)] {
        (p.factory?.ideas ?? []).filter { $0.status == .new }.map { i in
            let id = Project.ideaPlanetID(p.id, i.id)
            let body = Session(id: id, provider: p.provider, cwd: p.root, title: "\(i.id) \(i.title)", lastAt: i.sent ?? .distantPast, turnOpen: false)
            return (body, i, OrbitBodyKey(kind: "planet", id: id, opts: ["kind": "rocky", "state": "working"]))
        }
    }
    static func moonKey(_ a: SubAgent) -> OrbitBodyKey { OrbitBodyKey(kind: "moon", id: a.id, opts: ["type": a.type, "finished": a.finished ? "true" : "false"]) }
    static func infraKey(_ s: Server) -> OrbitBodyKey {
        OrbitBodyKey(kind: "infra", id: s.id, opts: ["kind": s.kind.rawValue, "state": s.state == .warn ? "warning" : s.state.rawValue])
    }

    /// Where the i-th of n items sits round the hole (orbit-gen's blackHole slot, before its tilt): angle and orbit.
    static func holeSlot(_ i: Int, _ n: Int) -> (a: CGFloat, d: CGFloat) {
        let side = i % 2, j = i / 2, m = (n + 1) / 2
        let a = (side == 1 ? CGFloat.pi : 0) + (m > 1 ? (CGFloat(j) / CGFloat(m - 1) - 0.5) * 2.1 : 0) * (side == 1 ? -1 : 1)
        return (a, 4.6 + CGFloat(j % 2) * 1.2)
    }

    func apply(_ world: World, layout: OrbitLayout) {
        var k = 0
        func meta() -> (CGFloat, CGFloat) { defer { k += 1 }; return k < layout.bodies.count ? (layout.bodies[k].scale, layout.bodies[k].extent) : (1, 1) }
        let place: [Provider: (CGFloat, CGFloat, CGFloat)] = [.claude: (-1150, -20, 600), .chatgpt: (1150, 40, 540)]
        galaxies = world.buildings.map { b in
            let (gx, gy, gr) = place[b.provider] ?? (0, 400, 500)
            let slots = layout.slots[b.provider.rawValue] ?? []
            let gm = layout.slots["meta:" + b.provider.rawValue] ?? []
            let pa = gm.first?.x ?? 0, incl = gm.first?.y ?? 0, sgn: CGFloat = (gm.count > 1 && gm[1].x < 0) ? -1 : 1
            let a = pa * .pi / 180, ci = max(0.05, cos(incl))
            let systems = b.projects.enumerated().map { i, p -> System in
                let slot = i < slots.count ? slots[i] : CGPoint(x: CGFloat(i % 4) * 0.3 - 0.45, y: CGFloat(i / 4) * 0.3 - 0.3)
                // back into the galaxy's own plane: undo the turn by pa, then the tilt
                let px = slot.x * cos(a) + slot.y * sin(a), py = (-slot.x * sin(a) + slot.y * cos(a)) / ci
                let (ss, se) = meta()
                let planets = p.sessions.map { s -> Planet in
                    let (ps, pe) = meta()
                    let moons = s.subAgents.map { a -> Moon in let (ms, me) = meta(); return Moon(sub: a, body: Self.moonKey(a), scale: ms, extent: me) }
                    return Planet(session: s, state: s.state(now: world.now), body: Self.planetKey(s, p, world.now), scale: ps, extent: pe, moons: moons)
                } + Self.workstreamPlanets(p).map { ws -> Planet in
                    let (ps, pe) = meta()
                    return Planet(session: ws.body, state: ws.state, body: ws.key, scale: ps, extent: pe, moons: [], workstream: ws.workstream)
                } + Self.ideaPlanets(p).map { i -> Planet in
                    let (ps, pe) = meta()
                    return Planet(session: i.body, state: .working, body: i.key, scale: ps * 0.7, extent: pe, moons: [], idea: i.idea)
                }
                let x = gx + slot.x * gr, y = gy + slot.y * gr
                return System(project: p, px: px, py: py, x: x, y: y, phase: x * 0.01, star: Self.starKey(p), scale: ss, extent: se,
                              planets: planets, waits: p.waits(now: world.now))
            }
            return Galaxy(provider: b.provider, x: gx, y: gy, r: gr, pa: pa, incl: incl, sgn: sgn, body: OrbitBodyKey(kind: "galaxy", id: b.provider.rawValue, opts: [:]), systems: systems)
        }
        if let hm = layout.slots["meta:hole"], hm.count >= 3 { holeLook = (hm[0].x, hm[0].y, hm[1].x, hm[1].y, hm[2].x) }
        // servers in a fixed order (by name), so a body keeps its place when its state changes
        let servers = world.servers.sorted { $0.name.lowercased() < $1.name.lowercased() }
        infra = servers.enumerated().map { i, s in let sl = Self.holeSlot(i, servers.count); return Infra(server: s, body: Self.infraKey(s), a0: sl.a, d: sl.d) }
        summary = world.serverSummary
        opsState = world.opsState
        if let id = selectedInfra, !servers.contains(where: { $0.id == id }) { selectedInfra = nil }
        loadHole()
        if !started { started = true; sizeChanged(); cs = FIT; cx = -shift / FIT; cy = -120 }
        draw()
    }

    // MARK: camera

    override func sizeChanged() {
        guard size.width > 0 else { return }
        let home = abs(cs - FIT) < 1e-6
        FIT = min(max(size.width - insets.left - insets.right, size.width * 0.5) / 3600, size.height / 1350); MINS = FIT * 0.8
        if home || !started { cs = FIT; cx = -shift / FIT; cy = -120 }
        skyNode?.size = size
        loadSky()
        draw()
    }

    private func loadSky() {
        let want = CGSize(width: (size.width * dpr).rounded(), height: (size.height * dpr).rounded())
        guard want.width > 0, want != skySize, let e = engine else { return }
        skySize = want
        Task { @MainActor in
            guard let img = await e.sky(width: Int(want.width), height: Int(want.height)), self.skySize == want else { return }
            if self.skyNode == nil { let n = SKSpriteNode(); n.zPosition = -1000; self.cam.addChild(n); self.skyNode = n }
            self.skyNode?.texture = SKTexture(cgImage: img); self.skyNode?.size = self.size
        }
    }

    /// The disk's table, once: then the hole is drawn by the GPU, turning (until then the generator's still image shows).
    private func loadHole() {
        guard holeShading == nil, !holeLoading, let e = engine else { return }
        holeLoading = true
        let look = holeLook
        Task { @MainActor in
            defer { self.holeLoading = false }
            guard let img = await e.body(OrbitBodyKey(kind: "blackHole", id: "engine-room", opts: ["layer": "disk"]), r: 8, light: nil) else { return }
            let tex = SKTexture(cgImage: img.image); tex.filteringMode = .linear
            let sh = HoleShading(pa: look.pa, sy: look.sy, inner: look.inner, outer: look.outer)
            let n = SKSpriteNode(texture: tex); n.shader = sh.shader; n.zPosition = 20; n.isHidden = true
            self.layer.addChild(n)
            self.holeShading = sh; self.holeNode = n
            self.draw()
        }
    }

    private func toS(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - cx) * cs, y: -(y - cy) * cs) }
    private func toW(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / cs + cx, y: -p.y / cs + cy) }

    public override func zoom(by factor: CGFloat, around p: CGPoint? = nil) {
        flight = nil
        let ns = min(max(cs / factor, MINS), MAXS)
        if follow != nil { cs = ns; draw(); return }
        let a = p ?? .zero, w = toW(a)
        cs = ns; cx = w.x - a.x / ns; cy = w.y + a.y / ns
        draw()
    }

    public override func pan(dx: CGFloat, dy: CGFloat) {
        flight = nil; follow = nil
        cx -= dx / cs; cy -= dy / cs
        draw()
    }

    private func fly(_ get: @escaping () -> CGPoint, scale: CGFloat) {
        follow = nil
        let target = min(max(scale, MINS), MAXS)
        func land() { flight = nil; cs = target; let p = get(); cx = p.x - shift / cs; cy = p.y; follow = get; draw() }
        guard frames else { land(); return }
        flight = (cx + shift / cs, cy, log(cs), get, log(target), now, 1.1)
        // frames can stop without the view knowing (a display asleep, a covered window): a flight still lands, so the
        // level, the breadcrumb and the HUD never wait on a frame that does not come
        flightSeq += 1
        let seq = flightSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 + 0.35) { [weak self] in
            guard let self, self.flightSeq == seq, self.flight != nil else { return }
            land()
        }
    }

    private func home() { selectedInfra = nil; fly({ CGPoint(x: 0, y: -120) }, scale: FIT) }

    private func ease(_ k: CGFloat) -> CGFloat { k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2 }

    // MARK: positions, as on the board

    /// Turns every galaxy's plane by its galaxy time and puts the systems where their arm has carried them.
    private func placeSystems() {
        let th = Self.galaxyOmega * tg
        for gi in galaxies.indices {
            let G = galaxies[gi], a = G.pa * .pi / 180, rot = -G.sgn * th, ci = cos(G.incl)
            for si in G.systems.indices {
                let S = G.systems[si]
                let x1 = S.px * cos(rot) - S.py * sin(rot), y1 = (S.px * sin(rot) + S.py * cos(rot)) * ci
                galaxies[gi].systems[si].x = G.x + (x1 * cos(a) - y1 * sin(a)) * G.r
                galaxies[gi].systems[si].y = G.y + (x1 * sin(a) + y1 * cos(a)) * G.r
            }
        }
    }

    private func planetPos(_ s: System, _ i: Int) -> (x: CGFloat, y: CGFloat, R: CGFloat) {
        let R = 10 + CGFloat(i) * 6.5, a = CGFloat(i) * 2.3 + s.phase + CGFloat(t) * 0.06 * (10 / R)
        return (s.x + cos(a) * R, s.y + sin(a) * R * 0.55, R)
    }
    private func moonPos(_ p: (x: CGFloat, y: CGFloat), _ j: Int) -> (x: CGFloat, y: CGFloat, R: CGFloat, back: Bool) {
        let R = 2.8 + CGFloat(j) * 1.1, a = CGFloat(j) * 2.6 + CGFloat(t) * 0.35 / (1 + CGFloat(j) * 0.5)
        // universe y points down: sin < 0 is the far half of the orbit, behind the planet
        return (p.x + cos(a) * R, p.y + sin(a) * R * 0.55, R, sin(a) < 0)
    }
    private func ramp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(1, max(0, (v - a) / (b - a))) }
    private func lightAngle(_ x: CGFloat, _ y: CGFloat, _ sx: CGFloat, _ sy: CGFloat) -> Double { Double(atan2(sy - y, sx - x)) }
    /// The hexagon round a body with a disc of radius `disc`: the board's markR (disc + base), but never smaller than the
    /// one whose flat sides clear the disc by 4 pt (a pointy-top hexagon's flats sit at 0.866 r).
    private func hexR(_ disc: CGFloat, _ base: CGFloat) -> CGFloat { max(disc + base, (disc + 4) / 0.866) }

    /// The infra item's place on screen round the hole at h, with shadow radius Rh on screen.
    private func infraPos(_ I: Infra, h: CGPoint, Rh: CGFloat) -> CGPoint {
        // the same sense as the disk; the inner orbit once in 4 min, the outer once in 5 min 40
        let om: CGFloat = I.d < 5 ? .pi * 2 / 240 : .pi * 2 / 340
        let a = I.a0 - om * CGFloat(t), x = cos(a) * I.d, y = sin(a) * I.d * 0.42, p = holeLook.pa * .pi / 180
        let X = x * cos(p) - y * sin(p), Y = x * sin(p) + y * cos(p)
        return CGPoint(x: h.x + X * Rh, y: h.y - Y * Rh)
    }
    private func infraRadius(_ I: Infra, Rh: CGFloat) -> CGFloat { (I.server.kind == .backup ? 0.12 : 0.16) * Rh }
    private func infraHex(_ I: Infra, R: CGFloat) -> CGFloat { I.server.kind == .backup ? hexR(R, 4) : max(R * 0.75 + 4, (R * 0.42 + 4) / 0.866) }

    // MARK: drawing

    public override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, currentTime - lastTime); lastTime = currentTime
        lastFrameWall = CACurrentMediaTime()
        now += dt; frameDT = CGFloat(dt)
        if animationsEnabled {
            t += dt
            tg += CGFloat(dt) * (1 - ramp(cs, 0.9, 1.4))
            holeTurn += CGFloat(dt) * Self.holeOmega * holeRate
            ts += CGFloat(dt) * (1 - ramp(cs, 32, 42))
        }
        evictSpinTextures()
        // the camera follows the inspector sliding in or out, smoothly
        let goal = shiftGoal
        if let sn = shiftNow, animationsEnabled, view?.isPaused != true { shiftNow = abs(goal - sn) < 0.5 ? goal : sn + (goal - sn) * min(1, CGFloat(dt) / 0.15) }
        else { shiftNow = goal }
        if let f = flight {
            let k = CGFloat(min(1, (now - f.t0) / f.dur)), e = ease(k), p = f.get()
            cs = exp(f.fls + (f.ls - f.fls) * e)
            cx = f.fx + (p.x - f.fx) * e - shift / cs; cy = f.fy + (p.y - f.fy) * e
            if k >= 1 { follow = f.get; flight = nil }
        } else if let g = follow { let p = g(); cx = p.x - shift / cs; cy = p.y }
        // hover fades in over 0.12 s and out over 0.18 s; moving straight to another body swaps at once
        if let h = hoverTarget {
            if hoverShown == nil { hoverK = 0 }
            hoverShown = h
            hoverK = animationsEnabled ? min(1, hoverK + CGFloat(dt) / 0.12) : 1
        } else if hoverShown != nil {
            hoverK = animationsEnabled ? max(0, hoverK - CGFloat(dt) / 0.18) : 0
            if hoverK <= 0 { hoverShown = nil }
        }
        draw()
        frameDT = 0
    }

    /// How fast the disk turns and how bright it burns: quieter with nothing connected, busier the more is ok.
    private var holeActivity: CGFloat { summary.connected ? 0.6 + 0.4 * CGFloat(summary.ok) / CGFloat(summary.total) : 0.3 }
    private var holeRate: CGFloat { 0.5 + 0.5 * holeActivity }

    /// Lays out every visible body, orbit, mark and tag for the current camera.
    public func draw() {
        guard size.width > 0 else { return }
        used.removeAll(keepingCapacity: true); hits.removeAll(keepingCapacity: true); tagQueue.removeAll(keepingCapacity: true); beaconRect = nil
        // no frames running (a still, a hidden window): the camera takes the HUD's room at once, not eased
        if shiftNow != shiftGoal, !frames {
            shiftNow = shiftGoal
            if flight == nil, let g = follow { let p = g(); cx = p.x - shift / cs; cy = p.y }
        }
        placeSystems()
        let s = cs, W = size.width, H = size.height

        drawEngineRoom()
        for (gi, G) in galaxies.enumerated() {
            let g = toS(G.x, G.y), gr = G.r * s
            if g.x + gr * 1.3 < -W / 2 || g.x - gr * 1.3 > W / 2 || g.y - gr > H / 2 || g.y + gr < -H / 2 { continue }
            // the galaxy stays as a faint backdrop deeper in, so systems sit on their arms
            let gda = 1 - 0.85 * ramp(s, 1.5, 6)
            if gda > 0.02 { galaxy(gi, G, at: g, radius: gr, alpha: gda) }
            let hovered = hoverTarget == .galaxy(gi)
            // the name fades as you fly into its level (the breadcrumb and the inspector say it there); hover brings it back
            let ga = hovered ? 1 : 1 - ramp(s, FIT * 1.25, FIT * 1.6)
            if ga > 0 {
                // under the galaxy's whole disk as seen (the hover ellipse's lowest point), so no arm or star runs
                // through the text; on the same dark pill as every tag
                let a = G.pa * .pi / 180, rx = gr * 0.98, ry = rx * cos(G.incl)
                let low = (pow(rx * sin(a), 2) + pow(ry * cos(a), 2)).squareRoot()
                let ly = max(g.y - low - 18, -H / 2 + bars.bottom + 34)
                let name = G.provider.displayName.uppercased()
                label("gal-name-\(gi)", name, at: CGPoint(x: g.x, y: ly), size: 13, color: providerColor(G.provider), alpha: ga, center: true)
                var w = CGFloat(name.count) * 13 * 0.602, h: CGFloat = 16
                if hovered {
                    let k = G.systems.filter(\.waits).count, n = G.systems.count
                    let parts = [("\(n) PROJECT\(n == 1 ? "" : "S")", Self.muted)] + (k > 0 ? [("\(k) NEED\(k == 1 ? "S" : "") YOU", Self.wait)] : [])
                    segments("gal-sub-\(gi)", parts, at: CGPoint(x: g.x, y: ly - 15), alpha: 1)
                    w = max(w, CGFloat(parts.reduce(0) { $0 + $1.0.count } + 3 * (parts.count - 1)) * 9 * 0.602); h = 31
                }
                pill("gal-bg-\(gi)", CGRect(x: g.x - w / 2, y: ly + 8 - h, width: w, height: h), alpha: ga)
            }
            let galSelected = path.level == .provider && path.provider == G.provider
            if s < 2 { hits.append(Hit(x: g.x, y: g.y, r: max(30, gr * 0.45), pri: 0, target: .galaxy(gi), hr: gr * 0.98, selected: galSelected)) }
            for (si, S) in G.systems.enumerated() {
                let c = toS(S.x, S.y), cull = (10 + 6.5 * CGFloat(S.planets.count) + 8) * s + 60
                if abs(c.x) > W / 2 + cull || abs(c.y) > H / 2 + cull { continue }
                let sunR = max(2.2, min(3.2 * s, 44)), disc = sunR * 0.8 * S.scale
                body("star-\(gi)-\(si)", S.star, at: c, radius: sunR * 0.8, light: nil, z: 20, add: true)
                let sh = max(disc * 1.9 + 4, (disc + 4) / 0.866)
                if S.waits { stateMark("star-mark-\(gi)-\(si)", at: c, r: sh, state: .waiting, alpha: s < 4 ? 1 : 0.45) }
                let sysSelected = path.level == .project && path.projectID == S.project.id
                let shr = S.waits ? sh + 8 : sh
                let sa = ramp(s, 0.45, 0.8) * (1 - ramp(s, 8, 14))
                tagQueue.append(TagReq(id: "sys-\(gi)-\(si)", name: S.project.name.uppercased(),
                                       sub: S.waits ? "NEEDS YOU" : nil, subColor: Self.wait, anchor: c, r0: max(disc * 1.9, S.waits ? sh + 4 : disc) + 12,
                                       alpha: sa, pri: S.waits ? 45 : 40, below: true, target: .system(gi, si)))
                hits.append(Hit(x: c.x, y: c.y, r: max(10, sunR + 4), pri: 1, target: .system(gi, si), hr: shr, selected: sysSelected))
                let pa = ramp(s, 2.2, 4)
                if pa <= 0 { continue }
                for (pi, P) in S.planets.enumerated() {
                    let q = planetPos(S, pi), p = toS(q.x, q.y), pr = max(2.2, 1.5 * s)
                    ellipse("orbit-\(gi)-\(si)-\(pi)", center: c, rx: q.R * s, ry: q.R * 0.55 * s,
                            color: P.state == .waiting ? Self.wait.withAlphaComponent(0.4 * pa) : SKColor(red: 0.92, green: 0.91, blue: 0.88, alpha: 0.26 * pa))
                    lit("pl-\(gi)-\(si)-\(pi)", P.body, at: p, radius: pr, angle: lightAngle(q.x, q.y, S.x, S.y), z: 30, alpha: pa, turns: ts / Self.planetDay + S.phase)
                    let prs = pr * P.scale, hasState = P.state == .waiting || P.state == .stuck, hr = hexR(prs, 8)
                    let ma = ramp(s, 14, 22)
                    // a selected moon's cyan ring crosses its planet's state mark: the planet's line yields round it
                    var gap: (c: CGPoint, r: CGFloat)?
                    if ma > 0, path.sessionID == P.session.id, let mi = P.moons.firstIndex(where: { $0.sub.id == path.subAgentID }) {
                        let m = moonPos((q.x, q.y), mi), mrs = max(1.3, 0.42 * s) * P.moons[mi].scale
                        gap = (toS(m.x, m.y), hexR(mrs, 5) + 6)
                    }
                    if hasState { stateMark("pl-mark-\(gi)-\(si)-\(pi)", at: p, r: hr, state: P.state, alpha: pa, gap: gap) }
                    let selected = path.sessionID == P.session.id && path.subAgentID == nil && path.level == .session
                    let selR = hasState ? hr + 8 : hr
                    if selected { ring("pl-sel-\(gi)-\(si)-\(pi)", at: p, r: selR, alpha: pa, lw: 1.4, glow: true) }
                    let la = ramp(s, 3.5, 4.8) * (1 - ramp(s, 90, 150))
                    let sub = [SessionState.working: "WORKING", .waiting: "WAITS ON YOU", .stuck: "STUCK", .done: "DONE"][P.state]!
                    // a workstream says its phase (and ↩ when it went back), a session who it is
                    let who = P.idea != nil ? "YOUR IDEA · WITH THE CEO" : P.workstream.map { w in "\(w.phase.label)\(w.wentBack ? " ↩" : "")" + (P.state == .waiting ? " · WAITS ON YOU" : "") }
                    tagQueue.append(TagReq(id: "pl-tag-\(gi)-\(si)-\(pi)", name: "\(Self.roman(pi + 1))  \(P.session.title.uppercased())",
                                           sub: who ?? "\(sub) · \(P.session.persona.name.uppercased())", subColor: stateColor(P.state), anchor: p,
                                           r0: selected ? selR : hasState ? hr + 4 : prs, alpha: pa * la,
                                           pri: P.state == .stuck ? 32 : P.state == .waiting ? 31 : P.state == .working ? 20 : 10, below: false, target: .planet(gi, si, pi)))
                    hits.append(Hit(x: p.x, y: p.y, r: max(9, prs + 4), pri: 2, target: .planet(gi, si, pi), hr: selR, selected: selected))
                    if ma <= 0 { continue }
                    for (mi, M) in P.moons.enumerated() {
                        let m = moonPos((q.x, q.y), mi), mp = toS(m.x, m.y), mr = max(1.3, 0.42 * s), mrs = mr * M.scale
                        ellipse("morbit-\(gi)-\(si)-\(pi)-\(mi)", center: p, rx: m.R * s, ry: m.R * 0.55 * s, color: SKColor(red: 0.92, green: 0.91, blue: 0.88, alpha: 0.1 * ma))
                        lit("mo-\(gi)-\(si)-\(pi)-\(mi)", M.body, at: mp, radius: mr, angle: lightAngle(m.x, m.y, S.x, S.y), z: m.back ? 25 : 53, alpha: ma,
                            turns: ts / Self.moonDay + CGFloat(mi) * 0.37)
                        let mh = hexR(mrs, 5), msel = path.subAgentID == M.sub.id
                        if msel { ring("mo-sel-\(gi)-\(si)-\(pi)-\(mi)", at: mp, r: mh, alpha: ma, lw: 1.4, glow: true) }
                        let ml = ramp(s, 40, 60)
                        tagQueue.append(TagReq(id: "mo-tag-\(gi)-\(si)-\(pi)-\(mi)", name: M.sub.type.uppercased(), sub: M.sub.finished ? "DONE" : "RUNNING", subColor: Self.muted,
                                               anchor: mp, r0: msel ? mh : mrs, alpha: ma * ml, pri: 15, below: false, target: .moon(gi, si, pi, mi)))
                        hits.append(Hit(x: mp.x, y: mp.y, r: max(8, mrs + 4), pri: 3, target: .moon(gi, si, pi, mi), hr: mh, selected: msel))
                    }
                }
            }
        }
        drawHover()
        placeTags()
        for (k, n) in sprites where !used.contains(k) { n.isHidden = true }
        for (k, n) in labels where !used.contains(k) { n.isHidden = true }
        for (k, n) in shapes where !used.contains(k) { n.isHidden = true }
        for (k, n) in planes where !used.contains(k) { n.tilt.isHidden = true }
        if !used.contains("hole-gpu") { holeNode?.isHidden = true }
        updatePath()
    }

    /// The black hole north of the galaxies, and round it what runs the work (D26): servers as pulsars, deploys as comets,
    /// backups as icy moonlets, on two wide flat orbits. With nothing connected it shows its survey grid and says so.
    private func drawEngineRoom() {
        let s = cs, W = size.width, H = size.height
        let h = toS(hole.x, hole.y), rr = max(13, hole.r * s), Rh = rr * 0.5
        guard abs(h.x) < W / 2 + Rh * 7, abs(h.y) < H / 2 + Rh * 4 else { return }
        if let n = holeNode, let sh = holeShading {
            used.insert("hole-gpu"); n.isHidden = false
            n.position = h; n.size = CGSize(width: HoleShading.quad.width * Rh, height: HoleShading.quad.height * Rh)
            let tt = CGFloat(t)
            sh.set(spin: holeLook.spin - holeTurn, k: 0.6 + 0.4 * holeActivity, rp: Rh * dpr,
                   ring: 1 + 0.04 * sin(tt * .pi * 2 / 3.1), glow: 1 + 0.08 * sin(tt * .pi * 2 / 9))
        } else {
            body("hole", holeBody, at: h, radius: Rh, light: nil, z: 20, cap: 1024)
        }
        let room = path.engineRoom
        let worst = summary.worst
        // fades relative to the Engine room's own zoom (it depends on the window): at 4 they are 1.6–2.6 and 2.5–3.5
        let eS = target(.hole).1
        let ia = ramp(s, eS * 0.4, eS * 0.65)
        // a warning hangs a yellow beacon above the hole, down a red one (as on the datacenter roof)
        if worst == .warn || worst == .down {
            // far out 2.2 shadow radii up, clear of the lensed arc; once the orbits show, clear above the outer one, by
            // as much as a body there with its mark and the beacon's own mark take, so nothing passes through it
            let br = max(1.4, min(3.2, Rh * 0.05)), bm = max(5, min(9, Rh * 0.2))
            let outer = (infra.map(\.d).max() ?? 0) * 0.42 * Rh
            let clear = infra.isEmpty ? Rh * 2.2 : outer + (0.12 * Rh + 4) / 0.866 + 4 + bm + 4 + 6
            let p = holeLook.pa * .pi / 180, d = Rh * 2.2 + (max(Rh * 2.2, clear) - Rh * 2.2) * ia
            let b = CGPoint(x: h.x + sin(p) * d, y: h.y + cos(p) * d)
            let col = worst == .down ? Self.stuck : Self.wait
            let pulse = animationsEnabled ? 0.775 + 0.225 * sin(CGFloat(now) * .pi * 2 / 1.2) : 1
            dot("beacon-glow", at: b, r: br * 5, color: col.withAlphaComponent(0.3 * pulse), z: 21)
            dot("beacon", at: b, r: br, color: col.withAlphaComponent(pulse), z: 22)
            stateMark("beacon-mark", at: b, r: bm, state: worst == .down ? .stuck : .waiting, alpha: 1, tint: worst == .down ? nil : Self.warn)
            beaconRect = CGRect(x: b.x - bm - 4, y: b.y - bm - 4, width: (bm + 4) * 2 + 12, height: (bm + 4) * 2 + 12)
        }
        // far out: the label under it; at the Engine room: its orbits, bodies, tags and a summary
        let la = ramp(s, 0.2, 0.3) * (1 - ramp(s, eS * 0.4, eS * 0.65))
        if la > 0 {
            let y = h.y - rr * 0.95 - 16
            label("hole-name", "ENGINE ROOM", at: CGPoint(x: h.x, y: y), size: 11, color: Self.violet, alpha: la, center: true)
            segments("hole-sub", summaryParts(short: true), at: CGPoint(x: h.x, y: y - 14), alpha: la)
        }
        if ia > 0 {
            let p = -holeLook.pa * .pi / 180
            if infra.isEmpty {
                // never an empty black screen: the survey grid round the hole, under it
                var d: CGFloat = 2.2
                while d <= 6.41 { ellipse("hole-grid-\(Int(d * 10))", center: h, rx: d * Rh, ry: d * Rh * 0.42, color: Self.hair.withAlphaComponent(0.05 * ia), rotation: p, z: 15, lw: 0.8); d += 0.6 }
                for k in 0..<12 {
                    let a = CGFloat(k) * .pi / 6, c = cos(a), sn = sin(a) * 0.42
                    let path = CGMutablePath()
                    let r0 = CGPoint(x: c * 2.2 * Rh, y: sn * 2.2 * Rh), r1 = CGPoint(x: c * 6.4 * Rh, y: sn * 6.4 * Rh)
                    let rot = CGAffineTransform(rotationAngle: p)
                    path.move(to: CGPoint(x: h.x + r0.applying(rot).x, y: h.y + r0.applying(rot).y)); path.addLine(to: CGPoint(x: h.x + r1.applying(rot).x, y: h.y + r1.applying(rot).y))
                    let n = shape("hole-spoke-\(k)", z: 15); n.path = path; n.strokeColor = Self.hair.withAlphaComponent(0.035 * ia); n.lineWidth = 0.8
                }
            } else {
                for d in Set(infra.map(\.d)).sorted() {
                    let on = infra.filter { $0.d == d }.map(\.server.state).max()
                    let col = on == .down ? Self.stuck.withAlphaComponent(0.38 * ia) : on == .warn ? Self.warn.withAlphaComponent(0.38 * ia) : Self.hair.withAlphaComponent(0.22 * ia)
                    ellipse("hole-orbit-\(Int(d * 10))", center: h, rx: d * Rh, ry: d * Rh * 0.42, color: col, rotation: p, z: 15)
                }
                for (i, I) in infra.enumerated() {
                    let q = infraPos(I, h: h, Rh: Rh), R = infraRadius(I, Rh: Rh)
                    var rot: CGFloat = 0
                    switch I.server.kind {
                    case .server: rot = I.server.state == .down ? 0 : -CGFloat(t) * .pi * 2 / 6        // the beams turn once in 6 s; a down pulsar stands still
                    case .deploy: rot = atan2(q.y - h.y, q.x - h.x)                                     // the tail points away from the hole
                    case .backup: rot = 0
                    }
                    var key = I.body
                    if I.server.kind == .deploy { key.opts["tail"] = "0" }
                    if I.server.kind == .backup { lit("infra-\(i)", key, at: q, radius: R, angle: Double(atan2(h.y - q.y, h.x - q.x)) * -1, z: 25, alpha: ia) }
                    else { body("infra-\(i)", key, at: q, radius: R, light: nil, z: 25, alpha: ia, add: true, rotation: rot) }
                    let hr = infraHex(I, R: R), st: SessionState? = I.server.state == .warn ? .waiting : I.server.state == .down ? .stuck : nil
                    if let st { stateMark("infra-mark-\(i)", at: q, r: hr, state: st, alpha: ia, tint: I.server.state == .warn ? Self.warn : nil) }
                    let sel = room && selectedInfra == I.server.id, selR = st != nil ? hr + 8 : hr
                    if sel { ring("infra-sel-\(i)", at: q, r: selR, alpha: ia, lw: 1.4, glow: true) }
                    tagQueue.append(TagReq(id: "infra-tag-\(i)", name: I.server.name.uppercased(), sub: "\(I.server.kind.rawValue.uppercased()) · \(I.server.state == .warn ? "WARNING" : I.server.state.rawValue.uppercased())",
                                           subColor: I.server.state == .down ? Self.stuckText : I.server.state == .warn ? Self.warn : Self.muted, anchor: q,
                                           r0: sel ? selR : st != nil ? hr + 4 : R, alpha: ia * ramp(s, eS * 0.62, eS * 0.87), pri: I.server.state == .down ? 34 : I.server.state == .warn ? 33 : 25,
                                           below: false, target: .infra(i)))
                    if ia > 0.5 { hits.append(Hit(x: q.x, y: q.y, r: max(10, R * 1.2 + 4), pri: 2, target: .infra(i), hr: selR, selected: sel)) }
                }
            }
            // the DevOps agent: a helper moon on a small orbit above the hole, lit while it runs, marked while it asks
            if let st = opsState {
                let a = CGFloat(t) * 0.05 + .pi / 2, q = CGPoint(x: h.x + cos(a) * 3.3 * Rh, y: h.y + sin(a) * 3.3 * Rh * 0.42), R = 0.12 * Rh
                lit("ops-moon", OrbitBodyKey(kind: "moon", id: "devops-agent", opts: ["type": "devops", "finished": st == .done ? "true" : "false"]),
                    at: q, radius: R, angle: Double(atan2(h.y - q.y, h.x - q.x)) * -1, z: 26, alpha: ia)
                let hr = hexR(R, 5)
                if st == .waiting || st == .stuck { stateMark("ops-mark", at: q, r: hr, state: st, alpha: ia) }
                let words = [SessionState.working: "RUNNING", .waiting: "WAITS ON YOU", .stuck: "STUCK", .done: "WATCHING"][st]!
                tagQueue.append(TagReq(id: "ops-tag", name: "DEVOPS AGENT", sub: words, subColor: stateColor(st), anchor: q, r0: hr + 4,
                                       alpha: ia * ramp(s, eS * 0.62, eS * 0.87), pri: st == .waiting ? 33 : 24, below: false, target: .ops))
                if ia > 0.5 { hits.append(Hit(x: q.x, y: q.y, r: max(10, R * 1.4 + 4), pri: 2, target: .ops, hr: hr, selected: false)) }
            }
            let lt = ramp(s, eS * 0.62, eS * 0.87)
            if lt > 0 {
                // below the outer orbit, so no body ever passes over it
                let y = h.y - (5.8 * 0.42 * Rh + 24)
                label("hole-room-name", "ENGINE ROOM", at: CGPoint(x: h.x, y: y), size: 10.5, color: Self.violet, alpha: lt, center: true)
                segments("hole-room-sub", summaryParts(short: false), at: CGPoint(x: h.x, y: y - 14), alpha: lt)
            }
        }
        hits.append(Hit(x: h.x, y: h.y, r: max(14, rr), pri: 1, target: .hole, hr: Rh * 1.25 + 6, selected: room))
    }

    /// The Engine room in one line, each part in its state's colour.
    private func summaryParts(short: Bool) -> [(String, SKColor)] {
        let m = summary
        guard m.connected else { return [(short ? "NOT CONNECTED" : "NO SERVERS CONNECTED", Self.muted)] }
        var parts: [(String, SKColor)] = []
        if !short || (m.warn == 0 && m.down == 0) { parts.append((short ? "\(m.total) ONLINE" : "\(m.ok) OK", Self.muted)) }
        if m.warn > 0 { parts.append(("\(m.warn) WARNING", Self.warn)) }
        if m.down > 0 { parts.append(("\(m.down) DOWN", Self.stuckText)) }
        return parts
    }

    static let wait = SKColor(red: 1, green: 0.847, blue: 0.239, alpha: 1)          // #FFD83D, Tuinstra yellow
    static let warn = SKColor(red: 1, green: 0.624, blue: 0.263, alpha: 1)          // #FF9F43, a server's warning
    static let stuck = SKColor(red: 1, green: 0.29, blue: 0.29, alpha: 1)           // #ff4a4a
    static let stuckText = SKColor(red: 0.941, green: 0.541, blue: 0.502, alpha: 1) // #f08a80
    static let cyan = SKColor(red: 0.31, green: 0.878, blue: 0.961, alpha: 1)       // #4fe0f5
    static let muted = SKColor(red: 0.612, green: 0.596, blue: 0.561, alpha: 1)     // #9c988f
    static let violet = SKColor(red: 0.725, green: 0.612, blue: 1, alpha: 1)        // #b99cff
    static let ink = SKColor(red: 0.949, green: 0.941, blue: 0.918, alpha: 1)       // #f2f0ea
    static let hair = SKColor(red: 0.922, green: 0.91, blue: 0.882, alpha: 1)       // rgb(235,232,225)
    static let backing = SKColor(red: 0.027, green: 0.027, blue: 0.047, alpha: 1)   // #07070c, the sky's own black
    static func roman(_ n: Int) -> String { ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"][min(max(n, 1), 12) - 1] }
    private func providerColor(_ p: Provider) -> SKColor { p == .claude ? SKColor(red: 0.91, green: 0.57, blue: 0.42, alpha: 1) : SKColor(red: 0.44, green: 0.83, blue: 0.72, alpha: 1) }
    private func stateColor(_ s: SessionState) -> SKColor { s == .waiting ? Self.wait : s == .stuck ? Self.stuckText : Self.muted }

    // MARK: bodies

    /// The image for a body at this size, if we have one (else the closest we have, scaled), and asks for a better one.
    private func texture(_ b: OrbitBodyKey, radius: CGFloat, light: Double?, cap: Int) -> (tex: SKTexture, size: CGSize)? {
        let rpx = radius * dpr, bucket = min(cap, Int(pow(2, ceil(log2(max(8, rpx))))))
        let base = b.key + "|" + (light.map { String(format: "%.2f", $0) } ?? "-")
        if textures[base]?.r != CGFloat(bucket) { request(base: base, body: b, r: bucket, light: light) }
        if b.opts["spin"] != nil { texUsed[base] = now }
        guard let tx = textures[base] else { return nil }
        let k = rpx / tx.r / dpr
        return (tx.tex, CGSize(width: tx.w * k, height: tx.h * k))
    }

    /// A body: the image of the right size step if we have it, else the closest we have, scaled.
    @discardableResult
    private func body(_ id: String, _ b: OrbitBodyKey, at p: CGPoint, radius: CGFloat, light: Double?, z: CGFloat, alpha: CGFloat = 1, cap: Int = 512, add: Bool = false, rotation: CGFloat = 0) -> Bool {
        guard let tx = texture(b, radius: radius, light: light, cap: cap) else { return false }
        let n = sprites[id] ?? { let n = SKSpriteNode(); layer.addChild(n); sprites[id] = n; return n }()
        used.insert(id); n.isHidden = false
        if n.texture !== tx.tex { n.texture = tx.tex }
        n.size = tx.size; n.zPosition = z; n.zRotation = rotation
        n.position = p; n.alpha = alpha; n.blendMode = add ? .add : .alpha
        return true
    }

    /// A lit body whose light turns smoothly: the two nearest of 24 light steps, the next one faded in over the first.
    /// With `turns` (how many turns on its axis it has made), the body also spins: the generator draws it per 1/40 turn,
    /// and the next step fades in over this one (the one after is asked for ahead, so a step never waits on its image).
    private func lit(_ id: String, _ b: OrbitBodyKey, at p: CGPoint, radius: CGFloat, angle: Double, z: CGFloat, alpha: CGFloat, turns: CGFloat? = nil) {
        let st = Double.pi * 2 / 24, f = angle / st, i0 = f.rounded(.down), w = CGFloat(f - i0)
        var b0 = b, b1: OrbitBodyKey?, v: CGFloat = 0
        if let turns {
            let n = CGFloat(Self.spinSteps), g = turns * n, j0 = g.rounded(.down), j = Int(j0) % Self.spinSteps
            v = g - j0
            func step(_ k: Int) -> OrbitBodyKey { var o = b; o.opts["spin"] = String(format: "%.4f", CGFloat((k % Self.spinSteps + Self.spinSteps) % Self.spinSteps) * .pi * 2 / n); return o }
            b0 = step(j); b1 = step(j + 1)
            // ahead: the next step in both lights
            if let b1 { _ = texture(b1, radius: radius, light: i0 * st, cap: 512); _ = texture(b1, radius: radius, light: (i0 + 1) * st, cap: 512) }
        }
        let drawn = body(id, b0, at: p, radius: radius, light: i0 * st, z: z, alpha: alpha)
        if w > 0.02 || !drawn { body(id + "~", b0, at: p, radius: radius, light: (i0 + 1) * st, z: z + 0.01, alpha: drawn ? alpha * w : alpha) }
        if let b1, v > 0.02 { body(id + "^", b1, at: p, radius: radius, light: (w < 0.5 ? i0 : i0 + 1) * st, z: z + 0.02, alpha: alpha * v) }
    }

    /// Steps per turn on a body's axis, and how long a turn takes: planets 2.5 min, moons 100 s (D18: slow, but alive).
    static let spinSteps = 40
    private static let planetDay: CGFloat = 150, moonDay: CGFloat = 100

    /// Drops the images of spin steps that have not been drawn for a while (each step is its own image).
    private func evictSpinTextures() {
        guard now - lastEvict > 5 else { return }
        lastEvict = now
        for (k, u) in texUsed where now - u > 8 { texUsed[k] = nil; textures[k] = nil }
    }

    /// A galaxy in three parts: what does not turn (halo, bulge), and its disk face on, tilted and turning in its own plane.
    private func galaxy(_ gi: Int, _ G: Galaxy, at g: CGPoint, radius gr: CGFloat, alpha: CGFloat) {
        var st = G.body; st.opts["layer"] = "static"
        var pl = G.body; pl.opts["layer"] = "plane"
        body("gal-\(gi)", st, at: g, radius: gr, light: nil, z: 0, alpha: alpha, cap: 512, add: true)
        guard let tx = texture(pl, radius: gr, light: nil, cap: 1024) else { return }
        let id = "gal-plane-\(gi)"
        let nodes = planes[id] ?? {
            let tilt = SKNode(), plane = SKSpriteNode()
            tilt.zPosition = 0; plane.blendMode = .add; tilt.addChild(plane); layer.addChild(tilt)
            planes[id] = (tilt, plane); return (tilt, plane)
        }()
        used.insert(id); nodes.tilt.isHidden = false
        nodes.tilt.position = g; nodes.tilt.zRotation = -G.pa * .pi / 180; nodes.tilt.yScale = cos(G.incl)
        if nodes.plane.texture !== tx.tex { nodes.plane.texture = tx.tex }
        nodes.plane.size = tx.size; nodes.plane.alpha = alpha
        // trailing arms: the disk turns against the way its arms wind outward
        nodes.plane.zRotation = G.sgn * Self.galaxyOmega * tg
    }

    private func request(base: String, body: OrbitBodyKey, r: Int, light: Double?) {
        let key = base + "|\(r)"
        guard !pending.contains(key) else { return }
        pending.insert(key)
        queue.append((key, base, body, r, light))
        pump()
    }

    private func pump() {
        guard let e = engine else { return }
        while inflight < 3, let job = queue.popLast() {
            inflight += 1
            Task { @MainActor in
                let img = await e.body(job.body, r: job.r, light: job.light)
                self.inflight -= 1
                self.pending.remove(job.key)
                if let img { self.textures[job.base] = (SKTexture(cgImage: img.image), CGFloat(job.r), CGFloat(img.image.width), CGFloat(img.image.height)); self.draw() }
                self.pump()
            }
        }
    }

    // MARK: marks, lines and text

    private func label(_ id: String, _ text: String, at p: CGPoint, size: CGFloat, color: SKColor, alpha: CGFloat, center: Bool = false, bold: Bool = true) {
        let n = labelNode(id, text, size: size, bold: bold)
        n.fontColor = color; n.alpha = alpha
        n.horizontalAlignmentMode = center ? .center : .left
        n.position = p
    }
    private func labelNode(_ id: String, _ text: String, size: CGFloat, bold: Bool) -> SKLabelNode {
        let n = labels[id] ?? { let n = SKLabelNode(); n.zPosition = 60; n.verticalAlignmentMode = .center; layer.addChild(n); labels[id] = n; return n }()
        used.insert(id); n.isHidden = false
        let font = bold ? "Menlo-Bold" : "Menlo-Regular"
        if n.fontName != font { n.fontName = font }
        if n.fontSize != size { n.fontSize = size }
        if n.text != text { n.text = text }
        return n
    }

    /// One line of 9 pt mono text in parts of different colours, centred on p.
    private func segments(_ id: String, _ parts: [(String, SKColor)], at p: CGPoint, alpha: CGFloat) {
        // " · " between the parts, in the colour of the part before it (a label drops leading spaces, so it trails)
        let parts = parts.enumerated().map { k, p in (k < parts.count - 1 ? p.0 + " · " : p.0, p.1) }
        let nodes = parts.enumerated().map { k, part -> SKLabelNode in
            let n = labelNode("\(id)-\(k)", part.0, size: 9, bold: false)
            n.fontColor = part.1; n.alpha = alpha; n.horizontalAlignmentMode = .left
            return n
        }
        // Menlo is monospaced: measure by characters (a label's frame drops leading spaces)
        let adv: CGFloat = 9 * 0.602
        var x = p.x - CGFloat(parts.reduce(0) { $0 + $1.0.count }) * adv / 2
        for (k, n) in nodes.enumerated() { n.position = CGPoint(x: x, y: p.y); x += CGFloat(parts[k].0.count) * adv }
    }

    /// The dark backing under a tag's text (#07070c at 50 %), so an orbit line or a galaxy arm never runs through it.
    private func pill(_ id: String, _ r: CGRect, alpha: CGFloat) {
        let bg = shape(id, z: 58)
        bg.path = CGPath(roundedRect: r.insetBy(dx: -5, dy: -2.5), cornerWidth: 4, cornerHeight: 4, transform: nil)
        bg.fillColor = Self.backing.withAlphaComponent(0.5 * alpha); bg.strokeColor = .clear; bg.lineWidth = 0; bg.glowWidth = 0
    }

    private func shape(_ id: String, z: CGFloat) -> SKShapeNode {
        let n = shapes[id] ?? { let n = SKShapeNode(); n.fillColor = .clear; n.isAntialiased = true; layer.addChild(n); shapes[id] = n; return n }()
        used.insert(id); n.isHidden = false; n.zPosition = z
        return n
    }

    private func ellipse(_ id: String, center: CGPoint, rx: CGFloat, ry: CGFloat, color: SKColor, rotation: CGFloat = 0, z: CGFloat = 10, lw: CGFloat = 1) {
        let n = shape(id, z: z)
        var tr = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
        n.path = CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &tr)
        n.strokeColor = color; n.lineWidth = lw; n.fillColor = .clear; n.glowWidth = 0
    }

    private func dot(_ id: String, at c: CGPoint, r: CGFloat, color: SKColor, z: CGFloat) {
        let n = shape(id, z: z)
        n.path = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
        n.fillColor = color; n.strokeColor = .clear; n.blendMode = .add
    }

    private func line(_ id: String, from a: CGPoint, to b: CGPoint, alpha: CGFloat) {
        let n = shape(id, z: 55), p = CGMutablePath(); p.move(to: a); p.addLine(to: b)
        n.path = p; n.strokeColor = Self.hair.withAlphaComponent(0.45 * alpha); n.lineWidth = 1; n.fillColor = .clear
    }

    /// A pointy-top hexagon as an open polyline that ends where it starts: never a closed subpath, since SpriteKit
    /// fills a closed path now and then even with a clear fill (it hid the moons inside a selected planet's mark).
    /// `gap`: a circle the line leaves out, so one mark can yield to another (a selected moon's ring over its planet's).
    private func hexPath(_ c: CGPoint, _ r: CGFloat, gap: (c: CGPoint, r: CGFloat)? = nil) -> CGMutablePath {
        let p = CGMutablePath()
        let v = (0...6).map { k -> CGPoint in let a = CGFloat(k % 6) * .pi / 3 + .pi / 6; return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r) }
        guard let g = gap else { p.addLines(between: v); return p }
        var pen: CGPoint?
        func seg(_ a: CGPoint, _ b: CGPoint) {
            if let q = pen, hypot(q.x - a.x, q.y - a.y) < 0.01 { p.addLine(to: b) } else { p.move(to: a); p.addLine(to: b) }
            pen = b
        }
        for k in 0..<6 {
            let a = v[k], b = v[k + 1], dx = b.x - a.x, dy = b.y - a.y, fx = a.x - g.c.x, fy = a.y - g.c.y
            let A = dx * dx + dy * dy, B = 2 * (fx * dx + fy * dy), C = fx * fx + fy * fy - g.r * g.r, D = B * B - 4 * A * C
            func at(_ t: CGFloat) -> CGPoint { CGPoint(x: a.x + dx * t, y: a.y + dy * t) }
            guard A > 0, D > 0 else { seg(a, b); continue }
            let t1 = (-B - D.squareRoot()) / (2 * A), t2 = (-B + D.squareRoot()) / (2 * A)
            if t1 > 0.001 { seg(a, at(min(1, t1))) }
            if t2 < 0.999 { seg(at(max(0, t2)), b) }
        }
        return p
    }

    /// State round a body, as on the board (D42): waiting is a dashed yellow hexagon that breathes, with a faint echo
    /// 4 pt out; stuck a red one that breathes faster, its echo, and a small red flag with a "!" on the upper right corner.
    /// `tint`: a server's warning draws the waiting hexagon in amber, not in the yellow of "waits for you" (D45)
    private func stateMark(_ id: String, at c: CGPoint, r: CGFloat, state: SessionState, alpha: CGFloat, gap: (c: CGPoint, r: CGFloat)? = nil, tint: SKColor? = nil) {
        let wait = state == .waiting, col = tint ?? (wait ? Self.wait : Self.stuck)
        let pulse = animationsEnabled ? 0.55 + 0.35 * sin(CGFloat(now) * (wait ? 1 / 0.9 : 1 / 0.5)) : (wait ? 0.85 : 0.9)
        let n = shape(id, z: 50), p = hexPath(c, r, gap: gap)
        n.path = wait ? p.copy(dashingWithPhase: CGFloat(now * 8), lengths: [4, 3]) : p
        n.strokeColor = col.withAlphaComponent(pulse * alpha); n.lineWidth = 1; n.fillColor = .clear; n.glowWidth = 0
        let e = shape(id + "-e", z: 50)
        e.path = hexPath(c, r + 4, gap: gap); e.strokeColor = col.withAlphaComponent((wait ? 0.22 : 0.3) * alpha); e.lineWidth = 1; e.fillColor = .clear; e.glowWidth = 0
        guard !wait else { return }
        let fx = c.x + r * 0.866, fy = c.y + r * 0.5
        let f = shape(id + "-f", z: 51)
        f.path = CGPath(rect: CGRect(x: fx + 2, y: fy, width: 9, height: 9), transform: nil); f.fillColor = Self.stuck.withAlphaComponent(alpha); f.strokeColor = .clear
        let i = shape(id + "-i", z: 52), ip = CGMutablePath()
        ip.addRect(CGRect(x: fx + 5.9, y: fy + 3.6, width: 1.4, height: 4)); ip.addRect(CGRect(x: fx + 5.9, y: fy + 1.3, width: 1.4, height: 1.3))
        i.path = ip; i.fillColor = SKColor(red: 0.1, green: 0.024, blue: 0.024, alpha: alpha); i.strokeColor = .clear
    }

    /// The cyan hexagon: the selection (with a soft glow), or at reduced strength the hover.
    private func ring(_ id: String, at c: CGPoint, r: CGFloat, alpha: CGFloat, lw: CGFloat, glow: Bool) {
        let n = shape(id, z: 50)
        n.path = hexPath(c, r); n.strokeColor = Self.cyan.withAlphaComponent(alpha); n.lineWidth = lw; n.fillColor = .clear
        n.glowWidth = glow ? 1.5 : 0
    }

    // MARK: hover

    /// The pointer moved: what is under it lights up the way a click there would pick it, and the cursor points.
    override func hover(at p: CGPoint?) {
        hoverPoint = p
        hoverTarget = pick(p)?.target
        setCursor(hoverTarget != nil)
        // with no frames running (reduced motion, a hidden window, a sleeping display) hover shows at once; and if no
        // frame comes in a moment after all, it shows then
        func settle() { hoverShown = hoverTarget; hoverK = hoverTarget == nil ? 0 : 1; draw() }
        guard frames else { settle(); return }
        let asked = CACurrentMediaTime()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.lastFrameWall < asked, self.view != nil else { return }
            settle()
        }
    }

    /// Exactly what click(at:) would pick there; nothing under a HUD panel.
    private func pick(_ p: CGPoint?) -> Hit? {
        guard let p, !underHUD(p) else { return nil }
        var best: Hit?
        for h in hits {
            let d = hypot(h.x - p.x, h.y - p.y)
            guard d <= h.r else { continue }
            if let b = best { let bd = hypot(b.x - p.x, b.y - p.y); if h.pri > b.pri || (h.pri == b.pri && d < bd) { best = h } } else { best = h }
        }
        return best
    }

    private var hudRects: [CGRect] {
        let W = size.width, H = size.height, r = hudRight(path.level)
        var out = [CGRect(x: -W / 2, y: H / 2 - bars.top, width: W, height: bars.top), CGRect(x: -W / 2, y: -H / 2, width: W, height: bars.bottom)]
        if insets.left > 0 { out.append(CGRect(x: -W / 2, y: -H / 2, width: insets.left - 12, height: H)) }
        if r > 0 { out.append(CGRect(x: W / 2 - r + 12, y: -H / 2, width: r - 12, height: H)) }
        return out
    }
    private func underHUD(_ p: CGPoint) -> Bool { hudRects.contains { $0.contains(p) } }

    /// The view shows a pointing hand while something clickable is under the pointer (WorldScene.hovering).
    private func setCursor(_ on: Bool) { if hovering != on { hovering = on } }

    public override func willMove(from view: SKView) {
        super.willMove(from: view)
        hoverPoint = nil; hoverTarget = nil; hoverShown = nil; hoverK = 0
        setCursor(false)
    }

    /// The hover mark: the selection's cyan hexagon at reduced strength, a thin ellipse in the galaxy's own plane, or round
    /// the hole's shadow. Bodies move under a still pointer, so it is picked again every frame.
    private func drawHover() {
        if hoverPoint != nil || hoverTarget != nil {
            let h = pick(hoverPoint)?.target
            if h != hoverTarget { hoverTarget = h; setCursor(h != nil) }
        }
        guard let target = hoverShown, hoverK > 0, let h = hits.first(where: { $0.target == target }), !h.selected else { return }
        let a = 1 - (1 - hoverK) * (1 - hoverK)
        if case .galaxy(let gi) = target {
            let G = galaxies[gi]
            ellipse("hover-gal", center: CGPoint(x: h.x, y: h.y), rx: h.hr, ry: h.hr * cos(G.incl), color: Self.cyan.withAlphaComponent(0.35 * a), rotation: -G.pa * .pi / 180, z: 50)
        } else {
            ring("hover", at: CGPoint(x: h.x, y: h.y), r: h.hr, alpha: 0.45 * a, lw: 1, glow: false)
        }
    }

    // MARK: tags

    /// Places the tags asked for this frame: the most important first (hovered, selected, then by state), each on the side
    /// it had before if it still fits, else flipped; one that fits nowhere fades out. Never under a HUD panel.
    private func placeTags() {
        let W = size.width, H = size.height
        // the HUD panels, and every small body's disc: a tag never prints over a planet, moon, star or server
        var taken = hudRects
        if let b = beaconRect { taken.append(b) }
        for h in hits { switch h.target { case .galaxy, .hole: continue; default: taken.append(CGRect(x: h.x - h.r, y: h.y - h.r, width: h.r * 2, height: h.r * 2)) } }
        let bounds = CGRect(x: -W / 2 + 4, y: -H / 2 + 4, width: W - 8, height: H - 8)
        func score(_ r: TagReq) -> CGFloat { r.pri + (r.target != nil && r.target == hoverTarget ? 1000 : 0) + (isSelected(r.target) ? 500 : 0) }
        // tags fade over 0.2 s; with no frames running (a still, a hidden window) they settle at once
        let fade = frames ? frameDT / 0.2 : 1
        for req in tagQueue.sorted(by: { score($0) > score($1) }) {
            let hovered = req.target != nil && req.target == hoverTarget
            let want = hovered ? 1 : req.alpha
            guard want > 0.01, abs(req.anchor.x) < W / 2 + 200, abs(req.anchor.y) < H / 2 + 100 else { tagVis[req.id] = 0; continue }
            let name = req.name.count > 40 ? String(req.name.prefix(39)) + "…" : req.name
            let nn = labelNode(req.id + "-n", name, size: 10.5, bold: true)
            let sn = req.sub.map { labelNode(req.id + "-s", $0, size: 9, bold: false) }
            let w = max(nn.frame.width, sn?.frame.width ?? 0), th: CGFloat = req.sub == nil ? 14 : 27
            var rect: CGRect?, right = true, dy: CGFloat = 0
            func cover(_ r: CGRect) -> CGFloat {
                taken.reduce(CGFloat(0)) { let i = $1.intersection(r); return $0 + (i.isNull ? 0 : i.width * i.height) } + (bounds.contains(r) ? 0 : 1e6)
            }
            if req.below {
                // under the body, centred; where a planet or the HUD is in the way above it, or a little to a side
                // (the place it had first while it still fits, so a tag does not hop while planets pass)
                let last = tagBelow[req.id] ?? 0
                var best: (CGFloat, CGRect, Int)?
                for k in [last] + (0..<6).filter({ $0 != last }) {
                    let r = belowRect(req, k, w: w, th: th), c = cover(r)
                    if c == 0 { rect = r; tagBelow[req.id] = k; break }
                    if best == nil || c < best!.0 { best = (c, r, k) }
                }
                if rect == nil, hovered || isSelected(req.target), let b = best { rect = b.1; tagBelow[req.id] = b.2 }
            } else {
                // beside the body, on the side it had (it keeps its place while it fits), else the other side, else a line up or down
                let last = tagSide[req.id] ?? true, lastDy = tagDy[req.id] ?? 0
                var tries: [(Bool, CGFloat)] = [(last, lastDy)]
                for d: CGFloat in [0, 15, -15, 30, -30] { for sd in [last, !last] where !(sd == last && d == lastDy) { tries.append((sd, d)) } }
                var best: (CGFloat, CGRect, Bool, CGFloat)?
                for (side, d) in tries {
                    let r = sideRect(req, side, d, w: w, th: th), c = cover(r)
                    if c == 0 { rect = r; right = side; dy = d; break }
                    if best == nil || c < best!.0 { best = (c, r, side, d) }
                }
                // the hovered or selected tag always shows: where it covers least
                if rect == nil, hovered || isSelected(req.target), let b = best { rect = b.1; right = b.2; dy = b.3 }
            }
            // nowhere free: the hovered or selected tag still shows (on its last side); the others fade out where they were
            let fits = rect != nil
            if rect == nil {
                right = tagSide[req.id] ?? true; dy = tagDy[req.id] ?? 0
                rect = req.below ? belowRect(req, tagBelow[req.id] ?? 0, w: w, th: th) : sideRect(req, right, dy, w: w, th: th)
            }
            let shows = fits || hovered || isSelected(req.target)
            let vis0 = tagVis[req.id] ?? (shows ? 1 : 0)
            let vis = !shows ? max(0, vis0 - fade) : (hovered ? 1 : min(1, vis0 + fade))
            tagVis[req.id] = vis
            guard let r = rect, vis > 0.01 else { nn.isHidden = true; sn?.isHidden = true; continue }
            if shows { taken.append(r.insetBy(dx: -6, dy: -3)); if !req.below { tagSide[req.id] = right; tagDy[req.id] = dy } }
            let a = want * vis
            nn.fontColor = Self.ink; nn.alpha = a
            // a dark backing, so an orbit line or a galaxy arm never runs through the text
            pill(req.id + "-bg", r, alpha: a)
            if req.below {
                nn.horizontalAlignmentMode = .center; nn.position = CGPoint(x: r.midX, y: r.maxY - 7)
                if let sn { sn.fontColor = req.subColor; sn.alpha = a; sn.horizontalAlignmentMode = .center; sn.position = CGPoint(x: r.midX, y: r.maxY - 20) }
            } else {
                nn.horizontalAlignmentMode = .left; sn?.horizontalAlignmentMode = .left
                // the name line's middle sits level with the body (shifted by dy), the sub line hangs under it
                let nameY = r.maxY - 7
                nn.position = CGPoint(x: r.minX, y: nameY)
                if let sn {
                    sn.fontColor = req.subColor; sn.alpha = a
                    // from the side the leader comes in
                    sn.position = CGPoint(x: right ? r.minX : r.maxX - sn.frame.width, y: nameY - 13)
                }
                if right { nn.position.x = r.minX } else { nn.position.x = r.maxX - nn.frame.width }
                // the leader runs to the middle of the name line, never to its baseline (it would read as "_ NAME")
                let x0 = req.anchor.x + (right ? 1 : -1) * (req.r0 + 2), x1 = right ? r.minX - 6 : r.maxX + 6
                if (x1 - x0) * (right ? 1 : -1) > 2 { line(req.id + "-l", from: CGPoint(x: x0, y: req.anchor.y), to: CGPoint(x: x1, y: nameY), alpha: a) }
            }
        }
    }

    /// A tag beside its body: the name line's middle at the body's height plus dy, on the right or the left.
    private func sideRect(_ req: TagReq, _ right: Bool, _ dy: CGFloat, w: CGFloat, th: CGFloat) -> CGRect {
        CGRect(x: right ? req.anchor.x + req.r0 + 14 : req.anchor.x - req.r0 - 14 - w, y: req.anchor.y + dy + 7 - th, width: w, height: th)
    }
    /// A centred tag's places: under the body, over it, then under or over it shifted to the left or the right.
    private func belowRect(_ req: TagReq, _ k: Int, w: CGFloat, th: CGFloat) -> CGRect {
        let under = req.anchor.y - req.r0 - th, over = req.anchor.y + req.r0 - 4, dx = w / 2 + 8
        let (x, y): (CGFloat, CGFloat) = [(0, under), (0, over), (-dx, under), (dx, under), (-dx, over), (dx, over)][min(max(k, 0), 5)]
        return CGRect(x: req.anchor.x + x - w / 2, y: y, width: w, height: th)
    }

    private func isSelected(_ t: Target?) -> Bool {
        guard let t else { return false }
        switch t {
        case .planet(let g, let s, let i): return path.level == .session && path.subAgentID == nil && galaxies[safe: g]?.systems[safe: s]?.planets[safe: i]?.session.id == path.sessionID
        case .moon(let g, let s, let i, let j): return galaxies[safe: g]?.systems[safe: s]?.planets[safe: i]?.moons[safe: j]?.sub.id == path.subAgentID
        case .infra(let i): return path.engineRoom && infra[safe: i]?.server.id == selectedInfra
        case .system(let g, let s): return path.level == .project && galaxies[safe: g]?.systems[safe: s]?.project.id == path.projectID
        default: return false
        }
    }

    // MARK: levels and selection

    /// The level follows the zoom, and the nearest body at that level is the selection (as the board's breadcrumb).
    private func updatePath() {
        let s = cs
        var p = OrbitPath()
        let c = CGPoint(x: cx + shift / cs, y: cy)
        func d(_ x: CGFloat, _ y: CGFloat) -> CGFloat { hypot(x - c.x, y - c.y) }
        if s >= FIT * 1.6 {
            if d(hole.x, hole.y) < hole.r * 5 { p.engineRoom = true; p.level = .provider; p.serverID = selectedInfra }
            else if let G = galaxies.min(by: { d($0.x, $0.y) < d($1.x, $1.y) }) {
                p.provider = G.provider; p.level = .provider
                if s >= 1.4, let S = G.systems.min(by: { d($0.x, $0.y) < d($1.x, $1.y) }) {
                    p.projectID = S.project.id; p.level = .project
                    if s >= 6, let (pi, P) = S.planets.enumerated().min(by: { let a = planetPos(S, $0.offset), b = planetPos(S, $1.offset); return d(a.x, a.y) < d(b.x, b.y) }) {
                        p.sessionID = P.session.id; p.level = .session
                        if s >= 30, !P.moons.isEmpty {
                            let q = planetPos(S, pi)
                            let mi = P.moons.indices.min { let a = moonPos((q.x, q.y), $0), b = moonPos((q.x, q.y), $1); return d(a.x, a.y) < d(b.x, b.y) }!
                            p.subAgentID = P.moons[mi].sub.id; p.level = .subAgent
                        }
                    }
                }
            }
        }
        if !p.engineRoom { selectedInfra = nil; p.serverID = nil }
        if p != path { path = p; onPath?(p) }
    }

    /// Where a body is now (it moves), and the zoom that shows its level: each level's zoom stays under the next level's
    /// threshold, so a flight lands on the level asked for (D24), framed in the part of the view the panels leave free.
    private func target(_ t: Target) -> (() -> CGPoint, CGFloat) {
        let clearW = max(size.width - insets.left - hudRight(.provider), size.width * 0.4), clearH = max(size.height - bars.top - bars.bottom, size.height * 0.5)
        let low = FIT * 1.7
        switch t {
        case .galaxy(let g):
            let G = galaxies[g], rmax = max(0.5, G.systems.map { hypot($0.px, $0.py) }.max() ?? 0.8) * G.r
            return ({ CGPoint(x: G.x, y: G.y) }, max(low, min(1.3, (clearW / 2 - 110) / rmax, (clearH / 2 - 60) / rmax)))
        case .hole:
            let Rh = max(24, min(68, (clearW / 2 - 150) / 5.8))
            return ({ [hole] in CGPoint(x: hole.x, y: hole.y) }, max(low, Rh / (hole.r * 0.5)))
        case .system(let g, let s):
            let n = CGFloat(galaxies[g].systems[s].planets.count), R = 10 + 6.5 * max(0, n - 1)
            return ({ [weak self] in self?.livePos(g, s) ?? .zero }, max(1.7, min(5.2, (clearW / 2 - 190) / R, (clearH / 2 - 40) / (R * 0.55 + 10))))
        case .planet(let g, let s, let i):
            let P = galaxies[g].systems[s].planets[i], m = min(clearW, clearH)
            return ({ [weak self] in
                guard let self, let S = self.galaxies[safe: g]?.systems[safe: s] else { return .zero }
                let q = self.planetPos(S, i); return CGPoint(x: q.x, y: q.y)
            }, P.moons.isEmpty ? 26 : min(26, m / ((2.8 + 1.1 * CGFloat(P.moons.count) + 2) * 2.8)))   // under 30: still the Session level
        case .moon(let g, let s, let i, let j):
            return ({ [weak self] in
                guard let self, let S = self.galaxies[safe: g]?.systems[safe: s] else { return .zero }
                let q = self.planetPos(S, i), mm = self.moonPos((q.x, q.y), j); return CGPoint(x: mm.x, y: mm.y)
            }, 180)
        case .infra, .ops:
            return ({ [hole] in CGPoint(x: hole.x, y: hole.y) }, cs)
        }
    }
    private func livePos(_ g: Int, _ s: Int) -> CGPoint? { galaxies[safe: g]?.systems[safe: s].map { CGPoint(x: $0.x, y: $0.y) } }

    private func go(_ t: Target) {
        if case .infra(let i) = t { selectedInfra = infra[safe: i]?.server.id; updatePath(); draw(); return }
        if t == .ops { selectedInfra = nil; if !path.engineRoom { let (g, sc) = target(.hole); fly(g, scale: sc) } else { updatePath(); draw() }; return }
        if t != .hole { selectedInfra = nil }
        let (g, sc) = target(t); fly(g, scale: sc)
    }

    /// Fly to a session's planet, or one of its moons.
    func fly(toSession id: String, subAgent: String? = nil) {
        for (gi, G) in galaxies.enumerated() { for (si, S) in G.systems.enumerated() { for (pi, P) in S.planets.enumerated() where P.session.id == id {
            if let a = subAgent, let mi = P.moons.firstIndex(where: { $0.sub.id == a }) { go(.moon(gi, si, pi, mi)) } else { go(.planet(gi, si, pi)) }
            return
        } } }
    }
    func fly(toProject id: String) {
        for (gi, G) in galaxies.enumerated() { if let si = G.systems.firstIndex(where: { $0.project.id == id }) { go(.system(gi, si)); return } }
    }
    /// Picks a server, deploy or backup round the black hole (from the HUD), flying there first; nil lets it go.
    func select(infra id: String?) {
        if !path.engineRoom { go(.hole) }
        selectedInfra = id.flatMap { i in infra.contains { $0.server.id == i } ? i : nil }
        updatePath(); draw()
    }

    func fly(toProvider key: String?) {
        if key == "engine" { go(.hole); return }
        guard let key, let gi = galaxies.firstIndex(where: { $0.provider.rawValue == key }) else { home(); return }
        go(.galaxy(gi))
    }

    public override func up() {
        let p = path
        if p.engineRoom, selectedInfra != nil { selectedInfra = nil; updatePath(); draw(); return }
        guard p.level != .all, !p.engineRoom, let prov = p.provider, let gi = galaxies.firstIndex(where: { $0.provider == prov }) else { home(); return }
        let G = galaxies[gi]
        if let sid = p.sessionID, p.subAgentID != nil, let si = G.systems.firstIndex(where: { $0.planets.contains { $0.session.id == sid } }),
           let pi = G.systems[si].planets.firstIndex(where: { $0.session.id == sid }) { go(.planet(gi, si, pi)); return }
        if p.sessionID != nil, let pid = p.projectID, let si = G.systems.firstIndex(where: { $0.project.id == pid }) { go(.system(gi, si)); return }
        if p.projectID != nil { go(.galaxy(gi)); return }
        home()
    }
    public override func next() { onNext?() }

    override func click(at p: CGPoint) {
        if let best = pick(p) { go(best.target) }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}



