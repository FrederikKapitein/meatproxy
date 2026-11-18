import SpriteKit
import FactoryCore

/// One floor from the inside (the Project level): the atrium (D38). Every session is a person in the room of its phase;
/// pose, face, a ring on the floor and the name tag say its state (D39). Helpers (sub-agents) stand beside their person,
/// smaller. When the work moves on, people walk there: out through the door, round the hall, in through the next door.
/// Click a person for the Session level, a helper for the Sub-agent level.
public final class FloorScene: WorldScene {
    var onSelect: ((_ sessionID: String?, _ subAgentID: String?) -> Void)?
    var onExit: (() -> Void)?
    var onNext: (() -> Void)?
    weak var engine: ArtEngine?

    private(set) var projectID = ""
    private var art: FloorArt?
    private var people: [String: Person] = [:]
    /// Who stands where with which plate (for tests): room, shown state, and the plate's "name|line|state|role|badge".
    func plates() -> [String: (room: String, state: SessionState, plate: String)] { people.mapValues { ($0.room, $0.state, $0.tagKey) } }
    private var marker: SKShapeNode?
    private var lastTime: TimeInterval = 0
    private var clock: TimeInterval = 0
    private(set) var selectedSession: String?
    /// the session whose figure is the project's CEO (it moves on to each next heartbeat run)
    private var ceoFigure: String?
    private(set) var selectedSubAgent: String?
    private var painted = false
    private var walkMap: FloorWalkMap?
    /// rooms forced by debugWalk, so the next refresh does not send them back
    private var debugRooms: [String: String] = [:]

    final class Person {
        /// the session it shows (a CEO's figure moves on to its next run, so this can change)
        var id: String
        /// whose helper it is (nil: a person, or a team member who is free); a team place shows helper `ref` at work
        var owner: String?, ref: String?
        let figure: Figure, scale: CGFloat
        let node = SKSpriteNode(), shadow = Blocky.shadow(18, 9, alpha: 0.28)
        var tag: SKSpriteNode?, emote: SKSpriteNode?, cloud: SKSpriteNode?, ring: SKNode?
        /// the plate's box round its tip (art units), and a helper's tie to its person: a dashed line and a faint ring (B3)
        var tagRect: CGRect = .zero
        var tie: SKShapeNode?, tieRing: SKShapeNode?
        var pos: CGPoint, spot: FloorArt.Spot, room: String
        var path: [CGPoint] = []
        /// tiles walked, for the step cycle; turns still to make on arrival (side, seconds)
        var walked: CGFloat = 0, routeLength: CGFloat = 0, turns: [(dir: String, left: Double)] = []
        var pose = "idle", mood = "calm", dir = "down", tagKey = "", emoteKey = "", name = ""
        var hoverRing: SKShapeNode?, hoverTag: SKSpriteNode?, hoverLift: SKSpriteNode?
        var state: SessionState = .working
        /// what they do while not walking (IdleMotion), set when the floor is applied
        var loop: [IdleMotion.Step] = []
        let phase: Double
        init(id: String, owner: String?, figure: Figure, scale: CGFloat, spot: FloorArt.Spot, room: String) {
            self.id = id; self.owner = owner; self.figure = figure; self.scale = scale; self.spot = spot; self.room = room
            pos = CGPoint(x: spot.i, y: spot.j)
            phase = Double(abs(id.hashValue % 97)) * 0.13
        }
        var walking: Bool { !path.isEmpty }
        /// walking or still turning round on arrival
        var moving: Bool { !path.isEmpty || !turns.isEmpty }
    }

    // MARK: building the floor

