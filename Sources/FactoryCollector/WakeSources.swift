import Foundation
import Security
import FactoryCore

/// Your tokens for the wake-up sources (D61), in the macOS Keychain: never in a file, a log or the repo.
public enum Secrets {
    public enum Key: String, CaseIterable, Sendable {
        case sentry = "sentry-token", tracker = "tracker-token"
        public var label: String { self == .sentry ? "Sentry" : "Tracker" }
    }
    static let service = "dev.tuinstra.meatproxy"

    public static func get(_ k: Key) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: k.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Saves a token (nil or empty: removes it). Returns whether the Keychain took it.
    @discardableResult
    public static func set(_ k: Key, _ value: String?) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: k.rawValue]
        SecItemDelete(base as CFDictionary)
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return true }
        var add = base; add[kSecValueData as String] = Data(v.utf8); add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// One HTTP exchange, so tests can answer for the network: the body and status, or nil when it failed.
public typealias HTTPTransport = @Sendable (URLRequest) -> (Data, Int, [String: String])?

/// The wake-up sources (D61): every 15 minutes Meatproxy asks each factory's Sentry project for new or returning errors
/// and its Tracker project for stories that changed, and wakes the CEO with their ids and titles. The first look only
/// notes what is there. It reads, never writes, and uses your own tokens.
public final class WakeSources: @unchecked Sendable {
    public static let interval: TimeInterval = 15 * 60

    private let transport: HTTPTransport
    private let lock = NSLock()
    /// per factory: the Sentry issues seen and how they stood ("id" → substatus), the Tracker stories and their state
    private var sentrySeen: [String: [String: String]] = [:]
    private var trackerSeen: [String: [String: String]] = [:]

    public init(transport: @escaping HTTPTransport = WakeSources.systemTransport) { self.transport = transport }

    /// What wakes which factory now. `factories`: each factory's folder, its sources, its heartbeat and whether its
    /// mandate allows bug work (bugs: off means no Sentry wake). Blocking: call it off the main queue.
    public func check(_ factories: [(root: String, sources: FactorySources, heartbeat: Heartbeat, bugsAllowed: Bool)],
                      tokens: (sentry: String?, tracker: String?)) -> [(String, WakeReason)] {
        var wakes: [(String, WakeReason)] = []
        for f in factories where !f.heartbeat.paused {
            if f.heartbeat.wakeOnSentry, f.bugsAllowed, f.sources.hasSentry, let t = tokens.sentry,
               let found = sentry(f.root, f.sources, token: t), !found.isEmpty {
                wakes.append((f.root, .sentry(found)))
            }
            if f.heartbeat.wakeOnTracker, let slug = f.sources.tracker, let t = tokens.tracker,
               let found = tracker(f.root, slug: slug, token: t), !found.isEmpty {
                wakes.append((f.root, .tracker(found)))
            }
        }
        return wakes
    }

    // MARK: Sentry

