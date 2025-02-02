import Foundation

// MARK: - MCPVersion

public enum MCPVersion {
  static let currentVersion = "2024-11-05"
  public static let supportedVersions = ["2024-11-05", "2024-10-07"]

  static func isSupported(_ version: String) -> Bool {
    supportedVersions.contains(version)
  }
}

// MARK: - MCPMessage

/// Core protocol marker for all MCP messages
public protocol MCPMessage: Codable, Sendable {
  /// Protocol version for this message
  static var supportedVersions: [String] { get }

  /// Current protocol version
  static var currentVersion: String { get }

  /// Version validation
  func validateVersion() throws
}

extension MCPMessage {
  public static var currentVersion: String { MCPVersion.currentVersion }
  public static var supportedVersions: [String] { MCPVersion.supportedVersions }

  public func validateVersion() throws {
    if !Self.supportedVersions.contains(Self.currentVersion) {
      throw MCPError.invalidRequest("Unsupported protocol version \(Self.currentVersion)")
    }
  }
}

public struct EmptyParams: MCPRequestParams {
  public var _meta: RequestMeta?
}

public struct RequestMeta: Codable, Sendable {
  var progressToken: ProgressToken?
}

/// Base params interface matching schema
public protocol MCPRequestParams: Codable, Sendable {
  var _meta: RequestMeta? { get set }
}

/// Protocol for request messages.
///
/// Conforming types specify a request method, associated response type, and parameters.
public protocol MCPRequest: MCPMessage {
  associatedtype Response: MCPResponse where Response.Request == Self
  associatedtype Params: MCPRequestParams = EmptyParams

  /// The JSON-RPC method name for this request.
  static var method: String { get }

  /// The request parameters, if any.
  var params: Params { get set }
}

/// Protocol for response messages
public protocol MCPResponse: MCPMessage {
  /// The request type this response corresponds to
  associatedtype Request: MCPRequest where Request.Response == Self

  var _meta: [String: AnyCodable]? { get set }
}

/// Protocol for notification messages
public protocol MCPNotification: MCPMessage {
  associatedtype Params: Codable = EmptyParams
  /// The method name for this notification
  static var method: String { get }

  /// The parameters for this notification, if any
  var params: Params { get }
}

public enum MCPServerRequest: Codable {
  case listRoots(ListRootsRequest)
  case createMessage(CreateMessageRequest)
  case ping(PingRequest)
}

public enum MCPClientRequest: Codable {
  case listPrompts(ListPromptsRequest)
  case listTools(ListToolsRequest)
  case callTool(CallToolRequest)
  case setLoggingLevel(SetLevelRequest)
  case listResources(ListResourcesRequest)
  case subscribe(SubscribeRequest)
  case unsubscribe(UnsubscribeRequest)
  case listResourceTemplates(ListResourceTemplatesRequest)
  case readResource(ReadResourceRequest)
  case ping(PingRequest)

  // MARK: Internal

  var request: any MCPRequest {
    switch self {
    case .listPrompts(let request):
      request
    case .listTools(let request):
      request
    case .callTool(let request):
      request
    case .setLoggingLevel(let request):
      request
    case .listResources(let request):
      request
    case .subscribe(let request):
      request
    case .unsubscribe(let request):
      request
    case .listResourceTemplates(let request):
      request
    case .readResource(let request):
      request
    case .ping(let request):
      request
    }
  }
}

extension MCPNotification {
  public var params: EmptyParams { EmptyParams() }
}

extension MCPRequest {
  public var params: EmptyParams { EmptyParams() }
}
