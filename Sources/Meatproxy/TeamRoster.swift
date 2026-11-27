import SwiftUI
import FactoryCore
import FactoryCollector

/// Who a factory's CEO may call in, and how many of each at once (D79): a row per profile with a counter. The CEO is
/// always there. There is no maximum but yours: the team's size is the sum. On a floor you choose between the campus
/// default and its own team; without a project this edits the campus default itself.
struct TeamRoster: View {
    @EnvironmentObject private var model: AppModel
    /// nil: the campus default
    let project: Project?
    @State private var more = false
    @State private var faces = 0
    @State private var adding = false
    @State private var removing: AgentProfile?

    private var root: String? { project?.root }
    private var current: (team: AgentTeam, own: Bool) {
        project.map { model.team($0.root) } ?? (model.projectSettings.defaultTeam, false)
    }
    private var working: [String: Int] { project.map(TeamUsage.working) ?? [:] }

    /// the first five always show; the rest when they are on the team, or when you open "more"
    private var shown: [AgentProfile] {
        let all = model.profiles(root), team = current.team
        return all.enumerated().filter { k, p in k < 5 || team.count(p.name) > 0 || more }.map(\.element)
    }

    var body: some View {
        let (team, own) = current
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let project { choice(project, team: team, own: own) } else { Eyebrow("Default team · \(team.size)") }
                Spacer(minLength: 0)
                Button { adding.toggle() } label: { PixelIcon(adding ? "close" : "plus", color: .inkText) }
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: true))
                    .help("A profile of your own: a name, what it may do, its model and its look. Every floor can use it.")
                    .accessibilityLabel(adding ? "Cancel the new profile" : "New profile")
            }
            if adding { NewProfileForm { adding = false; more = true } }
            VStack(spacing: 0) {
                ceoRow
                ForEach(shown) { p in
                    RowDivider()
                    row(p, team: team)
                }
                let hidden = model.profiles(root).count - shown.count
                if hidden > 0 || more {
                    RowDivider()
                    Button { withAnimation(.easeOut(duration: 0.15)) { more.toggle() } } label: {
                        HStack(spacing: 6) {
                            PixelIcon(more ? "up" : "chevd", color: .muted, size: 9)
                            Text(more ? "Fewer profiles" : rest).font(.s13m).foregroundStyle(Color.muted).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .spelCard(pad: 0)
            Text("In all \(team.size) agent\(team.size == 1 ? "" : "s") may work here at once: the sum of your numbers. No limit but yours.")
                .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            if let project {
                if project.provider == .claude { TeamFilesCard(project: project) }
                else {
                    Text("Codex has no agent files: its CEO follows only the numbers in mandate.yml.")
                        .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .alert("Remove the \(removing?.label ?? "") profile?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let r = removing { model.removeProfile(r.name) }; removing = nil }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("It leaves every team that has it. Agent files already written for it stay in their projects.")
        }
        .task(id: model.profiles(root).map(\.name)) {
            await model.controller.ensurePortraits(([.ceo] + model.profiles(root).map(\.role)).map(key))
            faces += 1
        }
    }

    private var rest: String {
        let names = model.profiles(root).dropFirst(5).map(\.label)
        guard let last = names.last else { return "More profiles" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// one face per role, the same on every roster (a floor's Team tab and the default team in Settings); the CEO is
    /// the one on the floor (AppModel.ceo, the floor's own source)
    private func key(_ r: CastRole) -> CastKey {
        if r == .ceo, let project { return model.ceo(of: project).cast }
        return CastKey(role: r, seed: "team")
    }

    private func face(_ r: CastRole) -> some View {
        let _ = faces
        return Portrait(image: model.controller.portrait(key(r)), role: r, size: 40)
    }

    /// the campus default or this floor's own team (C1): a segmented choice, white when chosen
    private func choice(_ project: Project, team: AgentTeam, own: Bool) -> some View {
        let campus = model.projectSettings.defaultTeam
        return LiftedSegments(items: [.init(id: false, title: "Campus default · \(campus.size)"), .init(id: true, title: own ? "Own team · \(team.size)" : "Own team")],
                              selected: own) { o in
            model.followCampusTeam(project.root, !o)
        }
        .accessibilityLabel("Which team this floor uses")
    }

    private var ceoRow: some View {
        HStack(spacing: 10) {
            face(.ceo)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(Color.role(.ceo)).frame(width: 8, height: 8); Text("CEO").font(.s15).foregroundStyle(Color.inkText) }
                Text("Hands out the work").font(.s13).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 6)
            HStack(spacing: 5) { PixelIcon("lock", color: .muted, size: 9); Text("Always 1").font(.s13).foregroundStyle(Color.muted) }
                .help("Every factory has its CEO: it cannot be taken off the team")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func row(_ p: AgentProfile, team: AgentTeam) -> some View {
        let n = team.count(p.name), now = working[p.name] ?? 0
        return HStack(spacing: 10) {
            face(p.role)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(Color.role(p.role)).frame(width: 8, height: 8); Text(p.label).font(.s15).foregroundStyle(Color.inkText) }
                Text(n == 0 ? "None on this team" : "\(model.model(p, root: root).capitalized) · \(p.may)")
                    .font(.s13).foregroundStyle(Color.muted).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                if now > 0 {
                    HStack(spacing: 4) {
                        if now > n { PixelIcon("warn", color: .warn, size: 9) }
                        Text(now > n ? "\(now) working now, \(n) allowed" : "\(now) working now").font(.s12).foregroundStyle(now > n ? Color.warn : Color.muted)
                    }
                    .help(now > n ? "More ran at once than the team allows. Claude Code has no limit per type of its own: the number is an agreement the CEO follows." : "")
                }
            }
            Spacer(minLength: 6)
            if project == nil && model.isCustom(p.name) {
                Button { removing = p } label: { PixelIcon("close", color: .muted, size: 9) }
                    .buttonStyle(SpelButtonStyle(kind: .ghost, size: .s, square: true)).accessibilityLabel("Remove the \(p.label) profile")
                    .help("Remove this profile from every team (its agent files stay where they are)")
            }
            counter(p, n)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    /// − n +: chunky keys round the number (it changes here, at once)
    private func counter(_ p: AgentProfile, _ n: Int) -> some View {
        HStack(spacing: 6) {
            Button { change(p.name, n - 1) } label: { PixelIcon("minus", color: .inkText, size: 9) }
                .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: true)).disabled(n == 0).accessibilityLabel("One \(p.label) fewer")
            Text("\(n)").font(.s15b.monospacedDigit()).foregroundStyle(Color.inkText).frame(minWidth: 16)
                .accessibilityLabel("\(n) \(p.label)")
            Button { change(p.name, n + 1) } label: { PixelIcon("plus", color: .inkText, size: 9) }
                .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: true)).accessibilityLabel("One \(p.label) more")
        }
    }

    private func change(_ name: String, _ n: Int) {
        if let root { model.setTeam(root) { $0.set(name, n) } }
        else { model.setDefaultTeam { $0.set(name, n) } }
    }
}

/// The agent files a floor's team still needs: shown first, written on Create, never replacing what is there.
private struct TeamFilesCard: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    @State private var open: String?

    @State private var showing = false
    var body: some View {
        let missing = model.teamFiles(project).filter { !$0.exists }
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PixelIcon("file", color: .inkText)
                    Text("Create \(missing.count) agent file\(missing.count == 1 ? "" : "s")?").font(.s15b).foregroundStyle(Color.inkText)
                }
                Text("They become Claude Code sub-agents in .claude/agents/. Nothing that is there is ever replaced.")
                    .font(.s13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                if showing {
                    ForEach(missing) { f in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.path).font(.mono12).foregroundStyle(Color.inkText)
                                    Text(f.why).font(.s12).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Button(open == f.path ? "Hide" : "View") { open = open == f.path ? nil : f.path }.buttonStyle(SpelButtonStyle(kind: .ghost, size: .s))
                            }
                            if open == f.path {
                                ScrollView { Text(f.text).font(.mono12).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                    .frame(maxHeight: 170).spelWell(pad: 8)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button { model.createTeamFiles(project, files: missing) } label: { SpelLabel("Create \(missing.count) file\(missing.count == 1 ? "" : "s")", onYellow: true) }
                        .buttonStyle(SpelButtonStyle(kind: .primary, size: .s))
                    Button { showing.toggle() } label: { SpelLabel(showing ? "Hide files" : "View files", icon: "eye", iconColor: .inkText) }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
                    Button { AppModel.copy(missing.map { "=== \($0.path)\n\($0.text)" }.joined(separator: "\n")) } label: { PixelIcon("copy", color: .inkText) }
                        .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s, square: true)).help("Copy them instead, to write them yourself").accessibilityLabel("Copy the files")
                }
            }
            .spelCard(flag: .signal)
        }
    }
}

