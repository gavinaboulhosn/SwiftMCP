import Foundation

public typealias ProgressToken = RequestID

public struct ProgressNotification: MCPNotification {
  public static let method = "notifications/progress"
  public var method: String { ProgressNotification.method }

  public struct Params: Codable, Sendable {
    public let progress: Double
    public let progressToken: ProgressToken
    public let total: Double?
  }

  public var params: Params

  public init(progress: Double, progressToken: ProgressToken, total: Double? = nil) {
    params = Params(
      progress: progress,
      progressToken: progressToken,
      total: total)
  }
}
