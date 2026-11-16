import CoreGraphics
import Foundation

/// The four sides a person is drawn from, by the names `Figure.frame` takes: down = SW (front-left), right = SE
/// (front-right), up = NE (back-right), left = NW (back-left). A step along +i goes down-right on screen, so it shows
/// SE; +j goes down-left (SW); -i up-left (NW); -j up-right (NE).
public enum Facing {
    /// The side for a step of (di, dj) tiles. Near-diagonal steps keep the current side, so the facing does not flicker.
    public static func dir(_ di: CGFloat, _ dj: CGFloat, current: String? = nil) -> String {
        let ai = abs(di), aj = abs(dj)
        guard max(ai, aj) > 1e-6 else { return current ?? "down" }
        let ci = di > 0 ? "right" : "left", cj = dj > 0 ? "down" : "up"
        if min(ai, aj) / max(ai, aj) > 0.8, let c = current, c == ci || c == cj { return c }
        return ai >= aj ? ci : cj
    }

    /// The side a step along it would be: down +j, right +i, up -j, left -i.
    public static func vector(_ dir: String) -> CGPoint {
        switch dir {
        case "right": CGPoint(x: 1, y: 0)
        case "left": CGPoint(x: -1, y: 0)
        case "up": CGPoint(x: 0, y: -1)
        default: CGPoint(x: 0, y: 1)
        }
    }

    public static func opposite(_ a: String, _ b: String) -> Bool {
        let v = vector(a), w = vector(b)
        return v.x * w.x + v.y * w.y < -0.5
    }

    /// Turning round, a person passes a side that faces the camera: NW↔SE via SW, NE↔SW via SE.
    public static func via(_ a: String, _ b: String) -> String? {
        guard opposite(a, b) else { return nil }
        return Set([a, b]) == Set(["left", "right"]) ? "down" : "right"
    }

    /// Standing still after walking: the side next to the arrival side that faces the camera (NW → SW, NE → SE).
    public static func front(of dir: String) -> String { dir == "left" ? "down" : dir == "up" ? "right" : dir }
}

/// The walk cycle, driven by distance so feet stay planted: one stride (A or B) every 0.225 tiles, with the standing
/// frame between them (A, idle, B, idle). Stride 7.2 model units = 0.45 tile per full step.
public enum StepCycle {
    public static let quarter: CGFloat = 0.225
    public static func pose(distance: CGFloat) -> String {
        ["walkA", "idle", "walkB", "idle"][Int(max(0, distance) / quarter) % 4]
    }
}

/// A small directed graph of lanes in tiles. Every lane is axis-aligned, so people only ever walk along i or j and
/// turn 90° at a node.
public struct LaneGraph {
    public private(set) var nodes: [CGPoint] = []
    private var out: [[(to: Int, len: CGFloat)]] = []
    private var lines: [(a: CGPoint, b: CGPoint, oneWay: Bool)] = []

    public init() {}

    /// A straight lane from a to b (one way, or both ways). Call `build()` after the last one.
    public mutating func lane(_ a: CGPoint, _ b: CGPoint, oneWay: Bool = false) { lines.append((a, b, oneWay)) }

    /// Joins every lane at every point of another lane that lies on it (ends and crossings).
    public mutating func build() {
        func id(_ p: CGPoint) -> Int {
            if let k = nodes.firstIndex(where: { abs($0.x - p.x) < 0.01 && abs($0.y - p.y) < 0.01 }) { return k }
            nodes.append(p); out.append([]); return nodes.count - 1
        }
        let ends = lines.flatMap { [$0.a, $0.b] }
        for l in lines {
            let d = CGPoint(x: l.b.x - l.a.x, y: l.b.y - l.a.y), len = hypot(d.x, d.y)
            guard len > 0.001 else { continue }
            // every end of any lane that lies on this one, in order along it
            var on: [(t: CGFloat, p: CGPoint)] = []
            for p in ends {
                let t = ((p.x - l.a.x) * d.x + (p.y - l.a.y) * d.y) / (len * len)
                let q = CGPoint(x: l.a.x + d.x * t, y: l.a.y + d.y * t)
                if t > -0.001, t < 1.001, hypot(q.x - p.x, q.y - p.y) < 0.01 { on.append((t, p)) }
            }
            // crossings with other lanes
            for m in lines {
                if let x = Self.cross(l.a, l.b, m.a, m.b) { on.append((((x.x - l.a.x) * d.x + (x.y - l.a.y) * d.y) / (len * len), x)) }
            }
            on.sort { $0.t < $1.t }
            for k in 1..<on.count {
                let a = id(on[k - 1].p), b = id(on[k].p)
                guard a != b else { continue }
                let s = hypot(nodes[a].x - nodes[b].x, nodes[a].y - nodes[b].y)
                if !out[a].contains(where: { $0.to == b }) { out[a].append((b, s)) }
                if !l.oneWay, !out[b].contains(where: { $0.to == a }) { out[b].append((a, s)) }
            }
        }
    }

