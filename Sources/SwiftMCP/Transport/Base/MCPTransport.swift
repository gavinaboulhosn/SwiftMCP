import Foundation

// MARK: - MCPTransport

/// A protocol describing the core transport interface for MCP.
/// It is an `Actor` so that transport operations are serialized.
public protocol MCPTransport: Actor {
  /// The current state of the transport
  var state: TransportState { get }

  /// Current transport-level configuration
  var configuration: TransportConfiguration { get }

  /// A live stream of the current transport state
  var stateMessages: AsyncStream<TransportState> { get throws }

  /// Provides a stream of raw `JSONRPCMessage` messages.
  /// This is used by `MCPClient` to receive inbound messages.
  var messages: AsyncThrowingStream<JSONRPCMessage, Error> { get throws }

  /// Start the transport, transitioning it from `.disconnected` to `.connecting` and eventually `.connected`.
  func start() async throws

  /// Stop the transport, closing any connections and cleaning up resources.
  func stop() async

  /// Send data across the transport, optionally with a custom timeout.
  func send(_ data: JSONRPCMessage, timeout: TimeInterval?) async throws
}

extension MCPTransport {
  /// Default `send(_ message:timeout:)` with an optional parameter.
  public func send(_ message: JSONRPCMessage, timeout: TimeInterval? = nil) async throws {
    try await send(message, timeout: timeout)
  }

  /// Validates messages before sending
  public func validate(_ message: JSONRPCMessage) throws -> Data {
    let bytes: Data
    do {
      bytes = try JSONEncoder().encode(message)
    } catch {
      throw TransportError.operationFailed(
        "Failed to serialize message: \(error.localizedDescription)")
    }
    let messageSize = bytes.count
    let maxMessageSize = configuration.maxMessageSize
    if messageSize > maxMessageSize {
      throw TransportError.messageTooLarge(messageSize)
    }
    return bytes
  }

  /// Parses message from data
  public func parse(_ data: Data) throws -> JSONRPCMessage {
    guard let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) else {
      throw TransportError.invalidMessage("Unable to parse JSONRPCMessage from data: \(data)")
    }
    return message
  }
}

extension MCPTransport {
  func startHealthCheckTask() async throws {
    guard state == .connected else {
      // not connected, why are we pinging?!?!??!
      return
    }
    try await ping()
    try await Task.sleep(for: .seconds(configuration.healthCheckInterval))
  }

  /// Sends a ping to the server
  func ping() async throws {
    let requestId = UUID().uuidString
    let message = JSONRPCMessage.request(id: .string(requestId), request: PingRequest())
    _ = try await send(message)
  }
}
