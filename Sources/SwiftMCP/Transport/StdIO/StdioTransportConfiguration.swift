import Foundation

// MARK: - StdioTransportOptions

extension StdioTransportConfiguration {
  public static let dummyData = StdioTransportConfiguration(
    command: "/dev/null",
    arguments: ["some", "args"],
    environment: ["another": "env"],
    baseConfiguration: .dummyData)
}

public struct StdioTransportConfiguration: Codable {
  public var command: String
  public var arguments: [String]
  public var environment: [String: String]
  public var baseConfiguration: TransportConfiguration
  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    baseConfiguration: TransportConfiguration = .default)
  {
    self.command = command
    self.arguments = arguments
    self.environment = environment
    self.baseConfiguration = baseConfiguration
  }
}
