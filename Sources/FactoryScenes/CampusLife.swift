import SpriteKit
import FactoryCore

/// D66: the campus's life, from what goes on (CampusSignals). State that lasts (the sky, weather, a crane, a deploy's
/// stream) is drawn anew when it changes; moments (a delivery, a ribbon, a lift ride) play once.
struct CampusLife {
    var daylight: CGFloat = 1
    /// window shots: a fixed hour instead of the Mac's clock
    var hourOverride: Double?
    /// the paint last asked for at dusk or dawn (nil: none yet)
    var askedNight: Bool?
    var clockAcc = 10.0
    /// factories in their quiet hours: their screens low
    var sleeping: Set<String> = []
    var streaming = false
    var demo = false
    var sky: SKSpriteNode?
    var shade: SKSpriteNode?
    /// what stays, drawn anew when its signature changes
    var nodes: [SKNode] = []
    var sig = ""
    var streams: [[CGPoint]] = []
    var streamAcc = 0.0
    /// a deploy's packets run on the ground, under everything that stands
    let ground = SKNode()
    /// the alarm lights on broken storeys (D75): their rotating beams and lenses, turned every frame
    var alarms: [AlarmLight] = []
    var alarmAngle = 0.0
    /// what has been seen, so only what is new plays: deliveries and helpers
    var primed = false
    var delivered: [String: Date] = [:]
    var helpers: Set<String> = []
    /// the Status layer (D69): on or off, what it drew, and its lamps for the blink
    var layerOn = false
    var layerSig = ""
    /// what each effect means, for the hover (D74): the node, a title and one line
    var hotspots: [(node: SKNode, title: String, line: String)] = []
    var layerNodes: [SKNode] = []
    var layerLamps: [(node: SKNode, glow: SKNode, state: ServiceStatus.State)] = []

    /// A rotating alarm light: where its lens sits (art units), its two beams, the lens faces that flare, a glow.
    struct AlarmLight { var lens: CGPoint; var beams: [SKShapeNode]; var faces: [SKShapeNode]; var glow: SKSpriteNode; var phase: Double }

    /// The campus was drawn anew: what hung on it is gone, the moments in the air and the rides stay.
    mutating func reset() { nodes = []; sig = ""; alarms = []; ground.removeAllChildren(); layerNodes = []; layerLamps = []; hotspots = [] }
}

