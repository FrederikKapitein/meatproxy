import Foundation
import Testing
@testable import FactoryCore

/// What is broken (the quiet line over Needs you, D25's middle way) and what stops when you quit (UX review 26 Nov).
struct AttentionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ id: String, failures: [Double], open: Bool = true) -> Session {
        var acts = [Activity(at: now.addingTimeInterval(-600), kind: .prompt, text: "asked")]
        for f in failures {
            acts.append(Activity(at: now.addingTimeInterval(-f - 5), kind: .edit, text: "edited it"))
            acts.append(Activity(at: now.addingTimeInterval(-f), kind: .test, text: "ran npm test", failed: true))
        }
        return Session(id: id, provider: .claude, cwd: "/demo/x", title: "T \(id)", lastAt: now.addingTimeInterval(-(failures.min() ?? 0)),
                       turnOpen: open, activities: acts)
    }

    @Test func oneFailureIsStuckSinceThatFailure() {
        let s = session("s1", failures: [40])
        #expect(s.stuckSince(now: now) == now.addingTimeInterval(-40))
    }

    @Test func aRunOfFailuresCountsFromItsFirst() {
        // failures 200, 140, 80 and 20 seconds ago: each within 90 s of the next, so stuck since 200 s
        let s = session("s1", failures: [200, 140, 80, 20])
        #expect(s.stuckSince(now: now) == now.addingTimeInterval(-200))
        // a gap of more than 90 s breaks the run
        let t = session("s2", failures: [400, 60, 20])
        #expect(t.stuckSince(now: now) == now.addingTimeInterval(-60))
    }

    @Test func notStuckHasNoStart() {
        #expect(session("s1", failures: [200]).stuckSince(now: now) == nil, "the last failure is too long ago")
        #expect(session("s2", failures: []).stuckSince(now: now) == nil)
    }

    @Test func theDemoCampusHasADownServerAndARedCI() {
        // nightly is down and Harbor API's CI on main is red; Ines and the Harbor session failed a moment ago, which is
        // part of the work, not broken yet
        let w = Fixture.world(now: now)
        #expect(w.broken == ["nightly is down", "Harbor API: CI on main is red"])
    }

    @Test func aSessionStuckForMoreThanTwoMinutesIsBroken() {
        var w = World(now: now, buildings: [ProviderBuilding(provider: .claude, projects: [
            Project(id: "p", provider: .claude, root: "/demo/x", name: "X", isChat: false, sessions: [session("s1", failures: [150, 90, 30])]),
        ])])
        #expect(w.broken.count == 1)
        #expect(w.broken.first?.hasSuffix("is stuck in X") == true)
        // a minute later stuck than the threshold says nothing
        w.buildings[0].projects[0].sessions = [session("s1", failures: [100, 30])]
        #expect(w.broken.isEmpty)
    }

    @Test func brokenThingsNeverCountAsWaiting() {
        let w = Fixture.world(now: now)
        #expect(!w.broken.isEmpty)
        #expect(!w.needsYou.contains { item in
            if case .session(_, let s) = item { return s.state(now: now) == .stuck }
            return false
        })
    }

    @Test func theQuitLineNamesWhatRuns() {
        #expect(RunningWork.line(terminals: 0, ceoRuns: [], devops: false) == nil)
        #expect(RunningWork.line(terminals: 1, ceoRuns: ["Pebble Puzzles"], devops: false) == "1 terminal and the CEO run of Pebble Puzzles will stop.")
        #expect(RunningWork.line(terminals: 2, ceoRuns: [], devops: false) == "2 terminals will stop.")
        #expect(RunningWork.line(terminals: 0, ceoRuns: ["Tide Notes", "Pebble Puzzles"], devops: true)
                == "The CEO runs of Pebble Puzzles and Tide Notes, and the DevOps agent's run will stop.")
        #expect(RunningWork.line(terminals: 3, ceoRuns: ["A"], devops: true) == "3 terminals, the CEO run of A and the DevOps agent's run will stop.")
    }
}
