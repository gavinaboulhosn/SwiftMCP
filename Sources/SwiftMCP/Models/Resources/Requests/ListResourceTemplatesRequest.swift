import Foundation

public struct ListResourceTemplatesRequest: MCPRequest {
  public static let method = "resources/templates/list"
  public typealias Response = ListResourceTemplatesResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let cursor: String?
  }

  public var params: Params

  public init(cursor: String? = nil) {
    params = Params(cursor: cursor)
  }
}