    /// Where an axis-aligned lane crosses another (both perpendicular), strictly inside both.
    static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let h1 = abs(a.y - b.y) < 0.001, h2 = abs(c.y - d.y) < 0.001
        guard h1 != h2 else { return nil }
        let (ha, hb, va, vb) = h1 ? (a, b, c, d) : (c, d, a, b)
        let x = va.x, y = ha.y
        guard x > min(ha.x, hb.x) + 0.001, x < max(ha.x, hb.x) - 0.001, y > min(va.y, vb.y) + 0.001, y < max(va.y, vb.y) - 0.001 else { return nil }
        return CGPoint(x: x, y: y)
    }

    public func nearest(_ p: CGPoint) -> Int? {
        nodes.indices.min { hypot(nodes[$0].x - p.x, nodes[$0].y - p.y) < hypot(nodes[$1].x - p.x, nodes[$1].y - p.y) }
    }

    /// The shortest way from node a to node b along the lanes, as points (both ends included); nil when there is none.
    public func path(_ a: Int, _ b: Int) -> [CGPoint]? {
        var dist = [CGFloat](repeating: .infinity, count: nodes.count), prev = [Int](repeating: -1, count: nodes.count)
        var done = [Bool](repeating: false, count: nodes.count)
        dist[a] = 0
        while true {
            guard let u = dist.indices.filter({ !done[$0] && dist[$0] < .infinity }).min(by: { dist[$0] < dist[$1] }) else { break }
            if u == b { break }
            done[u] = true
            for e in out[u] where dist[u] + e.len < dist[e.to] { dist[e.to] = dist[u] + e.len; prev[e.to] = u }
        }
        guard dist[b] < .infinity else { return nil }
        var list = [b]
        while list.last! != a { list.append(prev[list.last!]) }
        return list.reversed().map { nodes[$0] }
    }
}

/// A seeded random sequence, the same for the same seed on every run.
public struct SeededRandom {
    private var s: UInt64
    public init(_ seed: String) {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        s = h | 1
    }
    public init(_ seed: UInt64) { s = seed | 1 }
    public mutating func next() -> CGFloat {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return CGFloat(s % 1_000_000) / 1_000_000
    }
    public mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

/// The campus roads (D33) as a roundabout: a loop round the fountain, right-hand traffic, every merge and exit a right
/// turn, and an arm with an in and an out lane to each end of the island.
public enum CampusRoads {
    public struct Arm { public var name: String, inStart: CGPoint, inEnd: CGPoint, outStart: CGPoint, outEnd: CGPoint }
    public static let arms: [Arm] = [
        Arm(name: "west", inStart: CGPoint(x: 2.5, y: 13.4), inEnd: CGPoint(x: 12.6, y: 13.4), outStart: CGPoint(x: 12.6, y: 12.6), outEnd: CGPoint(x: 2.5, y: 12.6)),
        Arm(name: "east", inStart: CGPoint(x: 27.5, y: 12.6), inEnd: CGPoint(x: 17.4, y: 12.6), outStart: CGPoint(x: 17.4, y: 13.4), outEnd: CGPoint(x: 27.5, y: 13.4)),
        Arm(name: "north", inStart: CGPoint(x: 14.6, y: 3.5), inEnd: CGPoint(x: 14.6, y: 11), outStart: CGPoint(x: 15.4, y: 11), outEnd: CGPoint(x: 15.4, y: 3.5)),
        Arm(name: "south", inStart: CGPoint(x: 15.4, y: 23.5), inEnd: CGPoint(x: 15.4, y: 15), outStart: CGPoint(x: 14.6, y: 15), outEnd: CGPoint(x: 14.6, y: 23.5)),
    ]
    /// The loop, with the fountain on the walker's left.
    public static let loop = [CGPoint(x: 12.6, y: 15), CGPoint(x: 17.4, y: 15), CGPoint(x: 17.4, y: 11), CGPoint(x: 12.6, y: 11)]

    public static let graph: LaneGraph = {
        var g = LaneGraph()
        for k in loop.indices { g.lane(loop[k], loop[(k + 1) % loop.count], oneWay: true) }
        for a in arms { g.lane(a.inStart, a.inEnd, oneWay: true); g.lane(a.outStart, a.outEnd, oneWay: true) }
        g.build()
        return g
    }()

