import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "MCPClient")

// MARK: - MCPClientEvent

/// Events emitted by `MCPClient`, bridging some internal states and messages.
public enum MCPClientEvent {
  /// Connection state changed (connecting, running, disconnected, etc.)
  case connectionChanged(MCPEndpointState<InitializeResult>)
  /// Incoming MCP message (JSON-RPC request/notification from server)
  case message(any MCPMessage)
  /// Indicates an error encountered in the MCP client
  case error(Error)
}

// MARK: - MCPClient

/// A client (endpoint) for the Model Context Protocol (MCP).
public actor MCPClient: MCPEndpointProtocol {

  // MARK: Lifecycle

  // MARK: - Initialization

  /// Creates a client with a given configuration.
  public init(
    clientInfo: Implementation,
    capabilities: ClientCapabilities = .init())
  {
    let (notifications, notificationsContinuation) = AsyncStream.makeStream(
      of: (any MCPNotification).self)
    self.notifications = notifications
    self.notificationsContinuation = notificationsContinuation

    let (events, eventsContinuation) = AsyncStream.makeStream(of: MCPClientEvent.self)
    self.events = events
    self.eventsContinuation = eventsContinuation

    clientCapabilities = capabilities
    self.clientInfo = clientInfo
  }

  /// Convenience init that uses `Configuration`
  public init(configuration: Configuration) {
    self.init(
      clientInfo: configuration.clientInfo,
      capabilities: configuration.capabilities)
  }

  // MARK: Public

  public typealias SessionInfo = InitializeResult

  /// Configuration for the client, specifying `Implementation` details
  /// and `ClientCapabilities`.
  public struct Configuration {
    public let clientInfo: Implementation
    public let capabilities: ClientCapabilities

    public init(clientInfo: Implementation, capabilities: ClientCapabilities) {
      self.clientInfo = clientInfo
      self.capabilities = capabilities
    }

    public static let `default` = Configuration(
      clientInfo: .defaultClient,
      capabilities: .init())
  }

  /// Stream of notifications from this client
  public let notifications: AsyncStream<any MCPNotification>
  /// Stream of client events for external observation
  public let events: AsyncStream<MCPClientEvent>

  // MARK: - State

  public private(set) var state = MCPEndpointState<SessionInfo>.disconnected {
    didSet {
      eventsContinuation.yield(.connectionChanged(state))
    }
  }

  /// Returns `true` if the client is in a `.running` state.
  public var isConnected: Bool {
    guard case .running = state else { return false }
    return true
  }

  /// Registers a handler for a specific MCPRequest type
  /// so that the client can respond to inbound requests from a server.
  public func registerHandler<R: MCPRequest>(
    for _: R.Type,
    handler: @escaping (R) async throws -> R.Response)
  {
    let handler: ServerRequestHandler = { anyReq in
      guard let typed = anyReq as? R else {
        throw MCPError.invalidRequest("Unexpected request type")
      }
      return try await handler(typed)
    }
    requestHandlers[R.method] = handler
  }

  // MARK: - Connection Management

  /// Start the client using the given `transport`.
  /// - Throws: If starting or initialization fails.
  public func start(_ transport: MCPTransport) async throws {
    if case .running = state {
      await stop()
    }

    self.transport = transport
    state = .connecting

    try await transport.start()

    if await transport.state != .connected {
      for try await ready in try await transport.stateMessages {
        if ready == .connected {
          break
        }
      }
    }

    messageTask = Task {
      do {
        for try await message in await try transport.messages {
          try Task.checkCancellation()
          try await self.processIncomingMessage(message)
        }
      } catch {
        await handleError(error)
      }
    }

    await startMonitoring()

    state = .initializing
    registerDefaultRequestHandlers()

    do {
      let capabilities = try await performInitialization()
      state = .running(capabilities)
    } catch {
      let errMsg = "Failed to initialize server connection: \(error)"
      state = .failed(MCPError.internalError(errMsg))
      logger.error("\(errMsg)")
      throw error
    }
  }

  /// Stop the client, cancelling tasks and clearing state.
  public func stop() async {
    messageTask?.cancel()
    messageTask = nil

    monitoringTask?.cancel()
    monitoringTask = nil
    reconnectAttempts = 0

    let stopErr = MCPError.internalError("Client stopped")
    for request in pendingRequests.values {
      request.cancel(with: stopErr)
    }
    pendingRequests.removeAll()

    await transport?.stop()
    state = .disconnected
    logger.debug("MCPClient stopped.")
  }

  /// Attempt to reconnect using the same transport.
  public func reconnect() async throws {
    if isConnected {
      await stop()
    }
    guard let transport else {
      throw MCPError.internalError("No transport available to reconnect.")
    }

    state = .connecting
    await transport.stop()
    reconnectAttempts = 0

    try await transport.start()
    do {
      let capabilities = try await performInitialization()
      state = .running(capabilities)
    } catch {
      let msg = "Failed to initialize after reconnect: \(error)"
      state = .failed(MCPError.internalError(msg))
      logger.error("\(msg)")
    }
  }

  // MARK: - Request Handling

  /// Send an MCP request of type `R`.
  public func send<R: MCPRequest>(_ request: R) async throws -> R.Response {
    try await send(request, progressHandler: nil)
  }

  /// Send an MCP request with an optional progress handler.
  public func send<R: MCPRequest>(
    _ request: R,
    progressHandler: ProgressHandler.UpdateHandler? = nil)
    async throws -> R.Response
  {
    guard case .running(let sess) = state else {
      throw MCPError.internalError("Client must be running to send requests")
    }

    try validateCapabilities(sess.capabilities, for: request)
    let response = try await sendRequest(request, progressHandler: progressHandler)
    logger.debug(
      "MCPClient sent request \(R.method) -> received response type \(String(describing: R.Response.self))")
    return response
  }

  /// Emit an MCP notification (no response).
  public func emit(_ notification: some MCPNotification) async throws {
    guard case .running = state else {
      throw MCPError.internalError("Client must be running to send notifications")
    }
    try await transport?.send(.notification(notification))
  }

  /// Register a root structure for demonstration, if needed.
  public func updateRoots(_ roots: [Root]?) async throws {
    guard let roots else {
      currentRoots = []
      return
    }
    try await notifyRootsChanged(roots)
  }

  // MARK: Private

  private let notificationsContinuation: AsyncStream<any MCPNotification>.Continuation
  private let eventsContinuation: AsyncStream<MCPClientEvent>.Continuation

  private var pendingRequests: [RequestID: any PendingRequestProtocol] = [:]
  private var requestHandlers: [String: ServerRequestHandler] = [:]

  /// Manages background reading from transport
  private var messageTask: Task<Void, Error>?
  /// Periodic monitoring (health check) task
  private var monitoringTask: Task<Void, Never>?
  /// Count of reconnection attempts
  private var reconnectAttempts = 0

  private var transport: (any MCPTransport)?
  private let clientInfo: Implementation
  private let clientCapabilities: ClientCapabilities

  private var currentRoots: [Root] = []

  /// Manages progress notifications for requests
  private let progressManager = ProgressManager()

  /// Set up a periodic health check if the transport config so indicates.
  private func startMonitoring() async {
    guard
      let configuration = await transport?.configuration,
      configuration.healthCheckEnabled
    else { return }

    let interval = configuration.healthCheckInterval
    let maxReconnect = configuration.maxReconnectAttempts

    monitoringTask?.cancel()
    monitoringTask = Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(interval))
          try Task.checkCancellation()
          await performHealthCheck(maxReconnect: maxReconnect)
        } catch {
          return
        }
      }
    }
  }

  /// Perform a single health check by calling `ping()`.
  private func performHealthCheck(maxReconnect: Int) async {
    do {
      try await ping()
      reconnectAttempts = 0
    } catch {
      let newAttempts = reconnectAttempts + 1
      reconnectAttempts += newAttempts
      logger.warning("MCPClient ping failed: \(error). Reconnect attempt \(newAttempts)")
      if reconnectAttempts <= maxReconnect {
        do {
          try await reconnect()
        } catch {
          logger.error("Reconnection attempt failed: \(error)")
        }
      } else {
        logger.error("Max reconnect attempts reached. Stopping MCPClient.")
        await stop()
      }
    }
  }

  private func sendRequest<R: MCPRequest>(
    _ request: R,
    progressHandler: ProgressHandler.UpdateHandler? = nil)
    async throws -> R.Response
  {
    guard let transport else {
      throw MCPError.connectionClosed()
    }

    let requestId = RequestID.string(UUID().uuidString)
    var newReq = request

    if let progress = progressHandler {
      let meta = RequestMeta(progressToken: requestId)
      newReq.params._meta = meta
      let handler = ProgressHandler(token: requestId, handler: progress)
      await progressManager.register(handler, for: requestId)
    }

    let msg = JSONRPCMessage.request(id: requestId, request: newReq)

    return try await withCheckedThrowingContinuation { continuation in
      let timeoutTask = Task {
        try? await Task.sleep(for: .seconds(transport.configuration.sendTimeout))
        if pendingRequests[requestId] != nil {
          pendingRequests.removeValue(forKey: requestId)
          await continuation.resume(
            throwing: MCPError.timeout(
              R.method,
              duration: transport.configuration.sendTimeout))
        }
      }

      pendingRequests[requestId] = PendingRequest<R.Response>(
        continuation: continuation,
        timeoutTask: timeoutTask)

      Task {
        do {
          try await transport.send(msg)
        } catch {
          if let pen = pendingRequests.removeValue(forKey: requestId) {
            pen.cancel(with: error)
          }
        }
      }
    }
  }

  private func processIncomingMessage(_ message: JSONRPCMessage) async throws {
    switch message {
    case .notification(let anyNotif):
      switch anyNotif {
      case let cancelled as CancelledNotification:
        try await handleCancelledRequest(cancelled)
      case let progress as ProgressNotification:
        await progressManager.handle(progress)
      default:
        notificationsContinuation.yield(anyNotif)
      }

    case .response(let id, let anyResult):
      await handleResponse(id, anyResult)

    case .error(let id, let rpcError):
      if let pending = pendingRequests[id] {
        pending.cancel(with: rpcError)
        pendingRequests.removeValue(forKey: id)
      }
      await progressManager.unregister(for: id)

    case .request(let id, let inboundReq):
      try await handleRequest(id, inboundReq)
    }
  }

  private func handleResponse(_ id: RequestID, _ resultCodable: AnyCodable) async {
    if let pending = pendingRequests[id] {
      do {
        let encoded = try JSONEncoder().encode(resultCodable)
        let typedResponse = try JSONDecoder().decode(pending.responseType, from: encoded)
        try pending.complete(with: typedResponse)
      } catch {
        pending.cancel(with: error)
      }
      pendingRequests.removeValue(forKey: id)
    } else {
      logger.warning("No pending request found for id \(id)")
    }
    await progressManager.unregister(for: id)
  }

  private func handleRequest(_ id: RequestID, _ inbound: any MCPRequest) async throws {
    let method = type(of: inbound).method
    guard let handler = requestHandlers[method] else {
      let error = MCPError.methodNotFound(method)
      try await transport?.send(.error(id: id, error: error))
      return
    }

    do {
      let resp = try await handler(inbound)
      try await transport?.send(.response(id, response: resp))
    } catch {
      let mcpe = error as? MCPError ?? MCPError.internalError(error.localizedDescription)
      try await transport?.send(.error(id: id, error: mcpe))
    }
  }

  private func registerDefaultRequestHandlers() {
    registerHandler(for: ListRootsRequest.self) { [weak self] request in
      guard let self else {
        throw MCPError.internalError("Client was deallocated")
      }
      return try await handleListRoots(request)
    }
  }

  private func handleCancelledRequest(_ notification: CancelledNotification) async throws {
    guard let pending = pendingRequests[notification.params.requestId] else { return }
    pending.cancel(with: MCPError.internalError("Request was cancelled via CancelledNotification"))
    pendingRequests.removeValue(forKey: notification.params.requestId)
  }

  private func performInitialization() async throws -> SessionInfo {
    guard let transport else {
      throw MCPError.internalError("No transport available for initialization.")
    }

    let initReq = InitializeRequest(
      params: .init(
        capabilities: clientCapabilities,
        clientInfo: clientInfo,
        protocolVersion: MCPVersion.currentVersion))
    let initResp = try await sendRequest(initReq)

    // Validate protocol version
    guard MCPVersion.isSupported(initResp.protocolVersion) else {
      throw MCPError.invalidRequest("Server MCP version \(initResp.protocolVersion) not supported.")
    }

    let notification = InitializedNotification()
    try await transport.send(.notification(notification))

    return initResp
  }

  /// Validate that the server capabilities for the current session support the given request.
  private func validateCapabilities(
    _ capabilities: ServerCapabilities,
    for request: any MCPRequest)
    throws
  {
    switch request {
    case is ListPromptsRequest:
      guard capabilities.prompts != nil else {
        throw MCPError.invalidRequest("Server does not support prompts.")
      }

    case is ListResourcesRequest, is ReadResourceRequest:
      guard capabilities.resources != nil else {
        throw MCPError.invalidRequest("Server does not support resources.")
      }

    case is ListToolsRequest, is CallToolRequest:
      guard capabilities.tools != nil else {
        throw MCPError.invalidRequest("Server does not support tools.")
      }

    case is SetLevelRequest:
      guard capabilities.logging != nil else {
        throw MCPError.invalidRequest("Server does not support logging.")
      }

    case is InitializeRequest:
      // Always allowed
      break

    default:
      // Allow unknown request types for future extension
      break
    }
  }

  /// Called when we encounter an error in the message Task or SSE loop,
  /// attempts to reconnect (if configured).
  private func handleError(_ error: Error) async {
    logger.error("MCPClient encountered error: \(error). Transitioning to failed state.")
    state = .failed(error)
    // Cancel pending requests
    for pending in pendingRequests.values {
      pending.cancel(with: error)
    }
    pendingRequests.removeAll()
  }

  private func notifyRootsChanged(_ newRoots: [Root]) async throws {
    guard newRoots != currentRoots else { return }
    currentRoots = newRoots
    try await emit(RootsListChangedNotification())
  }

  /// Simplified handler for list roots request
  private func handleListRoots(_: ListRootsRequest) async throws -> ListRootsResult {
    ListRootsResult(roots: currentRoots)
  }
}

