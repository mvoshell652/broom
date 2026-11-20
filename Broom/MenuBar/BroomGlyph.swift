import SwiftUI

/// The broom mark, drawn to fill its frame. Stroke it; it has no fill.
struct BroomGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // A 24-unit drawing.
        var path = Path()
        path.move(to: CGPoint(x: 19, y: 3))
        path.addLine(to: CGPoint(x: 11.5, y: 10.5))
        path.move(to: CGPoint(x: 9, y: 9))
        path.addLine(to: CGPoint(x: 15, y: 15))
        path.move(to: CGPoint(x: 8.5, y: 9.5))
        path.addLine(to: CGPoint(x: 3, y: 15))
        path.addLine(to: CGPoint(x: 9, y: 21))
        path.addLine(to: CGPoint(x: 14.5, y: 15.5))
        path.move(to: CGPoint(x: 6, y: 18))
        path.addLine(to: CGPoint(x: 8, y: 16))

        let scale = min(rect.width, rect.height) / 24
        return path.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        )
    }
}