/// A profile of your own (D79): a name (its file and sub-agent type), what it may do, a model, how much it may touch
/// and the outfit it wears on the floor.
private struct NewProfileForm: View {
    @EnvironmentObject private var model: AppModel
    let done: () -> Void
    @State private var name = ""
    @State private var may = ""
    @State private var llm = "sonnet"
    @State private var access = CustomProfile.Access.read
    @State private var look = CastRole.researcher
    @State private var tried = false

    private var problem: String? { CustomProfile.check(name, taken: model.profiles(nil).map(\.name)) }
    static let looks: [CastRole] = [.researcher, .dev, .tester, .designer, .pm, .devops, .marketing, .sales]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("New profile").font(.s15b).foregroundStyle(Color.inkText)
            field("Name", hint: "code-reviewer") { TextField("code-reviewer", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Profile name") }
            if tried, let problem { Text(problem).font(.s13).foregroundStyle(Color.warn) }
            field("May do", hint: nil) { TextField("Reviews pull requests, changes nothing", text: $may).textFieldStyle(.roundedBorder).accessibilityLabel("What it may do") }
            field("Touches", hint: nil) {
                Picker("Touches", selection: $access) { ForEach(CustomProfile.Access.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .labelsHidden().pickerStyle(.menu)
            }
            field("Model", hint: nil) {
                Picker("Model", selection: $llm) { ForEach(["opus", "sonnet", "haiku"], id: \.self) { Text($0.capitalized).tag($0) } }
                    .labelsHidden().pickerStyle(.segmented)
            }
            field("Looks like", hint: nil) {
                Picker("Looks like", selection: $look) { ForEach(Self.looks, id: \.self) { Text($0.label).tag($0) } }
                    .labelsHidden().pickerStyle(.menu)
            }
            HStack(spacing: 8) {
                Button("Add profile") {
                    tried = true
                    guard problem == nil else { return }
                    model.addProfile(CustomProfile(name: name.trimmingCharacters(in: .whitespaces), may: may.trimmingCharacters(in: .whitespaces),
                                                   model: llm, access: access, look: look))
                    done()
                }
                .buttonStyle(SpelButtonStyle(kind: .primary, size: .s))
                Button("Cancel", action: done)
                    .buttonStyle(SpelButtonStyle(kind: .secondary, size: .s))
            }
            Text("It becomes .claude/agents/\(name.isEmpty ? "<name>" : name).md on a floor that puts it on its team, shown to you first.")
                .font(.s12).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
        .spelCard(selected: true)
    }

    private func field<V: View>(_ label: String, hint: String?, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.s13).foregroundStyle(Color.muted).frame(width: 74, alignment: .leading)
            content()
        }
    }
}
