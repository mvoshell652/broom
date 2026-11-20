import SwiftUI

/// Design tokens: the accents. Neutral text, fills and separators are the system's semantic styles, not tokens.
/// Dark values are chosen to keep 4.5:1 text contrast.
enum BroomStyle {
    // Waiting
    static let waitingText = ColorToken(light: 0xB45309, dark: 0xFDBA74)
    static let waitingLabel = ColorToken(light: 0x9A3412, dark: 0xFDBA74)
    /// The primary button's fill; its label is white in both modes.
    static let waitingButton = ColorToken(light: 0xB45309, dark: 0xB45309)
    /// The fill of a button that stops sessions; its label is white in both modes.
    static let destructiveButton = ColorToken(light: 0xB91C1C, dark: 0xB91C1C)

    // Running
    static let running = ColorToken(light: 0x1D4ED8, dark: 0x8AB4FF)
    static let runningTrack = ColorToken(light: 0xEEF2FF, dark: 0x27324D)

    // Done
    static let done = ColorToken(light: 0x15803D, dark: 0x4ADE80)

    /// Text on the system gray surfaces in Settings (grouped Form background, diff box), which are darker than the white popover.
    static let doneOnGray = ColorToken(light: 0x166534, dark: 0x4ADE80)
    static let waitingTextOnGray = ColorToken(light: 0x9A3412, dark: 0xFDBA74)

    // Surfaces
    static let popover = ColorToken(light: 0xFFFFFF, dark: 0x1E1E1E)

    // Shape
    static let popoverWidth: CGFloat = 380
    static let popoverHeight: CGFloat = 640
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8
    static let buttonRadius: CGFloat = 6
    static let gutter: CGFloat = 16

    /// How far quick-chat titles are faded.
    static let quickChatOpacity = 0.75

    /// Section label tracking: 0.06 em at 11 pt.
    static let labelTracking: CGFloat = 0.66
}
