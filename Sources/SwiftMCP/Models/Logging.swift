import Foundation

// MARK: - LoggingLevel

public enum LoggingLevel: String, Codable, Sendable {
  case alert, critical, debug, emergency, error, info, notice, warning
}

// MARK: - SetLevelRequest

public struct SetLevelRequest: MCPRequest {
  public static let method = "logging/setLevel"
  public typealias Response = EmptyResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let level: LoggingLevel
  }

  public var params: Params

  public init(level: LoggingLevel) {
    params = Params(level: level)
  }

  /// Empty result since just a confirmation is needed.
  public struct EmptyResult: MCPResponse {
    public typealias Request = SetLevelRequest
    public var _meta: [String: AnyCodable]?
  }
}
