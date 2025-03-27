import Foundation

/// A sample request for the "initialize" method as per the schema.
public struct InitializeRequest: MCPRequest {

  // MARK: Lifecycle

  public init(params: Params) {
    self.params = params
  }

  // MARK: Public

  public typealias Response = InitializeResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let capabilities: ClientCapabilities
    public let clientInfo: Implementation
    public let protocolVersion: String

    public init(
      capabilities: ClientCapabilities, clientInfo: Implementation, protocolVersion: String)
    {
      self.capabilities = capabilities
      self.clientInfo = clientInfo
      self.protocolVersion = protocolVersion
    }
  }

  public static let method = "initialize"

  public var params: Params
}
