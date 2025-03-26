import Foundation
import Testing

@testable import SwiftMCP

// Shared test transports
private var everythingStdio: MCPTransport {
  StdioTransport(
    command: "npx", arguments: ["-y", "@modelcontextprotocol/server-everything"]
  )
}

private var memoryTransport: MCPTransport {
  StdioTransport(
    command: "npx", arguments: ["-y", "@modelcontextprotocol/server-memory"])
}

private var everythingSSE: MCPTransport {
  SSEClientTransport(sseURL: .init(string: "http://localhost:8000/sse")!)
}

@Suite("Host Feature Tests")
struct FeatureTests {
  @Test(.serialized, arguments: [everythingStdio])
  func testTools(_ transport: MCPTransport) async throws {
    let host = MCPHost()

    let connection = try await host.connect("everything", transport: transport)

    await connection.refreshTools()

    let tools = connection.tools

    #expect(tools.count > 0)

    let echoResponse = try await connection.callTool(
      "echo", arguments: ["message": "Hello, World!"])
    let echoContent = try #require(echoResponse.content.first)
    guard case let .text(echoMessage) = echoContent else {
      Issue.record("Expected string content for echo tool")
      return
    }

    #expect(echoMessage.text == "Echo: Hello, World!")

    let addResponse = try await connection.callTool("add", arguments: ["a": 1, "b": 2])
    let addContent = try #require(addResponse.content.first)
    guard case let .text(addResult) = addContent else {
      Issue.record("Expected string content for add tool")
      return
    }

    #expect(addResult.text.contains("3"))

    // Image
    let imageResponse = try await connection.callTool("getTinyImage", arguments: [:])

    let imageContent = imageResponse.content.first { content in
      guard case .image = content else {
        return false
      }

      return true
    }

    guard case let .image(imageMessage) = imageContent else {
      Issue.record("Expected binary content for image tool")
      return
    }

    #expect(imageMessage.data.count > 0)
  }

  @Test(.serialized, arguments: [everythingStdio])
  func testToolsWithProgress(_ transport: MCPTransport) async throws {
    let host = MCPHost()

    let connection = try await host.connect("everything", transport: transport)

    await connection.refreshTools()
    let tools = connection.tools

    #expect(tools.count > 0)

    // Using actor to safely capture progress updates
    actor ProgressTracker {
      var called = false

      func markCalled() {
        called = true
      }

      func wasCalled() -> Bool {
        return called
      }
    }

    let tracker = ProgressTracker()

    _ = try await connection.callTool(
      "longRunningOperation",
      arguments: [
        "duration": 3,
        "step": 10,
      ],
      progress: { _, _ in
        Task {
          await tracker.markCalled()
        }
      }
    )

    try await Task.sleep(for: .seconds(5))
    #expect(await tracker.wasCalled())
  }

  @Test(.serialized, .disabled("Fix me!"), arguments: [everythingStdio])
  func testSampling(_ transport: MCPTransport) async throws {
    let config = MCPConfiguration(
      roots: .list([]),
      sampling: .init(handler: { _ in
        return .init(
          _meta: nil, content: .text(.init(text: "Hello", annotations: nil)), model: "",
          role: .user, stopReason: "")
      })
    )
    let host = MCPHost(config: config)

    let connection = try await host.connect("everything", transport: transport)

    let sampleResponse = try await connection.callTool(
      "sampleLLM", arguments: ["prompt": "Hello, World!"])
    print(sampleResponse)
    #expect(sampleResponse.content.count > 0)
  }

  @Test(.serialized, arguments: [everythingStdio])
  func testEverythingServerResources(_ transport: MCPTransport) async throws {
    let host = MCPHost()

    let connection = try await host.connect("test", transport: transport)

    await connection.refreshResources()

    #expect(connection.resources.count > 0)

    let textResource = try await connection.readResource("test://static/resource/1")
    #expect(textResource.contents.count > 0)

    let binaryResource = try await connection.readResource("test://static/resource/2")
    #expect(binaryResource.contents.count > 0)
  }

  @Test(arguments: [everythingStdio])
  func testPrompts(_ transport: MCPTransport) async throws {
    let host = MCPHost()

    let connection = try await host.connect("test", transport: transport)

    await connection.refreshPrompts()

    let simplePrompt = try await connection.getPrompt("simple_prompt")
    #expect(simplePrompt.messages.count > 0)

    let complexPrompt = try await connection.getPrompt(
      "complex_prompt",
      arguments: ["temperature": "1"]
    )
    #expect(complexPrompt.messages.count > 0)

    print(complexPrompt)
    print(simplePrompt)
  }

  @Test("Host handles feature notifications")
  func testFeatureNotifications() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingStdio)

    // Initial refresh
    await connection.refreshAll()
    let initialTools = connection.tools

    // Simulate tool list change notification
    try await connection.client.emit(ToolListChangedNotification())
    try await Task.sleep(for: .seconds(1))

    // Connection state should be updated
    #expect(connection.tools.count >= initialTools.count)

    // Similar tests for resources and prompts
    let initialResources = connection.resources
    try await connection.client.emit(ResourceListChangedNotification())
    try await Task.sleep(for: .seconds(1))
    #expect(connection.resources.count >= initialResources.count)
  }

  @Test("Host manages progress updates")
  func testProgressHandling() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingStdio)

    await connection.refreshTools()

    // Using actor to safely track progress updates
    actor ProgressTracker {
      var updates: [(Double, Double?)] = []

      func addUpdate(progress: Double, total: Double?) {
        updates.append((progress, total))
      }

      func getUpdates() -> [(Double, Double?)] {
        return updates
      }
    }

    let tracker = ProgressTracker()

    // Long running operation with progress
    _ = try await connection.callTool(
      "longRunningOperation",
      arguments: ["duration": 2, "steps": 4],
      progress: { progress, total in
        Task {
          await tracker.addUpdate(progress: progress, total: total)
        }
      }
    )

    try await Task.sleep(for: .seconds(3))
    let progressUpdates = await tracker.getUpdates()

    #expect(!progressUpdates.isEmpty)
    #expect(progressUpdates.count >= 4)
  }
}