    /// From the outer end of one arm to the outer end of another (or the same one, round the fountain): the sidestep
    /// to the in lane, in, round the loop, out.
    public static func trip(from: Int, to: Int) -> [CGPoint] {
        let a = arms[from], b = arms[to]
        guard let s = graph.nearest(a.inStart), let e = graph.nearest(b.outEnd), let p = graph.path(s, e) else { return [a.outEnd, a.inStart] }
        return [a.outEnd] + p
    }
}

/// Walking on a floor: a grid over the floor plan where furniture, walls and props are solid, and a shortest way that
/// only goes along i or j, turns as little as it can and keeps clear of things. People step out of a chair first.
public struct FloorWalkMap {
    public let cell: CGFloat = 0.2
    let w: Int, h: Int
    /// 0 free, 1 near something (costs more, so people keep to the middle), 2 solid
    var grid: [UInt8]

    /// `area`: rectangles you can walk on; `solid`: boxes (in tiles) nobody walks through. `body`: how far a person's
    /// feet keep from a solid; `wallBody`, when given, from a thin one (a wall or glass partition, under 0.2 tile thick):
    /// a person is about half a tile wide on screen, so walking closer to a wall reads as walking into it.
    public init(area: [CGRect], holes: [CGRect], solid: [CGRect], body: CGFloat = 0.2, wallBody: CGFloat? = nil, margin: CGFloat = 0.5) {
        let maxX = area.map(\.maxX).max() ?? 1, maxY = area.map(\.maxY).max() ?? 1
        w = Int(ceil(maxX / cell)); h = Int(ceil(maxY / cell))
        grid = [UInt8](repeating: 2, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let p = CGPoint(x: (CGFloat(x) + 0.5) * cell, y: (CGFloat(y) + 0.5) * cell)
            if area.contains(where: { $0.insetBy(dx: body * 0.6, dy: body * 0.6).contains(p) }), !holes.contains(where: { $0.insetBy(dx: -body, dy: -body).contains(p) }) {
                grid[y * w + x] = 0
            }
        } }
        for r in solid {
            let b = min(r.width, r.height) < 0.2 ? wallBody ?? body : body
            mark(r.insetBy(dx: -margin, dy: -margin), 1)
            mark(r.insetBy(dx: -b, dy: -b), 2)
        }
    }

    private mutating func mark(_ r: CGRect, _ v: UInt8) {
        let x0 = max(0, Int(floor(r.minX / cell))), x1 = min(w - 1, Int(ceil(r.maxX / cell)) - 1)
        let y0 = max(0, Int(floor(r.minY / cell))), y1 = min(h - 1, Int(ceil(r.maxY / cell)) - 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 { for x in x0...x1 {
            let c = CGPoint(x: (CGFloat(x) + 0.5) * cell, y: (CGFloat(y) + 0.5) * cell)
            if r.contains(c), grid[y * w + x] < v { grid[y * w + x] = v }
        } }
    }

    func cellOf(_ p: CGPoint) -> (Int, Int) { (min(max(Int(p.x / cell), 0), w - 1), min(max(Int(p.y / cell), 0), h - 1)) }
    func center(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: (CGFloat(x) + 0.5) * cell, y: (CGFloat(y) + 0.5) * cell) }
    public func free(_ p: CGPoint) -> Bool { let (x, y) = cellOf(p); return grid[y * w + x] < 2 }

    /// The nearest free cell to p (p's own when it is free).
    func nearestFree(_ p: CGPoint) -> (Int, Int)? {
        let (sx, sy) = cellOf(p)
        if grid[sy * w + sx] < 2 { return (sx, sy) }
        var best: (Int, Int)?, bd = CGFloat.infinity
        for r in 1..<12 {
            for y in max(0, sy - r)...min(h - 1, sy + r) { for x in max(0, sx - r)...min(w - 1, sx + r) where grid[y * w + x] < 2 {
                let d = hypot(center(x, y).x - p.x, center(x, y).y - p.y)
                if d < bd { bd = d; best = (x, y) }
            } }
            if best != nil { return best }
        }
        return nil
    }

