import SwiftUI
import AppKit
import FactoryCore
import FactoryCollector
import FactoryScenes

/// The inspector (C1–C10): whoever or whatever you selected, as a character card or a building's card. Its head is
/// the crest, the name and the close button; on a floor the folder tabs stay with it, and only the tab's body scrolls.
struct InspectorPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sel = model.selection
        VStack(alignment: .leading, spacing: 14) {
            content(sel)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spelFrame()
        .id(contentKey(sel))
        .transition(reduceMotion ? .identity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
        .animation(reduceMotion ? nil : Motion.arrive, value: contentKey(sel))
        .accessibilityElement(children: .contain).accessibilityLabel("Inspector")
    }

    /// which card the inspector shows: a new one fades in, the old one out
    private func contentKey(_ s: WorldSelection) -> String {
        [s.engineRoom ? "engine" : "", s.provider?.rawValue ?? "", s.projectID ?? "", s.sessionID ?? "", s.subAgentID ?? "", s.decisionID ?? "", s.workstreamID ?? "", s.serverID ?? ""].joined(separator: "|")
    }

    private func up() { model.controller.up() }

    @ViewBuilder private func content(_ s: WorldSelection) -> some View {
        if s.engineRoom, s.decisionID == nil, let id = s.serverID, let server = model.world.servers.first(where: { $0.id == id }) {
            InspectorHead(eyebrow: "\(server.kind.label) · Server room", title: server.name, close: up) {
                Socket(size: 44) { PixelIcon("server", color: .inkText) }
            }
            ScrollFit { ServerDetail(server: server).padding(.bottom, 4) }
        } else if s.engineRoom && s.decisionID == nil {
            InspectorHead(eyebrow: "Building · \(model.world.racks.count) racks", title: "Server room", close: up) {
                Socket(size: 44) { PixelIcon("server", color: .inkText) }
            }
            ScrollFit { ServerRoomCard(picked: s.serverID).padding(.bottom, 4) }
        } else if let a = s.subAgentID, let (_, owner) = model.session(s.sessionID), let sub = owner.subAgents.first(where: { $0.id == a }) {
            CharHead(image: model.controller.portrait(sub.cast), role: sub.cast.role, name: sub.persona.name,
                     mood: sub.finished ? "Finished" : "Running", tone: sub.finished ? .done : .working, place: "helper of \(owner.persona.name)", close: up)
            ScrollFit {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) { PixelIcon("person", color: .muted); Text(sub.type).font(.s15b).foregroundStyle(Color.inkText) }
                    Text(sub.summary.isEmpty ? "No description" : sub.summary).font(.s13).foregroundStyle(Color.inkText)
                        .fixedSize(horizontal: false, vertical: true).spelWell(pad: 12).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Helper of \(owner.persona.name) · \(owner.title)").font(.s13).foregroundStyle(Color.muted)
                }
                .padding(.bottom, 4)
            }
        } else if let (p, session) = model.session(s.sessionID) {
            let st = session.state(now: model.world.now), cast = model.cast(of: session)
            CharHead(image: model.controller.portrait(cast), role: cast.role, name: session.persona.name,
                     mood: SessionCard.mood(session, st), tone: st == .waiting ? .quest : st == .stuck ? .stuck : st == .done ? .done : .working,
                     place: nil, close: up)
            ScrollFit { SessionDetail(project: p, session: session).padding(.bottom, 4) }
        } else if let id = s.decisionID, let pid = s.projectID, let (p, d) = model.world.decision(project: pid, id) {
            // what it asks in plain words; its id (D-0008) only on hover, for whoever reads the files
            InspectorHead(eyebrow: (d.isTodo ? d.plainKind : "Question · " + d.plainKind) + (d.asked.map { " · " + $0.ago } ?? ""),
                          title: d.title, marker: d.status == .open, titleLines: 5, close: up,
                          closeHelp: "Back to \(p.name) (Esc)") { EmptyView() }
                .help(d.id)
            ScrollFit { DecisionCard(project: p, decision: d).padding(.bottom, 4) }
        } else if let id = s.workstreamID, let pid = s.projectID, let p = model.world.project(id: pid), let w = p.factory?.workstreams.first(where: { $0.id == id }) {
            InspectorHead(eyebrow: "Workstream · \(w.type)", title: w.title, titleLines: 3, close: up, closeHelp: "Back to \(p.name) (Esc)") { EmptyView() }
            ScrollFit { WorkstreamCard(project: p, workstream: w).padding(.bottom, 4) }
        } else if let id = s.projectID, let p = model.world.project(id: id) {
            InspectorHead(eyebrow: floorEyebrow(p), title: p.name, close: up) {
                Socket(size: 44) {
                    if p.logo != nil { ProjectLogoView(path: p.logo, size: 28) } else { PixelIcon(p.isChat ? "chat" : "floor", color: .inkText) }
                }
            }
            FloorTabs(project: p).id(p.id)
        } else if let prov = s.provider, let b = model.world.building(prov) {
            InspectorHead(eyebrow: "Tower · \(b.projects.count) floor\(b.projects.count == 1 ? "" : "s")", title: prov.displayName, close: up) {
                Socket(size: 44) { PixelIcon(prov == .claude ? "burst" : "star", color: Color.provider(prov)) }
            }
            ScrollFit { BuildingFloors(building: b).padding(.bottom, 4) }
        }
    }

    /// "FLOOR 2 · CLAUDE TOWER", "CHATS · CLAUDE TOWER"; the provider's colour stays out of it (E5)
    private func floorEyebrow(_ p: Project) -> String {
        let tower = "\(p.provider.displayName) tower"
        guard let b = model.world.building(p.provider), let k = b.projects.firstIndex(where: { $0.id == p.id }) else { return tower }
        return p.isChat ? "Chats · \(tower)" : "Floor \(k + 1) · \(tower)"
    }
}

