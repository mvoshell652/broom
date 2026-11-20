import SwiftUI

extension EnvironmentValues {
    /// Whether controls may use the system's glass styles. Off when drawing to an image, which cannot draw them.
    var allowsSystemGlass: Bool {
        get { self[AllowsSystemGlassKey.self] }
        set { self[AllowsSystemGlassKey.self] = newValue }
    }

    // A key written out rather than `@Entry`: that macro's plugin is missing from the Command Line Tools, which are all
    // Broom needs to build.
    private struct AllowsSystemGlassKey: EnvironmentKey {
        static let defaultValue = true
    }
}
