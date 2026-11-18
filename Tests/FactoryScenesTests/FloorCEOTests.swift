import CoreGraphics
import Foundation
import Testing
import FactoryCore
@testable import FactoryScenes

/// A factory's floor has one CEO (D47): its main chat, the run named CEO. It stands at the board in Planning and, while
/// the factory has open questions, wears the yellow plate (it is the one who asks them); nobody else is plated as CEO.
@MainActor
struct FloorCEOTests {
    private func factoryFloor() throws -> (FloorScene, Project) {
        let world = Fixture.world()
        let p = try #require(world.projects.first { $0.root == Fixture.factoryRoot }).withStandingCEO
        var spots: [String: [[Any]]] = [:]
        for r in FloorRoom.allCases { spots[r.rawValue] = (0..<8).map { k in [2 + Double(k) * 1.5, 2 + Double(k), "idle", "down"] } }
        spots["ceo"] = [[12.9, 1.15, "point", "down"]]
        let art = FloorArt(["spots": spots, "view": [0, 0, 100, 100]])
        var figures: [String: Figure] = [:]
        for s in p.sessions { figures[p.cast(of: s).key] = Figure([:]) }
        for s in p.sessions { for a in s.subAgents { figures[a.cast.key] = Figure([:]) } }
        for t in p.teamSlots { figures[t.cast.key] = Figure([:]) }
        let scene = FloorScene(size: CGSize(width: 1200, height: 800))
        scene.animationsEnabled = false
        scene.apply(art, project: p, figures: figures, now: world.now)
        return (scene, p)
    }

    @Test func theCEORunIsTheOneCEONoStandIn() throws {
        let (_, p) = try factoryFloor()
        #expect(!p.sessions.contains { $0.id.hasPrefix(Project.standingCEOPrefix) }, "a second, resting CEO beside the CEO run")
        let ceo = try #require(p.ceoID)
        let run = try #require(p.sessions.first { $0.id == ceo })
        #expect(run.title.contains("CEO"))
        #expect(p.role(of: run) == .ceo)
        // one name and face everywhere: the CEO is seeded by its project, as its heartbeat's runs and its stand-in are
        #expect(run.persona == Persona(id: "ceo:" + p.root))
        #expect(p.cast(of: run).seed == "ceo:" + p.root)
    }

    /// Shopfront set up as a factory (shot 28): its lead, who waits for you, becomes the CEO. The CEO plate must keep the
    /// waiting state (yellow, "!"), not hide it.
    @Test func aCEOThatWaitsForYouStillShowsIt() throws {
        let world = Fixture.world()
        var shop = try #require(world.projects.first { $0.root == "/demo/shopfront" })
        var f = try #require(world.projects.first { $0.root == Fixture.factoryRoot }?.factory)
        f.decisions = []
        shop.factory = f
        let p = shop.withStandingCEO
        let ceo = try #require(p.ceoID)
        let run = try #require(p.sessions.first { $0.id == ceo })
        #expect(run.state(now: world.now) == .waiting, "the fixture's lead waits for you")
        #expect(FloorScene.shownState(run, in: p, now: world.now) == .waiting)
        #expect(FloorScene.plateLine(run, in: p, state: .waiting, back: false, seated: false, now: world.now) == "CEO · waits for you")
    }

    @Test func aFactoryWithoutACEORunShowsItsStandIn() throws {
        let world = Fixture.world()
        var p = try #require(world.projects.first { $0.root == Fixture.factoryRoot })
        p.sessions = p.sessions.filter { !$0.title.contains("CEO") }.prefix(1).map { $0 }
        let shown = p.withStandingCEO
        #expect(shown.sessions.contains { $0.id.hasPrefix(Project.standingCEOPrefix) })
        #expect(shown.sessions.first { $0.id == shown.ceoID }.map { $0.persona } == Persona(id: "ceo:" + p.root))
    }

    @Test func theCEOStandsAtTheBoardAndCarriesTheOpenQuestions() throws {
        let (scene, p) = try factoryFloor()
        let ceo = try #require(p.ceoID), plates = scene.plates()
        let q = p.factory?.openDecisions.count ?? 0
        #expect(q > 0, "the fixture factory has open questions")
        let mine = try #require(plates[ceo])
        #expect(mine.room == FloorRoom.planning.rawValue)
        #expect(mine.state == .waiting)
        let parts = mine.plate.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        #expect(parts.count >= 3 && parts[0] == p.sessions.first { $0.id == ceo }?.persona.name)
        #expect(parts[1] == "CEO · \(q) questions" && parts[2] == "wait")
        // nobody else is plated as the CEO, and nobody else waits on this floor
        for (id, v) in plates where id != ceo {
            #expect(!v.plate.contains("|CEO"), "\(id) is plated as a CEO: \(v.plate)")
            #expect(v.state != .waiting, "\(id) waits: \(v.plate)")
        }
    }
}
