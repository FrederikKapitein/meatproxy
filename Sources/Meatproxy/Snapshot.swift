import AppKit
import SpriteKit
import FactoryCore
import FactoryCollector
import FactoryScenes

/// `Meatproxy --snapshot out.png [--fixture] [--focus claude|chatgpt|engine] [--floor next|<id>] [--orbit]` renders the world to
/// a PNG without opening a window. Use --fixture for anything you share: it shows fictional data.
@MainActor
enum Snapshot {
    static func run(_ args: [String]) -> Int32 {
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return 2 }
        let out = URL(fileURLWithPath: args[i + 1])
        let world = (args.contains("--fixture") || args.contains("--first-run")) ? Fixture.world() : Collector().world(settings: ProjectSettingsStore().load())
        _ = NSApplication.shared
        let size = CGSize(width: 1440, height: 900)
        let view = SKView(frame: NSRect(origin: .zero, size: size))
        let c = WorldController()
        c.animationsEnabled = false
        c.attach(view)
        c.show(world)
        func spin(_ seconds: Double, until done: () -> Bool) { let end = Date().addingTimeInterval(seconds); while Date() < end && !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
        spin(20) { c.campus.isPainted }
        if let f = args.firstIndex(of: "--focus"), f + 1 < args.count { c.focusBuilding(args[f + 1]); spin(0.3) { false } }
        if let f = args.firstIndex(of: "--floor"), f + 1 < args.count {
            if args[f + 1] == "next" { c.nextWaiting() } else { c.enterFloor(args[f + 1]) }
            spin(10) { c.floor != nil && view.scene === c.floor }
            spin(0.5) { false }
        }
        if args.contains("--orbit") {
            c.showOrbit(true)
            if let f = args.firstIndex(of: "--session"), f + 1 < args.count { c.select(session: args[f + 1]) }
            spin(1) { false }
            spin(30) { !c.orbit.isLoading }
            c.orbit.draw()
            spin(0.3) { false }
        }
        guard let scene = view.scene as? WorldScene, let tex = view.texture(from: scene, crop: scene.visibleRect) else { print("Could not render the scene"); return 1 }
        let rep = NSBitmapImageRep(cgImage: tex.cgImage())
        guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        do { try png.write(to: out) } catch { print("Could not write \(out.path): \(error.localizedDescription)"); return 1 }
        print("Wrote \(out.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        return 0
    }
}
