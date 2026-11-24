import Foundation
import Testing
@testable import FactoryCollector
@testable import FactoryCore

/// To-dos and your own releases (contract v5, D81): what a CEO needs from you is a decision with a button, never only a
/// line in the briefing; finished work that nobody asked to release waits under Needs you with Release now.
/// Fictional data only.
struct TodoReleaseTests {
    private let fm = FileManager.default

    private func tempRoot() throws -> URL {
        let u = fm.temporaryDirectory.appendingPathComponent("sf-release-\(UUID().uuidString)")
        try fm.createDirectory(at: u.appendingPathComponent("factory/decisions"), withIntermediateDirectories: true)
        try fm.createDirectory(at: u.appendingPathComponent("factory/workstreams"), withIntermediateDirectories: true)
        return u
    }

    private func workstream(_ id: String, phase: String) -> String {
        """
        ---
        id: \(id)
        title: Puzzle fix \(id)
        phase: \(phase)
        ---

        ## Log
        - 2026-11-20 test → \(phase): tests pass.
        """
    }

    private func decision(_ id: String, kind: String, status: String, workstreams: String, extra: String = "") -> String {
        """
        ---
        id: \(id)
        title: Something about \(workstreams)?
        kind: \(kind)
        status: \(status)
        workstreams: [\(workstreams)]
        asked: 2026-11-20T09:00:00+01:00
        \(extra)---

        ## Why
        Because.
        """
    }

    private func factory(_ files: [String: String]) -> Factory {
        FactoryText.factory(root: "/demo/pebble", files: files)
    }

    @Test func aToDoReadsWithItsStepsAndWaitsForYou() throws {
        let text = """
        ---
        id: D-0003
        title: Allow the error tracker's read tools in this project's allowlist
        kind: todo
        status: open
        asked: 2026-11-24T10:00:00+01:00
        ---

        ## Why
        The CEO cannot read new errors without them.

        ## How
        Add the tools to .claude/settings.json under permissions.allow.
        """
        let d = try #require(FactoryText.decision(text, file: "factory/decisions/D-0003-allow.md"))
        #expect(d.isTodo)
        #expect(!d.fromYou)
        #expect(d.how.contains("settings.json"))
        let f = factory(["factory/decisions/D-0003-allow.md": text])
        #expect(f.openDecisions.map(\.id) == ["D-0003"])
    }

    @Test func shipWorkWithoutAnOpenOrYesShipQuestionIsReadyToRelease() {
        let files = [
            "factory/workstreams/W-002-a.md": workstream("W-002", phase: "ship"),
            "factory/workstreams/W-003-b.md": workstream("W-003", phase: "ship"),
            "factory/workstreams/W-004-c.md": workstream("W-004", phase: "ship"),
            "factory/workstreams/W-005-d.md": workstream("W-005", phase: "ship"),
            "factory/workstreams/W-006-e.md": workstream("W-006", phase: "test"),
            // a no leaves its work waiting; an open question or an unshipped yes covers it; a yes on a plan does not
            "factory/decisions/D-0001-no.md": decision("D-0001", kind: "ship", status: "no", workstreams: "W-002"),
            "factory/decisions/D-0002-open.md": decision("D-0002", kind: "ship", status: "open", workstreams: "W-003"),
            "factory/decisions/D-0003-yes.md": decision("D-0003", kind: "ship", status: "yes", workstreams: "W-004",
                                                        extra: "answered: 2026-11-20T10:00:00+01:00\n"),
            "factory/decisions/D-0004-plan.md": decision("D-0004", kind: "plan", status: "yes", workstreams: "W-005",
                                                         extra: "answered: 2026-11-20T10:00:00+01:00\n"),
        ]
        #expect(factory(files).readyToRelease.map(\.id) == ["W-002", "W-005"])
    }

    @Test func aLaterNoOnTheReleaseOutweighsAnEarlierYesOnTheMerge() {
        let files = [
            "factory/workstreams/W-002-a.md": workstream("W-002", phase: "ship"),
            "factory/decisions/D-0007-merge.md": decision("D-0007", kind: "ship", status: "yes", workstreams: "W-002",
                                                          extra: "answered: 2026-11-16T11:32:40+01:00\n"),
            "factory/decisions/D-0009-release.md": decision("D-0009", kind: "ship", status: "no", workstreams: "W-002",
                                                            extra: "answered: 2026-11-16T13:37:48+01:00\n"),
        ]
        #expect(factory(files).readyToRelease.map(\.id) == ["W-002"])
    }

