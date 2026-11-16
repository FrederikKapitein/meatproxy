import Foundation

/// A provider is a building on the campus and a galaxy in Orbit (D7, D19).
public enum Provider: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude, chatgpt
    public var id: String { rawValue }
    public var displayName: String { self == .claude ? "Claude" : "ChatGPT" }
}

/// What a session is doing, as the worlds show it.
public enum SessionState: String, Codable, Sendable, CaseIterable {
    case working, waiting, stuck, done
    public var label: String {
        switch self {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .stuck: "Stuck"
        case .done: "Done"
        }
    }
}

/// The five levels both worlds share (D24): All → Provider → Project → Session → Sub-agent.
public enum Level: Int, CaseIterable, Sendable {
    case all, provider, project, session, subAgent
    public var name: String {
        switch self {
        case .all: "All"
        case .provider: "Provider"
        case .project: "Project"
        case .session: "Session"
        case .subAgent: "Sub-agent"
        }
    }
}

public enum ActivityKind: String, Codable, Sendable {
    case prompt, read, edit, shell, test, commit, push, deploy, plan, ask, delegate, browse, mcp, turnEnd
}

/// One thing a session did. Only a short label leaves the collector, never contents or full commands.
public struct Activity: Codable, Sendable, Hashable {
    public var at: Date
    public var kind: ActivityKind
    public var text: String
    public var failed: Bool
    public init(at: Date, kind: ActivityKind, text: String, failed: Bool = false) {
        self.at = at; self.kind = kind; self.text = text; self.failed = failed
    }
}

/// A sub-agent: a helper at the desk, a moon in Orbit.
public struct SubAgent: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var type: String
    public var summary: String
    public var finished: Bool
    public init(id: String, type: String, summary: String, finished: Bool) {
        self.id = id; self.type = type; self.summary = summary; self.finished = finished
    }
}

/// A chat or session: a person at a desk, a planet in Orbit.
public struct Session: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var provider: Provider
    public var cwd: String
    public var title: String
    public var branch: String?
    public var model: String?
    public var startedAt: Date?
    public var lastAt: Date
    public var turnOpen: Bool
    public var activities: [Activity]
    public var subAgents: [SubAgent]
    /// The project folder this session belongs to when that is not where it started: a factory's scheduled CEO run starts
    /// in a scratch folder and works in the factory, so it is the factory's (the factory files are the source of truth).
    public var projectRoot: String?
    /// A CEO run Meatproxy's heartbeat started (D47): nobody watches it, and its questions reach you as decisions, so the
    /// session itself never waits for you.
    public var heartbeatRun: Bool?
    /// What the agent said last (the end of its turn): what a waiting session wants from you.
    public var lastSaid: String?
    /// The heartbeat says this CEO's run is going right now: it works, whatever its file looks like.
    public var liveRun: Bool?

    public init(id: String, provider: Provider, cwd: String, title: String, branch: String? = nil, model: String? = nil,
                startedAt: Date? = nil, lastAt: Date, turnOpen: Bool, activities: [Activity] = [], subAgents: [SubAgent] = [],
                projectRoot: String? = nil) {
        self.id = id; self.provider = provider; self.cwd = cwd; self.title = title; self.branch = branch; self.model = model
        self.startedAt = startedAt; self.lastAt = lastAt; self.turnOpen = turnOpen; self.activities = activities; self.subAgents = subAgents
        self.projectRoot = projectRoot
    }

    /// A failure in an open turn is stuck, an open turn is working. A finished turn only waits for you when there is
    /// something to answer (D25): its last words ask you something. That question waits up to a day; a turn that ends
    /// without one is done.
    public func state(now: Date) -> SessionState {
        let idle = now.timeIntervalSince(lastAt)
        if liveRun == true {
            if let failed = activities.last(where: { $0.failed }), now.timeIntervalSince(failed.at) < 90 { return .stuck }
            return .working
        }
        if turnOpen {
            if let failed = activities.last(where: { $0.failed }), now.timeIntervalSince(failed.at) < 90 { return .stuck }
            if activities.last?.kind == .ask { return .waiting }
            return idle > 30 * 60 ? .done : .working
        }
        if heartbeatRun == true { return .done }
        return asksYou && idle < 24 * 3600 ? .waiting : .done
    }

    /// Its last words end with a question for you: a "?" in the last two paragraphs, code left out.
    public var asksYou: Bool {
        guard let t = lastSaid else { return false }
        let prose = t.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"`[^`\n]*`"#, with: "", options: .regularExpression)
        let paras = prose.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return paras.suffix(2).contains { $0.contains("?") }
    }

    /// The gist of what it said last, for a one-line list: its last paragraph (often the question), plain text.
    public var lastSaidGist: String? {
        guard let t = lastSaid?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let paras = t.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let pick = paras.last(where: { $0.contains("?") }) ?? paras.last ?? t
        let plain = pick.replacingOccurrences(of: #"[*_`#>]+"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return plain.count > 160 ? String(plain.prefix(159)) + "…" : plain
    }

    public var lastAction: String {
        guard let a = activities.last(where: { $0.kind != .turnEnd }) ?? activities.last else { return "Started" }
        return a.text.prefix(1).uppercased() + a.text.dropFirst()
    }
}

