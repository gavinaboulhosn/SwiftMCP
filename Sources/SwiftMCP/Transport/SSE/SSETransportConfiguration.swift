import Foundation

// MARK: - SSETransportConfiguration

/// Configuration settings for an SSE Transport option
public struct SSETransportConfiguration: Codable {

  // MARK: Lifecycle

  public init(
    sseURL: URL,
    postURL: URL? = nil,
    sseHeaders: [String: String] = [:],
    baseConfiguration: TransportConfiguration = .default)
  {
    self.sseURL = sseURL
    self.postURL = postURL
    self.sseHeaders = sseHeaders
    self.baseConfiguration = baseConfiguration
  }

  // MARK: Public

  public static let defaultSSEHeaders = [
    "Accept": "text/event-stream",
  ]

  public var sseURL: URL
  public var postURL: URL?
  public var sseHeaders: [String: String]
  public var baseConfiguration: TransportConfiguration

}

extension SSETransportConfiguration {
  public static let dummyData = SSETransportConfiguration(
    sseURL: URL(string: "http://localhost:3000")!,
    postURL: nil,
    sseHeaders: ["some": "sse-value"],
    baseConfiguration: .dummyData)
}

extension TransportConfiguration {
  public static let defaultSSE = TransportConfiguration(
    healthCheckEnabled: true, healthCheckInterval: 5.0)
}