/// A person's head (C5): the portrait from the cast, the name at 26, the role as a tag, and how they are, once.
struct CharHead: View {
    let image: CGImage?
    let role: CastRole
    let name: String
    let mood: String
    enum Tone { case quest, working, done, stuck, calm }
    let tone: Tone
    let place: String?
    let close: () -> Void
    var body: some View {
        let c: Color = tone == .quest ? .signal : tone == .working ? .working : tone == .done ? .done : tone == .stuck ? .stuck : .muted
        HStack(alignment: .center, spacing: 12) {
            Portrait(image: image, role: role, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.s26).foregroundStyle(Color.inkText).lineLimit(1)
                RoleTag(role: role)
                HStack(spacing: 5) {
                    PixelIcon(tone == .stuck ? "sq" : tone == .quest ? "bang" : "dot", color: c).frame(width: 18, height: 18)
                    Text(mood).font(.s13m).foregroundStyle(c).lineLimit(1)
                    if let place { Text("· " + place).font(.s13).foregroundStyle(Color.muted).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            CloseButton(action: close).frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: a building

/// A tower's floors, top floor first (E5): a number, the name, how many people, today's API price; a factory whose CEO
/// needs a look carries an amber edge and says so with a triangle and a word.
private struct BuildingFloors: View {
    @EnvironmentObject private var model: AppModel
    let building: ProviderBuilding
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if building.projects.isEmpty { Text("No sessions in the last 8 hours.").font(.s13).foregroundStyle(Color.muted) }
            ForEach(Array(building.projects.enumerated().reversed()), id: \.element.id) { k, p in
                let line = p.factory != nil ? model.factoryLine(p) : nil
                let waiting = model.world.needsYou.filter { $0.project.id == p.id }.count   // the quest log's own count for this floor
                Button { model.controller.enterFloor(p.id) } label: {
                    HStack(spacing: 12) {
                        Socket(size: 32) { Text("\(k + 1)").font(.s15b.monospacedDigit()).foregroundStyle(Color.inkText) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.s15).foregroundStyle(Color.inkText).lineLimit(1)
                            Text(people(p)).font(.s13).foregroundStyle(Color.muted).lineLimit(1)
                            if let line, line.warn { Tag(line.text, tone: .warn).padding(.top, 2) }
                        }.layoutPriority(1)
                        Spacer(minLength: 4)
                        // two fixed columns, so badges and prices line up from floor to floor
                        Group { if waiting > 0 { QuestBadge(count: waiting) } }.frame(width: 26, alignment: .center)
                        Text(p.cost.map { $0.today > 0 ? ProjectCost.format($0.today) : "" } ?? "").font(.s13m.monospacedDigit()).foregroundStyle(Color.inkText)
                            .lineLimit(1).fixedSize().frame(width: 56, alignment: .trailing)
                            .help("Today at API prices (an estimate)")
                    }
                    .spelCard(flag: line?.warn == true ? .warn : nil, pad: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CardPressStyle())
                .accessibilityLabel("Floor \(k + 1), \(p.name)")
            }
        }
    }
    private func people(_ p: Project) -> String {
        let n = p.sessions.count
        return n == 0 ? "Quiet" : "\(n) \(n == 1 ? "person" : "people")"
    }
}

// MARK: the Server room

/// The Server room building: the DevOps agent, the status pages and the racks, problems first.
private struct ServerRoomCard: View {
    @EnvironmentObject private var model: AppModel
    let picked: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.projectSettings.devops.enabled { OpsCard() }
            ServicesCard()
            if model.world.servers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No servers set up yet. They are checked over SSH with your own keys, without a password.")
                        .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    Button { model.settingsAtForm = true; model.settingsOpen = true } label: { SpelLabel("Set up servers", icon: "gear", onYellow: true) }
                        .buttonStyle(SpelButtonStyle(kind: .primary))
                }
                .spelCard()
            } else {
                let s = model.world.serverSummary
                SectionHead("Racks · \(model.world.racks.count)", icon: "server") {
                    HStack(spacing: 6) {
                        if s.down > 0 { Tag("\(s.down) down", tone: .stuck) }
                        if s.warn > 0 { Tag("\(s.warn) warning", tone: .warn) }
                    }
                }
                VStack(spacing: 8) {
                    ForEach(problemsFirst) { server in
                        Button { model.controller.select(server: server.id) } label: { ServerRow(server: server, picked: server.id == picked).contentShape(Rectangle()) }
                            .buttonStyle(CardPressStyle())
                    }
                }
            }
        }
    }
    private var problemsFirst: [Server] {
        let rank: (Server) -> Int = { $0.state == .down ? 0 : $0.state == .warn ? 1 : 2 }
        return model.world.racks.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}

