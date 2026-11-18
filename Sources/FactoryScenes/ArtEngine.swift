import Foundation
import WebKit
import AppKit
import SpriteKit
import FactoryCore

/// Runs the art in a hidden WebKit view and hands back textures. The blocky world (D32) and the Orbit generator (D42)
/// are the same scripts as on the design board (Art/src/art); Art/src/app/engine.js paints them layer by layer. SpriteKit
/// then sorts the layers by depth, moves the people and zooms.
@MainActor
public final class ArtEngine: NSObject, WKURLSchemeHandler {
    private let root: URL
    private var web: WKWebView!
    private var floorCache: [String: FloorArt] = [:]
    private var figures: [String: Figure] = [:]
    private var images: [String: CGImage] = [:]
    private var bodies: [String: BodyImage] = [:]

    public override init() {
        root = ScenesResources.bundle.url(forResource: "Art", withExtension: nil)!
        super.init()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(self, forURLScheme: "sfart")
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 16, height: 16), configuration: config)
        web.load(URLRequest(url: URL(string: "sfart://art/engine.html")!))
    }

    // MARK: serving the bundled files to the web view

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let file = root.appendingPathComponent(url.path)
        guard file.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime = file.pathExtension == "js" ? "text/javascript" : file.pathExtension == "html" ? "text/html" : "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime, "Access-Control-Allow-Origin": "*"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    // MARK: calls

    private func ready() async throws {
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript("!!(window.sf && window.sf.ready)")) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw URLError(.timedOut)
    }

    private func call(_ js: String, _ args: [String: Any]) async throws -> [String: Any] {
        try await ready()
        let result = try await web.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .page)
        guard let dict = result as? [String: Any] else { throw URLError(.cannotParseResponse) }
        return dict
    }

    /// The floor, from the inside (D38). Every floor is the same office, so it is painted once.
    /// A floor from the inside, in its provider's look (D55): its mark inlaid in the hall, its colour in the terrazzo.
    public func floor(_ provider: Provider? = nil) async throws -> FloorArt {
        let key = provider?.rawValue ?? ""
        if let f = floorCache[key] { return f }
        let f = FloorArt(try await call("return await window.sf.floor({R: 4, provider: p})", ["p": key]))
        floorCache[key] = f
        return f
    }

    /// The campus (Spel+, D80): the towers have a storey per project with a blade sign, yellow where something waits;
    /// the Server room's racks carry the servers' names; the quest pillar counts what waits for you and names the first
    /// quests. `night` paints it by moonlight, where only real light sources glow (A8).
    public func campus(_ world: World, night: Bool = false) async throws -> CampusArt {
        func floors(_ p: Provider) -> [[String: Any]] {
            (world.building(p)?.projects ?? []).map { pr in
                var f: [String: Any] = ["name": pr.name, "wait": pr.waits(now: world.now),
                                        "kind": pr.factory != nil ? "factory" : pr.isChat ? "chats" : "project"]   // D62
                if let logo = pr.logo.flatMap(logoURI) { f["logo"] = logo }   // D58: the logo in its plaque
                return f
            }
        }
        let sum = world.serverSummary
        let racks = world.racks.prefix(6).map { ["name": $0.name, "state": $0.state.rawValue] }
        let input: [String: Any] = ["R": 2, "claude": floors(.claude), "chatgpt": floors(.chatgpt), "waiting": world.needsYou.count,
                                    "quests": world.needsYou.prefix(2).map { Self.questLabel($0) }, "night": night, "racks": racks,
                                    "engine": ["total": sum.total, "warn": sum.warn, "down": sum.down]]
        return CampusArt(try await call("return await window.sf.campus(input)", ["input": input]))
    }

    /// A quest on the pillar's side (A3): what it asks in a word or two, its verb and its project ("SHIP PEBBLE?").
    static func questLabel(_ n: NeedsYou) -> String {
        let verb = n.title.split(whereSeparator: { !$0.isLetter && $0 != "-" }).first.map(String.init) ?? "Look"
        let project = n.project.name.split(separator: " ").first.map(String.init) ?? ""
        let both = "\(verb) \(project)?"
        return (both.count <= 12 ? both : "\(verb)?").uppercased()
    }

    /// A project's logo as a small PNG data URI for its plaque (D58): drawn once per file at 48 px, kept.
    private var logos: [String: String?] = [:]
    private func logoURI(_ path: String) -> String? {
        if let hit = logos[path] { return hit }
        var uri: String?
        if let img = NSImage(contentsOfFile: path), img.size.width > 0 {
            let px = 48, rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            if let rep {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                let s = img.size, k = min(CGFloat(px) / s.width, CGFloat(px) / s.height), w = s.width * k, h = s.height * k
                img.draw(in: CGRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h))
                NSGraphicsContext.restoreGraphicsState()
                uri = rep.representation(using: .png, properties: [:]).map { "data:image/png;base64," + $0.base64EncodedString() }
            }
        }
        logos[path] = .some(uri)
        return uri
    }

    /// Every frame one person needs, from the blocky rig (D41): cached per role and seed.
    public func figure(_ cast: CastKey) async throws -> Figure {
        if let f = figures[cast.key] { return f }
        let specs = Figure.specs.map { ["pose": $0.pose, "view": $0.view, "mood": $0.mood, "noProp": $0.noProp] as [String: Any] }
        let d = try await call("return window.sf.figure(who, frames, 6)", ["who": ["role": cast.role.rawValue, "seed": cast.seed], "frames": specs])
        let f = Figure(d)
        figures[cast.key] = f
        return f
    }
    public func cachedFigure(_ cast: CastKey) -> Figure? { figures[cast.key] }

    /// A name tag, an emote bubble or the stuck cloud: small images centred on their anchor.
    public func tag(_ text: String, state: String) async -> Overlay? { await tag(text, sub: "", state: state) }
    /// A name plate (Spel+, B2 B3 B6 B7): the name, a quiet second line, the role's colour; state work, wait, stuck, done
    /// or back; badge, the colour of a diamond a helper shares with its person (nil: none). Its rect: the tip at (0, 0).
    public func tag(_ text: String, sub: String, state: String, role: String = "#6a6478", badge: String? = nil) async -> Overlay? {
        var o: [String: Any] = ["text": text, "sub": sub, "state": state, "role": role]
        if let badge { o["badge"] = badge }
        return await overlay("tag|\(state)|\(text)|\(sub)|\(role)|\(badge ?? "")", "return await window.sf.tag(o)", o)
    }
    /// The one board on the Planning wall (B1): a card per workstream in its phase's column. A flat board laid on the
    /// wall's plane; its rect is relative to the board's top-left corner on the wall.
    public func board(_ cards: [[String: Any]]) async -> Overlay? {
        let key = "board|" + cards.map { "\($0["id"] ?? "")\($0["phase"] ?? "")\($0["wait"] ?? "")\($0["back"] ?? "")\($0["title"] ?? "")" }.joined(separator: ",")
        return await overlay(key, "return await window.sf.board(o)", ["cards": cards])
    }
    public func emote(_ kind: String) async -> Overlay? { await overlay("emote|\(kind)", "return await window.sf.emote(o)", ["kind": kind]) }
    public func cloud() async -> Overlay? { await overlay("cloud", "return await window.sf.cloud(o)", [:]) }
    private var overlays: [String: Overlay] = [:]
    private func overlay(_ key: String, _ js: String, _ o: [String: Any]) async -> Overlay? {
        if let v = overlays[key] { return v }
        guard let d = try? await call(js, ["o": o]), let img = ArtImage(d) else { return nil }
        let v = Overlay(image: img.image, rect: img.rect)
        overlays[key] = v
        return v
    }

    // MARK: Orbit

    public func orbitLayout(galaxies: [(id: String, n: Int)], bodies: [OrbitBodyKey]) async throws -> OrbitLayout {
        let input: [String: Any] = ["galaxies": galaxies.map { ["id": $0.id, "n": $0.n] }, "bodies": bodies.map { ["kind": $0.kind, "id": $0.id, "opts": $0.opts] }]
        return OrbitLayout(try await call("return window.sf.orbitLayout(input)", ["input": input]))
    }

    /// One body at radius `r` device pixels, lit from `light` (radians, nil for unlit bodies).
    public func body(_ b: OrbitBodyKey, r: Int, light: Double?) async -> BodyImage? {
        let key = "\(b.key)|\(r)|\(light.map { String(format: "%.2f", $0) } ?? "-")"
        if let v = bodies[key] { return v }
        var req: [String: Any] = ["kind": b.kind, "id": b.id, "opts": b.opts, "R": r]
        if let light { req["light"] = light }
        guard let d = try? await call("return window.sf.body(req)", ["req": req]), let img = decodeImage( d["png"] as? String) else { return nil }
        let v = BodyImage(image: img, r: CGFloat(r))
        if bodies.count > 600 { bodies.removeAll() }
        bodies[key] = v
        return v
    }

    /// The star field behind Orbit, at the view's size in device pixels.
    public func sky(width: Int, height: Int) async -> CGImage? {
        let key = "sky|\(width)x\(height)"
        if let v = images[key] { return v }
        guard let d = try? await call("return window.sf.sky(req)", ["req": ["w": width, "h": height, "seed": 77]]), let img = decodeImage( d["png"] as? String) else { return nil }
        images = images.filter { !$0.key.hasPrefix("sky|") }
        images[key] = img
        return img
    }
}

