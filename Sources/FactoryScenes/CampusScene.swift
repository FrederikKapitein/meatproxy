import SpriteKit
import FactoryCore

/// The campus (D22, D33) in blocky: a floating island with a tower per provider (a storey per project), the Server room,
/// the fountain that counts what waits for you, and people walking the roads. Every object is its own sprite, sorted by
/// depth. Level: All → Provider (a building) → into a storey, which opens the floor.
public final class CampusScene: WorldScene {
    var onFocus: ((String?) -> Void)?           // building key (claude, chatgpt, engine), or nil for the whole campus
    var onEnterFloor: ((String) -> Void)?       // project id
    var onNext: (() -> Void)?
    var onSelectSession: ((String) -> Void)?    // a walker: their floor, with them selected
    var onSelectServer: ((Int) -> Void)?        // a rack in the Server room: the server in that slot (rack order)
    /// what the pointer is on, as a title and a line, and where (view points from the top left); nil when nothing
    var onHoverTitle: ((HoverTitle?) -> Void)?
    var shownWorld: World = .empty
    /// how many racks hold a server, and the slot pulled out of one (rack index), with its parts
    private var rackCount = 0
    private var slot: Slot?

    /// How many of the team walk the roads.
    public static let walkerCount = 8
    /// The room the inspector takes on the right once a building is focused, in view points.
    static let inspectorRoom: CGFloat = 370

    /// What a click at a point would do, and so what lights up under the pointer (one hit test for both).
    enum Target: Equatable { case building(String), storey(String), fountain, walker(String), rack(Int) }

    var art: CampusArt?
    var buildings: [String: SKSpriteNode] = [:]
    /// per building: what is drawn over it and dims with it (rack LEDs, the beacon, waiting bands)
    var overlays: [String: SKNode] = [:]
    var storeys: [(storey: CampusArt.Storey, project: String)] = []
    private(set) var walkers: [String: Walker] = [:]
    private var skyNode: SKSpriteNode?
    var highlight: SKShapeNode?          // the storey you fly into
    var highlightID: String?
    private var focusMark: SKShapeNode?          // the focused building's footprint
    var hoverLayer: SKNode?
    var hoverTarget: Target?
    private var hoverRing: (node: SKShapeNode, walker: String)?
    /// shapes whose line stays the same width on screen at any zoom: (shape, points)
    private var screenLines: [(node: SKShapeNode, width: CGFloat)] = []
    private var leds: [(node: SKShapeNode, glow: SKSpriteNode, state: String, rack: Int, status: Bool)] = []
    private var beacon: (node: SKShapeNode, glow: SKSpriteNode)?
    private var worst: String?
    private var waitBands: [SKShapeNode] = []
    /// the towers' life (D62): windows that light up now and then, the antenna lamps, the chimneys of factories
    var windowLights: [(node: SKShapeNode, phase: Double, period: Double, peak: CGFloat, factory: String?)] = []
    private var antennaLamps: [(dot: SKShapeNode, glow: SKSpriteNode, phase: Double)] = []
    private var chimneys: [SKEmitterNode] = []
    private var fountainGlow: SKSpriteNode?
    /// the signs, each sorted with what it hangs on: owner is the building key for its roof sign and plaques
    var signs: [(node: SKSpriteNode, owner: String?, plaque: Bool, storey: Int?)] = []
    /// plaques of storeys that wait for you ("claude:0"): yellow, so they fade less when someone walks behind them
    private var waitingPlaques: Set<String> = []
    private var waiting = 0
    private var lastTime: TimeInterval = 0
    var clock: Double = 0
    private(set) var focus: String?
    /// 4A (D65): the towers that stand apart under the pointer, which one the pointer wants open, and the storey the
    /// wheel has marked (with where the pointer was then)
    var stacks: [String: TowerStack] = [:]
    var explodeWant: String?
    var explodeShut: String?
    /// a tower held apart without a pointer (window shots)
    public var pinnedApart: String?
    var wheelMark: (key: String, index: Int, at: CGPoint)?
    var wheelRest: CGFloat = 0
    /// where each sign sits with its tower together, to move it with its storey
    var signHome: [CGPoint] = []
    /// D66: the campus's life. effects outlives a repaint (a drone in the air); life is drawn anew with the state
    let effects = SKNode()
    var life = CampusLife()

    // colours (D24, one grammar): selection and hover cyan, waiting yellow, down red
    static let cyan = SKColor(red: 0.31, green: 0.88, blue: 0.96, alpha: 1)
    static let wait = SKColor(red: 1, green: 0.847, blue: 0.239, alpha: 1)
    /// a server warning: amber, not the yellow of "waits for you" (D45)
    static let warn = SKColor(red: 1, green: 0.624, blue: 0.263, alpha: 1)
    static let down = SKColor(red: 1, green: 0.29, blue: 0.29, alpha: 1)
    static let okGreen = SKColor(red: 0.49, green: 1, blue: 0.6, alpha: 1)
    static let activity = SKColor(red: 0.54, green: 0.71, blue: 1, alpha: 1)
    static let ink = SKColor(red: 0.16, green: 0.1, blue: 0.18, alpha: 1)
    static let night = SKColor(red: 0.09, green: 0.07, blue: 0.18, alpha: 1)

    // MARK: building the scene

    func apply(_ art: CampusArt, world: World, figures: [CastKey: Figure]) {
        let first = self.art == nil
        self.art = art
        shownWorld = world
        content.removeAllChildren(); buildings = [:]; overlays = [:]; highlight = nil; focusMark = nil
        hoverLayer = nil; hoverTarget = nil; hoverRing = nil; screenLines = []; leds = []; beacon = nil; waitBands = []; signs = []; waitingPlaques = []
        windowLights = []; antennaLamps = []; chimneys = []; stacks = [:]; life.reset()
        effects.removeFromParent(); effects.zPosition = 2990; content.addChild(effects)
        life.ground.removeFromParent(); life.ground.zPosition = -480; content.addChild(life.ground)
        if skyNode == nil {
            let s = SKSpriteNode(texture: Self.skyTexture); s.zPosition = -1000; cam.addChild(s); skyNode = s; sizeChanged()
        }
        if let g = place(art.ground, z: -500) { content.addChild(g) }
        var objectZ: [String: CGFloat] = [:]
        for o in art.objects {
            let n = place(o.texture, o.rect, z: o.key * 10, name: o.id)
            content.addChild(n)
            if let id = o.id { objectZ[id] = n.zPosition }
            if let id = o.id, id.hasPrefix("building:") {
                let key = String(id.dropFirst("building:".count))
                buildings[key] = n
                // the overlay sits in scene coordinates, as a child so it dims with the building
                let ov = SKNode(); ov.position = CGPoint(x: -n.position.x, y: -n.position.y); ov.zPosition = 0.2
                n.addChild(ov); overlays[key] = ov
            }
        }
        if let l = place(art.light, z: 3000, blend: .screen) { l.alpha = 0.9; l.name = "lamplight"; content.addChild(l) }
        // each sign just in front of what it hangs on (a building's roof sign and plaques, the Server room's board, the
        // plot's board, the fountain's count): people in front of a building pass in front of its plaques too
        for sg in art.signs {
            let parts = sg.id.split(separator: ":").map(String.init)
            let owner = parts.count > 1 ? parts[1] : nil
            let base = owner.map { "building:" + $0 } ?? sg.id
            // (+0.45: over the building's overlay, so a waiting band never runs across a plaque)
            guard let n = place(sg.image, z: (objectZ[base] ?? 3490) + 0.45) else { continue }
            content.addChild(n)
            let plaque = parts.first == "plaque"
            signs.append((n, owner, plaque, plaque && parts.count > 2 ? Int(parts[2]) : nil))
        }
        storeys = art.storeys.compactMap { st in
            guard let p = Provider(rawValue: st.building), let b = world.building(p), st.index < b.projects.count else { return nil }
            return (st, b.projects[st.index].id)
        }
        waiting = world.needsYou.count
        addWaitBands(world)
        addFountainGlow()
        addEngineLights(world)
        addTowerLife(world)
        buildStacks(world)
        signHome = signs.map { $0.node.position }
        updateLife(world)
        placeWalkers(figures, fresh: first)
        setHome(art.view.insetBy(dx: 30, dy: 0), fill: 0.98)  // dy 0: the tower roofs and signs stay in view
        if first { cam.setScale(homeScale); cam.position = homeCenter }
        applyFocus(animated: false)
        tick(0)
    }

