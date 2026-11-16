import SwiftUI
import AppKit
import FactoryCore
import FactoryCollector

// A Dark Software Factory in the HUD: its overview at the Project level (briefing first, then the open questions,
// autonomy and the workstreams) and a question as a decision card you answer with yes or no (D11, D25).

/// Switches a project on or off as a Dark Software Factory (D44), at the top of its inspector, with the pin that keeps
/// its floor on the campus without recent sessions (D46).
struct FactorySwitch: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    var body: some View {
        let on = model.isFactory(project), pinned = model.isPinned(project)
        HStack(spacing: 8) {
            if !on {
            Button { model.setPinned(project.root, on: !pinned) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 36)
            }
            .buttonStyle(TactileButtonStyle(kind: .neutral))
            .help(on ? "A factory always stays on the campus" : pinned ? "On campus: this floor stays. Click to let it go when quiet." : "Keep this floor on the campus without recent sessions")
            .accessibilityLabel(pinned ? "Kept on campus" : "Keep on campus")
            }
            switchCard(on)
        }
    }

    private func switchCard(_ on: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Factory").font(.system(size: 12.5, weight: .bold))
                if !on { Text("Off: a project like any other. On: an AI CEO runs it").font(.system(size: 11)).foregroundStyle(Color.muted) }
            }
            Spacer(minLength: 0)
            Toggle("Factory", isOn: Binding(get: { on }, set: { model.setFactory(project.root, on: $0) }))
                .labelsHidden().toggleStyle(TactileToggleStyle())
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background((on ? Color.raised : Color.surface), in: RoundedRectangle(cornerRadius: 10))
        .help("Switch this project on as a factory: an AI CEO works on it on a schedule. Nothing is written until you set it up and approve each file.")
    }
}

/// The CEO's heartbeat on a factory's overview (D47): its rhythm, the last run and how it ended, what wakes it next,
/// Run now and the log.
struct HeartbeatCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let state: HeartbeatState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 12, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating, isActive: state.running)
                Text("CEO heartbeat").font(.system(size: 12.5, weight: .bold)).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                if model.heartbeatLog(project) != nil {
                    // follow the run in the terminal (D57); while it runs you can also take it over
                    Button { model.watchRun(root: project.root, name: project.name) } label: {
                        Image(systemName: state.running ? "eye" : "doc.text").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 24)
                    }.buttonStyle(TactileButtonStyle(kind: .neutral)).help(state.running ? "Watch the run in the terminal" : "The last run's log, in the terminal")
                }
                if state.running, let ceo = project.sessions.first(where: { $0.heartbeatRun == true }) {
                    Button { model.takeOver(ceo) } label: {
                        Label("Take over", systemImage: "terminal").font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                    .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)))
                    .help("Stop this run and continue it yourself in the terminal")
                }
                Button { model.runNow(project) } label: {
                    Label(state.running ? "Running" : "Run now", systemImage: state.running ? "hourglass" : "play.fill")
                        .font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize()
                }
                .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)))
                .disabled(state.running).help("Wake the CEO now, also when the heartbeat is paused")
            }
            VStack(alignment: .leading, spacing: 3) {
                line("Beat", state.config.summary + " · " + state.config.runtime.label + " · \(state.runsToday)/\(state.config.runsPerDay) today", tone: nil)
                if let last = state.last { line("Last", lastText(last), tone: last.outcome) }
                else { line("Last", "No run yet", tone: nil) }
                if let p = state.pending, !state.running {
                    HStack(spacing: 0) {
                        Text("Next  ").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.muted)
                        Text(p.reason.label + ", ").font(.system(size: 11.5))
                        Text(p.at, style: .relative).font(.system(size: 11.5).monospacedDigit())
                        Text(" from now").font(.system(size: 11.5))
                    }
                } else if let n = state.next {
                    line("Next", "Heartbeat " + Self.when(n), tone: nil)
                } else {
                    line("Next", "Only Run now: the heartbeat is paused", tone: nil)
                }
            }
            // a warning that is fixed meanwhile (the allowlist is there now) is not shown again
            if let w = state.last?.warning, state.last?.outcome != .running, !(w.hasPrefix("No allowlist") && model.allowlist(project.root).exists) {
                Label(w, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true)
            }
            // what to do about the last run, in one button; or that nothing needs doing
            if let last = state.last, last.outcome != .running {
                if last.outcome == .failed, last.detail?.contains("was closed") == true, !model.projectSettings.heartbeatWhenClosed {
                    fix("Meatproxy was closed, so the run stopped. With Heartbeat when closed it carries on.", "Turn it on") { model.setHeartbeatWhenClosed(true) }
                } else if case .caughtUp = last.reason, last.outcome == .ok {
                    Label("A beat missed while Meatproxy was closed, caught up. Normal: nothing to do.", systemImage: "checkmark.circle")
                        .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let b = state.blocked { blocked(b) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    /// A problem with its fix: one line and one button.
    private func fix(_ text: String, _ button: String, _ action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: action) { Text(button).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize() }
                .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.warn.opacity(0.6)))
    }

    /// A guard holds the heartbeat (D48): said in words, amber; a hold that waits for you has Resume.
    private func blocked(_ b: Block) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: b.waitsForYou ? "hand.raised.fill" : "pause.circle.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(b.waitsForYou ? Color.warn : Color.muted)
            Text(b.text).font(.system(size: 11.5, weight: b.waitsForYou ? .semibold : .regular)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if b.waitsForYou {
                Button { model.resume(project) } label: { Text("Resume").font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize() }
                    .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)))
                    .help("Lift the hold and wake the CEO now")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(b.waitsForYou ? Color.warn.opacity(0.7) : Color.divider))
    }

    private func lastText(_ r: HeartbeatRun) -> String {
        outcomeText(r) + (r.model.map { " · \($0)" } ?? "")
    }
    private func outcomeText(_ r: HeartbeatRun) -> String {
        switch r.outcome {
        case .running: "\(r.reason.label), running since \(Self.clock(r.started))"
        case .ok: "\(r.reason.label), \(r.started.ago), done"
        case .failed: "\(r.reason.label), \(r.started.ago), failed (\(r.detail ?? "error"))"
        case .timedOut: "\(r.reason.label), \(r.started.ago), \(r.detail ?? "timed out")"
        case .takenOver: "\(r.reason.label), \(r.started.ago), taken over by you"
        }
    }

    private func line(_ label: String, _ text: String, tone: HeartbeatRun.Outcome?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label + "  ").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.muted)
            if tone == .failed || tone == .timedOut {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Color.warn).padding(.trailing, 4)
            }
            Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func clock(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }
    /// "today 13:00", "tomorrow 07:10", "Mon 07:10"
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today " + clock(d) }
        if cal.isDateInTomorrow(d) { return "tomorrow " + clock(d) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE HH:mm"
        return f.string(from: d)
    }
}

