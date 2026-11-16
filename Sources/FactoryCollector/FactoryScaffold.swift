import Foundation
import FactoryCore

/// One file Meatproxy offers when you set a factory up: where it goes (relative to the project), what it says, whether
/// it is already there (then it is never written), and whether it is offered unticked (the allowlist).
public struct StarterFile: Equatable, Sendable, Identifiable {
    public var path: String
    public var text: String
    public var exists: Bool
    public var optional: Bool
    /// one line on what the file is for
    public var why: String
    public var id: String { path }
}

/// Setting up a factory (D76): the starter files a CEO needs to work from, shown to you one by one. Meatproxy writes
/// only the files you approve and only where nothing is yet; it never overwrites. Switching a project on writes nothing.
public enum FactoryScaffold {
    /// A factory is set up when its CEO has the files the heartbeat's prompt points at.
    public static func isSetUp(_ root: String) -> Bool {
        ["factory/contract.yml", "factory/CHARTER.md", "factory/CEO.md"].allSatisfy {
            FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent($0))
        }
    }

    /// The starter files for the project at `root`, called `name` on the campus.
    public static func plan(root: String, name: String) -> [StarterFile] {
        let tests = testCommands(root)
        let files: [(String, String, Bool, String)] = [
            ("factory/contract.yml", contract, false, "The contract version this factory follows (v\(FactoryContract.current))"),
            ("factory/CHARTER.md", charter(name, tests: tests), false, "What the factory is for and its hard rules; edit it to fit"),
            ("factory/README.md", readme(name), false, "What lives in factory/ and who writes what"),
            ("factory/CEO.md", playbook(tests: tests), false, "The CEO's playbook for one run"),
            ("factory/autonomy.yml", autonomy, false, "The CEO's gates and streaks, all asking at first"),
            ("factory/mandate.yml", FactoryMandate().yaml, false, "Your mandate: Assistant, it asks before everything"),
            (".claude/settings.json", allowlist(tests: tests), true, "Lets the CEO read, edit, test and commit without asking; never push or merge"),
        ]
        return files.map { path, text, optional, why in
            StarterFile(path: path, text: text, exists: FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent(path)),
                        optional: optional, why: why)
        }
    }

    /// Writes the given files that are missing, and the factory's queue folders; returns the paths it wrote.
    @discardableResult
    public static func create(_ files: [StarterFile], root: String) throws -> [String] {
        let fm = FileManager.default, base = URL(fileURLWithPath: root)
        var written: [String] = []
        for f in files {
            let u = base.appendingPathComponent(f.path)
            guard !fm.fileExists(atPath: u.path) else { continue }
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            // withoutOverwriting: a file that appeared meanwhile is not replaced
            try Data(f.text.utf8).write(to: u, options: .withoutOverwriting)
            written.append(f.path)
        }
        if files.contains(where: { $0.path.hasPrefix("factory/") }) {
            for d in ["decisions", "workstreams", "ideas", "briefings"] {
                try fm.createDirectory(at: base.appendingPathComponent("factory/" + d), withIntermediateDirectories: true)
            }
        }
        return written
    }

    /// The project's test and build commands, from the files at its root (or in code/<repo>/).
    public static func testCommands(_ root: String) -> [String] {
        let fm = FileManager.default
        func has(_ f: String) -> Bool { fm.fileExists(atPath: (root as NSString).appendingPathComponent(f)) }
        if has("Package.swift") { return ["swift test", "swift build"] }
        if has("package.json") { return ["npm test", "npm run build"] }
        if has("Cargo.toml") { return ["cargo test", "cargo build"] }
        if has("go.mod") { return ["go test", "go build"] }
        if has("pyproject.toml") || has("setup.py") { return ["pytest"] }
        if has("pubspec.yaml") { return ["flutter test"] }
        return []
    }

    // MARK: the templates

    static let contract = """
    contract: meatproxy-factory
    version: \(FactoryContract.current)
    # sentry: my-org/my-app      # optional: wakes the CEO for new errors (v4)
    # sentry-host: de.sentry.io  # optional: where the Sentry organization lives (default sentry.io)
    # tracker: my-app            # optional: wakes the CEO for stories that change (v4)

    """

    static func charter(_ name: String, tests: [String]) -> String {
        let test = tests.isEmpty ? "the project's tests" : tests.map { "`\($0)`" }.joined(separator: " and ")
        return """
        # Charter: \(name)

        ## What this factory is for

        Keep \(name) healthy and moving: fix what breaks, keep dependencies current, and turn the ideas you get
        into small, finished, tested changes. Edit this section to say what \(name) is and who it is for.

        ## Hard rules

        - Work on your own branch per workstream (`feature/W-NNN-<slug>` or `bug/W-NNN-<slug>`). Never commit to the
          main branch, never force-push, never rewrite history.
        - \(test) must pass before a change is called done.
        - Never push, merge or deploy on your own: ask with a `ship` decision. Never spend money without a yes.
        - Secrets never go into files, logs, commits or briefings.
        - Follow `mandate.yml` on every run; it wins over this charter and the playbook. Never change your own mandate.
        - What you were denied or could not check goes in the briefing; never work round a denial.

        """
    }

    static func readme(_ name: String) -> String {
        """
        # \(name)'s factory

        A Meatproxy factory: an AI CEO works on this project on a heartbeat and asks the user in Meatproxy when it
        needs a yes. Its state lives in this folder, as plain files.

        - `CHARTER.md`: what the factory is for, and its hard rules.
        - `CEO.md`: the playbook for one run.
        - `mandate.yml`: what the CEO may do on its own. Meatproxy writes it; the CEO follows it.
        - `decisions/`, `workstreams/`, `ideas/`, `briefings/`: the queue, the work, the user's ideas, one briefing per run.

        The contract between this folder and Meatproxy is `meatproxy-factory` v\(FactoryContract.current):
        https://github.com/marcel-tuinstra/meatproxy/blob/main/docs/contracts/factory.md

        """
    }

    static func playbook(tests: [String]) -> String {
        let test = tests.isEmpty ? "run the project's tests" : "run " + tests.map { "`\($0)`" }.joined(separator: " and ")
        return """
        # CEO playbook: one run

        1. Read `mandate.yml` (it wins), `autonomy.yml`, the open `decisions/`, the `workstreams/`, new `ideas/` and
           the last briefing.
        2. Act on answered decisions first, then new ideas: shape each idea into a workstream in `plan` (goal,
           acceptance criteria, out of scope), set the idea `taken` with the workstream id and a one-line reply.
        3. Work on at most one workstream per run; small and finished beats big and half-done:
           - on its own branch, with tests added or updated;
           - \(test);
           - commit with a clear message.
        4. When a workstream is done and tested, ask with a `ship` decision. Do not push.
        5. Anything you were denied, or could not verify, goes in the briefing.
        6. End with the briefing (`## Briefing`, `## Needs you`, `## Delivered`).

        """
    }

    static let autonomy = """
    level: assistant
    gates:
      plan: ask
      ship: ask
      store: ask
    streaks:
      ship: 0

    """

    /// A project allowlist for `claude -p`: reading, editing, the project's tests and local git; never a push or merge.
    static func allowlist(tests: [String]) -> String {
        var allow = ["Read", "Edit", "Write", "Glob", "Grep",
                     "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git add:*)",
                     "Bash(git commit:*)", "Bash(git switch:*)", "Bash(git checkout -b:*)", "Bash(git branch:*)",
                     "Bash(ls:*)", "Bash(gh run list:*)", "Bash(gh run view:*)", "Bash(gh pr list:*)", "Bash(gh pr view:*)"]
        allow += tests.map { "Bash(\($0):*)" }
        let deny = ["Bash(git push:*)", "Bash(gh pr create:*)", "Bash(gh pr merge:*)", "Bash(git reset --hard:*)", "Bash(rm -rf:*)"]
        func list(_ a: [String]) -> String { a.map { "      \"\($0)\"" }.joined(separator: ",\n") }
        return """
        {
          "permissions": {
            "allow": [
        \(list(allow))
            ],
            "deny": [
        \(list(deny))
            ]
          }
        }

        """
    }
}
