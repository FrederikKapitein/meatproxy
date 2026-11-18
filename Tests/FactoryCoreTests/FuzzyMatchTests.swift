import Testing
@testable import FactoryCore

/// D72: search as you type.
@Suite struct FuzzyMatchTests {
    @Test func lettersInOrderMatch() {
        #expect(FuzzyMatch.score("pbl", "Pebble Puzzles") != nil)
        #expect(FuzzyMatch.score("zp", "Pebble Puzzles") == nil)       // out of order
        #expect(FuzzyMatch.score("ÉLAN", "elan vital") != nil)          // case and accents do not count
        #expect(FuzzyMatch.score("", "anything") == 0)
    }

    @Test func wordStartsAndRunsRankFirst() {
        let items = ["Settings · Projects · Pebble Puzzles", "Pebble Puzzles", "Open a new chat", "Run now · Pebble Puzzles"]
        #expect(FuzzyMatch.rank("pebble", items).first == "Pebble Puzzles")
        #expect(FuzzyMatch.rank("run", items).first == "Run now · Pebble Puzzles")
        #expect(FuzzyMatch.rank("sp", ["Status layer", "Server room", "Settings · Projects"]).first == "Settings · Projects")
        #expect(FuzzyMatch.rank("", items, limit: 2).count == 2)
    }

    /// D3: what you type filters every group; projects come first, and a group without a match drops out.
    @Test func searchFiltersByGroupProjectsFirst() {
        let items: [(String, String)] = [("go", "Campus"), ("go", "Next that needs you"), ("go", "Up a level"), ("go", "Server room"),
                                         ("project", "Pebble Puzzles"), ("project", "Shopfront"), ("people", "Cleo · Pebble factory: CEO run")]
        let found = FuzzyMatch.rankGrouped("peb", items, groups: ["project", "people", "go"], group: { $0.0 }, text: { $0.1 })
        #expect(found.map(\.group) == ["project", "people"])
        #expect(found.first?.items.map(\.1) == ["Pebble Puzzles"])
        // no query: every group, in the order asked for
        let all = FuzzyMatch.rankGrouped("", items, groups: ["project", "go"], group: { $0.0 }, text: { $0.1 })
        #expect(all.map(\.group) == ["project", "go"])
        #expect(all[1].items.count == 4)
    }

    /// Henk: "peb" matched "Recipe Box" (r-e-c-i-P-E … B-ox) and ranked its chat first. What you typed as one run wins,
    /// and once something holds it, letters picked from here and there drop out.
    @Test func whatYouTypedAsOneRunWins() {
        let items: [(String, String)] = [("need", "Add grocery list export · Recipe Box"), ("need", "Ship offline streak sync · Pebble Puzzles")]
        let found = FuzzyMatch.rankGrouped("peb", items, groups: ["need"], group: { $0.0 }, text: { $0.1 })
        #expect(found.first?.items.map(\.1) == ["Ship offline streak sync · Pebble Puzzles"])
        // nothing holds the run: the letters in order still find it
        #expect(FuzzyMatch.rankGrouped("rcpbx", items, groups: ["need"], group: { $0.0 }, text: { $0.1 }).first?.items.count == 1)
    }

    @Test func positionsMarkTheMatch() {
        #expect(FuzzyMatch.positions("peb", "Pebble Puzzles") == [0, 1, 2])
        #expect(FuzzyMatch.positions("pz", "Pebble Puzzles") == [0, 9])
        #expect(FuzzyMatch.positions("xyz", "Pebble") == nil)
    }
}