/// One server, deploy or backup: its state as shape and colour, its name and kind, and what the check saw.
private struct ServerRow: View {
    @EnvironmentObject private var model: AppModel
    let server: Server
    var picked = false
    var body: some View {
        let asks = model.world.ops.flatMap { AppModel.question(about: server.name, in: $0) } != nil
        let light: StateLight.S = server.state == .down ? .down : server.state == .warn ? .warn : .ok
        // one signal each: the state as shape, colour and word (also with a question), the flag in the state's colour,
        // and a question as a small yellow chip of its own
        HStack(spacing: 10) {
            StateLight(state: light)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name).font(.mono).foregroundStyle(Color.inkText).lineLimit(1).fixedSize()
                    Tag(server.kind.label)
                }
                if let d = server.detail {
                    Text(d).font(.s11n).foregroundStyle(server.state == .ok ? Color.muted : color).lineLimit(1).layoutPriority(1)
                }
            }
            Spacer(minLength: 6)
            if server.state != .ok { Text(server.state.label).font(.s13m).foregroundStyle(color).lineLimit(1).fixedSize() }
            if asks {
                Text("1 question").font(.s11).foregroundStyle(Color.onSignal).lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.signal))
            }
        }
        .spelCard(flag: server.state == .down ? .stuck : server.state == .warn ? .warn : nil, selected: picked, pad: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([server.name, light.word, server.detail, asks ? "1 question" : nil].compactMap { $0 }.joined(separator: ", "))
    }
    private var color: Color { server.state == .down ? .stuck : server.state == .warn ? .warn : .done }
}

// MARK: a session (C5)

