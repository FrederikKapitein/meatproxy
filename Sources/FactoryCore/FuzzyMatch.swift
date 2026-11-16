import Foundation

/// Search as you type (D72): the letters you type, in order, anywhere in the text; a match at the start, at the start
/// of a word or in one run scores higher. Case and accents do not count. nil: no match.
public enum FuzzyMatch {
    public static func score(_ query: String, _ text: String) -> Int? {
        let q = Array(fold(query).filter { !$0.isWhitespace }), t = Array(fold(text))
        guard !q.isEmpty else { return 0 }
        var score = 0, ti = 0, run = 0, last = -2
        for c in q {
            var found = false
            while ti < t.count {
                defer { ti += 1 }
                guard t[ti] == c else { continue }
                let wordStart = ti == 0 || !(t[ti - 1].isLetter || t[ti - 1].isNumber)
                run = ti == last + 1 ? run + 1 : 0
                score += 1 + (wordStart ? 8 : 0) + run * 3 + (ti == 0 ? 6 : 0)
                last = ti; found = true
                break
            }
            if !found { return nil }
        }
        // shorter texts win a tie: "Pebble" before "Pebble Puzzles settings"
        return score * 100 - min(t.count, 99)
    }

    /// Plain strings ranked best first.
    public static func rank(_ query: String, _ items: [String], limit: Int = 50) -> [String] { rank(query, items, limit: limit) { $0 } }

    /// The items ranked best first, at most `limit`.
    public static func rank<T>(_ query: String, _ items: [T], limit: Int = 50, text: (T) -> String) -> [T] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return Array(items.prefix(limit)) }
        return items.compactMap { i in score(query, text(i)).map { (i, $0) } }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
}
