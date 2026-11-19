import AppKit
import SpriteKit
import SwiftTerm

/// `SF_WINDOW_SHOT=out.png Meatproxy` (debug aid): after a few seconds the app draws its own window into a PNG
/// and quits: the world from SpriteKit first, the SwiftUI HUD on top. An environment variable, because AppKit treats
/// a path on the command line as a document to open. SF_WINDOW_SHOT_AFTER sets the wait, SF_WINDOW_SHOT_ACTION
/// can do a few things first, comma-separated, two seconds apart: "next" (fly to the next one that waits), "up",
/// "building:claude", "engine" (the Server room), "floor:<project id>", "session:<id>", "decision:<project id>|<D-id>", "workstream:<project id>|<W-id>", "orbit", "office",
/// "zoom:<factor>" (below 1 zooms in), "hover:x,y" or "click:x,y" (the pointer at x, y view points from the top left, as
/// a real mouse event, so the HUD panels still catch it), "uiclick:x,y" (a click through the window: HUD buttons), "move:<session>:<room>" (a person on the open floor walks to
/// another room), "walker:<k>" / "clickwalker:<k>" (the pointer on campus walker k), "person:<id>" / "clickperson:<id>" (the pointer on a
/// person on the open floor), "apart:<tower>" / "mark:<k>" (a tower held apart, storey k marked, D65), "life:demo"
/// (all of the campus's life at night, D66), "hour:<h>" (the campus clock), "layer:status" (D69),
/// "commands", "search:<text>" and "context:x,y" (a right-click; D72) and "wait:<seconds>". SF_WINDOW_SHOT_BURST="4@0.25" takes four
/// shots a quarter second apart (out-0.png … out-3.png), to judge motion.
enum WindowShot {
    static var active: Bool { ProcessInfo.processInfo.environment["SF_WINDOW_SHOT"] != nil }
    static var action: String? { ProcessInfo.processInfo.environment["SF_WINDOW_SHOT_ACTION"] }

    static func scheduleIfAsked() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SF_WINDOW_SHOT"], !path.isEmpty else { return }
        let wait = env["SF_WINDOW_SHOT_AFTER"].flatMap(Double.init) ?? 6
        let burst = (env["SF_WINDOW_SHOT_BURST"] ?? "").split(separator: "@").map(String.init)
        guard burst.count == 2, let n = Int(burst[0]), let dt = Double(burst[1]), n > 1 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { shoot(to: URL(fileURLWithPath: path)) }
            return
        }
        let url = URL(fileURLWithPath: path), base = url.deletingPathExtension().path
        for k in 0..<n {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + Double(k) * dt) {
                shoot(to: URL(fileURLWithPath: "\(base)-\(k).png"), quit: k == n - 1)
            }
        }
    }

    /// A real mouse event at x, y view points from the window's top left: "moved" or a click (down and up).
    static func mouse(_ kind: String, x: CGFloat, y: CGFloat) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }), let content = window.contentView,
              let sk = find(SKView.self, in: content) else { return }
        let wp = content.convert(NSPoint(x: x, y: content.isFlipped ? y : content.bounds.height - y), to: nil)
        func ev(_ t: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: t, location: wp, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1)
        }
        if kind == "uiclick" {
            // through the window, so whatever is on top there (a HUD button) gets it, as from a real mouse
            if let d = ev(.leftMouseDown) { window.sendEvent(d) }
            if let u = ev(.leftMouseUp) { window.sendEvent(u) }
        } else if kind == "right" {
            if let d = ev(.rightMouseDown) { sk.rightMouseDown(with: d) }
        } else if kind == "click" {
            if let d = ev(.leftMouseDown) { sk.mouseDown(with: d) }
            if let u = ev(.leftMouseUp) { sk.mouseUp(with: u) }
        } else if let m = ev(.mouseMoved) { sk.mouseMoved(with: m) }
    }

    /// A key press through the app, as from the keyboard: "n", "esc", "1", "cmd-k" (window shots check the HUD's keys).
    static func key(_ spec: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) else { return }
        let cmd = spec.hasPrefix("cmd-"), k = cmd ? String(spec.dropFirst(4)) : spec
        let chars = k == "esc" ? "\u{1b}" : k
        let code: UInt16 = k == "esc" ? 53 : k == "n" ? 45 : k == "1" ? 18 : k == "2" ? 19 : k == "k" ? 40 : 0
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: cmd ? .command : [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                        isARepeat: false, keyCode: code) { NSApp.sendEvent(e) }
        }
    }

    static func shoot(to out: URL, quit: Bool = true) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }), let content = window.contentView else { NSApp.terminate(nil); return }
        let bounds = content.bounds
        guard let sk = find(SKView.self, in: content), let scene = sk.scene, let cam = scene.camera else { NSApp.terminate(nil); return }
        let crop = CGRect(x: cam.position.x - scene.size.width * cam.xScale / 2, y: cam.position.y - scene.size.height * cam.yScale / 2,
                          width: scene.size.width * cam.xScale, height: scene.size.height * cam.yScale)
        let world = sk.texture(from: scene, crop: crop)?.cgImage()
        sk.isHidden = true; content.layoutSubtreeIfNeeded(); content.display()
        guard let hud = content.bitmapImageRepForCachingDisplay(in: bounds) else { NSApp.terminate(nil); return }
        content.cacheDisplay(in: bounds, to: hud)
        sk.isHidden = false; sk.isPaused = false
        let w = hud.pixelsWide, h = hud.pixelsHigh
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 7 / 255, green: 7 / 255, blue: 12 / 255, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let k = CGFloat(w) / bounds.width, r = sk.convert(sk.bounds, to: content)
        ctx.interpolationQuality = .none
        if let world { ctx.draw(world, in: CGRect(x: r.minX * k, y: (content.isFlipped ? bounds.height - r.maxY : r.minY) * k, width: r.width * k, height: r.height * k)) }
        // a terminal paints its background in its layer, which caching the view's display does not draw: lay the
        // terminal's own charcoal under it, as the screen shows it (checked with a real screen capture)
        for t in findAll(TerminalView.self, in: content) where !t.isHiddenOrHasHiddenAncestor && t.alphaValue > 0 {
            let f = t.convert(t.bounds, to: content)
            ctx.setFillColor(t.nativeBackgroundColor.usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 0.07, alpha: 1))
            ctx.fill(CGRect(x: f.minX * k, y: (content.isFlipped ? bounds.height - f.maxY : f.minY) * k, width: f.width * k, height: f.height * k))
        }
        if let hudImage = hud.cgImage { ctx.draw(hudImage, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        if let img = ctx.makeImage() { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: out) }
        print("Wrote \(out.path) scene \(type(of: scene)) \(Int(scene.size.width))x\(Int(scene.size.height)) camera \(cam.xScale)")
        if quit { NSApp.terminate(nil) }
    }

    static func findAll<T: NSView>(_ type: T.Type, in v: NSView) -> [T] {
        ((v as? T).map { [$0] } ?? []) + v.subviews.flatMap { findAll(type, in: $0) }
    }

    static func find<T: NSView>(_ type: T.Type, in v: NSView) -> T? {
        if let t = v as? T { return t }
        for s in v.subviews { if let t = find(type, in: s) { return t } }
        return nil
    }
}
