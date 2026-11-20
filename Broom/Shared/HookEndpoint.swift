import Foundation

/// Where hook events are sent and how they are authorised. Shared by the app and `broom-hook`.
public enum HookEndpoint {
    /// The loopback port the hook server listens on unless `BROOM_HOOK_PORT` says otherwise.
    public static let defaultPort: UInt16 = 47811
    public static let path = "/v1/events"

    /// The loopback port. `BROOM_HOOK_PORT` overrides it, for tests.
    public static func port(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt16 {
        environment["BROOM_HOOK_PORT"].flatMap(UInt16.init) ?? defaultPort
    }

    /// Broom's folder in Application Support. `BROOM_SUPPORT_DIR` overrides it, for tests.
    public static func supportDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["BROOM_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return URL.applicationSupportDirectory.appending(path: "Broom")
    }

    /// The file holding the bearer token, readable only by the user.
    public static func tokenFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        supportDirectory(environment: environment).appending(path: "token")
    }
}
