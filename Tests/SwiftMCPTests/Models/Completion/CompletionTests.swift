import Foundation
import Testing

@testable import SwiftMCP

@Suite("Completion Tests")
struct CompletionTests {
    @Test("CompletionReference Encoding/Decoding")
    func testCompletionReferenceCoding() throws {
        // Test prompt reference
        let promptRef = CompletionReference.prompt(PromptRef(name: "test-prompt"))
        let encoder = JSONEncoder()
        let promptEncoded = try encoder.encode(promptRef)
        let promptDecoded = try JSONDecoder().decode(CompletionReference.self, from: promptEncoded)

        if case .prompt(let decodedPromptRef) = promptDecoded {
            #expect(decodedPromptRef.name == "test-prompt")
            #expect(decodedPromptRef.type == "ref/prompt")
        } else {
            Issue.record("Expected prompt reference")
        }

        // Test resource reference
        let resourceRef = CompletionReference.resource(ResourceRef(uri: "file:///test"))
        let resourceEncoded = try encoder.encode(resourceRef)
        let resourceDecoded = try JSONDecoder().decode(CompletionReference.self, from: resourceEncoded)

        if case .resource(let decodedResourceRef) = resourceDecoded {
            #expect(decodedResourceRef.uri == "file:///test")
            #expect(decodedResourceRef.type == "ref/resource")
        } else {
            Issue.record("Expected resource reference")
        }
    }

    @Test("CompleteRequest Encoding/Decoding")
    func testCompleteRequest() throws {
        let expectedJSON = """
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "completion/complete",
          "params": {
            "argument": {
              "name": "test",
              "value": "value"
            },
            "ref": {
              "name": "test-prompt",
              "type": "ref/prompt"
            }
          }
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(JSONRPCMessage.self, from: expectedJSON)
        guard case .request(let id, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        #expect(id == .int(1))

        let params = req.params as? CompleteRequest.Params
        if let params = params {
            #expect(params.argument.name == "test")
            #expect(params.argument.value == "value")
            if case .prompt(let promptRef) = params.ref {
                #expect(promptRef.name == "test-prompt")
            } else {
                Issue.record("Expected prompt reference in params")
            }
        } else {
            Issue.record("params is nil, expected completion parameters")
        }

        // Test encoding
        let request = CompleteRequest(
            argument: CompletionArgument(name: "test", value: "value"),
            ref: CompletionReference.prompt(PromptRef(name: "test-prompt"))
        )
        let encoded = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(CompleteRequest.self, from: encoded)
        #expect(decodedRequest.params.argument.name == "test")
        #expect(decodedRequest.params.argument.value == "value")
        if case .prompt(let promptRef) = decodedRequest.params.ref {
            #expect(promptRef.name == "test-prompt")
        } else {
            Issue.record("Expected prompt reference in decoded request")
        }
    }

    @Test("CompleteResult Encoding/Decoding")
    func testCompleteResult() throws {
        let completionResult = CompletionResult(
            values: ["result1", "result2"],
            hasMore: true,
            total: 5
        )

        let result = CompleteResult(
            completion: completionResult,
            meta: ["key": AnyCodable("value")]
        )

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(result)
        let decoded = try JSONDecoder().decode(CompleteResult.self, from: encoded)

        #expect(decoded.completion.values == ["result1", "result2"])
        #expect(decoded.completion.hasMore == true)
        #expect(decoded.completion.total == 5)
        #expect((decoded._meta?["key"]?.value as? String) == "value")
    }

    @Test("Invalid Reference Type")
    func testInvalidReferenceType() throws {
        let invalidJSON = """
        {
          "type": "ref/invalid",
          "name": "test"
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(CompletionReference.self, from: invalidJSON)
            Issue.record("Expected decoding to fail for invalid reference type")
        } catch {
            // Expected error
        }
    }
}
