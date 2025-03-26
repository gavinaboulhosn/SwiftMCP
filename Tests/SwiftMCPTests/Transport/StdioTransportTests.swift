import Foundation
import Testing

@testable import SwiftMCP

@Suite("StdioTransport Tests")
struct StdioTransportTests {
  @Test("Start/stop a valid process")
  func testBasicLifecycle() async throws {
    let transport = StdioTransport(
      command: "echo",
      arguments: ["hello-world"]
    )

    #expect(await transport.state == .disconnected)
    try await transport.start()
    #expect(await transport.state == .connected)
    #expect(await transport.isRunning)

    // Read the stream
    let messages = try await transport.messages
    var outputData = Data()
    do {
      for try await message in messages {
        if let data = try? JSONEncoder().encode(message) {
          outputData.append(data)
        }
      }
    } catch {
      Issue.record("Unexpected error reading messages: \(error)")
    }

    // Stop
    await transport.stop()
    #expect(await transport.state == .disconnected)
    #expect(await !(transport.isRunning))
  }

  @Test("Invalid command fails to start")
  func testInvalidCommand() async throws {
    let transport = StdioTransport(command: "invalid_command_which_does_not_exist")

    try await transport.start()
    try await Task.sleep(for: .milliseconds(100))

    // Should remain disconnected
    #expect(await transport.state == .disconnected)
    #expect(await !transport.isRunning)
  }

  @Test("Stop is idempotent and does not crash if called multiple times")
  func testDoubleStop() async throws {
    let transport = StdioTransport(
      command: "echo",
      arguments: ["double-stop"]
    )
    try await transport.start()
    #expect(await transport.state == .connected)

    await transport.stop()
    #expect(await transport.state == .disconnected)
    await transport.stop()  // second stop call
    #expect(await transport.state == .disconnected)
  }

  @Test("Sending message exceeding maxMessageSize throws error")
  func testExceedingMaxMessageSize() async throws {
    let config = TransportConfiguration(maxMessageSize: 10)  // artificially small
    let transport = StdioTransport(
      command: "cat",
      arguments: [],
      configuration: config
    )

    try await transport.start()

    // Create a large notification that will exceed the size limit
    let largeString = String(repeating: "X", count: 100)
    let notification = LargeTestNotification(content: largeString)
    let message = JSONRPCMessage.notification(notification)

    do {
      try await transport.send(message)
      Issue.record("Expected to throw .messageTooLarge")
    } catch let TransportError.messageTooLarge(size) {
      #expect(size > 10)  // Size should be larger than our artificial limit
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    await transport.stop()
  }

  @Test("Forcible child termination does not leak zombies")
  func testForcedTermination() async throws {
    // Use a command that sleeps for 100 seconds
    // We'll forcibly kill it before it finishes
    let transport = StdioTransport(
      command: "sleep",
      arguments: ["100"]
    )

    try await transport.start()
    #expect(await transport.isRunning)

    // Stop the transport
    await transport.stop()
    #expect(await !transport.isRunning)

    // We can't easily detect zombies in a portable way here,
    // but we can at least confirm the transport is fully disconnected
    #expect(await transport.state == .disconnected)
  }

  @Test("Calling send after stop should fail gracefully")
  func testSendAfterStop() async throws {
    let transport = StdioTransport(
      command: "cat", arguments: []
    )
    try await transport.start()
    await transport.stop()

    let message = JSONRPCMessage.notification(StdioTestNotification())

    do {
      try await transport.send(message)
      Issue.record("Expected failure after stop()")
    } catch let TransportError.invalidState(reason) {
      #expect(reason.contains("not connected"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("Multiple calls to start() without stop() are no-ops")
  func testMultipleStartCalls() async throws {
    let transport = StdioTransport(
      command: "cat", arguments: []
    )
    try await transport.start()
    #expect(await transport.state == .connected)

    // Attempting to start again should do nothing
    try await transport.start()
    #expect(await transport.state == .connected)

    await transport.stop()
    #expect(await transport.state == .disconnected)
  }
}

// Helper notification classes for testing
struct StdioTestNotification: MCPNotification {
  var method: String { "test/notification" }
  var params: Any? { nil }
}

struct LargeTestNotification: MCPNotification {
  var content: String

  var method: String { "test/large_notification" }
  var params: Any? {
    ["content": content]
  }
}

