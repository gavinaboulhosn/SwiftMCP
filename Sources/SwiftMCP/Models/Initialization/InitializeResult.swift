import Foundation

/// The response for the "initialize" method as per the schema.
public struct InitializeResult: MCPResponse, Equatable {

  // MARK: Lifecycle

  public init(
    capabilities: ServerCapabilities,
    protocolVersion: String,
    serverInfo: Implementation,
    instructions: String? = nil,
    meta: [String: AnyCodable]? = nil)
  {
    self.capabilities = capabilities
    self.protocolVersion = protocolVersion
    self.serverInfo = serverInfo
    self.instructions = instructions
    _meta = meta
  }

  // MARK: Public

  public typealias Request = InitializeRequest

  public let capabilities: ServerCapabilities
  public let protocolVersion: String
  public let serverInfo: Implementation
  public let instructions: String?
  public var _meta: [String: AnyCodable]?

  public static func ==(lhs: InitializeResult, rhs: InitializeResult) -> Bool {
    (lhs.capabilities == rhs.capabilities)
      && (lhs.protocolVersion == rhs.protocolVersion)
      && (lhs.serverInfo == rhs.serverInfo) && (lhs.instructions == rhs.instructions)
  }
}
