import SwiftUI

/// A titled group of rows in the Live view.
struct SectionView<Tint: ShapeStyle, Content: View>: View {
    let title: String
    /// Shown after the title: a count, or a note such as "fade after 24h".
    let detail: String
    let tint: Tint
    var rowSpacing: CGFloat = 4
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text("\(title.localizedUppercase) · \(detail)")
                .font(.subheadline.weight(.semibold))
                .tracking(BroomStyle.labelTracking)
                .foregroundStyle(tint)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}
