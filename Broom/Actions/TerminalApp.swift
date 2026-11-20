import AppKit

/// The terminals and editors Broom knows how to bring forward or start a session in.
enum TerminalApp: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case iTerm
    case ghostty
    case warp
    case visualStudioCode
    case cursor

    var id: String { rawValue }

    var name: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        case .visualStudioCode: "Visual Studio Code"
        case .cursor: "Cursor"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        case .visualStudioCode: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        }
    }

    /// Whether the app can be handed a script to run. The others can only be opened at the folder.
    var runsScripts: Bool {
        switch self {
        case .terminal, .iTerm, .ghostty: true
        case .warp, .visualStudioCode, .cursor: false
        }
    }

    /// Where the app is installed, or `nil` if it is not.
    @MainActor
    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// The apps that are installed on this Mac.
    @MainActor
    static var installed: [TerminalApp] {
        allCases.filter { $0.applicationURL != nil }
    }
}