/// The factory at the top of its project's inspector.
struct FactoryOverview: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let factory: Factory
    private var tab: Tab { model.factoryTabs[project.id] ?? .overview }

    /// What you act on stays on top (a pause, the open questions); the rest is behind four tabs, so the panel never
    /// becomes one long stack (D44).
    enum Tab: String, Hashable { case overview, work, ceo }

    var body: some View {
        if !model.isSetUp(project.root) { SetUpFactoryCard(project: project) }
        else { overview }
    }

    @ViewBuilder private var overview: some View {
        if model.justSetUp == project.root { FirstBeatCard(project: project) }
        if factory.paused {
            Label("Paused: STOP is on line 1 of autonomy.yml. It starts and ships nothing.", systemImage: "pause.circle.fill")
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.stuck).fixedSize(horizontal: false, vertical: true)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.stuck.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.stuck.opacity(0.45)))
        }
        let open = factory.openDecisions
        if !open.isEmpty {
            Heading(text: "NEEDS YOU · \(open.count)")
            ForEach(open) { d in
                Button { model.controller.select(decision: d.id, in: project.id) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("?").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(Color.onSignal)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.signal, in: RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).font(.system(size: 13, weight: .bold)).multilineTextAlignment(.leading).lineLimit(3)
                            Text("\(d.kind) · asked \(d.asked?.ago ?? "")").font(.system(size: 11.5)).foregroundStyle(Color.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(9).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.signal)).contentShape(Rectangle())
                }.buttonStyle(CardPressStyle())
            }
        }
        LiftedSegments(items: tabs, selected: tab, fontSize: 12, padding: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)) { model.factoryTabs[project.id] = $0 }
            .padding(.top, 4)
        switch tab {
        case .overview: briefing; ideas
        case .work: work
        case .ceo: ceo
        }
        if !factory.problems.isEmpty {
            Text("Could not read \(factory.problems.joined(separator: ", "))").font(.system(size: 11.5)).foregroundStyle(Color.stuck)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tabs: [LiftedSegments<Tab>.Item] {
        let hb = model.heartbeat(project)
        let newIdeas = factory.ideas.filter { $0.status == .new }.count
        let ceoFlag = hb?.running == true ? " ●" : (hb?.blocked?.waitsForYou == true || hb?.last?.warning != nil || hb?.last?.outcome == .failed) ? " ▲" : ""
        return [
            .init(id: .overview, title: newIdeas > 0 ? "Overview · \(newIdeas)" : "Overview", help: "The CEO's briefing and your ideas"),
            .init(id: .work, title: "Work · \(factory.activeWorkstreams.count + project.sessions.count)", help: "Workstreams and sessions"),
            .init(id: .ceo, title: "CEO" + ceoFlag, help: hb?.running == true ? "The CEO is running" : "Heartbeat, autonomy and contract"),
        ]
    }

    @ViewBuilder private var briefing: some View {
        if factory.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No briefing yet").font(.system(size: 13.5, weight: .bold))
                Text("The CEO writes one at the end of every run: what it did, what needs you, what it delivered. Run now starts the first one.")
                    .font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        } else if let b = factory.briefing { BriefingCard(briefing: b) }
        else { Text("No briefing yet: the CEO writes one every run.").font(.system(size: 12.5)).foregroundStyle(Color.muted) }
    }

    @ViewBuilder private var work: some View {
        let streams = factory.activeWorkstreams
        if !streams.isEmpty {
            Heading(text: "WORKSTREAMS · \(streams.count)")
            ForEach(streams) { w in
                Button { model.controller.select(workstream: w.id, in: project.id) } label: { WorkstreamRow(workstream: w).contentShape(Rectangle()) }.buttonStyle(CardPressStyle())
            }
        }
        let dropped = factory.workstreams.count - streams.count
        if dropped > 0 { Text("\(dropped) dropped").font(.system(size: 11.5)).foregroundStyle(Color.muted) }
        Heading(text: "SESSIONS · \(project.sessions.count)")
        if project.sessions.isEmpty { Text("No session in the last 8 hours.").font(.system(size: 12)).foregroundStyle(Color.muted) }
        else { StateBar(sessions: project.sessions, now: model.world.now) }
        ForEach(project.sessions) { session in
            Button { model.controller.select(session: session.id) } label: { SessionCard(session: session, expanded: false) }.buttonStyle(CardPressStyle())
        }
    }

    @ViewBuilder private var ideas: some View {
        if factory.takesIdeas { IdeaBox(project: project, ideas: factory.ideas) }
        else {
            Text("Ideas need factory contract version \(FactoryContract.ideas): its CEO declares it in factory/contract.yml (docs/contracts/factory.md).")
                .font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var ceo: some View {
        if let hb = model.heartbeat(project) { HeartbeatCard(project: project, state: hb) }
        PermissionsCard(project: project)
        if factory.takesSources, factory.sources.hasSentry || factory.sources.tracker != nil, let e = model.projectSettings.entry(project.root) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WAKE-UP SOURCES").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted).padding(.horizontal, 14)
                if factory.sources.hasSentry, e.heartbeat.wakeOnSentry {
                    SourceHealthLine(health: model.sourceHealth[project.root]?.sentry, missing: nil, label: "Sentry")
                }
                if factory.sources.tracker != nil, e.heartbeat.wakeOnTracker {
                    SourceHealthLine(health: model.sourceHealth[project.root]?.tracker, missing: nil, label: "Tracker")
                }
            }.padding(.horizontal, -14)
        }
        if factory.takesMandate {
            AutonomyCard(mandate: model.mandate(project.root), autonomy: factory.autonomy) {
                model.settingsPage = "project:\(project.root)"; model.settingsOpen = true
            }
        } else if let a = factory.autonomy { AutonomyLine(autonomy: a) }
        HStack(spacing: 6) {
            Text("CONTRACT").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
            Text("Version \(factory.contractVersion)\(factory.contract == nil ? " (no contract.yml)" : "")").font(.system(size: 12))
            if factory.newerContract {
                Text("newer than this Meatproxy (v\(FactoryContract.current))").font(.system(size: 11.5)).foregroundStyle(Color.warn)
            }
        }
        Text(project.root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
    }
}

