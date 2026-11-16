import Foundation
import Testing
@testable import FactoryCore

/// The Engine room (D26): servers come from their own source (D20). Without one the world has none, and says so.
struct ServerTests {
    @Test func noSourceMeansNotConnected() {
        let w = World(now: Date(), buildings: [])
        #expect(w.servers.isEmpty)
        #expect(!w.serverSummary.connected)
        #expect(w.serverSummary.worst == nil)
        #expect(w.serverSummary.line == "Not connected")
    }

    @Test func summaryCountsStates() {
        let s = ServerSummary([Server(id: "a", name: "a", kind: .server, state: .ok), Server(id: "b", name: "b", kind: .deploy, state: .warn),
                               Server(id: "c", name: "c", kind: .backup, state: .down), Server(id: "d", name: "d", kind: .server, state: .ok)])
        #expect(s.ok == 2 && s.warn == 1 && s.down == 1 && s.total == 4)
        #expect(s.worst == .down)
        #expect(s.line == "1 warning · 1 down")
        #expect(ServerSummary([Server(id: "a", name: "a", kind: .server, state: .ok)]).line == "1 online")
    }

    @Test func racksPutProblemsFirst() {
        let w = World(now: Date(), buildings: [], servers: [
            Server(id: "1", name: "web-02", kind: .server, state: .ok), Server(id: "2", name: "web-01", kind: .server, state: .ok),
            Server(id: "3", name: "nightly", kind: .backup, state: .warn), Server(id: "4", name: "zeta", kind: .server, state: .down),
        ])
        #expect(w.racks.map(\.name) == ["zeta", "nightly", "web-01", "web-02"])
    }

    @Test func fixtureHasAMixedEngineRoom() {
        let s = Fixture.world().serverSummary
        #expect(s.total >= 5)
        #expect(s.warn >= 1 && s.down >= 1 && s.ok >= 1)
        #expect(Set(Fixture.servers.map(\.kind)) == Set(ServerKind.allCases))
    }
}