// MARK: decoded art

func decodeImage(_ s: String?) -> CGImage? {
    guard let s, let comma = s.firstIndex(of: ","), let data = Data(base64Encoded: String(s[s.index(after: comma)...])),
          let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func num(_ a: Any?) -> CGFloat { CGFloat((a as? Double) ?? Double((a as? Int) ?? 0)) }
func point(_ a: Any?) -> CGPoint { let p = a as? [Any] ?? []; return CGPoint(x: num(p.first), y: num(p.count > 1 ? p[1] : nil)) }

/// An image and where its top-left corner goes, in art units.
public struct ArtImage {
    public var image: CGImage, rect: CGRect
    init?(_ a: Any?) {
        guard let d = a as? [String: Any], let img = decodeImage( d["png"] as? String) else { return nil }
        image = img; rect = CGRect(x: num(d["x"]), y: num(d["y"]), width: num(d["w"]), height: num(d["h"]))
    }
}

public struct Overlay { public var image: CGImage, rect: CGRect }

/// One sign (a room sign, a plaque, a roof board) on its own image, named after what it hangs on.
public struct SignPart {
    public var id: String, image: ArtImage
    /// what it hangs on, as a depth key (a plaque on a wall sorts with the wall); nil: over everything
    public var key: CGFloat? = nil
}

func signParts(_ a: Any?) -> [SignPart] {
    ((a as? [[String: Any]]) ?? []).compactMap { d in ArtImage(d).map { SignPart(id: d["id"] as? String ?? "", image: $0, key: d["key"] is NSNumber ? num(d["key"]) : nil) } }
}

/// One object of a scene, cut from an atlas page: a sprite sorted by its depth key.
public struct ArtObject {
    public var id: String?
    public var key: CGFloat
    public var texture: SKTexture
    public var rect: CGRect
    /// how see-through it is drawn (a cloud); 1 for most
    public var alpha: CGFloat = 1
}

func atlasObjects(_ a: Any?) -> [ArtObject] {
    guard let d = a as? [String: Any] else { return [] }
    let pages: [SKTexture] = ((d["pages"] as? [[String: Any]]) ?? []).compactMap { p in decodeImage( p["png"] as? String).map { SKTexture(cgImage: $0) } }
    return ((d["items"] as? [[String: Any]]) ?? []).compactMap { it in
        let k = Int(num(it["page"]))
        guard k < pages.count else { return nil }
        let page = pages[k], W = page.size().width, H = page.size().height
        let px = num(it["px"]), py = num(it["py"]), pw = num(it["pw"]), ph = num(it["ph"])
        let tex = SKTexture(rect: CGRect(x: px / W, y: 1 - (py + ph) / H, width: pw / W, height: ph / H), in: page)
        return ArtObject(id: it["id"] as? String, key: num(it["key"]), texture: tex, rect: CGRect(x: num(it["x"]), y: num(it["y"]), width: num(it["w"]), height: num(it["h"])),
                         alpha: it["alpha"] == nil ? 1 : num(it["alpha"]))
    }
}

/// A box on the floor plan that hides what stands behind it (the painter's rule, in tiles).
public struct Box { public var i0: CGFloat, j0: CGFloat, i1: CGFloat, j1: CGFloat, key: CGFloat }

func boxes(_ a: Any?) -> [Box] {
    ((a as? [[String: Any]]) ?? []).map { b in Box(i0: num(b["i0"]), j0: num(b["j0"]), i1: num(b["i1"]), j1: num(b["j1"]), key: num(b["key"])) }
}

/// Draw order for someone standing at tile (i, j): in front of every box they are in front of. A box counts when they
/// stand past its near side and alongside it, within a tile of its ends (a figure is about a tile wide on screen); one
/// further off to the side is beside them, not behind, and must not lift them over what really stands in front (a desk
/// in the next room would otherwise put someone in front of the glass between them).
func depthKey(_ i: CGFloat, _ j: CGFloat, boxes: [Box]) -> CGFloat {
    var k = i + j + 0.3
    for b in boxes where (i >= b.i1 || j >= b.j1) && i > b.i0 - 1 && j > b.j0 - 1 { k = max(k, b.key + 0.01) }
    return k
}

/// The blocky projection: tile (i, j) at height z (model units) → art units.
func project(_ i: CGFloat, _ j: CGFloat, _ z: CGFloat = 0) -> CGPoint { CGPoint(x: (i - j) * 16, y: (i + j) * 8 - z * 1.08) }

public struct FloorArt {
    public struct Spot { public var i: CGFloat, j: CGFloat, pose: String, dir: String, seat: CGFloat }
    public struct Room { public var id: String, name: String, rect: CGRect }
    public var view: CGRect, ground: ArtImage?, objects: [ArtObject], light: ArtImage?, signs: [SignPart], boxes: [Box]
    public var spots: [String: [Spot]], rooms: [Room]
    /// what people walk round: furniture and walls (`boxes`) and the props that hide nothing (plants, lamps), in tiles
    public var solids: [CGRect]
    /// the room signs, in art units: speech bubbles keep off them
    public var labels: [CGRect]

    init(_ d: [String: Any]) {
        let v = (d["view"] as? [Any] ?? []).map(num)
        view = v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]) : .zero
        ground = ArtImage(d["ground"]); objects = atlasObjects(d["objects"]); light = ArtImage(d["light"]); signs = signParts(d["signParts"])
        boxes = FactoryScenes.boxes(d["boxes"])
        labels = ((d["labels"] as? [[Any]]) ?? []).compactMap { r in r.count == 4 ? CGRect(x: num(r[0]), y: num(r[1]), width: num(r[2]), height: num(r[3])) : nil }
        spots = ((d["spots"] as? [String: [[Any]]]) ?? [:]).mapValues { list in
            list.map { s in Spot(i: num(s[0]), j: num(s[1]), pose: s[2] as? String ?? "idle", dir: s[3] as? String ?? "down", seat: s.count > 4 ? num(s[4]) : 0) }
        }
        solids = boxes.map { CGRect(x: $0.i0, y: $0.j0, width: $0.i1 - $0.i0, height: $0.j1 - $0.j0) }
            + ((d["solids"] as? [[String: Any]]) ?? []).map { b in CGRect(x: num(b["i0"]), y: num(b["j0"]), width: num(b["i1"]) - num(b["i0"]), height: num(b["j1"]) - num(b["j0"])) }
        rooms = ((d["rooms"] as? [[String: Any]]) ?? []).map { r in
            Room(id: r["id"] as? String ?? "", name: r["name"] as? String ?? "", rect: CGRect(x: num(r["i"]), y: num(r["j"]), width: num(r["w"]), height: num(r["d"])))
        }
    }
}

