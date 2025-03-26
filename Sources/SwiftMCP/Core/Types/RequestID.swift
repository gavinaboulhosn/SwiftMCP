import Foundation

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
