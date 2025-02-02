import Foundation

// MARK: - ModelHint

/// For completion/hints
public struct ModelHint: Codable, Sendable {
  public let name: String?
}

// MARK: - ModelPreferences

public struct ModelPreferences: Codable, Sendable {
  public let costPriority: Double?
  public let hints: [ModelHint]?
  public let intelligencePriority: Double?
  public let speedPriority: Double?
}

// MARK: - SamplingMessage

/// For CreateMessage requests
public struct SamplingMessage: Codable, Sendable {
  public enum SamplingContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)

    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let textContent = try? container.decode(TextContent.self), textContent.type == "text" {
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
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "SamplingMessage content must be text or image")
    }

    // MARK: Public

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .text(let textContent): try textContent.encode(to: encoder)
      case .image(let imageContent): try imageContent.encode(to: encoder)
      }
    }
  }

  public let role: Role
  public let content: SamplingContent

}

// MARK: - CreateMessageRequest

public struct CreateMessageRequest: MCPRequest {

  // MARK: Lifecycle

  public init(
    maxTokens: Int,
    messages: [SamplingMessage],
    includeContext: String? = nil,
    metadata: [String: AnyCodable]? = nil,
    modelPreferences: ModelPreferences? = nil,
    stopSequences: [String]? = nil,
    systemPrompt: String? = nil,
    temperature: Double? = nil)
  {
    params = Params(
      includeContext: includeContext, maxTokens: maxTokens, messages: messages,
      metadata: metadata, modelPreferences: modelPreferences, stopSequences: stopSequences,
      systemPrompt: systemPrompt, temperature: temperature)
  }

  // MARK: Public

  public typealias Response = CreateMessageResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let includeContext: String?
    public let maxTokens: Int
    public let messages: [SamplingMessage]
    public let metadata: [String: AnyCodable]?
    public let modelPreferences: ModelPreferences?
    public let stopSequences: [String]?
    public let systemPrompt: String?
    public let temperature: Double?
  }

  public static let method = "sampling/createMessage"

  public var params: Params

}

// MARK: - CreateMessageResult

public struct CreateMessageResult: MCPResponse {
  public typealias Request = CreateMessageRequest

  public enum CreateMessageContentVariant: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)

    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let textContent = try? container.decode(TextContent.self), textContent.type == "text" {
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
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid content for CreateMessageResult")
    }

    // MARK: Public

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .text(let textContent): try textContent.encode(to: encoder)
      case .image(let imageContent): try imageContent.encode(to: encoder)
      }
    }
  }

  public var _meta: [String: AnyCodable]?
  public let content: CreateMessageContentVariant
  public let model: String
  public let role: Role
  public let stopReason: String?

}
