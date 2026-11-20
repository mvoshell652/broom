import Foundation

/// Parses strict JSON into a `JSONValue`.
struct JSONParser {
    struct Failure: Error, Equatable {
        /// Byte offset where parsing stopped.
        var offset: Int
    }

    private let bytes: [UInt8]
    private var index = 0

    /// Parses `text`, which must hold exactly one JSON value.
    static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(text.utf8))
        parser.skipWhitespace()
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw Failure(offset: parser.index) }
        return value
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func expect(_ literal: String) throws {
        let expected = Array(literal.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
            throw Failure(offset: index)
        }
        index += expected.count
    }

    private mutating func value() throws -> JSONValue {
        switch current {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default: return try number()
        }
    }

    private mutating func object() throws -> JSONValue {
        index += 1
        var members: [JSONValue.Member] = []
        skipWhitespace()
        if current == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard current == UInt8(ascii: "\"") else { throw Failure(offset: index) }
            let key = try string()
            skipWhitespace()
            try expect(":")
            skipWhitespace()
            // Readers disagree on which duplicate wins, so editing such a file could change the wrong one.
            guard !members.contains(where: { $0.key == key }) else { throw Failure(offset: index) }
            members.append(JSONValue.Member(key: key, value: try value()))
            skipWhitespace()
            if current == UInt8(ascii: ",") {
                index += 1
            } else {
                try expect("}")
                return .object(members)
            }
        }
    }

    private mutating func array() throws -> JSONValue {
        index += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if current == UInt8(ascii: "]") {
            index += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            elements.append(try value())
            skipWhitespace()
            if current == UInt8(ascii: ",") {
                index += 1
            } else {
                try expect("]")
                return .array(elements)
            }
        }
    }

    private mutating func number() throws -> JSONValue {
        let start = index
        while let byte = current, "+-0123456789.eE".utf8.contains(byte) {
            index += 1
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        guard !text.isEmpty, Double(text) != nil else { throw Failure(offset: start) }
        return .number(text)
    }

    private mutating func string() throws -> String {
        index += 1
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []

        func flush() {
            scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars)
            raw.removeAll(keepingCapacity: true)
        }

        while let byte = current {
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                flush()
                return String(scalars)
            case UInt8(ascii: "\\"):
                flush()
                guard let escape = current else { throw Failure(offset: index) }
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    var code = try hexQuad()
                    if (0xD800...0xDBFF).contains(code) {
                        try expect("\\u")
                        let low = try hexQuad()
                        guard (0xDC00...0xDFFF).contains(low) else { throw Failure(offset: index) }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw Failure(offset: index) }
                    scalars.append(scalar)
                default:
                    throw Failure(offset: index)
                }
            case 0..<0x20:
                throw Failure(offset: index)
            default:
                raw.append(byte)
            }
        }
        throw Failure(offset: index)
    }

    private mutating func hexQuad() throws -> UInt32 {
        guard index + 4 <= bytes.count,
              let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
        else { throw Failure(offset: index) }
        index += 4
        return value
    }
}
