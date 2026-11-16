import SwiftUI
import AppKit
import FactoryCore
import FactoryCollector

/// One server in the inspector (D52), opened by clicking its rack (its slot slides out), its row, or its body in Orbit:
/// how it is, its gauges and last two hours, the sites it serves, and what the DevOps agent may do and did there.
struct ServerDetail: View {
    @EnvironmentObject private var model: AppModel
    let server: Server

    var body: some View {
        let config = model.serverConfigs.first { $0.id == server.id }
        VStack(alignment: .leading, spacing: 12) {
            hero(config)
            if let m = server.metrics { gauges(m) }
            let history = model.serverHistory[server.id] ?? []
            if history.count > 2 { HistoryCard(samples: history) }
            if let c = config, !c.siteURLs.isEmpty { sites(c) }
            if let c = config { devops(c) }
            actions(config)
        }
    }

    private var color: Color { server.state == .down ? .stuck : server.state == .warn ? .warn : .done }

    private func hero(_ config: ServerConfig?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 44, height: 44)
                Circle().fill(color).frame(width: 16, height: 16).shadow(color: color.opacity(0.8), radius: 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(server.state == .ok ? "Running fine" : server.state == .warn ? "Needs a look" : "Down")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(server.state == .ok ? Color.inkText : color)
                if let d = server.detail { Text(d).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.muted).lineLimit(2) }
                if let h = config?.host { Text(h).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle) }
                if let at = server.checkedAt { Text("checked \(at.ago)").font(.system(size: 11)).foregroundStyle(Color.muted) }
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(server.state == .ok ? Color.divider : color.opacity(0.5)))
    }

    private func gauges(_ m: ServerMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Now")
            if let share = m.loadShare, let load = m.load {
                Gauge(label: "Load", value: String(format: "%.2f", load) + (m.cores.map { " on \($0) cores" } ?? ""),
                      fraction: min(share / 2, 1), warnAt: ServerProbe.loadWarn / 2)
            }
            if let d = m.disk {
                Gauge(label: "Disk", value: [ServerMetrics.size(m.diskUsedBytes, of: m.diskTotalBytes), "\(d)%"].compactMap { $0 }.joined(separator: " · "),
                      fraction: Double(d) / 100, warnAt: Double(ServerProbe.diskWarn) / 100)
            }
            if let mem = m.memory {
                Gauge(label: "Memory", value: [ServerMetrics.size(m.memoryUsedBytes, of: m.memoryTotalBytes), "\(mem)%"].compactMap { $0 }.joined(separator: " · "),
                      fraction: Double(mem) / 100, warnAt: 1 - ServerProbe.memoryFreeWarn)
            }
        }
        .padding(12).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sites(_ c: ServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Sites")
            ForEach(c.siteURLs, id: \.self) { u in
                let r = model.siteChecks[u]
                let col: Color = r.map { $0.state == .down ? .stuck : $0.state == .warn ? .warn : .done } ?? .muted
                HStack(spacing: 8) {
                    Circle().fill(col).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(URL(string: u)?.host ?? u).font(.system(size: 12, weight: .semibold, design: .monospaced)).lineLimit(1)
                        Text(r?.detail ?? "not checked yet").font(.system(size: 11, design: .monospaced)).foregroundStyle(r?.state == .ok || r == nil ? Color.muted : col).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func devops(_ c: ServerConfig) -> some View {
        let alerts = EngineRoom.openAlerts().filter { $0.title.hasPrefix(c.name + " ") }
        let done = EngineRoom.recentActions(server: c.name, limit: 4)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Eyebrow("DevOps agent")
                Spacer()
                Text(model.projectSettings.devops.enabled ? c.opsAutonomy.label : "off").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.muted)
            }
            Text(model.projectSettings.devops.enabled ? c.opsAutonomy.explanation : "Switch the DevOps agent on in Settings › Server room.")
                .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(alerts, id: \.id) { a in
                Label("\(a.id) \(a.title)", systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.warn).lineLimit(1)
            }
            ForEach(Array(done.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func actions(_ config: ServerConfig?) -> some View {
        HStack(spacing: 8) {
            Button { model.checkServers() } label: { Label(model.checkingServers ? "Checking" : "Check now", systemImage: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize() }
                .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)))
                .disabled(model.checkingServers || model.fixture)
            if let c = config {
                Button { model.openSSH(c) } label: { Label("Terminal", systemImage: "terminal").font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize() }
                    .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)))
                    .help("ssh \(c.host) in the terminal (⌘J)")
                Button { model.settingsPage = "server:\(c.id)"; model.settingsOpen = true } label: { Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 22) }
                    .buttonStyle(TactileButtonStyle(kind: .neutral)).help("This server's settings")
            }
            Spacer(minLength: 0)
        }
    }
}

/// A labelled bar: the value, how full, and a tick where a warning starts. Amber past the tick.
private struct Gauge: View {
    let label: String, value: String
    let fraction: Double, warnAt: Double
    var body: some View {
        let over = fraction >= warnAt
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(over ? Color.warn : Color.inkText)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.surface)
                    RoundedRectangle(cornerRadius: 3).fill(over ? Color.warn : Color.done.opacity(0.85))
                        .frame(width: max(3, g.size.width * min(max(fraction, 0), 1)))
                    Rectangle().fill(Color.border).frame(width: 1.5, height: 12).offset(x: g.size.width * warnAt - 0.75)
                }
            }
            .frame(height: 8)
        }
    }
}

/// The last two hours of disk, memory and load as three thin lines.
private struct HistoryCard: View {
    let samples: [AppModel.ServerSample]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Eyebrow("Last 2 hours"); Spacer(); Text("\(samples.count) checks").font(.system(size: 11)).foregroundStyle(Color.muted) }
            line("Disk", samples.map { $0.metrics.disk.map { Double($0) / 100 } })
            line("Memory", samples.map { $0.metrics.memory.map { Double($0) / 100 } })
            line("Load", samples.map { $0.metrics.loadShare.map { min($0 / 2, 1) } })
        }
        .padding(12).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }
    private func line(_ label: String, _ values: [Double?]) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted).frame(width: 52, alignment: .leading)
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
                    .stroke(Color.divider, lineWidth: 1)
                Path { p in guard let f = pts.first else { return }; p.move(to: f); for q in pts.dropFirst() { p.addLine(to: q) } }
                    .stroke(Color.inkText.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let l = pts.last { Circle().fill(Color.inkText).frame(width: 4, height: 4).position(l) }
            }
        }
    }
}

private struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted) }
}
