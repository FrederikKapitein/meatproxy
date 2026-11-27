import SwiftUI
import AppKit
import FactoryCore
import FactoryCollector

/// One server in the inspector (D52, C9), opened by clicking its rack, its row, or its body in Orbit: its state once,
/// its problem with the DevOps agent's open question about it and the answer, its gauges and last two hours, the sites
/// it serves, what the DevOps agent may do there (with a switch when it is off), and three buttons of one shape.
struct ServerDetail: View {
    @EnvironmentObject private var model: AppModel
    let server: Server
    /// your yes was written while the DevOps agent is off: it says when it runs
    @State private var savedWhileOff = false

    var body: some View {
        let config = model.serverConfigs.first { $0.id == server.id }
        let question = model.world.ops.flatMap { ops in AppModel.question(about: server.name, in: ops).map { (ops, $0) } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                stateTag
                if let h = config?.host { Text(h).font(.mono12).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                Spacer(minLength: 0)
            }
            .contextMenu { ServerMenu(server: server, host: config?.host) }
            problem(question)
            if let m = server.metrics { gauges(m) }
            let history = model.serverHistory[server.id] ?? []
            if history.count > 2 { HistoryCard(samples: history) }
            if let c = config, !c.siteURLs.isEmpty { sites(c) }
            if let c = config { devops(c) }
            actions(config)
        }
    }

    private var color: Color { server.state == .down ? .stuck : server.state == .warn ? .warn : .done }

    @ViewBuilder private var stateTag: some View {
        switch server.state {
        case .ok: Tag("Running fine", tone: .done, icon: "dot")
        case .warn: Tag("Needs a look", tone: .warn)
        case .down: Tag("Down", tone: .stuck)
        }
    }

