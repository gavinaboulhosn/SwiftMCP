import Foundation

public struct ListResourceTemplatesResult: MCPResponse {
  public typealias Request = ListResourceTemplatesRequest

  public var _meta: [String: AnyCodable]?
  public let resourceTemplates: [ResourceTemplate]
  public let nextCursor: String?
}
