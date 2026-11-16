import Foundation

/// A Dark Software Factory: a project folder with a `factory/` folder in it. A CEO agent keeps its queue there in plain
/// files, and those files are the source of truth: the latest briefing, the workstreams with their phase, the yes/no
/// decisions that wait for you and the autonomy level. The format is the factory's own data contract
/// (`factory/README.md` in the factory); this file only reads it.
/// The contract between a factory and Meatproxy (docs/contracts/factory.md). A factory declares its version in
/// factory/contract.yml; a feature is on only when the factory's version has it.
public enum FactoryContract {
    public static let name = "meatproxy-factory"
    /// the newest version this Meatproxy knows
    public static let current = 4
    /// the first version with ideas (factory/ideas/)
    public static let ideas = 2
    /// the first version with your mandate (factory/mandate.yml), written by Meatproxy
    public static let mandate = 3
    /// the first version with wake-up sources in contract.yml (Sentry, Tracker), D61
    public static let sources = 4
}

/// Where a factory's bugs and stories come from (contract v4, D61): its Sentry project and its Tracker project. Meatproxy
/// looks there every 15 minutes and wakes the CEO for a new error or a story that changed; the CEO reads the rest itself.
public struct FactorySources: Sendable, Hashable {
    /// "org/project" slugs
    public var sentryOrg: String?
    public var sentryProject: String?
    /// the Sentry host the organization lives on: sentry.io, or a region such as de.sentry.io
    public var sentryHost: String = "sentry.io"
    /// the Tracker project's slug
    public var tracker: String?
    public init(sentryOrg: String? = nil, sentryProject: String? = nil, sentryHost: String = "sentry.io", tracker: String? = nil) {
        self.sentryOrg = sentryOrg; self.sentryProject = sentryProject; self.sentryHost = sentryHost; self.tracker = tracker
    }
    public var hasSentry: Bool { sentryOrg != nil && sentryProject != nil }
}

public struct Factory: Sendable, Hashable {
    /// the project folder (the parent of `factory/`)
    public var root: String
    public var briefing: Briefing?
    public var workstreams: [Workstream]
    public var decisions: [FactoryDecision]
    public var autonomy: Autonomy?
    /// your ideas for the CEO (`factory/ideas/`), newest last
    public var ideas: [FactoryIdea] = []
    /// the contract version it declares in factory/contract.yml (nil: none, read as version 1)
    public var contract: Int?
    public var contractVersion: Int { contract ?? 1 }
    public var takesIdeas: Bool { contractVersion >= FactoryContract.ideas }
    public var takesMandate: Bool { contractVersion >= FactoryContract.mandate }
    /// your mandate (factory/mandate.yml), when there is one
    public var mandate: FactoryMandate?
    /// where its bugs and stories come from (contract.yml, v4)
    public var sources = FactorySources()
    public var takesSources: Bool { contractVersion >= FactoryContract.sources }
    /// it declares a contract this Meatproxy does not know yet
    public var newerContract: Bool { contractVersion > FactoryContract.current }
    /// files that could not be read, by name, so the HUD can say so instead of hiding them
    public var problems: [String]

    public init(root: String, briefing: Briefing? = nil, workstreams: [Workstream] = [], decisions: [FactoryDecision] = [],
                autonomy: Autonomy? = nil, problems: [String] = []) {
        self.root = root; self.briefing = briefing; self.workstreams = workstreams; self.decisions = decisions
        self.autonomy = autonomy; self.problems = problems
    }

    /// The questions that wait for you, oldest first.
    public var openDecisions: [FactoryDecision] {
        decisions.filter { $0.status == .open }.sorted { ($0.asked ?? .distantPast, $0.id) < ($1.asked ?? .distantPast, $1.id) }
    }
    /// The workstreams on the floor: dropped ones are gone for good.
    public var activeWorkstreams: [Workstream] { workstreams.filter { $0.phase != .dropped } }
    public var paused: Bool { autonomy?.paused ?? false }
    /// Switched on, but its CEO has written nothing yet.
    public var isEmpty: Bool { briefing == nil && autonomy == nil && workstreams.isEmpty && decisions.isEmpty && problems.isEmpty }
    public func decision(id: String) -> FactoryDecision? { decisions.first { $0.id == id } }
}

