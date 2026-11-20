import AppKit
import BroomCore
import SwiftUI

/// `Broom --render <folder>`: writes PNGs of the popover and menu bar item from sample data, to check the design without clicking.
@MainActor
enum RenderCommand {
    static func run(outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            try write(
                PopoverRoot(tab: .constant(.live), sections: SampleData.everything, now: SampleData.now, scheduledTasks: SampleData.scheduledTasks, scrolls: false),
                scheme: scheme, to: outputDirectory.appending(path: "popover-\(name).png")
            )
            try write(
                PopoverRoot(tab: .constant(.live), sections: SampleData.everything, now: SampleData.now, toast: "Resume command copied", selectedID: "r2", scrolls: false),
                scheme: scheme, to: outputDirectory.appending(path: "selected-\(name).png")
            )
            for (tab, file) in [(PopoverTab.inbox, "inbox"), (.history, "history")] {
                try write(
                    PopoverRoot(
                        tab: .constant(tab), sections: SampleData.everything, inbox: SampleData.inbox,
                        sweepCards: SampleData.sweepCards, history: SampleData.history, now: SampleData.now, scrolls: false
                    ),
                    scheme: scheme, to: outputDirectory.appending(path: "\(file)-\(name).png")
                )
            }
            try write(
                PopoverRoot(tab: .constant(.live), sections: SampleData.empty, now: SampleData.now, offersConnect: true, scrolls: false),
                scheme: scheme, to: outputDirectory.appending(path: "empty-\(name).png")
            )
            try write(
                HStack(spacing: 24) {
                    MenuBarLabel(runningCount: 0, waitingCount: 0)
                    MenuBarLabel(runningCount: 2, waitingCount: 0)
                    MenuBarLabel(runningCount: 2, waitingCount: 1)
                    MenuBarLabel(runningCount: 12, waitingCount: 3)
                }
                .padding(12)
                .background(scheme == .dark ? Color(hex: 0x1E1E1E) : Color(hex: 0xECECEC)),
                scheme: scheme, to: outputDirectory.appending(path: "menubar-\(name).png")
            )
        }
        print("Wrote 14 images to \(outputDirectory.path)")
    }

    private static func write(_ view: some View, scheme: ColorScheme, to url: URL) throws {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        var data: Data?
        // AppKit colors (the menu bar item's `labelColor`) follow the current appearance, not SwiftUI's color scheme.
        appearance?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
            renderer.scale = 2
            data = renderer.nsImage?.tiffRepresentation
                .flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:])
        }
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
