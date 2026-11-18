import Foundation
import Testing
@testable import FactoryCore

/// Everyone on the campus has a name of their own (D80 review): two people never share a name, a factory's CEO keeps
/// its name, and names stay put between refreshes.
@Suite struct UniqueNamesTests {
    func session(_ id: String, root: String, title: String = "Some work") -> Session {
        Session(id: id, provider: .claude, cwd: root, title: title, lastAt: Date(), turnOpen: false)
    }

    /// seeds that land on the same name as `seed`
    func clashing(_ seed: String, count: Int) -> [String] {
        let name = Persona(id: seed).name
        return (0..<5000).map { "s\($0)" }.filter { Persona(id: $0).name == name && $0 != seed }.prefix(count).map { $0 }
    }

    @Test func twoPeopleNeverShareAName() {
        let ids = clashing("a", count: 3) + ["a"]
        let p = Project(id: "claude:/p", provider: .claude, root: "/p", name: "P", isChat: false, sessions: ids.map { session($0, root: "/p") })
        let w = World(now: Date(), buildings: [ProviderBuilding(provider: .claude, projects: [p])]).withUniqueNames()
        let names = w.projects[0].sessions.map(\.persona.name)
        #expect(Set(names).count == names.count)
        // the first in order keeps the name its seed gives
        let first = w.projects[0].sessions.sorted { $0.id < $1.id }[0]
        #expect(first.persona.name == Persona(id: first.id).name)
    }

    @Test func aFactorysCEOChoosesFirstAndKeepsItsName() {
        let root = "/f"
        let ceoName = Persona(id: "ceo:" + root).name
        // a plain chat elsewhere whose seed lands on the CEO's name, and sorts before the factory
        let rival = (0..<5000).map { "r\($0)" }.first { Persona(id: $0).name == ceoName }!
        let other = Project(id: "claude:/a", provider: .claude, root: "/a", name: "A", isChat: false, sessions: [session(rival, root: "/a")])
        var factory = Project(id: "claude:/f", provider: .claude, root: root, name: "F", isChat: false,
                              sessions: [session("run1", root: root, title: "Pebble factory: CEO run")],
                              factory: FactoryText.factory(root: root, files: [:]))
        factory.sessions[0].projectRoot = root
        let w = World(now: Date(), buildings: [ProviderBuilding(provider: .claude, projects: [other, factory])]).withUniqueNames()
        let f = w.projects.first { $0.root == root }!, a = w.projects.first { $0.root == "/a" }!
        #expect(f.sessions[0].persona.name == ceoName)
        #expect(a.sessions[0].persona.name != ceoName)
        #expect(f.ceoName == ceoName)
    }

    @Test func aRestingStandInCEOGetsTheReservedName() {
        let root = "/f"
        let p = Project(id: "claude:/f", provider: .claude, root: root, name: "F", isChat: false, sessions: [],
                        factory: FactoryText.factory(root: root, files: [:]))
        let w = World(now: Date(), buildings: [ProviderBuilding(provider: .claude, projects: [p])]).withUniqueNames()
        let standing = w.projects[0].withStandingCEO.sessions.last!
        #expect(standing.persona.name == Persona(id: "ceo:" + root).name)
    }

    @Test func namesStayPutBetweenRefreshes() {
        let ids = clashing("x", count: 2) + ["x", "y", "z"]
        let p = Project(id: "claude:/p", provider: .claude, root: "/p", name: "P", isChat: false, sessions: ids.map { session($0, root: "/p") })
        let w1 = World(now: Date(), buildings: [ProviderBuilding(provider: .claude, projects: [p])]).withUniqueNames()
        var shuffled = p; shuffled.sessions.reverse()
        let w2 = World(now: Date(), buildings: [ProviderBuilding(provider: .claude, projects: [shuffled])]).withUniqueNames()
        let n1 = Dictionary(uniqueKeysWithValues: w1.projects[0].sessions.map { ($0.id, $0.persona.name) })
        let n2 = Dictionary(uniqueKeysWithValues: w2.projects[0].sessions.map { ($0.id, $0.persona.name) })
        #expect(n1 == n2)
    }
}
