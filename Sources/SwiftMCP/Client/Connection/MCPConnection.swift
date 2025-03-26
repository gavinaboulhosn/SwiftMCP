import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "ConnectionState")

// MARK: - ConnectionState

/// A handle for interacting with a specific MCP server connection,
/// wrapping an `MCPClient`.
///
/// This class is marked `@Observable` so SwiftUI or other observers
/// can react to its property changes.
@Observable
public final class ConnectionState: Identifiable {

  // MARK: Lifecycle

  /// Create a new ConnectionState wrapper.
  /// - Parameters:
  /// - id: A unique identifier for referencing this connection
  /// - client: The `MCPClient` that powers this connection
  /// - serverInfo: Implementation details from server
  /// - capabilities: Advertised server capabilities
  init(
    id: String,
    client: MCPClient,
    serverInfo: Implementation,
    capabilities: ServerCapabilities)
  {
    self.id = id
    self.client = client
    self.serverInfo = serverInfo
    self.capabilities = capabilities

    // Monitor the client's events to update local status
    statusMonitorTask = Task { [weak self] in
      guard let self else { return }
      let evtStream = await client.events
      for await event in evtStream {
        switch event {
        case .connectionChanged(let state):
          switch state {
          case .running:
            status = .connected
          case .failed(let error):
            status = .failed(error)
          case .disconnected:
            status = .disconnected
          case .connecting, .initializing:
            status = .connecting
          }

        case .message:
          break

        case .error(let err):
          await yieldEvent(.clientError(err))
          logger.error("MCPClient error: \(err)")
        }
      }
    }
  }

  // MARK: Public

  /// Unique identifier for this connection
  public let id: String

  /// Info about the server
  public let serverInfo: Implementation
  /// Advertised server capabilities
  public let capabilities: ServerCapabilities

  // Synchronized properties
  public private(set) var tools: [MCPTool] = []
  public private(set) var resources: [MCPResource] = []
  public private(set) var prompts: [MCPPrompt] = []

  public private(set) var lastActivity = Date()
  public private(set) var reconnectCount = 0
  public private(set) var isRefreshingTools = false
  public private(set) var isRefreshingResources = false
  public private(set) var isRefreshingPrompts = false

  /// The current `ConnectionStatus`.
  /// Observers may subscribe to `events()` or observe `status` changes if using SwiftUI.
  public private(set) var status = ConnectionStatus.connected {
    didSet {
      if oldValue != status {
        Task { [weak self] in
          guard let self else { return }
          await yieldEvent(.statusChanged(status))
        }
      }
    }
  }

  /// Whether the connection is logically "connected" from a user perspective
  public var isConnected: Bool { status != .disconnected }

  // MARK: - Public Async Event Stream

  /// Provides an `AsyncStream` of `ConnectionStateEvent` for multiple observers.
  /// Each call produces an independent stream.
  public func events() -> AsyncStream<ConnectionStateEvent> {
    let streamId = UUID()
    return AsyncStream<ConnectionStateEvent> { continuation in
      Task { [weak self] in
        await self?.storeConnectionContinuation(streamId, continuation)
      }
    }
  }

  // MARK: - High-Level Operations

  /// Refresh all known data (tools, resources, prompts) from the server.
  public func refreshAll() async {
    await refreshTools()
    await refreshResources()
    await refreshPrompts()
  }

  /// Re-fetch the list of Tools from the server, if supported.
  public func refreshTools() async {
    let connected = await client.isConnected
    guard connected, capabilities.supports(.tools) else { return }
    isRefreshingTools = true
    defer { isRefreshingTools = false }

    do {
      let connectionId = id
      logger.debug("ConnectionState [\(connectionId)] -> listing tools.")
      let result = try await client.listTools()
      tools = result.tools
      lastActivity = Date()
    } catch {
      logger.error("Failed to refresh tools: \(error)")
    }
  }

  /// Re-fetch the list of Resources from the server, if supported.
  public func refreshResources() async {
    let connected = await client.isConnected
    guard connected, capabilities.supports(.resources) else { return }
    isRefreshingResources = true
    defer { isRefreshingResources = false }

    do {
      let connectionId = id
      logger.debug("ConnectionState [\(connectionId)] -> listing resources.")
      let result = try await client.listResources()
      resources = result.resources
      lastActivity = Date()
    } catch {
      logger.error("Failed to refresh resources: \(error)")
    }
  }

