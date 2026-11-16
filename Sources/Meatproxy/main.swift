import Foundation
import FactoryCore
import FactoryCollector

// the settings folder moved with the brand (D45); --dump and --snapshot read it too
if !CommandLine.arguments.contains("--fixture") { AppSupport.migrateLegacyFolder() }

// `Meatproxy --dump` prints what the collector sees, like `python3 live.py`.
if CommandLine.arguments.contains("--dump") {
    let world = Collector().world(settings: ProjectSettingsStore().load())
    let f = DateFormatter(); f.dateFormat = "HH:mm"
    for b in world.buildings {
        print("\(b.provider.displayName): \(b.projects.count) floor(s)")
        for p in b.projects {
            print("  \(p.isChat ? "chat" : "proj") \(p.name)  [\(p.sessions.count) session(s)]")
            for s in p.sessions {
                print("     \(f.string(from: s.lastAt)) \(s.state(now: world.now).rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(s.activities.count) items, \(s.subAgents.count) sub-agents  \(s.title.prefix(48))")
            }
        }
    }
    for p in world.projects { if let f = p.factory {
        print("Factory \(p.name): \(f.autonomy?.level.rawValue ?? "no autonomy.yml")\(f.paused ? " PAUSED" : ""), \(f.activeWorkstreams.count) workstream(s), \(f.openDecisions.count) open question(s), briefing \(f.briefing?.name ?? "none")\(f.problems.isEmpty ? "" : ", unreadable: \(f.problems.joined(separator: ", "))")")
    } }
    print("Needs you: \(world.needsYou.count)")
    exit(0)
}
// `Meatproxy --costs`: what every floor's sessions would have cost at API prices (D61); reads and updates the ledger.
if CommandLine.arguments.contains("--costs") {
    let collector = Collector()
    let started = Date()
    collector.costs.update()
    let world = collector.world(settings: ProjectSettingsStore().load())
    print("Read in \(String(format: "%.1f", Date().timeIntervalSince(started))) s; prices of \(ApiPrices.asOf)")
    for b in world.buildings { for p in b.projects.sorted(by: { ($0.cost?.month ?? 0) > ($1.cost?.month ?? 0) }) {
        guard let c = p.cost else { continue }
        print("  \(b.provider.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)) \(p.name.padding(toLength: 28, withPad: " ", startingAt: 0)) today \(ProjectCost.format(c.today))  7 d \(ProjectCost.format(c.week))  30 d \(ProjectCost.format(c.month))\(c.unpricedTokens > 0 ? "  (\(c.unpricedTokens) unpriced tokens)" : "")")
    } }
    exit(0)
}
// `Meatproxy --ops <server> <action> [name]` (docs/contracts/engine-room.md): the DevOps agent's only way onto a server,
// checked against what that server allows in Meatproxy's own settings.
if let k = CommandLine.arguments.firstIndex(of: "--ops") {
    let args = Array(CommandLine.arguments.dropFirst(k + 1))
    let servers = ServerSettingsStore().load()
    if args.first == "list" || args.isEmpty { print(OpsTool.listing(servers), terminator: ""); exit(0) }
    guard args.count >= 2, let server = servers.first(where: { $0.name == args[0] }) else {
        print("refused: unknown server \(args.first ?? ""); see --ops list"); exit(2)
    }
    let (code, out) = OpsTool.run(server: server, action: args[1], arg: args.count > 2 ? args[2] : nil)
    print(out)
    exit(code)
}
// `Meatproxy --heartbeat` (the launch agent, D47): start every factory whose beat is due, wait for them, exit.
if CommandLine.arguments.contains("--heartbeat") {
    let settings = ProjectSettingsStore().load()
    let center = HeartbeatCenter()
    let started = center.tick(settings)
    for root in started { center.runner.wait(root) }
    print("Heartbeat: \(started.count) run(s)")
    exit(0)
}
if CommandLine.arguments.contains("--snapshot") {
    exit(MainActor.assumeIsolated { Snapshot.run(CommandLine.arguments) })
}
MeatproxyApp.main()