/// A project: a floor in a building, a solar system in Orbit. One per git root; a chat without a folder is its own (D27).
public struct Project: Identifiable, Sendable, Hashable {
    public var id: String
    public var provider: Provider
    public var root: String
    public var name: String
    public var isChat: Bool
    public var sessions: [Session]
    /// Set when the folder holds a Dark Software Factory (`factory/`).
    public var factory: Factory?
    /// The project's own logo, a file in its folder (D55), when it has one.
    public var logo: String?

    public init(id: String, provider: Provider, root: String, name: String, isChat: Bool, sessions: [Session], factory: Factory? = nil) {
        self.id = id; self.provider = provider; self.root = root; self.name = name; self.isChat = isChat; self.sessions = sessions
        self.factory = factory
    }

    public func count(_ state: SessionState, now: Date) -> Int { sessions.filter { $0.state(now: now) == state }.count }

    /// Something here waits for you (D25): a session, or a factory question that is still open.
    public func waits(now: Date) -> Bool {
        sessions.contains { $0.state(now: now) == .waiting } || !(factory?.openDecisions.isEmpty ?? true)
    }
}

/// A provider's building: its floors from the ground up.
public struct ProviderBuilding: Identifiable, Sendable, Hashable {
    public var provider: Provider
    public var projects: [Project]
    public var id: String { provider.id }
    public init(provider: Provider, projects: [Project]) { self.provider = provider; self.projects = projects }
}

/// What kind of machine sits in the Engine room (D26): a rack on campus, a body round the black hole in Orbit.
public enum ServerKind: String, Codable, Sendable, CaseIterable {
    case server, deploy, backup
    public var label: String { rawValue.capitalized }
}

/// How a server is doing. Down is worse than warn, warn is worse than ok.
public enum ServerState: String, Codable, Sendable, CaseIterable, Comparable {
    case ok, warn, down
    public var label: String {
        switch self {
        case .ok: "OK"
        case .warn: "Warning"
        case .down: "Down"
        }
    }
    var severity: Int { self == .down ? 2 : self == .warn ? 1 : 0 }
    public static func < (a: ServerState, b: ServerState) -> Bool { a.severity < b.severity }
}

/// A server, deploy or backup in the Engine room. They come from their own source (D20): the servers set up in the
/// app's settings, checked over SSH. Nothing set up: the Engine room is not connected.
/// What the built-in check measured on a server: the numbers behind its detail line, for the gauges and history.
public struct ServerMetrics: Codable, Sendable, Hashable {
    public var load: Double?
    public var cores: Int?
    public var disk: Int?
    public var memory: Int?
    /// the sizes behind the percentages, in bytes (the built-in check reads them; an older check has none)
    public var diskUsedBytes: Double?, diskTotalBytes: Double?, memoryUsedBytes: Double?, memoryTotalBytes: Double?
    public init(load: Double? = nil, cores: Int? = nil, disk: Int? = nil, memory: Int? = nil,
                diskUsedBytes: Double? = nil, diskTotalBytes: Double? = nil, memoryUsedBytes: Double? = nil, memoryTotalBytes: Double? = nil) {
        self.load = load; self.cores = cores; self.disk = disk; self.memory = memory
        self.diskUsedBytes = diskUsedBytes; self.diskTotalBytes = diskTotalBytes; self.memoryUsedBytes = memoryUsedBytes; self.memoryTotalBytes = memoryTotalBytes
    }
    /// "18 of 38 GB", "1.7 of 3.7 GB", "512 MB of 1 GB"
    public static func size(_ used: Double?, of total: Double?) -> String? {
        guard let used, let total, total > 0 else { return nil }
        func f(_ b: Double) -> String {
            let gb = b / 1_073_741_824
            return gb >= 10 ? String(format: "%.0f GB", gb) : gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", b / 1_048_576)
        }
        let (u, t) = (f(used), f(total))
        // "18 of 38 GB": the unit once when both have it
        if u.hasSuffix(" GB") && t.hasSuffix(" GB") { return u.dropLast(3) + " of " + t }
        return u + " of " + t
    }
    /// the load per core as a share (1 = every core busy)
    public var loadShare: Double? { load.map { l in cores.map { l / Double(max($0, 1)) } ?? l } }
}

