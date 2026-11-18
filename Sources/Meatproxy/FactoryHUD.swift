import SwiftUI
import AppKit
import FactoryCore
import FactoryCollector

// A floor in the inspector (C1, C6, C7, C10, D1, D2, D4): its folder tabs and their bodies. A factory has Overview,
// Work, CEO and Team; any other project Overview and Work. The head (name and tabs) stays; a tab's body scrolls.

/// The tabs of a floor.
struct FloorTabs: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    var body: some View {
        if let f = project.factory, model.isFactory(project) {
            if !model.isSetUp(project.root) { ScrollFit { SetUpFactoryCard(project: project).padding(.bottom, 4) } }
            else { FactoryOverview(project: project, factory: f) }
        } else {
            PlainFloor(project: project)
        }
    }
}

/// A factory's four tabs (C10): a yellow badge only where something waits for you; how much a tab holds is said in it.
struct FactoryOverview: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let factory: Factory
    private var tab: Tab { model.factoryTabs[project.id] ?? .overview }

    enum Tab: String, Hashable { case overview, work, ceo, team }

    var body: some View {
        let hb = model.heartbeat(project)
        let items: [FolderTabs<Tab>.Item] = [
            .init(id: .overview, title: "Overview", badge: factory.openDecisions.count, help: "What waits for you, the CEO's briefing and your ideas"),
            .init(id: .work, title: "Work", help: "Workstreams and sessions"),
            .init(id: .ceo, title: "CEO", badge: hb?.blocked?.waitsForYou == true ? 1 : 0, help: "Heartbeat, what it may do, autonomy and limits"),
            .init(id: .team, title: "Team", help: "Who the CEO may call in, and how many at once"),
        ]
        TabbedBox(items: items, selected: tab, pick: { model.factoryTabs[project.id] = $0 }) {
            ScrollFit {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .overview: overview
                    case .work: WorkTab(project: project, factory: factory)
                    case .ceo: CEOTab(project: project, factory: factory)
                    case .team: TeamRoster(project: project)
                    }
                    if !factory.problems.isEmpty {
                        Tag("Could not read \(factory.problems.count) file\(factory.problems.count == 1 ? "" : "s")", tone: .stuck)
                            .help(factory.problems.joined(separator: ", "))
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder private var overview: some View {
        if model.justSetUp == project.root { FirstBeatCard(project: project) }
        if factory.paused {
            HStack(alignment: .top, spacing: 10) {
                PixelIcon("pause", color: .stuck)
                Text("Paused: STOP is on line 1 of autonomy.yml. It starts and ships nothing.").font(.s13m).foregroundStyle(Color.inkText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .spelCard(flag: .stuck)
        }
        let open = factory.openDecisions
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    QuestMarker(size: 20)
                    Text("\(open.count) decision\(open.count == 1 ? " waits" : "s wait") for you").font(.s15b).foregroundStyle(Color.inkText)
                }
                ForEach(open) { d in
                    HStack(spacing: 10) {
                        Text(d.title).font(.s13).foregroundStyle(Color.inkText).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Button { model.controller.select(decision: d.id, in: project.id) } label: { Text("Answer") }
                            .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                            .accessibilityLabel("Answer: \(d.title)")
                    }
                }
            }
            .spelCard(flag: .signal)
        }
        if factory.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No briefing yet").font(.s15).foregroundStyle(Color.inkText)
                Text("The CEO writes one at the end of every run: what it did, what needs you, what it delivered. Run now on the CEO tab starts the first one.")
                    .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            .spelCard()
        } else if let b = factory.briefing { BriefingCard(project: project, briefing: b) }
        if let c = project.cost { CostLine(cost: c) }
        if factory.takesIdeas { IdeaBox(project: project, ideas: factory.ideas) }
        else {
            Text("Ideas need factory contract version \(FactoryContract.ideas): its CEO declares it in factory/contract.yml.")
                .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true).spelCard()
        }
    }
}

// MARK: a floor that is no factory (yet)

