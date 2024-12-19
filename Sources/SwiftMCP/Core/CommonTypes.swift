import Foundation

/// A request ID type that can be string or int.
public enum RequestID: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "RequestId must be string or int")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let stringValue): try container.encode(stringValue)
        case .int(let intValue): try container.encode(intValue)
        }
    }
}

/// AnyCodable helper for dynamic JSON fields.
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let boolValue as Bool: try container.encode(boolValue)
        case let intValue as Int: try container.encode(intValue)
        case let doubleValue as Double: try container.encode(doubleValue)
        case let stringValue as String: try container.encode(stringValue)
        case let dictionaryValue as [String: AnyCodable]: try container.encode(dictionaryValue)
        case let arrayValue as [AnyCodable]: try container.encode(arrayValue)
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Invalid type")
            throw EncodingError.invalidValue(value, context)
        }
    }
}

extension KeyedEncodingContainer {
    mutating func encodeAny(_ value: Encodable, forKey key: Key) throws {
        let wrapper = AnyEncodable(value)
        try encode(wrapper, forKey: key)
    }
}

/// A type-erased Encodable wrapper.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeFunc = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}

func decodeParams<T: Decodable>(
    _ type: T.Type,
    from dict: [String: AnyCodable]?
) -> T? {
    guard let dict = dict else {
        // If T has no required fields, attempt to decode an empty dictionary
        let data = try? JSONEncoder().encode([String: AnyCodable]())
        return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    
    // Use JSONEncoder to encode the dictionary
    guard let data = try? JSONEncoder().encode(dict) else {
        print("Failed to encode params using JSONEncoder.")
        return nil
    }
    
    // Decode the data into the desired type
    do {
        let decodedParams = try JSONDecoder().decode(T.self, from: data)
        return decodedParams
    } catch {
        print("Decoding failed with error: \(error)")
        return nil
    }
}