private struct Heading: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted).padding(.top, 4)
    }
}

/// The CEO's latest briefing: a few lines, and what was delivered.
private struct BriefingCard: View {
    let briefing: Briefing
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CEO BRIEFING").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                Spacer()
                Text(Self.day(briefing.name)).font(.system(size: 11.5)).foregroundStyle(Color.muted)
            }
            ForEach(Array(briefing.briefing.enumerated()), id: \.offset) { _, line in
                Text(Self.plain(line)).font(.system(size: 12.5)).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
            }
            if !briefing.delivered.isEmpty && !(briefing.delivered.count == 1 && briefing.delivered[0].lowercased().hasPrefix("nothing")) {
                ForEach(Array(briefing.delivered.enumerated()), id: \.offset) { _, line in
                    Label { Text(Self.plain(line)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "shippingbox.fill").foregroundStyle(Color.done) }
                        .font(.system(size: 12)).foregroundStyle(Color.inkText)
                }
            }
        }
        .padding(10).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.divider))
    }

    /// "2026-11-16" → "Mon 16 Nov", "2026-11-16-2" → "Mon 16 Nov · 2nd run"
    static func day(_ name: String) -> String {
        let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"; p.locale = Locale(identifier: "en_US_POSIX")
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.locale = Locale(identifier: "en_GB")
        let base = p.date(from: String(name.prefix(10))).map(f.string) ?? name
        return name.count > 11 ? "\(base) · run \(name.dropFirst(11))" : base
    }

    /// Markdown emphasis and links read as plain words.
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`]+"#, with: "", options: .regularExpression)
    }
}

/// What the CEO may do (D59): one card. Your mandate is what counts: its level and role on top, and per item your
/// setting. The CEO's own record (autonomy.yml) only adds its yeses in a row on a gate, as dots beside the item: at
/// five it may propose to stop asking. Edit opens the mandate in Settings.
struct AutonomyCard: View {
    let mandate: FactoryMandate
    let autonomy: Autonomy?
    let edit: () -> Void

    static func short(_ i: FactoryMandate.Item) -> String {
        switch i {
        case .propose: "Its own ideas"
        case .bugs: "Sentry and CI bugs"
        case .dependencies: "Dependency updates"
        case .prs: "Merge its own PRs"
        case .ship: "Ship to production"
        case .store: "Store releases"
        case .spend: "Spend money"
        case .promote: "Change its own gates"
        }
    }

    static func modeLabel(_ m: FactoryMandate.Mode) -> String {
        switch m { case .ask: "Ask"; case .notify: "Tell me"; case .off: "Off" }
    }

    /// the CEO's gate for a mandate item, when it keeps one (its gate names match the items)
    func gate(_ i: FactoryMandate.Item) -> Autonomy.Gate? { autonomy?.gates.first { $0.name.lowercased() == i.rawValue } }

    /// the CEO's gates that have no mandate item (they cannot override it; shown so nothing is hidden)
    var looseGates: [Autonomy.Gate] {
        (autonomy?.gates ?? []).filter { g in !FactoryMandate.Item.allCases.contains { $0.rawValue == g.name.lowercased() } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("AUTONOMY").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                        if autonomy?.paused == true {
                            Text("STOPPED").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Color.stuck)
                                .help("STOP is on line 1 of the CEO's autonomy.yml: it starts and ships nothing")
                        }
                    }
                    Text(mandate.level.rawValue.capitalized).font(.system(size: 16, weight: .bold))
                    Text(mandate.level.sentence).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text(mandate.summary.components(separatedBy: " · ").filter { $0 != mandate.level.rawValue.capitalized }.joined(separator: " · "))
                        .font(.system(size: 11.5)).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                Button(action: edit) {
                    HStack(spacing: 4) { Text("Edit"); Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)) }
                        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 26)
                }.buttonStyle(TactileButtonStyle(kind: .neutral)).help("Change the mandate in Settings › Projects")
            }
            .padding(.bottom, 8)
            ForEach(FactoryMandate.Item.allCases, id: \.self) { item in
                Divider().overlay(Color.divider)
                row(item)
            }
            ForEach(looseGates, id: \.name) { g in
                Divider().overlay(Color.divider)
                HStack(spacing: 8) {
                    Text("\(g.name.prefix(1).uppercased() + g.name.dropFirst()) · its own gate").font(.system(size: 12)).foregroundStyle(Color.muted)
                    Spacer(minLength: 0)
                    Text(g.notify ? "Tell me" : "Ask").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.muted)
                }.padding(.vertical, 6)
                .help("A gate in the CEO's autonomy.yml with no mandate item: it does not change what the mandate allows")
            }
            if FactoryMandate.Item.allCases.contains(where: { gate($0) != nil }) {
                Text("Dots: your yeses in a row on that step. At \(Autonomy.promoteAfter) the CEO may propose to stop asking; your setting still decides.")
                    .font(.system(size: 11)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 7)
            }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ item: FactoryMandate.Item) -> some View {
        let mode = mandate.mode(item), g = gate(item), strong = mode != .notify
        return HStack(spacing: 8) {
            Text(Self.short(item)).font(.system(size: 12.5)).foregroundStyle(mode == .off ? Color.muted : Color.inkText)
            Spacer(minLength: 0)
            if let g, mode == .ask { StreakDots(count: min(g.streak, Autonomy.promoteAfter), of: Autonomy.promoteAfter) }
            Text(Self.modeLabel(mode)).font(.system(size: 11.5, weight: strong ? .semibold : .regular))
                .foregroundStyle(mode == .ask ? Color.inkText : Color.muted)
                .frame(width: 62).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(mode == .ask ? Color.border : Color.divider))
        }
        .padding(.vertical, 6)
        .help(FactoryMandate.meaning(item))
    }
}

/// Yeses in a row as dots: filled up to the count, open after it.
private struct StreakDots: View {
    let count: Int, of: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<of, id: \.self) { k in
                Circle().fill(k < count ? Color.inkText : Color.clear).frame(width: 5, height: 5)
                    .overlay(Circle().stroke(k < count ? Color.clear : Color.border, lineWidth: 1))
            }
        }
        .accessibilityElement().accessibilityLabel("\(count) of \(of) yes in a row")
        .help("\(count) of \(of) yes in a row on this step")
    }
}

/// How dark the floor is, for a factory before contract v3 (no mandate): the level, each gate ask or notify with its
/// streak, and STOP.
private struct AutonomyLine: View {
    let autonomy: Autonomy
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("AUTONOMY").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                Text(autonomy.level.rawValue.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(Color.inkText)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.raised, in: RoundedRectangle(cornerRadius: 6))
                if autonomy.paused { Text("PAUSED").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Color.stuck) }
            }
            HStack(spacing: 6) {
                ForEach(autonomy.gates, id: \.name) { g in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.name).font(.system(size: 11.5, weight: .bold))
                        Text(g.notify ? "notify" : "ask · \(min(g.streak, Autonomy.promoteAfter))/\(Autonomy.promoteAfter)")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(g.notify ? Color.inkText : Color.muted)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                    .background((g.notify ? Color.raised : Color.surface), in: RoundedRectangle(cornerRadius: 6))
                    .help(g.notify ? "\(g.name): the factory does it and tells you" : "\(g.name): the factory asks you first; \(g.streak) yes in a row")
                }
            }
        }
    }
}

/// One workstream in full: its track, the questions about it, its PR, branch and release, and the log with the steps back.
struct WorkstreamCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let workstream: Workstream
    var body: some View {
        let w = workstream
        WorkstreamRow(workstream: w)
        HStack(spacing: 6) {
            Chip(text: w.type, strong: true)
            if let s = w.source { Chip(text: "from \(s)") }
            if let r = w.release { Chip(text: "release \(r)") }
            Spacer(minLength: 0)
        }
        if let pr = w.pr, let url = URL(string: pr) {
            Button { NSWorkspace.shared.open(url) } label: {
                Label(FactoryText.links(pr).first?.title ?? pr, systemImage: "arrow.up.right").font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.inkText).lineLimit(1)
            }.buttonStyle(.plain).help(pr)
        }
        if let b = w.branch { Text(b).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.muted).lineLimit(1) }
        let questions = (project.factory?.decisions ?? []).filter { $0.workstream == w.id || w.decisions.contains($0.id) }
        if !questions.isEmpty {
            Part(title: "QUESTIONS") {
                ForEach(questions) { d in
                    Button { model.controller.select(decision: d.id, in: project.id) } label: {
                        HStack(spacing: 6) {
                            Text(d.status == .open ? "?" : d.status.rawValue).font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(d.status == .open ? Color.onSignal : d.status == .yes ? Color.done : Color.muted)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(d.status == .open ? Color.signal : Color.raised, in: RoundedRectangle(cornerRadius: 4))
                            Text(d.title).font(.system(size: 12)).foregroundStyle(Color.inkText).lineLimit(1)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(CardPressStyle())
                }
            }
        }
        if !w.log.isEmpty {
            Part(title: "LOG") {
                ForEach(Array(w.log.reversed().prefix(8).enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(e.date.suffix(5))).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.muted)
                        Text(e.isBack ? "↩ \(e.from?.rawValue ?? "") → \(e.phase?.rawValue ?? "")" : e.phase?.rawValue ?? "")
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(e.isBack ? Color.inkText : Color.muted)
                        Text(e.text).font(.system(size: 11.5)).foregroundStyle(Color.inkText).lineLimit(2)
                    }
                }
            }
        }
    }
}

/// A workstream: its id and title, and the PLAN … DONE track with where it is, how far it got, and a ↩ when it went back.
private struct WorkstreamRow: View {
    let workstream: Workstream
    var body: some View {
        let w = workstream
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(w.id).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(Color.muted)
                Text(w.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if w.wentBack { Text("↩").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.inkText).help(w.backSteps.last?.text ?? "") }
            }
            HStack(spacing: 3) {
                ForEach(Array(WorkPhase.allCases.dropLast().enumerated()), id: \.offset) { k, phase in
                    let here = w.phase == phase, past = k < (w.phase.step ?? 0), reachedOnly = !here && !past && k <= w.reached
                    Text(phase.label).font(.system(size: 9.5, weight: here ? .bold : .semibold)).tracking(0.5)
                        .foregroundStyle(here ? Color.ink : past ? Color.inkText : reachedOnly ? Color.muted : Color.muted.opacity(0.45))
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .background(here ? (w.phase == .done ? Color.done : Color.signal) : (past ? Color.divider : Color.raised), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(reachedOnly ? Color.border : .clear, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                }
            }
            if let back = w.backSteps.last, w.wentBack {
                Text("↩ \(back.from?.rawValue ?? "") → \(back.phase?.rawValue ?? ""): \(back.text)").font(.system(size: 11)).foregroundStyle(Color.muted).lineLimit(2)
            }
        }
        .padding(9).background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: the decision card

/// One question: what it asks, why, the evidence, what happens on yes and on no, and your answer with an optional note.
/// Yes or No asks once more ("Send yes"), then writes the file; a question that is no longer open shows its answer.
struct DecisionCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let decision: FactoryDecision
    @State private var note = ""
    @State private var pending: Bool?
    @State private var sending = false
    @State private var failure: String?
    @FocusState private var noteFocused: Bool
    @State private var sendPulse = 0

    var body: some View {
        let d = decision
        HStack(spacing: 6) {
            Chip(text: d.kind, strong: true)
            if let g = d.gate, g != d.kind { Chip(text: "gate \(g)") }
            if let w = d.workstream { Chip(text: w) }
            Spacer(minLength: 0)
            if let a = d.asked { Text("asked \(a.ago)").font(.system(size: 11.5)).foregroundStyle(Color.muted) }
        }
        if let w = d.workstream, let ws = project.factory?.workstreams.first(where: { $0.id == w }) {
            Text("\(ws.title) · \(ws.phase.label)").font(.system(size: 12)).foregroundStyle(Color.muted).lineLimit(1)
        }
        if !d.why.isEmpty { Part(title: "WHY") { Prose(text: d.why) } }
        if !d.evidence.isEmpty { Part(title: "EVIDENCE") { Evidence(text: d.evidence, root: project.factory?.root ?? project.root) } }
        if !d.onYes.isEmpty || !d.onNo.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                if !d.onYes.isEmpty { Part(title: "ON YES") { Prose(text: d.onYes, size: 12) }.frame(maxWidth: .infinity, alignment: .leading) }
                if !d.onNo.isEmpty { Part(title: "ON NO") { Prose(text: d.onNo, size: 12) }.frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        if d.status == .open { answerForm } else { answered(d) }
    }

    @ViewBuilder private var answerForm: some View {
        Text(project.id == World.opsID ? "Note for the DevOps agent" : "Note for the CEO").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.inkText)
        TextField("", text: $note, prompt: Text("Optional. The CEO reads it before proposing anything similar.").foregroundStyle(Color.muted), axis: .vertical)
            .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(2...5).focused($noteFocused)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .lifted(focused: noteFocused)
            .padding(.bottom, 2)
            .onChange(of: noteFocused) { _, on in model.typing = on }
            .onDisappear { model.typing = false }
        if let pending {
            // the confirm step: the send is the one primary action, and its words stay literal in meme mode too
            HStack(spacing: 10) {
                Button { send(pending) } label: {
                    HStack(spacing: 7) {
                        if pending { BrandMark(face: .onSignal, ledge: false).frame(width: 16, height: 16) }
                        Text(sending ? "Sending…" : pending ? "Send yes" : "Send no")
                    }
                    .font(.system(size: 13.5, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(TactileButtonStyle(kind: pending ? .primary : .neutral, pulse: sendPulse)).disabled(sending)
                .background { Button("") { sendPulse += 1; send(pending) }.keyboardShortcut(.return, modifiers: .command).opacity(0).disabled(sending) }
                Button { self.pending = nil } label: {
                    Text("Cancel").font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                }.buttonStyle(TactileButtonStyle(kind: .neutral)).disabled(sending)
            }
            Text(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Writes \(pending ? "yes" : "no") into \(fileName)." : "Writes \(pending ? "yes" : "no") and your note into \(fileName).")
                .font(.system(size: 11)).foregroundStyle(Color.muted).lineLimit(2)
        } else {
            HStack(spacing: 10) {
                Button { pending = true; failure = nil } label: {
                    HStack(spacing: 7) {
                        BrandMark(face: .onSignal, ledge: false).frame(width: 16, height: 16)
                        Text(model.memeMode ? "LGTM" : "Yes")
                    }
                    .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(TactileButtonStyle(kind: .primary))
                Button { pending = false; failure = nil } label: {
                    Text(model.memeMode ? "Not today" : "No").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(TactileButtonStyle(kind: .neutral))
            }
        }
        if let failure { Text(failure).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.stuck).fixedSize(horizontal: false, vertical: true) }
    }

    @ViewBuilder private func answered(_ d: FactoryDecision) -> some View {
        let color: Color = d.status == .yes ? .done : d.status == .no ? .inkText : .muted
        HStack(alignment: .top, spacing: 12) {
        if d.status == .yes || d.status == .no { AnswerStamp(yes: d.status == .yes) }
        VStack(alignment: .leading, spacing: 4) {
            Text("\(d.status.rawValue.capitalized)\(d.answered.map { " · \($0.ago)" } ?? "")").font(.system(size: 14, weight: .bold)).foregroundStyle(color)
            if !d.answer.isEmpty { Text(d.answer).font(.system(size: 12.5)).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true) }
            if d.status == .yes || d.status == .no {
                Text("The CEO acts on it at its next run.").font(.system(size: 11.5)).foregroundStyle(Color.muted)
            }
        }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private var fileName: String { (decision.file as NSString).lastPathComponent }

    private func send(_ yes: Bool) {
        sending = true
        Task {
            let error = await model.answer(decision, in: project, yes: yes, note: note)
            sending = false
            if let error { failure = error; pending = nil } else { pending = nil; note = ""; noteFocused = false }
        }
    }
}

private struct Chip: View {
    let text: String; var strong = false
    var body: some View {
        Text(text).font(.system(size: 11, weight: strong ? .semibold : .medium)).lineLimit(1).fixedSize()
            .foregroundStyle(strong ? Color.inkText : Color.muted).padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke((strong ? Color.border : Color.divider)))
    }
}

private struct Part<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
            content
        }
    }
}

private struct Prose: View {
    let text: String; var size: CGFloat = 13
    var body: some View {
        Text(BriefingCard.plain(text)).font(.system(size: size)).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
    }
}

/// The evidence: its links open in the browser, a path into the factory folder opens in Finder, other lines are text.
private struct Evidence: View {
    let text: String; let root: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let links = FactoryText.links(line)
                if !links.isEmpty {
                    ForEach(links, id: \.url) { l in
                        Button { if let u = URL(string: l.url) { NSWorkspace.shared.open(u) } } label: {
                            Label(l.title, systemImage: "arrow.up.right").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.inkText).lineLimit(1)
                        }.buttonStyle(.plain).help(l.url)
                    }
                } else if let path = Self.path(in: line) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root + "/" + path)]) } label: {
                        Label(BriefingCard.plain(line), systemImage: "folder").font(.system(size: 12)).foregroundStyle(Color.inkText).lineLimit(2)
                    }.buttonStyle(.plain).help(root + "/" + path)
                } else {
                    Text(BriefingCard.plain(line)).font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private var lines: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }
    /// "Screenshots: factory/workstreams/W-002-x/" → "factory/workstreams/W-002-x/"
    static func path(in line: String) -> String? {
        guard let r = line.range(of: #"factory/[^\s`)]+"#, options: .regularExpression) else { return nil }
        let p = String(line[r])
        return p.contains("..") ? nil : p
    }
}

