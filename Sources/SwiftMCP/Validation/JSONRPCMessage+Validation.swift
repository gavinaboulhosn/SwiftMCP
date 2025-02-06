import Foundation

extension JSONRPCMessage {

  // MARK: Internal

  /// Validates that the message follows JSON-RPC and MCP constraints.
  func validate() throws {
    guard jsonrpcVersion == "2.0" else {
      throw MCPError.invalidRequest("Unsupported JSON-RPC version")
    }

    switch self {
    case .request(let id, let req):
      try validateRequestId(id)
      try validateRequest(req)

    case .response(let id, _):
      try validateRequestId(id)

    case .error(let id, let error):
      try validateRequestId(id)
      try validateError(error)

    case .notification(let notification):
      try validateNotification(notification)
    }
  }

  // MARK: Private

  private func validateRequestId(_ id: RequestID) throws {
    // IDs should be non-empty (string or non-negative int). Adjust as needed.
    // If ID is int, ensure it's >= 0. If string, ensure not empty.
    switch id {
    case .int(let val) where val < 0:
      throw MCPError.invalidRequest("Request ID must be non-negative")
    case .string(let str) where str.isEmpty:
      throw MCPError.invalidRequest("Request ID must not be an empty string")
    default:
      break
    }
  }

  private func validateRequest(_ request: any MCPRequest) throws {
    guard !type(of: request).method.isEmpty else {
      throw MCPError.invalidRequest("Method cannot be empty")
    }
  }

  private func validateError(_ error: MCPError) throws {
    guard !error.message.isEmpty else {
      throw MCPError.invalidRequest("Error message cannot be empty")
    }
  }

  private func validateNotification(_ notification: any MCPNotification) throws {
    guard !notification.method.isEmpty else {
      throw MCPError.invalidRequest("Method cannot be empty")
    }
  }
}