    /// what is wrong, what the DevOps agent proposes, and your answer, in one card (C9)
    @ViewBuilder private func problem(_ q: (Project, FactoryDecision)?) -> some View {
        let m = server.metrics
        if server.state != .ok || q != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let m, let d = m.disk, d >= ServerProbe.diskWarn || q != nil {
                    Meter(label: "Disk", value: [ServerMetrics.size(m.diskUsedBytes, of: m.diskTotalBytes), "\(d)%"].compactMap { $0 }.joined(separator: " · "),
                          fraction: Double(d) / 100, warnAt: Double(ServerProbe.diskWarn) / 100)
                        .padding(12)
                } else if server.state == .down {
                    // since when, why, and the last time it was fine: what you need to decide what to do
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            PixelIcon("sq", color: color, size: 9).padding(.top, 4)
                            Text(downLine).font(.s13m).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        if let good = model.lastGood[server.id] {
                            Text("Last good check: \(Self.clock(good)).").font(.s13).foregroundStyle(Color.muted).padding(.leading, 17)
                        }
                    }
                    .padding(12)
                } else if let d = server.detail {
                    HStack(alignment: .top, spacing: 8) {
                        PixelIcon("warn", color: color, size: 9).padding(.top, 4)
                        Text(d).font(.s13m).foregroundStyle(color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(12)
                }
                if let (ops, d) = q {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            QuestMarker(size: 22)
                            Text(d.title).font(.s15b).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        Text(Self.gist(d) + "Asked on the DevOps agent's last round, \(d.asked?.ago ?? "just now").")
                            .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        AnswerForm(project: ops, decision: d, yesTitle: Self.yesTitle(d), noTitle: "No", withNote: false,
                                   onSent: { yes in savedWhileOff = yes && !model.projectSettings.devops.enabled })
                        Button { model.controller.select(decision: d.id, in: ops.id) } label: { Text("Why and evidence") }
                            .buttonStyle(SpelButtonStyle(kind: .ghost, size: .s))
                    }
                    .padding(12)
                } else if savedWhileOff {
                    RowDivider()
                    HStack(spacing: 8) {
                        PixelIcon("check", color: .done, size: 9)
                        Text("Saved. It runs when the DevOps agent is on.").font(.s13m).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.divider, lineWidth: 2))
            .overlay { HStack(spacing: 0) { Rectangle().fill(q != nil ? Color.signal : color).frame(width: 6); Spacer(minLength: 0) }.clipShape(RoundedRectangle(cornerRadius: 10)).allowsHitTesting(false) }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.plinth).offset(y: 2))
        }
    }

    /// "Can't reach nightly since 14:02 (timed out)." from the check's own words; without a time, what there is
    private var downLine: String {
        let why = server.detail.map { $0.hasPrefix("no connection: ") ? String($0.dropFirst(15)) : $0 }
        // "since" only when the app saw it go: down from its first check, it would only be when the app started
        let since = model.lastGood[server.id] == nil ? "" : model.downSince[server.id].map { " since " + Self.clock($0) } ?? ""
        return "Can't reach \(server.name)\(since)" + (why.map { " (\($0))" } ?? "") + "."
    }
    /// "14:02" today, "Tue 14:02" before
    static func clock(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "Yes, prune" from "Prune Docker images…?"
    static func yesTitle(_ d: FactoryDecision) -> String {
        let first = d.title.split(separator: " ").first.map(String.init) ?? ""
        return first.count > 2 && first.count < 12 && first.first?.isUppercase == true ? "Yes, \(first.lowercased())" : "Yes"
    }
    /// the first sentence of its why
    static func gist(_ d: FactoryDecision) -> String {
        let why = d.why.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard let end = why.firstIndex(of: ".") else { return why.isEmpty ? "" : why + ". " }
        return String(why[...end]) + " "
    }

    private func gauges(_ m: ServerMetrics) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let share = m.loadShare, let load = m.load {
                Meter(label: "Load", value: String(format: "%.2f", load), fraction: min(share / 2, 1), warnAt: ServerProbe.loadWarn / 2)
                    .help(m.cores.map { "On \($0) cores" } ?? "")
            }
            if let mem = m.memory {
                Meter(label: "Memory", value: "\(mem)%", fraction: Double(mem) / 100, warnAt: 1 - ServerProbe.memoryFreeWarn)
                    .help(ServerMetrics.size(m.memoryUsedBytes, of: m.memoryTotalBytes) ?? "")
            }
            if let d = m.disk, server.state == .ok, model.world.ops.flatMap({ AppModel.question(about: server.name, in: $0) }) == nil {
                Meter(label: "Disk", value: "\(d)%", fraction: Double(d) / 100, warnAt: Double(ServerProbe.diskWarn) / 100)
            }
        }
        .spelCard()
    }

    private func sites(_ c: ServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Sites")
            ForEach(c.siteURLs, id: \.self) { u in
                let r = model.siteChecks[u]
                HStack(spacing: 8) {
                    StateLight(state: r.map { $0.state == .down ? .down : $0.state == .warn ? .warn : .ok } ?? .unknown)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(URL(string: u)?.host ?? u).font(.mono).foregroundStyle(Color.inkText).lineLimit(1).textSelection(.enabled)
                        Text(r?.detail ?? "not checked yet").font(.s12).foregroundStyle(r?.state == .ok || r == nil ? Color.muted : r?.state == .down ? Color.stuck : Color.warn).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .spelCard()
    }

    @ViewBuilder private func devops(_ c: ServerConfig) -> some View {
        if server.state == .down {
            // it works over the same connection that is gone: offering it here would promise what it cannot do
            HStack(spacing: 10) {
                PixelIcon("hand", color: .muted)
                Text("The DevOps agent can't fix a server it can't reach.").font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .spelCard()
        } else if !model.projectSettings.devops.enabled {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DevOps agent is off").font(.s15b).foregroundStyle(Color.inkText)
                    Text("Switch it on and it handles fixes like this one itself.").font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Button { model.updateDevOps { $0.enabled = true } } label: { SpelLabel("Switch on", icon: "power", iconColor: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
            }
            .spelCard()
        } else {
            let alerts = EngineRoom.openAlerts().filter { $0.title.hasPrefix(c.name + " ") }
            let done = EngineRoom.recentActions(server: c.name, limit: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PixelIcon("hand", color: .inkText)
                    Text("DevOps agent").font(.s15b).foregroundStyle(Color.inkText)
                    Spacer(minLength: 0)
                    Text(c.opsAutonomy.label).font(.s13).foregroundStyle(Color.muted)
                }
                Text(c.opsAutonomy.explanation).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(alerts, id: \.id) { a in
                    HStack(spacing: 6) { PixelIcon("warn", color: .warn, size: 9); Text("\(a.id) \(a.title)").font(.s13m).foregroundStyle(Color.warn).lineLimit(1) }
                }
                ForEach(Array(done.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.mono12).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
            .spelCard()
        }
    }

    private func actions(_ config: ServerConfig?) -> some View {
        // down: checking again is what you do first (the one primary action here), then a terminal of your own
        let down = server.state == .down
        return HStack(spacing: 8) {
            Button { model.checkServers() } label: {
                SpelLabel(model.checkingServers ? "Checking" : down ? "Check again" : "Check", icon: "refresh", onYellow: down, iconColor: down ? .onSignal : .inkText)
            }
                .buttonStyle(SpelButtonStyle(kind: down ? .primary : .secondary, size: .s, wide: !down))
                .disabled(model.checkingServers)
                .help(model.fixture ? "Demo data: the check only pretends" : "Check every server now")
            if let c = config {
                Button { model.openSSH(c) } label: { SpelLabel(down ? "Open a terminal" : "Terminal", icon: "terminal", iconColor: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, wide: !down))
                    .help("ssh \(c.host) in the terminal (⌘J)")
                // down, the two longer labels need the room: Settings keeps its icon
                if down { Spacer(minLength: 0) }
                Button { model.settingsPage = "server:\(c.id)"; model.settingsOpen = true } label: {
                    if down { PixelIcon("gear", color: .inkText) } else { SpelLabel("Settings", icon: "gear", iconColor: .inkText) }
                }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: down, wide: !down))
                    .help("How this server is reached, and what it may fix itself").accessibilityLabel("Server settings")
            }
        }
    }
}

/// The last two hours of disk, memory and load as three thin lines.
private struct HistoryCard: View {
    let samples: [AppModel.ServerSample]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHead("Last 2 hours") { Text("\(samples.count) checks").font(.s12).foregroundStyle(Color.muted) }
            line("Disk", samples.map { $0.metrics.disk.map { Double($0) / 100 } })
            line("Memory", samples.map { $0.metrics.memory.map { Double($0) / 100 } })
            line("Load", samples.map { $0.metrics.loadShare.map { min($0 / 2, 1) } })
        }
        .spelCard()
    }
    private func line(_ label: String, _ values: [Double?]) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.s12).foregroundStyle(Color.muted).frame(width: 52, alignment: .leading)
            Sparkline(values: values).frame(height: 22)
        }
    }
}

