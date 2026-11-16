import Foundation

/// The roles you see on a floor (D41): every role its own outfit and something in its hand. The CEO is the main chat of
/// a project, where the work starts and gets handed out; you are the stakeholder, not one of the cast.
public enum CastRole: String, Sendable, CaseIterable {
    case ceo, sales, marketing, pm, dev, designer, tester, devops, researcher

    public var label: String {
        switch self {
        case .ceo: "CEO"
        case .sales: "Sales"
        case .marketing: "Marketing"
        case .pm: "Product"
        case .dev: "Developer"
        case .designer: "Designer"
        case .tester: "Tester"
        case .devops: "DevOps"
        case .researcher: "Research"
        }
    }

    /// A sub-agent's type picks the helper's role: an Explore helper reads, a reviewer tests, and so on.
    public init(subAgentType type: String) {
        let t = type.lowercased()
        if t.contains("explor") || t.contains("research") || t.contains("search") || t.contains("doc") { self = .researcher }
        else if t.contains("plan") || t.contains("architect") { self = .pm }
        else if t.contains("review") || t.contains("test") || t.contains("qa") || t.contains("verif") || t.contains("audit") { self = .tester }
        else if t.contains("design") || t.contains("ui") || t.contains("style") { self = .designer }
        else if t.contains("deploy") || t.contains("devops") || t.contains("infra") || t.contains("ci") { self = .devops }
        else { self = .dev }
    }
}

/// How a person is drawn: the role decides the outfit and the prop, the seed (the session id) decides the rest, so the
/// same session always looks the same (D41).
public struct CastKey: Hashable, Sendable {
    public var role: CastRole
    public var seed: String
    public init(role: CastRole, seed: String) { self.role = role; self.seed = seed }
    public var key: String { role.rawValue + ":" + seed }
}

/// A stable name for a session or sub-agent: the same on every screen.
public struct Persona: Hashable, Sendable {
    public var name: String

    static let names = ["Mira", "Kai", "Rae", "Dex", "Lio", "Fen", "Uma", "Teo", "Ines", "Pax", "Rue", "Sol", "Vik", "Wren", "Yara", "Zia",
                        "Bram", "Cleo", "Duc", "Elif", "Gus", "Hana", "Ivy", "Jos", "Noor", "Otto"]

    public init(id: String) {
        var h: UInt32 = 2166136261
        for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        name = Self.names[Int(h % UInt32(Self.names.count))]
    }
}

/// The rooms of a floor (D38). The room a person is in says the phase of their work; the person says the state (D39).
public enum FloorRoom: String, Sendable, CaseIterable {
    case entrance, research, planning, development, tools, builds, testing, pullRequests, deploy, lounge, needsYou, parked

    public var name: String {
        switch self {
        case .entrance: "Entrance"
        case .research: "Research"
        case .planning: "Planning"
        case .development: "Development"
        case .tools: "Tools"
        case .builds: "Builds"
        case .testing: "Testing"
        case .pullRequests: "Pull requests"
        case .deploy: "Deploy"
        case .lounge: "Lounge"
        case .needsYou: "Needs you"
        case .parked: "Pull requests · parked"
        }
    }

    /// PLAN 0, BUILD 1, TEST 2, SHIP 3, DONE 4; the counter and the tools are no phase.
    public var phase: Int? {
        switch self {
        case .entrance, .research, .planning: 0
        case .development, .builds: 1
        case .testing: 2
        case .pullRequests, .deploy, .parked: 3
        case .lounge: 4
        case .needsYou, .tools: nil
        }
    }

    /// Where one action happens.
    public init?(_ kind: ActivityKind) {
        switch kind {
        case .prompt: self = .entrance
        case .read, .browse: self = .research
        case .plan, .delegate: self = .planning
        case .edit: self = .development
        case .shell: self = .builds
        case .test: self = .testing
        case .commit, .push: self = .pullRequests
        case .deploy: self = .deploy
        case .mcp: self = .tools
        case .ask: self = .needsYou
        case .turnEnd: return nil
        }
    }
}

extension Session {
    /// The heartbeat's CEO is the same person every run: seeded by its project folder, everyone else by their session.
    public var personaSeed: String { heartbeatRun == true ? "ceo:" + (projectRoot ?? cwd) : id }
    public var persona: Persona { Persona(id: personaSeed) }