    /// A sky from deep violet at the top to near black, behind everything and fixed to the camera.
    static let skyTexture: SKTexture = {
        let w = 8, h = 256, cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1), CGColor(red: 0.2, green: 0.16, blue: 0.36, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    /// A white radial dot, for glows: tint it with `color` and `colorBlendFactor = 1`, draw it with `.add`.
    static let glowTexture: SKTexture = {
        let n = 64, cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.35, 1])!
        let c = CGPoint(x: CGFloat(n) / 2, y: CGFloat(n) / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(n) / 2, options: [])
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    override func sizeChanged() {
        skyNode?.size = CGSize(width: size.width * 1.02, height: size.height * 1.02)
    }

    func shape(_ pts: [CGPoint], fill: SKColor, stroke: SKColor = .clear, width: CGFloat = 0) -> SKShapeNode {
        let path = CGMutablePath(); path.addLines(between: pts.map(scenePoint)); path.closeSubpath()
        let n = SKShapeNode(path: path); n.fillColor = fill; n.strokeColor = stroke; n.lineWidth = width; n.lineJoin = .miter
        return n
    }

    func glow(_ at: CGPoint, size: CGSize, color: SKColor) -> SKSpriteNode {
        let g = SKSpriteNode(texture: Self.glowTexture); g.size = CGSize(width: size.width * px, height: size.height * px)
        g.position = scenePoint(at); g.color = color; g.colorBlendFactor = 1; g.blendMode = .add
        return g
    }

    /// A storey that waits for you (D25): a yellow band across both of its faces, drawn in front of them, pulsing.
    private func addWaitBands(_ world: World) {
        for (st, id) in storeys {
            guard let p = world.project(id: id), p.waits(now: world.now),
                  let ov = overlays[st.building] else { continue }
            waitingPlaques.insert("\(st.building):\(st.index)")
            for face in st.faces where face.count == 4 {
                let a = face[0], b = face[1], lo: CGFloat = 3 * 1.08, hi: CGFloat = 6.4 * 1.08
                let band = shape([CGPoint(x: a.x, y: a.y - lo), CGPoint(x: b.x, y: b.y - lo), CGPoint(x: b.x, y: b.y - hi), CGPoint(x: a.x, y: a.y - hi)],
                                 fill: Self.wait, stroke: Self.ink, width: 0.7 * px)
                band.zPosition = 0.1
                (layer(st.building, storey: st.index) ?? ov).addChild(band); waitBands.append(band)
            }
        }
    }

    /// The fountain's warm glow, its own sprite so it can breathe (faster while something waits).
    private func addFountainGlow() {
        guard let art else { return }
        let g = glow(art.fountain, size: CGSize(width: 140, height: 77), color: Self.wait)
        g.zPosition = 3001; g.alpha = 0.25
        content.addChild(g); fountainGlow = g
    }

    /// The Server room's racks (D26): rack c is server c in rack order (problems first). The top LED says the state, the
    /// bottom one blinks with activity; a warning or a server down also lights the beacon on the roof. Nothing
    /// connected: every lens dark (the chip on the roof sign says "not connected").
    private func addEngineLights(_ world: World) {
        guard let art, let ov = overlays["engine"] else { return }
        let racks = world.racks
        rackCount = min(racks.count, 10)
        worst = world.serverSummary.worst?.rawValue
        for rack in art.racks where rack.c < racks.count && rack.pts.count == 4 {
            let st = racks[rack.c].state.rawValue, status = rack.r == 1
            let col = status ? (st == "down" ? Self.down : st == "warn" ? Self.warn : Self.okGreen) : Self.activity
            let led = shape(rack.pts, fill: col); led.zPosition = 0.2
            let c = CGPoint(x: rack.pts.map(\.x).reduce(0, +) / 4, y: rack.pts.map(\.y).reduce(0, +) / 4)
            let g = glow(c, size: CGSize(width: 7, height: 7), color: col); g.zPosition = 0.3
            ov.addChild(led); ov.addChild(g)
            leds.append((led, g, st, rack.c, status))
        }
        if let w = worst, w != "ok", art.beacon.count == 6 {
            let col = w == "down" ? Self.down : Self.wait, r: CGFloat = w == "down" ? 18 : 16
            let lens = shape(art.beacon, fill: col); lens.zPosition = 0.4
            let g = glow(art.beaconAt, size: CGSize(width: r * 2, height: r * 2), color: col); g.zPosition = 0.5
            ov.addChild(lens); ov.addChild(g)
            beacon = (lens, g)
        }
    }

