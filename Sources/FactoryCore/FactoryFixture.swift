import Foundation

/// A made-up Dark Software Factory for demos, screenshots and tests: "Pebble Puzzles", in hybrid autonomy, with two
/// questions open. Everything in it is fictional; no real factory's decisions, briefings or links end up in something shared.
extension Fixture {
    public static let factoryRoot = "/demo/pebble-puzzles"

    /// The factory's files as they would sit under the project folder, dated round `now`.
    public static func factoryFiles(now: Date = Date()) -> [String: String] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        iso.formatOptions = [.withInternetDateTime]
        let dayF = DateFormatter(); dayF.dateFormat = "yyyy-MM-dd"; dayF.locale = Locale(identifier: "en_US_POSIX")
        func at(_ hours: Double) -> String { iso.string(from: now.addingTimeInterval(-hours * 3600)) }
        func day(_ days: Double) -> String { dayF.string(from: now.addingTimeInterval(-days * 86400)) }
        let today = day(0)

        func decision(_ id: String, _ slug: String, title: String, kind: String, gate: String, status: String, ws: String?,
                      asked: Double, answered: Double? = nil, why: String, evidence: String, onYes: String, onNo: String, answer: String = "") -> (String, String) {
            ("factory/decisions/\(id)-\(slug).md", """
            ---
            id: \(id)
            title: \(title)
            kind: \(kind)            # plan | ship | store | promote | stop | other
            gate: \(gate)            # plan | ship | store | always-ask
            status: \(status)          # open | yes | no | expired | withdrawn
            workstream: \(ws ?? "null")
            replaces: null
            asked: \(at(asked))
            answered: \(answered.map(at) ?? "null")
            ---

            ## Why
            \(why)

            ## Evidence
            \(evidence)

            ## On yes
            \(onYes)

            ## On no
            \(onNo)

            ## Answer
            \(answer)

            """)
        }

        func workstream(_ id: String, _ slug: String, title: String, type: String, phase: String, source: String, pr: String?,
                        release: String?, opened: Double, decisions: String, log: [String]) -> (String, String) {
            ("factory/workstreams/\(id)-\(slug).md", """
            ---
            id: \(id)
            title: \(title)
            type: \(type)
            phase: \(phase)
            source: \(source)
            branch: \(type == "chore" ? "chore" : type)/\(id)-\(slug)
            pr: \(pr ?? "null")
            release: \(release ?? "null")
            opened: \(day(opened))
            updated: \(today)
            decisions: [\(decisions)]
            ---

            ## Goal
            A made-up goal for the demo factory.

            ## Acceptance criteria
            - [ ] a made-up criterion

            ## Out of scope
            Everything real.

            ## Log
            \(log.map { "- " + $0 }.joined(separator: "\n"))

            """)
        }

