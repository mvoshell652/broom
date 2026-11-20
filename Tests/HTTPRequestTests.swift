import Foundation
import Testing
@testable import BroomCore

@Suite("HTTPRequest")
struct HTTPRequestTests {
    private func parse(_ text: String) -> HTTPRequest.ParseResult {
        HTTPRequest.parse(Data(text.utf8))
    }

    @Test("A complete request parses into method, path, lowercased headers and body")
    func complete() {
        let result = parse("POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer abc\r\nContent-Length: 7\r\n\r\n{\"a\":1}")

        #expect(result == .complete(HTTPRequest(
            method: "POST", path: "/v1/events",
            headers: ["host": "127.0.0.1", "authorization": "Bearer abc", "content-length": "7"],
            body: Data("{\"a\":1}".utf8)
        )))
    }

    @Test("A request cut anywhere before its end needs more data")
    func partial() {
        let full = "POST /v1/events HTTP/1.1\r\nContent-Length: 7\r\n\r\n{\"a\":1}"

        for length in 0..<full.utf8.count {
            #expect(HTTPRequest.parse(Data(full.utf8.prefix(length))) == .needsMoreData, "cut at \(length)")
        }
    }

    @Test("Bytes after the declared body are ignored")
    func extraBytes() {
        guard case .complete(let request) = parse("POST / HTTP/1.1\r\nContent-Length: 2\r\n\r\nokEXTRA") else {
            Issue.record("did not parse")
            return
        }
        #expect(request.body == Data("ok".utf8))
    }

    @Test("A request with no body is complete at the blank line")
    func noBody() {
        #expect(parse("GET /v1/events HTTP/1.1\r\nHost: x\r\n\r\n") == .complete(
            HTTPRequest(method: "GET", path: "/v1/events", headers: ["host": "x"], body: Data())
        ))
    }

    @Test("Malformed or unsupported requests are rejected with a status", arguments: [
        ("NONSENSE\r\n\r\n", 400),
        ("POST /v1/events SPDY/3\r\n\r\n", 400),
        ("POST / HTTP/1.1\r\nno colon here\r\n\r\n", 400),
        ("POST / HTTP/1.1\r\nContent-Length: nine\r\n\r\n", 400),
        ("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n", 400),
        ("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", 501),
        ("POST / HTTP/1.1\r\nContent-Length: 999999999\r\n\r\n", 413),
    ])
    func rejected(request: String, status: Int) {
        #expect(parse(request) == .rejected(status: status))
    }

    @Test("A request refused on its headers is rejected before its body arrives")
    func earlyRefusal() {
        let head = Data("POST /v1/events HTTP/1.1\r\nContent-Length: 8000000\r\n\r\n".utf8)

        let refused = HTTPRequest.parse(head) { method, path, headers in
            method == "POST" && path == "/v1/events" && headers["authorization"] == nil ? 401 : nil
        }

        #expect(refused == .rejected(status: 401))
        // Without a refusal the same bytes wait for the 8 MB body.
        #expect(HTTPRequest.parse(head) == .needsMoreData)
    }

    @Test("Headers that never end are rejected once they pass the limit")
    func oversizedHeaders() {
        let request = "POST / HTTP/1.1\r\nX-Padding: " + String(repeating: "a", count: HTTPRequest.maximumHeaderLength)

        #expect(parse(request) == .rejected(status: 431))
    }
}