    /// The towers come alive (D62). A few windows of each storey light up and dim again, slowly; more of them, and
    /// faster, where someone is at work. A factory's windows glow cool, like screens. Each antenna's lamp blinks red,
    /// and a tower where a factory works smokes from its chimney, more while one of its sessions is busy.
    private func addTowerLife(_ world: World) {
        guard let art else { return }
        let warm = SKColor(red: 1, green: 0.82, blue: 0.5, alpha: 1), cool = SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 1)
        var busyTowers: Set<String> = []
        for (st, id) in storeys {
            guard let ov = overlays[st.building], let p = world.project(id: id) else { continue }
            let busy = p.sessions.contains { $0.state(now: world.now) == .working }, factory = st.kind == "factory"
            if busy && factory { busyTowers.insert(st.building) }
            for (k, w) in st.windows.enumerated() where w.count == 4 {
                // a stable pick per window: about one in three (two in three when busy) take part
                let h = (st.index &* 31 &+ k &* 17 &+ (st.building == "claude" ? 0 : 7)) % 9
                guard h < (busy ? 6 : 3) else { continue }
                let n = shape(w, fill: factory ? cool : warm); n.blendMode = .add; n.zPosition = 0.05; n.alpha = 0
                (layer(st.building, storey: st.index) ?? ov).addChild(n)
                windowLights.append((n, Double(h) * 1.37 + Double(k) * 0.61, (busy ? 3.2 : 6.5) + Double(h % 3), factory ? 0.42 : 0.32, factory ? id : nil))
            }
        }
        for t in art.towers {
            guard let ov = layer(t.building, storey: nil) else { continue }
            let dot = SKShapeNode(circleOfRadius: 1.3 * px); dot.fillColor = Self.down; dot.strokeColor = .clear
            dot.position = scenePoint(t.antenna); dot.zPosition = 0.6
            let g = glow(t.antenna, size: CGSize(width: 14, height: 14), color: Self.down); g.zPosition = 0.61
            ov.addChild(dot); ov.addChild(g)
            antennaLamps.append((dot, g, t.building == "claude" ? 0 : 0.8))
            if let c = t.chimney {
                let e = Self.smoke(busy: busyTowers.contains(t.building), px: px)
                e.position = scenePoint(c); e.zPosition = 0.7; e.targetNode = ov
                ov.addChild(e); e.advanceSimulationTime(6)
                chimneys.append(e)
                explain(e, ("Smoke", "A factory works in this tower; it smokes more while one of its runs is busy"))
            }
        }
    }

    /// Soft grey puffs that rise, drift and fade: a factory at work.
    static func smoke(busy: Bool, px: CGFloat) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = glowTexture
        e.particleBirthRate = busy ? 5 : 2
        e.particleLifetime = 5; e.particleLifetimeRange = 1.5
        e.emissionAngle = .pi / 2; e.emissionAngleRange = 0.35
        e.particleSpeed = 9 * px; e.particleSpeedRange = 3 * px
        e.xAcceleration = 1.6 * px
        e.particleSize = CGSize(width: 9 * px, height: 9 * px)
        e.particleScale = 0.6; e.particleScaleSpeed = 0.28
        e.particleAlpha = busy ? 0.55 : 0.4; e.particleAlphaSpeed = -0.1
        e.particleColor = SKColor(white: 0.86, alpha: 1); e.particleColorBlendFactor = 1
        e.particlePositionRange = CGVector(dx: 2 * px, dy: 0)
        return e
    }

    // MARK: people on the roads

    /// One of the team out on the campus: from the end of one road round the fountain to the end of another, and a
    /// short rest there. Lanes are one way and axis-aligned (CampusRoads), the step cycle follows the distance walked.
    final class Walker {
        let key: String, session: String, figure: Figure
        let node = SKSpriteNode(), shadow = Blocky.shadow(18, 9, alpha: 0.25)
        var rng: SeededRandom
        var arm: Int, path: [CGPoint], pos: CGPoint, dir = "down"
        var walked: CGFloat = 0, idle: Double = 0, waited: Double = 0, crowdWait: Double = 0
        let speed: CGFloat
        init(key: String, session: String, figure: Figure, slot: Int) {
            self.key = key; self.session = session; self.figure = figure
            rng = SeededRandom(key)
            speed = rng.range(0.95, 1.25)
            arm = slot % CampusRoads.arms.count
            path = []; pos = CampusRoads.arms[arm].outEnd
        }
    }

    func placeWalkers(_ figures: [CastKey: Figure], fresh: Bool) {
        let list = figures.sorted { $0.key.key < $1.key.key }.prefix(Self.walkerCount)
        let keep = Set(list.map(\.key.key))
        for k in walkers.keys where !keep.contains(k) { walkers[k] = nil }
        for (slot, entry) in list.enumerated() {
            let w: Walker
            if let old = walkers[entry.key.key] { w = old } else {
                w = Walker(key: entry.key.key, session: entry.key.seed, figure: entry.value, slot: slot)
                // already under way, somewhere along a trip: on the road from the very first frame, and never on top of
                // someone already out there (a start closer than 0.8 tile is rolled again)
                for _ in 0..<24 {
                    newTrip(w)
                    let total = zip(w.path, w.path.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }.reduce(0, +)
                    walk(w, w.rng.range(0.05, 0.9) * total)
                    // apart on the roads and on screen (a lane runs towards you, so people 1.2 tiles apart can still
                    // stand half in front of each other)
                    if walkers.values.allSatisfy({ o in
                        let di = o.pos.x - w.pos.x, dj = o.pos.y - w.pos.y
                        return hypot(di, dj) >= Self.spawnGap && hypot((di - dj) * 16, (di + dj) * 8) >= 40
                    }) { break }
                }
                w.walked = w.rng.range(0, 1)
                walkers[w.key] = w
                if animationsEnabled && !fresh { w.node.alpha = 0; w.node.run(.fadeIn(withDuration: 0.3)) }
            }
            w.node.anchorPoint = CGPoint(x: 0, y: 1); w.node.name = "walker:" + w.session
            w.shadow.setScale(px / 2 * 1.1)
            content.addChild(w.shadow); content.addChild(w.node)
            place(w)
        }
    }

    private func newTrip(_ w: Walker) {
        let n = CampusRoads.arms.count
        let to = w.rng.next() < 0.75 ? (w.arm + 1 + Int(w.rng.next() * CGFloat(n - 1))) % n : w.arm
        w.path = CampusRoads.trip(from: w.arm, to: to)
        w.pos = w.path.removeFirst()
        w.arm = to
    }

    /// Moves a walker `d` tiles along their path.
    private func walk(_ w: Walker, _ d: CGFloat) {
        var left = d
        while left > 0, let next = w.path.first {
            let dx = next.x - w.pos.x, dy = next.y - w.pos.y, dist = hypot(dx, dy)
            if dist > 0.001 { w.dir = Facing.dir(dx, dy, current: w.dir) }
            let step = min(dist, left)
            w.walked += step
            if dist <= left { w.pos = next; w.path.removeFirst() } else { w.pos = CGPoint(x: w.pos.x + dx / dist * left, y: w.pos.y + dy / dist * left) }
            left -= step
        }
        if w.path.isEmpty {
            // at the end of a road: a rest, turned half towards you (long enough that the little roundabout round the
            // fountain never holds more than a few at once: eight on it at a time made a knot at its corners)
            // Someone already resting there: no rest, just a turn and off again, so a road end never collects a queue.
            let taken = walkers.values.contains { $0 !== w && $0.idle > 0 && hypot($0.pos.x - w.pos.x, $0.pos.y - w.pos.y) < 1.6 }
            w.idle = taken ? 0.4 : Double(w.rng.range(4, 9)); w.dir = Facing.front(of: w.dir)
        }
    }

    /// How far apart two walkers keep (tiles): anyone, someone followed on the same lane; how far off one gives way to
    /// another heading for the same corner; how close a new one may start to another.
    static let walkGap: CGFloat = 0.6, followGap: CGFloat = 1.0, yieldGap: CGFloat = 0.95, spawnGap: CGFloat = 1.0

    /// Whether w must wait. Everyone keeps `walkGap` from everyone, not only from who is ahead on the lane. A step that
    /// does not close the gap is always free (so whoever is in front can always walk away); one that would close it
    /// waits. Two who would both close in on each other (at a merge, or side by side after a corner) settle it by key:
    /// the one with the higher key waits.
    func blocked(_ w: Walker) -> Bool {
        guard let next = w.path.first else { return false }
        let d = CGPoint(x: next.x - w.pos.x, y: next.y - w.pos.y), len = hypot(d.x, d.y)
        let f = len > 0.001 ? CGPoint(x: d.x / len, y: d.y / len) : Facing.vector(w.dir)
        for o in walkers.values where o !== w {
            let v = CGPoint(x: o.pos.x - w.pos.x, y: o.pos.y - w.pos.y), dist = hypot(v.x, v.y)
            // on top of each other (a tie): the higher key waits until the other has moved on
            if dist < 0.05 { if w.key > o.key { return true }; continue }
            let along = v.x * f.x + v.y * f.y
            guard dist < max(Self.yieldGap, Self.followGap), along > 0.02 || Self.distanceAlong(w, to: o.pos) != nil else { continue }   // far, moving away or past: free
            // following someone along the way (round the next corner too): a whole step behind, so a queue reads as
            // people, not as a knot
            if let k = Self.distanceAlong(w, to: o.pos), k < Self.followGap { return true }
            // would o, walking on, close in on w too (two heading for the same corner)? Then the one further from the
            // corner gives way (the higher key on a tie), and early, so the other passes it a whole gap clear.
            if let on = o.path.first, o.idle <= 0 {
                let od = CGPoint(x: on.x - o.pos.x, y: on.y - o.pos.y), ol = hypot(od.x, od.y)
                if ol > 0.001, -(v.x * od.x + v.y * od.y) / ol > 0.02, !Self.passing(w.pos, f, o.pos, CGPoint(x: od.x / ol, y: od.y / ol)) {
                    let g = CGPoint(x: od.x / ol, y: od.y / ol)
                    var wFirst = w.key < o.key
                    // perpendicular: where the two lines cross, and how far each still has to go
                    if abs(f.x) > 0.5, abs(g.y) > 0.5 { let tw = (o.pos.x - w.pos.x) * f.x, to = (w.pos.y - o.pos.y) * g.y; if abs(tw - to) > 0.05 { wFirst = tw < to } }
                    if abs(f.y) > 0.5, abs(g.x) > 0.5 { let tw = (o.pos.y - w.pos.y) * f.y, to = (w.pos.x - o.pos.x) * g.x; if abs(tw - to) > 0.05 { wFirst = tw < to } }
                    if wFirst { continue }
                    return true
                }
            }
            if dist < Self.walkGap { return true }
        }
        return false
    }

    /// Whether w's next step takes it further over someone on screen. Whoever would walk further over someone waits; when
    /// both would, the higher key.
    func crowded(_ w: Walker) -> Bool {
        guard let next = w.path.first else { return false }
        let d = CGPoint(x: next.x - w.pos.x, y: next.y - w.pos.y), len = hypot(d.x, d.y)
        guard len > 0.001 else { return false }
        let f = CGPoint(x: d.x / len, y: d.y / len)
        for o in walkers.values where o !== w && crowdsOnScreen(w, o, along: f) {
            guard let on = o.path.first, o.idle <= 0 else { return true }
            let od = CGPoint(x: on.x - o.pos.x, y: on.y - o.pos.y), ol = hypot(od.x, od.y)
            if ol > 0.001, Self.passing(w.pos, f, o.pos, CGPoint(x: od.x / ol, y: od.y / ol)) { continue }   // passing by: fine
            if ol < 0.001 || !crowdsOnScreen(o, w, along: CGPoint(x: od.x / ol, y: od.y / ol)) || w.key > o.key { return true }
        }
        return false
    }

    /// Two on the two lanes of one road, walking opposite ways: they pass each other, neither waits for the other.
    static func passing(_ a: CGPoint, _ f: CGPoint, _ b: CGPoint, _ g: CGPoint) -> Bool {
        guard f.x * g.x + f.y * g.y < -0.9 else { return false }
        let v = CGPoint(x: b.x - a.x, y: b.y - a.y)
        return abs(v.x * f.y - v.y * f.x) > 0.5     // side by side, a lane apart
    }

    /// How far w still walks along its way before it reaches p (when p lies on that way, within 0.3 tile of it), up to
    /// the follow gap; nil when p is not on the next stretch of w's way.
    static func distanceAlong(_ w: Walker, to p: CGPoint) -> CGFloat? {
        var at = w.pos, done: CGFloat = 0
        for q in w.path {
            let d = CGPoint(x: q.x - at.x, y: q.y - at.y), len = hypot(d.x, d.y)
            if len > 0.001 {
                let t = ((p.x - at.x) * d.x + (p.y - at.y) * d.y) / len, side = abs((p.x - at.x) * d.y - (p.y - at.y) * d.x) / len
                if t > 0.02, t <= len + 0.3, side < 0.3 { return done + t }
                done += len
            }
            if done > followGap { return nil }
            at = q
        }
        return nil
    }

    /// Someone closer than the gap ahead of w, or in the queue in front of it: then it does not push on after a long wait.
    private func touching(_ w: Walker) -> Bool {
        guard let next = w.path.first else { return false }
        let d = CGPoint(x: next.x - w.pos.x, y: next.y - w.pos.y)
        return walkers.values.contains { o in
            guard o !== w else { return false }
            let v = CGPoint(x: o.pos.x - w.pos.x, y: o.pos.y - w.pos.y)
            return (hypot(v.x, v.y) < Self.walkGap && v.x * d.x + v.y * d.y > 0) || (Self.distanceAlong(w, to: o.pos).map { $0 < Self.followGap } ?? false)
        }
    }

    /// A walker's body as you see it, in scene points: about shoulder wide and head to feet (the sprite's box has an
    /// empty margin round the figure).
    func bodyRect(_ w: Walker) -> CGRect {
        let foot = scenePoint(project(w.pos.x, w.pos.y))
        return CGRect(x: foot.x - Self.body.width / 2 * px, y: foot.y, width: Self.body.width * px, height: Self.body.height * px)
    }
    /// The body's size on screen (art units).
    static let body = CGSize(width: 12, height: 32)

    /// Whether a step of w along f brings it further over someone on screen: their bodies already overlap by more than
    /// about a third, and the step makes it worse. On a lane that runs towards you a whole tile is only a few units on
    /// screen, so the gaps on the ground do not keep people apart there.
    func crowdsOnScreen(_ w: Walker, _ o: Walker, along f: CGPoint) -> Bool {
        let a = project(w.pos.x, w.pos.y), b = project(o.pos.x, o.pos.y)
        let sx = Self.body.width * 0.9, sy = Self.body.height * 0.7
        guard abs(a.x - b.x) < sx, abs(a.y - b.y) < sy else { return false }
        let n = project(w.pos.x + f.x * 0.05, w.pos.y + f.y * 0.05)
        let d0 = hypot((a.x - b.x) / sx, (a.y - b.y) / sy), d1 = hypot((n.x - b.x) / sx, (n.y - b.y) / sy)
        return d1 < d0 - 0.0001
    }

    /// Where a walker is drawn: their frame for the side they walk to, depth from where they stand.
    private func place(_ w: Walker) {
        guard let art else { return }
        let moving = w.idle <= 0 && !w.path.isEmpty
        let pose = moving && animationsEnabled ? StepCycle.pose(distance: w.walked) : "idle"
        guard let f = w.figure.frame(pose, mood: "calm", dir: w.dir) else { return }
        let foot = project(w.pos.x, w.pos.y)
        w.node.texture = f.texture
        w.node.size = CGSize(width: f.rect.width * px, height: f.rect.height * px)
        w.node.position = scenePoint(CGPoint(x: foot.x + f.rect.minX, y: foot.y + f.rect.minY))
        // two people in front of the same box get the same key: the one nearer you (larger i + j) still goes in front,
        // never one drawn through the other
        w.node.zPosition = depthKey(w.pos.x, w.pos.y, boxes: art.boxes) * 10 + 0.5 + (w.pos.x + w.pos.y) * 0.001
        w.shadow.position = scenePoint(foot); w.shadow.zPosition = w.node.zPosition - 0.2
    }

    public override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, currentTime - lastTime); lastTime = currentTime
        tick(dt)
    }

    func tick(_ dt: Double) {
        if animationsEnabled {
            clock += dt
            // in a fixed order: who moves first decides who waits, so the walk is the same on every machine and run
            for w in walkers.values.sorted(by: { $0.key < $1.key }) {
                if w.idle > 0 {
                    // resting at the end of the road while someone comes up behind: up and off, so nobody queues there
                    if w.idle > 0.3, walkers.values.contains(where: { o in o !== w && o.idle <= 0 && Self.distanceAlong(o, to: w.pos) != nil }) { w.idle = 0.3 }
                    w.idle -= dt
                    if w.idle <= 0 { newTrip(w) }
                } else if !w.path.isEmpty {
                    // wait while someone is in the way; after a long wait (a knot of three at a merge) walk on, but not
                    // into someone within touching distance (only a knot that has not loosened in 12 s is let go)
                    // and keep apart on screen: a short wait while walking on would take them over someone, then on
                    // anyway (passing in front of someone is fine; walking glued to them is not)
                    if blocked(w), w.waited < 4 || (touching(w) && w.waited < 12) { w.waited += dt }
                    else if crowded(w), w.crowdWait < 0.8 { w.crowdWait += dt }
                    else {
                        w.waited = 0
                        if w.crowdWait < 0.8 || !crowded(w) { w.crowdWait = 0 }
                        walk(w, CGFloat(dt) * w.speed)
                    }
                }
                place(w)
            }
        } else {
            for w in walkers.values { place(w) }
        }
        tickStacks(dt)
        tickLife(dt)
        // close up, the storey plaques keep about their size on screen instead of filling the view
        let k = max(0.5, min(1, cam.xScale / max(homeScale, 0.0001)))
        for sg in signs where sg.plaque && abs(sg.node.xScale - k) > 0.005 { sg.node.setScale(k) }
        animateLights()
        fadePlaques(dt)
        for l in screenLines { l.node.lineWidth = screenWidth(l.width) }
        if let r = hoverRing, let w = walkers[r.walker] {
            r.node.position = scenePoint(project(w.pos.x, w.pos.y)); r.node.zPosition = w.node.zPosition - 0.1
        }
        // things move under a still pointer: look again every frame (not while the camera flies)
        refreshHover()
    }

    /// A plaque sticks out from its tower into the open: where someone walks behind one so that it hides a good part of
    /// them, it fades so you see them. Measured on the body as you see it (head to feet, shoulder wide), not on the
    /// sprite's box with its empty margin; a yellow plaque (it waits for you) stays readable.
    private func fadePlaques(_ dt: Double) {
        for sg in signs where sg.plaque {
            let f = sg.node.frame.insetBy(dx: 1 * px, dy: 1 * px)
            let behind = walkers.values.contains { w in
                guard w.node.zPosition < sg.node.zPosition, w.node.alpha > 0.1 else { return false }
                let body = bodyRect(w), x = body.intersection(f)
                return !x.isNull && x.width * x.height > 0.3 * body.width * body.height
            }
            let waits = sg.owner.flatMap { o in sg.storey.map { waitingPlaques.contains("\(o):\($0)") } } ?? false
            let target: CGFloat = behind ? (waits ? 0.8 : 0.55) : 1
            sg.node.alpha = animationsEnabled && dt > 0 ? sg.node.alpha + (target - sg.node.alpha) * CGFloat(min(1, dt * 8)) : target
        }
    }

    /// The rack LEDs, the beacon, the waiting bands and the fountain, all from one clock; a still frame (no
    /// animations) shows every light on, so it still says the state.
    private func animateLights() {
        let t = clock, on = animationsEnabled
        for l in leds {
            // a deploy on its way (5F): the activity lights answer, three times as fast
            let a = l.status ? RackLights.status(l.state, rack: l.rack, t: t, animated: on) : RackLights.activity(l.state, rack: l.rack, t: life.streaming ? t * 3 : t, animated: on)
            l.node.alpha = a; l.glow.alpha = 0.35 * a
            l.node.isHidden = a <= 0.01; l.glow.isHidden = a <= 0.01
        }
        if let b = beacon {
            let a = RackLights.beacon(worst, t: t, animated: on)
            b.node.alpha = a; b.glow.alpha = (worst == "down" ? 0.55 : 0.5) * a
        }
        let band = on ? CGFloat(0.775 + 0.225 * sin(t / 1.4 * 2 * .pi)) : 1
        for n in waitBands { n.alpha = band }
        for w in windowLights {
            // a slow swell: off most of the time, on for a while; a still frame shows them half lit
            let v = on ? max(0, sin((t / w.period + w.phase) * 2 * .pi)) : 0.5
            // brighter at night (5A); a factory in its quiet hours sleeps, its screens low
            let night = 1 + 1.4 * (1 - life.daylight), sleep: CGFloat = w.factory.map { life.sleeping.contains($0) } == true ? 0.3 : 1
            w.node.alpha = w.peak * CGFloat(v * v) * night * sleep
        }
        for l in antennaLamps {
            let lit = !on || (t + l.phase).truncatingRemainder(dividingBy: 1.8) < 0.35
            l.dot.alpha = lit ? 1 : 0.25; l.glow.alpha = lit ? 0.6 : 0
        }
        for c in chimneys { c.isPaused = !on }
        if let g = fountainGlow {
            let period = waiting > 0 ? 1.6 : 2.4
            g.alpha = on ? CGFloat(0.25 + 0.07 * sin(t / period * 2 * .pi)) : 0.25
        }
    }

    // MARK: levels

    func focus(on key: String?, animated: Bool = true) {
        focus = key
        applyFocus(animated: animated)
        if let key, let r = focusRect(key) { flyClear(r, padding: 1.2, right: Self.inspectorRoom) } else if animated { goHome() }
    }

    /// A building with its storey plaques, in scene coordinates: what the camera frames at the Provider level.
    private func focusRect(_ key: String) -> CGRect? {
        guard let n = buildings[key] else { return nil }
        var r = n.calculateAccumulatedFrame()
        for p in art?.plaques[key] ?? [] { r = r.union(CGRect(x: p.minX * px, y: -p.maxY * px, width: p.width * px, height: p.height * px)) }
        return r
    }

    /// Fly to a storey of its building, then hand over to the floor scene.
    func flyIntoFloor(_ id: String, then done: @escaping () -> Void) {
        guard let s = storeys.first(where: { $0.project == id }) else { done(); return }
        if focus != s.storey.building { focus = s.storey.building; applyFocus(animated: true) }
        showHighlight(s.storey); highlightID = id
        clearHover()
        let pts = s.storey.faces.flatMap { $0 }.map(scenePoint)
        let r = CGRect(x: pts.map(\.x).min()!, y: pts.map(\.y).min()!, width: pts.map(\.x).max()! - pts.map(\.x).min()!, height: pts.map(\.y).max()! - pts.map(\.y).min()!)
        flyClear(r, padding: 1.6, right: Self.inspectorRoom, completion: done)
    }

    /// The focused building stands out; the others dim (a colour blend toward the night, so nothing shows through them).
    private func applyFocus(animated: Bool) {
        for (k, n) in buildings { setDim(k, n, focus != nil && focus != k ? 0.55 : 0, animated: animated) }
        focusMark?.removeFromParent(); focusMark = nil
        screenLines.removeAll { $0.node.parent == nil }
        if let key = focus, let fp = art?.footprints["building:" + key] {
            let m = footprint(fp, outset: 0.5, fill: 0.12, stroke: 1, width: 2)
            content.addChild(m); focusMark = m
        }
        if focus == nil { highlight?.removeFromParent(); highlight = nil; highlightID = nil }
        if case .building(let k)? = hoverTarget, k == focus { clearHover() }
    }

    private func setDim(_ key: String, _ n: SKSpriteNode, _ f: CGFloat, animated: Bool) {
        let ov = overlays[key], a: CGFloat = f > 0 ? 1 - f * 0.9 : 1
        // the building's signs take the same colour blend as the building
        let nodes = [n] + signs.filter { $0.owner == key }.map(\.node)
        for m in nodes { m.color = Self.night }
        if animated && animationsEnabled {
            for m in nodes { m.run(.colorize(with: Self.night, colorBlendFactor: f, duration: 0.3), withKey: "dim") }
            ov?.run(.fadeAlpha(to: a, duration: 0.3))
        } else { for m in nodes { m.removeAction(forKey: "dim"); m.colorBlendFactor = f }; ov?.alpha = a }
    }

    /// The diamond round a footprint (tiles) on the ground, under every object: an RTS-style selection.
    private func footprint(_ r: CGRect, outset: CGFloat, fill: CGFloat, stroke: CGFloat, width: CGFloat) -> SKShapeNode {
        let a = r.insetBy(dx: -outset, dy: -outset)
        let n = shape([project(a.minX, a.minY), project(a.maxX, a.minY), project(a.maxX, a.maxY), project(a.minX, a.maxY)],
                      fill: Self.cyan.withAlphaComponent(fill), stroke: Self.cyan.withAlphaComponent(stroke), width: screenWidth(width))
        n.zPosition = -490
        screenLines.append((n, width))
        return n
    }

    /// The outline of a storey's two faces as one shape (six corners), with the shared corner edge fainter.
    private func storeyOutline(_ s: CampusArt.Storey, fill: CGFloat, stroke: CGFloat, width: CGFloat) -> SKShapeNode {
        let f0 = s.faces[0], f1 = s.faces.count > 1 ? s.faces[1] : s.faces[0]
        let n = shape([f0[0], f0[1], f1[1], f1[2], f0[2], f0[3]], fill: Self.cyan.withAlphaComponent(fill), stroke: Self.cyan.withAlphaComponent(stroke), width: screenWidth(width))
        // over its building, under the building's plaques (so the outline never runs across a name)
        n.zPosition = (buildings[s.building]?.zPosition ?? 3590) + 0.4
        let path = CGMutablePath(); path.addLines(between: [f0[1], f0[2]].map(scenePoint))
        let edge = SKShapeNode(path: path); edge.strokeColor = Self.cyan.withAlphaComponent(0.4); edge.lineWidth = screenWidth(width * 0.7)
        n.addChild(edge)
        screenLines.append((n, width)); screenLines.append((edge, width * 0.7))
        return n
    }

    private func showHighlight(_ s: CampusArt.Storey) {
        highlight?.removeFromParent()
        let n = storeyOutline(s, fill: 0.18, stroke: 1, width: 2)
        content.addChild(n); highlight = n
    }

    override func wheel(_ dy: CGFloat, precise: Bool) -> Bool { stackWheel(dy, precise: precise) }
    /// A right-click picks what a click would, but a storey counts even on a building you have not opened (D72).
    override func contextTarget(at p: CGPoint) -> ContextTarget? {
        let a = artPoint(p)
        if let s = storeys.first(where: { storeyHit($0.storey, a) }) { return .project(s.project) }
        switch target(at: p) {
        case .building(let k)?: return .building(k)
        case .storey(let id)?: return .project(id)
        case .walker(let id)?: return .session(id)
        case .rack(let c)?: return .server(c)
        case .fountain?: return .fountain
        case nil: return nil
        }
    }
    public override func up() {
        if closeStacks() { return }
        if focus != nil { focus(on: nil); onFocus?(nil) }
    }
    public override func next() { onNext?() }

    // MARK: input

    /// The one hit test: what a click at p picks.
    func target(at p: CGPoint) -> Target? {
        let a = artPoint(p)
        // a rack with a server in it (its whole panel behind the glass)
        if let c = (0..<rackCount).first(where: { contains(Self.rackPanel($0), a) }) { return .rack(c) }
        // a storey's plaque is its storey (on the campus overview: its building), in front of everything it hangs on
        if let sg = signs.filter({ $0.plaque && $0.storey != nil && $0.node.alpha > 0.3 && $0.node.frame.contains(p) }).max(by: { $0.node.zPosition < $1.node.zPosition }),
           let key = sg.owner, let s = storeys.first(where: { $0.storey.building == key && $0.storey.index == sg.storey }) {
            let w = walkers.values.filter { $0.node.alpha > 0.5 && $0.node.zPosition > sg.node.zPosition && bodyRect($0).contains(p) }
            if w.isEmpty { return focus == key || isApart(key) ? .storey(s.project) : .building(key) }
        }
        // a walker in front of whatever is behind them
        let walker = walkers.values.filter { $0.node.alpha > 0.5 && $0.node.contains(p) }.max { $0.node.zPosition < $1.node.zPosition }
        let building = buildings.filter { silhouette($0.key)?.contains(a) ?? $0.value.contains(p) }.max { $0.value.zPosition < $1.value.zPosition }
        if let w = walker, (building?.value.zPosition ?? -.infinity) < w.node.zPosition { return .walker(w.session) }
        // a storey of the focused building (or of any building, when you point right at it)
        if let s = storeys.filter({ storeyHit($0.storey, a) }).first(where: { focus == nil || $0.storey.building == focus || isApart($0.storey.building) })
            ?? storeys.first(where: { isApart($0.storey.building) && cutHit($0.storey, a) }) {
            return focus == s.storey.building || isApart(s.storey.building) ? .storey(s.project) : .building(s.storey.building)
        }
        if let (key, _) = building {
            if key == focus, let s = storeys.filter({ $0.storey.building == key }).min(by: { centerDistance($0.storey, a) < centerDistance($1.storey, a) }) { return .storey(s.project) }
            return .building(key)
        }
        // the fountain: its basin on the ground and the statue standing up out of it, as you see them
        if let fp = art?.footprints["fountain"], contains(diamond(fp.insetBy(dx: -0.2, dy: -0.2)), a)
            || (art?.hits["fountain"] ?? []).contains(where: { contains(boxOutline($0.rect, height: $0.height), a) }) { return .fountain }
        if let w = walker { return .walker(w.session) }
        return nil
    }

    override func click(at p: CGPoint) {
        // the storey the wheel marked opens, wherever in the stack the pointer is
        if wheelMark != nil, case .storey(let id)? = hoverTarget { onEnterFloor?(id); return }
        switch target(at: p) {
        case .walker(let id)?: onSelectSession?(id)
        case .storey(let id)?: onEnterFloor?(id)
        case .building(let key)?: focus(on: key); onFocus?(key)
        case .fountain?: onNext?()
        case .rack(let c)?: onSelectServer?(c)
        case nil: if focus != nil { focus(on: nil); onFocus?(nil) }
        }
    }

    /// Hover is a pre-selection (cyan, lighter than the selection): exactly what a click would pick, nothing while the
    /// camera flies, nothing on what is already selected.
    override func hover(at p: CGPoint?) {
        var t = p.flatMap(target(at:))
        if cam.hasActions() { t = nil }
        wantApart(t, at: p)
        // the wheel's mark holds until the pointer moves on
        if let m = wheelMark {
            if let q = pointer, hypot(q.x - m.at.x, q.y - m.at.y) > 4 { wheelMark = nil }
            else if stacks[m.key]?.target == 1, let s = storeys.first(where: { $0.storey.building == m.key && $0.storey.index == m.index }) { t = .storey(s.project) }
            else { wheelMark = nil }
        }
        if case .building(let k)? = t, k == focus { t = nil }
        if case .storey(let id)? = t, highlight != nil, id == highlightID { t = nil }
        hovering = p.flatMap(target(at:)) != nil && !cam.hasActions()
        // the title follows the pointer even over what is already picked (the outline does not)
        let titled = cam.hasActions() ? nil : (wheelMark != nil ? t : p.flatMap(target(at:)))
        // what an effect means comes first (D74): an alarm light, the lift, a drone, a lamp of the Status layer
        if !cam.hasActions(), wheelMark == nil, let p, let v = view, let hs = hotspot(at: p) {
            let q = convertPoint(toView: p)
            onHoverTitle?(HoverTitle(title: hs.0, line: hs.1, at: CGPoint(x: q.x, y: v.bounds.height - q.y), left: false))
        }
        // a marked storey's line hangs by its plaque, like a label (4A); otherwise it follows the pointer
        else if let titled, let v = view, let words = title(for: titled),
           let at = markLabelPoint() ?? p.map({ q -> CGPoint in let q = convertPoint(toView: q); return CGPoint(x: q.x, y: v.bounds.height - q.y) }) {
            var left = false
            switch titled { case .storey, .building: left = true; default: break }
            onHoverTitle?(HoverTitle(title: words.0, line: words.1, at: at, left: left))
        } else { onHoverTitle?(nil) }
        guard t != hoverTarget else { return }
        let had = hoverTarget != nil
        hoverTarget = t
        if let old = hoverLayer {
            hoverLayer = nil; hoverRing = nil
            if t == nil { old.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()])) } else { old.removeFromParent() }
        }
        for (k, n) in buildings where focus != nil && focus != k {
            let f: CGFloat = (t == .building(k)) ? 0.3 : 0.55
            n.colorBlendFactor = f
            for sg in signs where sg.owner == k { sg.node.colorBlendFactor = f }
        }
        guard let t else { return }
        let layer = SKNode()
        switch t {
        case .building(let key):
            if let fp = art?.footprints["building:" + key] { layer.addChild(footprint(fp, outset: 0.5, fill: 0.1, stroke: 0.9, width: 1.5)) }
            if let b = buildings[key], !isApart(key) {
                let lift = SKSpriteNode(texture: b.texture); lift.anchorPoint = b.anchorPoint; lift.size = b.size; lift.position = b.position
                lift.blendMode = .add; lift.alpha = 0.16; lift.zPosition = b.zPosition + 0.1
                layer.addChild(lift)
            }
        case .storey(let id):
            if let s = storeys.first(where: { $0.project == id }) { layer.addChild(storeyOutline(s.storey, fill: 0.15, stroke: 0.95, width: 2)) }
        case .fountain:
            if let fp = art?.footprints["fountain"] { layer.addChild(footprint(fp, outset: 0.3, fill: 0.1, stroke: 0.9, width: 1.5)) }
            // the basin and the statue light up, as a building does
            if let b = content.childNode(withName: "fountain") as? SKSpriteNode {
                let lift = SKSpriteNode(texture: b.texture); lift.anchorPoint = b.anchorPoint; lift.size = b.size; lift.position = b.position
                lift.blendMode = .add; lift.alpha = 0.2; lift.zPosition = b.zPosition + 0.1
                layer.addChild(lift)
            }
        case .rack(let c):
            let n = shape(Self.rackPanel(c), fill: Self.cyan.withAlphaComponent(0.12), stroke: Self.cyan.withAlphaComponent(0.9), width: px)
            n.zPosition = (buildings["engine"]?.zPosition ?? 0) + 0.6
            layer.addChild(n)
        case .walker(let id):
            if let w = walkers.values.first(where: { $0.session == id }) {
                let r = Blocky.ring(24 * px, 12 * px, color: Self.cyan.withAlphaComponent(0.85), lineWidth: px)
                r.position = scenePoint(project(w.pos.x, w.pos.y)); r.zPosition = w.node.zPosition - 0.1
                layer.addChild(r); hoverRing = (r, w.key)
            }
        }
        content.addChild(layer); hoverLayer = layer
        if !had && animationsEnabled { layer.alpha = 0; let f = SKAction.fadeIn(withDuration: 0.12); f.timingMode = .easeOut; layer.run(f) }
    }


    private func refreshHover() { if pointer != nil { hover(at: pointerInScene) } }
    func clearHover() { hoverLayer?.removeFromParent(); hoverLayer = nil; hoverTarget = nil; hoverRing = nil }

    override func didZoom(zoomingIn: Bool) {
        let z = zoomRatio
        if z > 0.8 { if focus != nil { focus = nil; applyFocus(animated: true); onFocus?(nil) }; return }
        let c = artPoint(cam.position)
        let near = buildings.min { dist($0.value, c) < dist($1.value, c) }?.key
        if let near, near != focus { focus = near; applyFocus(animated: true); onFocus?(near) }
        // zoomed in far enough on a storey: go inside
        if zoomingIn, z < 0.22, let key = focus, let s = storeys.filter({ $0.storey.building == key }).min(by: { centerDistance($0.storey, c) < centerDistance($1.storey, c) }) {
            onEnterFloor?(s.project)
        }
    }

    /// The outline of a building as you see it (its box from the ground to the top of its sprite), in art units.
    private func silhouette(_ key: String) -> CGMutablePath? {
        guard let fp = art?.footprints["building:" + key], let n = buildings[key] else { return nil }
        let top = -(n.position.y) / px - (stacks[key]?.roofOffset ?? 0)    // the sprite's top edge (the roof lifted), art units (y down)
        let i0 = fp.minX, j0 = fp.minY, i1 = fp.maxX, j1 = fp.maxY
        let h = ((i0 + j0) * 8 - top) / 1.08
        let path = CGMutablePath()
        path.addLines(between: [project(i0, j0, h), project(i1, j0, h), project(i1, j0, 0), project(i1, j1, 0), project(i0, j1, 0), project(i0, j1, h)])
        path.closeSubpath()
        return path
    }
    /// A box on the ground (tiles) up to a height (model units) as you see it: six corners, in art units.
    private func boxOutline(_ r: CGRect, height h: CGFloat) -> [CGPoint] {
        [project(r.minX, r.minY, h), project(r.maxX, r.minY, h), project(r.maxX, r.minY, 0), project(r.maxX, r.maxY, 0), project(r.minX, r.maxY, 0), project(r.minX, r.maxY, h)]
    }
    private func diamond(_ r: CGRect) -> [CGPoint] { [project(r.minX, r.minY), project(r.maxX, r.minY), project(r.maxX, r.maxY), project(r.minX, r.maxY)] }

    private func dist(_ n: SKNode, _ c: CGPoint) -> CGFloat { let f = n.calculateAccumulatedFrame(); let m = artPoint(CGPoint(x: f.midX, y: f.midY)); return hypot(m.x - c.x, m.y - c.y) }
    private func centerDistance(_ s: CampusArt.Storey, _ a: CGPoint) -> CGFloat {
        let pts = s.faces.flatMap { $0 }, n = CGFloat(max(pts.count, 1))
        return hypot(pts.map(\.x).reduce(0, +) / n - a.x, pts.map(\.y).reduce(0, +) / n - a.y)
    }
    func contains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        let path = CGMutablePath(); path.addLines(between: poly); path.closeSubpath(); return path.contains(p)
    }

    public var isPainted: Bool { art != nil }

    /// The words for what a hover is on: a building, a floor, the fountain, someone on the roads, a rack.
    private func title(for t: Target) -> (String, String)? {
        let w = shownWorld
        switch t {
        case .building(let key):
            if key == "engine" {
                let m = w.serverSummary
                return ("Server room", m.connected ? "\(w.servers.count) server\(w.servers.count == 1 ? "" : "s") · \(m.down) down · \(m.warn) warning" : "no servers connected")
            }
            guard let p = Provider(rawValue: key), let b = w.building(p) else { return nil }
            let waiting = b.projects.filter { $0.waits(now: w.now) }.count
            return (p.displayName, "\(b.projects.count) floor\(b.projects.count == 1 ? "" : "s")" + (waiting > 0 ? " · \(waiting) waiting" : ""))
        case .storey(let id):
            guard let p = w.project(id: id) else { return nil }
            if let f = p.factory {
                let q = f.openDecisions.count
                return (p.name, "Factory · \(f.autonomy?.level.rawValue ?? "assistant")" + (q > 0 ? " · \(q) question\(q == 1 ? "" : "s")" : ""))
            }
            let waiting = p.count(.waiting, now: w.now), working = p.count(.working, now: w.now)
            let ci = p.github?.ciFailing == true ? " · CI failing" : ""
            return (p.name, "\(p.sessions.count) session\(p.sessions.count == 1 ? "" : "s")" + (working > 0 ? " · \(working) working" : "") + (waiting > 0 ? " · \(waiting) waiting" : "") + ci)
        case .fountain:
            let n = w.needsYou.count
            return ("Needs you", n == 0 ? "nothing waits" : "\(n) waiting · N for the next")
        case .walker(let sid):
            guard let p = w.projects.first(where: { $0.sessions.contains { $0.id == sid } }), let s = p.sessions.first(where: { $0.id == sid }) else { return nil }
            return ("\(s.persona.name) · \(p.role(of: s).label)", s.title)
        case .rack(let c):
            guard c < w.racks.count else { return nil }
            let s = w.racks[c]
            return (s.name, "\(s.state == .warn ? "warning" : s.state.rawValue)" + (s.detail.map { " · \($0)" } ?? ""))
        }
    }

    // MARK: the Server room's slots

    /// The art's projection (blocky-cast.js projWith, S = 1, T = 16): tile i, j and height z to art units.
    static func artP(_ i: CGFloat, _ j: CGFloat, _ z: CGFloat) -> CGPoint { CGPoint(x: (i - j) * 16, y: (i + j) * 8 - z * 1.08) }
    /// Rack c's panel on the front face (blocky-world.js: 19.6 + c * 0.6, 0.4 wide, height 4 to 17, at j = 8).
    static func rackPanel(_ c: Int) -> [CGPoint] {
        let i0 = 19.6 + CGFloat(c) * 0.6, i1 = i0 + 0.4
        return [artP(i0, 8, 4), artP(i1, 8, 4), artP(i1, 8, 17), artP(i0, 8, 17)]
    }

    /// One pulled-out rack unit: its box faces, the dark opening it leaves, the details on its front, its tag.
    private struct Slot { var rack: Int; var node: SKNode; var faces: [SKShapeNode]; var front: [SKShapeNode]; var tag: SKNode }

    /// Pulls a server's whole rack unit out of the Server room (D52): the full-height unit slides towards you on its
    /// runners, leaving a dark opening, with its state light and vents on the front and its name on a tag above.
    /// nil slides the open one back in.
    public func showSlot(_ c: Int?, name: String = "", state: String = "ok", animated: Bool = true) {
        // a repaint of the campus took the unit with it: start over
        if let s = slot, s.node.scene == nil { slot = nil }
        if let s = slot, s.rack != c || c == nil {
            slot = nil
            s.tag.run(.fadeOut(withDuration: 0.12))
            s.node.run(.sequence([slide(s, from: 1, to: 0, duration: animated ? 0.26 : 0), .removeFromParent()]))
        }
        guard let c, c < 10, let engine = buildings["engine"] else { return }
        let col = state == "down" ? Self.down : state == "warn" ? Self.warn : Self.okGreen
        if let s = slot, s.rack == c { s.front[0].fillColor = col; return }
        let node = SKNode(); node.zPosition = engine.zPosition + 0.7
        func face(_ fill: SKColor, stroke: SKColor = .clear, width: CGFloat = 0) -> SKShapeNode {
            let n = SKShapeNode(); n.fillColor = fill; n.strokeColor = stroke; n.lineWidth = width; n.lineJoin = .miter; node.addChild(n); return n
        }
        // the opening, then the unit's side, top and front (cyan edges: it is the selection)
        let hole = face(SKColor(red: 0.04, green: 0.035, blue: 0.08, alpha: 1))
        let edge = Self.cyan.withAlphaComponent(0.9)
        let side = face(SKColor(red: 0.13, green: 0.11, blue: 0.24, alpha: 1), stroke: edge, width: px * 0.5)
        let top = face(SKColor(red: 0.33, green: 0.31, blue: 0.50, alpha: 1), stroke: edge, width: px * 0.5)
        let front = face(SKColor(red: 0.18, green: 0.17, blue: 0.33, alpha: 1), stroke: edge, width: px * 0.5)
        // on the front: the state light, the activity light, and vents between them
        let led = face(col), act = face(SKColor(red: 0.36, green: 0.55, blue: 0.94, alpha: 1))
        let vents = (0..<4).map { _ in face(SKColor(red: 0.10, green: 0.09, blue: 0.20, alpha: 1)) }
        // the name tag above the unit, in the cream of the signs
        let tag = SKNode()
        let label = SKLabelNode(text: name.uppercased()); label.fontName = "Menlo-Bold"; label.fontSize = 6 * px
        label.fontColor = SKColor(red: 0.16, green: 0.10, blue: 0.18, alpha: 1); label.verticalAlignmentMode = .center
        let w = label.frame.width + 9 * px, h = 10 * px
        let bg = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 1.5 * px)
        bg.fillColor = SKColor(red: 0.96, green: 0.94, blue: 0.85, alpha: 1); bg.strokeColor = SKColor(red: 0.16, green: 0.10, blue: 0.18, alpha: 1); bg.lineWidth = px * 0.8
        let dot = SKShapeNode(circleOfRadius: 2 * px); dot.fillColor = col; dot.strokeColor = .clear; dot.position = CGPoint(x: -w / 2 + 5 * px, y: 0)
        label.position = CGPoint(x: 2.5 * px, y: 0)
        tag.addChild(bg); tag.addChild(dot); tag.addChild(label)
        let i0 = 19.6 + CGFloat(c) * 0.6
        tag.position = scenePoint(Self.artP(i0 + 0.2, 8 + Self.slotTravel, 30)); tag.zPosition = 2; tag.alpha = 0
        node.addChild(tag)
        content.addChild(node)
        let s = Slot(rack: c, node: node, faces: [hole, side, top, front], front: [led, act] + vents, tag: tag)
        slot = s
        node.run(slide(s, from: 0, to: 1, duration: animated ? 0.34 : 0))
        tag.run(.sequence([.wait(forDuration: animated ? 0.22 : 0), .fadeIn(withDuration: animated ? 0.15 : 0)]))
    }

    /// how far a unit comes out, in tiles
    static let slotTravel: CGFloat = 1.5

    /// The unit between "in" (0) and "out" (1), eased (a small overshoot going out, like a unit on runners).
    private func slide(_ s: Slot, from a: CGFloat, to b: CGFloat, duration: TimeInterval) -> SKAction {
        let i0 = 19.6 + CGFloat(s.rack) * 0.6, i1 = i0 + 0.4, z0: CGFloat = 4, z1: CGFloat = 17
        let draw: (CGFloat) -> Void = { [weak self] t in
            guard let self else { return }
            let j1 = 8 + Self.slotTravel * t, P = Self.artP
            func path(_ pts: [CGPoint]) -> CGPath { let p = CGMutablePath(); p.addLines(between: pts.map { self.scenePoint($0) }); p.closeSubpath(); return p }
            func plate(_ u0: CGFloat, _ u1: CGFloat, _ h0: CGFloat, _ h1: CGFloat) -> CGPath { path([P(u0, j1, h0), P(u1, j1, h0), P(u1, j1, h1), P(u0, j1, h1)]) }
            s.faces[0].path = path([P(i0, 8, z0), P(i1, 8, z0), P(i1, 8, z1), P(i0, 8, z1)])          // the opening
            s.faces[1].path = path([P(i1, 8, z0), P(i1, j1, z0), P(i1, j1, z1), P(i1, 8, z1)])        // side
            s.faces[2].path = path([P(i0, 8, z1), P(i1, 8, z1), P(i1, j1, z1), P(i0, j1, z1)])        // top
            s.faces[3].path = plate(i0, i1, z0, z1)                                                   // front
            s.front[0].path = plate(i0 + 0.06, i0 + 0.16, 12, 13.2)                                   // state light
            s.front[1].path = plate(i0 + 0.06, i0 + 0.16, 6, 7)                                       // activity light
            for (k, v) in s.front.dropFirst(2).enumerated() {
                let h = 8.2 + CGFloat(k) * 0.9
                v.path = plate(i0 + 0.05, i1 - 0.05, h, h + 0.35)
            }
            let shown: CGFloat = t < 0.02 ? 0 : 1
            for n in s.faces + s.front { n.alpha = shown }
        }
        draw(a)
        guard duration > 0 else { return .run { draw(b) } }
        return .customAction(withDuration: duration) { _, e in
            let x = min(1, e / CGFloat(duration))
            let k: CGFloat = b > a ? 1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2) : x * x
            draw(a + (b - a) * k)
        }
    }

    // MARK: for window shots

    /// Where walker k stands now, in view points (a debug aid for hover shots).
    public func walkerViewPoint(_ k: Int) -> CGPoint? {
        let list = walkers.values.sorted { $0.key < $1.key }
        guard k < list.count, view != nil else { return nil }
        let f = list[k].node.frame
        return convertPoint(toView: CGPoint(x: f.midX, y: f.midY))
    }
}

/// What a hover is on, for the HUD's tooltip: a title, one line, and where the pointer is (view points, top left).
public struct HoverTitle: Equatable, Sendable {
    public var title: String, line: String, at: CGPoint
    /// left of the pointer: over a tower, whose plaques hang to the right and must stay readable
    public var left = false
}
