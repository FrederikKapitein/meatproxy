import Foundation
import FactoryCore

/// Reads the session files Claude Code and Codex already keep on this Mac, read-only, and turns them into a World.
///   Claude Code  ~/.claude/projects/<project>/<session>.jsonl  (+ <session>/subagents/*.meta.json)
///   Codex        ~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-*.jsonl  (titles in ~/.codex/session_index.jsonl)
/// Not thread-safe: call it from one serial queue.
public final class Collector: @unchecked Sendable {
    public static let window: TimeInterval = 8 * 3600

    private let home: URL
    private let resolver: ProjectResolver
    private var readers: [URL: SessionReader] = [:]
    private var codexNames: [String: String] = [:]
    private var codexIndexDate: Date?
    /// what the sessions would have cost at API prices (D61); `updateCosts()` reads the files, off this queue
    public let costs: CostLedger
    /// CI and merged pull requests per project (D67); `github.update(roots:)` asks gh, off this queue
    public let github = GitHubWatch()

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, resolver: ProjectResolver = ProjectResolver(),
                costStore: URL? = CostLedger.defaultStore) {
        self.home = home
        self.resolver = resolver
        self.costs = CostLedger(home: home, store: costStore)
    }

    /// The sessions as buildings and floors, with every factory on its floor (or a floor of its own). `factories`: the
    /// project folders you switched on as a factory (`FactorySettingsStore`).
    public func world(now: Date = Date(), factories: [String] = []) -> World {
        world(now: now, settings: ProjectSettings(projects: factories.map { .init(root: $0, pinned: true, factory: true) }))
    }

    /// The campus as your project settings shape it (D46): floors from sessions, pinned projects, factories, the Chats floor.
    public func world(now: Date = Date(), settings: ProjectSettings) -> World {
        let factories = settings.factoryRoots
        var w = WorldBuilder.build(sessions(now: now, factories: factories), now: now, showChats: settings.showChats, resolve: resolver.resolve)
        WorldBuilder.attach(factories.map { FactoryFinder.read(root: $0) }, to: &w)
        WorldBuilder.pin(settings.pinnedRoots, to: &w)
        WorldBuilder.hide(settings.hidden, in: &w)
        for b in w.buildings.indices { for p in w.buildings[b].projects.indices where !w.buildings[b].projects[p].isChat {
            w.buildings[b].projects[p].logo = ProjectLogo.find(root: w.buildings[b].projects[p].root)
        } }
        // each floor's cost, keyed like its project id: "claude:/path" or "chatgpt:chats"
        let resolver = self.resolver
        let cost = costs.costs(now: now) { cwd, codex in
            let k = resolver.resolve(cwd), provider = codex ? Provider.chatgpt.rawValue : Provider.claude.rawValue
            return k.isChat ? "\(provider):chats" : "\(provider):\(k.root)"
        }
        for b in w.buildings.indices { for p in w.buildings[b].projects.indices {
            w.buildings[b].projects[p].cost = cost[w.buildings[b].projects[p].id]
            if !w.buildings[b].projects[p].isChat { w.buildings[b].projects[p].github = github.status(root: w.buildings[b].projects[p].root) }
        } }
        return w
    }

    /// `factories`: project folders that claim a session which started outside any project (the home folder or a scratch
    /// folder) but says it works there, like a factory's scheduled CEO run that starts in a scratch folder and cds in.
    public func sessions(now: Date = Date(), factories: [String] = []) -> [Session] {
        loadCodexTitles()
        let files = sessionFiles(now: now)
        let seen = Set(files.map(\.0))
        readers = readers.filter { seen.contains($0.key) }
        var out: [Session] = []
        for (url, provider) in files {
            let r = readers[url] ?? SessionReader(url: url, provider: provider)
            readers[url] = r
            do { try r.read() } catch { continue }
            if provider == .chatgpt, r.title == nil, let name = codexNames[r.id] { r.title = name }
            if r.isSubAgentSession { continue }
            if var s = r.session(), now.timeIntervalSince(s.lastAt) < Self.window {
                // the DevOps agent works in the Server room, never on a floor of a provider tower
                if EngineRoom.contains(s.cwd) { continue }
                if !factories.isEmpty, resolver.resolve(s.cwd).isChat, let root = factories.first(where: { r.mentions($0, home: home.path) }) {
                    s.projectRoot = root
                }
                out.append(s)
            }
        }
        return out.sorted { $0.lastAt > $1.lastAt }
    }

    private func sessionFiles(now: Date) -> [(URL, Provider)] {
        var out: [(URL, Provider)] = []
        let fm = FileManager.default
        func recent(_ u: URL) -> Bool {
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return d.map { now.timeIntervalSince($0) < Self.window } ?? false
        }
        func children(_ u: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? []
        }
        for dir in children(home.appendingPathComponent(".claude/projects")) {
            for f in children(dir) where f.pathExtension == "jsonl" && recent(f) { out.append((f, .claude)) }
        }
        for y in children(home.appendingPathComponent(".codex/sessions")) {
            // a day folder's date says when the session started, not when it was last written, so check every file
            for m in children(y) { for d in children(m) {
                for f in children(d) where f.lastPathComponent.hasPrefix("rollout-") && f.pathExtension == "jsonl" && recent(f) { out.append((f, .chatgpt)) }
            } }
        }
        return out
    }

    private func loadCodexTitles() {
        let url = home.appendingPathComponent(".codex/session_index.jsonl")
        guard let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d != codexIndexDate,
              let data = try? Data(contentsOf: url) else { return }
        codexIndexDate = d
        for line in data.split(separator: 10) {
            if let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
               let id = o["id"] as? String, let name = o["thread_name"] as? String, !name.isEmpty { codexNames[id] = name }
        }
    }
}