/// Any other floor (D1): the Factory switch with what it does (the walk's quest lights it as step 2 of 2), today's
/// chats and their price; Work has the chats as cards.
private struct PlainFloor: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    @State private var tab = 0
    var body: some View {
        TabbedBox(items: [.init(id: 0, title: "Overview"), .init(id: 1, title: "Work")], selected: tab, pick: { tab = $0 }) {
            ScrollFit {
                VStack(alignment: .leading, spacing: 12) {
                    if tab == 0 { overview } else { work }
                }
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder private var overview: some View {
        if !project.isChat { FactoryCard(project: project, quest: model.factoryQuest == project.root) }
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Chats today · \(project.sessions.count)")
            if project.sessions.isEmpty { Text("No chat in the last 8 hours.").font(.s13).foregroundStyle(Color.muted) }
            ForEach(project.sessions.prefix(6)) { s in
                Button { model.controller.select(session: s.id) } label: {
                    HStack(spacing: 6) {
                        PixelIcon(s.state(now: model.world.now) == .stuck ? "sq" : "dot", color: Color.state(s.state(now: model.world.now)), size: 9)
                        Text(s.title).font(.s13).foregroundStyle(Color.inkText).lineLimit(1)
                        Text("· \(s.persona.name)").font(.s13).foregroundStyle(Color.muted).lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(CardPressStyle())
            }
        }
        .spelCard()
        if let c = project.cost { CostLine(cost: c) }
        if !project.isChat {
            Text(project.root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.mono11).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder private var work: some View {
        Eyebrow("Sessions · \(project.sessions.count)")
        if project.sessions.isEmpty { Text("No session in the last 8 hours.").font(.s13).foregroundStyle(Color.muted) }
        else { StateBar(sessions: project.sessions, now: model.world.now) }
        ForEach(project.sessions) { session in
            Button { model.controller.select(session: session.id) } label: { SessionCard(session: session) }.buttonStyle(CardPressStyle())
        }
    }
}

/// The Factory switch (D44, C7): what it does in plain words, on the floor it belongs to. Off it also keeps the floor
/// on the campus without recent sessions (D46). On the walk's quest it is step 2 of 2.
struct FactoryCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    var quest = false
    var body: some View {
        let on = model.isFactory(project), pinned = model.isPinned(project)
        VStack(alignment: .leading, spacing: 8) {
            if quest { Eyebrow("Quest · step 2 of 2", color: .signal) }
            HStack(spacing: 10) {
                PixelIcon("power", color: .inkText)
                Text("Factory").font(.s15b).foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                Toggle("Factory", isOn: Binding(get: { on }, set: { model.setFactory(project.root, on: $0) })).labelsHidden().toggleStyle(TactileToggleStyle())
            }
            Text(on ? "Off stops the CEO. The floor and its chats stay." : "A CEO runs this floor on a heartbeat and asks you yes or no. Nothing is written until you set it up; you pick its team later.")
                .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            if !on {
                RowDivider().padding(.vertical, 2)
                HStack(spacing: 10) {
                    PixelIcon("map", color: .muted)
                    Text("Keep on campus").font(.s13m).foregroundStyle(Color.inkText)
                    Spacer(minLength: 0)
                    Toggle("Keep on campus", isOn: Binding(get: { pinned }, set: { model.setPinned(project.root, on: $0) })).labelsHidden().toggleStyle(TactileToggleStyle())
                }
                .help("Keep this floor on the campus without recent sessions")
            }
        }
        .spelCard(flag: quest && !on ? .signal : nil)
    }
}

// MARK: the Work tab

private struct WorkTab: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let factory: Factory
    var body: some View {
        let streams = factory.activeWorkstreams
        SectionHead("Workstreams · \(streams.count)") {
            let dropped = factory.workstreams.count - streams.count
            if dropped > 0 { Text("\(dropped) dropped").font(.s11n).foregroundStyle(Color.muted) }
        }
        if streams.isEmpty { Text("No workstream yet: the CEO opens one for each piece of work.").font(.s13).foregroundStyle(Color.muted) }
        ForEach(streams) { w in
            Button { model.controller.select(workstream: w.id, in: project.id) } label: {
                WorkstreamRow(workstream: w, waits: factory.openDecisions.contains { $0.workstream == w.id || w.decisions.contains($0.id) }).contentShape(Rectangle())
            }.buttonStyle(CardPressStyle())
        }
        Eyebrow("Sessions · \(project.sessions.count)").padding(.top, 4)
        if project.sessions.isEmpty { Text("No session in the last 8 hours.").font(.s13).foregroundStyle(Color.muted) }
        ForEach(project.sessions) { session in
            Button { model.controller.select(session: session.id) } label: { SessionCard(session: session) }.buttonStyle(CardPressStyle())
        }
    }
}

/// A workstream on the Work tab: its id and title once, and its road (E9); a yellow edge when a question waits.
private struct WorkstreamRow: View {
    let workstream: Workstream
    var waits = false
    var body: some View {
        let w = workstream
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Tag(w.id)
                Text(w.title).font(.s15b).foregroundStyle(Color.inkText).lineLimit(1)
                Spacer(minLength: 0)
                if w.wentBack { Tag("↩ back").help(w.backSteps.last?.text ?? "") }
            }
            PhaseTrack(phases: WorkstreamCard.phases, current: WorkstreamCard.current(w))
        }
        .spelCard(flag: waits ? .signal : nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: the CEO tab (C6, C7, D2)

/// Everything about one factory's CEO, edited where it shows (D2): the heartbeat with its one problem and its buttons,
/// then groups that open in place (Rhythm, Wakes on, Autonomy, Limits, Models, Contract), what it may do (read-only,
/// so it does not look like buttons, C7), and the Factory switch at the bottom.
private struct CEOTab: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let factory: Factory
    @State private var saved: String?

    var body: some View {
        let root = project.root
        if let hb = model.heartbeat(project) { HeartbeatCard(project: project, state: hb) }
        if let e = model.projectSettings.entry(root) {
            let hb = e.heartbeat
            Group_(id: "rhythm", icon: "pulse", title: "Rhythm", summary: hb.summary, saved: $saved) { RhythmEditor(hb: hb, update: update("rhythm")) }
            Group_(id: "wakes", icon: "refresh", title: "Wakes on", summary: wakesSummary(hb), saved: $saved) {
                WakesEditor(project: project, factory: factory, hb: hb, update: update("wakes"))
            }
            MayDoCard(project: project)
            Group_(id: "autonomy", icon: "star", title: "Autonomy", summary: factory.takesMandate ? model.mandate(root).level.rawValue.capitalized : factory.autonomy?.level.rawValue.capitalized ?? "—", saved: $saved) {
                if factory.takesMandate { AutonomyEditor(root: root, autonomy: factory.autonomy, saved: { flash("autonomy") }) }
                else if let a = factory.autonomy { AutonomyLine(autonomy: a) }
                else { Text("No autonomy.yml yet.").font(.s13).foregroundStyle(Color.muted) }
            }
            Group_(id: "limits", icon: "lock", title: "Limits", summary: limitsSummary(hb), saved: $saved) {
                LimitsEditor(root: root, hb: hb, update: update("limits"), saved: { flash("limits") })
            }
            Group_(id: "models", icon: "box", title: "Models", summary: modelsSummary(hb), saved: $saved) { ModelsEditor(hb: hb, update: update("models")) }
            Group_(id: "contract", icon: "file", title: "Contract", summary: "v\(factory.contractVersion)", saved: $saved) { contract }
        }
        FactoryCard(project: project)
    }

    @ViewBuilder private var contract: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("meatproxy-factory v\(factory.contractVersion)\(factory.contract == nil ? " (no contract.yml)" : "")").font(.s13).foregroundStyle(Color.inkText)
            if factory.newerContract { Tag("Newer than this Meatproxy (v\(FactoryContract.current))", tone: .warn) }
            Text(project.root.replacingOccurrences(of: NSHomeDirectory(), with: "~") + "/factory").font(.mono11).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
            Text("The CEO declares it in factory/contract.yml (docs/contracts/factory.md).").font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func update(_ group: String) -> (@escaping (inout Heartbeat) -> Void) -> Void {
        { change in model.updateHeartbeat(project.root, change); flash(group) }
    }
    private func flash(_ group: String) {
        saved = group
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if saved == group { saved = nil } }
    }

    private func wakesSummary(_ hb: Heartbeat) -> String {
        var s: [String] = []
        if hb.wakeOnSentry && factory.sources.hasSentry { s.append("Sentry") }
        if hb.wakeOnTracker && factory.sources.tracker != nil { s.append("Tracker") }
        if hb.wakeOnCI { s.append("CI") }
        if hb.wakeOnAnswer { s.append("answers") }
        return s.isEmpty ? "Heartbeat only" : s.joined(separator: ", ")
    }
    private func limitsSummary(_ hb: Heartbeat) -> String {
        (hb.maxCostPerDay.map { "$\(Int($0)) a day · " } ?? "") + "\(hb.runsPerDay) runs"
    }
    private func modelsSummary(_ hb: Heartbeat) -> String {
        let set = ModelPolicy.Kind.allCases.compactMap { hb.models[$0].model }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return set.isEmpty ? "Default" : Array(Set(set)).sorted().joined(separator: ", ")
    }
}

/// A group on the CEO tab: its head (icon, name, summary or "Saved"), opened in place; one open at a time.
private struct Group_<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    let icon: String
    let title: String
    let summary: String
    @Binding var saved: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        let open = model.ceoGroup == id
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.15)) { model.ceoGroup = open ? nil : id } } label: {
                HStack(spacing: 10) {
                    PixelIcon(icon, color: .inkText)
                    Text(title).font(.s15b).foregroundStyle(Color.inkText)
                    Spacer(minLength: 6)
                    if saved == id {
                        HStack(spacing: 4) { PixelIcon("check", color: .done, size: 9); Text("Saved").font(.s13m) }.foregroundStyle(Color.done)
                    } else {
                        Text(summary).font(.s13).foregroundStyle(Color.muted).lineLimit(1)
                    }
                    PixelIcon(open ? "chevd" : "chev", color: .muted, size: 9)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title): \(summary)").accessibilityHint(open ? "Close" : "Open to change it here")
            if open { content() }
        }
        .spelCard(selected: open)
    }
}

