import Foundation

/// What the campus shows of what goes on (D66): the sky follows the clock, weather over a building says something is
/// broken, a factory's delivery flies to the plaza, a new project gets a crane, a sub-agent takes the lift, a deploy
/// runs to the Server room. Pure: the scene asks, the tests check.
public enum CampusSignals {
    // MARK: 5A day and night

    /// How light it is at an hour of the day (0 night, 1 day): dawn from 6 to 8, dusk from 18 to 20.
    public static func daylight(hour: Double) -> Double {
        let h = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        if h < 6 || h >= 20 { return 0 }
        if h < 8 { return smooth((h - 6) / 2) }
        if h < 18 { return 1 }
        return 1 - smooth((h - 18) / 2)
    }

    /// The hour of a moment on the Mac's clock, with minutes as a fraction.
    public static func hour(_ d: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }

    /// Whether an hour falls in quiet hours written "22:00-07:00" (over midnight is fine). Empty or unreadable: never.
    public static func quiet(_ spec: String, hour: Double) -> Bool {
        let parts = spec.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let a = clock(parts[0]), let b = clock(parts[1]), a != b else { return false }
        return a < b ? (hour >= a && hour < b) : (hour >= a || hour < b)
    }
    private static func clock(_ s: String) -> Double? {
        let hm = s.split(separator: ":")
        guard let h = Double(hm.first ?? ""), h >= 0, h < 24 else { return nil }
        let m = hm.count > 1 ? Double(hm[1]) ?? -1 : 0
        guard m >= 0, m < 60 else { return nil }
        return h + m / 60
    }

    // MARK: 5B weather is status

    public enum Weather: String, Sendable { case clear, cloudy, rain }

    /// A project left broken: a session whose turn has ended while its last test, push or deploy failed, in the last
    /// 12 hours. A red test in the middle of a turn is part of the work (the session shows it as stuck), not weather.
    /// With GitHub (D67) it is simply CI: the newest run on main failed.
    public static func broken(_ p: Project, now: Date) -> Bool {
        if let g = p.github { return g.ciFailing }
        return p.sessions.contains { s in
            guard !s.turnOpen, s.liveRun != true,
                  let last = s.activities.last(where: { $0.kind == .test || $0.kind == .push || $0.kind == .deploy }) else { return false }
            return last.failed && now.timeIntervalSince(last.at) < 12 * 3600
        }
    }

    /// Rain over a tower while one of its projects is left broken.
    public static func weather(_ b: ProviderBuilding, now: Date) -> Weather {
        b.projects.contains { broken($0, now: now) } ? .rain : .clear
    }

    /// Over the Server room: rain while something is down, clouds while something warns.
    public static func weather(servers s: ServerSummary) -> Weather { s.down > 0 ? .rain : s.warn > 0 ? .cloudy : .clear }

    // MARK: 5C delivery

    /// Deliveries after a moment, oldest first: with GitHub (D67) every merged pull request of any project; without it a
    /// factory's pushes and deploys that went through.
    public static func deliveries(_ p: Project, after: Date) -> [Date] {
        if let g = p.github { return g.merged.filter { $0 > after } }
        guard p.factory != nil else { return [] }
        return p.sessions.flatMap(\.activities).filter { ($0.kind == .push || $0.kind == .deploy) && !$0.failed && $0.at > after }.map(\.at).sorted()
    }

    // MARK: 5D crane

    /// A new project: its first and only session started in the last day and is not done yet. When it is done, the
    /// ribbon is cut.
    public static func underConstruction(_ p: Project, now: Date) -> Bool {
        guard !p.isChat, p.sessions.count == 1, let s = p.sessions.first, let start = s.startedAt,
              now.timeIntervalSince(start) < 24 * 3600 else { return false }
        return s.state(now: now) != .done
    }

    // MARK: 5E lift

    /// The helpers at work in a project (session id and sub-agent id): a new one takes the lift to its storey.
    public static func helpers(_ p: Project) -> Set<String> {
        Set(p.sessions.flatMap { s in s.subAgents.filter { !$0.finished }.map { s.id + "/" + $0.id } })
    }

    // MARK: 5F data stream

    /// A deploy under way: a session at work whose last step, in the last ten minutes, is a deploy.
    public static func deploying(_ p: Project, now: Date) -> Bool {
        p.sessions.contains { s in
            guard s.state(now: now) == .working, let last = s.activities.last(where: { $0.kind != .turnEnd }) else { return false }
            return last.kind == .deploy && !last.failed && now.timeIntervalSince(last.at) < 600
        }
    }
}
