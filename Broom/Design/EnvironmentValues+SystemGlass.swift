import SwiftUI

extension EnvironmentValues {
    /// Whether controls may use the system's glass styles. Off when drawing to an image, which cannot draw them.
    @Entry var allowsSystemGlass = true
}
