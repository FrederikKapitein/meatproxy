import SpriteKit
import FactoryCore

/// The shared camera and input for every world: one grammar (D24). Click flies in, scroll or pinch zooms continuously,
/// drag pans, Esc goes one level up. Art units (the blocky projection at S = 1) are drawn `px` points large.
public class WorldScene: SKScene {
    let cam = SKCameraNode()
    let content = SKNode()
    var homeScale: CGFloat = 1
    var homeCenter: CGPoint = .zero
    var homeRect: CGRect = .zero
    let px: CGFloat = 2
    var dragged = false
    public var animationsEnabled = true
    /// Room the HUD panels take on the left and right, in view points: home framing keeps the world clear of them.
    public var insets: (left: CGFloat, right: CGFloat) = (330, 0) { didSet { recomputeHome() } }
    /// Room the HUD bars take at the top (breadcrumb, world switch) and bottom (levels, zoom dock), in view points.
    public var bars: (top: CGFloat, bottom: CGFloat) = (64, 60) { didSet { recomputeHome() } }
    private var usableHeight: CGFloat { max(size.height - bars.top - bars.bottom, size.height * 0.5) }
    /// the camera's y offset that centres the target between the bars
    private func barShift(_ scale: CGFloat) -> CGFloat { (bars.top - bars.bottom) / 2 * scale }

