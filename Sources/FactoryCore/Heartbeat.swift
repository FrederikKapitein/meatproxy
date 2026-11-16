import Foundation

/// A factory's heartbeat (D47): when the app wakes its CEO. Like a heartbeat in an agent company, the CEO does not run
/// all the time; it wakes on a rhythm (a few times a day, or every few hours) and when something happens that it should
/// act on: your answer, a failed CI run, a "run now". The app is the runner; nothing relies on scheduled tasks in
/// Claude or ChatGPT.
public struct Heartbeat: Codable, Equatable, Sendable {
    public enum Days: String, Codable, Sendable, CaseIterable { case weekdays, everyDay }
    public enum Runtime: String, Codable, Sendable, CaseIterable {
        case claude, codex
        public var label: String { self == .claude ? "Claude Code" : "Codex" }
    }

    /// on which days the times below beat
    public var days: Days = .weekdays
    /// local wall-clock times, "07:10"
    public var times: [String] = ["07:10"]
    /// instead of times: every this many minutes (on the days above)
    public var everyMinutes: Int?
    public var runtime: Runtime = .claude
    /// your answer to a question wakes the CEO a few minutes later (answers in that window make one run)
    public var wakeOnAnswer = true
    /// a new failed CI run on the default branch wakes the CEO
    public var wakeOnCI = true
    /// a new or returning Sentry error, and a Tracker story that changed, wake the CEO (contract v4, D61)
    public var wakeOnSentry = true
    public var wakeOnTracker = true
    /// the heartbeat is off: nothing wakes the CEO but "Run now"
    public var paused = false
    /// guards against a factory burning your plan (D48): at most this many automatic runs a day, at least this long
    /// between two runs, and at most this many turns in one Claude run. "Run now" is yours and skips them.
    public var runsPerDay = 6
    public var cooldownMinutes = 20
    public var maxTurns = 60
    /// at most this much a day at API prices (D61, US dollars); above it automatic runs wait until tomorrow. nil: no cap
    public var maxCostPerDay: Double?
    /// which model and effort the CEO gets for which kind of wake-up (D70)
    public var models = ModelPolicy()

    public init(days: Days = .weekdays, times: [String] = ["07:10"], everyMinutes: Int? = nil, runtime: Runtime = .claude,
                wakeOnAnswer: Bool = true, wakeOnCI: Bool = true, paused: Bool = false) {
        self.days = days; self.times = times; self.everyMinutes = everyMinutes; self.runtime = runtime
        self.wakeOnAnswer = wakeOnAnswer; self.wakeOnCI = wakeOnCI; self.paused = paused
    }