  /// Re-fetch the list of Prompts from the server, if supported.
  public func refreshPrompts() async {
    let connected = await client.isConnected
    guard connected, capabilities.supports(.prompts) else { return }
    isRefreshingPrompts = true
    defer { isRefreshingPrompts = false }

    do {
      let connectionId = id
      logger.debug("ConnectionState [\(connectionId)] -> refreshPrompts.")
      let result = try await client.listPrompts()
      prompts = result.prompts
      lastActivity = Date()
    } catch {
      logger.error("Failed to refresh prompts: \(error)")
    }
  }

  /// Attempt to reconnect the underlying MCPClient.
  public func reconnect() async throws {
    reconnectCount += 1
    let connectionId = id
    let attempt = reconnectCount
    logger.info("ConnectionState [\(connectionId)] reconnection attempt #\(attempt)")
    try await client.reconnect()
  }

  // MARK: - Example Tools & Resources usage

  /// Call a named tool, with optional arguments and progress updates.
  public func callTool(
    _ name: String,
    arguments: [String: Any]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> CallToolResult
  {
    guard isConnected, capabilities.supports(.tools) else {
      throw MCPHostError.invalidOperation("Tool usage not supported or disconnected.")
    }
    let result = try await client.callTool(name, with: arguments, progress: progress)
    lastActivity = Date()
    return result
  }

  /// Read a named resource from the server, with optional progress updates.
  public func readResource(
    _ uri: String,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> ReadResourceResult
  {
    guard isConnected, capabilities.supports(.resources) else {
      throw MCPHostError.invalidOperation("Resource usage not supported or disconnected.")
    }
    let result = try await client.readResource(uri, progress: progress)
    lastActivity = Date()
    return result
  }

  /// Subscribe to a resource, if the server supports subscriptions.
  public func subscribe(to uri: String) async throws {
    guard isConnected, capabilities.supports(.resourceSubscribe) else {
      throw MCPHostError.invalidOperation("Resource subscription not supported or disconnected.")
    }
    try await client.subscribe(to: uri)
    lastActivity = Date()
  }

  /// Unsubscribe from a resource, if the server supports subscriptions.
  public func unsubscribe(from uri: String) async throws {
    guard isConnected, capabilities.supports(.resourceSubscribe) else {
      throw MCPHostError.invalidOperation("Resource subscription not supported or disconnected.")
    }
    try await client.unsubscribe(from: uri)
    lastActivity = Date()
  }

  // MARK: - Prompts usage

  /// List available prompts from the server, potentially using a cursor for pagination.
  public func listPrompts(
    cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> ListPromptsResult
  {
    guard isConnected, capabilities.supports(.prompts) else {
      throw MCPHostError.invalidOperation("Prompt usage not supported or disconnected.")
    }
    let result = try await client.listPrompts(cursor: cursor, progress: progress)
    lastActivity = Date()
    return result
  }

  /// Retrieve a specific prompt by name, optionally providing arguments and a progress handler.
  public func getPrompt(
    _ name: String,
    arguments: [String: String]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> GetPromptResult
  {
    guard isConnected, capabilities.supports(.prompts) else {
      throw MCPHostError.invalidOperation("Prompt usage not supported or disconnected.")
    }
    let result = try await client.getPrompt(name, arguments: arguments, progress: progress)
    lastActivity = Date()
    return result
  }

  // MARK: Internal

  /// The underlying MCPClient for this connection
  let client: MCPClient

  // MARK: Private

  private var statusMonitorTask: Task<Void, Never>?

  // MARK: - Async Streams for ConnectionState events

  /// Stores the continuation manager
  @ObservationIgnored private let continuationStore = ContinuationStore()

  private func storeConnectionContinuation(
    _ id: UUID,
    _ cont: AsyncStream<ConnectionStateEvent>.Continuation)
    async
  {
    await continuationStore.store(id, cont)
    cont.onTermination = { [weak self] _ in
      Task { [weak self] in
        await self?.removeConnectionContinuation(id)
      }
    }
  }

  private func removeConnectionContinuation(_ id: UUID) async {
    await continuationStore.remove(id)
  }

  private func yieldEvent(_ event: ConnectionStateEvent) async {
    await continuationStore.yieldToAll(event)
  }

}

// MARK: Equatable

extension ConnectionState: Equatable {
  public static func ==(lhs: ConnectionState, rhs: ConnectionState) -> Bool {
    lhs.id == rhs.id && lhs.status == rhs.status && lhs.serverInfo == rhs.serverInfo
      && lhs.capabilities == rhs.capabilities && lhs.tools == rhs.tools
      && lhs.resources == rhs.resources && lhs.prompts == rhs.prompts
      && lhs.lastActivity == rhs.lastActivity && lhs.reconnectCount == rhs.reconnectCount
  }
}
