import Foundation
import Testing
@testable import FactoryCore

/// The floor's rules: the room says the phase, the person the state (D39); everyone has a visible role (D41).
struct FloorRulesTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A session whose actions are a minute apart, the last one `last` minutes ago.
    func session(_ kinds: [ActivityKind], failedLast: Bool = false, open: Bool = true, last: Double = 0.2, title: String = "Something",
                 id: String = "s1", subAgents: Int = 0) -> Session {
        let acts = kinds.enumerated().map { k, kind in
            Activity(at: now.addingTimeInterval(-(last + Double(kinds.count - 1 - k)) * 60), kind: kind, text: kind.rawValue,
                     failed: failedLast && k == kinds.count - 1)
        }
        return Session(id: id, provider: .claude, cwd: "/demo/x", title: title, startedAt: now.addingTimeInterval(-3600),
                       lastAt: now.addingTimeInterval(-last * 60), turnOpen: open, activities: acts,
                       subAgents: (0..<subAgents).map { SubAgent(id: "\(id)-m\($0)", type: "Explore", summary: "", finished: false) })
    }

    @Test func roomFollowsTheWork() {
        #expect(session([.prompt, .read, .browse, .read]).room(now: now) == .research)
        #expect(session([.prompt, .plan, .edit, .edit, .edit]).room(now: now) == .development)
        #expect(session([.prompt, .edit, .shell, .shell]).room(now: now) == .builds)
        #expect(session([.prompt, .commit, .push]).room(now: now) == .pullRequests)
        #expect(session([.prompt, .mcp]).room(now: now) == .tools)
        #expect(session([.prompt]).room(now: now) == .entrance)
    }

    @Test func askFailedTestAndDeployGoFirst() {
        #expect(session([.prompt, .edit, .edit, .edit, .deploy]).room(now: now) == .deploy)
        // a failed test makes the session stuck, and it stays in Testing: stuck is not a room
        let red = session([.prompt, .edit, .edit, .edit, .test], failedLast: true)
        #expect(red.state(now: now) == .stuck)
        #expect(red.room(now: now) == .testing)
        let ask = session([.prompt, .edit, .ask])
        #expect(ask.state(now: now) == .waiting)
        #expect(ask.room(now: now) == .needsYou)
    }

    @Test func waitingAndDone() {
        // a finished turn that asks you something stands at Needs you; one that asks nothing goes to the lounge (D25)
        var asks = session([.prompt, .edit], open: false, last: 5); asks.lastSaid = "Shall I open the PR?"
        #expect(asks.room(now: now) == .needsYou)
        #expect(session([.prompt, .edit], open: false, last: 5).room(now: now) == .lounge)
        #expect(session([.prompt, .edit], open: false, last: 120).room(now: now) == .lounge)
        // done with a push: parked on the bench at Pull requests
        #expect(session([.prompt, .commit, .push], open: false, last: 120).room(now: now) == .parked)
    }

    @Test func workThatGoesBackCarriesANote() {
        let back = session([.prompt, .edit, .test, .plan, .plan])
        #expect(back.room(now: now) == .planning)
        #expect(back.wentBack(now: now))
        #expect(!session([.prompt, .plan, .edit, .test]).wentBack(now: now))
        // a new prompt starts a new turn: no note
        #expect(!session([.test, .prompt, .plan]).wentBack(now: now))
    }

    @Test func rolesFromWhatTheyDo() {
        #expect(session([.prompt, .edit, .shell]).workRole == .dev)
        #expect(session([.prompt, .test, .browse, .edit]).workRole == .tester)
        #expect(session([.prompt, .edit, .push]).workRole == .devops)
        #expect(session([.prompt, .read, .read, .edit]).workRole == .researcher)
        #expect(session([.prompt, .edit], title: "Dark mode for settings").workRole == .designer)
        #expect(session([.prompt, .edit], title: "New pricing page").workRole == .marketing)
        #expect(CastRole(subAgentType: "Explore") == .researcher)
        #expect(CastRole(subAgentType: "code-review") == .tester)
    }

    @Test func theCEOIsTheChatThatHandsOutWork() {
        let main = session([.prompt, .delegate], id: "main", subAgents: 2), other = session([.prompt, .edit], id: "other")
        let p = Project(id: "p", provider: .claude, root: "/demo/x", name: "X", isChat: false, sessions: [other, main])
        #expect(p.ceoID == "main")
        // a plain project's main chat is its Lead; only a factory has a CEO (in black, D73)
        #expect(p.role(of: main) == .lead && CastRole.lead.label == "Lead")
        #expect(p.role(of: other) == .dev)
        var f = p; f.factory = Factory(root: "/demo/x")
        #expect(f.role(of: main) == .ceo)
        // alone, a session is not a CEO of anyone
        #expect(Project(id: "q", provider: .claude, root: "/x", name: "Y", isChat: false, sessions: [main]).ceoID == nil)
    }

    @Test func theSameSessionLooksTheSame() {
        #expect(Persona(id: "abc").name == Persona(id: "abc").name)
        #expect(CastKey(role: .dev, seed: "abc").key == "dev:abc")
    }
}

extension FloorRulesTests {
    /// A CEO run the heartbeat says is going works, even when its file looks finished between turns.
    @Test func aLiveCEORunWorks() {
        var s = session([.prompt, .delegate], open: false, last: 3)
        s.heartbeatRun = true
        #expect(s.state(now: now) == .done)
        s.liveRun = true
        #expect(s.state(now: now) == .working)
    }
}