    func apply(_ art: FloorArt, project: Project, figures: [String: Figure], now: Date) {
        let fresh = projectID != project.id || !painted
        projectID = project.id
        self.art = art
        if fresh {
            content.removeAllChildren(); people = [:]; marker = nil; painted = true; factoryLayer = nil; factoryKey = "-"; ceoFigure = nil
            let bg = SKSpriteNode(color: SKColor(red: 0.13, green: 0.11, blue: 0.23, alpha: 1), size: CGSize(width: 40000, height: 40000)); bg.zPosition = -2000
            content.addChild(bg)
            if let g = place(art.ground, z: -500) { content.addChild(g) }
            for o in art.objects { content.addChild(place(o.texture, o.rect, z: o.key * 10)) }
            if let l = place(art.light, z: 3000, blend: .screen) { l.alpha = 0.9; content.addChild(l) }
            // each room's plaque hangs on its own wall and sorts with it: people pass in front of it (B4)
            for sg in art.signs {
                guard let n = place(sg.image, z: sg.key.map { $0 * 10 + 0.05 } ?? 3500) else { continue }
                n.name = "sign:" + sg.id
                content.addChild(n)
            }
            // the floor fills the room the panels leave (B9): its plate and walls, not the air round it
            setHome(Self.floorFrame, fill: 1.0)
        }
        if walkMap == nil { walkMap = Self.walkMap(art.solids) }
        // who stands where: each room hands out its spots in a fixed order (everyone first, so the helpers can keep
        // clear of all of them)
        var used: [String: Int] = [:], seen = Set<String>()
        let sessions = project.sessions.sorted(by: { $0.id < $1.id })
        // one CEO per project (D47): a new heartbeat run takes over the figure of the previous one (same person, same
        // place), instead of one walking off and another popping up
        if let run = sessions.first(where: { $0.heartbeatRun == true }), people[run.id] == nil,
           let old = ceoFigure, old != run.id, let p = people[old] {
            people[old] = nil; p.id = run.id; p.node.name = "person:" + run.id; people[run.id] = p
            if selectedSession == old { selectedSession = run.id }
            if hoverTarget == .person(old) { hoverTarget = .person(run.id) }
        }
        ceoFigure = sessions.first(where: { $0.heartbeatRun == true })?.id ?? ceoFigure
        var spots: [String: (spot: FloorArt.Spot, room: FloorRoom)] = [:]
        // a factory's CEO (its main chat) stands at the board in Planning, whatever its run is doing (B1); it carries the
        // factory's open questions
        let ceo = Self.factoryCEO(project)
        for s in sessions {
            if s.id == ceo, debugRooms[s.id] == nil { spots[s.id] = (art.spots["ceo"]?.first ?? Self.ceoSpot, .planning); continue }
            let room = debugRooms[s.id].flatMap(FloorRoom.init(rawValue:)) ?? s.room(now: now)
            spots[s.id] = (takeSpot(room.rawValue, &used), room)
        }
        // the team (D79): every member is always on the floor; a free one waits in the lounge, one at work stands with
        // the session it works for (the same person walks over and back)
        let slots = project.teamSlots
        let placeOf = Dictionary(slots.compactMap { t in t.helper.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        var free: [(slot: TeamSlot, spot: FloorArt.Spot)] = []
        let freeSlots = slots.filter { $0.helper == nil }
        for (t, spot) in zip(freeSlots, loungeSpots(freeSlots.count, &used)) { free.append((t, spot)) }
        var taken = spots.values.map { CGPoint(x: $0.spot.i, y: $0.spot.j) } + free.map { CGPoint(x: $0.spot.i, y: $0.spot.j) }
        for (t, spot) in free {
            guard let fig = figures[t.cast.key] else { continue }
            let p = person(t.id, owner: nil, figure: fig, scale: Self.helperScale, spot: spot, room: FloorRoom.lounge.rawValue)
            p.ref = nil; p.state = .done
            p.name = Persona(id: t.id).name
            (p.pose, p.mood) = (spot.seat > 0 ? "sit" : spot.pose, ["cheer": "happy", "wave": "happy", "type": "focus"][spot.pose] ?? "tired")
            if !p.moving { p.dir = spot.dir }
            setTag(p, text: p.name, sub: Self.pastime(spot), state: "free", role: Self.roleColour(t.role))
            setEmote(p, nil)
            p.node.alpha = 1
            seen.insert(t.id)
        }
        for s in sessions {
            guard let fig = figures[project.cast(of: s).key], let (spot, room) = spots[s.id] else { continue }
            let st = Self.shownState(s, in: project, now: now)
            let p = person(s.id, owner: nil, figure: fig, scale: 1, spot: spot, room: room.rawValue)
            p.state = st
            switch st {
            case .waiting: (p.pose, p.mood) = ("idle", "wait")
            case .stuck: (p.pose, p.mood) = spot.seat > 0 ? ("sit", "stuck") : ("stuck", "stuck")
            case .done: (p.pose, p.mood) = (spot.pose == "idle" ? "idle" : spot.pose, "tired")
            case .working: (p.pose, p.mood) = (spot.pose, ["type": "focus", "cheer": "happy", "wave": "happy", "mug": "tired"][spot.pose] ?? "calm")
            }
            if !p.moving { p.dir = spot.dir }
            p.name = s.persona.name
            let back = st == .working && s.wentBack(now: now), ceo = s.id == Self.factoryCEO(project) || s.heartbeatRun == true || s.id.hasPrefix(Project.standingCEOPrefix)
            let questions = s.id == Self.factoryCEO(project) ? project.factory?.openDecisions.count ?? 0 : 0
            let sub = questions > 0 ? "CEO · \(questions) question\(questions == 1 ? "" : "s")" : ceo && st != .stuck ? "CEO"
                : st == .waiting ? "Waits for you" : st == .stuck ? "Stuck" : back ? "Sent back" : st == .done ? (spot.seat > 0 ? "Parked" : "Done")
                : project.role(of: s).label
            let helped = !s.subAgents.filter { !($0.finished && project.isTeamProfile($0.type)) }.isEmpty
            setTag(p, text: s.persona.name, sub: sub, state: st == .waiting ? "wait" : st == .stuck ? "stuck" : back ? "back" : st == .done ? "done" : "work",
                   role: ceo ? "#c9a46a" : Self.roleColour(project.role(of: s)), badge: helped ? Self.helperBadge : nil)
            setEmote(p, nil)
            seen.insert(s.id)
            // helpers: beside their person on screen, facing you, as big as everyone (every agent counts the same); the running ones closest, a finished one
            // further off and faded
            for sub in s.subAgents.sorted(by: { !$0.finished && $1.finished }) {
                // a team member's job done: they are back in the lounge, not standing about here
                if sub.finished && project.isTeamProfile(sub.type) { continue }
                let place = placeOf[sub.id]
                guard let hf = figures[place?.cast.key ?? sub.cast.key] else { continue }
                let hs = helperSpot(beside: spot, finished: sub.finished, taken: &taken)
                let hp = person(place?.id ?? sub.id, owner: s.id, figure: hf, scale: Self.helperScale, spot: hs, room: room.rawValue)
                hp.ref = place == nil ? nil : sub.id
                hp.state = sub.finished ? .done : .working
                hp.name = place.map { Persona(id: $0.id).name } ?? Self.helperName(sub.type)
                setTag(hp, text: hp.name, sub: "\(s.persona.name)'s helper" + (sub.finished ? " · done" : ""), state: sub.finished ? "done" : "work",
                       role: Self.helperBadge, badge: Self.helperBadge)
                (hp.pose, hp.mood) = sub.finished ? ("idle", "tired") : ("idle", "calm")
                if !hp.moving { hp.dir = "down" }
                hp.node.alpha = 1
                seen.insert(place?.id ?? sub.id)
            }
        }
        for (id, p) in people where !seen.contains(id) { remove(p); people[id] = nil }
        if let s = selectedSession, people[s] == nil { selectedSession = nil; selectedSubAgent = nil }
        applyFactory(project.factory, art: art)
        for p in people.values {
            p.loop = IdleMotion.loop(state: p.state, room: p.room, spotPose: p.spot.pose, seated: p.spot.seat > 0, helper: p.owner != nil)
            layout(p)
        }
        declutterPlates()
        updateMarker()
    }

    /// Plates of people who stand close on screen would cover each other: from the front back, a plate that runs into
    /// one in front of it goes up just above it (B2). Someone walking keeps their plate where it is.
    private func declutterPlates() {
        // the loud plates (waits for you, stuck) stay over their person; quieter ones give way, front first
        let loud: (Person) -> Bool = { $0.state == .waiting || $0.state == .stuck }
        let list = people.values.compactMap { p -> (Person, SKSpriteNode)? in p.tag.map { (p, $0) } }
            .sorted { (loud($0.0) ? 0 : 1, $0.1.position.y) < (loud($1.0) ? 0 : 1, $1.1.position.y) }
        // the room signs (B4): a plate that would cover one goes up above it, but only a little way (a plate far above its
        // person reads as someone else's; a sign hidden behind the Planning board is no sign)
        let signs: [CGRect] = (art?.labels ?? []).map { CGRect(x: $0.minX * px, y: -$0.maxY * px, width: $0.width * px, height: $0.height * px) }
            .filter { !($0.intersects(boardFrame ?? .null)) }
        var placed: [CGRect] = []
        for (p, t) in list {
            var f = t.frame
            if !p.walking {
                let start = f.origin.y
                var moved = true, tries = 0
                while moved, tries < 8 {
                    moved = false; tries += 1
                    for r in placed + signs where r.intersects(f) {
                        let x = r.intersection(f)
                        guard x.width > 0.2 * f.width, x.height > 2 * px else { continue }
                        // over a sign, only when it takes a short step up
                        if !placed.contains(r), r.maxY + 1 * px - start > 22 * px { continue }
                        f.origin.y = r.maxY + 1 * px; moved = true
                    }
                }
                t.position.y = f.maxY
            }
            placed.append(f)
        }
    }

    // MARK: a Dark Software Factory

    private var factoryLayer: SKNode? { didSet { if factoryLayer == nil { boardFrame = nil } } }
    /// where the Planning board hangs, once painted (the signs it covers do not count)
    private var boardFrame: CGRect?
    private var factoryKey = ""

    /// A factory's floor: every workstream a card on the back wall of its phase's room (D39: the room says the phase),
    /// with a ↩ when it went back; the floor as dark as the factory is autonomous (assistant lights on, hybrid dimmed,
    /// dark lights out with only the lamps and screens glowing); and a red PAUSED sign when STOP is on.
    private func applyFactory(_ factory: Factory?, art: FloorArt) {
        let streams = (factory?.activeWorkstreams ?? []).filter { w in
            // done work stays on the Lounge wall for a week
            w.phase != .done || (w.updated.flatMap { FactoryText.date($0) }.map { Date().timeIntervalSince($0) < 7 * 86400 } ?? true)
        }
        let key = factory == nil ? "" : "\(factory!.autonomy?.level.rawValue ?? "")|\(factory!.paused)|\(factory!.openDecisions.count)|" + streams.map { "\($0.id)\($0.phase.rawValue)\($0.wentBack)\($0.title)" }.joined(separator: ",")
        guard key != factoryKey else { return }
        factoryKey = key
        factoryLayer?.removeFromParent(); factoryLayer = nil
        content.childNode(withName: "sign:room:war")?.isHidden = false
        guard let factory else { return }
        let layer = SKNode(); layer.zPosition = 0
        content.addChild(layer); factoryLayer = layer

        // darkness under the lights (the light layer is at 3000, screen-blended, so lamps and screens still glow)
        let dark = factory.autonomy?.level.darkness ?? 0
        if dark > 0 {
            let shade = SKSpriteNode(color: SKColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1), size: CGSize(width: 40000, height: 40000))
            shade.position = scenePoint(CGPoint(x: art.view.midX, y: art.view.midY)); shade.alpha = dark * 0.7; shade.zPosition = 2990
            shade.name = "factory:dark"
            layer.addChild(shade)
        }

        // one calm board on the Planning wall (B1, B5): a card per workstream in its phase's column; it hangs on the wall,
        // behind everyone (never over a person)
        let cards: [[String: Any]] = streams.sorted { $0.id < $1.id }.map { w in
            ["id": w.id, "title": w.title, "phase": w.phase.step ?? 0, "back": w.wentBack, "done": w.phase == .done,
             "wait": factory.openDecisions.contains { $0.title.contains(w.id) }]
        }
        if let e = engine, !cards.isEmpty {
            Task { @MainActor in
                guard let o = await e.board(cards), self.factoryLayer === layer else { return }
                // its top-left corner on the back wall of Planning (i 8.5, at the wall's face, 44 units up)
                let at = project(8.5, 0.02, 43)
                let n = self.place(SKTexture(cgImage: o.image), CGRect(x: at.x + o.rect.minX, y: at.y + o.rect.minY, width: o.rect.width, height: o.rect.height), z: -5)
                n.name = "factory:board"
                self.boardFrame = n.frame
                // the board carries the room's name: Planning's plaque would only peek out above it
                self.content.childNode(withName: "sign:room:war")?.isHidden = true
                layer.addChild(n)
            }
        }

        if factory.paused, let entrance = art.rooms.first(where: { $0.id == "entrance" }) {
            let sign = SKShapeNode(rect: CGRect(x: 0, y: -15 * px, width: 62 * px, height: 15 * px), cornerRadius: 2 * px)
            sign.fillColor = SKColor(red: 1, green: 0.29, blue: 0.29, alpha: 1); sign.strokeColor = SKColor(red: 0.3, green: 0.03, blue: 0.03, alpha: 1)
            sign.lineWidth = px
            let label = SKLabelNode(text: "PAUSED")
            label.fontName = "Menlo-Bold"; label.fontSize = 9 * px; label.fontColor = SKColor(red: 0.16, green: 0.01, blue: 0.01, alpha: 1)
            label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .center; label.position = CGPoint(x: 31 * px, y: -7.5 * px)
            sign.addChild(label)
            let c = project(entrance.rect.midX, entrance.rect.midY, 60)
            sign.position = scenePoint(CGPoint(x: c.x - 31, y: c.y)); sign.zPosition = 3600; sign.name = "factory:paused"
            layer.addChild(sign)
        }
    }

    /// A workstream card: a cream note like the room signs, its id in bold and the title cut short; ↩ when it went back.
    static func card(_ w: Workstream?, more: Int = 0, px: CGFloat) -> SKNode {
        let text: String
        if let w {
            let title = w.title.count > 22 ? String(w.title.prefix(21)) + "…" : w.title
            text = "\(w.id)  \(title)"
        } else { text = "+\(more) more" }
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"; label.fontSize = 6.8 * px; label.fontColor = SKColor(red: 0.12, green: 0.1, blue: 0.2, alpha: 1)
        label.horizontalAlignmentMode = .left; label.verticalAlignmentMode = .center
        let back = w?.wentBack == true
        let height: CGFloat = 12.5, width = label.frame.width / px + 6 + (back ? 9 : 0)
        let n = SKShapeNode(rect: CGRect(x: 0, y: -height * px, width: width * px, height: height * px), cornerRadius: 0)
        n.fillColor = w == nil ? SKColor(red: 0.85, green: 0.82, blue: 0.74, alpha: 0.92) : SKColor(red: 0.97, green: 0.93, blue: 0.83, alpha: 1)
        n.strokeColor = SKColor(red: 0.16, green: 0.13, blue: 0.24, alpha: 1); n.lineWidth = 0.8 * px
        label.position = CGPoint(x: 2.5 * px, y: -height * px / 2)
        n.addChild(label)
        if back {
            let note = SKShapeNode(rect: CGRect(x: (width - 8.5) * px, y: -(height - 1.5) * px, width: 7 * px, height: (height - 3) * px), cornerRadius: 1 * px)
            note.fillColor = .white; note.strokeColor = SKColor(red: 0.16, green: 0.13, blue: 0.24, alpha: 1); note.lineWidth = 0.6 * px
            let arrow = SKLabelNode(text: "↩"); arrow.fontName = "Menlo-Bold"; arrow.fontSize = 6 * px
            arrow.fontColor = SKColor(red: 0.2, green: 0.35, blue: 0.85, alpha: 1)
            arrow.horizontalAlignmentMode = .center; arrow.verticalAlignmentMode = .center; arrow.position = CGPoint(x: (width - 5) * px, y: -height * px / 2)
            n.addChild(note); n.addChild(arrow)
        }
        return n
    }

    /// Spots in the lounge for free team members: the standing ones first, the sofa last (whoever rests in front of it
    /// would hide a small figure sitting there), then beside the others as takeSpot does.
    private func loungeSpots(_ n: Int, _ used: inout [String: Int]) -> [FloorArt.Spot] {
        let room = FloorRoom.lounge.rawValue
        let list = art?.spots[room] ?? []
        let start = min(used[room, default: 0], list.count)
        let rest = Array(list[start...])
        let ordered = rest.filter { $0.seat == 0 } + rest.filter { $0.seat > 0 }
        var out = Array(ordered.prefix(n))
        used[room] = start + out.count
        while out.count < n { out.append(takeSpot(room, &used)) }
        return out
    }

    private func takeSpot(_ room: String, _ used: inout [String: Int]) -> FloorArt.Spot {
        let list = art?.spots[room] ?? art?.spots["lounge"] ?? [FloorArt.Spot(i: 10, j: 8, pose: "idle", dir: "down", seat: 0)]
        let k = used[room, default: 0]; used[room] = k + 1
        var s = list[k % list.count]
        if k >= list.count {       // more people than spots: stand beside, a little further each time
            let n = CGFloat(k / list.count)
            s.i += 0.5 * n; s.j += 0.4 * n; s.seat = 0
            if s.pose == "type" || s.pose == "sit" { s.pose = "idle" }
        }
        return s
    }

    /// Where a helper stands: to the right of their person on screen (along +i, a little forward when that is taken),
    /// clear of the person's ring and of everyone else, on a free cell, and not behind anything tall. A finished helper
    /// starts one place further off.
    /// Helpers are as big as the person they work for: every agent counts the same.
    static let helperScale: CGFloat = 1

    private func helperSpot(beside spot: FloorArt.Spot, finished: Bool, taken: inout [CGPoint]) -> FloorArt.Spot {
        // to the right first, clear of the person's ring and body (a full-size figure is about 20 art units wide: 1.5
        // tile of i − j keeps them apart on screen); the left (−i) only when the right is full or hidden
        // (Spel+, B3: beside their person on screen, one each side, far enough apart that the three plates never overlap:
        // a step of +i −j is three tiles to the right on screen at the same height)
        let offsets: [CGPoint] = [CGPoint(x: 1.5, y: -1.5), CGPoint(x: -1.5, y: 1.5), CGPoint(x: 2.0, y: -1.0), CGPoint(x: -1.0, y: 2.0),
                                  CGPoint(x: 2.5, y: -0.5), CGPoint(x: -0.5, y: 2.5), CGPoint(x: 1.6, y: -2.2), CGPoint(x: -2.2, y: 1.6),
                                  CGPoint(x: 3.0, y: 0), CGPoint(x: 0, y: 3.0)]
        let base = CGPoint(x: spot.i, y: spot.j), k = Self.helperScale / 0.62, gap = 0.65 * k * 0.85
        func ok(_ p: CGPoint) -> Bool {
            guard let map = walkMap, let art else { return true }
            guard map.free(p), taken.allSatisfy({ hypot($0.x - p.x, $0.y - p.y) >= gap }) else { return false }
            // nothing drawn in front of the figure (its body above its feet; the feet may touch)
            let foot = project(p.x, p.y), z = depthKey(p.x, p.y, boxes: art.boxes)
            let body = CGRect(x: foot.x - 6 * k, y: foot.y - 26 * k, width: 12 * k, height: 21 * k)
            // (an object's rect is its bounding box, so a corner of it over the figure does not count)
            let hid = art.objects.filter { o in
                let x = o.rect.intersection(body)
                return o.key > z + 0.05 && !x.isNull && x.width * x.height > 0.12 * body.width * body.height
            }
            // and not in front of or behind anyone else on screen
            let byPeople = taken.contains { q in
                let f = project(q.x, q.y)
                // their bodies, or their name plates (about 44 wide, 20 high) over each other
                return (abs(f.x - foot.x) < 14 * k && abs(f.y - foot.y) < 30 * k) || (abs(f.x - foot.x) < 44 && abs(f.y - foot.y) < 20)
            }
            return hid.isEmpty && !byPeople
        }
        let list = offsets.dropFirst(finished ? 1 : 0).map { CGPoint(x: base.x + $0.x, y: base.y + $0.y) }
        let pick = list.first(where: ok)
            ?? list.first { p in walkMap?.free(p) != false && taken.allSatisfy { hypot($0.x - p.x, $0.y - p.y) >= gap } }
            ?? CGPoint(x: base.x + 1.0, y: base.y + (spot.seat > 0 ? 0.1 : 0))
        taken.append(pick)
        return FloorArt.Spot(i: pick.x, j: pick.y, pose: "idle", dir: "down", seat: 0)
    }

    /// The person for an id, walking to its new spot when it moved.
    private func person(_ id: String, owner: String?, figure: Figure, scale: CGFloat, spot: FloorArt.Spot, room: String) -> Person {
        if let p = people[id] {
            if abs(p.spot.i - spot.i) > 0.01 || abs(p.spot.j - spot.j) > 0.01 {
                let from = p.walking ? p.pos : CGPoint(x: p.spot.i, y: p.spot.j)
                let way = route(from, CGPoint(x: spot.i, y: spot.j))
                p.path = animationsEnabled ? Array(way.dropFirst()) : []
                p.routeLength = zip(way, way.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }.reduce(0, +)
                p.turns = []
                p.pos = from
                if !animationsEnabled { p.pos = CGPoint(x: spot.i, y: spot.j) }
            }
            p.spot = spot; p.room = room; p.owner = owner
            p.node.name = (owner == nil && !id.hasPrefix("team:") ? "person:" : "helper:") + id
            return p
        }
        let p = Person(id: id, owner: owner, figure: figure, scale: scale, spot: spot, room: room)
        p.node.anchorPoint = CGPoint(x: 0, y: 1); p.node.name = (owner == nil && !id.hasPrefix("team:") ? "person:" : "helper:") + id
        p.shadow.setScale(px * scale / 2 * 1.1)
        content.addChild(p.shadow); content.addChild(p.node)
        people[id] = p
        return p
    }

    private func remove(_ p: Person) {
        if hoverTarget == .person(p.id) { hoverTarget = nil }
        [p.node, p.shadow, p.tag, p.emote, p.cloud, p.ring, p.hoverRing, p.hoverTag, p.hoverLift, p.tie, p.tieRing].forEach { $0?.removeFromParent() } }

    /// A plate for everyone (B2, B6): the name, a quiet second line, the role's colour. Waiting: yellow with a pixel "!";
    /// stuck: red with a storm cloud; sent back: a small blue bubble; done or free: dimmed. Waiting and stuck also get a
    /// ring on the floor, filled and edged so it shows on any floor colour (B8).
    private func setTag(_ p: Person, text: String, sub: String, state: String, role: String, badge: String? = nil) {
        let key = "\(text)|\(sub)|\(state)|\(role)|\(badge ?? "")"
        if state == "wait" || state == "stuck" {
            let col = state == "wait" ? SKColor(red: 1, green: 0.847, blue: 0.239, alpha: 1) : SKColor(red: 1, green: 0.29, blue: 0.29, alpha: 1)
            if p.ring == nil || p.ring?.name != state {
                p.ring?.removeFromParent()
                let r = Self.stateRing(col, px: px); r.name = state; r.zPosition = 3000
                if animationsEnabled { r.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)]))) }
                content.addChild(r); p.ring = r
            }
        } else { p.ring?.removeFromParent(); p.ring = nil }
        p.cloud?.removeFromParent(); p.cloud = nil
        guard key != p.tagKey else { return }
        p.tagKey = key
        p.tag?.removeFromParent(); p.tag = nil
        guard let e = engine else { return }
        Task { @MainActor in
            guard let o = await e.tag(text, sub: sub, state: state == "free" ? "done" : state, role: role, badge: badge), p.tagKey == key else { return }
            // the loud ones (waits for you, stuck) on top of any quiet one they meet
            let n = self.place(SKTexture(cgImage: o.image), o.rect, z: state == "wait" || state == "stuck" ? 4002 : state == "done" || state == "free" ? 3999 : 4000)
            n.name = "tag:" + p.id
            // done and free plates are quieter
            n.alpha = state == "done" || state == "free" ? 0.82 : 1
            p.tagRect = o.rect
            self.content.addChild(n); p.tag = n; self.layout(p)
        }
    }

    /// The floor's plate with its walls and the launch balcony, in art units: what the home view fills (B9).
    static let floorFrame = CGRect(x: -262, y: -58, width: 652, height: 396)

    /// A helper's tie to its person (B3), quiet and clear: a thin dashed line over the floor from their feet to its, and
    /// a faint ring at its feet, in the colour they share.
    private func tie(_ p: Person) {
        guard let o = p.owner, let q = people[o] else {
            p.tie?.removeFromParent(); p.tie = nil; p.tieRing?.removeFromParent(); p.tieRing = nil; return
        }
        let a = scenePoint(project(q.pos.x, q.pos.y)), b = scenePoint(project(p.pos.x, p.pos.y))
        let line = CGMutablePath(); line.move(to: a); line.addLine(to: b)
        if p.tie == nil {
            let t = SKShapeNode(); t.strokeColor = Self.helperTie.withAlphaComponent(0.95); t.lineWidth = 1.7 * px / 2; t.lineCap = .round; t.zPosition = -480
            content.addChild(t); p.tie = t
            let r = 0.46, pts = [CGPoint(x: 0, y: -r * 8), CGPoint(x: r * 16, y: 0), CGPoint(x: 0, y: r * 8), CGPoint(x: -r * 16, y: 0)].map { CGPoint(x: $0.x * px, y: -$0.y * px) }
            let path = CGMutablePath(); path.addLines(between: pts); path.closeSubpath()
            let ring = SKShapeNode(path: path); ring.fillColor = Self.helperTie.withAlphaComponent(0.14); ring.strokeColor = Self.helperTie.withAlphaComponent(0.8)
            ring.lineWidth = 1.4 * px / 2; ring.zPosition = -479
            content.addChild(ring); p.tieRing = ring
        }
        p.tie?.path = line.copy(dashingWithPhase: 0, lengths: [3 * px, 2.5 * px])
        p.tieRing?.position = b
    }

    /// The factory's CEO on its floor: its main chat (a heartbeat's run, the run named CEO, or the resting stand-in).
    static func factoryCEO(_ p: Project) -> String? {
        guard p.factory != nil, let id = p.ceoID, let s = p.sessions.first(where: { $0.id == id }), p.role(of: s) == .ceo else { return nil }
        return id
    }
    /// Where the CEO stands when the art says nothing: under the board's left end in Planning, facing you.
    static let ceoSpot = FloorArt.Spot(i: 8.65, j: 1.15, pose: "point", dir: "down", seat: 0)

    /// How a session shows on its floor: as its state, except a factory's CEO, which waits for you while the factory has
    /// an open question (it is the one who asks them), and otherwise is at work at the board or resting there.
    static func shownState(_ s: Session, in p: Project, now: Date) -> SessionState {
        let st = s.state(now: now)
        guard s.id == factoryCEO(p) else { return st }
        if !(p.factory?.openDecisions.isEmpty ?? true) { return .waiting }
        return st == .waiting ? .working : st
    }

    /// A diamond on the floor round someone who waits (yellow) or is stuck (red): a soft fill, a dark under-edge and the
    /// colour on top, so it reads on cream, mint and blue floors alike.
    static func stateRing(_ col: SKColor, px: CGFloat) -> SKNode {
        let n = SKNode(), r: CGFloat = 0.72
        let pts = [CGPoint(x: 0, y: -r * 8), CGPoint(x: r * 16, y: 0), CGPoint(x: 0, y: r * 8), CGPoint(x: -r * 16, y: 0)].map { CGPoint(x: $0.x * px, y: -$0.y * px) }
        let path = CGMutablePath(); path.addLines(between: pts); path.closeSubpath()
        let under = SKShapeNode(path: path); under.strokeColor = SKColor(red: 0.08, green: 0.05, blue: 0.12, alpha: 0.7); under.lineWidth = 3.6 * px / 2; under.fillColor = col.withAlphaComponent(0.2)
        let top = SKShapeNode(path: path); top.strokeColor = col; top.lineWidth = 2.2 * px / 2; top.fillColor = .clear; top.lineJoin = .miter
        n.addChild(under); n.addChild(top)
        return n
    }

    /// The colour of a role's plate edge (B2): the same colours as the HUD's role chips.
    static func roleColour(_ r: CastRole) -> String {
        switch r {
        case .ceo: "#c9a46a"
        case .lead: "#e0a04a"
        case .sales: "#3fae6a"
        case .marketing: "#ff8a2a"
        case .pm: "#2fb0a8"
        case .dev: "#4a74d8"
        case .designer: "#ff6ad5"
        case .tester: "#e05a86"
        case .devops: "#7a5ce0"
        case .researcher: "#6a8a4a"
        }
    }
    /// A helper and its person share this colour: the tie, the ring, the diamond on both plates (B3).
    static let helperBadge = "#9a7cf0"
    static let helperTie = SKColor(red: 0.6, green: 0.49, blue: 0.94, alpha: 1)

    /// What a free team member is doing in the break room, from where they are (B2).
    static func pastime(_ spot: FloorArt.Spot) -> String {
        switch spot.pose {
        case "mug": "Coffee break"
        case "cheer", "wave": "Ping-pong"
        case "type": "High score"
        case "snooze", "sit": "Napping"
        default: "Free"
        }
    }

    /// A helper's name from its type: "code-review" → "Review", "Explore" → "Explore".
    static func helperName(_ type: String) -> String {
        let last = type.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).last.map(String.init) ?? type
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    private func setEmote(_ p: Person, _ kind: String?) {
        let key = kind ?? ""
        guard key != p.emoteKey else { return }
        p.emoteKey = key
        p.emote?.removeFromParent(); p.emote = nil
        guard let kind, let e = engine else { return }
        Task { @MainActor in
            guard let o = await e.emote(kind), p.emoteKey == key else { return }
            let n = self.place(SKTexture(cgImage: o.image), o.rect, z: 4050); self.content.addChild(n); p.emote = n; self.layout(p)
        }
    }

    /// Where everything of one person goes, from where they stand and what they do.
    private func layout(_ p: Person) {
        guard let art else { return }
        let i = p.pos.x, j = p.pos.y, foot = project(i, j)
        let walking = p.walking, moving = p.moving, seat = moving ? 0 : p.spot.seat
        // standing still is never a statue: the loop of what they are doing (typing, reading, asking, dozing, …)
        let still = animationsEnabled && !p.loop.isEmpty ? IdleMotion.frame(p.loop, t: clock + p.phase * 7) : (pose: p.pose, mood: p.mood)
        let f = walking ? p.figure.frame(StepCycle.pose(distance: p.walked), mood: "calm", dir: p.dir)
            : moving ? p.figure.frame("idle", mood: "calm", dir: p.turns.first?.dir ?? p.dir)
            : p.figure.frame(still.pose, mood: still.mood, dir: p.dir)
        // the one nearer you in front, also when two stand in front of the same box
        let z = depthKey(i, j, boxes: art.boxes) * 10 + 0.5 + (i + j) * 0.001
        if let f {
            p.node.texture = f.texture
            p.node.size = CGSize(width: f.rect.width * px * p.scale, height: f.rect.height * px * p.scale)
            var y = foot.y + f.rect.minY * p.scale - seat * 1.08
            if !moving && still.pose.hasPrefix("type") && animationsEnabled { y += CGFloat(sin(clock * 16 + p.phase)) * 0.25 }
            // standing: a slow breath
            else if !moving && seat == 0 && animationsEnabled { y += CGFloat(sin(clock * 2.1 + p.phase)) * 0.22 }
            p.node.position = scenePoint(CGPoint(x: foot.x + f.rect.minX * p.scale, y: y))
        }
        p.node.zPosition = z
        if let l = p.hoverLift { l.texture = p.node.texture; l.size = p.node.size }
        p.shadow.position = scenePoint(foot); p.shadow.zPosition = z - 0.2; p.shadow.isHidden = seat > 0
        let head = foot.y - (35 + seat) * 1.08 * p.scale
        let bob = animationsEnabled ? CGFloat(sin(clock * 3.2 + p.phase)) * 1.2 : 0
        if let t = p.tag { t.position = scenePoint(CGPoint(x: foot.x + p.tagRect.minX, y: head - 2 + p.tagRect.minY)) }
        tie(p)
        if let t = p.hoverTag { t.position = scenePoint(CGPoint(x: foot.x - t.size.width / px / 2, y: head - 10.5)) }
        // rings lie round the feet; round someone seated, round the seat under them (at the floor it would sit on the
        // table in front of them and read as a mark on the table)
        let ring = Self.ringPoint(foot, seat: seat, scale: p.scale)
        p.hoverRing?.position = scenePoint(ring)
        p.ring?.position = scenePoint(ring)
        // a seated person's rings lie on the floor under the table in front of them, not across its edge
        p.ring?.zPosition = seat > 0 ? z - 0.15 : 3000
        p.hoverRing?.zPosition = seat > 0 ? z - 0.14 : 2999.9
        if let e = p.emote {
            // above the head; when a room sign hangs there, beside the head instead (right, then left), clear of the name tag
            let w = e.size.width / px, h = e.size.height / px, above = head - (p.tag == nil ? 6 : 22) - 17.5
            let side = head - 4 - h, gap = (p.tag.map { $0.size.width / px / 2 } ?? 6) + 3
            let spots = [CGPoint(x: foot.x - w / 2, y: above), CGPoint(x: foot.x + gap, y: side), CGPoint(x: foot.x - gap - w, y: side)]
            let at = spots.first { s in !art.labels.contains { $0.intersects(CGRect(x: s.x, y: s.y, width: w, height: h)) } } ?? spots[0]
            e.position = scenePoint(CGPoint(x: at.x, y: at.y + bob))
        }
        if let c = p.cloud { c.position = scenePoint(CGPoint(x: foot.x - c.size.width / px / 2, y: foot.y - (54 + seat) * 1.08 - 17.5)) }
    }

    // MARK: walking

    /// The floor, the balcony of the launch pad, and the void you cannot walk on. Walls and glass partitions keep people
    /// 0.35 tile off (half a figure on screen), so nobody seems to walk into the glass or past what stands beyond it.
    static func walkMap(_ solids: [CGRect]) -> FloorWalkMap {
        FloorWalkMap(area: [CGRect(x: 0.1, y: 0.1, width: 23.8, height: 15.8), CGRect(x: 4, y: 15, width: 5, height: 4.5)],
                     holes: [CGRect(x: 14, y: 11, width: 3, height: 5)], solid: solids, body: 0.18, wallBody: 0.35)
    }

    /// From one spot to another along i and j only, round furniture, through the doors (FloorWalkMap).
    func route(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] { walkMap?.route(a, b) ?? [a, b] }

    /// A brisk walk, the step cycle by distance so the feet stay put; on arrival a short stop, then a turn to face the
    /// way the spot faces (through a front side when it is a turn round).
    private func advance(_ p: Person, _ dt: CGFloat) {
        // a brisk walk; a long way a little quicker, so nobody is under way for more than about twelve seconds
        var left = dt * max(1.7, min(2.6, p.routeLength / 12))
        while left > 0, let next = p.path.first {
            let dx = next.x - p.pos.x, dy = next.y - p.pos.y, d = hypot(dx, dy)
            // a short sidestep (out of a chair, through a door) keeps the side they face
            if d > 0.3 { p.dir = Facing.dir(dx, dy, current: p.dir) }
            let step = min(d, left)
            p.walked += step
            if d <= left { p.pos = next; p.path.removeFirst(); left -= d }
            else { p.pos = CGPoint(x: p.pos.x + dx / d * left, y: p.pos.y + dy / d * left); left = 0 }
        }
        if p.path.isEmpty {
            p.pos = CGPoint(x: p.spot.i, y: p.spot.j); p.walked = 0
            var t: [(String, Double)] = [(p.dir, 0.12)]
            if let v = Facing.via(p.dir, p.spot.dir) { t.append((v, 0.12)) }
            if p.spot.dir != p.dir { t.append((p.spot.dir, 0.1)) }
            p.turns = t.map { (dir: $0.0, left: $0.1) }
            p.dir = p.spot.dir
        }
    }


    public override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, currentTime - lastTime); lastTime = currentTime
        guard animationsEnabled else { return }
        clock += dt
        for p in people.values {
            if p.walking { advance(p, CGFloat(dt)) }
            else if !p.turns.isEmpty {
                p.turns[0].left -= dt
                if p.turns[0].left <= 0 { p.turns.removeFirst() }
            }
            layout(p)
        }
        declutterPlates()
        if let m = marker, let id = selectedSubAgent ?? selectedSession, let p = who(id) { placeMarker(m, p) }
        hoverRoom?.lineWidth = screenWidth(1.5)
        if pointer != nil { hover(at: pointerInScene) }
    }

    /// A debug aid for window shots: sends a person (and their helpers) to another room, as if their work moved there.
    public func debugWalk(_ id: String, to room: String) {
        guard let p = people[id] else { return }
        debugRooms[id] = room
        var used: [String: Int] = [:]
        for q in people.values where q.room == room && q.owner == nil && q.id != id { used[room, default: 0] += 1 }
        let spot = takeSpot(room, &used)
        _ = person(id, owner: nil, figure: p.figure, scale: p.scale, spot: spot, room: room)
        (p.pose, p.mood) = (spot.pose, "calm")
        var taken = people.values.filter { $0.id != id && $0.owner != id }.map { CGPoint(x: $0.spot.i, y: $0.spot.j) } + [CGPoint(x: spot.i, y: spot.j)]
        for q in people.values.filter({ $0.owner == id }).sorted(by: { ($0.state != .done ? 0 : 1, $0.id) < ($1.state != .done ? 0 : 1, $1.id) }) {
            let hs = helperSpot(beside: spot, finished: q.state == .done, taken: &taken)
            _ = person(q.id, owner: id, figure: q.figure, scale: q.scale, spot: hs, room: room)
        }
    }

    /// Where a person's body is now, in view points from the top left (a debug aid for hover shots).
    public func personViewPoint(_ id: String) -> CGPoint? {
        guard let p = who(id), let v = view else { return nil }
        let f = p.node.frame, q = convertPoint(toView: CGPoint(x: f.midX, y: f.midY))
        return CGPoint(x: q.x, y: v.bounds.height - q.y)
    }

    /// Enter with a short zoom-in, so going inside feels like going inside.
    func arrive() {
        cam.setScale(homeScale * 1.35); cam.position = homeCenter
        goHome(duration: 0.6)
    }

    // MARK: selection

    /// the person showing a session or helper: a helper at work in a team place shows under that place's id
    private func who(_ id: String) -> Person? { people[id] ?? people.values.first { $0.ref == id } }

    func select(session: String?, subAgent: String? = nil) {
        selectedSession = session; selectedSubAgent = subAgent
        updateMarker()
        if let id = subAgent ?? session, let p = who(id) { flyMiddle(p) }
        else { goHome() }
    }

    private func updateMarker() {
        marker?.removeFromParent(); marker = nil
        selectRing?.removeFromParent(); selectRing = nil
        for q in people.values { q.ring?.isHidden = false }
        guard let id = selectedSubAgent ?? selectedSession, let p = who(id) else { return }
        if hoverTarget == .person(id) { clearHover() }
        // over a waiting or stuck ring the selection takes its exact size and place: one ring, not two
        let big = p.ring != nil, w: CGFloat = (big ? 28 : 24) * p.scale, h: CGFloat = (big ? 14 : 12) * p.scale
        let ring = Blocky.ring(w * px, h * px, color: Self.cyan, lineWidth: (big ? 1.6 : 1.3) * px); ring.zPosition = 3000.05
        content.addChild(ring); selectRing = ring
        let path = CGMutablePath(); path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 5), CGPoint(x: 0, y: 10), CGPoint(x: -4, y: 5)].map { CGPoint(x: $0.x * px, y: $0.y * px) }); path.closeSubpath()
        let m = SKShapeNode(path: path); m.fillColor = SKColor(red: 0.31, green: 0.88, blue: 0.96, alpha: 1); m.strokeColor = SKColor(red: 0.14, green: 0.1, blue: 0.17, alpha: 1); m.lineWidth = px
        m.zPosition = 4200
        content.addChild(m); marker = m
        placeMarker(m, p)
    }

    private var selectRing: SKShapeNode?

    /// B10: a middle zoom on someone (plates and signs stay in proportion), them and their plate in the middle of the
    /// free area between the panels and bars.
    private func flyMiddle(_ p: Person) {
        var r = p.node.calculateAccumulatedFrame()
        if let t = p.tag { r = r.union(t.frame) }
        let k = homeScale * 0.72, usable = max(size.width - insets.left - insets.right, size.width * 0.5)
        flyClear(CGRect(x: r.midX - usable * k / 2, y: r.midY - 1, width: usable * k, height: 2), padding: 1.0)
    }

    /// Where a person's ring goes (art units): round the feet, or for someone seated on the seat under them.
    static func ringPoint(_ foot: CGPoint, seat: CGFloat, scale: CGFloat) -> CGPoint {
        seat > 0 ? CGPoint(x: foot.x, y: foot.y - seat * 1.08 * scale) : foot
    }

    private func placeMarker(_ m: SKShapeNode, _ p: Person) {
        let foot = project(p.pos.x, p.pos.y), seat = p.moving ? 0 : p.spot.seat
        selectRing?.position = scenePoint(Self.ringPoint(foot, seat: seat, scale: p.scale))
        selectRing?.zPosition = seat > 0 ? p.node.zPosition - 0.13 : 3000.05
        p.ring?.isHidden = selectRing != nil
        let at = CGPoint(x: foot.x, y: foot.y - (35 + seat) * 1.08 * p.scale - 2 + (p.tag != nil ? p.tagRect.minY : 0) - 12)
        // a room sign hangs there: no mark over the head (the ring at the feet already says who is selected; beside the
        // tag it read as loose, belonging to nobody)
        m.position = scenePoint(at)
        if animationsEnabled { m.position.y += CGFloat(sin(clock * 4)) * 2 * px }
    }

    public override func up() {
        if selectedSubAgent != nil { select(session: selectedSession); onSelect?(selectedSession, nil) }
        else if selectedSession != nil { select(session: nil); onSelect?(nil, nil) }
        else { onExit?() }
    }
    public override func next() { onNext?() }

    /// What a click at a point picks (one hit test for clicks and hover): a person or helper (their tag counts), or,
    /// with nobody selected, the room under the pointer.
    enum Target: Equatable { case person(String), room(String) }

    func target(at p: CGPoint) -> Target? {
        let hits = nodes(at: p).filter { n in ["person:", "helper:", "tag:"].contains { (n.name ?? "").hasPrefix($0) } && n.alpha > 0.05 }
        if let top = hits.max(by: { $0.zPosition < $1.zPosition }), let name = top.name {
            return .person(String(name.drop { $0 != ":" }.dropFirst()))
        }
        guard selectedSession == nil, let art else { return nil }
        let a = artPoint(p), i = (a.x / 16 + a.y / 8) / 2, j = (a.y / 8 - a.x / 16) / 2
        return art.rooms.first { $0.rect.contains(CGPoint(x: i, y: j)) }.map { .room($0.id) }
    }

    /// A right-click on someone is their session; anywhere else on the floor is the project (D72).
    override func contextTarget(at p: CGPoint) -> ContextTarget? {
        if case .person(let id)? = target(at: p) {
            if id.hasPrefix(Project.standingCEOPrefix) { return .project(projectID) }
            if id.hasPrefix("team:") { return people[id]?.owner.map { .session($0) } ?? .project(projectID) }
            return .session(people[id]?.owner ?? id)
        }
        return .project(projectID)
    }

    override func click(at p: CGPoint) {
        switch target(at: p) {
        case .person(let id)?:
            if let p = people[id], let owner = p.owner { let sub = p.ref ?? id; select(session: owner, subAgent: sub); onSelect?(owner, sub) }
            else if id.hasPrefix("team:") { break }        // a free team member: nothing to open (hover says who)
            else { select(session: id); onSelect?(id, nil) }
        case .room(let id)?:
            clearHover()
            if let r = art?.rooms.first(where: { $0.id == id }) { flyClear(sceneRect(r.rect), padding: 1.4) }
        case nil:
            if selectedSession != nil { select(session: nil); onSelect?(nil, nil) }
        }
    }

    /// A room's floor (tiles) as a rectangle in the scene.
    private func sceneRect(_ r: CGRect) -> CGRect {
        let pts = [project(r.minX, r.minY), project(r.maxX, r.minY), project(r.maxX, r.maxY), project(r.minX, r.maxY)].map(scenePoint)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    // MARK: hover

    private var hoverTarget: Target?
    private var hoverRoom: SKShapeNode?
    private static let cyan = SKColor(red: 0.31, green: 0.88, blue: 0.96, alpha: 1)

    /// Hover is a pre-selection in cyan: a ring at the feet of a person (their name tag too, when they have none), or
    /// the outline of a room's floor. Nothing on who is selected, nothing while the camera flies.
    override func hover(at p: CGPoint?) {
        var t = p.flatMap(target(at:))
        if cam.hasActions() { t = nil }
        hovering = t != nil
        if case .person(let id)? = t, let sel = selectedSubAgent ?? selectedSession, people[id] === who(sel) { t = nil }
        guard t != hoverTarget else { return }
        let had = hoverTarget != nil
        if let old = hoverTarget { unhover(old, swap: t != nil) }
        hoverTarget = t
        switch t {
        case .person(let id)?:
            guard let person = people[id] else { break }
            let big = person.ring != nil, w: CGFloat = (big ? 34 : 24) * person.scale, h: CGFloat = (big ? 17 : 12) * person.scale
            let r = Blocky.ring(w * px, h * px, color: Self.cyan.withAlphaComponent(0.85), lineWidth: px); r.zPosition = 2999.9
            content.addChild(r); person.hoverRing = r
            fadeIn(r, had)
            // the figure itself lights up a little too, as a building does
            let lift = SKSpriteNode(texture: person.node.texture); lift.size = person.node.size
            lift.anchorPoint = CGPoint(x: 0, y: 1); lift.blendMode = .add; lift.alpha = 0.22; lift.zPosition = 0.01
            person.node.addChild(lift); person.hoverLift = lift
            if person.tag == nil, let e = engine {
                let name = person.name
                Task { @MainActor in
                    guard let o = await e.tag(name, state: "work"), self.hoverTarget == .person(id), person.hoverTag == nil, person.tag == nil else { return }
                    let n = self.place(SKTexture(cgImage: o.image), o.rect, z: 4000); n.alpha = 0.85
                    self.content.addChild(n); person.hoverTag = n; self.layout(person)
                }
            }
            layout(person)
        case .room(let id)?:
            guard let room = art?.rooms.first(where: { $0.id == id }) else { break }
            // the room's floor only: not past the floor plate (the Deploy room runs out onto the launch balcony)
            let plate = CGRect(x: 0.1, y: 0.1, width: 23.8, height: 15.8)
            let q = room.rect.intersection(plate).insetBy(dx: 0.08, dy: 0.08)
            let path = CGMutablePath()
            path.addLines(between: [project(q.minX, q.minY), project(q.maxX, q.minY), project(q.maxX, q.maxY), project(q.minX, q.maxY)].map(scenePoint))
            path.closeSubpath()
            let n = SKShapeNode(path: path); n.fillColor = Self.cyan.withAlphaComponent(0.05); n.strokeColor = Self.cyan.withAlphaComponent(0.5)
            n.lineWidth = screenWidth(1.5); n.zPosition = -499
            content.addChild(n); hoverRoom = n
            fadeIn(n, had)
        case nil: break
        }
    }

    private func fadeIn(_ n: SKNode, _ swap: Bool) {
        guard !swap, animationsEnabled else { return }
        n.alpha = 0; let f = SKAction.fadeAlpha(to: n.alpha == 0 ? 1 : n.alpha, duration: 0.12); f.timingMode = .easeOut; n.run(f)
    }

    private func unhover(_ t: Target, swap: Bool) {
        var gone: [SKNode] = []
        if case .person(let id) = t, let p = people[id] {
            gone = [p.hoverRing, p.hoverTag, p.hoverLift].compactMap { $0 }; p.hoverRing = nil; p.hoverTag = nil; p.hoverLift = nil
        }
        if let r = hoverRoom { gone.append(r); hoverRoom = nil }
        for n in gone { swap || !animationsEnabled ? n.removeFromParent() : n.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()])) }
    }

    private func clearHover() { if let t = hoverTarget { unhover(t, swap: true) }; hoverTarget = nil }

    override func didZoom(zoomingIn: Bool) {
        if !zoomingIn, zoomRatio > 1.45 { onExit?() }
    }
}