    // tolerant decoding: a field added later has its default
    enum CodingKeys: String, CodingKey { case days, times, everyMinutes, runtime, wakeOnAnswer, wakeOnCI, paused, runsPerDay, cooldownMinutes, maxTurns, maxCostPerDay, wakeOnSentry, wakeOnTracker, models }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), x = Heartbeat()
        days = try c.decodeIfPresent(Days.self, forKey: .days) ?? x.days
        times = try c.decodeIfPresent([String].self, forKey: .times) ?? x.times
        everyMinutes = try c.decodeIfPresent(Int.self, forKey: .everyMinutes)
        runtime = try c.decodeIfPresent(Runtime.self, forKey: .runtime) ?? x.runtime
        wakeOnAnswer = try c.decodeIfPresent(Bool.self, forKey: .wakeOnAnswer) ?? x.wakeOnAnswer
        wakeOnCI = try c.decodeIfPresent(Bool.self, forKey: .wakeOnCI) ?? x.wakeOnCI
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? x.paused
        runsPerDay = try c.decodeIfPresent(Int.self, forKey: .runsPerDay) ?? x.runsPerDay
        cooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? x.cooldownMinutes
        maxTurns = try c.decodeIfPresent(Int.self, forKey: .maxTurns) ?? x.maxTurns
        maxCostPerDay = try c.decodeIfPresent(Double.self, forKey: .maxCostPerDay)
        wakeOnSentry = try c.decodeIfPresent(Bool.self, forKey: .wakeOnSentry) ?? x.wakeOnSentry
        wakeOnTracker = try c.decodeIfPresent(Bool.self, forKey: .wakeOnTracker) ?? x.wakeOnTracker
        models = try c.decodeIfPresent(ModelPolicy.self, forKey: .models) ?? x.models
    }

    /// How long after your last answer the CEO wakes, so that a few answers in a row make one run.
    public static let answerWindow: TimeInterval = 3 * 60

    /// "Weekdays 07:10", "Every day 07:10 and 13:00", "Weekdays, every 4 h", "Paused"
    public var summary: String {
        if paused { return "Paused" }
        let d = days == .weekdays ? "Weekdays" : "Every day"
        if let m = everyMinutes { return "\(d), every " + (m % 60 == 0 ? "\(m / 60) h" : "\(m) min") }
        return "\(d) " + times.sorted().joined(separator: times.count > 2 ? ", " : " and ")
    }

    private func onDay(_ date: Date, _ cal: Calendar) -> Bool {
        days == .everyDay || !cal.isDateInWeekend(date)
    }

    private static func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }

    /// The scheduled beats in (from, to], oldest first. Interval beats fall on whole multiples from midnight.
    public func beats(after from: Date, through to: Date, calendar cal: Calendar = .current) -> [Date] {
        guard !paused, to > from else { return [] }
        var out: [Date] = []
        var day = cal.startOfDay(for: from)
        let last = cal.startOfDay(for: to)
        while day <= last {
            if onDay(day, cal) {
                let mins: [Int]
                if let m = everyMinutes, m > 0 { mins = Array(stride(from: 0, to: 24 * 60, by: m)) }
                else { mins = times.compactMap(Self.minutes).sorted() }
                for m in mins {
                    if let t = cal.date(byAdding: .minute, value: m, to: day), t > from, t <= to { out.append(t) }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    /// The next scheduled beat after `date` (within two weeks), or nil when paused or empty.
    public func next(after date: Date, calendar cal: Calendar = .current) -> Date? {
        beats(after: date, through: date.addingTimeInterval(15 * 86400), calendar: cal).first
    }

    /// The beat that is due now: the latest scheduled beat after the last run, up to `now`. A beat missed while the
    /// app was closed runs once ("caught up"), never once per missed beat.
    public func due(lastRun: Date?, now: Date, calendar cal: Calendar = .current) -> Date? {
        // never look further back than a day: an old factory switched on today does not catch up a week of beats
        let since = max(lastRun ?? now.addingTimeInterval(-86400), now.addingTimeInterval(-86400))
        return beats(after: since, through: now, calendar: cal).last
    }
}

/// Why the CEO woke up: said in the run's prompt and shown in the HUD.
public enum WakeReason: Codable, Equatable, Sendable {
    case schedule(Date)
    case caughtUp(Date)
    case answered([String])
    case runNow
    case ciFailed(repo: String, run: String)
    case idea([String])
    case alert([String])
    /// new or returning Sentry errors ("APP-12: TypeError in checkout"), D61
    case sentry([String])
    /// Tracker stories that changed ("NTF-3 rejected"), D61
    case tracker([String])

    public var label: String {
        switch self {
        case .schedule: "Heartbeat"
        case .caughtUp: "Missed heartbeat, caught up"
        case .answered(let ids): "You answered " + ids.joined(separator: ", ")
        case .runNow: "Run now"
        case .ciFailed(let repo, _): "CI failed in \(repo)"
        case .idea(let ids): "You sent " + ids.joined(separator: ", ")
        case .alert(let ids): "Alert " + ids.joined(separator: ", ")
        case .sentry(let ids): "Sentry: " + ids.joined(separator: ", ")
        case .tracker(let ids): "Tracker: " + ids.joined(separator: ", ")
        }
    }

    /// What the CEO is told about why it woke, at the end of its prompt.
    public var prompt: String {
        switch self {
        case .schedule: "You were woken by your regular heartbeat."
        case .caughtUp: "You were woken because a heartbeat was missed while Meatproxy was closed; this run catches up."
        case .answered(let ids): "You were woken because Marcel answered \(ids.joined(separator: ", ")) in Meatproxy. Act on the answers first (playbook step 2)."
        case .runNow: "Marcel asked for a run now from Meatproxy."
        case .ciFailed(let repo, let run): "You were woken because a CI run failed on the default branch of \(repo) (run \(run)). Look at it first."
        case .alert(let ids): "You were woken by \(ids.joined(separator: ", ")) in alerts/. Look at those first."
        case .sentry(let ids): "You were woken by new or returning errors in Sentry: \(ids.joined(separator: "; ")). Look at them first with your own Sentry access; what you may do about them is the bugs item of factory/mandate.yml."
        case .tracker(let ids): "You were woken because stories changed in Tracker: \(ids.joined(separator: "; ")). Read them with your own Tracker access first."
        case .idea(let ids): "You were woken because Marcel sent \(ids.joined(separator: ", ")) from Meatproxy (factory/ideas/). Your ideas are always handled: turn each into a workstream (or decline it with a reason), as the factory contract says."
        }
    }
}

/// One CEO run as the app keeps it: when, why, and how it ended.
public struct HeartbeatRun: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case running, ok, failed, timedOut, takenOver }
    public var started: Date
    public var ended: Date?
    public var reason: WakeReason
    public var outcome: Outcome
    /// the exit code, or why it could not start
    public var detail: String?
    /// something you should fix even when the run went fine (its allowlist was ignored)
    public var warning: String?
    /// the model and effort it ran with, when not the runtime's default (D70)
    public var model: String?
    public init(started: Date, ended: Date? = nil, reason: WakeReason, outcome: Outcome, detail: String? = nil) {
        self.started = started; self.ended = ended; self.reason = reason; self.outcome = outcome; self.detail = detail
    }
}

/// What the HUD shows about a factory's heartbeat.
public struct HeartbeatState: Equatable, Sendable {
    public var config: Heartbeat
    public var last: HeartbeatRun?
    public var next: Date?
    /// a wake-up waiting for its window (your answers), with when it fires
    public var pending: (reason: WakeReason, at: Date)?
    /// why the heartbeat would not start a run now (a guard, D48), if it would not
    public var blocked: Block?
    /// automatic runs started today
    public var runsToday = 0
    public init(config: Heartbeat, last: HeartbeatRun? = nil, next: Date? = nil, pending: (reason: WakeReason, at: Date)? = nil,
                blocked: Block? = nil, runsToday: Int = 0) {
        self.config = config; self.last = last; self.next = next; self.pending = pending; self.blocked = blocked; self.runsToday = runsToday
    }
    public var running: Bool { last?.outcome == .running }
    public static func == (a: Self, b: Self) -> Bool {
        a.config == b.config && a.last == b.last && a.next == b.next && a.pending?.at == b.pending?.at && a.pending?.reason == b.pending?.reason
            && a.blocked == b.blocked && a.runsToday == b.runsToday
    }
}

/// A guard that keeps the heartbeat from starting a run (D48). Every one is said in words in the HUD; a hold waits
/// for you (Resume), the others lift by themselves.
public enum Block: Equatable, Sendable {
    /// "Pause all" is on
    case allPaused
    /// held for you: the CI breaker tripped
    case held(String)
    /// the runtime's plan limit was hit; no factory on it starts until then
    case planLimit(Heartbeat.Runtime, until: Date)
    /// the day's automatic runs are used up
    case dailyCap(Int)
    /// today's work at API prices reached the factory's cap (D61)
    case costCap(spent: Double, cap: Double)
    /// too soon after the last run
    case coolingDown(until: Date)
    /// you took over in Meatproxy's terminal: nothing starts until you close that tab (D57)
    case takenOver
    /// the runtime's provider is down on its status page (D69): no run burns on an outage
    case providerDown(String)

    public var waitsForYou: Bool { if case .held = self { return true }; return false }
    public var text: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        switch self {
        case .allPaused: return "All factories are paused"
        case .held(let why): return why
        case .planLimit(let r, let until): return "\(r.label) plan limit reached, waiting until \(f.string(from: until))"
        case .dailyCap(let n): return "\(n) of \(n) runs today, the next one tomorrow"
        case .costCap(let spent, let cap): return "\(ProjectCost.format(spent)) today at API prices, over the cap of \(ProjectCost.format(cap)): the next run tomorrow"
        case .coolingDown(let until): return "Cooling down until \(f.string(from: until))"
        case .takenOver: return "In your hands: you took over in the terminal"
        case .providerDown(let name): return "\(name) is down on its status page: the run waits until it is back"
        }
    }
}

