import Foundation

// MARK: - MCPResource

public struct MCPResource: Codable, Sendable, Identifiable, Hashable {
  public let uri: String
  public let name: String
  public let description: String?
  public let mimeType: String?

  public var id: String { uri }
}

// MARK: - ListResourcesRequest

public struct ListResourcesRequest: MCPRequest {
  public static let method = "resources/list"
  public typealias Response = ListResourcesResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let cursor: String?
  }

  public var params: Params

  public init(cursor: String? = nil) {
    params = Params(cursor: cursor)
  }
}

// MARK: - ListResourcesResult

public struct ListResourcesResult: MCPResponse {
  public typealias Request = ListResourcesRequest

  public let resources: [MCPResource]
  public let nextCursor: String?
  public var _meta: [String: AnyCodable]?
}

// MARK: - ListResourceTemplatesRequest

public struct ListResourceTemplatesRequest: MCPRequest {
  public static let method = "resources/templates/list"
  public typealias Response = ListResourceTemplatesResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let cursor: String?
  }

  public var params: Params

  public init(cursor: String? = nil) {
    params = Params(cursor: cursor)
  }
}

// MARK: - ResourceTemplate

public struct ResourceTemplate: Codable, Sendable, Identifiable, Hashable {
  public let name: String
  public let uriTemplate: String
  public let description: String?
  public let mimeType: String?
  public let annotations: Annotations?

  public var id: String {
    name + uriTemplate
  }
}

// MARK: - ListResourceTemplatesResult

public struct ListResourceTemplatesResult: MCPResponse {
  public typealias Request = ListResourceTemplatesRequest

  public var _meta: [String: AnyCodable]?
  public let resourceTemplates: [ResourceTemplate]
  public let nextCursor: String?
}

// MARK: - ReadResourceRequest

public struct ReadResourceRequest: MCPRequest {
  public static let method = "resources/read"
  public typealias Response = ReadResourceResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let uri: String
  }

  public var params: Params

  public init(uri: String) {
    params = Params(uri: uri)
  }
}

// MARK: - ResourceContentsVariant

public enum ResourceContentsVariant: Codable, Sendable {
  case text(TextResourceContents)
  case blob(BlobResourceContents)

  // MARK: Lifecycle

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let textResource = try? container.decode(TextResourceContents.self) {
      self = .text(textResource)
      return
    }
    if let blobResource = try? container.decode(BlobResourceContents.self) {
      self = .blob(blobResource)
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "Invalid resource contents")
  }

  // MARK: Public

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .text(let textResource):
      try textResource.encode(to: encoder)
    case .blob(let blobResource):
      try blobResource.encode(to: encoder)
    }
  }
}

// MARK: - ReadResourceResult

public struct ReadResourceResult: MCPResponse {
  public typealias Request = ReadResourceRequest

  public var _meta: [String: AnyCodable]?
  public let contents: [ResourceContentsVariant]
}

// MARK: - SubscribeRequest

public struct SubscribeRequest: MCPRequest {
  public static var method = "resources/subscribe"
  public typealias Response = EmptyResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let uri: String
  }

  public var params: Params

  public init(uri: String) {
    params = Params(uri: uri)
  }

  public struct EmptyResult: MCPResponse {
    public typealias Request = SubscribeRequest
    public var _meta: [String: AnyCodable]?
  }
}

// MARK: - UnsubscribeRequest

public struct UnsubscribeRequest: MCPRequest {
  public static var method = "resources/unsubscribe"
  public typealias Response = EmptyResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let uri: String
  }

  public var params: Params

  public init(uri: String) {
    params = Params(uri: uri)
  }

  public struct EmptyResult: MCPResponse {
    public typealias Request = UnsubscribeRequest
    public var _meta: [String: AnyCodable]?
  }
}
