import Foundation
import Testing
@testable import FactoryCore

/// What the app says in words where it would otherwise only show (UX review 26 Nov, round 3).
struct SpokenTests {
    @Test func theBarInWords() {
        #expect(SessionState.tally([.done, .working, .stuck, .working, .waiting, .done, .done, .done]) == "2 working · 1 waits · 1 stuck · 4 done")
        #expect(SessionState.tally([.waiting, .waiting]) == "2 wait")
        #expect(SessionState.tally([]) == "")
    }

    @Test func theWorldSaysWhereYouAre() {
        let w = Fixture.world(now: Date())
        let hint = "Command-K finds a project, person or server; N goes to the next that needs you."
        let campus = w.spoken(serverRoom: false, project: nil, tower: nil)
        #expect(campus.hasPrefix("Campus"))
        #expect(campus.hasSuffix(hint))
        let p = w.projects.first { !$0.sessions.isEmpty }!
        let floor = w.spoken(serverRoom: false, project: p.id, tower: nil)
        #expect(floor.hasPrefix("\(p.name) floor, \(p.sessions.count) chat"))
        let waits = w.needsYou.filter { $0.project.id == p.id }.count
        #expect(floor.contains("wait") == (waits > 0))
        let room = w.spoken(serverRoom: true, project: nil, tower: nil)
        #expect(room.hasPrefix("Server room, \(w.racks.count) rack"))
        if w.serverSummary.down > 0 { #expect(room.contains("\(w.serverSummary.down) down")) }
        let tower = w.spoken(serverRoom: false, project: nil, tower: .claude)
        #expect(tower.hasPrefix("Claude tower, "))
    }

    @Test func menuTitlesInTitleCase() {
        #expect(MenuWords.titleCase("Open the floor") == "Open the Floor")
        #expect(MenuWords.titleCase("Take over in the terminal") == "Take Over in the Terminal")
        #expect(MenuWords.titleCase("Run the DevOps agent now") == "Run the DevOps Agent Now")
        // the first word is always capital, a small word or not
        #expect(MenuWords.titleCase("the end") == "The End")
    }

    @Test func menuKeys() {
        #expect(MenuWords.key("⌘2")! == ("2", true))
        #expect(MenuWords.key("⌘L")! == ("l", true))
        #expect(MenuWords.key("⌘−")! == ("-", true))
        #expect(MenuWords.key("N")! == ("n", false))
        #expect(MenuWords.key("esc")! == ("\u{1b}", false))
        #expect(MenuWords.key("1 2") == nil)
        #expect(MenuWords.key(nil) == nil)
    }

    @Test func largerTextMovesTheScaleUp() {
        #expect(TextSize.points(13, larger: false) == 13)
        #expect([11, 12, 13, 15, 19, 26].map { TextSize.points($0, larger: true) } == [13, 14, 15, 17, 21, 28])
        // never smaller than Default, and never the same for reading sizes
        for s in [11.0, 12, 13, 15, 19, 26] { #expect(TextSize.points(s, larger: true) > s) }
    }
}
