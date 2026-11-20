import Testing
@testable import Broom

@Suite("DiffLine")
struct DiffLineTests {
    @Test("Added and removed lines are marked, with three lines of context and gaps for the rest")
    func contextAndGaps() {
        let old = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 6", with: "line six")

        let marked = DiffLine.lines(from: old, to: new).map(\.marked)

        #expect(marked == [
            "  ⋯", "  line 3", "  line 4", "  line 5", "- line 6", "+ line six", "  line 7", "  line 8", "  line 9", "  ⋯",
        ])
    }

    @Test("A new file is all additions")
    func newFile() {
        #expect(DiffLine.lines(from: "", to: "{\n  \"a\": 1\n}").map(\.marked) == ["+ {", "+   \"a\": 1", "+ }"])
    }

    @Test("Identical texts produce no lines")
    func identical() {
        #expect(DiffLine.lines(from: "a\nb", to: "a\nb").isEmpty)
    }
}