public struct CampusArt {
    /// kind: "factory", "chats" or "project" (D62); windows: the front windows' quads, so the app can light them;
    /// mount: where an alarm light hangs on its front face (art units)
    public struct Storey { public var building: String, index: Int, faces: [[CGPoint]], kind: String = "project", windows: [[CGPoint]] = [], mount: CGPoint? = nil }
    /// per tower: the antenna's tip (its lamp blinks) and the chimney's mouth when a factory works there (it smokes)
    public struct Tower { public var building: String, antenna: CGPoint, chimney: CGPoint? }
    public var towers: [Tower] = []
    public var view: CGRect, ground: ArtImage?, objects: [ArtObject], light: ArtImage?, signs: [SignPart], boxes: [Box]
    /// the island's underside, a coarser image under the ground
    public var under: ArtImage?
    /// the island's top with its towers (art units): what the home view fills (A4)
    public var island: CGRect = .zero
    /// each rack's front panel (art units) and its box: i0, i1 along the front, the front's j, z0, z1
    public var rackPanels: [[CGPoint]] = [], rackBoxes: [[CGFloat]] = []
    /// the way a deploy's packets go from each tower's door to the Server room, in tiles
    public var streams: [String: [CGPoint]] = [:]
    /// painted by moonlight (A8)
    public var night = false
    /// how long the art engine took: building the scene and painting it (ms)
    public var timing: [Int] = []
    /// what you can point at besides the buildings, as boxes (tiles, and a height in model units): "fountain"
    public var hits: [String: [(rect: CGRect, height: CGFloat)]]
    public struct Rack { public var c: Int, r: Int, pts: [CGPoint] }
    public var storeys: [Storey], fountain: CGPoint
    /// what you can click, in tiles: "building:claude", "building:chatgpt", "building:engine", "fountain"
    public var footprints: [String: CGRect]
    /// the Server room's rack LEDs (art units, on its front face) and the roof beacon's lens
    public var racks: [Rack], beacon: [CGPoint], beaconAt: CGPoint
    /// where each tower's storey plaques are, in art units, so the camera can frame them
    public var plaques: [String: [CGRect]]

