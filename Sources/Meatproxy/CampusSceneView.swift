import SwiftUI
import SpriteKit
import FactoryScenes
import AppKit

/// Hosts the worlds (Office and Orbit) and hands them the mouse, trackpad and keyboard.
struct WorldView: NSViewRepresentable {
    let controller: WorldController

    func makeNSView(context: Context) -> WorldSKView {
        let v = WorldSKView()
        v.preferredFramesPerSecond = 60
        controller.attach(v)
        return v
    }

    func updateNSView(_ nsView: WorldSKView, context: Context) {}
}

final class WorldSKView: SKView {
    override var acceptsFirstResponder: Bool { true }
    private var occlusion: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if let o = occlusion { NotificationCenter.default.removeObserver(o); occlusion = nil }
        guard let window else { return }
        // Hidden, minimised or on another desktop: no frames to draw, so stop asking for them.
        occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            self?.updatePause()
        }
        updatePause()
    }

    private func updatePause() {
        isPaused = !(window?.occlusionState.contains(.visible) ?? false)
    }
    // hover: the pointer's moves reach the scene while it is over the world, not over a HUD panel (WorldScene.hover)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func presentScene(_ scene: SKScene?) { super.presentScene(scene); hook(scene) }
    override func presentScene(_ scene: SKScene, transition: SKTransition) { super.presentScene(scene, transition: transition); hook(scene) }
    private func hook(_ s: SKScene?) {
        (s as? WorldScene)?.onHoverChange = { [weak self] _ in self?.updateCursor() }
        updateCursor()
    }

    private var dragging = false, overHUD = false
    /// A pointing hand over what you can click, a closed hand while you drag the world, the arrow otherwise. Over the
    /// HUD panels SwiftUI decides.
    func updateCursor() {
        guard !overHUD, window?.isKeyWindow == true else { return }
        (dragging ? NSCursor.closedHand : (scene as? WorldScene)?.hovering == true ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
    override func cursorUpdate(with event: NSEvent) { if overHUD { super.cursorUpdate(with: event) } else { updateCursor() } }

    /// Is the world itself under this point of the window, or a HUD panel floating over it?
    private func worldIsUnder(_ windowPoint: NSPoint) -> Bool {
        guard let root = window?.contentView else { return true }
        let p = root.superview?.convert(windowPoint, from: nil) ?? windowPoint
        guard let hit = root.hitTest(p) else { return true }
        return hit === self || hit.isDescendant(of: self)
    }

    override func mouseMoved(with event: NSEvent) {
        let wasOver = overHUD
        overHUD = !worldIsUnder(event.locationInWindow)
        (scene as? WorldScene)?.pointerMoved(to: overHUD ? nil : convert(event.locationInWindow, from: nil))
        if !overHUD { updateCursor() } else if !wasOver { NSCursor.arrow.set() }
    }
    override func mouseExited(with event: NSEvent) { (scene as? WorldScene)?.pointerMoved(to: nil); overHUD = false }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); scene?.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) {
        if !dragging { dragging = true; updateCursor() }
        scene?.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        scene?.mouseUp(with: event)
        if dragging { dragging = false }
        (scene as? WorldScene)?.pointerMoved(to: convert(event.locationInWindow, from: nil))
        updateCursor()
    }
    override func scrollWheel(with event: NSEvent) { scene?.scrollWheel(with: event) }
    override func magnify(with event: NSEvent) { scene?.magnify(with: event) }
    override func keyDown(with event: NSEvent) { scene?.keyDown(with: event) }
}