/// The CEO's heartbeat (C6): its status once, in its head; its rhythm in one line; the problem once, with its one
/// button; Run now and Log with their labels.
struct HeartbeatCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let state: HeartbeatState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PixelIcon("pulse", color: .inkText)
                Text("Heartbeat").font(.s15b).foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                status
            }
            Text(rhythmLine).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            problem
            HStack(spacing: 8) {
                if state.running, let ceo = project.sessions.first(where: { $0.heartbeatRun == true }) {
                    Button { model.takeOver(ceo) } label: { SpelLabel("Take over", icon: "terminal") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).help("Stop this run and continue it yourself in the terminal")
                } else {
                    Button { model.runNow(project) } label: { SpelLabel("Run now", icon: "play") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).help("Wake the CEO now, also when the heartbeat is paused")
                }
                if model.heartbeatLog(project) != nil {
                    // follow the run in the terminal (D57)
                    Button { model.watchRun(root: project.root, name: project.name) } label: { SpelLabel(state.running ? "Watch" : "Log", icon: state.running ? "eye" : "log") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).help(state.running ? "Watch the run in the terminal" : "The last run's log, in the terminal")
                }
                Spacer(minLength: 0)
            }
        }
        .spelCard()
    }

    @ViewBuilder private var status: some View {
        if state.running { Tag("Running", tone: .work, icon: "dot") }
        else if let b = state.blocked { Tag(b.waitsForYou ? "Held" : "Waiting", tone: b.waitsForYou ? .warn : .neutral) }
        else if let last = state.last, last.outcome == .failed || last.outcome == .timedOut {
            Tag(last.detail?.contains("was closed") == true || Self.caughtUp(last) ? "Missed \(Self.clock(last.started))" : "Run failed", tone: .warn)
        }
        else if state.config.paused { Tag("Paused") }
        else { Tag("On schedule", tone: .done, icon: "check") }
    }

    private var rhythmLine: String {
        let c = state.config
        var s = c.summary + " · \(state.runsToday) of \(c.runsPerDay) today"
        if state.running, let last = state.last { s += " · running since \(Self.clock(last.started))" }
        else if let p = state.pending { s += " · \(p.reason.label.lowercased()) soon" }
        else if let n = state.next { s += " · next run \(Self.when(n))" }
        return s
    }

    /// the one problem of the last run, with its one fix; or that nothing needs doing
    @ViewBuilder private var problem: some View {
        if let b = state.blocked {
            fix(b.text, button: b.waitsForYou ? "Resume" : nil, warn: b.waitsForYou) { model.resume(project) }
        } else if let last = state.last, last.outcome != .running {
            if last.outcome == .failed, last.detail?.contains("was closed") == true, !model.projectSettings.heartbeatWhenClosed {
                fix("Meatproxy was closed at \(Self.clock(last.started)), so the run was skipped.", button: "Keep running when closed", warn: true) {
                    model.setHeartbeatWhenClosed(true)
                }
            } else if let w = last.warning, !(w.hasPrefix("No allowlist") && model.allowlist(project.root).exists) {
                fix(w, button: nil, warn: true) {}
            } else if last.outcome == .failed || last.outcome == .timedOut {
                fix("The last run \(last.outcome == .timedOut ? "timed out" : "failed"): \(last.detail ?? "see the log").", button: nil, warn: true) {}
            }
        }
    }

    private func fix(_ text: String, button: String?, warn: Bool, _ action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                PixelIcon(warn ? "warn" : "pause", color: warn ? .warn : .muted)
                Text(text).font(.s13m).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
            }
            if let button {
                Button(action: action) { Text(button) }.buttonStyle(SpelButtonStyle(kind: .primary, size: .s, wide: true))
            }
        }
        .spelWell(pad: 12)
    }

    static func caughtUp(_ r: HeartbeatRun) -> Bool { if case .caughtUp = r.reason { return true }; return false }
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

/// When the CEO wakes: days, a rhythm or times, the runtime, and Paused (D2).
private struct RhythmEditor: View {
    @EnvironmentObject private var model: AppModel
    let hb: Heartbeat
    let update: (@escaping (inout Heartbeat) -> Void) -> Void
    private static let rhythms: [(Int, String)] = [(0, "At times"), (60, "1 h"), (120, "2 h"), (240, "4 h")]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LiftedSegments(items: [.init(id: Heartbeat.Days.weekdays, title: "Weekdays"), .init(id: .everyDay, title: "Every day")],
                           selected: hb.days, fill: true) { d in update { $0.days = d } }
            editRow("Every") {
                LiftedSegments(items: Self.rhythms.map { .init(id: $0.0, title: $0.1) }, selected: hb.everyMinutes ?? 0, fontSize: 11,
                               padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { m in update { $0.everyMinutes = m == 0 ? nil : m } }
            }
            if hb.everyMinutes == nil { editRow("Runs at") { TimesField(times: hb.times) { t in update { $0.times = t } } } }
            editRow("Runtime") {
                LiftedSegments(items: Heartbeat.Runtime.allCases.map { .init(id: $0, title: $0.label) }, selected: hb.runtime, fontSize: 11,
                               padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { r in update { $0.runtime = r } }
            }
            editRow("When Meatproxy is closed", help: "Every factory: a launch agent keeps the heartbeat going while the app is closed") {
                Toggle("When Meatproxy is closed", isOn: Binding(get: { model.projectSettings.heartbeatWhenClosed }, set: { model.setHeartbeatWhenClosed($0) }))
                    .labelsHidden().toggleStyle(TactileToggleStyle())
            }
            editRow("Paused", help: "Only Run now wakes it while paused") {
                Toggle("Paused", isOn: Binding(get: { hb.paused }, set: { v in update { $0.paused = v } })).labelsHidden().toggleStyle(TactileToggleStyle())
            }
        }
    }
}

/// A label on the left and a control on the right, in a group.
private func editRow<C: View>(_ label: String, help: String? = nil, @ViewBuilder _ control: () -> C) -> some View {
    HStack(spacing: 10) {
        Text(label).font(.s13).foregroundStyle(Color.inkText).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 6)
        control()
    }
    .help(help ?? "")
}

/// What else wakes the CEO (D61): your answers and ideas, a failed CI run, Sentry and Tracker, with how each did.
private struct WakesEditor: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let factory: Factory
    let hb: Heartbeat
    let update: (@escaping (inout Heartbeat) -> Void) -> Void
    var body: some View {
        let src = factory.sources, v4 = factory.takesSources
        VStack(alignment: .leading, spacing: 10) {
            editRow("Your answers and ideas") { toggle(hb.wakeOnAnswer) { v in update { $0.wakeOnAnswer = v } } }
            editRow("A failed CI run on main") { toggle(hb.wakeOnCI) { v in update { $0.wakeOnCI = v } } }
            editRow(src.hasSentry ? "Sentry · a new error" : "Sentry") {
                toggle(hb.wakeOnSentry) { v in update { $0.wakeOnSentry = v } }.disabled(!v4 || !src.hasSentry)
            }
            if v4, src.hasSentry, hb.wakeOnSentry { health(model.sourceHealth[factory.root]?.sentry, missing: Secrets.get(.sentry) == nil && !model.fixture ? "No Sentry token yet." : nil) }
            editRow(src.tracker != nil ? "Tracker · a story in Ready" : "Tracker") {
                toggle(hb.wakeOnTracker) { v in update { $0.wakeOnTracker = v } }.disabled(!v4 || src.tracker == nil)
            }
            if v4, src.tracker != nil, hb.wakeOnTracker {
                health(model.sourceHealth[factory.root]?.tracker,
                       missing: WakeSources.trackerURL(model.projectSettings.trackerURL) == nil ? "No Tracker address yet." : Secrets.get(.tracker) == nil && !model.fixture ? "No Tracker token yet." : nil)
            }
            if !v4 || (!src.hasSentry && src.tracker == nil) {
                Text(!v4 ? "Sentry and Tracker need factory contract v4: the CEO names its projects in factory/contract.yml."
                         : "To wake on Sentry or Tracker, the CEO names its project in factory/contract.yml (sentry: org/project, tracker: <slug>).")
                    .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            Button { model.settingsPage = "sources"; model.settingsOpen = true } label: { SpelLabel("Tokens in Sources", icon: "key") }
                .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
        }
    }
    private func toggle(_ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { on }, set: set)).labelsHidden().toggleStyle(TactileToggleStyle())
    }
    private func health(_ h: SourceHealth?, missing: String?) -> some View {
        SourceHealthLine(health: h, missing: missing.map { $0 + " Add it in Settings › Sources." })
    }
}

