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
        VStack(alignment: .leading, spacing: 10) {
            if let project { choice(project, team: team, own: own) }
            VStack(spacing: 0) {
                ceoRow
                ForEach(shown) { p in
                    Divider().overlay(Color.divider)
                    row(p, team: team)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
            let hidden = model.profiles(root).count - shown.count
            if hidden > 0 || more {
                Button { withAnimation(.easeOut(duration: 0.15)) { more.toggle() } } label: {
                    Text(more ? "Fewer profiles" : "+ " + rest)
                        .font(.system(size: 12)).foregroundStyle(Color.muted).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).frame(minHeight: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Text("In all \(team.size) agent\(team.size == 1 ? "" : "s") may work here at once: the sum of your numbers. No limit but yours.")
                .font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            if let project {
                if project.provider == .claude { TeamFilesCard(project: project) }
                else {
                    Text("Codex has no agent files: its CEO follows only the numbers in mandate.yml.")
                        .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
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

    /// one face per role on this roster, the same every time; the CEO is the one on the floor (seeded by the project)
    private func key(_ r: CastRole) -> CastKey {
        if r == .ceo, let root { return CastKey(role: .ceo, seed: "ceo:" + root) }
        return CastKey(role: r, seed: "team:" + (root ?? "campus"))
    }

    private func face(_ r: CastRole, dim: Bool = false) -> some View {
        let _ = faces
        return Avatar(cg: model.controller.portrait(key(r))).frame(width: 34, height: 34).opacity(dim ? 0.5 : 1)
    }

    private func choice(_ project: Project, team: AgentTeam, own: Bool) -> some View {
        let campus = model.projectSettings.defaultTeam
        return HStack(spacing: 6) {
            option("Campus default", "\(campus.size) agent\(campus.size == 1 ? "" : "s")", on: !own) { model.followCampusTeam(project.root, true) }
            option("Own team", own ? "\(team.size) agent\(team.size == 1 ? "" : "s")" : "Starts from the default", on: own) { model.followCampusTeam(project.root, false) }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Which team this floor uses")
    }

    private func option(_ title: String, _ detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: on ? .bold : .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
            .background(on ? Color.raised : Color.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.signal : Color.divider, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var ceoRow: some View {
        HStack(spacing: 10) {
            face(.ceo)
            VStack(alignment: .leading, spacing: 1) {
                Text("CEO").font(.system(size: 13, weight: .semibold))
                Text("Hands the work out").font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 6)
            Label("Always 1", systemImage: "lock.fill").font(.system(size: 11.5)).foregroundStyle(Color.muted)
                .help("Every factory has its CEO: it cannot be taken off the team")
        }
        .padding(.vertical, 6)
    }

    private func row(_ p: AgentProfile, team: AgentTeam) -> some View {
        let n = team.count(p.name), now = working[p.name] ?? 0
        return HStack(spacing: 10) {
            face(p.role, dim: n == 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(n == 0 ? Color.muted : Color.inkText)
                Text(n == 0 ? "None on this team" : "\(model.model(p, root: root).capitalized) · \(p.may)")
                    .font(.system(size: 11)).foregroundStyle(Color.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if now > 0 {
                    Text(now > n ? "\(now) working now, \(n) allowed" : "\(now) working now")
                        .font(.system(size: 11, weight: now > n ? .semibold : .regular)).foregroundStyle(now > n ? Color.warn : Color.muted)
                        .help(now > n ? "More ran at once than the team allows. Claude Code has no limit per type of its own: the number is an agreement the CEO follows." : "")
                }
            }
            Spacer(minLength: 6)
            counter(p, n)
        }
        .padding(.vertical, 6)
    }

    private func counter(_ p: AgentProfile, _ n: Int) -> some View {
        HStack(spacing: 0) {
            Button { change(p.name, n - 1) } label: { Image(systemName: "minus").frame(width: 26, height: 26).contentShape(Rectangle()) }
                .buttonStyle(.plain).disabled(n == 0).accessibilityLabel("One \(p.label) fewer")
            Text("\(n)").font(.system(size: 13, weight: .bold).monospacedDigit()).frame(minWidth: 22)
                .accessibilityLabel("\(n) \(p.label)")
            Button { change(p.name, n + 1) } label: { Image(systemName: "plus").frame(width: 26, height: 26).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("One \(p.label) more")
        }
        .font(.system(size: 11, weight: .bold)).foregroundStyle(n == 0 ? Color.muted : Color.inkText)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(n == 0 ? Color.divider : Color.muted.opacity(0.7)))
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

    var body: some View {
        let missing = model.teamFiles(project).filter { !$0.exists }
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(missing.count) agent file\(missing.count == 1 ? "" : "s") to create").font(.system(size: 13, weight: .bold))
                    Text("Each profile becomes a Claude Code sub-agent in .claude/agents/. Nothing is written until you press Create, and a file that is there is never replaced.")
                        .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(missing) { f in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.path).font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                Text(f.why).font(.system(size: 11)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 8) {
                    Button { model.createTeamFiles(project, files: missing) } label: { Text("Create \(missing.count) file\(missing.count == 1 ? "" : "s")") }
                        .buttonStyle(TactileButtonStyle(kind: .primary, inset: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)))
                    Button { AppModel.copy(missing.map { "=== \($0.path)\n\($0.text)" }.joined(separator: "\n")) } label: { Text("Copy them instead") }
                        .buttonStyle(TactileButtonStyle(kind: .neutral, inset: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)))
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.signal.opacity(0.7)))
        }
    }
}