// MARK: workstreams

/// PLAN → BUILD → TEST → SHIP → DONE; dropped is final.
public enum WorkPhase: String, Sendable, Hashable, CaseIterable, Codable {
    case plan, build, test, ship, done, dropped
    public var label: String { rawValue.uppercased() }
    /// 0…4 along the track; dropped is off it
    public var step: Int? { self == .dropped ? nil : WorkPhase.allCases.firstIndex(of: self) }
    /// The room of a floor where the work of this phase happens (D39).
    public var room: FloorRoom {
        switch self {
        case .plan: .planning
        case .build: .development
        case .test: .testing
        case .ship: .deploy
        case .done, .dropped: .lounge
        }
    }
}

/// One line of a workstream's `## Log`: "- 2026-11-17 build: …" or a step back, "- 2026-11-17 test → build: …".
public struct WorkLogEntry: Sendable, Hashable {
    public var date: String
    public var from: WorkPhase?
    public var phase: WorkPhase?
    public var text: String
    public init(date: String, from: WorkPhase? = nil, phase: WorkPhase?, text: String) {
        self.date = date; self.from = from; self.phase = phase; self.text = text
    }
    /// A step backwards, like test → build.
    public var isBack: Bool {
        guard let f = from?.step, let t = phase?.step else { return false }
        return t < f
    }
}

public struct Workstream: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var type: String
    public var phase: WorkPhase
    public var source: String?
    public var branch: String?
    public var pr: String?
    public var release: String?
    public var opened: String?
    public var updated: String?
    public var decisions: [String]
    public var log: [WorkLogEntry]

    public init(id: String, title: String, type: String = "feature", phase: WorkPhase, source: String? = nil, branch: String? = nil,
                pr: String? = nil, release: String? = nil, opened: String? = nil, updated: String? = nil, decisions: [String] = [],
                log: [WorkLogEntry] = []) {
        self.id = id; self.title = title; self.type = type; self.phase = phase; self.source = source; self.branch = branch
        self.pr = pr; self.release = release; self.opened = opened; self.updated = updated; self.decisions = decisions; self.log = log
    }

    public var backSteps: [WorkLogEntry] { log.filter(\.isBack) }
    /// It went back and has not moved on since: the latest phase change in the log is a step back (D39's ↩ note).
    public var wentBack: Bool { log.last { $0.phase != nil }?.isBack ?? false }
    /// The furthest phase the log says it reached, for the PLAN … DONE track.
    public var reached: Int { max(phase.step ?? 0, log.compactMap { $0.phase?.step }.max() ?? 0, log.compactMap { $0.from?.step }.max() ?? 0) }
}

extension Project {
    /// A workstream's planet in Orbit is a body of its own round the factory's star; its id says whose it is.
    public static func workstreamPlanetID(_ projectID: String, _ workstream: String) -> String { "ws:\(projectID)#\(workstream)" }
    public static func workstream(fromPlanetID id: String) -> (project: String, workstream: String)? {
        guard id.hasPrefix("ws:"), let hash = id.lastIndex(of: "#") else { return nil }
        return (String(id[id.index(id.startIndex, offsetBy: 3)..<hash]), String(id[id.index(after: hash)...]))
    }
    /// An idea you sent, as a small body round the factory's star until the CEO takes it.
    public static func ideaPlanetID(_ projectID: String, _ idea: String) -> String { "idea:\(projectID)#\(idea)" }
    public static func isIdeaPlanet(_ id: String) -> Bool { id.hasPrefix("idea:") }
    /// Whether one of the factory's open questions is about this workstream: then it waits for you too.
    public func waits(_ w: Workstream) -> Bool { factory?.openDecisions.contains { $0.workstream == w.id || w.decisions.contains($0.id) } ?? false }
}

// MARK: decisions

public enum DecisionStatus: String, Sendable, Hashable, CaseIterable, Codable {
    case open, yes, no, expired, withdrawn
}

/// A link under Evidence: a markdown link or a bare URL.
public struct FactoryLink: Sendable, Hashable {
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}