    init(_ d: [String: Any]) {
        let v = (d["view"] as? [Any] ?? []).map(num)
        view = v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]) : .zero
        // the buildings come on their own atlas, painted with more pixels
        ground = ArtImage(d["ground"]); objects = atlasObjects(d["objects"]) + atlasObjects(d["buildings"]); light = ArtImage(d["light"])
        under = ArtImage(d["under"])
        signs = signParts(d["signParts"])
        for r in (d["rackPanels"] as? [[String: Any]]) ?? [] {
            rackPanels.append(((r["pts"] as? [Any]) ?? []).map(point)); rackBoxes.append(((r["box"] as? [Any]) ?? []).map(num))
        }
        streams = ((d["streams"] as? [String: [Any]]) ?? [:]).mapValues { $0.map(point) }
        timing = ((d["timing"] as? [Any]) ?? []).map { Int(num($0)) }
        night = d["night"] as? Bool ?? false
        let isl = (d["island"] as? [Any] ?? []).map(num)
        island = isl.count == 4 ? CGRect(x: isl[0], y: isl[1], width: isl[2] - isl[0], height: isl[3] - isl[1]) : view
        boxes = FactoryScenes.boxes(d["boxes"])
        hits = ((d["hits"] as? [String: [[Any]]]) ?? [:]).mapValues { list in
            list.compactMap { b in let v = b.map(num); return v.count == 5 ? (CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]), v[4]) : nil }
        }
        storeys = ((d["storeys"] as? [[String: Any]]) ?? []).map { s in
            Storey(building: s["building"] as? String ?? "", index: Int(num(s["index"])), faces: ((s["faces"] as? [[Any]]) ?? []).map { $0.map(point) },
                   kind: s["kind"] as? String ?? "project", windows: ((s["windows"] as? [[Any]]) ?? []).map { $0.map(point) },
                   mount: s["mount"].flatMap { $0 is NSNull ? nil : point($0) })
        }
        fountain = point(d["fountain"])
        towers = ((d["towers"] as? [[String: Any]]) ?? []).map { t in
            Tower(building: t["building"] as? String ?? "", antenna: point(t["antenna"]), chimney: t["chimney"].flatMap { $0 is NSNull ? nil : point($0) })
        }
        footprints = ((d["footprints"] as? [String: [Any]]) ?? [:]).mapValues { a in
            let v = a.map(num); return v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]) : .zero
        }
        racks = ((d["racks"] as? [[String: Any]]) ?? []).map { r in Rack(c: Int(num(r["c"])), r: Int(num(r["r"])), pts: ((r["pts"] as? [Any]) ?? []).map(point)) }
        let b = d["beacon"] as? [String: Any]
        beacon = ((b?["pts"] as? [Any]) ?? []).map(point); beaconAt = point(b?["at"])
        var pq: [String: [CGRect]] = [:]
        for l in (d["labels"] as? [[String: Any]]) ?? [] {
            let v = ((l["rect"] as? [Any]) ?? []).map(num)
            if v.count == 4, let k = l["building"] as? String { pq[k, default: []].append(CGRect(x: v[0], y: v[1], width: v[2], height: v[3])) }
        }
        plaques = pq
    }
}

