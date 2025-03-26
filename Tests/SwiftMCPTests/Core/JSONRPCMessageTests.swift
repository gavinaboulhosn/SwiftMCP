import Foundation
import Testing

@testable import SwiftMCP

@Suite("JSONRPC Message Serialization Tests")
struct JSONRPCMessageTests {

    @Test("Decode Initialize Request")
    func decodeInitializeRequest() throws {
        let initializeRequestJSON = """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "method": "initialize",
              "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                  "roots": {
                    "listChanged": true
                  },
                  "sampling": {},
                  "experimental": {
                    "featureX": {
                      "enabled": true
                    }
                  }
                },
                "clientInfo": {
                  "name": "ExampleClient",
                  "version": "1.0.0"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self, from: initializeRequestJSON)

        guard case .request(let id, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        #expect(id == .int(1))
        #expect(type(of: req).method == "initialize")

        let params = req.params as! InitializeRequest.Params
        #expect(params.protocolVersion == "2024-11-05")
        #expect(params.clientInfo.name == "ExampleClient")
        #expect(params.clientInfo.version == "1.0.0")
        #expect(params.capabilities.roots?.listChanged == true)
    }

    @Test("Decode Initialize Response")
    func decodeInitializeResponse() throws {
        let initializeResponseJSON = """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                  "logging": {},
                  "prompts": {
                    "listChanged": true
                  },
                  "resources": {
                    "subscribe": true,
                    "listChanged": true
                  },
                  "tools": {
                    "listChanged": true
                  }
                },
                "serverInfo": {
                  "name": "ExampleServer",
                  "version": "2.3.1"
                },
                "instructions": "Use this server to access code prompts and resources.",
                "_meta": {
                  "sessionId": "abc123"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self, from: initializeResponseJSON)

        guard case .response(let id, let result) = message else {
            Issue.record("Expected a response message")
            return
        }

        #expect(id == .int(1))

        // Convert the AnyCodable response to JSON data and then decode to InitializeResult
        let jsonData = try JSONEncoder().encode(result)
        let resp = try JSONDecoder().decode(InitializeResult.self, from: jsonData)

        #expect(resp.protocolVersion == "2024-11-05")
        #expect(resp.serverInfo.name == "ExampleServer")
        #expect(resp.serverInfo.version == "2.3.1")
        #expect(resp.instructions == "Use this server to access code prompts and resources.")

        let capabilities = resp.capabilities
        #expect(capabilities.tools?.listChanged == true)
    }
}

