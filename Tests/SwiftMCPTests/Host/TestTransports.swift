import Foundation

@testable import SwiftMCP

/// Factory for creating test transports connected to the everything server
enum TestTransports {
    /// Standard stdio transport to everything server
    static var stdio: MCPTransport {
        StdioTransport(
            command: "npx",
            arguments: ["-y", "@modelcontextprotocol/server-everything"]
        )
    }

    /// SSE transport to everything server via supergateway
    static func sse(port: Int = 8000) async throws -> (MCPTransport, Process) {
        // Start supergateway process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "npx", "-y", "supergateway",
            "--stdio", "npx -y @modelcontextprotocol/server-everything",
            "--port", String(port),
        ]

        // Capture output for debugging
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        try await Task.sleep(for: .seconds(2))  // Wait for server

        let transport = SSEClientTransport(
            sseURL: URL(string: "http://localhost:\(port)/sse")!
        )

        return (transport, process)
    }

    // TODO: Add WebSocket transport when implemented
    // static func ws() async throws -> (MCPTransport, Process) { ... }

    // TODO: Add StreamableHTTP transport when implemented
    // static func http() async throws -> (MCPTransport, Process) { ... }
}

/// Helper for running tests with a supergateway-based transport
extension TestTransports {
    static func withSupergateway(
        _ block: @escaping (MCPTransport) async throws -> Void
    ) async throws {
        let (transport, process) = try await sse()

        try await block(transport)
        process.terminate()
        try await Task.sleep(for: .seconds(1))
    }
}
