import Foundation
import Testing
@testable import ColorsipCore

private func json(_ string: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
}

private func validator(_ schema: String) throws -> SchemaValidator {
    try SchemaValidator(schema: json(schema))
}

private func isValid(_ instance: String, _ schema: SchemaValidator) throws -> Bool {
    try schema.errors(json(instance)).isEmpty
}

@Suite("Test support: JSON Schema validator")
struct SchemaValidatorTests {
    @Test func refusesUnknownKeywords() throws {
        #expect(throws: SchemaValidator.UnsupportedKeyword.self) {
            try validator(#"{ "properties": { "a": { "format": "uuid" } } }"#)
        }
        #expect(throws: SchemaValidator.UnsupportedKeyword.self) {
            try validator(#"{ "unevaluatedProperties": false }"#)
        }
    }

    @Test func types() throws {
        let s = try validator(#"{ "type": ["integer", "null"] }"#)
        #expect(try isValid("1", s))
        #expect(try isValid("null", s))
        #expect(try !isValid("1.5", s))
        #expect(try !isValid("true", s))
        #expect(try !isValid(#""1""#, s))
    }

    @Test func objects() throws {
        let s = try validator(#"""
            { "type": "object", "required": ["a"],
              "properties": { "a": { "type": "string" } },
              "patternProperties": { "^x-": { "type": "number" } },
              "additionalProperties": false }
            """#)
        #expect(try isValid(#"{ "a": "1", "x-b": 2 }"#, s))
        #expect(try !isValid(#"{ "x-b": 2 }"#, s))
        #expect(try !isValid(#"{ "a": "1", "x-b": "2" }"#, s))
        #expect(try !isValid(#"{ "a": "1", "c": 2 }"#, s))
    }

    @Test func propertyNames() throws {
        let s = try validator(#"{ "propertyNames": { "pattern": "^[a-z]+$" } }"#)
        #expect(try isValid(#"{ "abc": 1 }"#, s))
        #expect(try !isValid(#"{ "a.b": 1 }"#, s))
    }

    @Test func arraysAndNumbers() throws {
        let s = try validator(#"""
            { "type": "array", "minItems": 2, "maxItems": 3,
              "items": { "type": "number", "minimum": 0, "maximum": 1 } }
            """#)
        #expect(try isValid("[0, 1]", s))
        #expect(try !isValid("[0]", s))
        #expect(try !isValid("[0, 0, 0, 0]", s))
        #expect(try !isValid("[0, 2]", s))
    }

    @Test func stringsEnumsConst() throws {
        #expect(try isValid(#""ab""#, validator(#"{ "pattern": "b" }"#)))
        #expect(try !isValid(#""ab""#, validator(#"{ "pattern": "^b" }"#)))
        #expect(try isValid(#""a""#, validator(#"{ "enum": ["a", "b"] }"#)))
        #expect(try !isValid(#""c""#, validator(#"{ "enum": ["a", "b"] }"#)))
        #expect(try isValid("1", validator(#"{ "const": 1 }"#)))
        #expect(try !isValid("2", validator(#"{ "const": 1 }"#)))
    }

    @Test func combinators() throws {
        let oneOf = try validator(#"{ "oneOf": [{ "type": "number" }, { "minimum": 0 }] }"#)
        #expect(try isValid("-1", oneOf))
        #expect(try !isValid("1", oneOf))  // matches both
        let anyOf = try validator(#"{ "anyOf": [{ "type": "string" }, { "type": "null" }] }"#)
        #expect(try isValid("null", anyOf))
        #expect(try !isValid("1", anyOf))
        let not = try validator(#"{ "not": { "type": "string" } }"#)
        #expect(try isValid("1", not))
        #expect(try !isValid(#""a""#, not))
    }

    @Test func refs() throws {
        let s = try validator(#"""
            { "$defs": { "id": { "type": "string", "pattern": "^[0-9]+$" } },
              "type": "array", "items": { "$ref": "#/$defs/id" } }
            """#)
        #expect(try isValid(#"["1", "22"]"#, s))
        #expect(try !isValid(#"["1", "x"]"#, s))
        #expect(try !isValid("[1]", validator(##"{ "items": { "$ref": "#/$defs/missing" } }"##)))
    }
}
