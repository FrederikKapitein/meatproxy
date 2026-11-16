import SpriteKit
import FactoryCore

/// D66: the campus's life, from what goes on (CampusSignals). State that lasts (the sky, weather, a crane, a deploy's
/// stream) is drawn anew when it changes; moments (a delivery, a ribbon, a lift ride) play once.
struct CampusLife {
    var daylight: CGFloat = 1
    /// window shots: a fixed hour instead of the Mac's clock
    var hourOverride: Double?
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
    var shafts: [String: SKNode] = [:]
    var cars: [String: SKNode] = [:]
    var lifts: [String: Lift] = [:]
    var streams: [[CGPoint]] = []
    var streamAcc = 0.0
    /// a deploy's packets run on the ground, under everything that stands
    let ground = SKNode()
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

    struct Lift { var z: CGFloat = 0, target: CGFloat = 0, hold = 0.0, queue: [Int] = [] }

    /// The campus was drawn anew: what hung on it is gone, the moments in the air and the rides stay.
    mutating func reset() { nodes = []; sig = ""; shafts = [:]; cars = [:]; ground.removeAllChildren(); layerNodes = []; layerLamps = []; hotspots = [] }
}

extension CampusScene {
    static let daySkyTexture: SKTexture = {
        let w = 8, h = 256, cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.66, green: 0.72, blue: 0.95, alpha: 1), CGColor(red: 0.42, green: 0.48, blue: 0.86, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
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
                if !fresh.isEmpty { ride(s.storey.building, to: s.storey.index) }
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
        if let s = storeys.first(where: { $0.storey.building == "chatgpt" }) { ride("chatgpt", to: max(0, s.storey.index + 1)) }
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
        // 5B: a red alarm light where a storey meets its plaque, blinking while the project is broken
        for (st, id) in storeys {
            guard let why = alarms[id], let host = layer(st.building, storey: st.index),
                  let rects = art?.plaques[st.building], st.index < rects.count else { continue }
            let r = rects[st.index]
            let a = alarmLight(at: CGPoint(x: r.minX - 1, y: r.midY))
            host.addChild(a); life.nodes.append(a)
            explain(a, ("Alarm · \(w.project(id: id)?.name ?? "a project")", why))
        }
        // 5E: a glass lift on each tower, its car parked below
        for (key, st) in stacks {
            guard let ov = overlays[key], let shaft = liftShaft(key) else { continue }
            shaft.alpha = 1 - min(1, st.e * 3)
            ov.addChild(shaft); life.nodes.append(shaft); life.shafts[key] = shaft
            explain(shaft, ("Glass lift", "Takes someone up when a session starts a sub-agent"))
            life.cars[key] = shaft.childNode(withName: "car")
        }
        // 5F: a deploy's packets on the road from its tower to the Server room
        life.streams = deploying.compactMap { Self.streamRoutes[$0] }.map { $0.map { project($0.x, $0.y) } }
        life.streaming = !life.streams.isEmpty
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

    /// A red alarm light: a dark base, a red lamp that blinks and a glow that pulses (steady when motion is reduced).
    private func alarmLight(at c: CGPoint) -> SKNode {
        let n = SKNode(); n.zPosition = 1.35
        let red = SKColor(red: 0.93, green: 0.16, blue: 0.14, alpha: 1), dim = SKColor(red: 0.55, green: 0.08, blue: 0.08, alpha: 1)
        let glowNode = glow(c, size: CGSize(width: 56, height: 56), color: red); glowNode.zPosition = -0.05
        let base = SKShapeNode(rectOf: CGSize(width: 14 * px, height: 4 * px))
        base.fillColor = Self.ink; base.strokeColor = Self.ink; base.position = scenePoint(CGPoint(x: c.x, y: c.y + 7))
        let lamp = SKShapeNode(rectOf: CGSize(width: 11 * px, height: 11 * px))
        lamp.fillColor = red; lamp.strokeColor = Self.ink; lamp.lineWidth = 1 * px; lamp.position = scenePoint(c)
        let shine = SKShapeNode(rectOf: CGSize(width: 3.5 * px, height: 3.5 * px))
        shine.fillColor = SKColor(white: 1, alpha: 0.8); shine.strokeColor = .clear; shine.position = CGPoint(x: -2.2 * px, y: 2.2 * px)
        lamp.addChild(shine)
        n.addChild(glowNode); n.addChild(base); n.addChild(lamp)
        if animationsEnabled {
            let blink = SKAction.repeatForever(.sequence([
                .run { lamp.fillColor = red }, .wait(forDuration: 0.45), .run { lamp.fillColor = dim }, .wait(forDuration: 0.35)]))
            lamp.run(blink)
            glowNode.run(.repeatForever(.sequence([.fadeAlpha(to: 1, duration: 0.4), .fadeAlpha(to: 0.45, duration: 0.4)])))
        }
        return n
    }

    /// A glass lift up the left end of a tower's front, from the plinth to the roof, with its car (named "car").
    private func liftShaft(_ key: String) -> SKNode? {
        let sts = storeys.filter { $0.storey.building == key }.map(\.storey).sorted { $0.index < $1.index }
        guard let first = sts.first, let last = sts.last, first.faces.count == 2 else { return nil }
        let o = first.faces[0][0]          // the front face's bottom-left corner: tile i0, jd, z 8
        let height = CGFloat(last.index + 1) * 30
        // a point by tiles along i and out from the front (j) and model units up
        func P(_ u: CGFloat, _ v: CGFloat, _ z: CGFloat) -> CGPoint { CGPoint(x: o.x + u * 16 - v * 16, y: o.y + u * 8 + v * 8 - z * 1.08) }
        let n = SKNode(); n.zPosition = 0.45
        let glass = SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 0.2), edge = SKColor(white: 1, alpha: 0.55)
        let u0: CGFloat = 0.22, u1: CGFloat = 0.98, v1: CGFloat = 0.45
        n.addChild(shape([P(u0, v1, 0), P(u1, v1, 0), P(u1, v1, height), P(u0, v1, height)], fill: glass, stroke: edge, width: 0.7 * px))
        n.addChild(shape([P(u1, v1, 0), P(u1, 0, 0), P(u1, 0, height), P(u1, v1, height)], fill: glass.withAlphaComponent(0.14), stroke: edge, width: 0.7 * px))
        // the car: a box with a window and someone in it
        let car = SKNode(); car.name = "car"
        let body = SKColor(red: 0.85, green: 0.87, blue: 0.93, alpha: 1)
        car.addChild(shape([P(u1 - 0.04, v1 - 0.02, 1), P(u1 - 0.04, 0.04, 1), P(u1 - 0.04, 0.04, 15), P(u1 - 0.04, v1 - 0.02, 15)], fill: body.withAlphaComponent(0.8), stroke: Self.ink, width: 0.6 * px))
        car.addChild(shape([P(u0 + 0.05, v1 - 0.02, 1), P(u1 - 0.04, v1 - 0.02, 1), P(u1 - 0.04, v1 - 0.02, 15), P(u0 + 0.05, v1 - 0.02, 15)], fill: body, stroke: Self.ink, width: 0.6 * px))
        car.addChild(shape([P(u0 + 0.15, v1 - 0.02, 5), P(u1 - 0.14, v1 - 0.02, 5), P(u1 - 0.14, v1 - 0.02, 13), P(u0 + 0.15, v1 - 0.02, 13)], fill: SKColor(red: 0.2, green: 0.24, blue: 0.4, alpha: 1)))
        let head = SKShapeNode(circleOfRadius: 1.6 * px); head.fillColor = SKColor(red: 0.95, green: 0.71, blue: 0.54, alpha: 1); head.strokeColor = Self.ink; head.lineWidth = 0.4 * px
        head.position = scenePoint(P((u0 + u1) / 2, v1 - 0.02, 9.5)); car.addChild(head)
        n.addChild(car)
        return n
    }