    /// The way from a to b: axis-aligned legs only, ends included, corners only where it turns.
    public func route(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        guard let s = nearestFree(a), let e = nearestFree(b) else { return Self.ell(a, b) }
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let n = w * h, turn: Int32 = 4, near: Int32 = 2
        var dist = [Int32](repeating: .max, count: n * 4), prev = [Int32](repeating: -1, count: n * 4)
        var heap = MinHeap()
        for d in 0..<4 { let k = (s.1 * w + s.0) * 4 + d; dist[k] = 0; heap.push(0, Int32(k)) }
        var goal: Int32 = -1
        while let (c, k) = heap.pop() {
            guard c == dist[Int(k)] else { continue }
            let cellIndex = Int(k) / 4, d = Int(k) % 4, x = cellIndex % w, y = cellIndex / w
            if x == e.0 && y == e.1 { goal = k; break }
            for (nd, v) in dirs.enumerated() {
                let nx = x + v.0, ny = y + v.1
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let g = grid[ny * w + nx]
                guard g < 2 else { continue }
                let cost = c + 1 + (nd == d ? 0 : turn) + (g == 1 ? near : 0)
                let nk = (ny * w + nx) * 4 + nd
                if cost < dist[nk] { dist[nk] = cost; prev[nk] = k; heap.push(cost, Int32(nk)) }
            }
        }
        guard goal >= 0 else { return Self.ell(a, b) }
        var cells: [CGPoint] = []
        var k = goal
        while k >= 0 { let ci = Int(k) / 4; cells.append(center(ci % w, ci / w)); k = prev[Int(k)] }
        cells.reverse()
        // a, then into the grid, along it, out to b; each join as an L so every leg stays on one axis
        var pts = [a] + Self.ell(a, cells[0]).dropFirst() + cells.dropFirst()
        pts += Self.ell(cells[cells.count - 1], b).dropFirst()
        return Self.simplify(pts)
    }

    /// Two points joined by at most two axis-aligned legs (the longer leg first).
    static func ell(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        if abs(a.x - b.x) < 0.001 || abs(a.y - b.y) < 0.001 { return [a, b] }
        return abs(b.x - a.x) >= abs(b.y - a.y) ? [a, CGPoint(x: b.x, y: a.y), b] : [a, CGPoint(x: a.x, y: b.y), b]
    }

    /// Drops points in the middle of a straight leg and repeats.
    static func simplify(_ p: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for q in p {
            if let l = out.last, hypot(l.x - q.x, l.y - q.y) < 0.001 { continue }
            if out.count >= 2 {
                let a = out[out.count - 2], b = out[out.count - 1]
                if (abs(a.x - b.x) < 0.001 && abs(b.x - q.x) < 0.001) || (abs(a.y - b.y) < 0.001 && abs(b.y - q.y) < 0.001) { out[out.count - 1] = q; continue }
            }
            out.append(q)
        }
        return out
    }
}

/// A binary min-heap of (cost, key).
struct MinHeap {
    private var a: [(Int32, Int32)] = []
    mutating func push(_ c: Int32, _ k: Int32) {
        a.append((c, k)); var i = a.count - 1
        while i > 0 { let p = (i - 1) / 2; if a[p].0 <= a[i].0 { break }; a.swapAt(p, i); i = p }
    }
    mutating func pop() -> (Int32, Int32)? {
        guard !a.isEmpty else { return nil }
        let top = a[0]; let last = a.removeLast()
        if !a.isEmpty {
            a[0] = last; var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1; var m = i
                if l < a.count, a[l].0 < a[m].0 { m = l }
                if r < a.count, a[r].0 < a[m].0 { m = r }
                if m == i { break }
                a.swapAt(i, m); i = m
            }
        }
        return top
    }
}

/// The Server room's rack lights (D26): how bright each LED is at time t. Pure, so a still frame and the tests agree.
public enum RackLights {
    /// The status LED (top): ok breathes, warn blinks, down blinks fast. With animations off: fully on.
    public static func status(_ state: String, rack: Int, t: Double, animated: Bool) -> CGFloat {
        guard animated else { return 1 }
        switch state {
        case "warn": return t.truncatingRemainder(dividingBy: 1.2) < 0.6 ? 1 : 0
        case "down": return t.truncatingRemainder(dividingBy: 0.5) < 0.25 ? 1 : 0
        default:
            let ph = (t + Double(rack) * 0.37) / 2.4 * 2 * .pi
            return CGFloat(0.775 + 0.225 * sin(ph))
        }
    }
    /// The activity LED (bottom): a random hold every 1/8 s, seeded per rack; dark when the server is down.
    public static func activity(_ state: String, rack: Int, t: Double, animated: Bool) -> CGFloat {
        if state == "down" { return 0 }
        guard animated else { return 0.85 }
        var r = SeededRandom(UInt64(rack + 1) &* 2654435761 &+ UInt64(max(0, Int(t * 8))) &* 40503)
        _ = r.next()
        if r.next() < 0.4 { return 0 }
        return [0.35, 0.6, 0.85][min(2, Int(r.next() * 3))]
    }
    /// The roof beacon: off when all is well, blinking yellow for a warning, faster red when something is down.
    public static func beacon(_ worst: String?, t: Double, animated: Bool) -> CGFloat {
        guard let worst, worst != "ok" else { return 0 }
        guard animated else { return 1 }
        let period = worst == "down" ? 0.5 : 0.9
        return t.truncatingRemainder(dividingBy: period) < period / 2 ? 1 : 0
    }
}
