import BroomShared
import Darwin
import Foundation

/// Finds running Claude Code processes with libproc, without shelling out to `ps`.
public struct ProcessMonitor: Sendable {
    public init() {}

    /// Returns every Claude Code process owned by a user this process can inspect. Runs off the caller's actor.
    @concurrent
    public func snapshot() async -> [ClaudeProcess] {
        Self.allProcessIDs().compactMap { pid in
            pid != getpid() && ProcessInspector.isClaude(pid) ? Self.process(pid) : nil
        }
    }

    /// Returns the working directory and start time of `pid`, or `nil` if it cannot be inspected.
    static func process(_ pid: Int32) -> ClaudeProcess? {
        guard let cwd = ProcessInspector.workingDirectory(of: pid), let started = ProcessInspector.startTime(of: pid) else {
            return nil
        }
        return ClaudeProcess(
            pid: pid,
            cwd: URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path,
            startedAt: Date(timeIntervalSince1970: started)
        )
    }

    private static func allProcessIDs() -> [Int32] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size)))
        return count > 0 ? Array(pids.prefix(count)).filter { $0 > 0 } : []
    }
}
