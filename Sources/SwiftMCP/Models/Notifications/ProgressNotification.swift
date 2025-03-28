import Foundation

public typealias ProgressToken = RequestID

// MARK: - ProgressNotification

public struct ProgressNotification: MCPNotification {

  // MARK: Lifecycle

  public init(
    progress: Double,
    progressToken: ProgressToken,
    total: Double? = nil,
    message: String? = nil)
  {
    params = Params(
      progress: progress,
      progressToken: progressToken,
      total: total,
      message: message)
  }

  // MARK: Public

  public struct Params: Codable, Sendable {
    public let progress: Double
    public let progressToken: ProgressToken
    public let total: Double?
    public let message: String?
  }

  public static let method = "notifications/progress"

  public var params: Params

  public var method: String { ProgressNotification.method }

}
