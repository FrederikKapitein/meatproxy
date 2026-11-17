import Foundation

/// One kind of agent a factory's CEO may call in (D79): a Claude Code sub-agent in `.claude/agents/<name>.md`, drawn on
/// the floor in its role's outfit. The CEO itself is no profile: it is always there.
public struct AgentProfile: Hashable, Sendable, Identifiable {
    /// the file name and the sub-agent type the CEO uses: "developer"
    public var name: String
    public var role: CastRole
    /// the model it starts with (the agent file may say otherwise; that file wins)
    public var model: String
    /// the Claude Code tools it gets
    public var tools: [String]
    /// what it may do, in a few words: "Edits, tests and commits"
    public var may: String
    /// when the CEO calls it in, for the agent file's description
    public var when: String
    public var id: String { name }

    /// "Developer"; your own profile by its name
    public var label: String { AgentProfile.standard(name) != nil ? role.label : name.capitalized }

    /// The profiles Meatproxy knows, in the order the roster shows them.
    public static let standard: [AgentProfile] = [
        .init(name: "product", role: .pm, model: "sonnet", tools: ["Read", "Glob", "Grep", "Write"],
              may: "Plans and writes specs, no code", when: "to shape an idea into a workstream: goal, acceptance criteria, out of scope"),
        .init(name: "developer", role: .dev, model: "sonnet", tools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash"],
              may: "Edits, tests and commits", when: "to build one workstream on its branch, with tests"),
        .init(name: "tester", role: .tester, model: "haiku", tools: ["Read", "Glob", "Grep", "Bash"],
              may: "Reads and runs the tests, edits nothing", when: "to test finished work independently against its acceptance criteria"),
        .init(name: "designer", role: .designer, model: "sonnet", tools: ["Read", "Edit", "Write", "Glob", "Grep"],
              may: "UI and copy changes, no shell", when: "for interface, styling and copy work"),
        .init(name: "research", role: .researcher, model: "haiku", tools: ["Read", "Glob", "Grep", "WebSearch", "WebFetch"],
              may: "Reads code and the web, changes nothing", when: "to find out how something works or what the options are"),
        .init(name: "devops", role: .devops, model: "sonnet", tools: ["Read", "Edit", "Glob", "Grep", "Bash"],
              may: "CI and build files; never deploys", when: "for CI, build and dependency work"),
        .init(name: "marketing", role: .marketing, model: "haiku", tools: ["Read", "Write", "Glob", "Grep", "WebSearch"],
              may: "Drafts copy and posts, publishes nothing", when: "to draft release notes, posts and site copy"),
        .init(name: "sales", role: .sales, model: "haiku", tools: ["Read", "Write", "Glob", "Grep"],
              may: "Drafts quotes and mails, sends nothing", when: "to draft quotes, pricing and customer mails"),
    ]

    public static func standard(_ name: String) -> AgentProfile? { standard.first { $0.name == name } }

    /// A profile of your own: an agent file Meatproxy does not know, drawn by what its name suggests.
    public static func own(_ name: String, model: String?) -> AgentProfile {
        AgentProfile(name: name, role: CastRole(subAgentType: name), model: model ?? "inherit", tools: [], may: "Your own agent file", when: "")
    }

    /// `.claude/agents/<name>.md` for this profile, for the project called `project`.
    public func agentFile(project: String) -> String {
        """
        ---
        name: \(name)
        description: \(role.label) on the \(project) factory team. The CEO calls it in \(when). It works only on the task and branch the CEO gives it.
        tools: \(tools.joined(separator: ", "))
        model: \(model)
        ---

        You are the \(role.label) on \(project)'s factory team, called in by its CEO for one task.

        - \(may). Stay inside that.
        - Work only on the task, files and branch the CEO names. Never commit to the main branch, never push, never merge.
        - Follow the project's AGENTS.md and factory/CHARTER.md.
        - Secrets never go into files, logs or commits.
        - End with a short report for the CEO: what you did, what you checked, and what you could not do or verify.

        """
    }

    /// The model an agent file asks for ("sonnet"), read from its front matter.
    public static func model(inAgentFile text: String) -> String? {
        guard text.hasPrefix("---") else { return nil }
        for line in text.components(separatedBy: "\n").dropFirst() {
            if line.hasPrefix("---") { break }
            if line.hasPrefix("model:") { return line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}

/// Who a factory's CEO may call in, and how many of each at once (D79). The CEO is always there and is not counted
/// here; there is no maximum but yours: the team's size is the CEO plus the sum of the numbers.
public struct AgentTeam: Hashable, Sendable, Codable {
    /// profile name → how many may work at once (0 or missing: none)
    public var counts: [String: Int]

    public init(_ counts: [String: Int] = [:]) { self.counts = counts.filter { $0.value > 0 } }

    /// The campus default a new Meatproxy starts with: a Developer and a Tester.
    public static let campusStart = AgentTeam(["developer": 1, "tester": 1])

    public func count(_ name: String) -> Int { counts[name] ?? 0 }
    public mutating func set(_ name: String, _ n: Int) { counts[name] = n > 0 ? n : nil }

    /// everyone who may work at once, the CEO included
    public var size: Int { 1 + counts.values.reduce(0, +) }

    /// the profiles on the team, in roster order (standard ones first, then your own by name)
    public var names: [String] {
        let std = AgentProfile.standard.map(\.name).filter { count($0) > 0 }
        return std + counts.keys.filter { k in !AgentProfile.standard.contains { $0.name == k } && count(k) > 0 }.sorted()
    }

    /// "CEO, Product, 2 Developers and a Tester"
    public var sentence: String {
        let parts = ["CEO"] + names.map { n -> String in
            let label = AgentProfile.standard(n)?.role.label ?? n.capitalized
            return count(n) == 1 ? label : "\(count(n)) \(label)s"
        }
        return parts.count == 1 ? "CEO only" : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}

extension FactoryMandate {
    /// mandate.yml's team block: whether the floor has its own team or follows the campus default, and the numbers the
    /// CEO follows (the campus default's, written out, when it follows that).
    func teamYAML(_ team: AgentTeam, own: Bool) -> String {
        var out = """
        team:                     # who you may call in as sub-agents (subagent_type = the name), and at most how many at once
          follows: \(own ? "own" : "campus")          # campus: the campus default team · own: this floor's own team

        """
        for n in team.names { out += "  \(n): \(team.count(n))\n" }
        return out
    }
}

/// Counts the helpers of each profile working on a project right now: its sessions' sub-agents that have not finished,
/// by their type. More than the team allows is shown, never stopped: Claude Code has no limit of its own per type.
public enum TeamUsage {
    public static func working(_ project: Project) -> [String: Int] {
        var out: [String: Int] = [:]
        for s in project.sessions { for a in s.subAgents where !a.finished { out[a.type.lowercased(), default: 0] += 1 } }
        return out
    }
}
