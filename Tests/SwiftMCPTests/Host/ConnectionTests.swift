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

private var smitheryWebsocket: MCPTransport {
  // Create a WebSocketTransportConfiguration with the URL
  let websocketURL = URL(
    string:
      "wss://app-dd803694-33d0-4d8d-a220-61bf21ca0b27-5u5fdnfupa-uc.a.run.app/ws?config=e30%3D")!
  if let config = try? WebSocketTransportConfiguration(endpointURL: websocketURL) {
    return WebSocketClientTransport(configuration: config)
  } else {
    fatalError("Failed to create WebSocketTransportConfiguration")
  }
}

@Suite("Connection Management Tests")
struct ConnectionTests {
  var configuration = MCPConfiguration(
    roots: .list([])
  )

  @Test("Host Connection", .serialized, arguments: [everythingStdio])
  func testHostConnection(_ transport: MCPTransport) async throws {
    let host = MCPHost(config: configuration)

    let connection = try await host.connect("memory", transport: transport)

    await connection.refreshAll()
    let tools = connection.tools

    #expect(tools.count > 0)

    try await host.disconnect(connection.id)
    try await Task.sleep(for: .milliseconds(500))

    let isConnected = connection.isConnected

    #expect(!isConnected)
  }

  @Test("Host manages connection state", .disabled("Fix connection status check (.connected)"))
  func testConnectionStateManagement() async throws {
    let host = MCPHost()

    // Initial state
    var connections = await host.allConnections()
    #expect(connections.isEmpty)

    // Connect
    let connection = try await host.connect("test", transport: everythingStdio)
    connections = await host.allConnections()
    #expect(connections.count == 1)
    #expect(connection.status == .connected)
    #expect(connection.isConnected)

    // Verify initial feature state
    #expect(connection.tools.isEmpty)
    #expect(connection.resources.isEmpty)
    #expect(connection.prompts.isEmpty)
    #expect(!connection.isRefreshingTools)
    #expect(!connection.isRefreshingResources)
    #expect(!connection.isRefreshingPrompts)

    // Refresh should populate features
    await connection.refreshAll()
    #expect(!connection.tools.isEmpty)
    #expect(!connection.resources.isEmpty)
    #expect(!connection.prompts.isEmpty)

    // Disconnect
    try await host.disconnect(connection.id)
    connections = await host.allConnections()
    #expect(connections.isEmpty)
    #expect(!connection.isConnected)
    #expect(connection.status == .disconnected)
  }

  @Test("Host handles connection errors", .disabled("Need to fix StdioTransport start()"))
  func testConnectionErrorHandling() async throws {
    let host = MCPHost()

    // Bad transport that will fail
    let badTransport = StdioTransport(
      command: "invalid-command",
      arguments: []
    )

    do {
      _ = try await host.connect("test", transport: badTransport)
      Issue.record("Expected connection to fail")
    } catch {
      #expect(true)
      let connections = await host.allConnections()
      #expect(connections.isEmpty)
    }

    // Test automatic state updates on connection failure
    let connection = try await host.connect("test", transport: everythingStdio)
    await connection.refreshAll()

    // Force connection failure
    await connection.client.stop()
    try await Task.sleep(for: .seconds(1))

    #expect(connection.status == .disconnected)
    #expect(!connection.isConnected)
    #expect((await host.failedConnections()).isEmpty)
  }

  @Test("Host monitors connection health")
  func testHealthMonitoring() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingStdio)

    // Initially active
    var inactive = await host.inactiveConnections(timeout: 60)
    #expect(inactive.isEmpty)

    // Force inactivity
    let oldActivity = connection.lastActivity
    try await Task.sleep(for: .seconds(2))

    inactive = await host.inactiveConnections(timeout: 1)
    #expect(!inactive.isEmpty)
    #expect(inactive.first?.lastActivity == oldActivity)

    // Activity updates on operations
    await connection.refreshTools()
    inactive = await host.inactiveConnections(timeout: 1)
    #expect(connection.lastActivity > oldActivity)
    #expect(inactive.isEmpty)
  }
}
