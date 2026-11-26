import Foundation
import Testing
@testable import FactoryCore

/// One count of what waits for you (UX review 26 Nov, point 1): the Needs you segment, the Overview tab and its card,
/// the CEO's plate and ⌘K all say the same number for a floor.
struct WaitingCountTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func ship(_ id: String, _ phase: String) -> String {
        "---\nid: \(id)\ntitle: Piece \(id)\nphase: \(phase)\ntype: feature\nopened: 2026-11-20\n---\n\n## Log\n- 2026-11-20 \(phase): moved.\n"
    }
    func question(_ id: String, kind: String = "ship", status: String = "open", workstream: String = "null") -> String {
        "---\nid: \(id)\ntitle: Q \(id)?\nkind: \(kind)\nstatus: \(status)\nworkstream: \(workstream)\nasked: 2026-11-20T10:00:00Z\n---\n\n## Why\nx\n"
    }

    @Test func theDemoFactoryCountsItsQuestionsToDosAndOneRelease() throws {
        let w = Fixture.world(now: now)
        let p = try #require(w.projects.first { $0.root == Fixture.factoryRoot })
        let f = try #require(p.factory)
        // D-0007 and D-0008 (questions), D-0010 and D-0011 (to-dos), and W-006 waiting for its release
        #expect(f.openDecisions.count == 4)
        #expect(f.readyToRelease.map(\.id) == ["W-006"])
        #expect(f.waiting == 5)
        // the floor's count is the same as its items in Needs you (its chats do not wait here)
        #expect(w.waiting(project: p.id) == 5)
        #expect(w.waiting(project: p.id) == w.needsYou.filter { $0.project.id == p.id }.count)
    }

    @Test func severalReadyPiecesAreOneRelease() {
        let f = FactoryText.factory(root: "/demo/x", files: [
            "factory/workstreams/W-001-a.md": ship("W-001", "ship"),
            "factory/workstreams/W-002-b.md": ship("W-002", "ship"),
            "factory/decisions/D-0001-q.md": question("D-0001", kind: "plan"),
        ])
        #expect(f.readyToRelease.count == 2)
        #expect(f.waiting == 2, "one question and one release, however many pieces it holds")
    }

    @Test func nothingReadyCountsOnlyTheOpenOnes() {
        let f = FactoryText.factory(root: "/demo/x", files: [
            "factory/workstreams/W-001-a.md": ship("W-001", "build"),
            "factory/decisions/D-0001-q.md": question("D-0001"),
            "factory/decisions/D-0002-q.md": question("D-0002", status: "yes"),
        ])
        #expect(f.waiting == 1)
        #expect(Factory(root: "/demo/empty").waiting == 0)
    }

    @Test func aWaitingChatCountsOnItsFloor() {
        let w = Fixture.world(now: now)
        // every floor, factory or not, with or without chats that wait
        for p in w.projects {
            #expect(w.waiting(project: p.id) == w.needsYou.filter { $0.project.id == p.id }.count, "\(p.name)")
        }
        #expect(w.waiting(project: "nowhere") == 0)
    }

    @Test func aReleaseSaysWhatItIs() {
        let one = Workstream(id: "W-006", title: "Sharper hint arrows", phase: .ship)
        let two = Workstream(id: "W-007", title: "Other", phase: .ship)
        #expect(NeedsYou.releaseTitle([one]) == "Release Sharper hint arrows")
        #expect(NeedsYou.releaseTitle([one, two]) == "Release 2 finished pieces")
    }

    @Test func kindsInPlainWords() {
        #expect(FactoryDecision(id: "D-1", title: "x", kind: "ship").plainKind == "ship it?")
        #expect(FactoryDecision(id: "D-1", title: "x", kind: "promote").plainKind == "ask less?")
        #expect(FactoryDecision(id: "D-1", title: "x", kind: "fix").plainKind == "fix?")
        #expect(FactoryDecision(id: "D-1", title: "x", kind: "plan").plainKind == "build it?")
        #expect(FactoryDecision(id: "D-1", title: "x", kind: "todo").plainKind == "to-do")
        var d = FactoryDecision(id: "D-1", title: "x", kind: "todo"); d.forWhom = "devops"
        #expect(d.plainKind == "DevOps to-do")
        #expect(FactoryDecision(id: "D-1", title: "x", kind: "weird").plainKind == "question")
    }
}