    /// New errors (an id not seen before) and returning ones (now regressed or escalating), as "APP-12: title".
    func sentry(_ root: String, _ s: FactorySources, token: String) -> [String]? {
        guard let org = s.sentryOrg, let project = s.sentryProject,
              var c = URLComponents(string: "https://\(s.sentryHost)/api/0/projects/\(org)/\(project)/issues/") else { return nil }
        c.queryItems = [.init(name: "query", value: "is:unresolved level:[error,fatal]"), .init(name: "statsPeriod", value: "14d"),
                        .init(name: "sort", value: "date"), .init(name: "limit", value: "50")]
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, status, _) = transport(r), status == 200,
              let issues = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var now: [String: String] = [:], names: [String: String] = [:]
        for i in issues {
            guard let id = i["id"] as? String else { continue }
            now[id] = (i["substatus"] as? String) ?? "ongoing"
            names[id] = "\(i["shortId"] as? String ?? id): \((i["title"] as? String ?? "").prefix(80))"
        }
        lock.lock(); let before = sentrySeen[root]; sentrySeen[root] = (before ?? [:]).merging(now) { _, n in n }; lock.unlock()
        guard let before else { return [] }   // the first look only notes
        let returning: Set<String> = ["regressed", "escalating"]
        return now.keys.sorted().filter { id in
            guard let was = before[id] else { return true }
            return returning.contains(now[id]!) && !returning.contains(was)
        }.compactMap { names[$0] }
    }

    // MARK: Tracker

    /// Stories that became rejected, or newly ready to pick up (unstarted), as "NTF-3 rejected: title".
    func tracker(_ root: String, slug: String, token: String) -> [String]? {
        let mcp = MCPClient(url: URL(string: "https://tracker.tuinstra.dev/mcp/delivery")!, token: token, transport: transport)
        var now: [String: String] = [:], names: [String: String] = [:]
        for state in ["rejected", "unstarted"] {
            guard let result = mcp.call("list_stories", ["project": slug, "state": state, "limit": 50]),
                  let items = result["items"] as? [[String: Any]] else { return nil }
            for s in items {
                guard let key = s["key"] as? String else { continue }
                now[key] = state
                names[key] = "\(key) \(state == "unstarted" ? "ready" : state): \((s["title"] as? String ?? "").prefix(80))"
            }
        }
        lock.lock(); let before = trackerSeen[root]; trackerSeen[root] = now; lock.unlock()
        guard let before else { return [] }
        return now.keys.sorted().filter { before[$0] != now[$0] }.compactMap { names[$0] }
    }

    // MARK: testing a token

    /// Whether a token works (the Test button in Settings): one read per Sentry project the factories name, or, when
    /// none names one, Sentry's own API root. The answer is one line, and true when it worked. Blocking.
    public func testSentry(token: String, projects: [FactorySources]) -> (ok: Bool, line: String) {
        let named = projects.filter(\.hasSentry)
        if named.isEmpty {
            guard let (_, status, _) = transport(Self.request("https://sentry.io/api/0/", token: token)) else { return (false, "Sentry did not answer") }
            return status == 200 ? (true, "Token accepted. No factory names a Sentry project yet.") : (false, Self.reason(status))
        }
        var ok: [String] = []
        for s in named {
            guard let org = s.sentryOrg, let project = s.sentryProject else { continue }
            guard let (_, status, _) = transport(Self.request("https://\(s.sentryHost)/api/0/projects/\(org)/\(project)/", token: token)) else {
                return (false, "\(s.sentryHost) did not answer")
            }
            guard status == 200 else { return (false, "\(org)/\(project): " + Self.reason(status)) }
            ok.append("\(org)/\(project)")
        }
        return (true, "Works: reads " + ok.joined(separator: ", "))
    }

    /// Whether a Tracker token works: one small read of each project the factories name, or a hello when none does.
    public func testTracker(token: String, slugs: [String]) -> (ok: Bool, line: String) {
        let mcp = MCPClient(url: URL(string: "https://tracker.tuinstra.dev/mcp/delivery")!, token: token, transport: transport)
        if slugs.isEmpty {
            return mcp.hello() ? (true, "Token accepted. No factory names a Tracker project yet.") : (false, "Tracker refused the token or did not answer")
        }
        for slug in slugs where mcp.call("list_stories", ["project": slug, "limit": 1]) == nil {
            return (false, "Could not read the Tracker project \(slug)")
        }
        return (true, "Works: reads " + slugs.joined(separator: ", "))
    }

    static func request(_ url: String, token: String) -> URLRequest {
        var r = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
    static func reason(_ status: Int) -> String {
        switch status {
        case 401: return "the token was refused (401)"
        case 403: return "the token may not read this (403)"
        case 404: return "not found, or the token cannot see it (404)"
        default: return "Sentry answered \(status)"
        }
    }

    // MARK: network

    public static let systemTransport: HTTPTransport = { request in
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var out: (Data, Int, [String: String])?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let h = response as? HTTPURLResponse {
                let headers = Dictionary(uniqueKeysWithValues: h.allHeaderFields.compactMap { k, v in (k as? String).map { ($0.lowercased(), "\(v)") } })
                out = (data ?? Data(), h.statusCode, headers)
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 30)
        return out
    }
}

/// A small MCP client over streamable HTTP: initialize, then one tool call; reads a JSON or an event-stream answer.
struct MCPClient {
    let url: URL
    let token: String
    let transport: HTTPTransport

    private func post(_ body: [String: Any], session: String?) -> (Any?, [String: String])? {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        if let session { r.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, status, headers) = transport(r), (200..<300).contains(status) else { return nil }
        return (Self.message(data), headers)
    }

    /// The JSON-RPC message in an answer: the body itself, or the last `data:` line of an event stream.
    static func message(_ data: Data) -> Any? {
        if let o = try? JSONSerialization.jsonObject(with: data) { return o }
        let text = String(decoding: data, as: UTF8.self)
        for line in text.components(separatedBy: "\n").reversed() where line.hasPrefix("data:") {
            if let o = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)) { return o }
        }
        return nil
    }

    /// Says hello (initialize): true when the server takes the token.
    func hello() -> Bool {
        let hello: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                    "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](),
                                               "clientInfo": ["name": "meatproxy", "version": "1"]]]
        guard let (reply, _) = post(hello, session: nil) else { return false }
        return (reply as? [String: Any])?["result"] != nil
    }

    /// Calls a tool and returns its result as JSON: the structured content, or the JSON in its first text block.
    func call(_ tool: String, _ arguments: [String: Any]) -> [String: Any]? {
        let hello: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                    "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](),
                                               "clientInfo": ["name": "meatproxy", "version": "1"]]]
        guard let (_, headers) = post(hello, session: nil) else { return nil }
        let session = headers["mcp-session-id"]
        _ = post(["jsonrpc": "2.0", "method": "notifications/initialized"], session: session)
        guard let (reply, _) = post(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": tool, "arguments": arguments]], session: session),
              let result = (reply as? [String: Any])?["result"] as? [String: Any], result["isError"] as? Bool != true else { return nil }
        if let s = result["structuredContent"] as? [String: Any] { return s }
        if let text = ((result["content"] as? [[String: Any]])?.first { $0["type"] as? String == "text" })?["text"] as? String {
            return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        }
        return nil
    }
}
