import Foundation

public struct CancelledNotification: MCPNotification {
  public static let method = "notifications/cancelled"
  public var method: String { CancelledNotification.method }

  public struct Params: Codable, Sendable {
    public let requestId: RequestID
    public let reason: String?
  }

  public var params: Params

  public init(requestId: RequestID, reason: String? = nil) {
    params = Params(requestId: requestId, reason: reason)
  }
}
