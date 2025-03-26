import Foundation

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