/// How a wake source did at its last check: works, or what fails and since when; or what is still missing.
struct SourceHealthLine: View {
    let health: SourceHealth?
    let missing: String?
    var label: String? = nil
    var body: some View {
        let (ok, line): (Bool, String) = {
            if let missing { return (false, missing) }
            guard let h = health else { return (true, "Not checked yet") }
            if h.ok { return (true, "Works · checked \(h.at.formatted(date: .omitted, time: .shortened))") }
            let since = h.since.map { " since " + $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? ""
            return (false, h.line + since + ". The CEO is not woken by it until it works.")
        }()
        HStack(alignment: .top, spacing: 6) {
            PixelIcon(ok ? "check" : "warn", color: ok ? .done : .warn, size: 9).padding(.top, 3)
            Text((label.map { $0 + ": " } ?? "") + line).font(.s13).foregroundStyle(ok ? Color.muted : Color.warn).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What the CEO can really do (C6, C7): read from the project's allowlist, as plain text with ticks and crosses; it
/// never looks like a button. Without an allowlist it offers the standard one, shown first, written on Create.
private struct MayDoCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    @State private var showing = false
    var body: some View {
        let a = model.allowlist(project.root)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PixelIcon("lock", color: .inkText)
                Text("What it may do").font(.s15b).foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                if a.exists { Text("\(a.rules) rules").font(.s13).foregroundStyle(Color.muted).help("In .claude/settings.json") }
            }
            if a.exists {
                HStack(spacing: 14) {
                    may("Test", a.tests); may("Commit", a.commit); may("Push", a.push); may("Merge", a.merge)
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    PixelIcon("warn", color: .warn, size: 9).padding(.top, 4)
                    Text("No allowlist: the CEO cannot run tests or commit, so most runs end with a question. The standard one lets it read, edit, test and commit; never push or merge.")
                        .font(.s13).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
                }
                if showing {
                    ScrollView { Text(model.standardAllowlist(project.root)).font(.mono11).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160).spelWell(pad: 8)
                }
                HStack(spacing: 8) {
                    if showing {
                        Button { model.addAllowlist(project); showing = false } label: { Text("Create .claude/settings.json") }
                            .buttonStyle(SpelButtonStyle(kind: .primary, size: .s))
                        Button { showing = false } label: { Text("Cancel") }.buttonStyle(SpelButtonStyle(kind: .ghost, size: .s))
                    } else {
                        Button { showing = true } label: { Text("Add the standard allowlist…") }.buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                    }
                }
            }
        }
        .spelCard()
    }
    private func may(_ what: String, _ yes: Bool) -> some View {
        HStack(spacing: 4) {
            PixelIcon(yes ? "check" : "close", color: yes ? .done : .muted, size: 9)
            Text(what).font(.s13m).foregroundStyle(yes ? Color.inkText : Color.muted)
        }
        .accessibilityLabel(yes ? "May \(what.lowercased())" : "May not \(what.lowercased())")
    }
}

/// Your mandate for the factory (D56), edited in place (C7): its level, each item ask, tell or off with the CEO's
/// yeses in a row, its role and your preferences. Written to factory/mandate.yml; the CEO follows it from its next run.
private struct AutonomyEditor: View {
    @EnvironmentObject private var model: AppModel
    let root: String
    let autonomy: Autonomy?
    let saved: () -> Void
    @State private var notes = ""
    @State private var quiet = ""
    @FocusState private var focus: Field?
    enum Field { case notes, quiet }

    private static let levelText: [FactoryMandate.Level: String] = [
        .assistant: "It asks before everything: a yes/no question for each step.",
        .hybrid: "It fixes bugs, updates dependencies and merges its tested PRs, and tells you. The rest it asks first.",
        .dark: "It does everything and tells you, except spending money and store releases.",
        .custom: "You set each item yourself below.",
    ]

    var body: some View {
        let m = model.mandate(root), dark = model.projectSettings.darkAllowed(root)
        VStack(alignment: .leading, spacing: 10) {
            LiftedSegments(items: FactoryMandate.Level.allCases.filter { $0 != .custom || m.level == .custom }.map { l in
                .init(id: l, title: l.rawValue.capitalized, enabled: l != .dark || dark, help: l == .dark && !dark ? "Dark is off for this factory (Limits › Allow Dark)" : nil)
            }, selected: m.level, fill: true) { l in set { $0.set(level: l) } }
            Text(Self.levelText[m.level] ?? "").font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(FactoryMandate.Item.allCases, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(AutonomyEditor.short(i)).font(.s13).foregroundStyle(Color.inkText).lineLimit(1)
                    if let g = autonomy?.gates.first(where: { $0.name.lowercased() == i.rawValue }), m.mode(i) == .ask {
                        StreakDots(count: min(g.streak, Autonomy.promoteAfter), of: Autonomy.promoteAfter)
                    }
                    Spacer(minLength: 4)
                    // changing an item makes the mandate Custom
                    LiftedSegments(items: [.init(id: FactoryMandate.Mode.ask, title: "Ask"), .init(id: .notify, title: "Tell me"), .init(id: .off, title: "Off")],
                                   selected: m.mode(i), fontSize: 11, padding: EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)) { v in
                        set { $0.level = .custom; $0.items[i] = v }
                    }
                }
                .help(FactoryMandate.meaning(i))
            }
            if autonomy?.gates.isEmpty == false {
                Text("Dots: your yeses in a row. At \(Autonomy.promoteAfter) the CEO may propose to stop asking; your setting decides.")
                    .font(.s11n).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            RowDivider()
            editRow("The CEO") {
                LiftedSegments(items: [.init(id: FactoryMandate.Role.orchestrator, title: "Orchestrates"), .init(id: .handsOn, title: "Works along")],
                               selected: m.role, fontSize: 11, padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { r in set { $0.role = r } }
            }
            editRow("Briefing in") {
                LiftedSegments(items: [.init(id: "en", title: "English"), .init(id: "nl", title: "Dutch")], selected: m.briefingLanguage, fontSize: 11,
                               padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { v in set { $0.briefingLanguage = v } }
            }
            editRow("Proposals a run") {
                LiftedSegments(items: [1, 2, 3].map { .init(id: $0, title: "\($0)") }, selected: m.proposalsPerRun, fontSize: 11,
                               padding: EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9)) { v in set { $0.proposalsPerRun = v } }
            }
            editRow("PR size") {
                LiftedSegments(items: ["small", "medium", "large"].map { .init(id: $0, title: $0.capitalized) }, selected: m.prSize, fontSize: 11,
                               padding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)) { v in set { $0.prSize = v } }
            }
            editRow("Batch small fixes") {
                Toggle("Batch small fixes", isOn: Binding(get: { m.batchSmallFixes }, set: { v in set { $0.batchSmallFixes = v } })).labelsHidden().toggleStyle(TactileToggleStyle())
            }
            editRow("Quiet hours") {
                TextField("22:00-07:00", text: $quiet).focused($focus, equals: .quiet).font(.mono).textFieldStyle(.plain)
                    .padding(.horizontal, 10).frame(width: 120, height: 30).lifted(focused: focus == .quiet).onSubmit { save() }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Anything else, in your words").font(.s13).foregroundStyle(Color.inkText)
                TextField("", text: $notes, prompt: Text("Never touch the payment code.").foregroundStyle(Color.muted), axis: .vertical)
                    .lineLimit(2...6).focused($focus, equals: .notes).font(.s13).textFieldStyle(.plain)
                    .padding(10).lifted(focused: focus == .notes)
            }
        }
        .onAppear { notes = m.notes; quiet = m.quietHours }
        .onChange(of: focus) { old, new in model.typing = new != nil; if old != nil { save() } }
        .onDisappear { model.typing = false }
    }

