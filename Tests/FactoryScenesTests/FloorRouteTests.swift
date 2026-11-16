import CoreGraphics
import Testing
@testable import FactoryScenes

/// Walks on the atrium's real furniture and walls (AtriumFixture, from the art engine): a way from one room to another
/// goes out through the room's door, round the hall and in through the next door, and keeps clear of every solid thing.
struct FloorRouteTests {
    let map = FloorScene.walkMap(AtriumFixture.solids)

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    /// Every point along a route, a twentieth of a tile apart.
    private func samples(_ r: [CGPoint]) -> [(p: CGPoint, along: CGFloat)] {
        var out: [(CGPoint, CGFloat)] = [], walked: CGFloat = 0
        for (a, b) in zip(r, r.dropFirst()) {
            let d = hypot(b.x - a.x, b.y - a.y), n = max(1, Int(d / 0.05))
            for k in 0..<n { let t = CGFloat(k) / CGFloat(n); out.append((CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), walked + d * t)) }
            walked += d
        }
        if let l = r.last { out.append((l, walked)) }
        return out
    }

    @Test func planningToLoungeGoesThroughTheDoorsAndKeepsClear() throws {
        let from = try #require(AtriumFixture.spots["planning"]?.first), to = try #require(AtriumFixture.spots["lounge"]?[1])
        let route = map.route(CGPoint(x: from.i, y: from.j), CGPoint(x: to.i, y: to.j))
        let pts = samples(route), total = pts.last?.along ?? 0
        #expect(total > 5)
        for (p, along) in pts {
            // never in the Development room next door (the glass partition at i = 14)
            #expect(!(p.x > 13.95 && p.y < 5), "into the next room at \(p)")
            // out of Planning only through its door (i 10.5…11.5 in the hall wall at j = 5)
            if abs(p.y - 5) < 0.1 { #expect(p.x > 10.5 && p.x < 11.5, "through the hall wall at \(p)") }
            // into the Lounge only through its door (j 9.5…10.5 in the wall at i = 3)
            if abs(p.x - 3) < 0.1, p.y > 9 { #expect(p.y > 9.5 && p.y < 10.5, "through the lounge wall at \(p)") }
            // getting out of the chair and sitting down aside, a person keeps clear of everything solid
            guard along > 0.8, along < total - 0.8 else { continue }
            #expect(map.free(p), "on a solid cell at \(p)")
            for r in AtriumFixture.solids {
                let wall = min(r.width, r.height) < 0.2
                #expect(distance(p, r) >= (wall ? 0.34 : 0.17), "brushes \(r) at \(p)")
            }
        }
    }

    @Test func everyRoomReachesEveryOtherWithoutWalkingThroughThings() throws {
        let rooms = ["research", "entrance", "planning", "development", "builds", "testing", "pullRequests", "deploy", "lounge", "needsYou", "parked"]
        for a in rooms { for b in rooms where a != b {
            guard let s = AtriumFixture.spots[a]?.first, let e = AtriumFixture.spots[b]?.first else { continue }
            let route = map.route(CGPoint(x: s.i, y: s.j), CGPoint(x: e.i, y: e.j))
            let pts = samples(route), total = pts.last?.along ?? 0
            for (p, along) in pts where along > 0.8 && along < total - 0.8 {
                #expect(map.free(p), "\(a) → \(b) crosses a solid cell at \(p)")
            }
        } }
    }
}
