import Foundation
import Testing

@testable import SwiftMCP

@Suite("Resources Serialization Tests")
struct ResourcesTests {
    @Test("Decode List Resources Request")
    func decodeListResourcesRequest() throws {
        let listResourcesRequestJSON = """
            {
              "jsonrpc": "2.0",
              "id": 30,
              "method": "resources/list",
              "params": {
                "cursor": "page1"
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self,
            from: listResourcesRequestJSON)

        guard case .request(_, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        let params = req.params as? ListResourcesRequest.Params
        if let params = params {
            #expect(params.cursor == "page1")
        } else {
            Issue.record("params is nil, expected a cursor")
        }
    }

    @Test("Decode List Resources Response")
    func decodeListResourcesResponse() throws {
        let listResourcesResponseJSON = """
            {
              "jsonrpc": "2.0",
              "id": 30,
              "result": {
                "resources": [
                  {
                    "uri": "file:///project/src/main.rs",
                    "name": "main.rs",
                    "description": "Rust main file",
                    "mimeType": "text/x-rust"
                  }
                ],
                "nextCursor": "page2",
                "_meta": {
                  "count": "1"
                }
              }
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let message = try decoder.decode(
            JSONRPCMessage.self,
            from: listResourcesResponseJSON)

        guard case .response(_, let result) = message else {
            Issue.record("Expected a response message")
            return
        }

        // Convert the AnyCodable response to JSON data and then decode
        let jsonData = try JSONEncoder().encode(result)
        let resp = try JSONDecoder().decode(ListResourcesResult.self, from: jsonData)

        #expect(resp.resources.count == 1)
        let resource = resp.resources.first!
        #expect(resource.uri == "file:///project/src/main.rs")
        #expect(resource.name == "main.rs")
        #expect(resp.nextCursor == "page2")
    }

    @Test("Decode Resource Contents Variant")
    func decodeResourceContentsVariant() throws {
        let textContentJSON = """
            {
              "text": "Hello, World!",
              "uri": "file:///path/to/file.txt",
              "mimeType": "text/plain",
              "type": "text",
              "annotations": null
            }
            """.data(using: .utf8)!

        let blobContentJSON = """
            {
              "blob": "SGVsbG8sIFdvcmxkIQ==",
              "uri": "file:///path/to/file",
              "mimeType": "application/octet-stream",
              "type": "resource",
              "annotations": null
            }
            """.data(using: .utf8)!

        let decoder = JSONDecoder()

        // Test text content
        let textVariant = try decoder.decode(ResourceContentsVariant.self, from: textContentJSON)
        if case .text(let textContent) = textVariant {
            #expect(textContent.text == "Hello, World!")
            #expect(textContent.uri == "file:///path/to/file.txt")
            #expect(textContent.mimeType == "text/plain")
            #expect(textContent.type == .text)
        } else {
            Issue.record("Expected text content")
        }

        // Test blob content
        let blobVariant = try decoder.decode(ResourceContentsVariant.self, from: blobContentJSON)
        if case .blob(let blobContent) = blobVariant {
            #expect(blobContent.blob == "SGVsbG8sIFdvcmxkIQ==")
            #expect(blobContent.uri == "file:///path/to/file")
            #expect(blobContent.type == .resource)
            #expect(blobContent.mimeType == "application/octet-stream")
        } else {
            Issue.record("Expected blob content")
        }
    }
}
