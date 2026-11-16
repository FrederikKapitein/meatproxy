import Foundation
import Testing
@testable import FactoryCollector
import FactoryCore

/// D69: public status pages, read with a fake network; D68: Meatproxy's own factory in the settings.
@Suite struct StatusPagesTests {
    func page(_ indicator: String) -> Data { Data(#"{"page":{"name":"X"},"status":{"indicator":"\#(indicator)","description":"Words"}}"#.utf8) }

    @Test func statuspageIndicatorsMapToFourStates() {
        #expect(StatusPages.parse(page("none"))?.0 == .ok)
        #expect(StatusPages.parse(page("minor"))?.0 == .degraded)
        #expect(StatusPages.parse(page("major"))?.0 == .down && StatusPages.parse(page("critical"))?.0 == .down)
        #expect(StatusPages.parse(page("odd"))?.0 == .unknown)
        #expect(StatusPages.parse(Data("<html>".utf8)) == nil)
    }

    @Test func aPageNotReadTurnsUnknownNeverGreen() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let answers = Box2()
        let pages = StatusPages { req in answers.next(req.url!.host!) }
        answers.set("status.claude.com", (Data(#"{"status":{"indicator":"major","description":"Outage"}}"#.utf8), 200))
        answers.set("status.openai.com", nil)                        // the network failed
        answers.set("www.githubstatus.com", (page("none"), 200))
        pages.update(StatusSource.defaults, now: t0)
        let s = Dictionary(uniqueKeysWithValues: pages.current().map { ($0.id, $0) })
        #expect(s["claude"]?.shown(now: t0) == .down && s["github"]?.shown(now: t0) == .ok)
        #expect(s["openai"]?.shown(now: t0) == .unknown)              // never read: unknown, not ok
        // fifteen minutes later without a new answer: unknown too
        #expect(s["github"]?.shown(now: t0.addingTimeInterval(16 * 60)) == .unknown)
        // the guard: Claude's factories wait, Codex's do not
        #expect(pages.down("claude", now: t0) == "Claude" && pages.down("codex", now: t0) == nil)
        #expect(pages.down("claude", now: t0.addingTimeInterval(20 * 60)) == nil)   // stale is not "down" either
    }

    @Test func aPageYouTypeBecomesASource() {
        #expect(StatusSource.custom("status.example.com")?.url == "https://status.example.com/api/v2/status.json")
        #expect(StatusSource.custom("https://status.example.com/incidents")?.page == "https://status.example.com")
        #expect(StatusSource.custom("not a host") == nil && StatusSource.custom("http://insecure.example.com") == nil)
    }

    @Test func darkOffSurvivesTheSettingsFileAndAnOldOwnFactoryKeyIsIgnored() throws {
        var s = ProjectSettings(); s.darkOff = ["/demo/meatproxy"]
        let back = try JSONDecoder().decode(ProjectSettings.self, from: JSONEncoder().encode(s))
        #expect(!back.darkAllowed("/demo/meatproxy") && back.darkAllowed("/demo/other"))
        let old = try JSONDecoder().decode(ProjectSettings.self, from: Data(#"{"ownFactory":"/demo/meatproxy"}"#.utf8))
        #expect(old.darkOff.isEmpty)
    }
}

final class Box2: @unchecked Sendable {
    private let lock = NSLock(); private var answers: [String: (Data, Int)?] = [:]
    func set(_ host: String, _ a: (Data, Int)?) { lock.lock(); answers[host] = .some(a); lock.unlock() }
    func next(_ host: String) -> (Data, Int, [String: String])? {
        lock.lock(); defer { lock.unlock() }
        guard let a = answers[host] ?? nil else { return nil }
        return (a.0, a.1, [:])
    }
}