/// One yes/no question to you: `factory/decisions/D-NNNN-<slug>.md`.
public struct FactoryDecision: Identifiable, Sendable, Hashable {
    public var id: String
    /// the question, one sentence
    public var title: String
    public var kind: String
    public var gate: String?
    public var status: DecisionStatus
    public var workstream: String?
    public var replaces: String?
    public var asked: Date?
    public var answered: Date?
    public var why: String
    public var evidence: String
    public var onYes: String
    public var onNo: String
    public var answer: String
    /// the file's path relative to the project folder, "factory/decisions/D-0001-….md"
    public var file: String

    public init(id: String, title: String, kind: String = "other", gate: String? = nil, status: DecisionStatus = .open,
                workstream: String? = nil, replaces: String? = nil, asked: Date? = nil, answered: Date? = nil, why: String = "",
                evidence: String = "", onYes: String = "", onNo: String = "", answer: String = "", file: String = "") {
        self.id = id; self.title = title; self.kind = kind; self.gate = gate; self.status = status; self.workstream = workstream
        self.replaces = replaces; self.asked = asked; self.answered = answered; self.why = why; self.evidence = evidence
        self.onYes = onYes; self.onNo = onNo; self.answer = answer; self.file = file
    }

    /// The links under Evidence, in order.
    public var links: [FactoryLink] { FactoryText.links(evidence) }
}

// MARK: briefing and autonomy

/// The CEO's latest briefing: `factory/briefings/YYYY-MM-DD.md` (a second run that day: `-2`).
public struct Briefing: Sendable, Hashable {
    /// "2026-11-16" or "2026-11-16-2"
    public var name: String
    public var briefing: [String]
    public var needsYou: [String]
    public var delivered: [String]
    public init(name: String, briefing: [String], needsYou: [String] = [], delivered: [String] = []) {
        self.name = name; self.briefing = briefing; self.needsYou = needsYou; self.delivered = delivered
    }
    /// the day it was written, "2026-11-16"
    public var day: String { String(name.prefix(10)) }
}

public enum AutonomyLevel: String, Sendable, Hashable, CaseIterable {
    case assistant, hybrid, dark
    /// How dark the floor is (factory-model: autonomy is how dark the floor stays): 0 lights on … 1 lights out.
    public var darkness: Double { self == .assistant ? 0 : self == .hybrid ? 0.45 : 0.8 }
}

/// `factory/autonomy.yml`: the level, every gate `ask` or `notify`, the streak of yeses per gate, and STOP.
public struct Autonomy: Sendable, Hashable {
    public struct Gate: Sendable, Hashable {
        public var name: String
        public var notify: Bool
        public var streak: Int
        public init(name: String, notify: Bool, streak: Int) { self.name = name; self.notify = notify; self.streak = streak }
    }
    public var level: AutonomyLevel
    public var gates: [Gate]
    /// STOP on line 1: the factory starts and ships nothing
    public var paused: Bool
    public init(level: AutonomyLevel, gates: [Gate], paused: Bool = false) { self.level = level; self.gates = gates; self.paused = paused }
    /// Five yeses in a row on a gate earn a promote question (CHARTER).
    public static let promoteAfter = 5
}

// MARK: parsing

