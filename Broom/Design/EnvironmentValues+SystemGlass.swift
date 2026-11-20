import SwiftUI

extension EnvironmentValues {
    /// Whether controls may use the system's glass styles. Off when drawing to an image, which cannot draw them.
    var allowsSystemGlass: Bool {
        get { self[AllowsSystemGlassKey.self] }
        set { self[AllowsSystemGlassKey.self] = newValue }
    }

    // A key written out rather than `@Entry`: that macro's plugin ships with Xcode only, and Broom must build with the
    // Command Line Tools alone.
    private struct AllowsSystemGlassKey: EnvironmentKey {
        static let defaultValue = true
    }
}
