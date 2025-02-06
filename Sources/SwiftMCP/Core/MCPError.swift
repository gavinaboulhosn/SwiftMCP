import Foundation

// MARK: - JSONRPCErrorCode

/// Standard JSON-RPC error codes with MCP extensions
@frozen
public enum JSONRPCErrorCode: Int, Error, Codable {
  // MCP-specific codes
  case connectionClosed = -1
  case requestTimeout = -2

  // Standard JSON-RPC error codes
  case parseError = -32700
  case invalidRequest = -32600
  case methodNotFound = -32601
  case invalidParams = -32602
  case internalError = -32603

  /// Server error range (-32000 to -32099)
  case serverError = -32000

  // MARK: Public

  public var description: String {
    switch self {
    case .parseError: "Parse error"
    case .invalidRequest: "Invalid request"
    case .methodNotFound: "Method not found"
    case .invalidParams: "Invalid params"
    case .internalError: "Internal error"
    case .serverError: "Server error"
    case .connectionClosed: "Connection closed"
    case .requestTimeout: "Request timeout"
    }
  }
}

// MARK: - MCPError

/// MCP Error structure following JSON-RPC 2.0 spec
public struct MCPError: Codable, LocalizedError {

  // MARK: Lifecycle

  public init(code: JSONRPCErrorCode, message: String, data: ErrorData? = nil) {
    self.code = code
    self.message = message
    self.data = data
  }

  // MARK: Public

  public struct ErrorData: Codable {

    // MARK: Lifecycle

    public init(
      details: String? = nil,
      stackTrace: String? = nil,
      cause: String? = nil,
      metadata: [String: String]? = nil)
    {
      self.details = details
      self.stackTrace = stackTrace
      self.cause = cause
      self.metadata = metadata
    }

    // MARK: Public

    /// Detailed error description
    public let details: String?

    /// Stack trace if available
    public let stackTrace: String?

    /// Underlying cause if any
    public let cause: String?

    /// Additional context
    public let metadata: [String: String]?

  }

  /// Required error code
  public let code: JSONRPCErrorCode

  /// Required short message
  public let message: String

  /// Optional detailed error data
  public let data: ErrorData?

  public var errorDescription: String? {
    "\(code.description): \(message)"
  }
}

extension MCPError {
  /// Standard JSON-RPC errors
  public static func parseError(_ message: String, cause: Error? = nil) -> Self {
    MCPError(
      code: .parseError,
      message: message,
      data: cause.map { ErrorData(cause: String(describing: $0)) })
  }

  public static func invalidRequest(_ message: String) -> Self {
    MCPError(code: .invalidRequest, message: message)
  }

  public static func methodNotFound(_ method: String) -> Self {
    MCPError(code: .methodNotFound, message: "Method not found: \(method)")
  }

  public static func invalidParams(_ message: String) -> Self {
    MCPError(code: .invalidParams, message: message)
  }

  public static func internalError(_ message: String, data: ErrorData? = nil) -> Self {
    MCPError(code: .internalError, message: message, data: data)
  }

  /// MCP-specific errors
  public static func timeout(_ operation: String, duration: TimeInterval) -> Self {
    MCPError(
      code: .requestTimeout,
      message: "\(operation) timed out after \(duration) seconds")
  }

  public static func connectionClosed(reason: String? = nil) -> Self {
    MCPError(
      code: .connectionClosed,
      message: "Connection closed" + (reason.map { ": \($0)" } ?? ""))
  }
}
