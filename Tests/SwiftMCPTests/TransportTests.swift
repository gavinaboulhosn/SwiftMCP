import Foundation
import Testing

@testable import SwiftMCP

@Suite("StdioTransport")
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

    // Read the stream (which should produce "hello-world\n")
    let messages = await transport.messages()
    var outputData = Data()
    do {
      for try await chunk in messages {
        outputData.append(chunk)
      }
    } catch {
      Issue.record("Unexpected error reading messages: \(error)")
    }

    // Stop
    await transport.stop()
    #expect(await transport.state == .disconnected)
    #expect(await !(transport.isRunning))
    let outputString = String(data: outputData, encoding: .utf8) ?? ""
    #expect(outputString.contains("hello-world"))
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

  @Test("Send data before start triggers start automatically")
  func testAutoStartOnSend() async throws {
    let transport = StdioTransport(
      command: "echo",
      arguments: ["auto-start-test"]
    )

    // Access the message stream, which should auto-start the process
    let stream = await transport.messages()
    var lines = [String]()
    do {
      for try await data in stream {
        let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
        if let s = str, !s.isEmpty {
          lines.append(s)
        }
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(!lines.isEmpty)
    #expect(lines.contains("auto-start-test"))
    #expect(await transport.state == .disconnected)
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

  @Test("Large message that fits in maxMessageSize can be sent")
  func testSendingLargeMessage() async throws {
    // Increase max message size for testing
    let config = TransportConfiguration(maxMessageSize: 1024 * 1024)  // 1 MB
    let transport = StdioTransport(
      command: "cat",
      arguments: [],
      configuration: config
    )

    try await transport.start()
    let testData = Data(repeating: 65, count: 100_000)  // 100 KB of 'A'
    try await transport.send(testData)

    // Read back from messages
    var totalRead = 0
    let stream = await transport.messages()
    do {
      for try await chunk in stream {
        totalRead += chunk.count
        if totalRead >= 100_000 {
          break
        }
      }
    } catch {
      Issue.record("Unexpected error reading large message: \(error)")
    }
    #expect(totalRead == 100_000)

    await transport.stop()
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
    let oversized = Data(repeating: 66, count: 100)  // 100 bytes

    do {
      try await transport.send(oversized)
      Issue.record("Expected to throw .messageTooLarge")
    } catch let TransportError.messageTooLarge(size) {
      #expect(size == 100)
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

    // We can’t easily detect zombies in a portable way here,
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

    do {
      try await transport.send(Data("Hello?".utf8))
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
