import SwiftUI

/// A color with a light and a dark value, usable anywhere a `ShapeStyle` is.
struct ColorToken: ShapeStyle, Equatable, Sendable {
    /// 0xRRGGBB
    let light: UInt32
    let dark: UInt32

    func resolve(in environment: EnvironmentValues) -> Color {
        Color(hex: environment.colorScheme == .dark ? dark : light)
    }
}