public struct Server: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var kind: ServerKind
    public var state: ServerState
    /// what the last check saw, in a few words ("load 0.4 · disk 61% · memory 42%"), or why it failed
    public var detail: String?
    public var checkedAt: Date?
    /// the numbers, when the built-in check ran (an own check has only its line)
    public var metrics: ServerMetrics?
    public init(id: String, name: String, kind: ServerKind, state: ServerState, detail: String? = nil, checkedAt: Date? = nil, metrics: ServerMetrics? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.state = state; self.detail = detail; self.checkedAt = checkedAt; self.metrics = metrics
    }
}

/// How many servers are ok, warn and down; what the Engine room shows in one line.
public struct ServerSummary: Sendable, Hashable {
    public var ok = 0, warn = 0, down = 0
    public init(_ servers: [Server]) {
        for s in servers {
            switch s.state {
            case .ok: ok += 1
            case .warn: warn += 1
            case .down: down += 1
            }
        }
    }
    public var total: Int { ok + warn + down }
    public var connected: Bool { total > 0 }
    /// The worst state, nil when nothing is connected.
    public var worst: ServerState? { down > 0 ? .down : warn > 0 ? .warn : total > 0 ? .ok : nil }
    /// "Not connected", "6 online", "1 warning · 1 down".
    public var line: String {
        guard connected else { return "Not connected" }
        var parts: [String] = []
        if warn > 0 { parts.append("\(warn) warning") }
        if down > 0 { parts.append("\(down) down") }
        return parts.isEmpty ? "\(total) online" : parts.joined(separator: " · ")
    }
}

/// Everything the worlds show at one moment.
public struct World: Sendable, Hashable {
    public var now: Date
    public var buildings: [ProviderBuilding]
    /// The Engine room (D26). Empty until a server source is connected.
    public var servers: [Server]
    /// The Engine room's DevOps agent, held like a factory (its questions and journal), never a floor on the campus.
    public var ops: Project?
    public static let opsID = "ops:engine-room"
    /// The DevOps agent's state as Orbit shows it at the black hole (nil: switched off): working while it runs, waiting
    /// while it has a question for you.
    public var opsState: SessionState?
    public init(now: Date, buildings: [ProviderBuilding], servers: [Server] = [], ops: Project? = nil) {
        self.now = now; self.buildings = buildings; self.servers = servers; self.ops = ops
    }

    public var serverSummary: ServerSummary { ServerSummary(servers) }
    /// Servers in rack order: problems first (down, warn, ok), then by name, so a problem never falls off the racks.
    public var racks: [Server] {
        servers.sorted { ($1.state, $0.name.lowercased()) < ($0.state, $1.name.lowercased()) }
    }

    public static let empty = World(now: Date(), buildings: Provider.allCases.map { ProviderBuilding(provider: $0, projects: []) })

    public func building(_ p: Provider) -> ProviderBuilding? { buildings.first { $0.provider == p } }
    public var projects: [Project] { buildings.flatMap(\.projects) }
    public func project(id: String) -> Project? { id == Self.opsID ? ops : projects.first { $0.id == id } }

    /// The sessions that wait for you, oldest first.
    public var waitingSessions: [(project: Project, session: Session)] {
        projects.flatMap { p in p.sessions.filter { $0.state(now: now) == .waiting }.map { (p, $0) } }
            .sorted { $0.session.lastAt < $1.session.lastAt }
    }

    /// Everything that waits for you, oldest first (D25): sessions, and the open questions of every factory.
    public var needsYou: [NeedsYou] {
        let sessions = waitingSessions.map { NeedsYou.session($0.project, $0.session) }
        let questions = (projects + [ops].compactMap { $0 }).flatMap { p in (p.factory?.openDecisions ?? []).map { NeedsYou.decision(p, $0) } }
        return (sessions + questions).enumerated().sorted { ($0.element.since, $0.offset) < ($1.element.since, $1.offset) }.map(\.element)
    }

    /// A factory question by its project and id.
    public func decision(project id: String, _ decision: String) -> (project: Project, decision: FactoryDecision)? {
        guard let p = project(id: id), let d = p.factory?.decision(id: decision) else { return nil }
        return (p, d)
    }
}

/// One thing that waits for you: a session, or a yes/no question from a factory's CEO.
public enum NeedsYou: Sendable, Identifiable {
    case session(Project, Session)
    case decision(Project, FactoryDecision)

    public var id: String {
        switch self {
        case .session(_, let s): "session:" + s.id
        case .decision(let p, let d): "decision:" + p.id + "/" + d.id
        }
    }
    public var project: Project {
        switch self { case .session(let p, _), .decision(let p, _): p }
    }
    public var title: String {
        switch self {
        case .session(_, let s): s.title
        case .decision(_, let d): d.title
        }
    }
    /// how long it has waited: a session since its last action, a question since it was asked
    public var since: Date {
        switch self {
        case .session(_, let s): s.lastAt
        case .decision(_, let d): d.asked ?? .distantPast
        }
    }
}
