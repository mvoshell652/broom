import Foundation

/// Waits until `condition` holds, checking again every 20 ms, and returns whether it did before `timeout`.
///
/// For things that happen on another process or task with no event to await. Returns instead of throwing so the caller's
/// `#expect` or `#require` names what did not happen.
func eventually(
    timeout: Duration = .seconds(10),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while true {
        if await condition() { return true }
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
}