/// Send the CEO an idea (a feature, a wish, a worry): it lands in factory/ideas/ and wakes the CEO a few minutes later.
/// Below it, your recent ideas and what the CEO did with them.
struct IdeaBox: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let ideas: [FactoryIdea]
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IDEAS FOR THE CEO").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
            TextField("", text: $text, prompt: Text("A feature, a wish, a worry. The CEO turns it into a question for you.").foregroundStyle(Color.muted), axis: .vertical)
                .lineLimit(2...6).font(.system(size: 12.5)).textFieldStyle(.plain).focused($focused)
                .padding(8).background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? Color.signal : Color.border))
            HStack {
                if let error { Text(error).font(.system(size: 11.5)).foregroundStyle(Color.warn).lineLimit(2) }
                Spacer(minLength: 0)
                Button { send() } label: {
                    HStack(spacing: 6) {
                        Label(sending ? "Sending" : "Send idea", systemImage: "paperplane.fill").font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                        KeyCap("⌘↩")
                    }
                }
                .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)))
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command).help("Send to the CEO (⌘↩)")
            }
            ForEach(ideas.suffix(4).reversed()) { idea in
                HStack(alignment: .top, spacing: 8) {
                    Text(idea.id).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(idea.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                        Text(statusLine(idea)).font(.system(size: 11.5)).foregroundStyle(Color.muted).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusLine(_ i: FactoryIdea) -> String {
        let when = i.sent.map { " · sent \($0.ago)" } ?? ""
        switch i.status {
        case .new: return "Waiting for the CEO" + when
        case .taken: return "Taken" + ((i.workstream ?? i.decision).map { " as \($0)" } ?? "") + when
        case .declined: return "Declined" + (i.reply.isEmpty ? "" : ": " + i.reply.replacingOccurrences(of: "\n", with: " ")) + when
        }
    }

    private func send() {
        let t = text
        sending = true; error = nil
        Task {
            let e = await model.sendIdea(project, text: t)
            sending = false
            if let e { error = e } else { text = "" }
        }
    }
}

/// The Server room's DevOps agent (D49): its rhythm and last run, Run now and the log, its open alerts and questions,
/// and what its last journal said.
struct OpsCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let ops = model.world.ops, alerts = EngineRoom.openAlerts()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 12, weight: .bold))
                Text("DevOps agent").font(.system(size: 12.5, weight: .bold)).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                if model.devopsState?.last != nil {
                    Button { model.watchRun(root: EngineRoom.folder.path, name: "DevOps") } label: {
                        Image(systemName: model.devopsState?.running == true ? "eye" : "doc.text").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 24)
                    }.buttonStyle(TactileButtonStyle(kind: .neutral)).help("The DevOps agent's run log, in the terminal")
                }
                Button { model.runDevOpsNow() } label: {
                    Label(model.devopsState?.running == true ? "Running" : "Run now", systemImage: model.devopsState?.running == true ? "hourglass" : "play.fill")
                        .font(.system(size: 11.5, weight: .semibold)).lineLimit(1).fixedSize()
                }
                .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)))
                .disabled(model.devopsState?.running == true)
            }
            if let st = model.devopsState {
                Text("\(st.config.summary) · \(st.config.runtime.label)\(st.last.map { " · last run \($0.started.ago), \($0.outcome.rawValue)" } ?? "")")
                    .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                if let b = st.blocked { Text(b.text).font(.system(size: 11.5)).foregroundStyle(b.waitsForYou ? Color.warn : Color.muted) }
            }
            if !alerts.isEmpty {
                ForEach(alerts.prefix(3), id: \.id) { a in
                    Label("\(a.id) \(a.title)", systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.warn).lineLimit(1)
                }
            }
            if let open = ops?.factory?.openDecisions, !open.isEmpty {
                ForEach(open) { d in
                    Button { model.controller.select(decision: d.id, in: World.opsID) } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text("?").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Color.onSignal).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.signal, in: RoundedRectangle(cornerRadius: 4))
                            Text(d.title).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.leading).lineLimit(2)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if let b = ops?.factory?.briefing, !b.briefing.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(b.briefing.prefix(3), id: \.self) { Text("· " + $0).font(.system(size: 11.5)).lineLimit(2) }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }
}


