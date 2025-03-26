import Foundation
import Testing

@testable import SwiftMCP

@Suite("Tools Serialization Tests")
struct ToolsTests {
    @Test("Decode Call Tool Request")
    func decodeCallToolRequest() throws {
        let callToolRequestJSON = """
            {
              "jsonrpc": "2.0",
              "id": 21,
              "method": "tools/call",
              "params": {
                "name": "get_weather",
                "arguments": {
                  "location": "New York"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self, from: callToolRequestJSON)

        guard case .request(_, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        let params = req.params as! CallToolRequest.Params
        #expect(params.name == "get_weather")
        #expect((params.arguments["location"]?.value as? String) == "New York")
    }

    @Test("Decode Call Tool Result")
    func decodeCallToolResult() throws {
        let callToolResultJSON = """
            {
              "jsonrpc": "2.0",
              "id": 21,
              "result": {
                "content": [
                  {
                    "type": "text",
                    "text": "Current weather in New York: 75°F, partly cloudy"
                  }
                ],
                "isError": false
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self, from: callToolResultJSON)

        guard case .response(_, let result) = message else {
            Issue.record("Expected a response message")
            return
        }

        // Convert the AnyCodable response to JSON data and then decode
        let jsonData = try JSONEncoder().encode(result)
        let resp = try JSONDecoder().decode(CallToolResult.self, from: jsonData)

        #expect(resp.isError == false)
        #expect(resp.content.count == 1)
        if case let .text(textContent) = resp.content.first! {
            #expect(textContent.text.contains("New York"))
        } else {
            Issue.record("Expected text content in the tool result")
        }
    }
}

