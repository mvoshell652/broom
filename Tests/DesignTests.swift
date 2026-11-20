import Foundation
import Testing
@testable import Broom

@Suite("Design tokens")
struct DesignTests {
    /// WCAG 2 contrast ratio between two 0xRRGGBB colors.
    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let value = Double((hex >> UInt32(shift)) & 0xFF) / 255
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Every text color with the surface it is drawn on.
    struct ContrastPair: Sendable, CustomTestStringConvertible {
        var name: String
        var text: ColorToken
        var surface: ColorToken

        var testDescription: String { name }

        init(_ name: String, _ text: ColorToken, _ surface: ColorToken) {
            self.name = name
            self.text = text
            self.surface = surface
        }
    }

    private static let pairs: [ContrastPair] = [
        ContrastPair("waiting label on popover", BroomStyle.waitingLabel, BroomStyle.popover),
        ContrastPair("waiting link on popover", BroomStyle.waitingText, BroomStyle.popover),
        ContrastPair("running label on popover", BroomStyle.running, BroomStyle.popover),
        ContrastPair("done label on popover", BroomStyle.done, BroomStyle.popover),
        ContrastPair("done text on form background", BroomStyle.doneOnGray, formBackground),
        ContrastPair("done text on diff box", BroomStyle.doneOnGray, diffBox),
        ContrastPair("waiting text on form background", BroomStyle.waitingTextOnGray, formBackground),
        ContrastPair("waiting text on diff box", BroomStyle.waitingTextOnGray, diffBox),
    ]

    /// Approximations of the system grays in Settings; the light values are the darkest the system uses there.
    private static let formBackground = ColorToken(light: 0xECECEC, dark: 0x2C2C2E)
    private static let diffBox = ColorToken(light: 0xE5E5E5, dark: 0x3A3A3C)

    @Test("Text meets 4.5:1 against its surface in light and dark", arguments: pairs)
    func textContrast(pair: ContrastPair) {
        #expect(contrast(pair.text.light, pair.surface.light) >= 4.5, "\(pair.name), light")
        #expect(contrast(pair.text.dark, pair.surface.dark) >= 4.5, "\(pair.name), dark")
    }

    @Test("White on the primary button meets 4.5:1")
    func primaryButton() {
        #expect(contrast(0xFFFFFF, BroomStyle.waitingButton.light) >= 4.5)
        #expect(contrast(0xFFFFFF, BroomStyle.waitingButton.dark) >= 4.5)
        #expect(contrast(0xFFFFFF, BroomStyle.destructiveButton.light) >= 4.5)
    }

    /// A duration and how each kind of row label should read it.
    struct TimeCase: Sendable, CustomTestStringConvertible {
        var seconds: TimeInterval
        var age: String
        var ago: String
        var elapsed: String

        var testDescription: String { "\(Int(seconds)) s" }
    }

    private static let timeCases: [TimeCase] = [
        TimeCase(seconds: 0, age: "now", ago: "just now", elapsed: "under 1m"),
        TimeCase(seconds: 59, age: "now", ago: "just now", elapsed: "under 1m"),
        TimeCase(seconds: 60, age: "1m", ago: "1m ago", elapsed: "1m"),
        TimeCase(seconds: 1360, age: "22m", ago: "22m ago", elapsed: "22m"),
        TimeCase(seconds: 3600, age: "1h", ago: "1h ago", elapsed: "1h"),
        TimeCase(seconds: 7140, age: "1h", ago: "1h ago", elapsed: "1h 59m"),
        TimeCase(seconds: 7800, age: "2h", ago: "2h ago", elapsed: "2h 10m"),
        TimeCase(seconds: 86_399, age: "23h", ago: "23h ago", elapsed: "23h 59m"),
        TimeCase(seconds: 93_600, age: "1d", ago: "1d ago", elapsed: "1d 2h"),
        TimeCase(seconds: 86_700, age: "1d", ago: "1d ago", elapsed: "1d"),
    ]

    @Test("Row times are floored, never rounded up", arguments: timeCases)
    func timeLabels(timeCase: TimeCase) {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(timeCase.seconds)

        #expect(TimeLabel.age(since: start, now: now) == timeCase.age)
        #expect(TimeLabel.ago(since: start, now: now) == timeCase.ago)
        #expect(TimeLabel.elapsed(since: start, now: now) == timeCase.elapsed)
    }

    @Test("The menu bar item is described as the spec words it")
    func menuBarAccessibilityLabel() {
        #expect(MenuBarIcon.accessibilityLabel(runningCount: 2, waitingCount: 1) == "Broom: 2 running, 1 waiting on you")
    }

    @Test("The menu bar image grows with the count and the dot")
    func menuBarImageSize() {
        let bare = MenuBarIcon.makeImage(runningCount: 0, hasWaiting: false).size
        let counted = MenuBarIcon.makeImage(runningCount: 2, hasWaiting: false).size
        let dotted = MenuBarIcon.makeImage(runningCount: 2, hasWaiting: true).size

        #expect(bare.width == MenuBarIcon.glyphSize)
        #expect(counted.width > bare.width)
        #expect(dotted.width > counted.width)
        #expect(bare.height == dotted.height)
    }
}