// MARK: setting a factory up (D76)

/// A factory without its starter files: Meatproxy offers them one by one, shows what each says, and writes only the
/// ticked ones that are missing, when you press Create. The allowlist is offered unticked.
private struct SetUpFactoryCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    @State private var plan: [StarterFile] = []
    @State private var ticked: Set<String> = []
    @State private var open: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up this factory").font(.system(size: 15, weight: .bold))
                Text("Its CEO works from a few files in factory/. Meatproxy can create starters for \(project.name). Nothing is written until you press Create, and nothing that is there is ever replaced.")
                    .font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) { ForEach(plan) { f in row(f) } }
            let n = plan.filter { ticked.contains($0.path) && !$0.exists }.count
            HStack(spacing: 8) {
                Button { create() } label: { Text(n == 0 ? "Nothing to create" : "Create \(n) file\(n == 1 ? "" : "s")") }
                    .buttonStyle(TactileButtonStyle(kind: .primary, inset: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)))
                    .disabled(n == 0 && plan.allSatisfy { !$0.exists || $0.optional })
                Button { Self.copy(plan) } label: { Text("Copy them instead") }
                    .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)))
                    .help("Copies every file with its path, to write them yourself")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.signal.opacity(0.7)))
        .onAppear {
            plan = model.setupPlan(project)
            ticked = Set(plan.filter { !$0.optional && !$0.exists }.map(\.path))
            if let d = model.debugViewFile { open = d }
        }
        .onChange(of: model.debugViewFile) { _, d in open = d }
    }

    @ViewBuilder private func row(_ f: StarterFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if f.exists {
                    Image(systemName: "checkmark.circle").font(.system(size: 13)).foregroundStyle(Color.muted).frame(width: 16)
                } else {
                    let on = ticked.contains(f.path)
                    Button { if on { ticked.remove(f.path) } else { ticked.insert(f.path) } } label: {
                        RoundedRectangle(cornerRadius: 3).fill(on ? Color.signal : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? Color.signal : Color.muted, lineWidth: 1.2))
                            .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.onSignal).opacity(on ? 1 : 0))
                            .frame(width: 15, height: 15).padding(.top, 1)
                    }
                    .buttonStyle(.plain).frame(width: 16)
                    .accessibilityLabel(f.path).accessibilityValue(on ? "will be created" : "not created").accessibilityAddTraits(.isToggle)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.path).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(f.exists ? "Already there: left as it is" : f.why).font(.system(size: 11.5)).foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(open == f.path ? "Hide" : "View") { open = open == f.path ? nil : f.path }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.muted)
            }
            if open == f.path {
                ScrollView { Text(f.text).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 170).padding(8).background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func create() {
        let files = plan.filter { ticked.contains($0.path) && !$0.exists }
        if model.setUp(project, files: files) { model.justSetUp = project.root }
    }

    static func copy(_ plan: [StarterFile]) {
        AppModel.copy(plan.map { "=== \($0.path)\n\($0.text)" }.joined(separator: "\n"))
    }
}

