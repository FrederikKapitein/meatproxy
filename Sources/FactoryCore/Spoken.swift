import Foundation

// What the app says in words where it would otherwise only show (UX review 26 Nov, round 3): the states of a floor's
// chats under their bar, the world for VoiceOver, the right-click menu's titles and keys, and the Larger text size.

extension SessionState {
    /// "2 working · 1 stuck · 1 waits · 4 done": the bar's colours in words, in the bar's order; empty states are left out
    public static func tally(_ states: [SessionState]) -> String {
        allCases.compactMap { st in
            let n = states.filter { $0 == st }.count
            guard n > 0 else { return nil }
            let word: String
            switch st {
            case .working: word = "working"
            case .waiting: word = n == 1 ? "waits" : "wait"
            case .stuck: word = "stuck"
            case .done: word = "done"
            }
            return "\(n) \(word)"
        }.joined(separator: " · ")
    }
}

extension World {
    /// What the world says to VoiceOver for where you are, and how to get on from there: "Pebble Puzzles floor, 6
    /// chats, 4 wait for you. Command-K finds …". The people and floors themselves are reached through ⌘K and Needs you.
    public func spoken(serverRoom: Bool, project: String?, tower: Provider?) -> String {
        let hint = "Command-K finds a project, person or server; N goes to the next that needs you."
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        if serverRoom {
            let sum = serverSummary
            let state = [sum.down > 0 ? "\(sum.down) down" : nil, sum.warn > 0 ? "\(sum.warn) warning" : nil].compactMap { $0 }
            return (["Server room", count(racks.count, "rack", "racks")] + state).joined(separator: ", ") + ". " + hint
        }
        if let id = project, let p = self.project(id: id) {
            let waiting = needsYou.filter { $0.project.id == id }.count
            return (["\(p.name) floor", count(p.sessions.count, "chat", "chats")] + (waiting > 0 ? [count(waiting, "waits for you", "wait for you")] : []))
                .joined(separator: ", ") + ". " + hint
        }
        if let t = tower, let b = building(t) { return "\(t.displayName) tower, \(count(b.projects.count, "floor", "floors")). " + hint }
        let n = needsYou.count
        return (n > 0 ? "Campus, \(count(n, "waits for you", "wait for you"))" : "Campus") + ". " + hint
    }
}

/// A command's words as a Mac menu item.
public enum MenuWords {
    /// "Open the floor" → "Open the Floor": menus are in title case; small words stay small, names keep their capitals
    public static func titleCase(_ s: String) -> String {
        let small: Set<String> = ["a", "an", "the", "and", "or", "of", "in", "on", "to", "for", "at", "by", "as"]
        return s.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { k, w in
            let word = String(w)
            if k > 0, small.contains(word) { return word }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
    /// The key a menu item shows for a command's keys: "⌘2" → ("2", command), "N" → ("n", plain), "esc" → Escape;
    /// nil for two keys ("1 2") or none.
    public static func key(_ keys: String?) -> (key: String, command: Bool)? {
        guard let k = keys, !k.isEmpty, !k.contains(" ") else { return nil }
        if k == "esc" { return ("\u{1b}", false) }
        if k.hasPrefix("⌘") { return (String(k.dropFirst()).replacingOccurrences(of: "−", with: "-").lowercased(), true) }
        return (k.lowercased(), false)
    }
}

/// Text size (Settings › General): Default, or Larger.
public enum TextSize {
    /// Larger moves the reading sizes a whole step up the type scale (11 → 13, 12 → 14, 13 → 15) and the titles by 2
    /// (15 → 17, 19 → 21, 26 → 28), so a 360 pt panel still holds a name on one line.
    public static func points(_ size: Double, larger: Bool) -> Double {
        guard larger else { return size }
        return size <= 11 ? 13 : size <= 12 ? 14 : size <= 13 ? 15 : size + 2
    }
}