    /// The role from what the session does (D41), apart from the CEO, which its project decides (`Project.role(of:)`).
    /// The title names marketing, sales and design work; otherwise the actions vote, and pushes and deploys weigh three.
    public var workRole: CastRole {
        let t = title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["marketing", "copy", "blog", "newsletter", "landing page", "pricing page", "seo", "social post", "launch post", "tweet"]) { return .marketing }
        if has(["sales", "quote", "invoice", "proposal", "offerte", "customer mail", "pricing table"]) { return .sales }
        if has(["design", "dark mode", "theme", "style", "css", "icon", "font", "colour", "color", "logo", "layout", "illustration"]) { return .designer }
        var count: [CastRole: Int] = [:]
        for a in activities {
            switch a.kind {
            case .edit, .shell, .commit: count[.dev, default: 0] += 1
            case .test, .browse: count[.tester, default: 0] += 1
            case .push, .deploy: count[.devops, default: 0] += 3
            case .plan, .delegate: count[.pm, default: 0] += 1
            case .read, .mcp: count[.researcher, default: 0] += 1
            case .prompt, .ask, .turnEnd: break
            }
        }
        return count.max { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }?.key ?? .dev
    }

    /// The actions of the current turn: everything since the last prompt.
    var turn: ArraySlice<Activity> {
        guard let k = activities.lastIndex(where: { $0.kind == .prompt }) else { return activities[...] }
        return activities[k...]
    }

    /// The room on its floor (D39). Waiting for you is the counter; done is the Lounge, or the bench at Pull requests
    /// when it ended with a push. Otherwise the latest ask, failed test or deploy wins, then the most frequent room of
    /// the last eight actions or five minutes. Stuck is not a room: a stuck person stays where it went wrong.
    public func room(now: Date) -> FloorRoom {
        switch state(now: now) {
        case .waiting: return .needsYou
        case .done:
            let last = activities.last { $0.kind != .turnEnd }
            return last?.kind == .push ? .parked : .lounge
        case .working, .stuck: return Self.room(of: turn)
        }
    }

    static func room<C: BidirectionalCollection>(of acts: C) -> FloorRoom where C.Element == Activity {
        let real = acts.filter { $0.kind != .turnEnd }
        guard let last = real.last else { return .entrance }
        if last.kind == .ask { return .needsYou }
        if last.kind == .test && last.failed { return .testing }
        if last.kind == .deploy { return .deploy }
        let cutoff = last.at.addingTimeInterval(-5 * 60)
        let recent = real.suffix(8)
        let window = real.filter { $0.at >= cutoff }.count > recent.count ? real.filter { $0.at >= cutoff } : Array(recent)
        var count: [FloorRoom: (n: Int, latest: Int)] = [:]
        for (k, a) in window.enumerated() {
            guard let r = FloorRoom(a.kind), r != .entrance || window.count == 1 else { continue }
            count[r] = ((count[r]?.n ?? 0) + 1, k)
        }
        return count.max { ($0.value.n, $0.value.latest) < ($1.value.n, $1.value.latest) }?.key ?? FloorRoom(last.kind) ?? .entrance
    }

    /// Work that went back (D39): the room is an earlier phase than one this turn already reached, like WIP → PLAN or a
    /// red test sending you back to Development. Such a person carries a ↩ note.
    public func wentBack(now: Date) -> Bool {
        let st = state(now: now)
        guard st == .working || st == .stuck, let phase = room(now: now).phase else { return false }
        let acts = Array(turn.filter { $0.kind != .turnEnd })
        guard acts.count > 1 else { return false }
        var reached = 0
        for k in 1..<acts.count { if let p = Self.room(of: acts[..<k]).phase { reached = max(reached, p) } }
        return phase < reached
    }

    /// The command that reopens this session in its own tool.
    public var resumeCommand: String {
        provider == .claude ? "cd \(cwd) && claude --resume \(id)" : "cd \(cwd) && codex resume \(id)"
    }
}

extension Project {
    /// The CEO (D41): the main chat of the project, the session that hands work out to helpers. Only a project with more
    /// than one session has one.
    public var ceoID: String? {
        // the heartbeat's run is the CEO (one per project); otherwise a factory's CEO run says so in its title
        if let run = sessions.first(where: { $0.heartbeatRun == true }) { return run.id }
        if factory != nil, let run = sessions.first(where: { $0.title.range(of: #"\bCEO\b"#, options: [.regularExpression, .caseInsensitive]) != nil }) {
            return run.id
        }
        guard sessions.count > 1 else { return nil }
        let scored = sessions.map { s in (s, s.subAgents.count + s.activities.filter { $0.kind == .delegate }.count) }.filter { $0.1 > 0 }
        return scored.max { $0.1 < $1.1 || ($0.1 == $1.1 && ($0.0.startedAt ?? $0.0.lastAt) > ($1.0.startedAt ?? $1.0.lastAt)) }?.0.id
    }

    public func role(of s: Session) -> CastRole { s.id == ceoID ? .ceo : s.workRole }

    /// The id of a factory's resting CEO, before its first heartbeat run.
    public static let standingCEOPrefix = "ceo-standing:"
    /// A factory always shows its CEO on its floor: before the first heartbeat run, a resting stand-in. It is the same
    /// person as the runs (the CEO is seeded by the project), so the first run takes over that figure.
    public var withStandingCEO: Project {
        guard factory != nil, !isChat, !sessions.contains(where: { $0.heartbeatRun == true }) else { return self }
        var s = Session(id: Self.standingCEOPrefix + root, provider: provider, cwd: root, title: "CEO, waiting for the next heartbeat",
                        lastAt: .distantPast, turnOpen: false, projectRoot: root)
        s.heartbeatRun = true
        var p = self
        p.sessions.append(s)
        return p
    }
    /// The CEO is the same person every run (seeded by the project, not the run); everyone else by their session.
    public func cast(of s: Session) -> CastKey { CastKey(role: role(of: s), seed: s.personaSeed) }
}

extension SubAgent {
    public var persona: Persona { Persona(id: id) }
    public var cast: CastKey { CastKey(role: CastRole(subAgentType: type), seed: id) }
}
