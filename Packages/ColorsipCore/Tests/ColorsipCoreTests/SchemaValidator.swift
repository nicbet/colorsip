import Foundation
import ColorsipCore

/// A JSON Schema 2020-12 validator for the subset of keywords that
/// `schema/colorsip-palette.schema.json` uses. It refuses schemas with any other keyword, so the
/// schema can't rely on a keyword that would be silently ignored here.
struct SchemaValidator {
    struct UnsupportedKeyword: Error, CustomStringConvertible {
        let keyword: String
        let path: String
        var description: String { "unsupported schema keyword \(keyword) at \(path)" }
    }

    static let supportedKeywords: Set<String> = [
        // Validation
        "$ref", "$defs", "type", "properties", "required", "additionalProperties",
        "patternProperties", "propertyNames", "items", "minItems", "maxItems", "enum", "const",
        "pattern", "minimum", "maximum", "oneOf", "anyOf", "not",
        // Annotations, ignored
        "$schema", "$id", "$comment", "title", "description", "examples",
    ]

    let root: JSONValue

    init(schema: JSONValue) throws {
        root = schema
        try Self.checkKeywords(schema, path: "#")
    }

    /// The repository's `.colorsip` schema.
    static func colorsipPalette() throws -> SchemaValidator {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ColorsipCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ColorsipCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
            .appending(path: "schema/colorsip-palette.schema.json")
        return try SchemaValidator(schema: JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
    }

    /// Validation errors for `instance`; empty when it is valid.
    func errors(_ instance: JSONValue) -> [String] {
        var errors: [String] = []
        validate(instance, against: root, path: "$", &errors)
        return errors
    }

    func errors(_ data: Data) throws -> [String] {
        errors(try JSONDecoder().decode(JSONValue.self, from: data))
    }

    // MARK: - Keyword check

    private static func checkKeywords(_ schema: JSONValue, path: String) throws {
        guard case .object(let object) = schema else { return }  // `true`/`false` schemas
        for (keyword, value) in object {
            guard supportedKeywords.contains(keyword) else {
                throw UnsupportedKeyword(keyword: keyword, path: path)
            }
            switch keyword {
            case "properties", "patternProperties", "$defs":
                guard case .object(let children) = value else { continue }
                for (name, child) in children { try checkKeywords(child, path: "\(path)/\(keyword)/\(name)") }
            case "oneOf", "anyOf":
                guard case .array(let children) = value else { continue }
                for (i, child) in children.enumerated() { try checkKeywords(child, path: "\(path)/\(keyword)/\(i)") }
            case "items", "additionalProperties", "propertyNames", "not":
                try checkKeywords(value, path: "\(path)/\(keyword)")
            default:
                continue
            }
        }
    }

    // MARK: - Validation

    private func validate(_ instance: JSONValue, against schema: JSONValue, path: String, _ errors: inout [String]) {
        switch schema {
        case .bool(true): return
        case .bool(false): errors.append("\(path): not allowed"); return
        case .object(let keywords): validate(instance, keywords, path: path, &errors)
        default: errors.append("\(path): invalid schema")
        }
    }

    private func validate(
        _ instance: JSONValue, _ schema: [String: JSONValue], path: String, _ errors: inout [String]
    ) {
        if case .string(let ref) = schema["$ref"] {
            if let target = resolve(ref) {
                validate(instance, against: target, path: path, &errors)
            } else {
                errors.append("\(path): unresolved $ref \(ref)")
            }
        }
        if let type = schema["type"] {
            let types: [String] = switch type {
            case .string(let t): [t]
            case .array(let ts): ts.compactMap { if case .string(let t) = $0 { t } else { nil } }
            default: []
            }
            if !types.contains(where: { instance.hasType($0) }) {
                errors.append("\(path): expected type \(types.joined(separator: "|"))")
                return
            }
        }
        if case .array(let values) = schema["enum"], !values.contains(instance) {
            errors.append("\(path): not one of the enum values")
        }
        if let value = schema["const"], value != instance {
            errors.append("\(path): not the const value")
        }
        if case .string(let string) = instance {
            if case .string(let pattern) = schema["pattern"], !Self.matches(string, pattern) {
                errors.append("\(path): \"\(string)\" doesn't match \(pattern)")
            }
        }
        if case .number(let number) = instance {
            if case .number(let minimum) = schema["minimum"], number < minimum {
                errors.append("\(path): below minimum \(minimum)")
            }
            if case .number(let maximum) = schema["maximum"], number > maximum {
                errors.append("\(path): above maximum \(maximum)")
            }
        }
        if case .array(let items) = instance {
            if case .number(let min) = schema["minItems"], Double(items.count) < min {
                errors.append("\(path): fewer than \(Int(min)) items")
            }
            if case .number(let max) = schema["maxItems"], Double(items.count) > max {
                errors.append("\(path): more than \(Int(max)) items")
            }
            if let itemSchema = schema["items"] {
                for (i, item) in items.enumerated() {
                    validate(item, against: itemSchema, path: "\(path)[\(i)]", &errors)
                }
            }
        }
        if case .object(let object) = instance {
            validateObject(object, schema, path: path, &errors)
        }
        if case .array(let subschemas) = schema["oneOf"] {
            let passing = subschemas.filter { isValid(instance, $0, path) }.count
            if passing != 1 { errors.append("\(path): matches \(passing) oneOf subschemas, not 1") }
        }
        if case .array(let subschemas) = schema["anyOf"], !subschemas.contains(where: { isValid(instance, $0, path) }) {
            errors.append("\(path): matches no anyOf subschema")
        }
        if let not = schema["not"], isValid(instance, not, path) {
            errors.append("\(path): matches a `not` subschema")
        }
    }

    private func validateObject(
        _ object: [String: JSONValue], _ schema: [String: JSONValue], path: String, _ errors: inout [String]
    ) {
        if case .array(let required) = schema["required"] {
            for case .string(let name) in required where object[name] == nil {
                errors.append("\(path): missing required property \(name)")
            }
        }
        var properties: [String: JSONValue] = [:]
        if case .object(let p) = schema["properties"] { properties = p }
        var patterns: [String: JSONValue] = [:]
        if case .object(let p) = schema["patternProperties"] { patterns = p }
        for (name, value) in object {
            let childPath = "\(path).\(name)"
            if let propertyNames = schema["propertyNames"] {
                validate(.string(name), against: propertyNames, path: "\(childPath) (name)", &errors)
            }
            var matched = false
            if let subschema = properties[name] {
                matched = true
                validate(value, against: subschema, path: childPath, &errors)
            }
            for (pattern, subschema) in patterns where Self.matches(name, pattern) {
                matched = true
                validate(value, against: subschema, path: childPath, &errors)
            }
            if !matched, let additional = schema["additionalProperties"] {
                if additional == .bool(false) {
                    errors.append("\(path): unexpected property \(name)")
                } else {
                    validate(value, against: additional, path: childPath, &errors)
                }
            }
        }
    }

    private func isValid(_ instance: JSONValue, _ schema: JSONValue, _ path: String) -> Bool {
        var errors: [String] = []
        validate(instance, against: schema, path: path, &errors)
        return errors.isEmpty
    }

    /// Resolves a local JSON Pointer reference such as `#/$defs/token`.
    private func resolve(_ ref: String) -> JSONValue? {
        guard ref.hasPrefix("#") else { return nil }
        var node = root
        for part in ref.dropFirst().split(separator: "/") {
            let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            guard case .object(let object) = node, let next = object[key] else { return nil }
            node = next
        }
        return node
    }

    /// ECMA-262-style search: the pattern may match anywhere unless it is anchored.
    private static func matches(_ string: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
}

/// Any JSON value, for schema validation.
enum JSONValue: Hashable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func hasType(_ type: String) -> Bool {
        switch (type, self) {
        case ("null", .null), ("boolean", .bool), ("number", .number), ("string", .string),
            ("array", .array), ("object", .object):
            true
        case ("integer", .number(let n)):
            n.rounded() == n
        default:
            false
        }
    }
}
