import Foundation
import Testing
@testable import FactoryCollector
import FactoryCore

/// D63: floors you hide stay off the campus, a factory never; the DevOps agent's sessions are no tower floor.
@Suite struct HideTests {
    @Test func hiddenFloorsLeaveTheCampusButFactoriesStay() {
        var w = Fixture.world()
        let shop = w.projects.first { $0.name == "Shopfront" }!.root
        WorldBuilder.hide([shop, Fixture.factoryRoot], in: &w)
        #expect(!w.projects.contains { $0.root == shop })
        // the made-up factory is attached as a factory only once its files are read; here it has none, so attach one
        var withFactory = Fixture.world()
        WorldBuilder.attach([Factory(root: Fixture.factoryRoot)], to: &withFactory)
        WorldBuilder.hide([Fixture.factoryRoot], in: &withFactory)
        #expect(withFactory.projects.contains { $0.root == Fixture.factoryRoot })
    }

    @Test func hiddenSurvivesTheSettingsFileAndOldFilesStillRead() throws {
        var s = ProjectSettings(); s.hidden = ["/demo/old-name"]
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(ProjectSettings.self, from: data).hidden == ["/demo/old-name"])
        #expect(try JSONDecoder().decode(ProjectSettings.self, from: Data("{}".utf8)).hidden.isEmpty)
    }

    @Test func theDevOpsWorkspaceIsNotAProjectFloor() {
        let ws = EngineRoom.folder.path
        #expect(EngineRoom.contains(ws) && EngineRoom.contains(ws + "/journal"))
        #expect(!EngineRoom.contains(ws + "-other") && !EngineRoom.contains("/demo/shopfront"))
    }
}