    private func set(_ change: (inout FactoryMandate) -> Void) { model.setMandate(root, change); saved() }
    private func save() {
        let m = model.mandate(root)
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines), q = quiet.trimmingCharacters(in: .whitespaces)
        guard n != m.notes || q != m.quietHours else { return }
        set { $0.notes = n; $0.quietHours = q }
    }

    static func short(_ i: FactoryMandate.Item) -> String {
        switch i {
        case .propose: "Own ideas"
        case .bugs: "Bug fixes"
        case .dependencies: "Dependencies"
        case .prs: "Merging PRs"
        case .ship: "Shipping"
        case .store: "Store releases"
        case .spend: "Spending"
        case .promote: "Its own gates"
        }
    }
}

/// Yeses in a row as dots: filled up to the count, open after it.
private struct StreakDots: View {
    let count: Int, of: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<of, id: \.self) { k in
                RoundedRectangle(cornerRadius: 1.5).fill(k < count ? Color.inkText : Color.clear).frame(width: 5, height: 5)
                    .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(k < count ? Color.clear : Color.muted, lineWidth: 1))
            }
        }
        .accessibilityElement().accessibilityLabel("\(count) of \(of) yes in a row")
        .help("\(count) of \(of) yes in a row on this step")
    }
}

/// How dark the floor is, for a factory before contract v3 (no mandate): read-only.
private struct AutonomyLine: View {
    let autonomy: Autonomy
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Tag(autonomy.level.rawValue)
                if autonomy.paused { Tag("Paused", tone: .stuck) }
            }
            ForEach(autonomy.gates, id: \.name) { g in
                HStack {
                    Text(g.name.prefix(1).uppercased() + g.name.dropFirst()).font(.s13).foregroundStyle(Color.inkText)
                    Spacer()
                    Text(g.notify ? "Tells you" : "Asks · \(min(g.streak, Autonomy.promoteAfter)) of \(Autonomy.promoteAfter) yes").font(.s13).foregroundStyle(Color.muted)
                }
            }
            Text("Upgrade factory/contract.yml to v\(FactoryContract.current) to set this here.").font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Limits on automatic runs (D48, D61), and whether Dark is allowed at all (D68): one group, once.
