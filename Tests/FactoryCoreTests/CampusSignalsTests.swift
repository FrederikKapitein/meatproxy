import Foundation
import Testing
@testable import FactoryCore

/// D66: what the campus shows of what goes on, on made-up sessions only.
@Suite struct CampusSignalsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ago(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
    func session(_ id: String, open: Bool, acts: [(ActivityKind, Bool)], started: Double = 120, subs: [SubAgent] = []) -> Session {
        let list = acts.enumerated().map { k, a in Activity(at: ago(Double(acts.count - k)), kind: a.0, text: "step", failed: a.1) }
        return Session(id: id, provider: .claude, cwd: "/demo/x", title: "t", startedAt: ago(started), lastAt: ago(1), turnOpen: open,
                       activities: list, subAgents: subs)
    }
    func project(_ s: [Session], factory: Bool = false) -> Project {
        var p = Project(id: "claude:/demo/x", provider: .claude, root: "/demo/x", name: "X", isChat: false, sessions: s)
        if factory { p.factory = Factory(root: "/demo/x") }
        return p
    }

    @Test func theSkyFollowsTheClock() {
        #expect(CampusSignals.daylight(hour: 3) == 0 && CampusSignals.daylight(hour: 23) == 0)
        #expect(CampusSignals.daylight(hour: 12) == 1)
        #expect(CampusSignals.daylight(hour: 7) == 0.5 && CampusSignals.daylight(hour: 19) == 0.5)
        #expect(CampusSignals.daylight(hour: 26) == 0)    // past midnight wraps
    }

    @Test func quietHoursRunOverMidnight() {
        #expect(CampusSignals.quiet("22:00-07:00", hour: 23.5) && CampusSignals.quiet("22:00-07:00", hour: 6.9))
        #expect(!CampusSignals.quiet("22:00-07:00", hour: 12))
        #expect(CampusSignals.quiet("13:30-14:00", hour: 13.75) && !CampusSignals.quiet("13:30-14:00", hour: 14))
        #expect(!CampusSignals.quiet("", hour: 3) && !CampusSignals.quiet("soon", hour: 3) && !CampusSignals.quiet("25:00-03:00", hour: 2))
    }

    @Test func rainOnlyWhenATurnEndedBroken() {
        // a red test in an open turn is work in progress: no rain
        let busy = project([session("a", open: true, acts: [(.edit, false), (.test, true)])])
        #expect(!CampusSignals.broken(busy, now: now))
        // the turn ended with a failed push: rain, until a later push goes through
        let left = project([session("b", open: false, acts: [(.test, false), (.push, true), (.edit, false)])])
        #expect(CampusSignals.broken(left, now: now))
        let fixed = project([session("c", open: false, acts: [(.push, true), (.push, false)])])
        #expect(!CampusSignals.broken(fixed, now: now))
        #expect(CampusSignals.weather(ProviderBuilding(provider: .claude, projects: [busy, left]), now: now) == .rain)
        #expect(CampusSignals.weather(ProviderBuilding(provider: .claude, projects: [busy, fixed]), now: now) == .clear)
    }

    @Test func withGitHubTheWeatherIsCIAndADeliveryIsAMergedPR() {
        // the sessions say all is fine, GitHub says main is red: rain; and the other way round
        var p = project([session("h", open: false, acts: [(.test, false)])])
        p.github = GitHubStatus(failing: ["pebble"], merged: [ago(30), ago(5)], checkedAt: now)
        #expect(CampusSignals.broken(p, now: now))
        var q = project([session("i", open: false, acts: [(.push, true)])])
        q.github = GitHubStatus(checkedAt: now)
        #expect(!CampusSignals.broken(q, now: now))
        // any project with GitHub delivers its merged pull requests, factory or not
        #expect(CampusSignals.deliveries(p, after: ago(10)) == [ago(5)])
        #expect(CampusSignals.deliveries(q, after: ago(60)).isEmpty)
    }

    @Test func theServerRoomsWeather() {
        let ok = Server(id: "web-01", name: "web-01", kind: .server, state: .ok)
        var warn = ok; warn.state = .warn
        var down = ok; down.state = .down
        #expect(CampusSignals.weather(servers: ServerSummary([ok])) == .clear)
        #expect(CampusSignals.weather(servers: ServerSummary([ok, warn])) == .cloudy)
        #expect(CampusSignals.weather(servers: ServerSummary([warn, down])) == .rain)
    }

    @Test func onlyAFactoryDeliversAndOnlyWhatWentThrough() {
        let s = session("f", open: false, acts: [(.push, true), (.commit, false), (.push, false), (.deploy, false)])
        #expect(CampusSignals.deliveries(project([s]), after: ago(60)).isEmpty)
        let d = CampusSignals.deliveries(project([s], factory: true), after: ago(60))
        #expect(d.count == 2 && d == d.sorted())
        #expect(CampusSignals.deliveries(project([s], factory: true), after: ago(1.5)).count == 1)
    }

    @Test func aNewProjectIsBuiltUntilItsFirstSessionIsDone() {
        #expect(CampusSignals.underConstruction(project([session("n", open: true, acts: [(.edit, false)], started: 30)]), now: now))
        // an older project, or one with a second session, is not new
        #expect(!CampusSignals.underConstruction(project([session("o", open: true, acts: [(.edit, false)], started: 26 * 60)]), now: now))
        #expect(!CampusSignals.underConstruction(project([session("p", open: true, acts: [(.edit, false)], started: 30),
                                                         session("q", open: false, acts: [], started: 20)]), now: now))
        // the first session done: the ribbon is cut
        #expect(!CampusSignals.underConstruction(project([session("r", open: false, acts: [(.edit, false)], started: 30)]), now: now))
    }

    @Test func helpersAtWorkTakeTheLift() {
        let s = session("s", open: true, acts: [(.delegate, false)], subs: [SubAgent(id: "m1", type: "Explore", summary: "", finished: true),
                                                                          SubAgent(id: "m2", type: "review", summary: "", finished: false)])
        #expect(CampusSignals.helpers(project([s])) == ["s/m2"])
    }

    @Test func aDeployRunsWhileItIsTheLastStep() {
        #expect(CampusSignals.deploying(project([session("d", open: true, acts: [(.test, false), (.deploy, false)])]), now: now))
        #expect(!CampusSignals.deploying(project([session("e", open: true, acts: [(.deploy, false), (.edit, false)])]), now: now))
        #expect(!CampusSignals.deploying(project([session("g", open: false, acts: [(.deploy, false)])]), now: now))
    }
}
