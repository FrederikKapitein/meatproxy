import Foundation
import Testing
@testable import FactoryCollector
import FactoryCore

/// D61: Sentry and Tracker wake a factory's CEO. The network is answered here; nothing leaves the machine.
@Suite struct WakeSourcesTests {
    /// A fake network: answers by the request's host and, for MCP, the JSON-RPC method; records what was asked.
    final class Fake: @unchecked Sendable {
        var sentryIssues: [[String: Any]] = []
        var stories: [String: [[String: Any]]] = ["rejected": [], "unstarted": []]
        var asked: [URLRequest] = []
        var eventStream = false

        var transport: HTTPTransport {
            { [self] r in
                asked.append(r)
                if r.url?.host?.hasSuffix("sentry.io") == true {
                    return (try! JSONSerialization.data(withJSONObject: sentryIssues), 200, [:])
                }
                let body = (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any] ?? [:]
                switch body["method"] as? String {
                case "initialize":
                    return (try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "result": ["protocolVersion": "2025-06-18"]]), 200, ["mcp-session-id": "s-1"])
                case "notifications/initialized":
                    return (Data(), 202, [:])
                case "tools/call":
                    let state = ((body["params"] as? [String: Any])?["arguments"] as? [String: Any])?["state"] as? String ?? ""
                    let payload = String(decoding: try! JSONSerialization.data(withJSONObject: ["items": stories[state] ?? [], "nextCursor": NSNull()]), as: UTF8.self)
                    let reply: [String: Any] = ["jsonrpc": "2.0", "id": 2, "result": ["content": [["type": "text", "text": payload]], "isError": false]]
                    let json = try! JSONSerialization.data(withJSONObject: reply)
                    if eventStream { return (Data("event: message\ndata: \(String(decoding: json, as: UTF8.self))\n\n".utf8), 200, ["content-type": "text/event-stream"]) }
                    return (json, 200, [:])
                default: return nil
                }
            }
        }
    }

    private let sources = FactorySources(sentryOrg: "demo-org", sentryProject: "pebble-app", tracker: "pebble")

    private func factories(bugs: Bool = true, hb: Heartbeat = Heartbeat()) -> [(root: String, sources: FactorySources, heartbeat: Heartbeat, bugsAllowed: Bool)] {
        [("/demo/pebble-puzzles", sources, hb, bugs)]
    }

    @Test func contractNamesItsSources() {
        let text = """
        contract: meatproxy-factory
        version: 4
        sentry: demo-org/pebble-app   # org/project
        sentry-host: de.sentry.io
        tracker: pebble
        """
        #expect(FactoryText.contract(text) == 4)
        let s = FactoryText.sources(text)
        #expect(s.sentryOrg == "demo-org" && s.sentryProject == "pebble-app" && s.sentryHost == "de.sentry.io" && s.tracker == "pebble")
        // a host that is not Sentry's, or a slug with a slash or a space, is ignored
        let bad = FactoryText.sources("sentry: a/b/c\nsentry-host: evil.example.com\ntracker: my project")
        #expect(!bad.hasSentry && bad.sentryHost == "sentry.io" && bad.tracker == nil)
    }

    @Test func sentryWakesForNewAndReturningErrorsAfterAFirstLook() {
        let fake = Fake(), w = WakeSources(transport: fake.transport)
        fake.sentryIssues = [["id": "1", "shortId": "PEB-1", "title": "TypeError in board", "substatus": "ongoing"]]
        // the first look only notes
        #expect(w.check(factories(), tokens: ("sntry", nil)).isEmpty)
        #expect(fake.asked.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sntry")
        #expect(fake.asked.first?.url?.absoluteString.hasPrefix("https://sentry.io/api/0/projects/demo-org/pebble-app/issues/?") == true)
        // a new error, and the old one comes back
        fake.sentryIssues = [["id": "1", "shortId": "PEB-1", "title": "TypeError in board", "substatus": "regressed"],
                             ["id": "2", "shortId": "PEB-2", "title": "Crash on resume", "substatus": "new"]]
        let wakes = w.check(factories(), tokens: ("sntry", nil))
        #expect(wakes.count == 1)
        if case .sentry(let ids)? = wakes.first?.1 { #expect(ids == ["PEB-1: TypeError in board", "PEB-2: Crash on resume"]) }
        else { Issue.record("no Sentry wake") }
        // nothing new: no wake
        #expect(w.check(factories(), tokens: ("sntry", nil)).isEmpty)
    }

    @Test func noSentryWakeWhenBugsAreOffOrTheSwitchIsOffOrNoToken() {
        let fake = Fake(), w = WakeSources(transport: fake.transport)
        var off = Heartbeat(); off.wakeOnSentry = false
        _ = w.check(factories(bugs: false), tokens: ("sntry", nil))
        _ = w.check(factories(hb: off), tokens: ("sntry", nil))
        _ = w.check(factories(), tokens: (nil, nil))
        #expect(fake.asked.isEmpty)
    }

    @Test func trackerWakesForStoriesThatChangeOverMCP() {
        for stream in [false, true] {
            let fake = Fake(), w = WakeSources(transport: fake.transport)
            fake.eventStream = stream
            fake.stories["unstarted"] = [["key": "PEB-7", "title": "Daily puzzle archive", "state": "unstarted"]]
            #expect(w.check(factories(), tokens: (nil, "trk")).isEmpty)
            // the MCP handshake, then the call, with the session and the token
            let calls = fake.asked.filter { $0.url?.host == "tracker.tuinstra.dev" }
            #expect(calls.count == 6 && calls.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer trk" })
            #expect(calls[1].value(forHTTPHeaderField: "Mcp-Session-Id") == "s-1")
            // PEB-7 is rejected now, PEB-8 is new and ready
            fake.stories["unstarted"] = [["key": "PEB-8", "title": "Hint button", "state": "unstarted"]]
            fake.stories["rejected"] = [["key": "PEB-7", "title": "Daily puzzle archive", "state": "rejected"]]
            let wakes = w.check(factories(), tokens: (nil, "trk"))
            if case .tracker(let ids)? = wakes.first?.1 { #expect(ids == ["PEB-7 rejected: Daily puzzle archive", "PEB-8 ready: Hint button"]) }
            else { Issue.record("no Tracker wake (event stream: \(stream))") }
        }
    }

    @Test func aPausedHeartbeatAsksNothing() {
        let fake = Fake(), w = WakeSources(transport: fake.transport)
        _ = w.check(factories(hb: Heartbeat(paused: true)), tokens: ("sntry", "trk"))
        #expect(fake.asked.isEmpty)
    }
}