        let files: [(String, String)] = [
            ("factory/autonomy.yml", """
            # Demo factory autonomy state.
            level: hybrid
            gates:
              plan: notify
              ship: ask
              store: ask
            streaks:
              plan: 5
              ship: 5
              store: 0
            history:
              - date: \(day(9))
                change: Factory started at assistant; all gates ask.

            """),
            ("factory/briefings/\(day(1)).md", """
            ## Briefing
            Quiet day; nothing moved.

            ## Needs you
            Nothing.

            ## Delivered
            Nothing new.

            """),
            ("factory/briefings/\(today).md", """
            ## Briefing
            - Web and both stores healthy; crash-free sessions 99.8%.
            - Offline streak sync passed test and is ready to ship.
            - The timer fix went back to build once: the tester caught a reset on resume.
            - Next: ship W-002 after your yes, then colour-blind pebbles.

            ## Needs you
            1. Ship offline streak sync (W-002) to production?
            2. Stop asking before each ship? You'd still be told.
            3. To-do D-0010: allow the error tracker's read tools in this project's allowlist.
            4. To-do D-0011 for DevOps: the CI runner drops the last check.

            ## Delivered
            - Undo after a hint (W-001), released in 3.2.1 on web, App Store and Google Play.

            """),
            workstream("W-001", "undo-after-hint", title: "Undo works after a hint", type: "bug", phase: "done", source: "sentry",
                       pr: "https://github.com/example/pebble-puzzles/pull/38", release: "3.2.1", opened: 6, decisions: "D-0003, D-0004",
                       log: ["\(day(6)) plan: proposed from a crash report (D-0003).", "\(day(5)) build: developer started.",
                             "\(day(4)) test: tester passed it.", "\(day(3)) ship: shipped to web (D-0004).", "\(day(2)) done: released in 3.2.1."]),
            workstream("W-002", "offline-streak-sync", title: "Offline streak sync", type: "feature", phase: "ship", source: "product",
                       pr: "https://github.com/example/pebble-puzzles/pull/41", release: nil, opened: 4, decisions: "D-0005, D-0007",
                       log: ["\(day(4)) plan: proposed by product (D-0005).", "\(day(3)) build: developer started.",
                             "\(day(2)) test: tester started.", "\(day(2)) test → build: streak lost after airplane mode; back to build.",
                             "\(day(1)) test: fixed; tester passed it.", "\(today) ship: ship decision filed (D-0007)."]),
            workstream("W-003", "timer-resume", title: "Timer keeps time after resume", type: "bug", phase: "build", source: "ci",
                       pr: "https://github.com/example/pebble-puzzles/pull/43", release: nil, opened: 2, decisions: "",
                       log: ["\(day(2)) plan: started under notify.", "\(day(1)) build: developer started.", "\(day(1)) test: tester started.",
                             "\(today) test → build: timer reset to zero on resume; back to build."]),
            workstream("W-004", "colour-blind-pebbles", title: "Colour-blind friendly pebbles", type: "feature", phase: "plan", source: "product",
                       pr: nil, release: nil, opened: 0, decisions: "", log: ["\(today) plan: proposed by product; starts after W-003 (plan gate is notify)."]),
            workstream("W-005", "weekly-league", title: "A weekly league", type: "feature", phase: "dropped", source: "product",
                       pr: nil, release: nil, opened: 8, decisions: "D-0006", log: ["\(day(8)) plan: proposed (D-0006).", "\(day(7)) dropped: outside the product boundary."]),
            decision("D-0005", "plan-offline-streak-sync", title: "Build offline streak sync?", kind: "plan", gate: "plan", status: "yes",
                     ws: "W-002", asked: 96, answered: 90, why: "Players lose their streak when they play on a plane.",
                     evidence: "- [Support thread](https://support.example.com/t/streak-lost)", onYes: "Build it.", onNo: "Drop it.",
                     answer: "Yes, players ask for it."),
            decision("D-0006", "plan-weekly-league", title: "Add a weekly league?", kind: "plan", gate: "plan", status: "no",
                     ws: "W-005", asked: 190, answered: 170, why: "A league could bring players back every week.",
                     evidence: "- Product idea", onYes: "Build it.", onNo: "Drop it.", answer: "No: leagues are outside the boundary."),
            decision("D-0007", "ship-offline-streak-sync", title: "Ship offline streak sync (W-002) to production?", kind: "ship", gate: "ship",
                     status: "open", ws: "W-002", asked: 2.5,
                     why: "Streaks now survive airplane mode. The tester passed it on web and both simulators after one round back to build.",
                     evidence: """
                     - [PR #41](https://github.com/example/pebble-puzzles/pull/41)
                     - [CI run, all green](https://github.com/example/pebble-puzzles/actions/runs/1001)
                     - Screenshots: factory/workstreams/W-002-offline-streak-sync/
                     """,
                     onYes: "Merge to develop, release to main and deploy web; check health and version.", onNo: "Hold it and ask what to change."),
            decision("D-0008", "promote-ship-gate", title: "Stop asking before each ship? You'd still be told.", kind: "promote",
                     gate: "always-ask", status: "open", ws: nil, asked: 1,
                     why: "The last five ship questions were all a yes, with no revert or hotfix after them. Without asking, the CEO ships after green checks and an independent tester pass, and tells you in the briefing.",
                     evidence: "- [Ship history](https://github.com/example/pebble-puzzles/releases)\n- https://status.example.com/pebble-puzzles",
                     onYes: "Shipping goes from Ask to Tell me; it's logged in the history.", onNo: "Keep asking before every ship."),
            // a release you held back (D81): W-006 waits for your Release now; and a to-do only you can do
            workstream("W-006", "sharper-hint-arrows", title: "Sharper hint arrows", type: "feature", phase: "ship", source: "product",
                       pr: "https://github.com/example/pebble-puzzles/pull/44", release: nil, opened: 5, decisions: "D-0009",
                       log: ["\(day(5)) plan: proposed by product.", "\(day(4)) build: developer started.", "\(day(3)) test: tester passed it.",
                             "\(day(2)) ship: you said no on D-0009 (not before the weekend); it waits for your release."]),
            decision("D-0009", "ship-sharper-hint-arrows", title: "Ship sharper hint arrows (W-006) to production?", kind: "ship", gate: "ship",
                     status: "no", ws: "W-006", asked: 60, answered: 50, why: "Hint arrows are easier to see on small phones.",
                     evidence: "- [PR #44](https://github.com/example/pebble-puzzles/pull/44)", onYes: "Release it.", onNo: "Hold it.",
                     answer: "Not before the weekend."),
            ("factory/decisions/D-0010-allow-error-tracker-reads.md", """
            ---
            id: D-0010
            title: Allow the error tracker's read tools in this project's allowlist
            kind: todo
            gate: always-ask
            status: open
            workstream: null
            asked: \(at(0.5))
            answered: null
            ---

            ## Why
            The CEO cannot read new crashes: the error tracker's tools are not in the allowlist, so every search is denied.

            ## How
            1. Open .claude/settings.json in this project.
            2. Add the error tracker's read tools (search issues, issue details, stack traces) to permissions.allow.
            3. Press Done; the CEO checks it on its next run.

            ## Answer

            """),
            ("factory/decisions/D-0011-ci-runner-drops-last-check.md", """
            ---
            id: D-0011
            title: Get the CI runner to finish its last check again
            kind: todo
            for: devops
            gate: always-ask
            status: open
            workstream: W-003
            asked: \(at(0.2))
            answered: null
            ---

            ## Why
            The timer fix passes every check, then the shared CI runner drops out before the last one reports, so the
            pull request cannot merge. The runner is shared infrastructure, not this factory's.

            ## How
            1. Look at the runner's service and its last cleanup on the build server.
            2. Restart it if it hangs, and check that a new job finishes.

            ## Answer

            """),
            ("factory/contract.yml", "contract: meatproxy-factory\nversion: 6\nsentry: demo-org/pebble-app\ntracker: pebble\n"),
            ("factory/mandate.yml", { var m = FactoryMandate(); m.set(level: .hybrid); m.quietHours = "22:00-07:00"; m.ownTeam = true; m.team = AgentTeam(["product": 1, "developer": 2, "tester": 1]); return m.yaml }()),
            // your ideas: one the CEO took (it became D-0007's sibling W-004), one still waiting
            ("factory/ideas/I-0001-colour-blind-pebbles.md", """
            ---
            id: I-0001
            title: Colour-blind friendly pebbles
            status: taken
            sent: \(at(30))
            workstream: W-004
            ---

            Colour-blind friendly pebbles: shapes as well as colours.

            ## CEO
            Taken: planned as W-004.
            """),
            ("factory/ideas/I-0002-daily-puzzle-streak-reminder.md", """
            ---
            id: I-0002
            title: A gentle reminder when a daily streak is about to break
            status: new
            sent: \(at(0.2))
            workstream: null
            ---

            A gentle reminder when a daily streak is about to break, at most once a day, and easy to switch off.

            ## CEO

            """),
        ]
        return Dictionary(files, uniquingKeysWith: { a, _ in a })
    }

    /// The demo factory as the app reads it.
    public static func factory(now: Date = Date()) -> Factory {
        FactoryText.factory(root: factoryRoot, files: factoryFiles(now: now))
    }
}
