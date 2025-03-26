import Foundation
import OSLog

// MARK: - MCPHost

/// The primary interface for interacting with multiple MCP server connections at once.
public actor MCPHost {

  // MARK: Lifecycle

  /// Initialize an MCPHost with a given configuration.
  public init(config: MCPConfiguration = .init()) {
    configuration = config
  }

  // MARK: Public

  // MARK: - Public Event Stream

  /// Provides an `AsyncStream` for observing `MCPHostEvent` changes.
  /// Each call returns a new independent stream for a different observer.
  public func events() -> AsyncStream<MCPHostEvent> {
    let id = UUID()
    return AsyncStream<MCPHostEvent> { continuation in
      Task { [weak self] in
        await self?.storeHostEventContinuation(id, continuation)
      }
    }
  }

  // MARK: - Connection Management

  /// Retrieve an existing connection state by ID.
  public func connectionState(for id: String) -> ConnectionState? {
    connections[id]
  }

  /// Returns a list of all current connections.
  public func allConnections() -> [ConnectionState] {
    Array(connections.values)
  }

  /// Creates a new connection by starting an `MCPClient` with the given transport,
  /// then wrapping it in a `ConnectionState`.
  ///
  /// - Throws: `MCPHostError.connectionExists` if ID is already in use,
  ///           or other errors if the client fails to start.
  /// - Returns: The newly created `ConnectionState`.
  @discardableResult
  public func connect(_ id: String, transport: MCPTransport) async throws -> ConnectionState {
    if connections[id] != nil {
      throw MCPHostError.connectionExists(id)
    }

    let client = MCPClient(configuration: configuration.clientConfig)
    if let sampling = configuration.sampling {
      await client.registerHandler(for: CreateMessageRequest.self) { request in
        try await sampling.handler(request)
      }
    }

    try await client.start(transport)
    let state = await client.state
    guard case .running(let sessInfo) = state else {
      throw MCPHostError.invalidOperation("Client failed to reach running state after start.")
    }

    let connection = ConnectionState(
      id: id,
      client: client,
      serverInfo: sessInfo.serverInfo,
      capabilities: sessInfo.capabilities)

    // Spawn a task to listen to client notifications.
    let notifTask = Task { [weak self, weak connection] in
      guard let self = self, let connection = connection else { return }
      for await note in client.notifications {
        await self.handleNotification(note, for: connection)
        await Task.yield() // yield to allow other actor messages to run
      }
    }
    connections[id] = connection
    notificationTasks[id] = notifTask

    // Immediately yield a connection-added event.
    yieldHostEvent(.connectionAdded(connection))

    // Spawn a detached task to forward connection status events.
    let connEventStream = connection.events()
    Task.detached { [weak self, weak connection] in
      guard let self = self, let connection = connection else { return }
      for await _ in connEventStream {
        await self.yieldHostEvent(.connectionStatusChanged(connection))
        await Task.yield()
      }
    }

    return connection
  }

  /// Disconnect and remove a connection by ID, if present.
  public func disconnect(_ id: String) async throws {
    guard let conn = connections[id] else {
      throw MCPHostError.connectionNotFound(id)
    }
    await conn.client.stop()

    connections[id] = nil
    notificationTasks[id]?.cancel()
    notificationTasks[id] = nil

    yieldHostEvent(.connectionRemoved(id))
  }

  // MARK: - Capability Management

  /// Retrieves all available tools across all connections (union).
  public func availableTools() async -> [MCPTool] {
    Array(Set(connections.values.flatMap { $0.tools }))
  }

  /// Returns all connections that support a particular feature.
  public func connections(supporting feature: ServerCapabilities.Features) -> [ConnectionState] {
    connections.values.filter { $0.capabilities.supports(feature) }
  }

  // MARK: - Health & State Queries

  /// Returns a list of connections that haven't had activity within the specified timeout.
  public func inactiveConnections(timeout: TimeInterval) -> [ConnectionState] {
    let cutoff = Date().addingTimeInterval(-timeout)
    return connections.values.filter { $0.lastActivity < cutoff }
  }

  /// Indicates whether any connections are in a failed state.
  public func hasFailedConnections() -> Bool {
    connections.values.contains { $0.status.hasError }
  }

  /// Returns all connections currently in the failed state.
  public func failedConnections() -> [ConnectionState] {
    connections.values.filter { $0.status.hasError }
  }

  // MARK: Private

  private var configuration: MCPConfiguration
  private var connections: [String: ConnectionState] = [:]
  private var notificationTasks: [String: Task<Void, Never>] = [:]

  /// Async Streams for host-level events
  private var hostEventContinuations: [UUID: AsyncStream<MCPHostEvent>.Continuation] = [:]

  private func storeHostEventContinuation(
    _ id: UUID, _ cont: AsyncStream<MCPHostEvent>.Continuation)
  {
    hostEventContinuations[id] = cont
    cont.onTermination = { _ in
      Task { [weak self] in
        await self?.removeHostEventContinuation(id)
      }
    }
  }

  private func removeHostEventContinuation(_ id: UUID) {
    hostEventContinuations.removeValue(forKey: id)
  }

  private func yieldHostEvent(_ event: MCPHostEvent) {
    for cont in hostEventContinuations.values {
      cont.yield(event)
    }
  }

  /// Handle inbound notifications from a given ConnectionState's client.
  private func handleNotification(_ notification: any MCPNotification, for state: ConnectionState)
    async
  {
    switch notification {
    case is ToolListChangedNotification:
      await state.refreshTools()
    case is ResourceListChangedNotification:
      await state.refreshResources()
    case is PromptListChangedNotification:
      await state.refreshPrompts()
    case is ResourceUpdatedNotification:
      await state.refreshResources()
    default:
      break
    }
  }
}
