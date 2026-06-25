import Foundation

/// JSON value used by custom canvas object payloads.
///
/// The package keeps custom objects in the same document as strokes without
/// requiring every app-defined type to be known at compile time. Register a type
/// ID in `LabyrinthObjectRegistry`, then encode your own Codable payload into
/// this value.
public enum LabyrinthJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([LabyrinthJSONValue])
    case object([String: LabyrinthJSONValue])

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: LabyrinthJSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(LabyrinthJSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [LabyrinthJSONValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(LabyrinthJSONValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in values {
                try container.encode(value, forKey: DynamicCodingKey(key))
            }
        }
    }

    public static func encodePayload<T: Encodable>(_ payload: T) throws -> LabyrinthJSONValue {
        let data = try LabyrinthJSONCodec.encoder().encode(payload)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        return try LabyrinthJSONValue(jsonObject: jsonObject)
    }

    public func decodePayload<T: Decodable>(as type: T.Type = T.self) throws -> T {
        let object = toJSONObject()
        let data = try JSONSerialization.data(withJSONObject: object)
        return try LabyrinthJSONCodec.decoder().decode(T.self, from: data)
    }

    public init(jsonObject: Any) throws {
        switch jsonObject {
        case is NSNull:
            self = .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as Bool:
            self = .bool(value)
        case let value as String:
            self = .string(value)
        case let values as [Any]:
            self = .array(try values.map { try LabyrinthJSONValue(jsonObject: $0) })
        case let values as [String: Any]:
            var object: [String: LabyrinthJSONValue] = [:]
            for (key, value) in values {
                object[key] = try LabyrinthJSONValue(jsonObject: value)
            }
            self = .object(object)
        default:
            throw LabyrinthCanvasError.invalidPayload("Unsupported JSON payload value: \(type(of: jsonObject))")
        }
    }

    public func toJSONObject() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map { $0.toJSONObject() }
        case .object(let values):
            return values.mapValues { $0.toJSONObject() }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
