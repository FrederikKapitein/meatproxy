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

    /// "Developer"; your own profile by its name ("code-reviewer" → "Code reviewer")
    public var label: String {
        if AgentProfile.standard(name) != nil { return role.label }
        let words = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

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

/// A profile you made yourself (D79): kept with your settings and offered on every floor, written as an agent file like
/// Meatproxy's own.
public struct CustomProfile: Codable, Hashable, Sendable, Identifiable {
    /// what it may touch: reading only, editing files, or editing and running commands
    public enum Access: String, Codable, CaseIterable, Sendable {
        case read, edit, run
        public var tools: [String] {
            switch self {
            case .read: ["Read", "Glob", "Grep", "WebSearch", "WebFetch"]
            case .edit: ["Read", "Edit", "Write", "Glob", "Grep"]
            case .run: ["Read", "Edit", "Write", "Glob", "Grep", "Bash"]
            }
        }
        public var label: String {
            switch self { case .read: "Reads only"; case .edit: "Edits files"; case .run: "Edits and runs commands" }
        }
    }
    public var name: String
    public var may: String
    public var model: String
    public var access: Access
    /// the outfit it wears on the floor
    public var look: CastRole
    public var id: String { name }

    public init(name: String, may: String, model: String = "sonnet", access: Access = .read, look: CastRole = .researcher) {
        self.name = name; self.may = may; self.model = model; self.access = access; self.look = look
    }

    public var profile: AgentProfile {
        AgentProfile(name: name, role: look, model: model, tools: access.tools, may: may.isEmpty ? access.label : may,
                     when: "when its work fits: \(may.isEmpty ? access.label.lowercased() : may.lowercased())")
    }

    /// A profile name is a file name and a sub-agent type: lower case letters, digits and dashes, not one that exists.
    public static func check(_ name: String, taken: [String]) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Give it a name" }
        if n.range(of: "^[a-z][a-z0-9-]{0,30}$", options: .regularExpression) == nil { return "Lower case letters, digits and dashes, starting with a letter" }
        if n == "ceo" || taken.contains(n) { return "There is a profile called \(n) already" }
        return nil
    }
}

/// One place for a team member on a factory floor (D79): every agent you switch on is always there. A free one waits
/// in the lounge; when the CEO calls one in, that same person does the job, then comes back.
public struct TeamSlot: Hashable, Sendable {
    /// "team:<root>:developer:0", the same person every time
    public var id: String
    public var profile: String
    public var role: CastRole
    /// the helper doing a job in this place now, and the session it works for
    public var helper: String?
    public var owner: String?
    public var cast: CastKey { CastKey(role: role, seed: id) }
}

extension Project {
    /// Its team's places, each with the running helper of that profile that fills it (in the order the helpers
    /// started). Helpers beyond the numbers get no place: they are shown as extra, and the Team tab says so.
    public var teamSlots: [TeamSlot] {
        guard let team, factory != nil else { return [] }
        var running: [String: [(sub: String, owner: String)]] = [:]
        for s in sessions.sorted(by: { $0.id < $1.id }) {
            for a in s.subAgents where !a.finished { running[a.type.lowercased(), default: []].append((a.id, s.id)) }
        }
        return team.names.flatMap { name -> [TeamSlot] in
            let role = teamRoles[name] ?? AgentProfile.standard(name)?.role ?? CastRole(subAgentType: name)
            let busy = running[name] ?? []
            return (0..<team.count(name)).map { k in
                TeamSlot(id: "team:\(root):\(name):\(k)", profile: name, role: role,
                         helper: k < busy.count ? busy[k].sub : nil, owner: k < busy.count ? busy[k].owner : nil)
            }
        }
    }

    /// a helper of a profile on the team: once its job is done it is back in the lounge, not standing about
    public func isTeamProfile(_ type: String) -> Bool { factory != nil && (team?.count(type.lowercased()) ?? 0) > 0 }
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
