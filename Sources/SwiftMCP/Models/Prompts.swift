import Foundation

// MARK: - MCPPrompt

public struct MCPPrompt: Codable, Sendable, Hashable, Identifiable {
  public var id: String { name }

  public let name: String
  public let description: String?
  public let arguments: [PromptArgument]?

  public init(
    name: String,
    description: String? = nil,
    arguments: [PromptArgument]? = nil)
  {
    self.name = name
    self.description = description
    self.arguments = arguments
  }
}

// MARK: - PromptArgument

public struct PromptArgument: Codable, Sendable, Hashable {
  public let name: String
  public let description: String?
  public let required: Bool?

  public init(
    name: String,
    description: String? = nil,
    required: Bool? = nil)
  {
    self.name = name
    self.description = description
    self.required = required
  }
}

// MARK: - PromptMessage

public struct PromptMessage: Codable, Sendable, Hashable {
  public enum PromptContent: Codable, Sendable, Hashable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResourceContent)

    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if
        let textContent = try? container.decode(TextContent.self),
        textContent.type == "text"
      {
        self = .text(textContent)
        return
      }
      if
        let imageContent = try? container.decode(ImageContent.self),
        imageContent.type == "image"
      {
        self = .image(imageContent)
        return
      }
      if
        let resourceContent = try? container.decode(EmbeddedResourceContent.self),
        resourceContent.type == "resource"
      {
        self = .resource(resourceContent)
        return
      }
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid PromptContent")
    }

    // MARK: Public

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .text(let textContent): try textContent.encode(to: encoder)
      case .image(let imageContent): try imageContent.encode(to: encoder)
      case .resource(let resourceContent): try resourceContent.encode(to: encoder)
      }
    }
  }

  public let role: Role
  public let content: PromptContent

}

// MARK: - ListPromptsRequest

public struct ListPromptsRequest: MCPRequest, Sendable {
  public static let method = "prompts/list"
  public typealias Response = ListPromptsResult

  public struct Params: MCPRequestParams, Sendable {
    public var _meta: RequestMeta?
    public let cursor: String?
  }

  public var params: Params

  public init(cursor: String? = nil) {
    params = Params(cursor: cursor)
  }
}

// MARK: - ListPromptsResult

public struct ListPromptsResult: MCPResponse {
  public typealias Request = ListPromptsRequest

  public var _meta: [String: AnyCodable]?
  public let prompts: [MCPPrompt]
  public let nextCursor: String?

  public init(
    prompts: [MCPPrompt],
    nextCursor: String? = nil,
    metadata: [String: AnyCodable]? = nil)
  {
    self.prompts = prompts
    self.nextCursor = nextCursor
    _meta = metadata
  }
}

// MARK: - GetPromptRequest

public struct GetPromptRequest: MCPRequest, Sendable {
  public static let method = "prompts/get"
  public typealias Response = GetPromptResult

  public struct Params: MCPRequestParams, Sendable {
    public var _meta: RequestMeta?
    public let name: String
    public let arguments: [String: String]?
  }

  public var params: Params

  public init(name: String, arguments: [String: String]? = nil) {
    params = Params(name: name, arguments: arguments)
  }
}

// MARK: - GetPromptResult

public struct GetPromptResult: MCPResponse, Sendable {
  public typealias Request = GetPromptRequest

  public var _meta: [String: AnyCodable]?
  public let description: String?
  public let messages: [PromptMessage]
}
