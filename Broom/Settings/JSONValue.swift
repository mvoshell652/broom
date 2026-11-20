import Foundation

/// A JSON document that keeps object keys in their original order and numbers exactly as written,
/// so a settings file can be edited without reshuffling what the user wrote.
indirect enum JSONValue: Equatable, Sendable {
    case object([Member])
    case array([JSONValue])
    case string(String)
    /// The number's original text, for example `1e3` or `0.10`.
    case number(String)
    case bool(Bool)
    case null

    struct Member: Equatable, Sendable {
        var key: String
        var value: JSONValue
    }

    /// The value for `key` if this is an object that has it.
    subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case .object(var members) = self else { return }
            let index = members.firstIndex { $0.key == key }
            switch (index, newValue) {
            case (let index?, let value?): members[index].value = value
            case (let index?, nil): members.remove(at: index)
            case (nil, let value?): members.append(Member(key: key, value: value))
            case (nil, nil): break
            }
            self = .object(members)
        }
    }
}
