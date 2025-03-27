import Foundation
import JSONSchema
import Testing

@testable import SwiftMCP

@Suite("Tools Tests")
struct ToolsTests {
    @Test("MCPTool Model")
    func testToolModel() async throws {
        let schemaString = """
            {
              "type": "object",
              "properties": {
                "message": {
                  "type": "string"
                }
              },
              "required": ["message"]
            }
            """
        let schema = try Schema(instance: schemaString)
        let tool = MCPTool(
            name: "test",
            description: "A test tool",
            inputSchema: schema
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(MCPTool.self, from: encoded)

        #expect(decoded.name == "test")
        #expect(decoded.description == "A test tool")

        // Verify schema validation works
        let validInstance = """
            {
              "message": "Hello"
            }
            """
        let invalidInstance = """
            {
              "message": 123
            }
            """
        let validResult = try decoded.inputSchema.validate(instance: validInstance)
        let invalidResult = try decoded.inputSchema.validate(instance: invalidInstance)

        #expect(validResult.isValid)
        #expect(!invalidResult.isValid)
    }

    @Test("Tool Content Types")
    func testToolContent() async throws {
        // Test text content
        let text = TextContent(text: "Hello", annotations: nil)
        let textContent = ToolContent.text(text)
        let encodedText = try JSONEncoder().encode(textContent)
        let decodedText = try JSONDecoder().decode(ToolContent.self, from: encodedText)
        if case .text(let content) = decodedText {
            #expect(content.text == "Hello")
            #expect(content.type == .text)
        } else {
            Issue.record("Expected text content")
        }

        // Test image content
        let image = ImageContent(data: "base64", mimeType: "image/png", annotations: nil)
        let imageContent = ToolContent.image(image)
        let encodedImage = try JSONEncoder().encode(imageContent)
        let decodedImage = try JSONDecoder().decode(ToolContent.self, from: encodedImage)
        if case .image(let content) = decodedImage {
            #expect(content.data == "base64")
            #expect(content.mimeType == "image/png")
            #expect(content.type == .image)
        } else {
            Issue.record("Expected image content")
        }

        // Test resource content
        let resource = TextResourceContents(
            text: "Resource text",
            uri: "file://test.txt",
            mimeType: "text/plain"
        )
        let embedded = EmbeddedResourceContent(resource: .text(resource))
        let resourceContent = ToolContent.resource(embedded)
        let encodedResource = try JSONEncoder().encode(resourceContent)
        let decodedResource = try JSONDecoder().decode(ToolContent.self, from: encodedResource)
        if case .resource(let content) = decodedResource {
            #expect(content.type == .resource)
            if case .text(let textResource) = content.resource {
                #expect(textResource.text == "Resource text")
                #expect(textResource.uri == "file://test.txt")
                #expect(textResource.mimeType == "text/plain")
            } else {
                Issue.record("Expected text resource")
            }
        } else {
            Issue.record("Expected resource content")
        }
    }

    @Test("Call Tool Protocol")
    func testCallTool() async throws {
        // Test request via JSON-RPC
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

        // Test request via direct model
        let request = CallToolRequest(
            name: "echo",
            arguments: ["message": "Hello, World!"]
        )
        let encodedRequest = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(CallToolRequest.self, from: encodedRequest)
        #expect(decodedRequest.params.name == "echo")
        #expect(decodedRequest.params.arguments["message"]?.value as? String == "Hello, World!")

        // Test response via JSON-RPC
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

        let resultMessage = try decoder.decode(
            JSONRPCMessage.self, from: callToolResultJSON)

        guard case .response(_, let result) = resultMessage else {
            Issue.record("Expected a response message")
            return
        }

        let jsonData = try JSONEncoder().encode(result)
        let resp = try JSONDecoder().decode(CallToolResult.self, from: jsonData)

        #expect(resp.isError == false)
        #expect(resp.content.count == 1)
        if case let .text(textContent) = resp.content.first! {
            #expect(textContent.text.contains("New York"))
        } else {
            Issue.record("Expected text content in the tool result")
        }

        // Test response via direct model
        let response = CallToolResult(
            content: [.text(TextContent(text: "Echo: Hello, World!"))],
            isError: false,
            _meta: nil
        )
        let encodedResponse = try JSONEncoder().encode(response)
        let decodedResponse = try JSONDecoder().decode(CallToolResult.self, from: encodedResponse)
        #expect(decodedResponse.isError == false)
        #expect(decodedResponse.content.count == 1)
        if case .text(let content) = decodedResponse.content[0] {
            #expect(content.text == "Echo: Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("List Tools Protocol")
    func testListTools() async throws {
        // Test request
        let request = ListToolsRequest(cursor: "page1")
        let encodedRequest = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(ListToolsRequest.self, from: encodedRequest)
        #expect(decodedRequest.params.cursor == "page1")

        // Test response
        let schemaString = """
            {
              "type": "object",
              "properties": {
                "message": {
                  "type": "string"
                }
              },
              "required": ["message"]
            }
            """
        let schema = try Schema(instance: schemaString)
        let tool = MCPTool(
            name: "test",
            description: "A test tool",
            inputSchema: schema
        )
        let response = ListToolsResult(
            _meta: nil,
            tools: [tool],
            nextCursor: "page2"
        )
        let encodedResponse = try JSONEncoder().encode(response)
        let decodedResponse = try JSONDecoder().decode(ListToolsResult.self, from: encodedResponse)
        #expect(decodedResponse.tools.count == 1)
        #expect(decodedResponse.tools[0].name == "test")
        #expect(decodedResponse.nextCursor == "page2")
    }
}