private struct LimitsEditor: View {
    @EnvironmentObject private var model: AppModel
    let root: String
    let hb: Heartbeat
    let update: (@escaping (inout Heartbeat) -> Void) -> Void
    let saved: () -> Void
    private static let caps: [LiftedSegments<Int>.Item] = [.init(id: 0, title: "None"), .init(id: 5, title: "$5"), .init(id: 10, title: "$10"), .init(id: 20, title: "$20"), .init(id: 50, title: "$50")]
    var body: some View {
        let pad = EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
        VStack(alignment: .leading, spacing: 10) {
            editRow("Runs a day") {
                LiftedSegments(items: [3, 6, 12].map { .init(id: $0, title: "\($0)") }, selected: hb.runsPerDay, fontSize: 11, padding: pad) { n in update { $0.runsPerDay = n } }
            }
            editRow("Between runs") {
                LiftedSegments(items: [10, 20, 60].map { .init(id: $0, title: $0 == 60 ? "1 h" : "\($0) min") }, selected: hb.cooldownMinutes, fontSize: 11, padding: pad) { m in update { $0.cooldownMinutes = m } }
            }
            editRow("API price a day") {
                LiftedSegments(items: Self.caps, selected: Int(hb.maxCostPerDay ?? 0), fontSize: 11, padding: pad) { v in update { $0.maxCostPerDay = v == 0 ? nil : Double(v) } }
            }
            editRow("Allow Dark", help: "Off: its CEO runs Assistant or Hybrid at most, whatever the mandate says") {
                Toggle("Allow Dark", isOn: Binding(get: { model.projectSettings.darkAllowed(root) }, set: { model.setDarkAllowed(root, on: $0); saved() }))
                    .labelsHidden().toggleStyle(TactileToggleStyle())
            }
            Text("A run is one wake of the CEO. Run now is yours and does not count. The API price is what this floor's sessions would have cost at list prices today.")
                .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Which model and effort a run gets, by why it woke (D70). Default keeps the runtime's own choice.
private struct ModelsEditor: View {
    let hb: Heartbeat
    let update: (@escaping (inout Heartbeat) -> Void) -> Void
    private static let titles: [String: String] = [
        "haiku": "Haiku", "sonnet": "Sonnet", "opus": "Opus",
        "gpt-6-luna": "Luna", "gpt-6.1-sol": "Sol", "gpt-6-astra": "Astra", "gpt-5.3-codex": "5.3 Codex",
        "low": "Low", "medium": "Med", "high": "High", "xhigh": "XHigh", "max": "Max",
    ]
    private func items(_ ids: [String]) -> [LiftedSegments<String>.Item] {
        [LiftedSegments<String>.Item(id: "", title: "Default")] + ids.map { LiftedSegments<String>.Item(id: $0, title: Self.titles[$0] ?? $0) }
    }
    var body: some View {
        let pad = EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ModelPolicy.Kind.allCases, id: \.self) { k in
                let c = hb.models[k]
                VStack(alignment: .leading, spacing: 6) {
                    Text(k.label).font(.s13m).foregroundStyle(Color.inkText)
                    LiftedSegments(items: items(ModelPolicy.models[hb.runtime] ?? []), selected: c.model ?? "", fontSize: 11, padding: pad) { m in
                        update { $0.models[k].model = m.isEmpty ? nil : m }
                    }
                    LiftedSegments(items: items(ModelPolicy.efforts[hb.runtime] ?? []), selected: c.effort ?? "", fontSize: 11, padding: pad) { e in
                        update { $0.models[k].effort = e.isEmpty ? nil : e }
                    }
                }
            }
            Text("Default leaves the choice to \(hb.runtime.label). The routine heartbeat runs most: a smaller model there saves the most.")
                .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "07:10, 13:00": wall-clock times; anything that is not a time is dropped, and an empty list keeps the old one.
struct TimesField: View {
    @EnvironmentObject private var model: AppModel
    let times: [String]
    let change: ([String]) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("07:10, 13:00", text: $text).focused($focused).font(.mono)
            .textFieldStyle(.plain).padding(.horizontal, 10).frame(width: 130, height: 30)
            .lifted(focused: focused)
            .onSubmit(save).onChange(of: focused) { _, f in model.typing = f; if !f { save() } }
            .onAppear { text = times.joined(separator: ", ") }
            .onChange(of: times) { _, t in if !focused { text = t.joined(separator: ", ") } }
            .accessibilityLabel("Times of day")
    }
    private func save() {
        let parsed = text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { part -> String? in
            let p = part.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
            return String(format: "%02d:%02d", p[0], p[1])
        }
        let unique = Array(Set(parsed)).sorted()
        if unique.isEmpty || unique == times { text = times.joined(separator: ", "); return }
        change(unique)
    }
}

// MARK: the Overview tab's cards

/// The CEO's latest briefing: who wrote it and when, a few lines, and what was delivered.
private struct BriefingCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let briefing: Briefing
    var body: some View {
        // the CEO as the floor shows it: its run's person when there is one
        let run = project.sessions.first { $0.heartbeatRun == true }
        let key = run.map { model.cast(of: $0) } ?? CastKey(role: .ceo, seed: "ceo:" + project.root)
        let ceo = run?.persona.name ?? Persona(id: "ceo:" + project.root).name
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Portrait(image: model.controller.portrait(key), role: .ceo, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Briefing from \(ceo)").font(.s15b).foregroundStyle(Color.inkText)
                    Text("CEO · \(Self.day(briefing.name))").font(.s11n).foregroundStyle(Color.muted)
                }
            }
            .task { await model.controller.ensurePortraits([key]) }
            ForEach(Array(briefing.briefing.enumerated()), id: \.offset) { _, line in
                Text(Self.plain(line)).font(.s13).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
            }
            if !briefing.delivered.isEmpty && !(briefing.delivered.count == 1 && briefing.delivered[0].lowercased().hasPrefix("nothing")) {
                ForEach(Array(briefing.delivered.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        PixelIcon("box", color: .done, size: 9).padding(.top, 4)
                        Text(Self.plain(line)).font(.s13).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .spelCard()
    }

    /// "2026-11-16" → "Mon 16 Nov", "2026-11-16-2" → "Mon 16 Nov · run 2"
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { PixelIcon("idea", color: .inkText); Text("Ideas for the CEO").font(.s15b).foregroundStyle(Color.inkText) }
            TextField("", text: $text, prompt: Text("A feature, a wish, a worry. The CEO turns it into a question for you.").foregroundStyle(Color.muted), axis: .vertical)
                .lineLimit(2...6).font(.s13).textFieldStyle(.plain).focused($focused)
                .padding(10).lifted(focused: focused)
                .onChange(of: focused) { _, on in model.typing = on }
                .onDisappear { model.typing = false }
            HStack {
                if let error { Text(error).font(.s13).foregroundStyle(Color.warn).lineLimit(2) }
                Spacer(minLength: 0)
                Button { send() } label: { SpelLabel(sending ? "Sending" : "Send idea", icon: "send", key: "⌘↩") }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command).help("Send to the CEO (⌘↩)")
            }
            ForEach(ideas.suffix(4).reversed()) { idea in
                HStack(alignment: .top, spacing: 8) {
                    Tag(idea.id)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(idea.title).font(.s13m).foregroundStyle(Color.inkText).lineLimit(2)
                        Text(statusLine(idea)).font(.s11n).foregroundStyle(Color.muted).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .spelCard()
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

// MARK: a workstream (C4)

/// One workstream in full (C4): its id and phase once, the road, the open question as a quest, then the story so far.
struct WorkstreamCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let workstream: Workstream

    static let phases = ["Plan", "Build", "Test", "Ship", "Done"]
    static func current(_ w: Workstream) -> Int { w.phase == .done ? phases.count : (w.phase.step ?? 0) }

    var body: some View {
        let w = workstream
        let questions = (project.factory?.decisions ?? []).filter { $0.workstream == w.id || w.decisions.contains($0.id) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Tag(w.id)
                Text(sinceLine(w)).font(.s13).foregroundStyle(Color.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
            PhaseTrack(phases: Self.phases, current: Self.current(w))
            ForEach(questions.filter { $0.status == .open }) { d in
                HStack(spacing: 10) {
                    QuestMarker(size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waits for your yes").font(.s15b).foregroundStyle(Color.inkText)
                        Text("\(d.id) · \(d.title)").font(.s13).foregroundStyle(Color.muted).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button { model.controller.select(decision: d.id, in: project.id) } label: { Text("Answer") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                }
                .spelCard(flag: .signal)
            }
            let answered = questions.filter { $0.status != .open }
            if !answered.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Answered")
                    ForEach(answered) { d in
                        Button { model.controller.select(decision: d.id, in: project.id) } label: {
                            HStack(spacing: 8) {
                                Tag(d.status.rawValue, tone: d.status == .yes ? .done : .neutral)
                                Text("\(d.id) · \(d.title)").font(.s13).foregroundStyle(Color.inkText).lineLimit(1)
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(CardPressStyle())
                    }
                }
            }
            links(w)
            if !w.log.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Story so far")
                    VStack(spacing: 0) {
                        ForEach(Array(w.log.reversed().prefix(8).enumerated()), id: \.offset) { k, e in
                            if k > 0 { RowDivider() }
                            logRow(e)
                        }
                    }
                    .spelCard(pad: 0)
                }
            }
        }
    }

    @ViewBuilder private func links(_ w: Workstream) -> some View {
        let tags: [String] = [w.source.map { "from \($0)" }, w.release.map { "release \($0)" }].compactMap { $0 }
        if w.pr != nil || w.branch != nil || !tags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let pr = w.pr, let url = URL(string: pr) {
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 6) { PixelIcon("branch", color: .muted); Text(FactoryText.links(pr).first?.title ?? pr).font(.s13m).lineLimit(1); PixelIcon("chev", color: .muted, size: 9) }
                            .foregroundStyle(Color.inkText)
                    }.buttonStyle(.plain).help(pr)
                }
                if let b = w.branch { Text(b).font(.mono11).foregroundStyle(Color.muted).lineLimit(1) }
                if !tags.isEmpty { HStack(spacing: 6) { ForEach(tags, id: \.self) { Tag($0) } } }
            }
        }
    }

    private func logRow(_ e: WorkLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Socket(size: 32) { PixelIcon(Self.icon(e.phase), color: e.isBack ? .warn : .inkText) }
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.sentence(BriefingCard.plain(e.text))).font(.s13m).foregroundStyle(Color.inkText).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(e.isBack ? "Back from \(e.from?.rawValue ?? "") to \(e.phase?.rawValue ?? "")" : (e.phase?.rawValue.capitalized ?? "Note"))
                    .font(.s11n).foregroundStyle(e.isBack ? Color.warn : Color.muted)
            }
            Spacer(minLength: 4)
            Text(BriefingCard.day(e.date)).font(.s11n).foregroundStyle(Color.muted).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func sinceLine(_ w: Workstream) -> String {
        let at = w.log.last { $0.phase == w.phase }?.date
        let label = w.phase.rawValue.capitalized
        return w.phase == .done ? "Done" + (at.map { " since \(BriefingCard.day($0))" } ?? "") : "In \(label)" + (at.map { " since \(BriefingCard.day($0))" } ?? "")
    }

    /// a log line as a sentence: its first letter capital
    static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func icon(_ p: WorkPhase?) -> String {
        switch p { case .plan?: "idea"; case .build?: "box"; case .test?: "check"; case .ship?: "ship"; case .done?: "star"; default: "file" }
    }
}

// MARK: the decision card (C4)

/// One question (C4): one line with its id, kind and workstream, then why, the evidence, what yes and no do, and the
/// answer with 1 and 2. Yes or No asks once more ("Send yes"), then writes the file; a question that is no longer
/// open shows its answer.
struct DecisionCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let decision: FactoryDecision

