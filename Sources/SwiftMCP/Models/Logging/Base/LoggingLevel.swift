import Foundation

/// Logging level for MCP logging messages
public enum LoggingLevel: String, Codable, Sendable {
  case alert, critical, debug, emergency, error, info, notice, warning
}
