import Foundation
@testable import SwiftMCP

final class PromptsTests {
  func testMCPPromptCoding() async throws {
    let prompt = MCPPrompt(
      name: "test-prompt",
      description: "A test prompt",
      arguments: [
        PromptArgument(
          name: "arg1",
          description: "First argument",
          required: true
        ),
        PromptArgument(
          name: "arg2",
          description: "Second argument",
          required: false
        )
      ]
    )

    let encoded = try JSONEncoder().encode(prompt)
    let decoded = try JSONDecoder().decode(MCPPrompt.self, from: encoded)

    assert(decoded.name == prompt.name)
    assert(decoded.description == prompt.description)
    assert(decoded.arguments?.count == prompt.arguments?.count)
    assert(decoded.arguments?[0].name == prompt.arguments?[0].name)
    assert(decoded.arguments?[0].description == prompt.arguments?[0].description)
    assert(decoded.arguments?[0].required == prompt.arguments?[0].required)
  }

  func testPromptMessageCoding() async throws {
    let textMessage = PromptMessage(
      role: .assistant,
      content: .text(TextContent(text: "Hello"))
    )

    let imageMessage = PromptMessage(
      role: .user,
      content: .image(ImageContent(data: "base64", mimeType: "image/png"))
    )

    let resourceMessage = PromptMessage(
      role: .assistant,
      content: .resource(EmbeddedResourceContent(
        resource: .text(TextResourceContents(text: "content", uri: "test://uri"))
      ))
    )

    // Test text message
    let encodedText = try JSONEncoder().encode(textMessage)
    let decodedText = try JSONDecoder().decode(PromptMessage.self, from: encodedText)
    if case .text(let content) = decodedText.content {
      assert(content.text == "Hello")
      assert(content.type == .text)
    } else {
      assertionFailure("Expected text content")
    }
    assert(decodedText.role == .assistant)

    // Test image message
    let encodedImage = try JSONEncoder().encode(imageMessage)
    let decodedImage = try JSONDecoder().decode(PromptMessage.self, from: encodedImage)
    if case .image(let content) = decodedImage.content {
      assert(content.data == "base64")
      assert(content.mimeType == "image/png")
      assert(content.type == .image)
    } else {
      assertionFailure("Expected image content")
    }
    assert(decodedImage.role == .user)

    // Test resource message
    let encodedResource = try JSONEncoder().encode(resourceMessage)
    let decodedResource = try JSONDecoder().decode(PromptMessage.self, from: encodedResource)
    if case .resource(let content) = decodedResource.content {
      assert(content.type == .resource)
      if case .text(let textResource) = content.resource {
        assert(textResource.text == "content")
        assert(textResource.uri == "test://uri")
      } else {
        assertionFailure("Expected text resource content")
      }
    } else {
      assertionFailure("Expected resource content")
    }
    assert(decodedResource.role == .assistant)
  }

  func testListPromptsRequestCoding() async throws {
    let request = ListPromptsRequest(cursor: "test-cursor")
    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(ListPromptsRequest.self, from: encoded)

    assert(decoded.params.cursor == request.params.cursor)
  }

  func testListPromptsResultCoding() async throws {
    let result = ListPromptsResult(
      prompts: [
        MCPPrompt(name: "prompt1", description: "First prompt"),
        MCPPrompt(name: "prompt2", description: "Second prompt")
      ],
      nextCursor: "next-cursor",
      metadata: ["key": "value"].mapValues(AnyCodable.init)
    )

    let encoded = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(ListPromptsResult.self, from: encoded)

    assert(decoded.prompts.count == result.prompts.count)
    assert(decoded.prompts[0].name == result.prompts[0].name)
    assert(decoded.prompts[0].description == result.prompts[0].description)
    assert(decoded.nextCursor == result.nextCursor)
    assert(decoded._meta?["key"]?.value as? String == "value")
  }

  func testGetPromptRequestCoding() async throws {
    let request = GetPromptRequest(
      name: "test-prompt",
      arguments: ["arg1": "value1", "arg2": "value2"]
    )

    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(GetPromptRequest.self, from: encoded)

    assert(decoded.params.name == request.params.name)
    assert(decoded.params.arguments?["arg1"] == request.params.arguments?["arg1"])
    assert(decoded.params.arguments?["arg2"] == request.params.arguments?["arg2"])
  }

  func testGetPromptResultCoding() async throws {
    let result = GetPromptResult(
      description: "Test prompt",
      messages: [
        PromptMessage(
          role: .assistant,
          content: .text(TextContent(text: "Hello"))
        ),
        PromptMessage(
          role: .user,
          content: .text(TextContent(text: "Hi"))
        )
      ],
      metadata: ["key": "value"].mapValues(AnyCodable.init)
    )

    let encoded = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(GetPromptResult.self, from: encoded)

    assert(decoded.description == result.description)
    assert(decoded.messages.count == result.messages.count)
    assert(decoded._meta?["key"]?.value as? String == "value")

    if case .text(let content) = decoded.messages[0].content {
      assert(content.text == "Hello")
      assert(content.type == .text)
    } else {
      assertionFailure("Expected text content")
    }
    assert(decoded.messages[0].role == .assistant)

    if case .text(let content) = decoded.messages[1].content {
      assert(content.text == "Hi")
      assert(content.type == .text)
    } else {
      assertionFailure("Expected text content")
    }
    assert(decoded.messages[1].role == .user)
  }
}