    public override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 7 / 255, green: 7 / 255, blue: 12 / 255, alpha: 1)
        addChild(content)
        addChild(cam)
        camera = cam
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// art units (y down) → scene points (y up)
    func scenePoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * px, y: -p.y * px) }
    func artPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / px, y: -p.y / px) }

    /// A sprite over a rectangle in art units (top-left corner and size).
    func place(_ tex: SKTexture, _ r: CGRect, z: CGFloat, name: String? = nil) -> SKSpriteNode {
        let n = SKSpriteNode(texture: tex)
        n.anchorPoint = CGPoint(x: 0, y: 1)
        n.size = CGSize(width: r.width * px, height: r.height * px)
        n.position = scenePoint(r.origin)
        n.zPosition = z
        n.name = name
        return n
    }
    func place(_ img: ArtImage?, z: CGFloat, blend: SKBlendMode = .alpha) -> SKSpriteNode? {
        guard let img else { return nil }
        let n = place(SKTexture(cgImage: img.image), img.rect, z: z)
        n.blendMode = blend
        return n
    }

    // MARK: camera

    func setHome(_ artRect: CGRect, fill: CGFloat = 1.04) {
        let r = CGRect(x: artRect.minX * px, y: -artRect.maxY * px, width: artRect.width * px, height: artRect.height * px)
        homeRect = r; homeFill = fill
        recomputeHome()
    }
    private var homeFill: CGFloat = 1.04

    func recomputeHome() {
        guard size.width > 0, homeRect.width > 0 else { return }
        let usable = max(size.width - insets.left - insets.right, size.width * 0.5)
        homeScale = max(homeRect.width / usable, homeRect.height / usableHeight) * homeFill
        homeCenter = CGPoint(x: homeRect.midX - (insets.left - insets.right) / 2 * homeScale, y: homeRect.midY + barShift(homeScale))
    }

    /// Like fly(toScene:), but the target sits in the part of the view the panels leave free. `right`: the room a panel
    /// takes on the right at the target's level, when it differs from the home framing's (the inspector).
    func flyClear(_ r: CGRect, padding: CGFloat = 1.3, right: CGFloat? = nil, completion: (() -> Void)? = nil) {
        let rightInset = right ?? insets.right
        let usable = max(size.width - insets.left - rightInset, size.width * 0.5)
        let s = min(max(max(r.width / usable, r.height / usableHeight) * padding, homeScale * 0.08), homeScale * 1.2)
        fly(center: CGPoint(x: r.midX - (insets.left - rightInset) / 2 * s, y: r.midY + barShift(s)), scale: s, completion: completion)
    }

    var zoomRatio: CGFloat { cam.xScale / max(homeScale, 0.0001) }

    /// The part of the scene the camera sees, in scene coordinates.
    public var visibleRect: CGRect {
        CGRect(x: cam.position.x - size.width * cam.xScale / 2, y: cam.position.y - size.height * cam.yScale / 2,
               width: size.width * cam.xScale, height: size.height * cam.yScale)
    }

    func fly(center: CGPoint, scale: CGFloat, duration: TimeInterval = 0.7, completion: (() -> Void)? = nil) {
        cam.removeAllActions()
        // a view that draws no frames (paused, hidden, its display asleep) runs no actions: jump there, so what waits on the flight still happens
        guard animationsEnabled, view.map({ $0.drawsFrames }) ?? true else { cam.position = center; cam.setScale(scale); completion?(); return }
        let m = SKAction.move(to: center, duration: duration); m.timingMode = .easeInEaseOut
        let s = SKAction.scale(to: scale, duration: duration); s.timingMode = .easeInEaseOut
        camFlightSeq += 1
        let seq = camFlightSeq
        cam.run(.sequence([.group([m, s]), .run { completion?() }]), withKey: Self.flightKey)
        // frames can stop without the view knowing (a sleeping display, a covered window, a stalled fade): a flight
        // still lands, so what waits on it (a floor, a level, the HUD) never waits on a frame that does not come
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.35) { [weak self] in
            guard let self, self.camFlightSeq == seq, self.cam.action(forKey: Self.flightKey) != nil else { return }
            self.cam.removeAction(forKey: Self.flightKey)
            self.cam.position = center; self.cam.setScale(scale)
            completion?()
        }
    }
    private static let flightKey = "flight"
    private var camFlightSeq = 0

    func fly(toScene r: CGRect, padding: CGFloat = 1.3, completion: (() -> Void)? = nil) {
        let s = max(r.width / size.width, r.height / size.height) * padding
        fly(center: CGPoint(x: r.midX, y: r.midY), scale: min(max(s, homeScale * 0.08), homeScale * 1.2), completion: completion)
    }

    func goHome(duration: TimeInterval = 0.7) { fly(center: homeCenter, scale: homeScale, duration: duration) }

    public func zoom(by factor: CGFloat, around p: CGPoint? = nil) {
        cam.removeAllActions()
        let old = cam.xScale, new = min(max(old * factor, homeScale * 0.08), homeScale * 1.6), a = p ?? cam.position
        cam.position = CGPoint(x: a.x + (cam.position.x - a.x) * new / old, y: a.y + (cam.position.y - a.y) * new / old)
        cam.setScale(new)
        didZoom(zoomingIn: factor < 1)
    }

    public func pan(dx: CGFloat, dy: CGFloat) {
        cam.removeAllActions()
        cam.position = CGPoint(x: cam.position.x - dx * cam.xScale, y: cam.position.y + dy * cam.xScale)
        didPan()
    }

    /// The level follows the zoom: subclasses decide what is "in" at this zoom.
    func didZoom(zoomingIn: Bool) {}
    func didPan() {}
    /// What a right-click at a scene point is on (D72): a scene answers with a target, or nil for the empty world.
    func contextTarget(at scenePoint: CGPoint) -> ContextTarget? { nil }
    /// The right-click's way out: what it is on, and where (view points from the top left).
    public var onContext: ((ContextTarget?, CGPoint) -> Void)?
    /// The wheel turned (points, or lines when not precise): a scene that uses it for something else says true and
    /// nothing zooms.
    func wheel(_ dy: CGFloat, precise: Bool) -> Bool { false }
    func click(at scenePoint: CGPoint) {}
    /// The pointer moved over the scene (nil: it left the view, went over a HUD panel, or a drag started). Scenes
    /// highlight what a click there would pick and set `hovering`. Things move under a still pointer, so scenes may
    /// call it again every frame with `pointerInScene`.
    func hover(at scenePoint: CGPoint?) {}

    // MARK: hover

    /// Where the pointer is over the view, in view points; nil when it is outside, over a HUD panel, or dragging.
    public private(set) var pointer: CGPoint?
    /// The pointer in scene coordinates (it changes when the camera moves under a still pointer).
    var pointerInScene: CGPoint? { guard let p = pointer, view != nil else { return nil }; return convertPoint(fromView: p) }
    /// Something clickable is under the pointer: the view shows a pointing hand.
    public var hovering = false { didSet { if hovering != oldValue { onHoverChange?(hovering) } } }
    public var onHoverChange: ((Bool) -> Void)?
    /// The view's way in: the pointer moved to a point of the view (nil: away).
    public func pointerMoved(to p: CGPoint?) {
        pointer = p
        hover(at: pointerInScene)
        if p == nil { hovering = false }
    }
    /// A line `points` wide on screen, whatever the zoom (for nodes in `content`).
    func screenWidth(_ points: CGFloat) -> CGFloat { points * cam.xScale }
    public func up() {}
    public func next() {}

    public override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, homeRect.width > 0 else { sizeChanged(); return }
        let atHome = abs(cam.xScale - homeScale) < 0.0001
        recomputeHome()
        if atHome { cam.setScale(homeScale); cam.position = homeCenter }
        sizeChanged()
    }
    func sizeChanged() {}

    // MARK: input

    #if os(macOS)
    public override func mouseDown(with event: NSEvent) { dragged = false }
    public override func mouseMoved(with event: NSEvent) { pointerMoved(to: view.map { $0.convert(event.locationInWindow, from: nil) }) }
    public override func mouseExited(with event: NSEvent) { pointerMoved(to: nil) }
    public override func mouseDragged(with event: NSEvent) {
        if abs(event.deltaX) + abs(event.deltaY) > 0.5 { if !dragged { pointerMoved(to: nil) }; dragged = true }
        pan(dx: event.deltaX, dy: event.deltaY)
    }
    public override func mouseUp(with event: NSEvent) { if !dragged { click(at: event.location(in: self)) } }
    public override func rightMouseDown(with event: NSEvent) {
        guard let v = view else { return }
        let q = v.convert(event.locationInWindow, from: nil)
        onContext?(contextTarget(at: event.location(in: self)), CGPoint(x: q.x, y: v.isFlipped ? q.y : v.bounds.height - q.y))
    }
    public override func scrollWheel(with event: NSEvent) {
        if wheel(event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas) { return }
        let k: CGFloat = event.hasPreciseScrollingDeltas ? 0.006 : 0.06
        zoom(by: exp(-event.scrollingDeltaY * k), around: event.location(in: self))
    }
    public override func magnify(with event: NSEvent) { zoom(by: 1 / (1 + event.magnification), around: event.location(in: self)) }
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: up()
        case 24, 69: zoom(by: 0.8)
        case 27, 78: zoom(by: 1.25)
        case 45: next()
        default: super.keyDown(with: event)
        }
    }
    #endif
}

/// What a right-click is on (D72): the HUD turns it into a menu.
public enum ContextTarget: Equatable, Sendable {
    case building(String)          // claude, chatgpt, engine
    case project(String)           // a storey, or the floor you are on
    case session(String)           // someone on the roads or at a desk
    case server(Int)               // a rack, by rack order
    case fountain
}