/// Right after setting up: the first beat, now or at its time.
private struct FirstBeatCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set up. Run the first beat now?").font(.system(size: 13.5, weight: .bold))
            Text("The CEO reads the project, writes a briefing and asks its first question. It changes nothing without your yes: it starts on Assistant.")
                .font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { model.runNow(project); model.justSetUp = nil } label: { Text("Run now") }
                    .buttonStyle(TactileButtonStyle(kind: .primary, inset: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)))
                Button { model.justSetUp = nil } label: { Text("At its next beat") }
                    .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
    }
}


/// What the CEO can really do (the project's allowlist is the lock; the mandate says what it should do). Without an
/// allowlist it offers the standard one, shown first, written only when you press Create.
private struct PermissionsCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    @State private var showing = false
    var body: some View {
        let a = model.allowlist(project.root)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("WHAT IT CAN DO").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Color.muted)
                Spacer(minLength: 0)
                if a.exists { Text("\(a.rules) rules in .claude/settings.json").font(.system(size: 11)).foregroundStyle(Color.muted) }
            }
            Label(a.line, systemImage: a.exists ? "lock.shield" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(a.exists ? Color.inkText : Color.warn)
            if !a.exists {
                Text("Without an allowlist the CEO cannot run tests or commit, so most runs end with a question. The standard one lets it read, edit, test and commit; it can never push or merge.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                if showing {
                    ScrollView { Text(model.standardAllowlist(project.root)).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160).padding(8).background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 8) {
                    if showing {
                        Button { model.addAllowlist(project); showing = false } label: { Text("Create .claude/settings.json") }
                            .buttonStyle(TactileButtonStyle(kind: .primary, inset: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)))
                        Button("Cancel") { showing = false }.buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.muted)
                    } else {
                        Button { showing = true } label: { Text("Add the standard allowlist…") }
                            .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)))
                    }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
    }
}
