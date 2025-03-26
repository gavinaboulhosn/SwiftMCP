import Foundation

// MARK: - RootSource

public enum RootSource {
  /// A static list of roots
  case list([Root])

  /// A dynamic list of roots
  case dynamic(() -> [Root])
}

// MARK: - RootsConfig

/// Configuration for filesystem roots
public struct RootsConfig {
  let source: RootSource
  let autoUpdate: Bool

  public static func list(_ roots: [Root]) -> Self {
    .init(source: .list(roots), autoUpdate: false)
  }

  public static func dynamic(_ roots: @escaping () -> [Root]) -> Self {
    .init(source: .dynamic(roots), autoUpdate: true)
  }

  var roots: [Root] {
    switch source {
    case .list(let roots): roots
    case .dynamic(let roots): roots()
    }
  }
}

// MARK: - SamplingConfig

/// Configuration for AI model sampling
public struct SamplingConfig {
  public typealias SamplingHandler = @Sendable (CreateMessageRequest) async throws ->
    CreateMessageResult

  /// Handler for sampling requests
  public let handler: SamplingHandler

  public init(
    handler: @escaping SamplingHandler)
  {
    self.handler = handler
  }
}

// MARK: - MCPConfiguration

public struct MCPConfiguration {

  // MARK: Lifecycle

  public init(
    roots: RootsConfig? = nil,
    sampling: SamplingConfig? = nil,
    clientInfo: Implementation = .defaultClient,
    capabilities: ClientCapabilities = .init())
  {
    self.roots = roots
    self.sampling = sampling
    self.capabilities = capabilities
    self.clientInfo = clientInfo

    if roots != nil {
      self.capabilities.roots = .init(listChanged: true)
    }

    if sampling != nil, !capabilities.supports(.sampling) {
      self.capabilities.sampling = .init()
    }

    self.capabilities = capabilities
  }

  // MARK: Public

  /// Broadcasted capabilities for all clients
  public internal(set) var capabilities: ClientCapabilities

  public var clientInfo: Implementation
  /// Configuration for filesystem roots
  public var roots: RootsConfig?

  /// Configuration for AI model sampling
  public var sampling: SamplingConfig?

  // MARK: Internal

  var clientConfig: MCPClient.Configuration {
    MCPClient.Configuration(
      clientInfo: clientInfo,
      capabilities: capabilities)
  }

}