/// A chat in the inspector (C5): what it does, its question as dialogue, then the one action. Meatproxy cannot type
/// into someone else's running Claude Code session, so the answer happens in the terminal: Take over opens it there,
/// with the question shown above it.
struct SessionDetail: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let session: Session
    var body: some View {
        let st = session.state(now: model.world.now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PixelIcon("chat", color: .muted)
                Text(session.title).font(.s15b).foregroundStyle(Color.inkText).lineLimit(2)
                Text("· \(project.name)").font(.s13).foregroundStyle(Color.muted).lineLimit(1)
            }
            if let said = session.lastSaid?.trimmingCharacters(in: .whitespacesAndNewlines), !said.isEmpty { Bubble(text: said, asks: st == .waiting) }
            if session.inClaudeApp {
                // a chat in the Claude app is answered there (D83): resuming it in a terminal would fork it
                Text(st == .waiting ? "This chat runs in the Claude app: answer it there." : "This chat runs in the Claude app.")
                    .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                Button { model.openInClaude(session) } label: { SpelLabel("Open in Claude", icon: "chat", onYellow: st == .waiting, iconColor: st == .waiting ? .onSignal : .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: st == .waiting ? .primary : .secondary))
                    .help("Bring the Claude app to the front; the chat is in its Code tab")
            } else {
            if st == .waiting {
                Text("Your answer goes in the terminal: Take over continues this chat there, with its question on top.")
                    .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                // take over in the app's terminal (D57): the conversation goes on where the agent left it
                Button { model.takeOver(session) } label: { SpelLabel("Take over", icon: "terminal", onYellow: st == .waiting, iconColor: st == .waiting ? .onSignal : .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: st == .waiting ? .primary : .secondary))
                    .help(session.heartbeatRun == true ? "Stop the CEO's run and continue it yourself in the terminal" : "Continue this conversation in the terminal")
                Button { AppModel.copy(session.resumeCommand) } label: { PixelIcon("copy", color: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, square: true))
                    .help("Copy: \(session.resumeCommand)").accessibilityLabel("Copy the resume command")
                Spacer(minLength: 0)
            }
            }
            if !session.subAgents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Helpers")
                    FlowTags(items: session.subAgents.map { a in (a.id, "\(a.type) · \(a.finished ? "done" : "busy")", a.finished ? Tag.Tone.done : .work) }) { id in
                        model.controller.select(session: session.id, subAgent: id)
                    }
                }
            }
            if !session.activities.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Lately")
                    ForEach(Array(session.activities.suffix(6).reversed().enumerated()), id: \.offset) { _, a in
                        HStack(spacing: 8) {
                            if a.failed { PixelIcon("sq", color: .stuck, size: 9) }
                            Text(a.text.prefix(1).uppercased() + a.text.dropFirst()).font(.s13).foregroundStyle(a.failed ? Color.stuck : Color.inkText).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(a.at.ago).font(.s11n).foregroundStyle(Color.muted)
                        }
                    }
                }
            }
        }
    }
}

