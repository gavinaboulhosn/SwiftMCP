import Foundation

public typealias ProgressToken = RequestID

public struct ProgressNotification: MCPNotification {
  public static let method = "notifications/progress"
  public var method: String { ProgressNotification.method }

  public struct Params: Codable, Sendable {
    public let progress: Double
    public let progressToken: ProgressToken
    public let total: Double?
    public let message: String?
  }

  public var params: Params

  public init(
    progress: Double,
    progressToken: ProgressToken,
    total: Double? = nil,
    message: String? = nil
  ) {
    params = Params(
      progress: progress,
      progressToken: progressToken,
      total: total,
      message: message)
  }
}