/// Which model and effort a run gets (D70), by why it woke: the routine heartbeat, your own input (an answer, an idea,
/// Run now), or something that broke (CI, Sentry, Tracker, an alert). nil keeps the runtime's own default.
public struct ModelPolicy: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case routine, input, incident
        public var label: String { self == .routine ? "Routine heartbeat" : self == .input ? "Your answers, ideas, Run now" : "CI, Sentry, Tracker, alerts" }
    }
    public struct Choice: Codable, Equatable, Sendable {
        public var model: String?
        public var effort: String?
        public init(model: String? = nil, effort: String? = nil) { self.model = model; self.effort = effort }
    }
    public var routine = Choice()
    public var input = Choice()
    public var incident = Choice()
    public init(routine: Choice = Choice(), input: Choice = Choice(), incident: Choice = Choice()) {
        self.routine = routine; self.input = input; self.incident = incident
    }
    public subscript(_ k: Kind) -> Choice {
        get { k == .routine ? routine : k == .input ? input : incident }
        set { switch k { case .routine: routine = newValue; case .input: input = newValue; case .incident: incident = newValue } }
    }
    public static func kind(_ r: WakeReason) -> Kind {
        switch r {
        case .schedule, .caughtUp: return .routine
        case .answered, .idea, .runNow: return .input
        case .ciFailed, .sentry, .tracker, .alert: return .incident
        }
    }
    public func choice(for r: WakeReason) -> Choice { self[Self.kind(r)] }

    /// What each runtime offers: its model aliases and effort levels (the first, nil, is its own default).
    public static let models: [Heartbeat.Runtime: [String]] = [.claude: ["haiku", "sonnet", "opus"], .codex: ["gpt-6-luna", "gpt-6.1-sol", "gpt-6-astra", "gpt-5.3-codex"]]
    public static let efforts: [Heartbeat.Runtime: [String]] = [.claude: ["low", "medium", "high", "xhigh", "max"], .codex: ["low", "medium", "high"]]
}
