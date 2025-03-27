import Foundation

public struct ReadResourceRequest: MCPRequest {
  public static let method = "resources/read"
  public typealias Response = ReadResourceResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let uri: String
  }

  public var params: Params

  public init(uri: String) {
    params = Params(uri: uri)
  }
}