/// Reads the factory's Markdown and YAML files. Plain text in, model out: no file system here, so every platform can use
/// it and the tests need no disk. Unknown keys are ignored; a file without its required fields is a problem, not a crash.
public enum FactoryText {
    /// Builds a factory from its files, keyed by their path under the project folder ("factory/decisions/D-0001-x.md").
    public static func factory(root: String, files: [String: String]) -> Factory {
        var f = Factory(root: root)
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let name = (path as NSString).lastPathComponent
            if path.hasPrefix("factory/decisions/") && name.hasPrefix("D-") && name.hasSuffix(".md") {
                if let d = decision(text, file: path) { f.decisions.append(d) } else { f.problems.append(name) }
            } else if path.hasPrefix("factory/workstreams/") && name.hasPrefix("W-") && name.hasSuffix(".md") {
                if let w = workstream(text) { f.workstreams.append(w) } else { f.problems.append(name) }
            } else if path.hasPrefix("factory/ideas/") && name.hasPrefix("I-") && name.hasSuffix(".md") {
                if let i = idea(text, file: path) { f.ideas.append(i) } else { f.problems.append(name) }
            } else if path == "factory/mandate.yml" {
                f.mandate = FactoryMandate.parse(text)
            } else if path == "factory/contract.yml" {
                f.contract = contract(text)
                if f.contract == nil { f.problems.append(name) } else { f.sources = sources(text) }
            } else if path == "factory/autonomy.yml" {
                f.autonomy = autonomy(text)
            }
        }
        let briefings = files.keys.filter { $0.hasPrefix("factory/briefings/") && $0.hasSuffix(".md") }
            .map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
            .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}(-\d+)?$"#, options: .regularExpression) != nil }
        if let latest = briefings.max(by: { briefingOrderKey($0) < briefingOrderKey($1) }), let text = files["factory/briefings/\(latest).md"] {
            f.briefing = briefing(text, name: latest)
        }
        f.workstreams.sort { $0.id < $1.id }
        f.decisions.sort { $0.id < $1.id }
        f.ideas.sort { $0.id < $1.id }
        // your mandate sets how dark the factory runs (D44, D56)
        if let m = f.mandate, f.takesMandate {
            if f.autonomy == nil { f.autonomy = Autonomy(level: m.autonomyLevel, gates: []) } else { f.autonomy?.level = m.autonomyLevel }
        }
        return f
    }

    /// "2026-11-16-2" sorts after "2026-11-16".
    public static func briefingOrderKey(_ name: String) -> (String, Int) {
        (String(name.prefix(10)), name.count > 11 ? Int(name.dropFirst(11)) ?? 1 : 1)
    }

    // MARK: front matter

    /// The `---` block at the top as key → raw value (comments and quotes stripped), and the body after it.
    /// Nil when there is no front matter.
    public static func frontMatter(_ text: String) -> (fields: [String: String], body: String)? {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              lines[first].trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines[(first + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else { return nil }
        var fields: [String: String] = [:]
        for line in lines[(first + 1)..<end] {
            guard let (k, v) = keyValue(line) else { continue }
            fields[k] = v
        }
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }

    /// "status: open   # open | yes" → ("status", "open"). Only top-level keys.
    static func keyValue(_ line: String) -> (String, String)? {
        guard let c = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("#") else { return nil }
        let key = line[..<c].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.range(of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else { return nil }
        return (key, value(String(line[line.index(after: c)...])))
    }

    /// A value without its trailing comment (a # after whitespace) and quotes.
    public static func value(_ raw: String) -> String {
        var v = raw
        if let r = v.range(of: #"\s+#.*$"#, options: .regularExpression) { v.removeSubrange(r) }
        v = v.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("#") { return "" }
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) { v = String(v.dropFirst().dropLast()) }
        return v
    }

    public static func optional(_ v: String?) -> String? {
        guard let v, !v.isEmpty, !["null", "~", "none"].contains(v.lowercased()) else { return nil }
        return v
    }

    /// "[D-0001, D-0002]" or "D-0001" → ["D-0001", "D-0002"]
    static func list(_ v: String?) -> [String] {
        guard let v = optional(v) else { return [] }
        let inner = v.hasPrefix("[") && v.hasSuffix("]") ? String(v.dropFirst().dropLast()) : v
        return inner.split(separator: ",").map { value(String($0)) }.filter { !$0.isEmpty }
    }

    private static let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let iso = ISO8601DateFormatter()
    private static let dayOnly: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f }()
    public static func date(_ v: String?) -> Date? {
        guard let v = optional(v) else { return nil }
        return iso.date(from: v) ?? isoFrac.date(from: v) ?? dayOnly.date(from: v)
    }

    // MARK: sections

    /// "## Why" → its text, up to the next heading of the same or a higher level.
    public static func sections(_ body: String) -> [String: String] {
        var out: [String: String] = [:], cur: String?, buf: [String] = []
        func flush() { if let cur { out[cur.lowercased()] = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) } }
        for line in body.components(separatedBy: "\n") {
            if let h = heading(line) { flush(); cur = h; buf = [] } else if cur != nil { buf.append(line) }
        }
        flush()
        return out
    }

    /// "## Needs you" or "# Needs you" or a line that is only "**Needs you**" → "Needs you"
    static func heading(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil {
            return t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        }
        if t.count > 4, t.hasPrefix("**"), t.hasSuffix("**") {
            return String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        }
        return nil
    }

    /// The lines of a section as short items: list markers and blank lines dropped.
    static func items(_ section: String?) -> [String] {
        (section ?? "").components(separatedBy: "\n").map { line -> String in
            var t = line.trimmingCharacters(in: .whitespaces)
            if let r = t.range(of: #"^([-*+]|\d+[.)])\s+"#, options: .regularExpression) { t.removeSubrange(r) }
            return t
        }.filter { !$0.isEmpty }
    }

    /// Markdown links `[title](url)` and bare http(s) URLs, in order, without duplicates.
    public static func links(_ text: String) -> [FactoryLink] {
        var out: [FactoryLink] = [], seen = Set<String>()
        let ns = text as NSString
        let md = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#)
        let bare = try! NSRegularExpression(pattern: #"https?://[^\s)>\]]+"#)
        var taken: [NSRange] = []
        var found: [(Int, FactoryLink)] = []
        for m in md.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            taken.append(m.range)
            found.append((m.range.location, FactoryLink(title: ns.substring(with: m.range(at: 1)), url: ns.substring(with: m.range(at: 2)))))
        }
        for m in bare.matches(in: text, range: NSRange(location: 0, length: ns.length)) where !taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            var url = ns.substring(with: m.range)
            while let last = url.last, ".,;:".contains(last) { url.removeLast() }
            found.append((m.range.location, FactoryLink(title: shortTitle(url), url: url)))
        }
        for (_, l) in found.sorted(by: { $0.0 < $1.0 }) where seen.insert(l.url).inserted { out.append(l) }
        return out
    }

    /// "https://github.com/o/r/pull/12" → "github.com/o/r/pull/12"
    static func shortTitle(_ url: String) -> String {
        var s = url.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
        if s.hasSuffix("/") { s.removeLast() }
        return s.count > 48 ? String(s.prefix(47)) + "…" : s
    }

    // MARK: the files

    public static func decision(_ text: String, file: String) -> FactoryDecision? {
        guard let (fm, body) = frontMatter(text), let id = optional(fm["id"]), let title = optional(fm["title"]),
              let raw = optional(fm["status"]), let status = DecisionStatus(rawValue: raw.lowercased()) else { return nil }
        let s = sections(body)
        return FactoryDecision(id: id, title: title, kind: optional(fm["kind"]) ?? "other", gate: optional(fm["gate"]), status: status,
                               workstream: optional(fm["workstream"]), replaces: optional(fm["replaces"]), asked: date(fm["asked"]),
                               answered: date(fm["answered"]), why: s["why"] ?? "", evidence: s["evidence"] ?? "",
                               onYes: s["on yes"] ?? "", onNo: s["on no"] ?? "", answer: s["answer"] ?? "", file: file)
    }

    public static func idea(_ text: String, file: String) -> FactoryIdea? {
        guard let (fm, body) = frontMatter(text), let id = optional(fm["id"]), let title = optional(fm["title"]),
              let raw = optional(fm["status"]), let status = FactoryIdea.Status(rawValue: raw.lowercased()) else { return nil }
        let s = sections(body)
        let text = body.components(separatedBy: "\n## ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var i = FactoryIdea(id: id, title: title, status: status, sent: date(fm["sent"]), decision: optional(fm["decision"]),
                            text: text, reply: s["ceo"] ?? "", file: file)
        i.workstream = optional(fm["workstream"])
        return i
    }

    /// `contract: meatproxy-factory` and `version: N`; nil when it is another contract or has no version.
    public static func contract(_ text: String) -> Int? {
        var name: String?, version: Int?
        for line in text.components(separatedBy: "\n") {
            guard let (k, v) = keyValue(line) else { continue }
            if k == "contract" { name = v } else if k == "version" { version = Int(v) }
        }
        guard name == FactoryContract.name else { return nil }
        return version
    }

    /// The wake-up sources in contract.yml (v4): `sentry: org/project`, `sentry-host: de.sentry.io`, `tracker: slug`.
    /// A slug is letters, digits, dots, dashes and underscores; anything else is ignored.
    public static func sources(_ text: String) -> FactorySources {
        var s = FactorySources()
        func slug(_ v: String) -> String? { v.range(of: #"^[A-Za-z0-9._-]{1,80}$"#, options: .regularExpression) != nil ? v : nil }
        for line in text.components(separatedBy: "\n") {
            guard let (k, v) = keyValue(line), v != "null", !v.isEmpty else { continue }
            switch k {
            case "sentry":
                let parts = v.split(separator: "/").map(String.init)
                if parts.count == 2, let o = slug(parts[0]), let p = slug(parts[1]) { s.sentryOrg = o; s.sentryProject = p }
            case "sentry-host":
                if v.range(of: #"^([a-z0-9-]+\.)*sentry\.io$"#, options: .regularExpression) != nil { s.sentryHost = v }
            case "tracker": s.tracker = slug(v)
            default: break
            }
        }
        return s
    }

    public static func workstream(_ text: String) -> Workstream? {
        guard let (fm, body) = frontMatter(text), let id = optional(fm["id"]), let title = optional(fm["title"]),
              let raw = optional(fm["phase"]), let phase = WorkPhase(rawValue: raw.lowercased()) else { return nil }
        return Workstream(id: id, title: title, type: optional(fm["type"]) ?? "feature", phase: phase, source: optional(fm["source"]),
                          branch: optional(fm["branch"]), pr: optional(fm["pr"]), release: optional(fm["release"]),
                          opened: optional(fm["opened"]), updated: optional(fm["updated"]), decisions: list(fm["decisions"]),
                          log: log(sections(body)["log"]))
    }

    /// "- 2026-11-17 test → build: tester found …" (also "->") and "- 2026-11-16 plan: proposed …".
    static func log(_ section: String?) -> [WorkLogEntry] {
        let re = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2})\s+(?:([a-z]+)\s*(?:→|->)\s*)?([a-z]+)\s*:\s*(.*)$"#, options: .caseInsensitive)
        return items(section).compactMap { line in
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                // a line in another shape still counts as history, without a phase
                return line.isEmpty ? nil : WorkLogEntry(date: String(line.prefix(10)), phase: nil, text: line)
            }
            func g(_ k: Int) -> String? { m.range(at: k).location == NSNotFound ? nil : ns.substring(with: m.range(at: k)) }
            let from = g(2).flatMap { WorkPhase(rawValue: $0.lowercased()) }, to = g(3).flatMap { WorkPhase(rawValue: $0.lowercased()) }
            return WorkLogEntry(date: g(1) ?? "", from: from, phase: to, text: g(4) ?? "")
        }
    }

    public static func briefing(_ text: String, name: String) -> Briefing {
        let s = sections(frontMatter(text)?.body ?? text)
        return Briefing(name: name, briefing: Array(items(s["briefing"]).prefix(5)), needsYou: items(s["needs you"]), delivered: items(s["delivered"]))
    }

    /// The small YAML of autonomy.yml: `level:`, and `gates:` / `streaks:` blocks of `name: value`.
    public static func autonomy(_ text: String) -> Autonomy {
        let lines = text.components(separatedBy: "\n")
        let paused = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("STOP") ?? false
        var level: AutonomyLevel?, gates: [(String, String)] = [], streaks: [String: Int] = [:], block = ""
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            let indented = line.hasPrefix(" ") || line.hasPrefix("\t")
            if !indented {
                guard let (k, v) = keyValue(line) else { block = ""; continue }
                block = k
                if k == "level" { level = AutonomyLevel(rawValue: v.lowercased()) }
                continue
            }
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let c = t.firstIndex(of: ":"), !t.hasPrefix("-") else { continue }
            let k = String(t[..<c]).trimmingCharacters(in: .whitespaces), v = value(String(t[t.index(after: c)...]))
            if block == "gates" { gates.append((k, v.lowercased())) } else if block == "streaks" { streaks[k] = Int(v) ?? 0 }
        }
        let list = gates.map { Autonomy.Gate(name: $0.0, notify: $0.1 == "notify", streak: streaks[$0.0] ?? 0) }
        // the level is derived from the gates; the file's own line wins when it is there
        let derived: AutonomyLevel = list.isEmpty || list.allSatisfy { !$0.notify } ? .assistant : list.allSatisfy(\.notify) ? .dark : .hybrid
        return Autonomy(level: level ?? derived, gates: list, paused: paused)
    }
}

