import SpriteKit

import FactoryCore

/// The Status layer (D69) as a map mode (Spel+, A6): switched on, the campus goes grey, like the map view of a sim game,
/// and only status keeps its colour. Each service stands as a pin with a shape and a word on its own building (Claude
/// on the Claude tower, ChatGPT, whatever the status page calls it, on the ChatGPT tower), the servers on the Server
/// room, a red CI on its floor; and a pool of its colour lights the building from below. Never a lamp post. Off, the
/// campus is in colour again.
extension CampusScene {
    public func setStatusLayer(_ on: Bool) {
        life.layerOn = on
        drawStatusLayer(shownWorld)
    }

    /// One shader greys every sprite of the world (a map's grey: its brightness, a little darker, a hint of cool).
    static let mapShader = SKShader(source: """
        void main() {
            vec4 c = texture2D(u_texture, v_tex_coord);
            float l = dot(c.rgb, vec3(0.3, 0.59, 0.11)) * 0.78;
            gl_FragColor = vec4(mix(c.rgb, vec3(l * 0.96, l * 0.98, l * 1.06), 0.88), c.a);
        }
        """)

    /// Greys the world's sprites, or gives them their colour back.
    func greyWorld(_ on: Bool) {
        content.enumerateChildNodes(withName: "//*") { n, _ in (n as? SKSpriteNode).map { s in if s.blendMode == .alpha { s.shader = on ? Self.mapShader : nil } } }
    }

    func drawStatusLayer(_ world: World) {
        for n in life.layerNodes { n.removeFromParent() }
        // (a repaint of the campus forgets its layer nodes: the old layer goes by its name)
        childNode(withName: "statusLayer")?.removeFromParent()
        life.hotspots.removeAll { $0.node.parent == nil }
        life.layerNodes = []; life.layerLamps = []
        guard art != nil else { return }
        greyWorld(life.layerOn)
        guard life.layerOn else { return }
        let now = world.now
        var pins: [(key: String, at: CGPoint?, state: ServiceStatus.State, title: String, word: String, line: String)] = []
        // the providers' services on their towers; anything else (GitHub) only when it is not well, by the pillar
        for s in world.services {
            let st = s.shown(now: now), name = s.name.lowercased(), rt = (s.runtime ?? "").lowercased()
            let key: String? = rt == "claude" || name.contains("claude") || name.contains("anthropic") ? "claude"
                : rt == "codex" || name.contains("openai") || name.contains("chatgpt") ? "chatgpt" : nil
            // the service by its own name (OpenAI, not the tower's ChatGPT): one word per thing
            let title = s.name
            let line = st == .unknown ? "Not read for a while: unknown" : st.rawValue.capitalized + (s.detail.isEmpty ? "" : " · " + s.detail)
            if let key { pins.append((key, nil, st, title, Self.word(st), line)) }
            else if st != .ok, let f = art?.fountain { pins.append(("fountain", CGPoint(x: f.x + 70, y: f.y - 40), st, title, Self.word(st), line)) }
        }
        // the servers on the Server room
        let sum = world.serverSummary
        if sum.connected {
            let st: ServiceStatus.State = sum.down > 0 ? .down : sum.warn > 0 ? .degraded : .ok
            let word = sum.down > 0 ? "\(sum.down) down" : sum.warn > 0 ? "\(sum.warn) warning" : "ok"
            pins.append(("engine", nil, st, "Servers", word, "\(world.servers.count) servers · \(sum.down) down · \(sum.warn) warning"))
        }
        // a red CI on its floor (a green one says nothing)
        for (st, id) in storeys {
            guard let p = world.project(id: id), let g = p.github, g.ciFailing,
                  let r = art?.plaques[st.building], st.index < r.count else { continue }
            let at = CGPoint(x: r[st.index].maxX + 4, y: r[st.index].minY)
            pins.append((st.building, at, .down, p.name, "CI red", "CI on main is red: " + g.failing.joined(separator: ", ")))
        }
        let layer = SKNode(); layer.zPosition = 6000; layer.name = "statusLayer"
        addChild(layer); life.layerNodes.append(layer)
        var lit: Set<String> = []
        for pin in pins {
            let col = Self.lampColour(pin.state)
            guard let n = buildings[pin.key] ?? (pin.key == "fountain" ? content.childNode(withName: "fountain") as? SKSpriteNode : nil) else { continue }
            let f = n.calculateAccumulatedFrame()
            // a pool of the state's colour under the building (once per building: the worst wins, it comes first below)
            if !lit.contains(pin.key), let fp = art?.footprints[pin.key == "fountain" ? "fountain" : "building:" + pin.key] {
                lit.insert(pin.key)
                let c = project(fp.midX, fp.midY)
                let g = glow(c, size: CGSize(width: (fp.width + fp.height) * 16 * 1.6, height: (fp.width + fp.height) * 8 * 1.6), color: col)
                g.alpha = pin.state == .ok ? 0.35 : 0.6; g.zPosition = -1
                layer.addChild(g)
            }
            // the pin: a stalk from the roof, a plate with a shape and a word
            // a tower's pin hangs by its roof on the left (its blade signs are on the right); a low building's above it
            let tower = pin.key == "claude" || pin.key == "chatgpt"
            let top = pin.at.map(scenePoint) ?? (tower ? CGPoint(x: f.minX + f.width * 0.2, y: f.maxY - f.height * 0.2) : CGPoint(x: f.midX, y: f.maxY))
            let plate = Self.pin(title: pin.title, word: pin.word, state: pin.state, color: col)
            let stalk = SKShapeNode(rectOf: CGSize(width: 2, height: 30)); stalk.fillColor = col; stalk.strokeColor = .clear
            stalk.position = CGPoint(x: 0, y: -15)
            let holder = SKNode(); holder.position = CGPoint(x: top.x, y: top.y + 34 * px)
            holder.addChild(stalk); holder.addChild(plate)
            plate.position = CGPoint(x: 0, y: 14)
            let dot = SKShapeNode(circleOfRadius: 4); dot.fillColor = col; dot.strokeColor = Self.ink; dot.lineWidth = 1.5
            dot.position = CGPoint(x: 0, y: -30); holder.addChild(dot)
            layer.addChild(holder)
            explain(plate, (pin.title, pin.line))
            life.layerLamps.append((plate, dot, pin.state))
        }
        scaleLayer()
    }

