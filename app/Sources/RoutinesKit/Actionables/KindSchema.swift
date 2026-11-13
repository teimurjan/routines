import Foundation

/// The shape of a kind: a small subset of JSON Schema. See specs/004-actionables/research.md, section 2.
public struct KindSchema: Equatable, Sendable {
    public indirect enum Additional: Equatable, Sendable {
        case allowed
        case forbidden
        case schema(KindSchema)
    }

    public var types: [String]?
    public var properties: [String: KindSchema]
    public var required: [String]
    public var items: [KindSchema]
    public var allowedValues: [JSONValue]?
    public var additional: Additional
    public var maxLength: Int?

    /// The keywords that a check reads. `title` and `description` only annotate.
    static let keywords: Set<String> = ["type", "properties", "required", "items", "enum", "additionalProperties", "maxLength", "title", "description"]
    static let typeNames: Set<String> = ["object", "array", "string", "number", "integer", "boolean", "null"]

    /// A kind that no plugin declares accepts any object.
    public static let anyObject = KindSchema(types: ["object"], properties: [:], required: [], items: [], allowedValues: nil, additional: .allowed, maxLength: nil)

    public static func parse(_ value: JSONValue, path: String = "schema") -> Result<KindSchema, HostError> {
        guard case .object(let object) = value else { return .failure(.failed("\(path) must be an object")) }
        if let keyword = object.keys.sorted().first(where: { !keywords.contains($0) }) {
            return .failure(.failed("\(path) has the keyword \(keyword), which the host does not check"))
        }
        var schema = KindSchema(types: nil, properties: [:], required: [], items: [], allowedValues: nil, additional: .allowed, maxLength: nil)
        switch object["type"] {
        case nil: break
        case .string(let name)?: schema.types = [name]
        case .array(let names)?: schema.types = names.compactMap { if case .string(let name) = $0 { name } else { nil } }
        default: return .failure(.failed("\(path).type must be a string or a list"))
        }
        if let unknown = schema.types?.first(where: { !typeNames.contains($0) }) { return .failure(.failed("\(path).type \(unknown) is unknown")) }
        if let properties = object["properties"] {
            guard case .object(let fields) = properties else { return .failure(.failed("\(path).properties must be an object")) }
            for (name, field) in fields {
                switch parse(field, path: "\(path).properties.\(name)") {
                case .success(let parsed): schema.properties[name] = parsed
                case .failure(let error): return .failure(error)
                }
            }
        }
        if let required = object["required"] {
            guard case .array(let names) = required else { return .failure(.failed("\(path).required must be a list")) }
            schema.required = names.compactMap { if case .string(let name) = $0 { name } else { nil } }
        }
        switch object["items"] {
        case nil: break
        case .array(let list)?:
            for (index, item) in list.enumerated() {
                switch parse(item, path: "\(path).items[\(index)]") {
                case .success(let parsed): schema.items.append(parsed)
                case .failure(let error): return .failure(error)
                }
            }
        case let item?:
            switch parse(item, path: "\(path).items") {
            case .success(let parsed): schema.items = [parsed]
            case .failure(let error): return .failure(error)
            }
        }
        if let allowed = object["enum"] {
            guard case .array(let values) = allowed else { return .failure(.failed("\(path).enum must be a list")) }
            schema.allowedValues = values
        }
        switch object["additionalProperties"] {
        case nil, .bool(true)?: break
        case .bool(false)?: schema.additional = .forbidden
        case let nested?:
            switch parse(nested, path: "\(path).additionalProperties") {
            case .success(let parsed): schema.additional = .schema(parsed)
            case .failure(let error): return .failure(error)
            }
        }
        if let limit = object["maxLength"] {
            guard case .number(let number) = limit, number >= 0, number == number.rounded() else { return .failure(.failed("\(path).maxLength must be a whole number")) }
            schema.maxLength = Int(number)
        }
        return .success(schema)
    }

    /// The first fault names its path, for example `data.repo must be a string`.
    public func validate(_ value: JSONValue, path: String = "data") -> Result<Void, HostError> {
        if let types, !types.contains(where: { Self.matches(value, type: $0) }) {
            return .failure(.failed("\(path) must be \(types.map(Self.article).joined(separator: " or "))"))
        }
        if let allowedValues, !allowedValues.contains(value) {
            return .failure(.failed("\(path) must be one of \(allowedValues.map(Self.describe).joined(separator: ", "))"))
        }
        switch value {
        case .string(let text):
            if let maxLength, text.count > maxLength { return .failure(.failed("\(path) must have at most \(maxLength) characters")) }
        case .array(let list):
            for (index, item) in list.enumerated() {
                guard let schema = items.isEmpty ? nil : items[min(index, items.count - 1)] else { break }
                if case .failure(let error) = schema.validate(item, path: "\(path)[\(index)]") { return .failure(error) }
            }
        case .object(let object):
            if let missing = required.first(where: { object[$0] == nil }) { return .failure(.failed("\(path).\(missing) is required")) }
            for name in object.keys.sorted() {
                let field = object[name]!
                if let schema = properties[name] {
                    if case .failure(let error) = schema.validate(field, path: "\(path).\(name)") { return .failure(error) }
                    continue
                }
                switch additional {
                case .allowed: continue
                case .forbidden: return .failure(.failed("\(path).\(name) is not allowed"))
                case .schema(let schema):
                    if case .failure(let error) = schema.validate(field, path: "\(path).\(name)") { return .failure(error) }
                }
            }
        default: break
        }
        return .success(())
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("number", .number), ("boolean", .bool), ("null", .null): true
        case ("integer", .number(let number)): number == number.rounded()
        default: false
        }
    }

    private static func article(_ type: String) -> String {
        switch type {
        case "object", "array", "integer": "an \(type)"
        case "null": "null"
        default: "a \(type)"
        }
    }

    private static func describe(_ value: JSONValue) -> String {
        if case .string(let text) = value { return text }
        return Reply.encode(value) ?? "?"
    }
}
