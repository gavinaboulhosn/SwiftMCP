import Foundation

/// Reference types for completion requests
public enum CompletionReference: Codable, Sendable {
  case prompt(PromptRef)
  case resource(ResourceRef)

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if
      let promptRef = try? container.decode(PromptRef.self),
      promptRef.type == "ref/prompt"
    {
      self = .prompt(promptRef)
      return
    }
    if
      let resourceRef = try? container.decode(ResourceRef.self),
      resourceRef.type == "ref/resource"
    {
      self = .resource(resourceRef)
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "Unknown reference type")
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .prompt(let promptRef): try promptRef.encode(to: encoder)
    case .resource(let resourceRef): try resourceRef.encode(to: encoder)
    }
  }
}

/// Reference to a prompt for completion
public struct PromptRef: Codable, Sendable {
  public let name: String
  public var type = "ref/prompt"

  public init(name: String) {
    self.name = name
  }
}

/// Reference to a resource for completion
public struct ResourceRef: Codable, Sendable {
  public let uri: String
  public var type = "ref/resource"

  public init(uri: String) {
    self.uri = uri
  }
}

/// Argument for completion requests
public struct CompletionArgument: Codable, Sendable {
  public let name: String
  public let value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

/// Result of a completion request
public struct CompletionResult: Codable, Sendable {
  public let values: [String]
  public let hasMore: Bool?
  public let total: Int?

  public init(values: [String], hasMore: Bool? = nil, total: Int? = nil) {
    self.values = values
    self.hasMore = hasMore
    self.total = total
  }
}
