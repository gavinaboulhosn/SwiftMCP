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

@Suite("Host Capability Tests")
struct CapabilityTests {
  @Test("Host aggregates tools across connections")
  func testToolAggregation() async throws {
    let host = MCPHost()

    // Connect multiple servers
    let conn1 = try await host.connect("test1", transport: everythingStdio)
    let conn2 = try await host.connect("test2", transport: memoryTransport)

    // Refresh both connections
    Task {
      await conn1.refreshAll()
    }

    Task {
      await conn2.refreshAll()
    }

    // Wait for refreshes to complete
    try await Task.sleep(for: .seconds(2))

    // Should aggregate all unique tools
    var allTools = await host.availableTools()
    #expect(allTools.count > 0)
    #expect(allTools.count >= conn1.tools.count)
    #expect(allTools.count >= conn2.tools.count)

    // Tool list should update when connections refresh
    let initialCount = allTools.count
    await conn1.refreshTools()
    allTools = await host.availableTools()
    #expect(allTools.count >= initialCount)
  }

  @Test("Host handles client capability checks")
  func testCapabilityChecks() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingStdio)

    // Verify capability inference
    let toolConns = await host.connections(supporting: .tools)
    #expect(!toolConns.isEmpty)
    #expect(toolConns.contains(connection))

    let resourceConns = await host.connections(supporting: .resources)
    #expect(!resourceConns.isEmpty)
    #expect(resourceConns.contains(connection))

    // Connection API should respect capabilities
    await connection.refreshAll()
    #expect(connection.capabilities.supports(.tools))
    #expect(!connection.tools.isEmpty)

    // Test capability changes
    let noCapConn = ConnectionState(
      id: "test2",
      client: connection.client,
      serverInfo: connection.serverInfo,
      capabilities: .init()
    )

    await noCapConn.refreshTools()
    #expect(noCapConn.tools.isEmpty)
  }
}