    var body: some View {
        let d = decision
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Tag(d.id)
                Tag(d.kind)
                if let w = d.workstream, let ws = project.factory?.workstreams.first(where: { $0.id == w }) {
                    Button { model.controller.select(workstream: w, in: project.id) } label: {
                        HStack(spacing: 4) { Text("\(ws.id) \(ws.title)").font(.s13m).lineLimit(1); PixelIcon("chev", color: .muted, size: 9) }
                            .foregroundStyle(Color.inkText)
                            .padding(.bottom, 2).overlay(alignment: .bottom) { Rectangle().fill(Color.border).frame(height: 2) }
                    }
                    .buttonStyle(.plain).help("Open the workstream")
                } else if let w = d.workstream { Tag(w) }
                Spacer(minLength: 0)
            }
            if d.status == .open, let t = model.trigger(for: d, in: project) {
                HStack(alignment: .top, spacing: 6) {
                    PixelIcon("chev", color: .muted, size: 9).padding(.top, 4)
                    Text(t).font(.s13m).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !d.why.isEmpty { Part(title: "Why") { Prose(text: d.why) } }
            if !d.evidence.isEmpty { Part(title: "Evidence") { Evidence(text: d.evidence, root: project.factory?.root ?? project.root) } }
            if !d.onYes.isEmpty || !d.onNo.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if !d.onYes.isEmpty { Part(title: "On yes") { Prose(text: d.onYes) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).spelWell(pad: 10) }
                    if !d.onNo.isEmpty { Part(title: "On no") { Prose(text: d.onNo) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).spelWell(pad: 10) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if d.status == .open { AnswerForm(project: project, decision: d) } else { answered(d) }
        }
    }

    @ViewBuilder private func answered(_ d: FactoryDecision) -> some View {
        let color: Color = d.status == .yes ? .done : .inkText
        HStack(alignment: .top, spacing: 12) {
            if d.status == .yes || d.status == .no { AnswerStamp(yes: d.status == .yes) }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(d.status.rawValue.capitalized)\(d.answered.map { " · \($0.ago)" } ?? "")").font(.s15b).foregroundStyle(color)
                if !d.answer.isEmpty { Text(d.answer).font(.s13).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true) }
                if d.status == .yes || d.status == .no {
                    Text(model.receipt(for: d, in: project)).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .spelCard()
    }
}

/// Yes and No with their keys (1 and 2), a note, and the confirm step: the send is the one primary action, and its
/// words stay literal in meme mode too. The server card (C9) uses it without the note.
struct AnswerForm: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let decision: FactoryDecision
    var yesTitle: String? = nil
    var noTitle: String? = nil
    var withNote = true
    @State private var note = ""
    @State private var pending: Bool?
    @State private var sending = false
    @State private var failure: String?
    @State private var sendPulse = 0
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pending {
                HStack(spacing: 8) {
                    Button { send(pending) } label: {
                        SpelLabel(sending ? "Sending…" : pending ? "Send yes" : "Send no", key: "⌘↩", onYellow: pending)
                    }
                    .buttonStyle(SpelButtonStyle(kind: pending ? .primary : .secondary, wide: true, pulse: sendPulse)).disabled(sending)
                    .background { Button("") { sendPulse += 1; send(pending) }.keyboardShortcut(.return, modifiers: .command).opacity(0).disabled(sending) }
                    Button { self.pending = nil } label: { Text("Cancel") }.buttonStyle(SpelButtonStyle(kind: .secondary)).disabled(sending)
                }
                Text(model.consequence(of: decision, yes: pending, in: project)).font(.s13m).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
                Text(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Writes \(pending ? "yes" : "no") into \(fileName)." : "Writes \(pending ? "yes" : "no") and your note into \(fileName).")
                    .font(.s11n).foregroundStyle(Color.muted).lineLimit(2)
            } else {
                HStack(spacing: 8) {
                    Button { pending = true; failure = nil } label: { SpelLabel(yesTitle ?? (model.memeMode ? "LGTM" : "Yes"), key: "1", onYellow: true) }
                        .buttonStyle(SpelButtonStyle(kind: .primary, wide: withNote))
                    Button { pending = false; failure = nil } label: { SpelLabel(noTitle ?? (model.memeMode ? "Not today" : "No"), key: "2") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, wide: withNote))
                    if !withNote { Spacer(minLength: 0) }
                }
            }
            if withNote {
                TextField("", text: $note, prompt: Text(project.id == World.opsID ? "Add a note for the DevOps agent…" : "Add a note for the CEO…").foregroundStyle(Color.muted), axis: .vertical)
                    .textFieldStyle(.plain).font(.s13).lineLimit(1...5).focused($noteFocused)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .lifted(focused: noteFocused)
                    .onChange(of: noteFocused) { _, on in model.typing = on }
                    .onDisappear { model.typing = false }
                    .help("Optional. The CEO reads it before proposing anything similar.")
            }
            if let failure { Text(failure).font(.s13m).foregroundStyle(Color.stuck).fixedSize(horizontal: false, vertical: true) }
        }
        .onChange(of: model.answerKey) { _, k in
            guard model.openQuestion?.decision.id == decision.id, !sending else { return }
            pending = k.yes; failure = nil
        }
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

private struct Part<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(title)
            content
        }
    }
}

private struct Prose: View {
    let text: String
    var body: some View {
        Text(BriefingCard.plain(text)).font(.s13).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true)
    }
}

/// The evidence: its links open in the browser, a path into the factory folder opens in Finder, other lines are text.
private struct Evidence: View {
    let text: String; let root: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let links = FactoryText.links(line)
                if !links.isEmpty {
                    ForEach(links, id: \.url) { l in
                        Button { if let u = URL(string: l.url) { NSWorkspace.shared.open(u) } } label: {
                            HStack(spacing: 4) { Text(l.title).font(.s13m).lineLimit(1); PixelIcon("chev", color: .muted, size: 9) }.foregroundStyle(Color.inkText)
                        }.buttonStyle(.plain).help(l.url)
                    }
                } else if let path = Self.path(in: line) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root + "/" + path)]) } label: {
                        HStack(spacing: 6) { PixelIcon("folder", color: .muted, size: 9); Text(BriefingCard.plain(line)).font(.s13).lineLimit(2) }.foregroundStyle(Color.inkText)
                    }.buttonStyle(.plain).help(root + "/" + path)
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        PixelIcon("check", color: .done, size: 9).padding(.top, 4)
                        Text(BriefingCard.plain(line)).font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    }
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

