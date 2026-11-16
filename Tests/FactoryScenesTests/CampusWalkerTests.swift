import CoreGraphics
import Testing
import FactoryCore
@testable import FactoryScenes

/// The team on the campus roads keeps its distance: nobody starts on top of someone else, nobody walks through anyone,
/// and nobody stands still for good.
@MainActor
struct CampusWalkerTests {
    private func campus(_ n: Int, seed: String = "walker") -> CampusScene {
        let scene = CampusScene(size: CGSize(width: 1200, height: 800))
        var figures: [CastKey: Figure] = [:]
        for k in 0..<n { figures[CastKey(role: CastRole.allCases[k % CastRole.allCases.count], seed: "\(seed)-\(k)")] = Figure([:]) }
        scene.placeWalkers(figures, fresh: true)
        return scene
    }

    private func closest(_ scene: CampusScene) -> CGFloat {
        let p = scene.walkers.values.map(\.pos)
        var best = CGFloat.infinity
        for a in p.indices { for b in p.indices where b > a { best = min(best, hypot(p[a].x - p[b].x, p[a].y - p[b].y)) } }
        return best
    }

    @Test(arguments: ["walker", "team", "session"]) func walkersStartApart(seed: String) {
        let scene = campus(CampusScene.walkerCount, seed: seed)
        #expect(scene.walkers.count == CampusScene.walkerCount)
        #expect(closest(scene) >= CampusScene.spawnGap - 0.001)
    }

    @Test(arguments: ["walker", "team", "session", "crew", "night"]) func walkersNeverWalkThroughEachOther(seed: String) {
        let scene = campus(CampusScene.walkerCount, seed: seed)
        var worst = CGFloat.infinity, follow = CGFloat.infinity
        var moved: [String: CGFloat] = [:]
        var last = Dictionary(uniqueKeysWithValues: scene.walkers.map { ($0.key, $0.value.pos) })
        // five minutes at 30 frames a second
        for _ in 0..<(300 * 30) {
            scene.tick(1.0 / 30)
            worst = min(worst, closest(scene))
            // one behind another on the same lane, walking the same way: clear of each other (a queue keeps a whole step;
            // only at a corner, where one turns in just ahead of another, is it a little less)
            let list = Array(scene.walkers.values)
            for a in list.indices { for b in list.indices where b > a {
                let p = list[a], q = list[b]
                guard p.dir == q.dir, !p.path.isEmpty, !q.path.isEmpty, p.idle <= 0, q.idle <= 0 else { continue }
                if abs(p.pos.x - q.pos.x) < 0.05 || abs(p.pos.y - q.pos.y) < 0.05 { follow = min(follow, hypot(p.pos.x - q.pos.x, p.pos.y - q.pos.y)) }
            } }
            for (k, w) in scene.walkers { moved[k, default: 0] += hypot(w.pos.x - last[k]!.x, w.pos.y - last[k]!.y); last[k] = w.pos }
        }
        #expect(worst >= 0.55, "two walkers came within \(worst) tile")
        #expect(follow >= 0.62, "one followed another at \(follow) tile")
        // everyone gets about: a few trips' worth in five minutes
        for (k, d) in moved { #expect(d > 50, "\(k) walked only \(d) tiles") }
    }

    /// On screen too: a lane that runs towards you puts people a tile apart half in front of each other. Two walking
    /// on with their bodies overlapping by more than a third never last long (they read as one two-headed figure). Only a
    /// merge at a corner of the roundabout, where one waits for the other to turn in, may hold them for a few seconds.
    @Test(arguments: ["walker", "team", "session", "crew", "night"]) func walkersDoNotWalkGluedOnScreen(seed: String) {
        let scene = campus(CampusScene.walkerCount, seed: seed)
        var glued: [String: Double] = [:], longest = 0.0
        for _ in 0..<(300 * 30) {
            scene.tick(1.0 / 30)
            let list = scene.walkers.values.sorted { $0.key < $1.key }
            for a in list.indices { for b in list.indices where b > a {
                let p = list[a], q = list[b], k = p.key + "|" + q.key
                let fp = project(p.pos.x, p.pos.y), fq = project(q.pos.x, q.pos.y)
                let overlap = abs(fp.x - fq.x) < CampusScene.body.width * 0.66 && abs(fp.y - fq.y) < CampusScene.body.height * 0.66
                let moving = p.idle <= 0 && q.idle <= 0 && !p.path.isEmpty && !q.path.isEmpty
                glued[k] = overlap && moving ? glued[k, default: 0] + 1.0 / 30 : 0
                longest = max(longest, glued[k]!)
            } }
        }
        #expect(longest < 4.5, "two walkers walked glued together for \(longest) s")
    }

    /// The walkers the app puts out for the fixture world: the most recent sessions' cast.
    private func fixtureCampus() -> CampusScene {
        let world = Fixture.world()
        let keys = world.projects.flatMap { p in p.sessions.map { (p, $0) } }.sorted { $0.1.lastAt > $1.1.lastAt }
            .prefix(CampusScene.walkerCount).map { $0.0.cast(of: $0.1) }
        let scene = CampusScene(size: CGSize(width: 1200, height: 800))
        scene.placeWalkers(Dictionary(keys.map { ($0, Figure([:])) }, uniquingKeysWith: { a, _ in a }), fresh: true)
        return scene
    }

    /// No knots: three or more within a tile and a half of each other, two of them standing (waiting for each other),
    /// read as one lump. Passing each other on the two lanes of a road is fine; a merge may hold three for a moment.
    @Test(arguments: ["fixture", "walker", "team", "session", "crew", "night"]) func noKnotsRoundTheFountain(seed: String) {
        let scene = seed == "fixture" ? fixtureCampus() : campus(CampusScene.walkerCount, seed: seed)
        var run = 0.0, longest = 0.0, frame = 0
        var trail: [String: [CGPoint]] = [:]       // where each was over the last second
        for _ in 0..<(300 * 30) {
            scene.tick(1.0 / 30); frame += 1
            for (k, w) in scene.walkers { trail[k, default: []].append(w.pos); if trail[k]!.count > 30 { trail[k]!.removeFirst() } }
            guard frame > 30 else { continue }
            // standing: moved less than a third of a tile in the last second (waiting, or resting at a road end)
            let list = scene.walkers.map { (k, w) in (pos: w.pos, standing: hypot(w.pos.x - trail[k]![0].x, w.pos.y - trail[k]![0].y) < 0.33) }
            let knot = list.contains { a in
                let near = list.filter { hypot($0.pos.x - a.pos.x, $0.pos.y - a.pos.y) < 1.5 }
                return near.count >= 3 && near.filter(\.standing).count >= 2
            }
            run = knot ? run + 1.0 / 30 : 0
            longest = max(longest, run)
        }
        #expect(longest < 3, "three or more stood in a knot for \(longest) s")
    }
}
