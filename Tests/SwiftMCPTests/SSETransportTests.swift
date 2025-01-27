//
//  SSETransportTests.swift
//  SwiftMCP
//
//  Created by Noah Lozevski on 1/14/25.
//

import Foundation
import Testing
@testable import SwiftMCP

@Suite("SSEClientTransport Tests", .serialized)
struct SSEClientTransportTests {

    /// ../../../
    private var repoRootPath: URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// <REPO>/JS/sse.js
    private var sseScriptPath: String {
        let scriptURL = repoRootPath.appendingPathComponent("JS/sse.js")
        return scriptURL.path
    }

    /// Must match the setup from JS
    private let sseServerEndpoint = URL(string: "http://127.0.0.1:3000/sse")!

    private func spawnSSEServer() -> StdioTransport {
        StdioTransport(
            options: .init(
                command: "node",
                arguments: [sseScriptPath],
                environment: ProcessInfo.processInfo.environment
            )
        )
    }

    @Test("Connects to dummy SSE server, receives endpoint event, sets postEndpoint")
    func testConnectionAndEndpoint() async throws {
        let server = spawnSSEServer()

        let serverLogsTask = Task {
            for try await line in await server.messages() {
                print("Server Log:", String(data: line, encoding: .utf8) ?? "<nil>")
            }
        }

        try await server.start()
        // wait a sec
        try await Task.sleep(for: .milliseconds(500))

        let sseTransport = SSEClientTransport(
          sseURL: sseServerEndpoint,
            configuration: .default
        )

        var receivedMessages = [Data]()
        let messagesTask = Task {
            for try await msg in await sseTransport.messages() {
                receivedMessages.append(msg)
            }
        }

        try await Task.sleep(for: .seconds(1))

        // We expect the SSE server to send an "endpoint" event with data: <postURL>.
        // SSEClientTransport should set `postEndpoint` from that event.
      let postEndpoint = await sseTransport.postURL
        #expect(postEndpoint != nil)  // We should have discovered the endpoint
        #expect(await sseTransport.state == .connected)

        // 🧹💨💨
        await sseTransport.stop()
        await server.stop()
        try await messagesTask.value
        serverLogsTask.cancel()
    }

