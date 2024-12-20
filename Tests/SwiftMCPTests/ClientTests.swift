import Foundation
import Testing
@testable import SwiftMCP

/// Mock transport for testing
actor MockTransport: MCPTransport {
  var state: TransportState = .disconnected
  let configuration: TransportConfiguration
  
  private var messageStream: AsyncStream<Data>
  private let messageContinuation: AsyncStream<Data>.Continuation
  private var queuedResponses: [(Data) async throws -> Data] = []
  private var sentMessages: [Data] = []
  
  init(configuration: TransportConfiguration = .default) {
    self.configuration = configuration
    
    var continuation: AsyncStream<Data>.Continuation!
    self.messageStream = AsyncStream { continuation = $0 }
    self.messageContinuation = continuation
  }
  
  func messages() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      Task {
        for try await message in messageStream {
          continuation.yield(message)
        }
        continuation.finish()
      }
    }
  }
  
  func start() async throws {
    state = .connected
  }
  
  func stop() async {
    state = .disconnected
    messageContinuation.finish()
  }
  
  func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
    sentMessages.append(data)
    
    // Only process requests, not notifications
    if let message = try? JSONDecoder().decode(
        JSONRPCMessage<InitializeRequest, InitializeResult>.self,
        from: data
    ) {
        switch message {
        case .request:
            // Process the request with next handler
            if let handler = queuedResponses.first {
                queuedResponses.removeFirst()
                let response = try await handler(data)
                messageContinuation.yield(response)
            }
        case .notification:
            // Just record the notification, don't consume a response handler
            break
        default:
            break
        }
    }
}
  
  func queueResponse(_ handler: @escaping (Data) async throws -> Data) {
    queuedResponses.append(handler)
  }
  
  func queueError(_ error: Error) {
    queuedResponses.append { _ in throw error }
  }
  
  func queueInitSuccess() {
    queueResponse { _ in
      let response = JSONRPCMessage<InitializeRequest, InitializeResult>.response(
        id: .string("1"),
        response: InitializeResult(
          capabilities: ServerCapabilities(
            prompts: .init(listChanged: true),
            resources: .init(listChanged: true),
            tools: .init(listChanged: true)
          ),
          protocolVersion: MCPVersion.currentVersion,
          serverInfo: .init(name: "Test", version: "1.0")
        )
      )
      return try JSONEncoder().encode(response)
    }
  }
  
  func sentMessageCount() -> Int {
    sentMessages.count
  }
  
  func lastSentMessage<T: Decodable>(_ type: T.Type) throws -> T {
    guard let data = sentMessages.last else {
      throw MCPError.internalError("No messages sent")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  
  func emitNotification(_ notification: MCPNotification) throws {
    let message = JSONRPCMessage<InitializeRequest, InitializeResult>.notification(notification)
    let data = try JSONEncoder().encode(message)
    messageContinuation.yield(data)
  }
}

@Suite("MCPClient Tests")
struct MCPClientTests {
  @Test("Successfully initializes and connects")
  func testInitialization() async throws {
    let transport = MockTransport()
    await transport.queueInitSuccess()
    
    let client = MCPClient(transport: transport)
    try await client.start()
    
    // Verify state transitions
    let finalState = await client.state
    guard case .running = finalState else {
      throw MCPError.internalError("Expected running state")
    }
    
    // Verify initialization message was sent
    let count = await transport.sentMessageCount()
    try await #require(count == 2)  // Init request + notification
    
    let initMessage: JSONRPCMessage<InitializeRequest, InitializeResult> =
    try await transport.lastSentMessage(JSONRPCMessage<InitializeRequest, InitializeResult>.self)
    guard case .notification = initMessage else {
      throw MCPError.internalError("Expected notification")
    }
  }
  
  @Test("Handles initialization failure")
  func testInitializationFailure() async throws {
    let transport = MockTransport()
    await transport.queueError(MCPError.internalError("Init failed"))
    
    let client = MCPClient(transport: transport)
    
    do {
      try await client.start()
      throw MCPError.internalError("Expected failure")
    } catch {
      let finalState = await client.state
      guard case .failed = finalState else {
        throw MCPError.internalError("Expected failed state")
      }
    }
  }
  
  @Test(
    "Successfully sends requests and receives responses",
    .disabled("Need better coordination for request / response before enabling")
  )
  func testRequestResponse() async throws {
    let transport = MockTransport()
    // Queue initialization first
    await transport.queueInitSuccess()
    
    // Queue prompts list response
    await transport.queueResponse { data in
      // Decode the request to get its ID
      let request = try JSONDecoder().decode(
        JSONRPCMessage<ListPromptsRequest, ListPromptsResult>.self,
        from: data
      )
      guard case .request(let id, _) = request else {
        throw MCPError.internalError("Expected request")
      }
      
      let response = JSONRPCMessage<ListPromptsRequest, ListPromptsResult>.response(
        id: id,  // Use the same ID from request
        response: ListPromptsResult(prompts: [], nextCursor: nil)
      )
      return try JSONEncoder().encode(response)
    }
    
    let client = MCPClient(transport: transport)
    try await client.start()
    
    let result = try await client.send(ListPromptsRequest())
    #expect(result.prompts.isEmpty)
  }
  
  @Test("Handles notifications")
  func testNotifications() async throws {
    let transport = MockTransport()
    await transport.queueInitSuccess()
    
    let client = MCPClient(transport: transport)
    try await client.start()
    
    var receivedNotifications: [MCPNotification] = []
    let notificationTask = Task {
      for await notification in await client.notifications {
        receivedNotifications.append(notification)
        if receivedNotifications.count == 2 {
          break
        }
      }
    }
    
    try await transport.emitNotification(
      PromptListChangedNotification()
    )
    try await transport.emitNotification(
      ResourceListChangedNotification()
    )
    
    _ = await notificationTask.value
    
    #expect(receivedNotifications.count == 2)
    #expect(receivedNotifications[0] as? PromptListChangedNotification != nil)
    #expect(receivedNotifications[1] as? ResourceListChangedNotification != nil)
  }
  
  @Test("Validates capabilities")
  func testCapabilityValidation() async throws {
    let transport = MockTransport()
    // Queue initialization with no prompts capability
    await transport.queueResponse { _ in
      let response = JSONRPCMessage<InitializeRequest, InitializeResult>.response(
        id: .string("1"),
        response: InitializeResult(
          capabilities: ServerCapabilities(),  // No capabilities
          protocolVersion: MCPVersion.currentVersion,
          serverInfo: Implementation(name: "Test", version: "1.0")
        )
      )
      return try JSONEncoder().encode(response)
    }
    
    let client = MCPClient(transport: transport)
    try await client.start()
    
    do {
      _ = try await client.send(ListPromptsRequest())
      throw MCPError.internalError("Expected capability validation failure")
    } catch {
      #expect(error is MCPError)
      #expect("\(error)".contains("does not support prompts"))
    }
  }
  
  @Test("Handles clean shutdown")
  func testShutdown() async throws {
    let transport = MockTransport()
    await transport.queueInitSuccess()
    
    let client = MCPClient(transport: transport)
    try await client.start()
    await client.stop()
    
    let finalState = await client.state
    guard case .disconnected = finalState else {
      throw MCPError.internalError("Expected disconnected state")
    }
    
    let transportState = await transport.state
    guard case .disconnected = transportState else {
      throw MCPError.internalError("Expected disconnected transport")
    }
  }
}