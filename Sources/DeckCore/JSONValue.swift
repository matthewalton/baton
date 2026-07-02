import Foundation

/// Minimal dynamic JSON representation for JSON-RPC payloads.
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Accessors

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    public var intValue: Int64? {
        if case let .number(value) = self, value.rounded() == value { return Int64(value) }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    // MARK: - Parsing / serializing

    public static func parse(_ data: Data) throws -> JSONValue {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return fromRaw(raw)
    }

    static func fromRaw(_ raw: Any) -> JSONValue {
        switch raw {
        case is NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map(fromRaw))
        case let object as [String: Any]:
            return .object(object.mapValues(fromRaw))
        default:
            return .null
        }
    }

    var rawValue: Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .number(value):
            return value.rounded() == value && abs(value) < 1e15 ? Int64(value) as Any : value as Any
        case let .string(value):
            return value
        case let .array(value):
            return value.map(\.rawValue)
        case let .object(value):
            return value.mapValues(\.rawValue)
        }
    }

    public func serialized() -> Data {
        (try? JSONSerialization.data(withJSONObject: rawValue, options: [.fragmentsAllowed, .sortedKeys])) ?? Data("null".utf8)
    }

    public func serializedString() -> String {
        String(data: serialized(), encoding: .utf8) ?? "null"
    }

    // MARK: - Construction sugar

    public static func int(_ value: Int64) -> JSONValue { .number(Double(value)) }
    public static func int(_ value: Int) -> JSONValue { .number(Double(value)) }
}
