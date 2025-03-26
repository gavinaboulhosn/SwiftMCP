import Foundation

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
