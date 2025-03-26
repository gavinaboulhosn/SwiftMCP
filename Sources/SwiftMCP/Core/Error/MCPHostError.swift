import Foundation

/// Host-level errors that are not part of the MCP protocol itself.
///
/// For instance, "no such connection," "connection already exists," or other
/// usage errors at the MCPHost level.
public enum MCPHostError: Error, LocalizedError {
  /// No connection found for a given ID
  case connectionNotFound(String)
  /// A connection with the same ID already exists
  case connectionExists(String)
  /// Operation is invalid in the current host context
  case invalidOperation(String)
  /// Catch-all for unknown issues
  case unknown(String)

  // MARK: Public

  public var errorDescription: String? {
    switch self {
    case .connectionNotFound(let id):
      "No connection found for id: \(id)"
    case .connectionExists(let id):
      "A connection with id '\(id)' already exists."
    case .invalidOperation(let msg):
      "Invalid host operation: \(msg)"
    case .unknown(let msg):
      "Unknown Host Error: \(msg)"
    }
  }
}
