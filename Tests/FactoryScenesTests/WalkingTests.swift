import CoreGraphics
import Testing
@testable import FactoryScenes

/// People face the way they walk (blocky views: +i SE, +j SW, -i NW, -j NE), walk only along i or j, and their feet
/// stay put (the step cycle follows the distance).
struct WalkingTests {
    @Test func facingFollowsTheTileAxis() {
        #expect(Facing.dir(1, 0) == "right")     // +i: down-right on screen, SE (front-right)
        #expect(Facing.dir(0, 1) == "down")      // +j: down-left, SW (front-left)
        #expect(Facing.dir(-1, 0) == "left")     // -i: up-left, NW (back-left)
        #expect(Facing.dir(0, -1) == "up")       // -j: up-right, NE (back-right)
        #expect(Facing.dir(2, 0.3) == "right")
        #expect(Facing.dir(-0.2, -3) == "up")
    }

    @Test func nearDiagonalsKeepTheCurrentSide() {
        #expect(Facing.dir(1, 0.95, current: "down") == "down")
        #expect(Facing.dir(1, 0.95, current: "right") == "right")
        #expect(Facing.dir(1, 0.95, current: "up") == "right")       // not a side of this step: the dominant axis wins
        #expect(Facing.dir(0, 0, current: "left") == "left")
    }

    @Test func turningRoundPassesAFrontSide() {
        #expect(Facing.via("left", "right") == "down")
        #expect(Facing.via("up", "down") == "right")
        #expect(Facing.via("left", "down") == nil)
        #expect(Facing.front(of: "left") == "down")
        #expect(Facing.front(of: "up") == "right")
        #expect(Facing.front(of: "right") == "right")
    }

    @Test func stepsFollowTheDistance() {
        #expect(StepCycle.pose(distance: 0) == "walkA")
        #expect(StepCycle.pose(distance: 0.3) == "idle")
        #expect(StepCycle.pose(distance: 0.5) == "walkB")
        #expect(StepCycle.pose(distance: 0.8) == "idle")
        #expect(StepCycle.pose(distance: 0.9) == "walkA")
    }

    private func axisAligned(_ p: [CGPoint]) -> Bool {
        zip(p, p.dropFirst()).allSatisfy { abs($0.x - $1.x) < 0.001 || abs($0.y - $1.y) < 0.001 }
    }

    @Test func campusTripsStayOnTheRoads() {
        let arms = CampusRoads.arms
        for a in arms.indices { for b in arms.indices {
            let t = CampusRoads.trip(from: a, to: b)
            #expect(t.first == arms[a].outEnd)
            #expect(t.last == arms[b].outEnd)
            #expect(t.count > 3, "a trip goes round the fountain")
            #expect(axisAligned(t), "trip \(a) → \(b) has a diagonal leg")
            // never through the fountain's basin
            let basin = CGRect(x: 13.4, y: 11.4, width: 3.2, height: 3.2)
            for (p, q) in zip(t, t.dropFirst()) {
                for k in 0...10 {
                    let m = CGPoint(x: p.x + (q.x - p.x) * CGFloat(k) / 10, y: p.y + (q.y - p.y) * CGFloat(k) / 10)
                    #expect(!basin.contains(m))
                }
            }
        } }
    }

    @Test func floorRoutesGoRoundThingsAlongTheAxes() {
        // a room with a table in the middle: the way from one side to the other goes round it
        let table = CGRect(x: 2, y: 1, width: 2, height: 3)
        let map = FloorWalkMap(area: [CGRect(x: 0, y: 0, width: 6, height: 5)], holes: [], solid: [table])
        let r = map.route(CGPoint(x: 1, y: 2.5), CGPoint(x: 5, y: 2.5))
        #expect(r.first == CGPoint(x: 1, y: 2.5))
        #expect(r.last == CGPoint(x: 5, y: 2.5))
        #expect(axisAligned(r))
        for (p, q) in zip(r, r.dropFirst()) {
            for k in 0...20 {
                let m = CGPoint(x: p.x + (q.x - p.x) * CGFloat(k) / 20, y: p.y + (q.y - p.y) * CGFloat(k) / 20)
                #expect(!table.contains(m), "walks through the table at \(m)")
            }
        }
    }

    @Test func rackLightsSayTheState() {
        // a still frame shows every light on
        #expect(RackLights.status("warn", rack: 0, t: 0.9, animated: false) == 1)
        // warn blinks 0.6 s on, 0.6 s off; down twice as fast
        #expect(RackLights.status("warn", rack: 0, t: 0.3, animated: true) == 1)
        #expect(RackLights.status("warn", rack: 0, t: 0.9, animated: true) == 0)
        #expect(RackLights.status("down", rack: 3, t: 0.1, animated: true) == 1)
        #expect(RackLights.status("down", rack: 3, t: 0.3, animated: true) == 0)
        // ok breathes between 0.55 and 1
        for k in 0..<20 {
            let a = RackLights.status("ok", rack: 2, t: Double(k) * 0.13, animated: true)
            #expect(a >= 0.549 && a <= 1.001)
        }
        // a server that is down shows no activity
        #expect(RackLights.activity("down", rack: 1, t: 2, animated: true) == 0)
        #expect(RackLights.beacon(nil, t: 0, animated: true) == 0)
        #expect(RackLights.beacon("ok", t: 0, animated: true) == 0)
        #expect(RackLights.beacon("down", t: 0.1, animated: true) == 1)
        #expect(RackLights.beacon("down", t: 0.3, animated: true) == 0)
    }
}
