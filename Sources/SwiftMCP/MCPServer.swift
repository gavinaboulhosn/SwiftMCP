import Foundation

// MARK: - MCPServerProtocol

public protocol MCPServerProtocol { }

// MARK: - MCPServerConfiguration

// public struct MCPServerFeature: OptionSet {
//   public let rawValue: UInt
//
// }

public struct MCPServerConfiguration {
  public let implementation: Implementation
  public let capabilities: ServerCapabilities

}