/// One person's frames. A frame's rect is where its top-left corner goes relative to the feet, in art units.
public struct Figure {
    public struct Spec { var pose: String, view: String, mood: String, noProp: Bool; var name: String { "\(pose)-\(mood)-\(view)" } }
    static let views = ["SW", "SE", "NW", "NE"]
    /// The frames every person gets: walking and standing, at a desk, sitting, and one pose per state, from all four sides.
    static let specs: [Spec] = views.flatMap { v in [
        Spec(pose: "idle", view: v, mood: "calm", noProp: false), Spec(pose: "walkA", view: v, mood: "calm", noProp: false),
        Spec(pose: "walkB", view: v, mood: "calm", noProp: false), Spec(pose: "type", view: v, mood: "focus", noProp: true),
        Spec(pose: "sit", view: v, mood: "calm", noProp: true), Spec(pose: "sit", view: v, mood: "tired", noProp: true),
        Spec(pose: "idle", view: v, mood: "wait", noProp: false), Spec(pose: "stuck", view: v, mood: "stuck", noProp: true),
        Spec(pose: "mug", view: v, mood: "tired", noProp: false), Spec(pose: "cheer", view: v, mood: "happy", noProp: true),
        Spec(pose: "wave", view: v, mood: "happy", noProp: false), Spec(pose: "idle", view: v, mood: "tired", noProp: false),
        // the loops of someone who stands still (IdleMotion): typing, asking, reading, pointing, dozing
        Spec(pose: "typeB", view: v, mood: "focus", noProp: true), Spec(pose: "ask", view: v, mood: "wait", noProp: false),
        Spec(pose: "read", view: v, mood: "calm", noProp: false), Spec(pose: "point", view: v, mood: "calm", noProp: false),
        Spec(pose: "snooze", view: v, mood: "tired", noProp: true),
    ] }
    public var frames: [String: (texture: SKTexture, rect: CGRect)] = [:]
    public var portrait: CGImage?