    @Test func aLogLineWrappedOverTwoLinesStaysOneEntry() {
        let text = """
        ---
        id: W-002
        title: Puzzle fix
        phase: ship
        ---

        ## Log
        - 2026-11-16 ship: you said no on D-0009. It stays on develop; the release
          is asked again later as a larger batch.
        - 2026-11-17 note: nothing new.
        """
        let w = FactoryText.workstream(text)
        #expect(w?.log.count == 2)
        #expect(w?.log.first?.text.hasSuffix("asked again later as a larger batch.") == true)
    }

    @Test func readyWorkIsOneItemUnderNeedsYouPerFactory() {
        var p = Project(id: "claude:/demo/pebble", provider: .claude, root: "/demo/pebble", name: "Pebble", isChat: false, sessions: [])
        p.factory = factory([
            "factory/workstreams/W-002-a.md": workstream("W-002", phase: "ship"),
            "factory/workstreams/W-003-b.md": workstream("W-003", phase: "ship"),
        ])
        let w = World(now: Date(), buildings: [ProviderBuilding(provider: .claude, projects: [p])])
        #expect(w.needsYou.count == 1)
        #expect(w.needsYou.first?.title == "Release W-002 and W-003")
        #expect(w.needsYou.first?.group == .factories)
        #expect(w.needsYou.first?.since != .distantPast, "it says how long it waits, from its log")
    }

    @Test func releasingWritesAYesYouStartedThatCoversTheWork() throws {
        let root = try tempRoot()
        defer { try? fm.removeItem(at: root) }
        // the CEO's own D-0007 is taken: the release gets the next number
        try decision("D-0007", kind: "ship", status: "no", workstreams: "W-002")
            .write(to: root.appendingPathComponent("factory/decisions/D-0007-earlier.md"), atomically: true, encoding: .utf8)
        for id in ["W-002", "W-003"] {
            try workstream(id, phase: "ship").write(to: root.appendingPathComponent("factory/workstreams/\(id)-x.md"), atomically: true, encoding: .utf8)
        }
        let before = FactoryFinder.read(root: root.path)
        #expect(before.readyToRelease.count == 2)

        let id = try ReleaseRequest.send(root: root.path, workstreams: before.readyToRelease)
        #expect(id == "D-0008")
        let after = FactoryFinder.read(root: root.path)
        let d = try #require(after.decisions.first { $0.id == id })
        #expect(d.status == .yes && d.fromYou && d.kind == "ship")
        #expect(d.workstreams == ["W-002", "W-003"])
        #expect(d.answered != nil)
        #expect(after.readyToRelease.isEmpty)
        #expect(after.openDecisions.isEmpty, "your own release is already answered: nothing to answer again")
    }

    @Test func aReleaseNeverOverwritesAFile() throws {
        let root = try tempRoot()
        defer { try? fm.removeItem(at: root) }
        let w = Workstream(id: "W-002", title: "Puzzle fix", phase: .ship)
        let first = try ReleaseRequest.send(root: root.path, workstreams: [w])
        let second = try ReleaseRequest.send(root: root.path, workstreams: [w])
        #expect(first == "D-0001" && second == "D-0002")
        #expect(throws: ReleaseRequest.Failure.self) { try ReleaseRequest.send(root: root.path, workstreams: []) }
    }

    @Test func theCEOIsToldToAskWithButtonsNotInProse() {
        let prompt = HeartbeatRunner.prompt(root: "/demo/pebble", name: "Pebble", reason: .runNow)
        #expect(prompt.contains("kind: todo"))
        #expect(prompt.contains("from: you"))
        #expect(prompt.contains("Never ask the user for anything in the briefing's prose alone"))
    }
}

/// Meatproxy's own new files in a factory (an idea, a release) are created, never replaced: a file with that name that
/// appeared in the meantime stays as it was.
struct NewFileTests {
    @Test func aNewFileNeverReplacesOneThatIsThere() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sf-newfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("I-0003-idea.md")
        try "the CEO's file".write(to: url, atomically: true, encoding: .utf8)
        #expect(try NewFile.create(url, text: "Meatproxy's file") == false)
        #expect(try String(contentsOf: url, encoding: .utf8) == "the CEO's file")
        let fresh = dir.appendingPathComponent("I-0004-idea.md")
        #expect(try NewFile.create(fresh, text: "Meatproxy's file") == true)
        #expect(try String(contentsOf: fresh, encoding: .utf8) == "Meatproxy's file")
    }
}
