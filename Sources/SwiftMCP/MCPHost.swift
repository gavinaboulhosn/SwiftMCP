import Foundation
import OSLog

/// Events emitted by an `MCPHost`:
/// - connectionAdded: A new connection was added
/// - connectionRemoved: A connection was removed
/// - connectionStatusChanged: The status of a connection changed
public enum MCPHostEvent {
  case connectionAdded(ConnectionState)
  case connectionRemoved(String)
  case connectionStatusChanged(ConnectionState)
}

/// The primary interface for interacting with multiple MCP server connections at once.
public actor MCPHost {
  private let logger = Logger(subsystem: "SwiftMCP", category: "MCPHost")

  private var configuration: MCPConfiguration
  private var connections: [String: ConnectionState] = [:]
  private var notificationTasks: [String: Task<Void, Never>] = [:]

  // Async Streams for host-level events
  private var hostEventContinuations: [UUID: AsyncStream<MCPHostEvent>.Continuation] = [:]

  /// Initialize an MCPHost with a given configuration.
  public init(config: MCPConfiguration = .init()) {
    self.configuration = config
  }

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

  private func storeHostEventContinuation(
    _ id: UUID, _ cont: AsyncStream<MCPHostEvent>.Continuation
  ) {
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
  public func connect(
    _ id: String,
    transport: MCPTransport
  ) async throws -> ConnectionState {
    if connections[id] != nil {
      throw MCPHostError.connectionExists(id)
    }

    let client = MCPClient(configuration: configuration.clientConfig)

    // If there's some special "sampling" handler
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
      capabilities: sessInfo.capabilities
    )

    // Listen to the client's notifications
    let notifTask = Task { [weak self, weak connection] in
      guard let self, let connection else { return }
      for await note in client.notifications {
        await self.handleNotification(note, for: connection)
      }
    }

    connections[id] = connection
    notificationTasks[id] = notifTask

    yieldHostEvent(.connectionAdded(connection))

    // Also watch for status changes from the connection itself
    let connEventStream = connection.events()
    Task.detached { [weak self, weak connection] in
      guard let self, let connection else { return }
      for await _ in connEventStream {
        await self.yieldHostEvent(.connectionStatusChanged(connection))
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
    connections.values.contains { $0.status == .failed }
  }

  /// Returns all connections currently in the failed state.
  public func failedConnections() -> [ConnectionState] {
    connections.values.filter { $0.status == .failed }
  }

  // MARK: - Private

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

/// Host-level errors that are not part of the MCP protocol itself.
///
/// For instance, "no such connection," "connection already exists," or other
/// usage errors at the MCPHost level.
public enum MCPHostError: Error, LocalizedError {
  /// No connection found for a given ID
  case connectionNotFound(String)
  /// A connection with the same ID already exists
  case connectionExists(String)
  /// Operation is invalid in the current host context
  case invalidOperation(String)
  /// Catch-all for unknown issues
  case unknown(String)

  public var errorDescription: String? {
    switch self {
    case .connectionNotFound(let id):
      return "No connection found for id: \(id)"
    case .connectionExists(let id):
      return "A connection with id '\(id)' already exists."
    case .invalidOperation(let msg):
      return "Invalid host operation: \(msg)"
    case .unknown(let msg):
      return "Unknown Host Error: \(msg)"
    }
  }
}
