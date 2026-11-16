import SpriteKit

/// The Office worlds (campus and floors) are blocky all the way down: rings, shadows and hover marks on the ground are
/// iso tiles, a 2:1 diamond with hard corners, never an ellipse. Orbit stays round.
enum Blocky {
    /// A diamond lies smaller in its box than an ellipse does: this much larger, it covers about the same ground.
    static let grow: CGFloat = 1.2

    /// A 2:1 iso tile `width` × `height` (scene points), centred on its origin.
    static func tile(_ width: CGFloat, _ height: CGFloat) -> CGPath {
        let w = width / 2, h = height / 2, path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 0, y: h), CGPoint(x: w, y: 0), CGPoint(x: 0, y: -h), CGPoint(x: -w, y: 0)])
        path.closeSubpath()
        return path
    }

    /// The outline of a tile on the floor, mitred: a status ring, a selection or a hover mark. `width` × `height` is the
    /// box an ellipse of the old design took; the tile grows to cover the same ground.
    static func ring(_ width: CGFloat, _ height: CGFloat, color: SKColor, lineWidth: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(path: tile(width * grow, height * grow))
        n.fillColor = .clear; n.strokeColor = color; n.lineWidth = lineWidth
        n.lineJoin = .miter; n.miterLimit = 10; n.isAntialiased = false
        return n
    }

    /// A shadow under someone's feet: a dark tile.
    static func shadow(_ width: CGFloat, _ height: CGFloat, alpha: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(path: tile(width * grow, height * grow))
        n.fillColor = SKColor(white: 0, alpha: alpha); n.strokeColor = .clear; n.isAntialiased = false
        return n
    }
}
