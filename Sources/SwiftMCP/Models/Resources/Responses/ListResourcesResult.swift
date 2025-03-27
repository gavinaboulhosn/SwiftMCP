import Foundation

public struct ListResourcesResult: MCPResponse {
  public typealias Request = ListResourcesRequest

  public let resources: [MCPResource]
  public let nextCursor: String?
  public var _meta: [String: AnyCodable]?
}