/// An idea you sent the CEO from Meatproxy (`factory/ideas/I-NNNN-<slug>.md`). The CEO takes it (files a plan decision
/// for it) or declines it with a reason; until then it is new.
public struct FactoryIdea: Identifiable, Sendable, Hashable {
    public enum Status: String, Sendable { case new, taken, declined }
    public var id: String
    public var title: String
    public var status: Status
    public var sent: Date?
    /// the decision the CEO filed for it (contract v2), or the workstream it became (v3: your ideas need no yes)
    public var decision: String?
    public var workstream: String?
    /// what you wrote
    public var text: String
    /// the CEO's answer under `## CEO`
    public var reply: String
    public var file: String
    public init(id: String, title: String, status: Status, sent: Date?, decision: String?, text: String, reply: String, file: String) {
        self.id = id; self.title = title; self.status = status; self.sent = sent; self.decision = decision
        self.text = text; self.reply = reply; self.file = file
    }
}

/// Your mandate for a factory (contract v3, D56): how much its CEO may do on its own, its role, and your preferences.
/// Meatproxy writes it (factory/mandate.yml); the CEO reads it every run and follows it over autonomy.yml and its playbook.
public struct FactoryMandate: Hashable, Sendable {
    public enum Level: String, CaseIterable, Sendable { case assistant, hybrid, dark, custom }
    public enum Mode: String, CaseIterable, Sendable { case ask, notify, off }
    public enum Role: String, CaseIterable, Sendable { case orchestrator, handsOn = "hands-on" }

