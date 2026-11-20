import Foundation

extension JSONValue {
    /// The document as indented text. `unit` is one level of indentation; Claude Code writes two spaces.
    func text(indent: Int = 0, unit: String = "  ") -> String {
        let padding = String(repeating: unit, count: indent + 1)
        let closing = String(repeating: unit, count: indent)
        switch self {
        case .object(let members):
            guard !members.isEmpty else { return "{}" }
            let lines = members.map { "\(padding)\(Self.quoted($0.key)): \($0.value.text(indent: indent + 1, unit: unit))" }
            return "{\n\(lines.joined(separator: ",\n"))\n\(closing)}"
        case .array(let elements):
            guard !elements.isEmpty else { return "[]" }
            let lines = elements.map { "\(padding)\($0.text(indent: indent + 1, unit: unit))" }
            return "[\n\(lines.joined(separator: ",\n"))\n\(closing)]"
        case .string(let string):
            return Self.quoted(string)
        case .number(let number):
            return number
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private static func quoted(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