    /// The road from each tower's door to the Server room's racks, in tiles.
    static let streamRoutes: [String: [CGPoint]] = [
        "claude": [CGPoint(x: 5.5, y: 8.3), CGPoint(x: 5.5, y: 12.5), CGPoint(x: 22.5, y: 12.5), CGPoint(x: 22.5, y: 8.3)],
        "chatgpt": [CGPoint(x: 23.5, y: 20.6), CGPoint(x: 23.5, y: 13.5), CGPoint(x: 22.5, y: 13.5), CGPoint(x: 22.5, y: 8.3)],
    ]

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

    /// 5E: the lift takes someone to a storey, waits, and comes back down; rides close together share a trip.
    func ride(_ key: String, to k: Int) {
        var l = life.lifts[key] ?? CampusLife.Lift()
        if !l.queue.contains(k), l.target != CGFloat(k) * 30 + 2, l.queue.count < 3 { l.queue.append(k) }
        life.lifts[key] = l
    }

    // MARK: every frame

    func tickLife(_ dt: Double) {
        // 5A: the sky and the light follow the clock (looked at every few seconds)
        life.clockAcc += dt
        if life.clockAcc >= 5 {
            life.clockAcc = 0
            life.daylight = CGFloat(CampusSignals.daylight(hour: life.hourOverride ?? CampusSignals.hour(Date())))
        }
        if life.sky == nil {
            let s = SKSpriteNode(texture: Self.daySkyTexture); s.zPosition = -999; cam.addChild(s); life.sky = s
            // night is a thin blue veil (an ordinary blend, so it never goes darker than its alpha), under the lamps' light
            let sh = SKSpriteNode(color: SKColor(red: 0.06, green: 0.07, blue: 0.24, alpha: 1), size: CGSize(width: 10, height: 10))
            sh.zPosition = 2995; cam.addChild(sh); life.shade = sh
        }
        let full = CGSize(width: size.width * 1.02, height: size.height * 1.02)
        life.sky?.size = full; life.sky?.alpha = life.daylight
        life.shade?.size = full; life.shade?.alpha = (1 - life.daylight) * 0.3
        content.childNode(withName: "lamplight")?.alpha = 0.3 + 0.65 * (1 - life.daylight)
        animateLayer(clock)
        // 5E: the lifts
        for (key, var l) in life.lifts {
            if l.hold > 0 { l.hold -= dt; if l.hold <= 0 { l.target = 0 } }
            else if l.z == l.target, l.target == 0, !l.queue.isEmpty { l.target = CGFloat(l.queue.removeFirst()) * 30 + 2 }
            if l.z != l.target {
                let step = CGFloat(dt) * 45 * (animationsEnabled ? 1 : 1000)
                l.z = l.z < l.target ? min(l.target, l.z + step) : max(l.target, l.z - step)
                if l.z == l.target, l.target > 0 { l.hold = 1.6 }
            }
            life.lifts[key] = l
            life.cars[key]?.position.y = l.z * 1.08 * px
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