    /// What the CEO may do, each ask (a yes/no question first), notify (do it, tell in the briefing) or off (never).
    public enum Item: String, CaseIterable, Sendable {
        // (your own ideas from the inbox are always handled: no item for them, D56)
        case propose, bugs, dependencies, prs, ship, store, spend, promote
        public var label: String {
            switch self {
            case .propose: "Come up with ideas of its own"
            case .bugs: "Pick up Sentry and CI bugs"
            case .dependencies: "Dependency and security updates"
            case .prs: "Open and merge its own PRs, after an independent test"
            case .ship: "Ship to production"
            case .store: "Store releases"
            case .spend: "Spend money (paid services, extra CI minutes)"
            case .promote: "Change its own gates (promote proposals)"
            }
        }
    }

    public var level: Level = .assistant
    public var items: [Item: Mode] = FactoryMandate.preset(.assistant)
    public var role: Role = .orchestrator
    /// a few fixed preferences
    public var quietHours: String = ""
    public var briefingLanguage: String = "en"
    public var proposalsPerRun: Int = 2
    public var prSize: String = "small"
    public var batchSmallFixes: Bool = true
    /// anything else, in your words: part of the mandate the CEO must follow
    public var notes: String = ""

    public init() {}

    /// The levels as presets over the items: Assistant asks everything; Hybrid lets planning, bugs, dependencies and its
    /// PRs through and asks before ship, store, spend and its own gates; Dark lets everything through but spend and store.
    public static func preset(_ l: Level) -> [Item: Mode] {
        switch l {
        case .assistant, .custom: return Dictionary(uniqueKeysWithValues: Item.allCases.map { ($0, .ask) })
        case .hybrid: return [.propose: .ask, .bugs: .notify, .dependencies: .notify, .prs: .notify, .ship: .ask, .store: .ask, .spend: .ask, .promote: .ask]
        case .dark: return [.propose: .notify, .bugs: .notify, .dependencies: .notify, .prs: .notify, .ship: .notify, .store: .ask, .spend: .ask, .promote: .notify]
        }
    }

