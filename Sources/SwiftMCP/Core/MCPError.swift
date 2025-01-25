import Foundation

/// Standard JSON-RPC error codes with MCP extensions
@frozen public enum JSONRPCErrorCode: Int, Codable {
    // MCP-specific codes
    case connectionClosed = -1
    case requestTimeout = -2

    // Standard JSON-RPC error codes
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603

    // Server error range (-32000 to -32099)
    case serverError = -32000

    public var description: String {
        switch self {
        case .parseError: return "Parse error"
        case .invalidRequest: return "Invalid request"
        case .methodNotFound: return "Method not found"
        case .invalidParams: return "Invalid params"
        case .internalError: return "Internal error"
        case .serverError: return "Server error"
        case .connectionClosed: return "Connection closed"
        case .requestTimeout: return "Request timeout"
        }
    }
}

/// MCP Error structure following JSON-RPC 2.0 spec
public struct MCPError: Error, Codable {
    /// Required error code
    public let code: JSONRPCErrorCode

    /// Required short message
    public let message: String

    /// Optional detailed error data
    public let data: ErrorData?

    public init(code: JSONRPCErrorCode, message: String, data: ErrorData? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public struct ErrorData: Codable {
        /// Detailed error description
        public let details: String?

        /// Stack trace if available
        public let stackTrace: String?

        /// Underlying cause if any
        public let cause: String?

        /// Additional context
        public let metadata: [String: String]?

        public init(
            details: String? = nil,
            stackTrace: String? = nil,
            cause: String? = nil,
            metadata: [String: String]? = nil
        ) {
            self.details = details
            self.stackTrace = stackTrace
            self.cause = cause
            self.metadata = metadata
        }
    }

    public var description: String {
        var desc = "\(code.description): \(message)"
        if let data = data {
            desc += "\n\(data)"
        }
        return desc
    }
}

extension MCPError {
    // Standard JSON-RPC errors
    public static func parseError(_ message: String, cause: Error? = nil) -> Self {
        MCPError(
            code: .parseError,
            message: message,
            data: cause.map { ErrorData(cause: String(describing: $0)) }
        )
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

    // MCP-specific errors
    public static func timeout(_ operation: String, duration: TimeInterval) -> Self {
        MCPError(
            code: .requestTimeout,
            message: "\(operation) timed out after \(duration) seconds"
        )
    }

    public static func connectionClosed(reason: String? = nil) -> Self {
        MCPError(
            code: .connectionClosed,
            message: "Connection closed" + (reason.map { ": \($0)" } ?? "")
        )
    }
}
