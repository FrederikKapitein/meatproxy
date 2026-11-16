import Foundation

/// What one model request used, in tokens, split the way the API prices it (D61).
public struct TokenUsage: Codable, Equatable, Sendable {
    /// input not served from a cache
    public var input: Int = 0
    /// input written to a cache: a short-lived entry (Claude 5 min, OpenAI 30 min) and a long one (1 h, 12 h)
    public var cacheWriteShort: Int = 0
    public var cacheWriteLong: Int = 0
    public var cacheRead: Int = 0
    /// output, thinking and reasoning included
    public var output: Int = 0
    /// Claude's fast mode (twice the price)
    public var fast = false

    public init(input: Int = 0, cacheWriteShort: Int = 0, cacheWriteLong: Int = 0, cacheRead: Int = 0, output: Int = 0, fast: Bool = false) {
        self.input = input; self.cacheWriteShort = cacheWriteShort; self.cacheWriteLong = cacheWriteLong
        self.cacheRead = cacheRead; self.output = output; self.fast = fast
    }

    /// all input of the request, cached or not: what decides a long-context price
    public var promptTokens: Int { input + cacheWriteShort + cacheWriteLong + cacheRead }
    public var total: Int { promptTokens + output }
}

/// The public API list prices, per million tokens, to show what work would have cost through the API, also when it ran
/// under a subscription (D61). Estimates, not invoices. Update this table (and `asOf`) when the providers change their
/// prices; a model it does not know counts as unpriced, never as free.
public enum ApiPrices {
    /// when these prices were checked: Anthropic's model table and OpenAI's pricing page
    public static let asOf = "16 Nov 2026"

    public struct Rate: Sendable, Equatable {
        public var input: Double, output: Double, cacheRead: Double, writeShort: Double, writeLong: Double
        public init(_ input: Double, _ output: Double, read: Double, writeShort: Double, writeLong: Double) {
            self.input = input; self.output = output; self.cacheRead = read; self.writeShort = writeShort; self.writeLong = writeLong
        }
        /// Claude: a cache write costs 1.25× input for 5 minutes, 2× for an hour
        static func claude(_ i: Double, _ o: Double, read: Double) -> Rate { Rate(i, o, read: read, writeShort: i * 1.25, writeLong: i * 2) }
    }

    /// A model's prices, with a dearer rate above a prompt size (long context).
    public struct Price: Sendable, Equatable {
        public var base: Rate
        public var longAbove: Int? = nil
        public var long: Rate? = nil
    }

    /// Model name fragments, most specific first (so "opus-5-5" is found before "opus-5").
    static let table: [(String, Price)] = [
        // Anthropic
        ("fable-5-2", Price(base: .claude(8, 40, read: 0.20))),
        ("mythos-5-2", Price(base: .claude(8, 40, read: 0.20))),
        ("fable-5-1", Price(base: .claude(10, 50, read: 0.25))),
        ("mythos-5-1", Price(base: .claude(10, 50, read: 0.25))),
        ("fable-5", Price(base: .claude(10, 50, read: 1.00))),
        ("mythos-5", Price(base: .claude(10, 50, read: 1.00))),
        ("opus-5-5", Price(base: .claude(4, 20, read: 0.20))),
        ("opus-5", Price(base: .claude(5, 25, read: 0.50))),
        ("opus-4-8", Price(base: .claude(5, 25, read: 0.50))),
        ("opus-4-7", Price(base: .claude(5, 25, read: 0.50))),
        ("opus-4-6", Price(base: .claude(5, 25, read: 0.50))),
        ("opus-4-5", Price(base: .claude(5, 25, read: 0.50))),
        ("opus-4", Price(base: .claude(15, 75, read: 1.50))),
        ("sonnet-5-5", Price(base: .claude(2, 10, read: 0.10))),
        ("sonnet-5", Price(base: .claude(2, 10, read: 0.20))),
        ("sonnet-4", Price(base: .claude(3, 15, read: 0.30))),
        ("haiku-5-5", Price(base: .claude(0.10, 0.50, read: 0.01), longAbove: 100_000, long: .claude(0.50, 2.50, read: 0.05))),
        ("haiku-4-5", Price(base: .claude(1, 5, read: 0.10))),
        // OpenAI (Codex): a cache write lasts 30 min or 12 h; long context above 272K input tokens
        ("gpt-6.1-sol", Price(base: Rate(2, 10, read: 0.10, writeShort: 2.50, writeLong: 5), longAbove: 272_000,
                              long: Rate(4, 15, read: 0.20, writeShort: 5, writeLong: 10))),
        ("gpt-6-luna", Price(base: Rate(0.10, 0.50, read: 0.01, writeShort: 0.125, writeLong: 0.25), longAbove: 272_000,
                             long: Rate(0.20, 0.75, read: 0.02, writeShort: 0.25, writeLong: 0.50))),
        ("gpt-6-astra", Price(base: Rate(10, 50, read: 1, writeShort: 12.50, writeLong: 25), longAbove: 272_000,
                              long: Rate(20, 75, read: 2, writeShort: 25, writeLong: 50))),
        ("gpt-5.3-codex", Price(base: Rate(1.75, 14, read: 0.175, writeShort: 1.75, writeLong: 1.75))),
    ]

    /// The price of a model by its name as the session file has it ("claude-opus-5-5", "claude-sonnet-5-5[1m]",
    /// "gpt-6.1-sol"); nil when unknown.
    public static func price(_ model: String) -> Price? {
        let m = model.lowercased()
        return table.first { m.contains($0.0) }?.1
    }

    /// What one request cost in US dollars at list price, or nil for a model without a known price. `prompt`: the
    /// request's whole prompt in tokens when `u` is only part of it; it decides the long-context rate.
    public static func cost(model: String, _ u: TokenUsage, prompt: Int? = nil) -> Double? {
        guard let p = price(model) else { return nil }
        let size = max(prompt ?? 0, u.promptTokens)
        let r = (p.longAbove.map { size > $0 } ?? false) ? (p.long ?? p.base) : p.base
        let sum = Double(u.input) * r.input + Double(u.output) * r.output + Double(u.cacheRead) * r.cacheRead
            + Double(u.cacheWriteShort) * r.writeShort + Double(u.cacheWriteLong) * r.writeLong
        return sum / 1_000_000 * (u.fast ? 2 : 1)
    }
}

/// What a project's work cost at API prices (D61): today, the last 7 days and the last 30, with the tokens no price
/// was known for.
public struct ProjectCost: Hashable, Sendable {
    public var today: Double = 0
    public var week: Double = 0
    public var month: Double = 0
    public var unpricedTokens: Int = 0
    public init(today: Double = 0, week: Double = 0, month: Double = 0, unpricedTokens: Int = 0) {
        self.today = today; self.week = week; self.month = month; self.unpricedTokens = unpricedTokens
    }

    /// "$12.40", "$0.82", "<$0.01", "$1,240"
    public static func format(_ usd: Double) -> String {
        if usd <= 0 { return "$0" }
        if usd < 0.01 { return "<$0.01" }
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = usd >= 100 ? 0 : 2; f.minimumFractionDigits = usd >= 100 ? 0 : 2
        return f.string(from: NSNumber(value: usd)) ?? String(format: "$%.2f", usd)
    }
}