    /// What an item means, written next to it in mandate.yml so the CEO reads it there.
    public static func meaning(_ i: Item) -> String {
        switch i {
        case .propose: "come up with ideas of its own: product improvements and new workstreams it thinks of"
        case .bugs: "pick up Sentry and CI bugs"
        case .dependencies: "dependency and security updates"
        case .prs: "open and merge its own PRs, after an independent test"
        case .ship: "ship to production"
        case .store: "store releases"
        case .spend: "spend money: paid services, extra CI minutes"
        case .promote: "change its own gates in autonomy.yml (promote proposals)"
        }
    }

    public func mode(_ i: Item) -> Mode { items[i] ?? .ask }

    /// Picks a level: its preset (Custom keeps what is set now).
    public mutating func set(level l: Level) {
        level = l
        if l != .custom { items = Self.preset(l) }
    }

    /// The floor's darkness (D44): the level, or for Custom what its items amount to.
    public var autonomyLevel: AutonomyLevel {
        switch level {
        case .assistant: return .assistant
        case .hybrid: return .hybrid
        case .dark: return .dark
        case .custom:
            let lets = Item.allCases.filter { mode($0) == .notify }.count
            return lets == 0 ? .assistant : lets >= 6 ? .dark : .hybrid
        }
    }

    /// "Orchestrator · Hybrid · 2 preferences"
    public var summary: String {
        var prefs = 0
        if !quietHours.isEmpty { prefs += 1 }
        if briefingLanguage != "en" { prefs += 1 }
        if proposalsPerRun != 2 { prefs += 1 }
        if prSize != "small" { prefs += 1 }
        if !batchSmallFixes { prefs += 1 }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { prefs += 1 }
        return [role == .orchestrator ? "Orchestrator" : "Works along", level.rawValue.capitalized,
                prefs == 0 ? nil : "\(prefs) preference\(prefs == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: the file

    /// factory/mandate.yml as Meatproxy writes it.
    public var yaml: String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        var out = """
        # Marcel's mandate for this factory, written by Meatproxy (meatproxy-factory v3). The CEO follows it on every run;
        # it wins over autonomy.yml and the playbook. Change it in Meatproxy, not here.
        level: \(level.rawValue)            # assistant | hybrid | dark | custom
        role: \(role.rawValue)        # orchestrator (delegates all work) | hands-on (may do small things itself)
        items:                    # ask: a yes/no question first · notify: do it, say so in the briefing · off: never

        """
        for i in Item.allCases {
            let key = "  \(i.rawValue): \(mode(i).rawValue)"
            out += key.padding(toLength: max(key.count + 1, 26), withPad: " ", startingAt: 0) + "# " + Self.meaning(i) + "\n"
        }
        out += """
        preferences:
          quiet_hours: \(q(quietHours))
          briefing_language: \(briefingLanguage)
          proposals_per_run: \(proposalsPerRun)
          pr_size: \(prSize)
          batch_small_fixes: \(batchSmallFixes)
        notes: |

        """
        let lines = notes.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        out += (lines == [""] ? ["  (none)"] : lines.map { "  " + $0 }).joined(separator: "\n") + "\n"
        return out
    }

    /// Reads factory/mandate.yml (tolerant: a field it does not know keeps its default).
    public static func parse(_ text: String) -> FactoryMandate {
        var m = FactoryMandate(), block = "", notes: [String] = []
        for raw in text.components(separatedBy: "\n") {
            if block == "notes" {
                if raw.hasPrefix("  ") || raw.isEmpty { notes.append(String(raw.dropFirst(min(2, raw.count)))); continue }
                block = ""
            }
            let line = raw.components(separatedBy: " #").first ?? raw
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            let indented = line.hasPrefix(" ")
            guard let c = line.firstIndex(of: ":") else { continue }
            let k = line[..<c].trimmingCharacters(in: .whitespaces)
            var v = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = String(v.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
            if !indented {
                block = k
                switch k {
                case "level": m.level = Level(rawValue: v) ?? m.level
                case "role": m.role = Role(rawValue: v) ?? m.role
                default: break
                }
                continue
            }
            if block == "items", let i = Item(rawValue: k), let mode = Mode(rawValue: v) { m.items[i] = mode }
            if block == "preferences" {
                switch k {
                case "quiet_hours": m.quietHours = v
                case "briefing_language": m.briefingLanguage = v
                case "proposals_per_run": m.proposalsPerRun = Int(v) ?? m.proposalsPerRun
                case "pr_size": m.prSize = v
                case "batch_small_fixes": m.batchSmallFixes = v == "true"
                default: break
                }
            }
        }
        let n = notes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        m.notes = n == "(none)" ? "" : n
        if m.level != .custom { m.items = preset(m.level) }
        return m
    }
}
