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
}
