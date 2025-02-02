import Foundation

// MARK: - RequestID

/// A request ID type that can be string or int.
public enum RequestID: Codable, Hashable, Sendable, CustomStringConvertible {
  case string(String)
  case int(Int)

  // MARK: Lifecycle

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

  // MARK: Public

  public var description: String {
    switch self {
    case .string(let string):
      string
    case .int(let int):
      "\(int)"
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

// MARK: - AnyCodable

/// AnyCodable helper for dynamic JSON fields.
public struct AnyCodable: Codable, Sendable, Equatable {

  // MARK: Lifecycle

  public init(_ value: Any) {
    if let value = value as? AnyCodable {
      storage = value.storage
    } else if let value = value as? Bool {
      storage = .bool(value)
    } else if let value = value as? Int {
      storage = .int(value)
    } else if let value = value as? Double {
      storage = .double(value)
    } else if let value = value as? String {
      storage = .string(value)
    } else if let value = value as? [String: AnyCodable] {
      storage = .dictionary(value)
    } else if let value = value as? [AnyCodable] {
      storage = .array(value)
    } else if value is NSNull {
      storage = .null
    } else {
      // Default to null for unsupported types
      storage = .null
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      storage = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      storage = .int(value)
    } else if let value = try? container.decode(Double.self) {
      storage = .double(value)
    } else if let value = try? container.decode(String.self) {
      storage = .string(value)
    } else if let value = try? container.decode([String: AnyCodable].self) {
      storage = .dictionary(value)
    } else if let value = try? container.decode([AnyCodable].self) {
      storage = .array(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported type")
    }
  }

  // MARK: Public

  public var value: Any {
    switch storage {
    case .bool(let value): value
    case .int(let value): value
    case .double(let value): value
    case .string(let value): value
    case .dictionary(let value): value
    case .array(let value): value
    case .null: NSNull()
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch storage {
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .dictionary(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  // MARK: Private

  private enum Storage: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case dictionary([String: AnyCodable])
    case array([AnyCodable])
    case null
  }

  private let storage: Storage

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
    encodeFunc = { encoder in
      try value.encode(to: encoder)
    }
  }

  func encode(to encoder: Encoder) throws {
    try encodeFunc(encoder)
  }
}

func decodeParams<T: Decodable>(
  _: T.Type,
  from dict: [String: AnyCodable]?)
  -> T?
{
  guard let dict else {
    // If T has no required fields, attempt to decode an empty dictionary
    let data = try? JSONEncoder().encode([String: AnyCodable]())
    return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  // Use JSONEncoder to encode the dictionary
  guard let data = try? JSONEncoder().encode(dict) else {
    NSLog("Failed to encode params using JSONEncoder.")
    return nil
  }

  // Decode the data into the desired type
  do {
    return try JSONDecoder().decode(T.self, from: data)
  } catch {
    NSLog("Decoding failed with error: \(error)")
    return nil
  }
}
