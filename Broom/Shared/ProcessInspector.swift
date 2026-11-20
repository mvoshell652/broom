import Darwin

/// Reads facts about running processes with libproc.
public enum ProcessInspector {
    /// The process's short name, or an empty string if it cannot be read.
    public static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return string(from: buffer)
    }

    /// The path of the process's executable, or an empty string if it cannot be read.
    public static func executablePath(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return string(from: buffer)
    }

    /// The process's parent, or `nil` if it cannot be read.
    public static func parent(of pid: Int32) -> Int32? {
        bsdInfo(of: pid).map { Int32(bitPattern: $0.pbi_ppid) }
    }

    /// When the process started, as seconds since 1970, or `nil` if it cannot be read.
    public static func startTime(of pid: Int32) -> Double? {
        bsdInfo(of: pid).map { Double($0.pbi_start_tvsec) + Double($0.pbi_start_tvusec) / 1_000_000 }
    }

    /// The process's working directory, or `nil` if it cannot be read.
    public static func workingDirectory(of pid: Int32) -> String? {
        var paths = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, size) == size else { return nil }
        let path = withUnsafeBytes(of: &paths.pvi_cdir.vip_path) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// Whether a process with this name and executable is Claude Code.
    ///
    /// The docs do not promise the name: a native install runs `~/.local/share/claude/versions/<version>`,
    /// whose process name is the version number.
    public static func isClaude(name: String, executablePath: String) -> Bool {
        name == "claude"
            || executablePath.hasSuffix("/claude")
            || executablePath.contains("/claude/versions/")
    }

    /// Whether `pid` is a Claude Code process.
    public static func isClaude(_ pid: Int32) -> Bool {
        isClaude(name: name(of: pid), executablePath: executablePath(of: pid))
    }

    /// Returns `pid` or its nearest ancestor that is Claude Code, looking at most `maximumDepth` levels up.
    ///
    /// A hook command is often run through a shell, so its direct parent is not always Claude Code.
    public static func claudeAncestor(of pid: Int32, maximumDepth: Int = 8) -> Int32? {
        var current = pid
        for _ in 0..<maximumDepth {
            guard current > 1 else { return nil }
            if isClaude(current) { return current }
            guard let next = parent(of: current), next != current else { return nil }
            current = next
        }
        return nil
    }

    /// The value of one environment variable of the process, or `nil` if it is unset or cannot be read.
    ///
    /// Only the named variable is kept; the rest of the environment, which can hold tokens, is dropped at once.
    public static func environmentValue(named name: String, of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return environmentValue(named: name, inProcessArguments: buffer.prefix(size))
    }

    /// The value of `name` in a `KERN_PROCARGS2` buffer: the argument count, the executable path, the arguments,
    /// then the environment, each string ending in a NUL.
    static func environmentValue(named name: String, inProcessArguments buffer: some Collection<UInt8>) -> String? {
        let bytes = Array(buffer)
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        let argumentCount = bytes.prefix(4).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = 4
        // The executable path, then the NULs that pad it.
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var strings: [ArraySlice<UInt8>] = []
        while index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            if index == start { break }
            strings.append(bytes[start..<index])
            index += 1
        }
        let prefix = Array("\(name)=".utf8)
        for entry in strings.dropFirst(argumentCount) where entry.starts(with: prefix) {
            return String(decoding: entry.dropFirst(prefix.count), as: UTF8.self)
        }
        return nil
    }

    private static func bsdInfo(of pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func string(from buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
