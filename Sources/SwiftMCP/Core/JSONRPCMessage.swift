import Foundation

// MARK: - JSONRPCMessage

/// A JSON-RPC 2.0 message in the MCP protocol.
///
/// It can be a request, response, error, or notification.
/// Requests and responses are strongly typed thanks to generics.
enum JSONRPCMessage: Codable {
  /// A request message expecting a response.
  case request(id: RequestID, request: any MCPRequest)

  /// A successful response message.
  case response(id: RequestID, response: AnyCodable)

  /// An error response message.
  case error(id: RequestID, error: MCPError)

  /// A notification message that doesn't expect a response.
  case notification(any MCPNotification)

  // MARK: Lifecycle

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let jsonrpc = try container.decode(String.self, forKey: .jsonrpc)

    if let id = try container.decodeIfPresent(RequestID.self, forKey: .id) {
      // Could be request, response, or error
      if let errorVal = try container.decodeIfPresent(MCPError.self, forKey: .error) {
        self = .error(id: id, error: errorVal)
      } else if let method = try? container.decode(String.self, forKey: .method) {
        // It's a request
        let paramsAny = try container.decodeIfPresent([String: AnyCodable].self, forKey: .params)
        guard let req = RequestFactory.makeRequest(method: method, params: paramsAny) else {
          throw MCPError.methodNotFound(method)
        }
        self = .request(id: id, request: req)
      } else if container.contains(.result) {
        // It's a response
        let resultData = try container.decode(AnyCodable.self, forKey: .result)
        self = .response(id: id, response: resultData)
      } else {
        throw MCPError.invalidRequest("Invalid message format")
      }
    } else {
      // Notification case remains the same
      let method = try container.decode(String.self, forKey: .method)
      let paramsAny = try container.decodeIfPresent([String: AnyCodable].self, forKey: .params)
      guard let notif = NotificationFactory.makeNotification(method: method, params: paramsAny)
      else {
        throw MCPError.methodNotFound(method)
      }
      self = .notification(notif)
    }

    try validateRPCVersion(jsonrpc)
    try validateVersion()
  }

  // MARK: Internal

  /// JSON-RPC version constant
  var jsonrpcVersion: String { "2.0" }

  func encode(to encoder: Encoder) throws {
    try validateVersion()

    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(jsonrpcVersion, forKey: .jsonrpc)

    switch self {
    case .request(let id, let request):
      try container.encode(id, forKey: .id)
      try container.encode(type(of: request).method, forKey: .method)
      try container.encodeAny(request.params, forKey: .params)

    case .response(let id, let response):
      try container.encode(id, forKey: .id)
      try container.encode(response, forKey: .result)

    case .error(let id, let error):
      try container.encode(id, forKey: .id)
      try container.encode(error, forKey: .error)

    case .notification(let notification):
      try container.encode(type(of: notification).method, forKey: .method)
      try container.encodeAny(notification.params, forKey: .params)
    }
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case jsonrpc, id, method, params, result, error
  }

  private func validateRPCVersion(_ version: String) throws {
    guard version == jsonrpcVersion else {
      throw MCPError.invalidRequest("Invalid JSON-RPC version")
    }
  }
}

extension JSONRPCMessage {
  static func response(_ id: RequestID, response: any MCPResponse) -> JSONRPCMessage {
    .response(id: id, response: AnyCodable(response))
  }
}

struct EmptyRequest: MCPRequest {
  typealias Response = EmptyResult

  var params = EmptyParams()

  static let method = "empty"
}

struct EmptyResult: MCPResponse {
  typealias Request = EmptyRequest
  var _meta: [String: AnyCodable]?
}

extension JSONRPCMessage: MCPMessage { }