/// The Server room's DevOps agent (D49): its rhythm and last run, Run now and the log, its open alerts and questions,
/// and what its last journal said.
struct OpsCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let ops = model.world.ops, alerts = EngineRoom.openAlerts(), running = model.devopsState?.running == true
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PixelIcon("hand", color: .inkText)
                Text("DevOps agent").font(.s15b).foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                if running { Tag("Running", tone: .work, icon: "dot") }
            }
            if let st = model.devopsState {
                Text("\(st.config.summary) · \(st.config.runtime.label)\(st.last.map { " · last run \($0.started.ago), \($0.outcome.rawValue)" } ?? "")")
                    .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                if let b = st.blocked { Text(b.text).font(.s13).foregroundStyle(b.waitsForYou ? Color.warn : Color.muted) }
            }
            ForEach(alerts.prefix(3), id: \.id) { a in
                HStack(spacing: 6) { PixelIcon("warn", color: .warn, size: 9); Text("\(a.id) \(a.title)").font(.s13m).foregroundStyle(Color.warn).lineLimit(1) }
            }
            if let open = ops?.factory?.openDecisions, !open.isEmpty {
                ForEach(open) { d in
                    Button { model.controller.select(decision: d.id, in: World.opsID) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            QuestMarker(glyph: "server", size: 20)
                            Text(d.title).font(.s13m).foregroundStyle(Color.inkText).multilineTextAlignment(.leading).lineLimit(2)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(CardPressStyle())
                }
            }
            if let b = ops?.factory?.briefing, !b.briefing.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(b.briefing.prefix(3), id: \.self) { Text("· " + $0).font(.s13).foregroundStyle(Color.inkText).lineLimit(2) }
                }
            }
            HStack(spacing: 8) {
                Button { model.runDevOpsNow() } label: { SpelLabel(running ? "Running" : "Run now", icon: "play") }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).disabled(running)
                if model.devopsState?.last != nil {
                    Button { model.watchRun(root: EngineRoom.folder.path, name: "DevOps") } label: { SpelLabel("Log", icon: "log") }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s)).help("The DevOps agent's run log, in the terminal")
                }
            }
        }
        .spelCard()
    }
}

// MARK: setting a factory up (D4, D76)

/// A factory without its starter files (D4): first the two choices that matter, in plain words (what the CEO may do on
/// its own, when it runs), and the files behind one line. Start the factory writes only what is ticked and missing;
/// nothing that is there is ever replaced.
private struct SetUpFactoryCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    @State private var plan: [StarterFile] = []
    @State private var ticked: Set<String> = []
    @State private var open: String?
    @State private var showFiles = false
    @State private var editCommit = true

    private static let allowlist = ".claude/settings.json"

    var body: some View {
        let hb = model.projectSettings.entry(project.root)?.heartbeat
        let factoryFiles = plan.filter { $0.path != Self.allowlist }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) { QuestMarker(size: 20); Text("Set up this factory").font(.s15b).foregroundStyle(Color.inkText) }
            Text("What may the CEO do on its own?").font(.s13m).foregroundStyle(Color.inkText)
            VStack(spacing: 8) {
                choice("Ask first", "Asks before every change.", on: !editCommit) { setEditCommit(false) }
                choice("Edit and commit", "Asks before push and merge.", on: editCommit) { setEditCommit(true) }
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Color.muted, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ship").font(.s15).foregroundStyle(Color.muted)
                        Text("Unlocks after five yeses in a row.").font(.s13).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.border, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                .accessibilityElement(children: .combine).accessibilityLabel("Ship: unlocks after five yeses in a row")
            }
            if let hb {
                HStack(spacing: 10) {
                    Text("Runs at \(hb.times.first ?? "07:10")").font(.s13m).foregroundStyle(Color.inkText)
                    Spacer(minLength: 0)
                    LiftedSegments(items: [.init(id: Heartbeat.Days.weekdays, title: "Weekdays"), .init(id: .everyDay, title: "Daily")], selected: hb.days,
                                   padding: EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9)) { d in model.updateHeartbeat(project.root) { $0.days = d } }
                }
            }
            Button { withAnimation(.easeOut(duration: 0.15)) { showFiles.toggle() } } label: {
                HStack(spacing: 8) {
                    PixelIcon("folder", color: .muted)
                    Text("\(factoryFiles.count) files in factory/").font(.s13m).foregroundStyle(Color.inkText)
                    Spacer(minLength: 0)
                    Text(showFiles ? "Hide files" : "View files").font(.s13m).foregroundStyle(Color.inkText)
                    PixelIcon(showFiles ? "chevd" : "chev", color: .muted, size: 9)
                }
                .spelWell(pad: 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFiles { VStack(spacing: 6) { ForEach(plan) { f in row(f) } } }
            HStack(spacing: 8) {
                let n = plan.filter { ticked.contains($0.path) && !$0.exists }.count
                Button { create() } label: { SpelLabel("Start the factory", key: "↩", onYellow: true) }
                    .buttonStyle(SpelButtonStyle(kind: .primary)).keyboardShortcut(.return, modifiers: [])
                    .disabled(n == 0 && plan.allSatisfy { !$0.exists || $0.optional })
                    .help(n == 0 ? "Everything is there already" : "Writes \(n) file\(n == 1 ? "" : "s"); nothing that is there is replaced")
                Button { Self.copy(plan) } label: { Text("Copy instead") }.buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                    .help("Copies every file with its path, to write them yourself")
            }
        }
        .spelCard(flag: .signal)
        .onAppear {
            plan = model.setupPlan(project)
            ticked = Set(plan.filter { !$0.optional && !$0.exists }.map(\.path))
            setEditCommit(true)
            if let d = model.debugViewFile { open = d; showFiles = true }
        }
        .onChange(of: model.debugViewFile) { _, d in open = d; if d != nil { showFiles = true } }
    }

    private func setEditCommit(_ on: Bool) {
        editCommit = on
        guard plan.contains(where: { $0.path == Self.allowlist && !$0.exists }) else { return }
        if on { ticked.insert(Self.allowlist) } else { ticked.remove(Self.allowlist) }
    }

    private func choice(_ title: String, _ text: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().strokeBorder(on ? Color.selection : Color.muted, lineWidth: 2)
                    if on { Circle().fill(Color.selection).padding(5) }
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.s15).foregroundStyle(Color.inkText)
                    Text(text).font(.s13).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
            }
            .spelCard(selected: on, fill: on ? .raised : .surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private func row(_ f: StarterFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if f.exists {
                    PixelIcon("check", color: .muted, size: 9).frame(width: 18, height: 18)
                } else {
                    let on = ticked.contains(f.path)
                    Button { if on { ticked.remove(f.path) } else { ticked.insert(f.path) } } label: {
                        RoundedRectangle(cornerRadius: 4).fill(on ? Color.lit : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(on ? Color.white : Color.muted, lineWidth: 2))
                            .overlay(PixelIcon("check", color: .onSignal, size: 9).opacity(on ? 1 : 0))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.path).accessibilityValue(on ? "will be created" : "not created").accessibilityAddTraits(.isToggle)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.path).font(.mono11).foregroundStyle(Color.inkText)
                    Text(f.exists ? "Already there: left as it is" : f.why).font(.s11n).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(open == f.path ? "Hide" : "View") { open = open == f.path ? nil : f.path }
                    .buttonStyle(SpelButtonStyle(kind: .ghost, size: .s))
            }
            if open == f.path {
                ScrollView { Text(f.text).font(.mono11).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 170).spelWell(pad: 8)
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up. Run the first beat now?").font(.s15b).foregroundStyle(Color.inkText)
            Text("The CEO reads the project, writes a briefing and asks its first question. It changes nothing without your yes: it starts on Assistant.")
                .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { model.runNow(project); model.justSetUp = nil } label: { SpelLabel("Run now", icon: "play", onYellow: true) }
                    .buttonStyle(SpelButtonStyle(kind: .primary, size: .s))
                Button { model.justSetUp = nil } label: { Text("At its next beat") }.buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
            }
        }
        .spelCard(flag: .signal)
    }
}
