import Foundation

extension MCPClient {
  /// Configuration for the client, specifying `Implementation` details
  /// and `ClientCapabilities`.
  public struct Configuration {
    public let clientInfo: Implementation
    public let capabilities: ClientCapabilities

    public init(clientInfo: Implementation, capabilities: ClientCapabilities) {
      self.clientInfo = clientInfo
      self.capabilities = capabilities
    }

    public static let `default` = Configuration(
      clientInfo: .defaultClient,
      capabilities: .init())
  }
}
