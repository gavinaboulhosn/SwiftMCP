import Foundation

/// Defines supported MCP protocol versions
public enum MCPVersion {
  /// Current version of the protocol
  static let currentVersion = "2024-11-05"

  /// All versions this implementation supports
  public static let supportedVersions = ["2024-11-05", "2024-10-07"]

  /// Check if a given version is supported
  static func isSupported(_ version: String) -> Bool {
    supportedVersions.contains(version)
  }
}