    init(_ d: [String: Any]) {
        // one atlas page, or more when the frames do not fit on one
        let pages = ((d["pages"] as? [[String: Any]]) ?? [d["page"] as? [String: Any]].compactMap { $0 })
            .compactMap { decodeImage($0["png"] as? String) }
        guard !pages.isEmpty else { return }
        let textures = pages.map { SKTexture(cgImage: $0) }
        for (k, f) in ((d["frames"] as? [[String: Any]]) ?? []).enumerated() where k < Self.specs.count {
            let n = min(Int(num(f["page"])), pages.count - 1), tex = textures[n], W = CGFloat(pages[n].width), H = CGFloat(pages[n].height)
            let px = num(f["px"]), py = num(f["py"]), pw = num(f["pw"]), ph = num(f["ph"])
            let t = SKTexture(rect: CGRect(x: px / W, y: 1 - (py + ph) / H, width: pw / W, height: ph / H), in: tex)
            frames[Self.specs[k].name] = (t, CGRect(x: num(f["x"]), y: num(f["y"]), width: num(f["w"]), height: num(f["h"])))
            if k == 0 { portrait = pages[n].cropping(to: CGRect(x: px, y: py, width: pw, height: ph * 0.62)) }
        }
    }

    /// A frame by pose, mood and direction on the floor (down = front-left, right = front-right, up, left).
    public func frame(_ pose: String, mood: String, dir: String) -> (texture: SKTexture, rect: CGRect)? {
        let view = ["down": "SW", "right": "SE", "up": "NE", "left": "NW"][dir] ?? "SW"
        return frames["\(pose)-\(mood)-\(view)"] ?? frames["\(pose)-calm-\(view)"] ?? frames["idle-calm-\(view)"]
    }
}

// MARK: Orbit

/// A body in Orbit: which generator, its stable id and options (D42).
public struct OrbitBodyKey: Hashable, @unchecked Sendable {
    public var kind: String, id: String, opts: [String: String]
    public var key: String { kind + "|" + id + "|" + opts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }
    public static func == (a: Self, b: Self) -> Bool { a.key == b.key }
    public func hash(into h: inout Hasher) { h.combine(key) }
}

public struct BodyImage { public var image: CGImage, r: CGFloat }

public struct OrbitLayout {
    public var slots: [String: [CGPoint]], extents: [String: CGFloat], bodies: [(scale: CGFloat, extent: CGFloat)]
    init(_ d: [String: Any]) {
        var s: [String: [CGPoint]] = [:], e: [String: CGFloat] = [:]
        for g in (d["galaxies"] as? [[String: Any]]) ?? [] {
            let id = g["id"] as? String ?? ""
            s[id] = ((g["slots"] as? [Any]) ?? []).map(point); e[id] = num(g["extent"])
        }
        slots = s; extents = e
        bodies = ((d["bodies"] as? [[String: Any]]) ?? []).map { (num($0["scale"]), num($0["extent"])) }
    }
}

/// This module's resources: inside Meatproxy.app they sit in Contents/Resources (scripts/make-app.sh); in a bare build,
/// where SwiftPM put them.
enum ScenesResources {
    static let bundle: Bundle = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Meatproxy_FactoryScenes.bundle"), let b = Bundle(url: r) { return b }
        return Bundle.module
    }()
}
