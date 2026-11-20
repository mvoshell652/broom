// broom-hook: forwards one Claude Code hook event to Broom.
//
// Claude Code runs this for every hook. It must never slow Claude Code down or change what it does:
// it stops itself after 300 ms, always exits 0, and writes nothing to stdout or stderr.
// (Stdout from a SessionStart or UserPromptSubmit hook is injected into Claude's context, and exit 2 blocks the tool call.)

import BroomShared
import Darwin
import Foundation

signal(SIGALRM) { _ in _exit(0) }
signal(SIGPIPE, SIG_IGN)
ualarm(300_000, 0)

/// Sends `request` to Broom on the loopback interface and waits for it to answer or hang up.
func send(_ request: Data, port: UInt16) {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    // Broom is not running: drop the event.
    guard connected == 0 else { return }

    var sent = 0
    while sent < request.count {
        let written = request.withUnsafeBytes { write(descriptor, $0.baseAddress! + sent, request.count - sent) }
        guard written > 0 else { return }
        sent += written
    }
    // Wait for the reply so the event is not lost to an early close. The alarm bounds this.
    var reply = [UInt8](repeating: 0, count: 256)
    while read(descriptor, &reply, reply.count) > 0 {}
}

let environment = ProcessInfo.processInfo.environment
// Read with `read`, not FileHandle: FileHandle raises an exception, and so writes to stderr, when stdin is closed.
var input = Data()
var chunk = [UInt8](repeating: 0, count: 64 * 1024)
while true {
    let count = read(STDIN_FILENO, &chunk, chunk.count)
    guard count > 0 else { break }
    input.append(contentsOf: chunk[0..<count])
}

guard var payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
      let token = try? String(contentsOf: HookEndpoint.tokenFile(environment: environment), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !token.isEmpty
else { exit(0) }

payload["received_at"] = Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
if let pid = ProcessInspector.claudeAncestor(of: getppid()) {
    payload["pid"] = Int(pid)
}
guard let body = try? JSONSerialization.data(withJSONObject: payload) else { exit(0) }

var request = Data("""
    POST \(HookEndpoint.path) HTTP/1.1\r
    Host: 127.0.0.1\r
    Authorization: Bearer \(token)\r
    Content-Type: application/json\r
    Content-Length: \(body.count)\r
    Connection: close\r
    \r

    """.utf8)
request.append(body)
send(request, port: HookEndpoint.port(environment: environment))
exit(0)
