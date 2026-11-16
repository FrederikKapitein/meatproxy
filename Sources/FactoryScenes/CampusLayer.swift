import SpriteKit
import FactoryCore

/// The Status layer (D69): switched on, the campus shows what the outside says. A row of lamps by the Server room, one
/// per status page you watch (green ok, amber degraded, red down, grey unknown), and on every floor with GitHub a small
/// CI lamp by its plaque. Off, the campus is calm again. Blocky: lamps are boxes, never rings.
extension CampusScene {
    public func setStatusLayer(_ on: Bool) {
        life.layerOn = on
        drawStatusLayer(shownWorld)
    }

    func drawStatusLayer(_ world: World) {
        for n in life.layerNodes { n.removeFromParent() }
        life.layerNodes = []; life.layerLamps = []
        guard life.layerOn, let art else { return }
        // the services, along the front of the Server room
        if let ov = overlays["engine"] {
            for (k, s) in world.services.enumerated() {
                let i = 19.8 + CGFloat(k) * 1.9, j: CGFloat = 8.9
                let n = SKNode(); n.zPosition = 1.2
                n.addChild(shape([Self.artP(i - 0.06, j + 0.06, 0), Self.artP(i + 0.06, j + 0.06, 0), Self.artP(i + 0.06, j + 0.06, 14), Self.artP(i - 0.06, j + 0.06, 14)], fill: Self.ink))
                let col = Self.lampColour(s.shown(now: world.now))
                let lamp = box(i - 0.22, j - 0.22, 14, i + 0.22, j + 0.22, 20, col)
                n.addChild(lamp)
                let g = glow(Self.artP(i, j, 17), size: CGSize(width: 18, height: 18), color: col); g.zPosition = 0.1
                n.addChild(g)
                let label = SKLabelNode(text: s.name.uppercased())
                label.fontName = "Menlo-Bold"; label.fontSize = 5.2 * px; label.fontColor = SKColor(white: 0.95, alpha: 1)
                label.position = scenePoint(CGPoint(x: Self.artP(i, j, 0).x, y: Self.artP(i, j, 0).y + 7)); label.verticalAlignmentMode = .center
                let plate = SKShapeNode(rectOf: CGSize(width: label.frame.width + 5 * px, height: 7.5 * px), cornerRadius: 1.5 * px)
                plate.fillColor = Self.ink.withAlphaComponent(0.85); plate.strokeColor = .clear; plate.position = label.position; plate.zPosition = -0.01
                n.addChild(plate); n.addChild(label)
                ov.addChild(n); life.layerNodes.append(n)
                life.layerLamps.append((lamp, g, s.shown(now: world.now)))
            }
        }
        // a CI lamp by the plaque of every floor GitHub knows
        for (st, id) in storeys {
            guard let p = world.project(id: id), let g = p.github, let host = layer(st.building, storey: st.index),
                  let rects = art.plaques[st.building], st.index < rects.count else { continue }
            let r = rects[st.index], c = CGPoint(x: r.minX - 1, y: r.midY)
            let state: ServiceStatus.State = g.ciFailing ? .down : .ok
            let col = Self.lampColour(state)
            let lamp = SKShapeNode(rectOf: CGSize(width: 6 * px, height: 6 * px))
            lamp.fillColor = col; lamp.strokeColor = Self.ink; lamp.lineWidth = 1 * px
            lamp.position = scenePoint(c); lamp.zPosition = 1.3
            let glowNode = glow(c, size: CGSize(width: 16, height: 16), color: col); glowNode.zPosition = 1.25
            host.addChild(glowNode); host.addChild(lamp)
            life.layerNodes.append(contentsOf: [lamp, glowNode])
            life.layerLamps.append((lamp, glowNode, state))
        }
    }

    /// A small box in art space, flat-shaded: its top, its front and its right face.
    private func box(_ i0: CGFloat, _ j0: CGFloat, _ z0: CGFloat, _ i1: CGFloat, _ j1: CGFloat, _ z1: CGFloat, _ col: SKColor) -> SKNode {
        let n = SKNode()
        func shade(_ f: CGFloat) -> SKColor { var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; col.getRed(&r, green: &g, blue: &b, alpha: &a); return SKColor(red: r * f, green: g * f, blue: b * f, alpha: 1) }
        n.addChild(shape([Self.artP(i0, j1, z0), Self.artP(i1, j1, z0), Self.artP(i1, j1, z1), Self.artP(i0, j1, z1)], fill: shade(0.82), stroke: Self.ink, width: 0.6 * px))
        n.addChild(shape([Self.artP(i1, j1, z0), Self.artP(i1, j0, z0), Self.artP(i1, j0, z1), Self.artP(i1, j1, z1)], fill: shade(0.66), stroke: Self.ink, width: 0.6 * px))
        n.addChild(shape([Self.artP(i0, j0, z1), Self.artP(i1, j0, z1), Self.artP(i1, j1, z1), Self.artP(i0, j1, z1)], fill: col, stroke: Self.ink, width: 0.6 * px))
        return n
    }

    static func lampColour(_ s: ServiceStatus.State) -> SKColor {
        switch s {
        case .ok: return okGreen
        case .degraded: return warn
        case .down: return down
        case .unknown: return SKColor(white: 0.55, alpha: 1)
        }
    }

    /// Down blinks, degraded breathes slowly, ok and unknown stay still; a still frame shows them all lit.
    func animateLayer(_ t: Double) {
        for l in life.layerLamps {
            let a: CGFloat
            switch l.state {
            case .down: a = !animationsEnabled || t.truncatingRemainder(dividingBy: 1.2) < 0.7 ? 1 : 0.25
            case .degraded: a = animationsEnabled ? CGFloat(0.65 + 0.35 * sin(t / 2.4 * 2 * .pi)) : 1
            default: a = 1
            }
            l.node.alpha = a; l.glow.alpha = (l.state == .unknown ? 0 : 0.5) * a
        }
    }
}
