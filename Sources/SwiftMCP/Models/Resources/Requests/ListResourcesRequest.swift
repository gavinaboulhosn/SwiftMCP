import Foundation

public struct ListResourcesRequest: MCPRequest {
  public static let method = "resources/list"
  public typealias Response = ListResourcesResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let cursor: String?
  }

  public var params: Params

  public init(cursor: String? = nil) {
    params = Params(cursor: cursor)
  }
}