    @Test("Sends data to SSE server; receives no immediate errors")
    func testDataTransfer() async throws {
        let server = spawnSSEServer()
        let serverLogsTask = Task {
            for try await line in await server.messages() {
                print("Server Log:", String(data: line, encoding: .utf8) ?? "<nil>")
            }
        }

        try await server.start()
        try await Task.sleep(for: .milliseconds(500))

        let sseTransport = SSEClientTransport(sseURL: sseServerEndpoint)

        let messagesTask = Task {
            for try await _ in await sseTransport.messages() { }
        }

        // Wait for the "endpoint" event to set postEndpoint
        try await Task.sleep(for: .seconds(1))
      let postURL = await sseTransport.postURL
        #expect(postURL != nil)

        let testMessage = Data(#"{"hello":"world"}"#.utf8)
        do {
            try await sseTransport.send(testMessage)
            // we dont care what was returned just that the fact that it succeeded
        } catch {
            Issue.record("Sending data threw an error: \(error)")
        }

        await sseTransport.stop()
        await server.stop()
        try await messagesTask.value
        serverLogsTask.cancel()
    }

    @Test("Handles server close/disconnect gracefully")
    func testServerDisconnection() async throws {
        let server = spawnSSEServer()
        try await server.start()
        try await Task.sleep(for: .milliseconds(300))

        let sseTransport = SSEClientTransport(sseURL: sseServerEndpoint)
        let messagesTask = Task {
            for try await _ in await sseTransport.messages() { }
        }

        try await Task.sleep(for: .milliseconds(500))
        #expect(await sseTransport.state == .connected)

        // STOP 🛑
        await server.stop()

        // hold-up
        try await Task.sleep(for: .seconds(1))

        #expect(true, "No crash or exception means success.")

        await sseTransport.stop()
        try await messagesTask.value
    }

    @Test("Can reconnect after stopping SSEClientTransport")
    func testReconnection() async throws {
        let server = spawnSSEServer()
        try await server.start()
        try await Task.sleep(for: .milliseconds(300))

        let sseTransport = SSEClientTransport(sseURL: sseServerEndpoint)

        let firstSessionTask = Task {
            for try await _ in await sseTransport.messages() {}
        }

        try await Task.sleep(for: .milliseconds(500))
        #expect(await sseTransport.state == .connected)

        await sseTransport.stop()
        #expect(await sseTransport.state == .disconnected)

        let secondSessionTask = Task {
            for try await _ in await sseTransport.messages() {}
        }

        try await Task.sleep(for: .milliseconds(500))
        #expect(await sseTransport.state == .connected)

        // Cleanup
        await sseTransport.stop()
        await server.stop()
        try await firstSessionTask.value
        try await secondSessionTask.value
    }

    @Test("Handles server changing the post endpoint mid-connection")
    func testEndpointChangeEvent() async throws {
        let server = spawnSSEServer()
        try await server.start()
        try await Task.sleep(for: .milliseconds(300))

        let sseTransport = SSEClientTransport(sseURL: sseServerEndpoint)
        let messagesTask = Task {
            for try await _ in await sseTransport.messages() {}
        }

        try await Task.sleep(for: .seconds(1))
        let firstEndpoint = await sseTransport.postURL
        #expect(firstEndpoint != nil, "First endpoint is set")

        do {
            // trigger endpoint change
            try await sseTransport.send(Data(#"client::changeEndpoint"#.utf8))
        } catch { }

        try await Task.sleep(for: .seconds(3))
        let secondEndpoint = await sseTransport.postURL
        #expect(secondEndpoint != nil, "Second endpoint is set or remains unchanged")
        #expect(firstEndpoint != secondEndpoint, "Endpoints are the same. they should have updated.")

        // Cleanup
        await sseTransport.stop()
        await server.stop()
        try await messagesTask.value
    }

    @Test("Handles error response from the server for data send")
    func testDataSendError() async throws {
        let server = spawnSSEServer()
        try await server.start()
        try await Task.sleep(for: .milliseconds(300))

        let sseTransport = SSEClientTransport(sseURL: sseServerEndpoint)
        let messagesTask = Task {
            for try await _ in await sseTransport.messages() {}
        }

        try await Task.sleep(for: .seconds(1))
        let postURL = await sseTransport.postURL
        #expect(postURL != nil)

        // trigger 5XX on post
        let badData = Data(#"client::badMessage"#.utf8)
        do {
            try await sseTransport.send(badData)
            Issue.record("Expected an error but got none")
        } catch {
            #expect(true)
        }

        await sseTransport.stop()
        await server.stop()
        try await messagesTask.value
    }

    @Test("Handles forced server close/disconnect gracefully")
    func testServerDisconnect() async throws {
        let server = spawnSSEServer()
        let serverLogsTask = Task {
            for try await line in await server.messages() {
                print("Server Log:", String(data: line, encoding: .utf8) ?? "<nil>")
            }
        }

        try await server.start()
        try await Task.sleep(for: .milliseconds(300))

        let sseTransport = SSEClientTransport(sseURL: sseServerEndpoint)
        let messagesTask = Task {
            for try await line in await sseTransport.messages() {
                print("Server Log:", String(data: line, encoding: .utf8) ?? "<nil>")
            }
        }

        try await Task.sleep(for: .seconds(1))
      let postURL = await sseTransport.postURL
        #expect(postURL != nil)

        let disconnectMsg = Data(#"client::disconnect"#.utf8)
        try? await sseTransport.send(disconnectMsg)

        do {
            try await messagesTask.value
            #expect(true, "server disconnect should not throw")
            #expect(await sseTransport.state == .disconnected)
        } catch {
            Issue.record("server side initiated disconnect should not throw, it should be handled the same as client initiated disconnect")
        }

        await sseTransport.stop()
        await server.stop()
        serverLogsTask.cancel()
    }
}