extension CampusScene {
    /// The day sky in Spel+ (D80): the town floats in a deep violet dusk, with a few stars (world-s-campus.png).
    static let daySkyTexture: SKTexture = gradient([(0.11, 0.082, 0.204), (0.165, 0.122, 0.282), (0.227, 0.165, 0.353)])
    /// A pixel moon (A8): rows of 4-unit blocks with two darker patches.
    static let moonTexture: SKTexture = {
        let n = 72, cs = CGColorSpaceCreateDeviceRGB(), r = 30
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0.953, blue: 0.816, alpha: 1))
        for y in stride(from: -r, through: r, by: 4) {
            let half = Int(Double(r * r - y * y).squareRoot() / 4) * 4
            ctx.fill(CGRect(x: n / 2 - half, y: n / 2 + y, width: half * 2, height: 4))
        }
        ctx.setFillColor(CGColor(red: 0.91, green: 0.863, blue: 0.722, alpha: 1))
        for (x, y, w, h) in [(-10, 0, 8, 8), (8, -18, 12, 8), (-18, -22, 6, 6)] { ctx.fill(CGRect(x: n / 2 + x, y: n / 2 + y, width: w, height: h)) }
        return SKTexture(cgImage: ctx.makeImage()!)
    }()
    /// A raindrop: a short white stroke.
    static let dropTexture: SKTexture = {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 2, height: 10, bitsPerComponent: 8, bytesPerRow: 8, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 10))
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    // MARK: reading the world

    /// Called with every new world (and after each repaint): what lasts is drawn anew when it changed, what is new
    /// plays once. The first look only takes note, so nothing old plays at launch.
    public func updateLife(_ world: World) {
        guard art != nil else { return }
        let now = world.now, hour = life.hourOverride ?? CampusSignals.hour(now)
        life.sleeping = Set(world.projects.filter { p in p.factory?.mandate.map { CampusSignals.quiet($0.quietHours, hour: hour) } ?? false }.map(\.id))
        // what lasts: a red alarm light on each broken storey, deploys
        var alarms: [String: String] = [:]
        for p in world.projects { if let why = CampusSignals.alarm(p, now: now) { alarms[p.id] = why } }
        var deploying = Set(world.buildings.filter { $0.projects.contains { CampusSignals.deploying($0, now: now) } }.map(\.provider.rawValue))
        if life.demo {
            if let s = storeys.first(where: { $0.storey.building == "chatgpt" && $0.storey.kind == "project" }) {
                alarms[s.project] = "A session ended with a failed test. Clears when a test passes, or after 12 hours."
            }
            deploying.insert("claude")
        }
        if let f = world.projects.first(where: { ($0.factory?.mandate?.level ?? .assistant) != .assistant }), let m = f.factory?.mandate {
            // the effect's name as the title, the cause with the project's name under it (never cut off in the middle)
            onEffect?("dark", "Dimmed floor", "\(f.name): its mandate is \(m.level.rawValue.capitalized). Lights on is Assistant, dimmed Hybrid, lights out Dark.")
        }
        let sig = alarms.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            + "|" + deploying.sorted().joined(separator: ",")
        if sig != life.sig || life.nodes.isEmpty {
            life.sig = sig
            drawLife(alarms: alarms, deploying: deploying)
        }
        // moments: a delivery, a lift ride
        if life.primed {
            for p in world.projects {
                guard let s = storeys.first(where: { $0.project == p.id }) else { continue }
                if let last = CampusSignals.deliveries(p, after: life.delivered[p.id] ?? now).last {
                    life.delivered[p.id] = last
                    deliver(from: s.storey, words: p.github != nil ? "\(p.name) merged a pull request" : "\(p.name)'s factory pushed or deployed")
                }
                let fresh = CampusSignals.helpers(p).subtracting(life.helpers)
                if !fresh.isEmpty { helperArrives(s.storey) }
            }
        } else {
            for p in world.projects { life.delivered[p.id] = now }
        }
        let layerSig = world.services.map { "\($0.id)=\($0.shown(now: now).rawValue)" }.joined() + world.projects.map { "\($0.id)=\($0.github?.ciFailing.description ?? "-")" }.joined()
        if layerSig != life.layerSig || life.layerNodes.isEmpty { life.layerSig = layerSig; drawStatusLayer(world) }
        life.helpers = Set(world.projects.flatMap { CampusSignals.helpers($0) })
        life.primed = true
    }

    /// Window shots: every kind of life at once, at night, on the made-up campus.
    public func demoLife() {
        life.demo = true; life.hourOverride = 21.5; life.clockAcc = 10
        updateLife(shownWorld)
        if let f = storeys.first(where: { $0.storey.kind == "factory" }) { deliver(from: f.storey) }
        if let s = storeys.first(where: { $0.storey.building == "chatgpt" }) { helperArrives(s.storey) }
    }
    public func setHour(_ h: Double?) { life.hourOverride = h; life.clockAcc = 10 }

    // MARK: what lasts

    private func drawLife(alarms: [String: String], deploying: Set<String>) {
        for n in life.nodes { n.removeFromParent() }
        life.nodes = []; life.ground.removeAllChildren()
        // keep what the Status layer and the moments in the air explain; the rest is drawn anew below
        let keep = Set(life.layerNodes.map(ObjectIdentifier.init))
        life.hotspots.removeAll { h in h.node.parent == nil || (!keep.contains(ObjectIdentifier(h.node)) && h.node.name != "moment") }
        let w = shownWorld
        // 5B: a rotating red alarm light on the front corner of a broken storey, on a bracket out of the wall
        life.alarms = []
        for (k, (st, id)) in storeys.enumerated() {
            guard let why = alarms[id], let host = layer(st.building, storey: st.index), let mount = st.mount ?? Self.frontCorner(st) else { continue }
            let (fixture, beams, light) = alarmLight(at: mount, phase: Double(k) * 1.3)
            host.addChild(beams); host.addChild(fixture); life.nodes.append(contentsOf: [beams, fixture])
            life.alarms.append(light)
            explain(fixture, ("Alarm · \(w.project(id: id)?.name ?? "a project")", why))
            onEffect?("alarm", "Red alarm light", "\(w.project(id: id)?.name ?? "A floor"): " + (why.hasPrefix("CI on main is red") ? "CI on main is red." : why))
        }
        // 5F: a deploy's packets on the road from its tower to the Server room
        life.streams = deploying.compactMap { art?.streams[$0] }.map { $0.map { project($0.x, $0.y, CampusRoads.height($0.x, $0.y) + 0.5) } }
        life.streaming = !life.streams.isEmpty
        if life.streaming { onEffect?("packets", "Packets on the road to the Server room", "A deploy is running.") }
    }

    /// Remembers what an effect means, for the hover (D74).
    func explain(_ node: SKNode, _ words: (String, String)) { life.hotspots.append((node, words.0, words.1)) }
    private func isMoment(_ n: SKNode) -> Bool { n.name == "moment" }

    /// The explanation under a scene point, if an effect is there.
    func hotspot(at p: CGPoint) -> (String, String)? {
        life.hotspots.removeAll { $0.node.parent == nil }
        for h in life.hotspots.reversed() {
            guard let parent = h.node.parent, h.node.alpha > 0.05, !h.node.isHidden else { continue }
            let q = convert(p, to: parent)
            if h.node.calculateAccumulatedFrame().insetBy(dx: -3 * px, dy: -3 * px).contains(q) { return (h.title, h.line) }
        }
        return nil
    }

    /// Where a storey's two front faces meet, a little above its middle (art units): the alarm light's bracket.
    static func frontCorner(_ st: CampusArt.Storey) -> CGPoint? {
        guard st.faces.count == 2 else { return nil }
        let shared = st.faces[0].filter { p in st.faces[1].contains { hypot(p.x - $0.x, p.y - $0.y) < 0.6 } }
        guard shared.count >= 2, let top = shared.min(by: { $0.y < $1.y }), let bottom = shared.max(by: { $0.y < $1.y }) else { return nil }
        return CGPoint(x: top.x, y: bottom.y + (top.y - bottom.y) * 0.58)
    }

    /// A point `di`, `dj` tiles and `dz` model units from `o`, in art units (the campus's own projection).
    private static func iso(_ o: CGPoint, _ di: CGFloat, _ dj: CGFloat, _ dz: CGFloat) -> CGPoint {
        CGPoint(x: o.x + (di - dj) * 16, y: o.y + (di + dj) * 8 - dz * 1.08)
    }

    /// An iso box round `o` (half a side `h` tiles, from `z0` to `z1` model units): its two visible sides and its top.
    private func isoBox(_ o: CGPoint, h: CGFloat, z0: CGFloat, z1: CGFloat, top: SKColor, left: SKColor, right: SKColor) -> [SKShapeNode] {
        let P = Self.iso
        let l = shape([P(o, -h, h, z0), P(o, h, h, z0), P(o, h, h, z1), P(o, -h, h, z1)], fill: left, stroke: Self.ink, width: 0.5 * px)
        let r = shape([P(o, h, h, z0), P(o, h, -h, z0), P(o, h, -h, z1), P(o, h, h, z1)], fill: right, stroke: Self.ink, width: 0.5 * px)
        let t = shape([P(o, -h, -h, z1), P(o, h, -h, z1), P(o, h, h, z1), P(o, -h, h, z1)], fill: top, stroke: Self.ink, width: 0.5 * px)
        return [l, r, t]
    }

    static let alarmRed = SKColor(red: 0.95, green: 0.18, blue: 0.15, alpha: 1)

    /// A rotating alarm light on a bracket out of the storey's corner: a steel bracket, a dark base, a red lens and a
    /// cap, with two beams that sweep round it over the ground plane (turned in `tickLife`); the lens flares when a
    /// beam points at you. With reduced motion it is a steady red light.
    private func alarmLight(at corner: CGPoint, phase: Double) -> (SKNode, SKNode, CampusLife.AlarmLight) {
        let P = Self.iso
        let steel = SKColor(red: 0.32, green: 0.34, blue: 0.4, alpha: 1), dark = SKColor(red: 0.13, green: 0.13, blue: 0.16, alpha: 1)
        let out = P(corner, 0.2, 0.2, 0)                     // the light stands a little out from the wall, towards you
        let fixture = SKNode(); fixture.zPosition = 1.35
        // the bracket: a flat arm from the wall to under the base
        for n in isoBox(P(corner, 0.1, 0.1, 0), h: 0.1, z0: -1.2, z1: 0, top: steel, left: steel.withBrightness(0.8), right: steel.withBrightness(0.62)) { fixture.addChild(n) }
        for n in isoBox(out, h: 0.1, z0: 0, z1: 1.6, top: dark, left: dark, right: dark.withBrightness(0.8)) { fixture.addChild(n) }
        let red = Self.alarmRed
        let lens = isoBox(out, h: 0.075, z0: 1.6, z1: 6.2, top: red.withBrightness(1.05), left: red.withBrightness(0.82), right: red.withBrightness(0.62))
        for n in lens { fixture.addChild(n) }
        for n in isoBox(out, h: 0.095, z0: 6.2, z1: 7.2, top: dark.withBrightness(1.4), left: dark, right: dark.withBrightness(0.8)) { fixture.addChild(n) }
        // a highlight on the lens's left face
        fixture.addChild(shape([P(out, -0.05, 0.075, 3.4), P(out, -0.02, 0.075, 3.4), P(out, -0.02, 0.075, 5.6), P(out, -0.05, 0.075, 5.6)],
                               fill: SKColor(white: 1, alpha: 0.55)))
        let center = P(out, 0, 0, 3.9)
        let g = glow(center, size: CGSize(width: 34, height: 34), color: red); g.zPosition = 0.05; fixture.addChild(g)
        // the beams: drawn under the fixture, added to on screen, pointed every frame
        let beamsNode = SKNode(); beamsNode.zPosition = 1.3
        var beams: [SKShapeNode] = []
        if animationsEnabled {
            for _ in 0..<2 {
                let b = SKShapeNode(); b.fillColor = red.withAlphaComponent(0.32); b.strokeColor = .clear; b.blendMode = .add
                beamsNode.addChild(b); beams.append(b)
            }
        }
        let light = CampusLife.AlarmLight(lens: center, beams: beams, faces: Array(lens.prefix(2)), glow: g, phase: phase)
        pointAlarm(light, angle: phase)
        return (fixture, beamsNode, light)
    }

    /// Turns an alarm light's beams to `angle` (radians, in the ground plane) and flares its lens towards you.
    private func pointAlarm(_ a: CampusLife.AlarmLight, angle: Double) {
        let P = Self.iso, reach: CGFloat = 1.9, spread = 0.22
        for (k, b) in a.beams.enumerated() {
            let t = angle + Double(k) * .pi
            let p1 = P(a.lens, reach * CGFloat(cos(t - spread)), reach * CGFloat(sin(t - spread)), 0)
            let p2 = P(a.lens, reach * CGFloat(cos(t + spread)), reach * CGFloat(sin(t + spread)), 0)
            let path = CGMutablePath(); path.addLines(between: [a.lens, p1, p2].map(scenePoint)); path.closeSubpath()
            b.path = path
            // a beam into the wall is hidden by it: it fades out as it turns away from the street
            let out = cos(t - .pi / 4), fade = min(1, max(0, (out - 0.15) / 0.45))
            b.alpha = CGFloat(fade)
        }
        // towards you is +i +j (down the screen): a beam there lights the lens and the glow
        var toYou: Double = 1
        if !a.beams.isEmpty {
            let first: Double = cos(angle - .pi / 4)
            let second: Double = cos(angle + .pi - .pi / 4)
            toYou = max(0, max(first, second))
        }
        let f = CGFloat(0.55 + 0.45 * toYou)
        let lit: CGFloat = 0.7 + 0.5 * f
        for (k, n) in a.faces.enumerated() {
            let base: CGFloat = k == 0 ? 0.82 : 0.62
            n.fillColor = Self.alarmRed.withBrightness(base * lit)
        }
        a.glow.alpha = 0.35 + 0.65 * f
        a.glow.setScale(0.8 + 0.5 * f)
    }

    // MARK: moments

    /// 5C: a drone takes a factory's delivery from its storey to the plaza; the fountain splashes once.
    func deliver(from s: CampusArt.Storey, words: String = "A pull request was merged") {
        guard let art, animationsEnabled, s.faces.count == 2 else { return }
        let f = s.faces[0]
        let off = stacks[s.building]?.offset(s.index) ?? 0
        let start = scenePoint(CGPoint(x: (f[0].x + f[2].x) / 2, y: (f[0].y + f[2].y) / 2 - off))
        let end = scenePoint(CGPoint(x: art.fountain.x, y: art.fountain.y - 30))
        let drone = SKNode(); drone.position = start; drone.zPosition = 10
        let body = SKShapeNode(rect: CGRect(x: -5 * px, y: 0, width: 10 * px, height: 3 * px), cornerRadius: 1 * px)
        body.fillColor = SKColor(red: 0.18, green: 0.16, blue: 0.24, alpha: 1); body.strokeColor = SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 1); body.lineWidth = 0.6 * px
        drone.addChild(body)
        for x: CGFloat in [-6, 6] {
            let rotor = SKShapeNode(ellipseOf: CGSize(width: 7 * px, height: 1.6 * px)); rotor.fillColor = SKColor(white: 0.85, alpha: 0.9); rotor.strokeColor = .clear
            rotor.position = CGPoint(x: x * px, y: 4 * px)
            rotor.run(.repeatForever(.sequence([.scaleX(to: 0.2, duration: 0.05), .scaleX(to: 1, duration: 0.05)])))
            drone.addChild(rotor)
        }
        let parcel = SKShapeNode(rect: CGRect(x: -3 * px, y: -6 * px, width: 6 * px, height: 5 * px))
        parcel.fillColor = SKColor(red: 0.78, green: 0.58, blue: 0.36, alpha: 1); parcel.strokeColor = Self.ink; parcel.lineWidth = 0.6 * px
        let tape = SKShapeNode(rect: CGRect(x: -0.6 * px, y: -6 * px, width: 1.2 * px, height: 5 * px)); tape.fillColor = SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 1); tape.strokeColor = .clear
        parcel.addChild(tape); drone.addChild(parcel)
        effects.addChild(drone)
        drone.name = "moment"
        explain(drone, ("Delivery", words))
        onEffect?("drone", "A drone flies to the fountain", words)
        let path = CGMutablePath(); path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 90 * px))
        let fly = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 3.2); fly.timingMode = .easeInEaseOut
        let fall = -18 * px
        let drop = SKAction.run { [weak self] in
            parcel.run(.sequence([.group([.moveBy(x: 0, y: fall, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
            self?.splash()
        }
        drone.run(.sequence([fly, drop, .wait(forDuration: 0.3), .group([.moveBy(x: 0, y: 60 * px, duration: 1.2), .fadeOut(withDuration: 1.2)]), .removeFromParent()]))
    }

    /// The fountain splashes once: a burst of drops and a warm flash.
    private func splash() {
        guard let art else { return }
        let e = SKEmitterNode()
        e.particleTexture = Self.glowTexture
        e.numParticlesToEmit = 36; e.particleBirthRate = 200
        e.particleLifetime = 0.9; e.emissionAngle = .pi / 2; e.emissionAngleRange = 1.1
        e.particleSpeed = 55 * px; e.particleSpeedRange = 20 * px; e.yAcceleration = -140 * px
        e.particleSize = CGSize(width: 3 * px, height: 3 * px)
        e.particleColor = SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 1); e.particleColorBlendFactor = 1; e.particleAlpha = 0.9; e.particleAlphaSpeed = -0.8
        e.position = scenePoint(CGPoint(x: art.fountain.x, y: art.fountain.y - 14)); e.zPosition = 5
        effects.addChild(e)
        e.run(.sequence([.wait(forDuration: 2), .removeFromParent()]))
        let g = glow(art.fountain, size: CGSize(width: 90, height: 50), color: Self.wait); g.zPosition = 4; g.alpha = 0
        effects.addChild(g)
        g.run(.sequence([.fadeAlpha(to: 0.6, duration: 0.15), .fadeOut(withDuration: 0.9), .removeFromParent()]))
    }

    /// 5E (Spel+, no lift, A10): a helper arrives on a storey: its windows light up together for a moment, cool white,
    /// and its blade sign gives a short nod.
    func helperArrives(_ st: CampusArt.Storey) {
        onEffect?("helper", "A floor's windows light up", "A chat started a helper (a sub-agent) on that floor.")
        guard animationsEnabled, let host = layer(st.building, storey: st.index) else { return }
        let flash = SKNode(); flash.name = "moment"
        for w in st.windows where w.count == 4 {
            let n = shape(w, fill: SKColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)); n.blendMode = .add; flash.addChild(n)
        }
        flash.alpha = 0; flash.zPosition = 0.06
        host.addChild(flash)
        explain(flash, ("A helper arrives", "A chat started a helper (a sub-agent) on this floor"))
        flash.run(.sequence([.fadeAlpha(to: 0.55, duration: 0.25), .wait(forDuration: 0.5), .fadeAlpha(to: 0.2, duration: 0.3), .fadeAlpha(to: 0.45, duration: 0.25), .fadeOut(withDuration: 1.2), .removeFromParent()]))
        if let sg = signs.first(where: { $0.plaque && $0.owner == st.building && $0.storey == st.index })?.node {
            sg.run(.sequence([.scale(by: 1.12, duration: 0.15), .scale(by: 1 / 1.12, duration: 0.25)]))
        }
    }

    // MARK: every frame

    func tickLife(_ dt: Double) {
        // 5A: the sky and the light follow the clock (looked at every few seconds)
        life.clockAcc += dt
        if life.clockAcc >= 5 {
            life.clockAcc = 0
            life.daylight = CGFloat(CampusSignals.daylight(hour: life.hourOverride ?? CampusSignals.hour(Date())))
            if life.daylight < 0.4 { onEffect?("night", "Night on the campus", "The sky follows your Mac's clock: by moonlight only real lights glow. Nothing is wrong.") }
            // A8: night is painted, not filtered. Once dusk has fallen far enough the campus asks for its night paint
            // (and at dawn for its day paint); until it comes, a thin veil darkens the day
            let wantNight = life.daylight < 0.35
            if art != nil, wantNight != artNight, life.askedNight != wantNight { life.askedNight = wantNight; onNightChange?(wantNight) }
        }
        if life.sky == nil {
            let s = SKSpriteNode(texture: Self.daySkyTexture); s.zPosition = -999; cam.addChild(s); life.sky = s
            // night is a thin blue veil (an ordinary blend, so it never goes darker than its alpha), under the lamps' light
            let sh = SKSpriteNode(color: SKColor(red: 0.06, green: 0.07, blue: 0.24, alpha: 1), size: CGSize(width: 10, height: 10))
            sh.zPosition = 2995; cam.addChild(sh); life.shade = sh
        }
        let full = CGSize(width: size.width * 1.02, height: size.height * 1.02)
        life.sky?.size = full; life.sky?.alpha = artNight ? 0 : max(life.daylight, 0.4)
        life.shade?.size = full; life.shade?.alpha = artNight ? 0 : (1 - life.daylight) * 0.3
        // stars only at night, and faintly at dusk while the night paint is on its way: never in a day sky
        starNode?.alpha = artNight ? 1 : life.daylight < 0.35 ? 0.4 : 0
        if artNight, moonNode == nil {
            let m = SKSpriteNode(texture: Self.moonTexture); m.size = CGSize(width: 46, height: 46); m.zPosition = -997
            let g = SKSpriteNode(texture: Self.glowTexture); g.size = CGSize(width: 150, height: 150); g.color = SKColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
            g.colorBlendFactor = 1; g.alpha = 0.25; g.blendMode = .add; m.addChild(g)
            cam.addChild(m); moonNode = m
        }
        moonNode?.isHidden = !artNight
        moonNode?.position = CGPoint(x: size.width * 0.34, y: size.height * 0.36)
        content.childNode(withName: "lamplight")?.alpha = artNight ? 1 : 0.3 + 0.65 * (1 - life.daylight)
        animateLayer(clock)
        // 5B: the alarm lights turn (about a turn every two seconds)
        if animationsEnabled, !life.alarms.isEmpty {
            life.alarmAngle += dt * 3.1
            for a in life.alarms { pointAlarm(a, angle: life.alarmAngle + a.phase) }
        }
        // 5F: packets on the road while a deploy runs
        guard animationsEnabled, !life.streams.isEmpty else { return }
        life.streamAcc += dt
        guard life.streamAcc >= 0.35 else { return }
        life.streamAcc = 0
        for route in life.streams where route.count > 1 {
            let path = CGMutablePath(); path.addLines(between: route.map(scenePoint))
            var length: CGFloat = 0
            for k in 1..<route.count { length += hypot(route[k].x - route[k - 1].x, route[k].y - route[k - 1].y) }
            let packet = SKShapeNode(rectOf: CGSize(width: 4 * px, height: 2.4 * px), cornerRadius: 0.6 * px)
            packet.fillColor = Self.cyan; packet.strokeColor = Self.ink; packet.lineWidth = 0.4 * px
            packet.position = scenePoint(route[0])
            life.ground.addChild(packet)
            packet.run(.sequence([.follow(path, asOffset: false, orientToPath: false, duration: Double(length) / 70), .fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
    }
}

extension SKColor {
    /// The same colour, its RGB scaled by `f` (shading the faces of a box).
    func withBrightness(_ f: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (usingColorSpace(.deviceRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: min(1, r * f), green: min(1, g * f), blue: min(1, b * f), alpha: a)
    }
}