/// What a chat last said, as a speech balloon: the question it ends with in bold.
private struct Bubble: View {
    let text: String
    let asks: Bool
    var body: some View {
        let t = text.count > 1200 ? "…" + text.suffix(1199) : text
        let (lead, question) = asks ? Self.split(String(t)) : (String(t), "")
        VStack(alignment: .leading, spacing: 6) {
            if !lead.isEmpty { Text(lead).font(.s13).foregroundStyle(asks ? Color.muted : Color.inkText).fixedSize(horizontal: false, vertical: true) }
            if !question.isEmpty { Text(question).font(.s15b).foregroundStyle(Color.inkText).fixedSize(horizontal: false, vertical: true) }
        }
        .textSelection(.enabled)
        .lineLimit(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spelWell(pad: 12)
        .overlay(alignment: .topLeading) {
            // the balloon's tail, towards the portrait
            Rectangle().fill(Color.well).frame(width: 12, height: 12).rotationEffect(.degrees(45))
                .overlay(Rectangle().strokeBorder(Color.divider, lineWidth: 2).rotationEffect(.degrees(45)).mask(Rectangle().padding(.bottom, 6)))
                .offset(x: 18, y: -6).allowsHitTesting(false)
        }
    }
    /// the last sentence that asks something, apart from what came before it
    static func split(_ s: String) -> (String, String) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("?") else { return (trimmed, "") }
        let body = trimmed.dropLast()
        let cut = body.lastIndex { ".!?\n".contains($0) }
        guard let cut else { return ("", trimmed) }
        return (String(trimmed[...cut]).trimmingCharacters(in: .whitespacesAndNewlines), String(trimmed[trimmed.index(after: cut)...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Tags that wrap onto the next line; each one opens what it names.
struct FlowTags<ID: Hashable>: View {
    let items: [(id: ID, text: String, tone: Tag.Tone)]
    let open: (ID) -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tags(items) }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { k in
                    HStack(spacing: 6) { tags(Array(items[k..<min(k + 2, items.count)])) }
                }
            }
        }
    }
    @ViewBuilder private func tags(_ list: [(id: ID, text: String, tone: Tag.Tone)]) -> some View {
        ForEach(Array(list.enumerated()), id: \.offset) { _, i in
            Button { open(i.id) } label: { Tag(i.text, tone: i.tone) }.buttonStyle(CardPressStyle()).help("Show this helper")
        }
    }
}

/// A session as a card on a floor's Work tab: its person, what it is on, and how it is.
struct SessionCard: View {
    @EnvironmentObject private var model: AppModel
    let session: Session
    var body: some View {
        let st = session.state(now: model.world.now), cast = model.cast(of: session)
        HStack(alignment: .center, spacing: 12) {
            Portrait(image: model.controller.portrait(cast), role: cast.role, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.persona.name) · \(session.title)").font(.s15).foregroundStyle(Color.inkText).lineLimit(1)
                HStack(spacing: 5) {
                    PixelIcon(st == .stuck ? "sq" : st == .waiting ? "bang" : st == .done ? "check" : "dot", color: Color.state(st)).frame(width: 18, height: 18)
                    Text(Self.mood(session, st)).font(.s13).foregroundStyle(Color.state(st)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            PixelIcon("chev", color: .muted, size: 9)
        }
        .spelCard(flag: st == .waiting ? .signal : st == .stuck ? .stuck : nil, pad: 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private static func lower(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
    /// how a session is, in one line
    static func mood(_ session: Session, _ st: SessionState) -> String {
        switch st {
        case .waiting: "Waits for you · \(session.lastAt.ago)"
        case .working: "Working · \(lower(session.lastAction))"
        case .stuck: "Stuck · \(lower(session.lastAction))"
        case .done: "Done · \(session.lastAt.ago)"
        }
    }
}

/// Sessions by state as one thin bar.
struct StateBar: View {
    let sessions: [Session]; let now: Date
    var body: some View {
        let counts = SessionState.allCases.map { st in (st, sessions.filter { $0.state(now: now) == st }.count) }.filter { $0.1 > 0 }
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(counts, id: \.0) { st, n in Rectangle().fill(Color.state(st)).frame(width: max(0, (g.size.width - CGFloat(counts.count - 1) * 2) * CGFloat(n) / CGFloat(max(sessions.count, 1)))) }
            }
        }
        .frame(height: 8).padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.well))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.divider, lineWidth: 2))
        .accessibilityElement().accessibilityLabel(counts.map { "\($0.1) \($0.0.label.lowercased())" }.joined(separator: ", "))
    }
}

/// What a floor's work would have cost at API list prices (D61): today, the last 7 days and the last 30. An estimate,
/// also for work under a subscription; tokens of a model without a known price are said, never counted as free.
struct CostLine: View {
    let cost: ProjectCost
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("API price today").font(.s13).foregroundStyle(Color.muted)
                if cost.unpricedTokens > 0 {
                    PixelIcon("help", color: .muted, size: 9)
                        .help("\(cost.unpricedTokens.formatted()) tokens of a model without a known price are not in these sums")
                }
                Spacer(minLength: 6)
                Text(ProjectCost.format(cost.today)).font(.s19.monospacedDigit()).foregroundStyle(Color.inkText)
            }
            Text("\(ProjectCost.format(cost.week)) this week · \(ProjectCost.format(cost.month)) this month").font(.s13).foregroundStyle(Color.muted).lineLimit(1)
        }
        .spelCard()
        .help("What these sessions would have cost through the API, at list prices of \(ApiPrices.asOf). An estimate, not an invoice: under a subscription you pay the plan.")
        .accessibilityElement(children: .combine)
    }
}