private struct Sparkline: View {
    let values: [Double?]
    var body: some View {
        GeometryReader { g in
            // each line on its own scale (at least 10 points of range), so a trend shows
            let known = values.compactMap { $0 }
            let lo = known.min() ?? 0, hi = known.max() ?? 1, span = max(hi - lo, 0.1), mid = (hi + lo) / 2
            let base = max(0, min(mid - span / 2, 1 - span))
            let pts = values.enumerated().compactMap { k, v in v.map { CGPoint(x: g.size.width * CGFloat(k) / CGFloat(max(values.count - 1, 1)), y: g.size.height * (1 - CGFloat(($0 - base) / span)) * 0.9 + g.size.height * 0.05) } }
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: g.size.height)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height)) }
                    .stroke(Color.divider, lineWidth: 2)
                Path { p in guard let f = pts.first else { return }; p.move(to: f); for q in pts.dropFirst() { p.addLine(to: q) } }
                    .stroke(Color.inkText.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let l = pts.last { Rectangle().fill(Color.inkText).frame(width: 4, height: 4).position(l) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A server's right-click menu, in the inspector and in the racks list: its host, and its settings.
struct ServerMenu: View {
    @EnvironmentObject private var model: AppModel
    let server: Server
    let host: String?
    var body: some View {
        if let host { Button("Copy Host") { AppModel.copy(host) } }
        Button("Server Settings") { model.settingsPage = "server:" + server.id; model.settingsOpen = true }
    }
}
