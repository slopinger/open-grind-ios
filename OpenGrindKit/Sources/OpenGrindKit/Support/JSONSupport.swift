import Foundation

/// A Grindr profile id. The API sends them as numbers in most places and as
/// numeric strings in a few, so models decode both.
public typealias ProfileID = Int

extension Date {
    /// A date from the API's Unix timestamps in milliseconds.
    init(milliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    /// Unix time in milliseconds, as the API expects it.
    var milliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}

extension KeyedDecodingContainer {
    /// An integer the API sends either as a number or as a numeric string.
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key), value.rounded() == value,
            abs(value) < 1e15
        {
            return Int(value)
        }
        let string = try decode(String.self, forKey: key)
        guard let value = Int(string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self, debugDescription: "Expected an integer, got \(string)")
        }
        return value
    }

    /// Like ``decodeFlexibleInt(forKey:)``, `nil` when missing, `null` or malformed.
    func flexibleInt(forKey key: Key) -> Int? {
        try? decodeFlexibleInt(forKey: key)
    }

    /// A value that is `nil` when missing, `null`, or of a shape this version
    /// does not model. Used for fields that must never fail a whole response.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// A millisecond timestamp, `nil` when missing, zero, `null` or malformed.
    func timestamp(forKey key: Key) -> Date? {
        guard let value = lenient(Double.self, forKey: key), value > 0 else { return nil }
        return Date(milliseconds: Int64(value))
    }

    /// An array that keeps the elements it can decode and drops the others.
    func lossyArray<Element: Decodable>(of type: Element.Type, forKey key: Key) -> [Element] {
        lenient(LossyArray<Element>.self, forKey: key)?.elements ?? []
    }

    /// A `Bool` that defaults to `false` when missing or `null`, as the server
    /// leaves out default values.
    func flag(forKey key: Key) -> Bool {
        lenient(Bool.self, forKey: key) ?? false
    }
}

/// Decodes an array, dropping elements that fail to decode instead of failing
/// the whole array. The server adds variants faster than clients learn them.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not advance the container; skip the element.
                _ = try? container.decode(Skipped.self)
            }
        }
        self.elements = elements
    }

    private struct Skipped: Decodable {
        init(from decoder: any Decoder) {}
    }
}

/// A JSON document built in code, for request bodies and websocket payloads
/// whose shape depends on what changed.
public enum JSONValue: Hashable, Sendable, Encodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public static func int(_ value: Int) -> JSONValue { .number(Double(value)) }

    public static func optional(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    public static func optional(_ value: Int?) -> JSONValue { value.map(JSONValue.int) ?? .null }

    public static func optional(_ value: Double?) -> JSONValue {
        value.map(JSONValue.number) ?? .null
    }

    public static func ints(_ values: some Sequence<Int>) -> JSONValue {
        .array(values.map(JSONValue.int))
    }
}

enum JSON {
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
