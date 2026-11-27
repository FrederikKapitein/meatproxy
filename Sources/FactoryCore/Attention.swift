import Foundation

// What the app says about the campus as a whole, outside the world itself (UX review 26 Nov): what is broken (one quiet
// line over Needs you, D25's middle way), and what stops when you quit.

extension Session {
    /// When it got stuck, if it is stuck now: the first failure of the run of failures that keeps it stuck (each one
    /// within 90 seconds of the next, the last one less than 90 seconds ago). nil when it is not stuck.
    public func stuckSince(now: Date) -> Date? {
        guard state(now: now) == .stuck else { return nil }
        let failures = activities.filter(\.failed).map(\.at).sorted()
        guard var since = failures.last else { return nil }
        for at in failures.dropLast().reversed() {
            guard since.timeIntervalSince(at) < 90 else { break }
            since = at
        }
        return since
    }
}

extension World {
    /// How long a session has to stay stuck before it counts as broken: a single failed command is part of the work,
    /// and the agent usually tries again on its own.
    public static let stuckFor: TimeInterval = 120

    /// What is broken now (D25's middle way): a server that is down, a project whose CI on main is red, a session that
    /// has been stuck for more than two minutes. Never a question for you: it is not in Needs you's count, and N does
    /// not walk it. One line each, worst first.
    public var broken: [String] {
        var out = servers.filter { $0.state == .down }.sorted { $0.name < $1.name }.map { "\($0.name) is down" }
        out += projects.filter { $0.github?.ciFailing == true }.map { "\($0.name): CI on main is red" }
        for p in projects {
            for s in p.sessions {
                guard let since = s.stuckSince(now: now), now.timeIntervalSince(since) > Self.stuckFor else { continue }
                out.append("\(s.persona.name) is stuck in \(p.name)")
            }
        }
        return out
    }
}

/// What runs in the app and stops when it quits (UX review 26 Nov, point 6): open terminals, the CEO runs it started,
/// the DevOps agent's run. Said in one sentence for the quit alert.
public enum RunningWork {
    /// "1 terminal and the CEO run of Pebble Puzzles will stop."; nil when nothing runs.
    public static func line(terminals: Int, ceoRuns: [String], devops: Bool) -> String? {
        var parts: [String] = []
        if terminals > 0 { parts.append("\(terminals) terminal\(terminals == 1 ? "" : "s")") }
        if !ceoRuns.isEmpty {
            parts.append("the CEO run\(ceoRuns.count == 1 ? "" : "s") of \(NeedsYou.list(ceoRuns.sorted()))")
        }
        if devops { parts.append("the DevOps agent's run") }
        guard !parts.isEmpty else { return nil }
        // a comma before the last "and" when a part has an "and" of its own
        let s = parts.dropLast().contains(where: { $0.contains(" and ") }) ? parts.dropLast().joined(separator: ", ") + ", and " + parts.last! : NeedsYou.list(parts)
        return s.prefix(1).uppercased() + s.dropFirst() + " will stop."
    }
}