    static func word(_ s: ServiceStatus.State) -> String {
        switch s { case .ok: "ok"; case .degraded: "slow"; case .down: "down"; case .unknown: "unknown" }
    }

    /// A pin's plate: dark, an edge in its colour, a shape (✓ ok, ▲ slow, ■ down, ? unknown) and "Title · word".
    static func pin(title: String, word: String, state: ServiceStatus.State, color: SKColor) -> SKNode {
        let n = SKNode()
        let shape = SKLabelNode(text: state == .ok ? "✓" : state == .degraded ? "▲" : state == .down ? "■" : "?")
        shape.fontName = "Avenir Next Heavy"; shape.fontSize = 15; shape.fontColor = color; shape.verticalAlignmentMode = .center; shape.horizontalAlignmentMode = .left
        let label = SKLabelNode(text: "\(title) · \(word)")
        label.fontName = "Avenir Next Demi Bold"; label.fontSize = 15; label.fontColor = SKColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .left
        let w = shape.frame.width + label.frame.width + 26, h: CGFloat = 30
        let bg = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 6)
        bg.fillColor = SKColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 0.94); bg.strokeColor = color; bg.lineWidth = 2
        // the under-edge of Spel+'s plates
        let edge = SKShapeNode(rect: CGRect(x: -w / 2 + 2, y: -h / 2 - 3, width: w - 4, height: 3), cornerRadius: 1.5)
        edge.fillColor = color.withAlphaComponent(0.6); edge.strokeColor = .clear
        shape.position = CGPoint(x: -w / 2 + 10, y: 0); label.position = CGPoint(x: shape.position.x + shape.frame.width + 6, y: 0)
        n.addChild(edge); n.addChild(bg); n.addChild(shape); n.addChild(label)
        return n
    }

    /// The pins keep their size on screen at any zoom.
    func scaleLayer() {
        let k = cam.xScale
        for l in life.layerNodes { for c in l.children where !(c is SKSpriteNode) { c.setScale(k) } }
    }

    static func lampColour(_ s: ServiceStatus.State) -> SKColor {
        switch s {
        case .ok: return okGreen
        case .degraded: return warn
        case .down: return down
        case .unknown: return SKColor(white: 0.55, alpha: 1)
        }
    }

    /// Down breathes faster than slow; ok and unknown stay still; a still frame shows them all lit.
    func animateLayer(_ t: Double) {
        guard life.layerOn else { return }
        scaleLayer()
        for l in life.layerLamps {
            let a: CGFloat
            switch l.state {
            case .down: a = animationsEnabled ? CGFloat(0.55 + 0.45 * sin(t / 1.1 * 2 * .pi)) : 1
            case .degraded: a = animationsEnabled ? CGFloat(0.7 + 0.3 * sin(t / 2.4 * 2 * .pi)) : 1
            default: a = 1
            }
            l.glow.alpha = a
        }
    }
}
