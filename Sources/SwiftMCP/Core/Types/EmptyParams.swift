import Foundation

// MARK: - EmptyParams

/// Empty parameter structure for requests that don't require parameters
public struct EmptyParams: MCPRequestParams {
  public var _meta: RequestMeta?
}

// MARK: - MCPRequestParams

/// Base params interface matching schema
public protocol MCPRequestParams: Codable, Sendable {
  var _meta: RequestMeta? { get set }
}
