import Foundation
import Testing
@testable import FactoryScenes
import FactoryCore

/// The campus paints what waits for you into its art (the plaza pillar's count, the yellow blade sign on a storey), so
/// it must repaint whenever that changes. It repainted only when a session changed, so an answered factory question
/// left "1" on the pillar and a "!" on the storey while the quest log said nothing needs you.
@MainActor @Suite struct CampusRepaintTests {
    @Test func answeringAFactoryQuestionRepaintsTheCampus() throws {
        var w = Fixture.world()
        let before = WorldController.signature(w)
        var spot: (Int, Int)?
        for b in w.buildings.indices {
            if let k = w.buildings[b].projects.firstIndex(where: { !($0.factory?.openDecisions.isEmpty ?? true) }) { spot = (b, k); break }
        }
        let (b, k) = try #require(spot)
        w.buildings[b].projects[k].factory?.decisions = []
        #expect(w.needsYou.count != Fixture.world().needsYou.count)
        #expect(WorldController.signature(w) != before)
    }

    @Test func theServerRoomsQuestionsRepaintTheCampusToo() throws {
        var w = Fixture.world()
        w.ops = Project(id: World.opsID, provider: .claude, root: "/ops", name: "Server room", isChat: false, sessions: [], factory: Fixture.factory())
        #expect(!(w.ops?.factory?.openDecisions.isEmpty ?? true))
        let before = WorldController.signature(w)
        w.ops?.factory?.decisions = []
        #expect(WorldController.signature(w) != before)
    }

    @Test func anUnchangedWorldKeepsItsSignature() {
        let w = Fixture.world()
        #expect(WorldController.signature(w) == WorldController.signature(w))
    }
}
