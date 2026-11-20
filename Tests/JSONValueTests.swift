import Foundation
import Testing
@testable import Broom

@Suite("Order-preserving JSON")
struct JSONValueTests {
    @Test("Key order, number text and nesting survive a parse and print")
    func roundTrip() throws {
        let text = """
            {
              "zeta": 1,
              "alpha": {
                "b": [
                  true,
                  false,
                  null,
                  1.50,
                  -2e3
                ],
                "a": "x"
              },
              "empty": {},
              "none": []
            }
            """

        #expect(try JSONParser.parse(text).text() == text)
    }

    @Test("Compact input is printed with two-space indentation, keys in their original order")
    func reformatted() throws {
        let value = try JSONParser.parse(#"{"b":1,"a":[{"y":2,"x":3}]}"#)

        #expect(value.text() == "{\n  \"b\": 1,\n  \"a\": [\n    {\n      \"y\": 2,\n      \"x\": 3\n    }\n  ]\n}")
    }

    @Test("Escapes and non-ASCII text are read and written back correctly")
    func strings() throws {
        let value = try JSONParser.parse(#"{"k":"quote \" slash \\ path a\/b tab \t nl \n e-acute \u00e9 emoji \ud83e\uddf9 café"}"#)

        #expect(value["k"] == .string("quote \" slash \\ path a/b tab \t nl \n e-acute é emoji 🧹 café"))
        #expect(try JSONParser.parse(value.text()) == value)
        #expect(value.text().contains("a/b"))
        #expect(value.text().contains("🧹"))
    }

    @Test("Control characters are written as lowercase four-digit unicode escapes")
    func controlCharacters() {
        let value = JSONValue.string("\u{01}\u{1f}")

        #expect(value.text() == #""\u0001\u001f""#)
    }

    @Test("Invalid JSON is rejected", arguments: [
        "", "{", "{\"a\":}", "{\"a\":1,}", "[1,]", "{'a':1}", "{\"a\":1} extra", "{\"a\":01x}", "\"unterminated",
        "{\"a\":\"bad \\q escape\"}", "{\"a\":\"\\ud83e\"}", "// comment\n{}", "{\"a\":tru}", "nul",
        "{\"a\":1,\"a\":2}",
    ])
    func invalid(text: String) {
        #expect(throws: JSONParser.Failure.self) {
            try JSONParser.parse(text)
        }
    }

    @Test("Setting a key keeps its position; a new key goes last; nil removes it")
    func editing() throws {
        var value = try JSONParser.parse(#"{"a":1,"b":2,"c":3}"#)

        value["b"] = .string("two")
        value["d"] = .bool(true)
        value["a"] = nil

        #expect(value == .object([
            .init(key: "b", value: .string("two")), .init(key: "c", value: .number("3")), .init(key: "d", value: .bool(true)),
        ]))
    }
}
