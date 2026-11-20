import AppKit
import SwiftUI

/// Draws the menu bar item: the broom, the running count when it is not zero, and an amber dot when something is waiting.
enum MenuBarIcon {
    static let glyphSize: CGFloat = 16
    static let dotSize: CGFloat = 7
    static let height: CGFloat = 18

    static func makeImage(runningCount: Int, hasWaiting: Bool) -> NSImage {
        let count = runningCount > 0 ? String(runningCount) : ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let countWidth = count.isEmpty ? 0 : ceil((count as NSString).size(withAttributes: attributes).width) + 4
        // Room on the right so the dot overhangs the corner instead of covering the glyph or digits.
        let size = NSSize(width: glyphSize + countWidth + (hasWaiting ? dotSize - 1 : 0), height: height)

        // The handler runs each time the item is drawn, so `labelColor` follows the menu bar's own appearance.
        let image = NSImage(size: size, flipped: true) { _ in
            // The same drawing as the popover's empty state, so the mark exists in one place.
            let frame = CGRect(x: 0, y: (height - glyphSize) / 2, width: glyphSize, height: glyphSize)
            let glyph = NSBezierPath(cgPath: BroomGlyph().path(in: frame).cgPath)
            glyph.lineWidth = 2 * glyphSize / 24
            glyph.lineCapStyle = .round
            glyph.lineJoinStyle = .round
            NSColor.labelColor.setStroke()
            glyph.stroke()

            if !count.isEmpty {
                let textSize = (count as NSString).size(withAttributes: attributes)
                (count as NSString).draw(
                    at: NSPoint(x: glyphSize + 4, y: (height - textSize.height) / 2), withAttributes: attributes
                )
            }
            if hasWaiting {
                // A darker amber on a light menu bar, where the bright one is too faint to notice (under 3:1).
                let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                NSColor(srgbRed: (isDark ? 0xF5 : 0xB4) / 255, green: (isDark ? 0x9E : 0x53) / 255, blue: (isDark ? 0x0B : 0x09) / 255, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: size.width - dotSize, y: 0, width: dotSize, height: dotSize)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// "Broom: N running, M waiting on you"
    static func accessibilityLabel(runningCount: Int, waitingCount: Int) -> String {
        "Broom: \(runningCount) running, \(waitingCount) waiting on you"
    }
}
