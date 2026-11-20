import Foundation

/// A minimal HTTP/1.1 request, as much as the hook endpoint needs.
struct HTTPRequest: Equatable, Sendable {
    var method: String
    var path: String
    /// Header names are lowercased.
    var headers: [String: String]
    var body: Data

    /// What parsing the bytes received so far produced.
    enum ParseResult: Equatable, Sendable {
        /// The request is incomplete; read more.
        case needsMoreData
        case complete(HTTPRequest)
        /// The request cannot be served; answer with this status.
        case rejected(status: Int)
    }

    /// Largest header block accepted.
    static let maximumHeaderLength = 16 * 1024
    /// Largest body accepted. Hook payloads carry tool input and output, so this is generous.
    static let maximumBodyLength = 8 * 1024 * 1024

    /// Parses everything received so far on a connection.
    ///
    /// `authorize` is called once the headers are in, before any body is waited for; returning a status rejects
    /// the request there, so an unauthorised client cannot make the server buffer a large body.
    static func parse(_ data: Data, authorize: (_ method: String, _ path: String, _ headers: [String: String]) -> Int? = { _, _, _ in nil }) -> ParseResult {
        let terminator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: terminator) else {
            return data.count > maximumHeaderLength ? .rejected(status: 431) : .needsMoreData
        }
        guard headerEnd.lowerBound - data.startIndex <= maximumHeaderLength,
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8)
        else { return .rejected(status: 400) }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .rejected(status: 400) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .rejected(status: 400) }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { return .rejected(status: 501) }
        if let status = authorize(String(requestLine[0]), String(requestLine[1]), headers) {
            return .rejected(status: status)
        }

        var length = 0
        if let declared = headers["content-length"] {
            guard let value = Int(declared), value >= 0 else { return .rejected(status: 400) }
            guard value <= maximumBodyLength else { return .rejected(status: 413) }
            length = value
        }
        let received = data[headerEnd.upperBound...]
        guard received.count >= length else { return .needsMoreData }

        return .complete(HTTPRequest(
            method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data(received.prefix(length))
        ))
    }
}
