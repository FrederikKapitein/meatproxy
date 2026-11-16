import Foundation
import Testing
@testable import FactoryCollector
import FactoryCore

/// D70: which model and effort a run gets, by why it woke; and a factory's CEO before its first run.
@Suite struct ModelPolicyTests {
    @Test func theWakeDecidesTheChoice() {
        var p = ModelPolicy()
        p.routine = .init(model: "sonnet", effort: "low"); p.input = .init(model: "opus", effort: "high"); p.incident = .init(model: "opus", effort: nil)
        #expect(p.choice(for: .schedule(Date())).model == "sonnet" && p.choice(for: .caughtUp(Date())).effort == "low")
        #expect(p.choice(for: .idea(["I-0001"])).model == "opus" && p.choice(for: .runNow).effort == "high" && p.choice(for: .answered(["D-1"])).model == "opus")
        #expect(p.choice(for: .ciFailed(repo: "app", run: "1")).model == "opus" && p.choice(for: .sentry(["X"])).effort == nil)
    }

    @Test func claudeAndCodexGetTheirOwnFlags() {
        let c = HeartbeatRunner.arguments(.init(runtime: .claude, prompt: "p", maxTurns: 5, settings: nil, model: "opus", effort: "high"))
        #expect(c.suffix(4) == ["--model", "opus", "--effort", "high"])
        let x = HeartbeatRunner.arguments(.init(runtime: .codex, prompt: "p", maxTurns: 5, settings: nil, model: "gpt-6.1-sol", effort: "medium"))
        #expect(x.contains("-m") && x.contains("gpt-6.1-sol") && x.contains("model_reasoning_effort=\"medium\"") && x.last == "p")
        // the runtime's default: no flags at all
        let d = HeartbeatRunner.arguments(.init(runtime: .claude, prompt: "p", maxTurns: 5, settings: nil))
        #expect(!d.contains("--model") && !d.contains("--effort"))
        // something that is not a plain name never reaches the command line
        let bad = HeartbeatRunner.arguments(.init(runtime: .claude, prompt: "p", maxTurns: 5, settings: nil, model: "opus --dangerously", effort: "high;rm"))
        #expect(!bad.contains("--model") && !bad.contains("--effort"))
    }

    @Test func anOldHeartbeatReadsWithDefaults() throws {
        let old = try JSONDecoder().decode(Heartbeat.self, from: Data(#"{"days":"weekdays","times":["09:00"]}"#.utf8))
        #expect(old.models == ModelPolicy())
        var hb = Heartbeat(); hb.models.input = .init(model: "opus", effort: "max")
        #expect(try JSONDecoder().decode(Heartbeat.self, from: JSONEncoder().encode(hb)).models.input.effort == "max")
    }

    @Test func aFactoryShowsItsCEOBeforeTheFirstRun() {
        let p = Project(id: "claude:/demo/new", provider: .claude, root: "/demo/new", name: "New", isChat: false, sessions: [], factory: Factory(root: "/demo/new"))
        let shown = p.withStandingCEO
        #expect(shown.sessions.count == 1 && shown.ceoID?.hasPrefix(Project.standingCEOPrefix) == true)
        #expect(shown.sessions[0].state(now: Date()) == .done)
        // it is the same person a later run will be
        var run = Session(id: "r1", provider: .claude, cwd: "/demo/new", title: "run", lastAt: Date(), turnOpen: true, projectRoot: "/demo/new")
        run.heartbeatRun = true
        #expect(run.personaSeed == shown.sessions[0].personaSeed)
        // with a run, no stand-in; and a project that is no factory gets none
        var withRun = p; withRun.sessions = [run]
        #expect(withRun.withStandingCEO.sessions.count == 1)
        let plain = Project(id: "claude:/demo/plain", provider: .claude, root: "/demo/plain", name: "Plain", isChat: false, sessions: [])
        #expect(plain.withStandingCEO.sessions.isEmpty)
    }
}
