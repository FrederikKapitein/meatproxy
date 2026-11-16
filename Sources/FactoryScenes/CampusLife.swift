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
    /// what has been seen, so only what is new plays: deliveries, helpers, projects being built, the weather
    var primed = false
    var delivered: [String: Date] = [:]
    var helpers: Set<String> = []
    var building: Set<String> = []
    var weather: [String: CampusSignals.Weather] = [:]
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
        // what lasts: the weather, new projects, deploys
        var weather: [String: CampusSignals.Weather] = ["engine": CampusSignals.weather(servers: world.serverSummary)]
        for b in world.buildings { weather[b.provider.rawValue] = CampusSignals.weather(b, now: now) }
        var building = Set(world.projects.filter { CampusSignals.underConstruction($0, now: now) }.map(\.id))
        var deploying = Set(world.buildings.filter { $0.projects.contains { CampusSignals.deploying($0, now: now) } }.map(\.provider.rawValue))
        if life.demo {
            weather["chatgpt"] = .rain
            if let s = storeys.first(where: { $0.storey.building == "claude" && $0.storey.kind == "project" && $0.storey.index > 0 }) { building.insert(s.project) }
            deploying.insert("claude")
        }
        let sig = weather.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }.joined(separator: ",")
            + "|" + building.sorted().joined(separator: ",") + "|" + deploying.sorted().joined(separator: ",")
        if sig != life.sig || life.nodes.isEmpty {
            life.sig = sig
            drawLife(weather: weather, building: building, deploying: deploying)
        }
        // moments: a delivery, a ribbon, a lift ride, the sun after rain
        if life.primed {
            for (key, w) in weather where w == .clear && (life.weather[key] ?? .clear) != .clear { sunAfterRain(key) }
            for id in life.building.subtracting(building) where world.project(id: id) != nil { cutRibbon(id) }
            for p in world.projects {
                guard let s = storeys.first(where: { $0.project == p.id }) else { continue }
                if let last = CampusSignals.deliveries(p, after: life.delivered[p.id] ?? now).last {
                    life.delivered[p.id] = last; deliver(from: s.storey)
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
        life.building = building
        life.weather = weather
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

    private func drawLife(weather: [String: CampusSignals.Weather], building: Set<String>, deploying: Set<String>) {
        for n in life.nodes { n.removeFromParent() }
        life.nodes = []; life.ground.removeAllChildren()
        // keep what the Status layer and the moments in the air explain; the rest is drawn anew below
        let keep = Set(life.layerNodes.map(ObjectIdentifier.init))
        life.hotspots.removeAll { h in h.node.parent == nil || (!keep.contains(ObjectIdentifier(h.node)) && h.node.name != "moment") }
        let w = shownWorld
        // 5B: a cloud over a building, rain from it while something is broken
        for (key, wx) in weather where wx != .clear {
            guard let host = key == "engine" ? overlays["engine"] : layer(key, storey: nil), let at = cloudPoint(key) else { continue }
            let c = cloud(rain: wx == .rain); c.position = scenePoint(at); c.zPosition = 0.9
            host.addChild(c); life.nodes.append(c)
            explain(c, weatherWords(key, wx, w))
        }
        // 5D: scaffolding round a new project's storey and a crane on its tower's roof
        var cranes: Set<String> = []
        for (st, id) in storeys where building.contains(id) {
            guard let host = layer(st.building, storey: st.index) else { continue }
            let sc = scaffold(st); host.addChild(sc); life.nodes.append(sc)
            cranes.insert(st.building)
            explain(sc, ("Under construction: \(w.project(id: id)?.name ?? "a new project")", "A new project: the scaffold comes down when its first session is done"))
        }
        for key in cranes {
            guard let host = layer(key, storey: nil), let c = crane(key) else { continue }
            host.addChild(c); life.nodes.append(c)
            let names = storeys.filter { $0.storey.building == key && building.contains($0.project) }.compactMap { w.project(id: $0.project)?.name }
            explain(c, ("Crane", "Building " + names.joined(separator: ", ") + ": a new project's first session is running"))
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

    /// What the weather over a building says, in words.
    private func weatherWords(_ key: String, _ wx: CampusSignals.Weather, _ w: World) -> (String, String) {
        if key == "engine" {
            let down = w.servers.filter { $0.state == .down }.map(\.name), warn = w.servers.filter { $0.state == .warn }.map(\.name)
            return wx == .rain ? ("Rain over the Server room", "Down: " + down.joined(separator: ", ")) : ("Clouds over the Server room", "Warning: " + warn.joined(separator: ", "))
        }
        let b = Provider(rawValue: key).flatMap { w.building($0) }
        let red = b?.projects.filter { $0.github?.ciFailing == true }.map(\.name) ?? []
        let broken = b?.projects.filter { $0.github == nil && CampusSignals.broken($0, now: w.now) }.map(\.name) ?? []
        var line = [String]()
        if !red.isEmpty { line.append("CI on main is red: " + red.joined(separator: ", ")) }
        if !broken.isEmpty { line.append("A session ended with a failed test or push: " + broken.joined(separator: ", ")) }
        return ("Rain over \(Provider(rawValue: key)?.displayName ?? key)", line.isEmpty ? "Something is broken" : line.joined(separator: " · "))
    }

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

    /// Where a building's cloud hangs, in art units: over a tower's antenna, over the Server room's sign.
    private func cloudPoint(_ key: String) -> CGPoint? {
        if key == "engine" { return Self.artP(22.5, 5.5, 62) }
        guard let t = art?.towers.first(where: { $0.building == key }) else { return nil }
        return CGPoint(x: t.antenna.x + 6, y: t.antenna.y - 16)
    }

    /// A blocky cloud: three slabs, grey and low with rain under it, light without.
    private func cloud(rain: Bool) -> SKNode {
        let n = SKNode()
        let col = rain ? SKColor(red: 0.6, green: 0.62, blue: 0.72, alpha: 1) : SKColor(red: 0.86, green: 0.87, blue: 0.93, alpha: 1)
        let top = rain ? SKColor(red: 0.72, green: 0.74, blue: 0.83, alpha: 1) : SKColor(white: 0.97, alpha: 1)
        for (x, y, w, h) in [(-18.0, 0.0, 36.0, 9.0), (-11.0, 7.0, 16.0, 8.0), (1.0, 6.0, 12.0, 7.0)] {
            let r = SKShapeNode(rect: CGRect(x: x * px, y: y * px, width: w * px, height: h * px), cornerRadius: 2 * px)
            r.fillColor = col; r.strokeColor = Self.ink; r.lineWidth = 0.9 * px
            let hi = SKShapeNode(rect: CGRect(x: (x + 1.5) * px, y: (y + h - 2.6) * px, width: (w - 3) * px, height: 1.4 * px))
            hi.fillColor = top; hi.strokeColor = .clear
            r.addChild(hi); n.addChild(r)
        }
        if rain {
            let e = SKEmitterNode()
            e.particleTexture = Self.dropTexture
            e.particleBirthRate = 26; e.particleLifetime = 0.55
            e.emissionAngle = -.pi / 2 - 0.12; e.emissionAngleRange = 0.04
            e.particleSpeed = 70 * px; e.particleSpeedRange = 8 * px
            e.particleSize = CGSize(width: 1 * px, height: 5 * px)
            e.particleColor = SKColor(red: 0.62, green: 0.78, blue: 1, alpha: 1); e.particleColorBlendFactor = 1; e.particleAlpha = 0.75
            e.particlePositionRange = CGVector(dx: 30 * px, dy: 0)
            e.position = CGPoint(x: 0, y: -1 * px); e.zPosition = -0.1
            e.advanceSimulationTime(1)
            n.addChild(e)
        }
        if animationsEnabled {
            n.run(.repeatForever(.sequence([.moveBy(x: 5 * px, y: 0, duration: 4), .moveBy(x: -5 * px, y: 0, duration: 4)])))
        }
        return n
    }

    private func line(_ pts: [CGPoint], _ color: SKColor, _ width: CGFloat) -> SKShapeNode {
        let p = CGMutablePath(); p.addLines(between: pts.map(scenePoint))
        let n = SKShapeNode(path: p); n.strokeColor = color; n.lineWidth = width * px; n.lineCap = .square
        return n
    }

    /// Scaffolding on a storey's two faces: poles and planks, the wood of the plot's scaffold.
    private func scaffold(_ s: CampusArt.Storey) -> SKNode {
        let n = SKNode(), wood = SKColor(red: 0.79, green: 0.64, blue: 0.42, alpha: 1)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        for f in s.faces where f.count == 4 {
            // f: bottom-left, bottom-right, top-right, top-left
            for t in stride(from: 0.0, through: 1.0, by: 1.0 / 3) { n.addChild(line([lerp(f[0], f[1], t), lerp(f[3], f[2], t)], wood, 1.3)) }
            for h in [0.3, 0.68] {
                let a = lerp(f[0], f[3], h), b = lerp(f[1], f[2], h)
                n.addChild(line([a, b], Self.ink, 2.6)); n.addChild(line([a, b], wood, 1.6))
            }
        }
        n.zPosition = 0.3
        return n
    }

    /// A tower crane on the roof: a lattice mast and a jib that swings slowly (a turn, seen from the side), its hook
    /// hanging over the storey being built.
    private func crane(_ key: String) -> SKNode? {
        guard let top = art?.storeys.filter({ $0.building == key }).max(by: { $0.index < $1.index }), top.faces.count == 2 else { return nil }
        let a3 = top.faces[0][3], b2 = top.faces[1][2]
        let foot = CGPoint(x: (a3.x + b2.x) / 2 + 12, y: (a3.y + b2.y) / 2 - 4)
        let n = SKNode(); n.position = scenePoint(foot); n.zPosition = 0.8
        let white = SKColor(red: 0.91, green: 0.93, blue: 0.95, alpha: 1), red = SKColor(red: 0.88, green: 0.28, blue: 0.23, alpha: 1)
        let mastH: CGFloat = 52
        let mast = SKShapeNode(rect: CGRect(x: -2 * px, y: 0, width: 4 * px, height: mastH * px))
        mast.fillColor = white; mast.strokeColor = Self.ink; mast.lineWidth = 0.8 * px
        for k in stride(from: 4.0, to: Double(mastH), by: 8) {
            let p = CGMutablePath(); p.move(to: CGPoint(x: -2 * px, y: k * px)); p.addLine(to: CGPoint(x: 2 * px, y: (k + 4) * px))
            let x = SKShapeNode(path: p); x.strokeColor = Self.ink.withAlphaComponent(0.6); x.lineWidth = 0.5 * px; mast.addChild(x)
        }
        n.addChild(mast)
        let jib = SKNode(); jib.position = CGPoint(x: 0, y: mastH * px)
        let arm = SKShapeNode(rect: CGRect(x: -40 * px, y: 0, width: 56 * px, height: 3.4 * px))
        arm.fillColor = white; arm.strokeColor = Self.ink; arm.lineWidth = 0.8 * px
        let tip = SKShapeNode(rect: CGRect(x: -40 * px, y: 0, width: 6 * px, height: 3.4 * px)); tip.fillColor = red; tip.strokeColor = .clear
        let weight = SKShapeNode(rect: CGRect(x: 9 * px, y: -4 * px, width: 7 * px, height: 4 * px)); weight.fillColor = SKColor(white: 0.45, alpha: 1); weight.strokeColor = Self.ink; weight.lineWidth = 0.6 * px
        let cab = SKShapeNode(rect: CGRect(x: -3 * px, y: -5 * px, width: 6 * px, height: 5 * px)); cab.fillColor = red; cab.strokeColor = Self.ink; cab.lineWidth = 0.6 * px
        let hookLine = SKShapeNode(rect: CGRect(x: -33.3 * px, y: -24 * px, width: 0.6 * px, height: 24 * px)); hookLine.fillColor = Self.ink; hookLine.strokeColor = .clear
        let block = SKShapeNode(rect: CGRect(x: -35.5 * px, y: -28 * px, width: 5 * px, height: 4 * px)); block.fillColor = SKColor(red: 0.79, green: 0.64, blue: 0.42, alpha: 1); block.strokeColor = Self.ink; block.lineWidth = 0.6 * px
        for c in [hookLine, block, arm, tip, weight, cab] { jib.addChild(c) }
        n.addChild(jib)
        if animationsEnabled {
            // a slow swing: the jib turns towards you and away (its length on screen changes), and the load sways
            let swing = SKAction.customAction(withDuration: 14) { node, t in node.xScale = cos(t / 14 * 2 * .pi) * 0.85 + 0.15 }
            jib.run(.repeatForever(swing))
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
    func deliver(from s: CampusArt.Storey) {
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
        explain(drone, ("Delivery", "A pull request was merged"))
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

    /// 5D: a new project's first session is done: the red ribbon across its storey snaps and falls away.
    func cutRibbon(_ id: String) {
        guard animationsEnabled, let s = storeys.first(where: { $0.project == id })?.storey, s.faces.count == 2 else { return }
        let f = s.faces[0], off = stacks[s.building]?.offset(s.index) ?? 0
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - off) }
        let l = mid(f[0], f[3]), r = mid(f[1], f[2]), c = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        let red = SKColor(red: 0.88, green: 0.28, blue: 0.23, alpha: 1)
        for (a, b, dx) in [(l, c, -1.0), (c, r, 1.0)] {
            let half = line([a, b], red, 3); half.zPosition = 6
            effects.addChild(half)
            half.run(.sequence([.wait(forDuration: 0.3), .group([.moveBy(x: dx * 8 * px, y: -14 * px, duration: 0.8), .fadeOut(withDuration: 0.8)]), .removeFromParent()]))
        }
        let e = SKEmitterNode()
        e.particleTexture = Self.dropTexture; e.numParticlesToEmit = 30; e.particleBirthRate = 120
        e.particleLifetime = 1.4; e.emissionAngle = .pi / 2; e.emissionAngleRange = 1.4
        e.particleSpeed = 40 * px; e.particleSpeedRange = 15 * px; e.yAcceleration = -50 * px
        e.particleSize = CGSize(width: 1.5 * px, height: 2.5 * px); e.particleRotationSpeed = 6
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: [Self.wait, Self.cyan, red, Self.okGreen], times: [0, 0.33, 0.66, 1])
        e.particleColorBlendFactor = 1
        e.position = scenePoint(c); e.zPosition = 7
        effects.addChild(e)
        e.run(.sequence([.wait(forDuration: 2.5), .removeFromParent()]))
    }

    /// 5B: the weather cleared: a short sun where the cloud was.
    private func sunAfterRain(_ key: String) {
        guard animationsEnabled, let at = cloudPoint(key) else { return }
        let g = glow(at, size: CGSize(width: 60, height: 60), color: SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)); g.alpha = 0; g.zPosition = 3
        effects.addChild(g)
        g.run(.sequence([.group([.fadeAlpha(to: 0.8, duration: 0.6), .scale(to: 1.3, duration: 1.6)]), .fadeOut(withDuration: 1.2), .removeFromParent()]))
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