// MARK: Client API
extension MCPClient {
  public func listPrompts(
    cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> ListPromptsResult
  {
    try await send(ListPromptsRequest(cursor: cursor), progressHandler: progress)
  }

  public func getPrompt(
    _ name: String,
    arguments: [String: String]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> GetPromptResult
  {
    try await send(
      GetPromptRequest(name: name, arguments: arguments ?? [:]), progressHandler: progress)
  }

  public func listTools(
    cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> ListToolsResult
  {
    try await send(ListToolsRequest(cursor: cursor), progressHandler: progress)
  }

  public func callTool(
    _ toolName: String,
    with arguments: [String: Any]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> CallToolResult
  {
    try await send(
      CallToolRequest(
        name: toolName,
        arguments: arguments ?? [:]),
      progressHandler: progress)
  }

  public func setLoggingLevel(
    _ level: LoggingLevel,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws
  {
    _ = try await send(SetLevelRequest(level: level), progressHandler: progress)
  }

  public func listResources(
    _ cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> ListResourcesResult
  {
    try await send(ListResourcesRequest(cursor: cursor), progressHandler: progress)
  }

  public func subscribe(
    to uri: String,
    progress _: ProgressHandler.UpdateHandler? = nil)
    async throws
  {
    _ = try await send(SubscribeRequest(uri: uri))
  }

  public func unsubscribe(
    from uri: String,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws
  {
    _ = try await send(UnsubscribeRequest(uri: uri), progressHandler: progress)
  }

  public func listResourceTemplates(
    _ cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> ListResourceTemplatesResult
  {
    try await send(ListResourceTemplatesRequest(cursor: cursor), progressHandler: progress)
  }

  public func readResource(
    _ uri: String,
    progress: ProgressHandler.UpdateHandler? = nil)
    async throws -> ReadResourceResult
  {
    try await send(ReadResourceRequest(uri: uri), progressHandler: progress)
  }

  public func ping() async throws {
    _ = try await send(PingRequest())
  }
}

extension MCPClient {

  // MARK: Public

  public typealias ServerRequestHandler = (any MCPRequest) async throws -> any MCPResponse

  // MARK: Private

  private protocol PendingRequestProtocol {
    func cancel(with error: Error)
    func complete(with response: any MCPResponse) throws

    var responseType: any MCPResponse.Type { get }
  }

  private struct PendingRequest<Response: MCPResponse>: PendingRequestProtocol {
    let continuation: CheckedContinuation<Response, any Error>
    let timeoutTask: Task<Void, Never>?

    var responseType: any MCPResponse.Type { Response.self }

    func cancel(with error: Error) {
      timeoutTask?.cancel()
      continuation.resume(throwing: error)
    }

    func complete(with response: any MCPResponse) throws {
      guard let typedResponse = response as? Response else {
        throw MCPError.internalError("Unexpected response type")
      }
      timeoutTask?.cancel()
      continuation.resume(returning: typedResponse)
    }
  }
}
