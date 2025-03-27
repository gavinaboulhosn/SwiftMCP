import Foundation
import Testing

@testable import SwiftMCP

@Suite("Sampling Model Tests")
struct SamplingTests {
    @Test("ModelHint Encoding/Decoding")
    func testModelHint() throws {
        // Test encoding
        let hint = ModelHint(name: "claude-3-5-sonnet")
        let encoder = JSONEncoder()
        let data = try encoder.encode(hint)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ModelHint.self, from: data)
        #expect(decoded.name == "claude-3-5-sonnet")

        // Test optional name
        let emptyHint = ModelHint(name: nil)
        let emptyData = try encoder.encode(emptyHint)
        let emptyDecoded = try decoder.decode(ModelHint.self, from: emptyData)
        #expect(emptyDecoded.name == nil)
    }

    @Test("ModelPreferences Encoding/Decoding")
    func testModelPreferences() throws {
        let prefs = ModelPreferences(
            costPriority: 0.8,
            hints: [ModelHint(name: "claude-3")],
            intelligencePriority: 0.6,
            speedPriority: 0.4
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(prefs)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ModelPreferences.self, from: data)

        #expect(decoded.costPriority == 0.8)
        #expect(decoded.hints?.first?.name == "claude-3")
        #expect(decoded.intelligencePriority == 0.6)
        #expect(decoded.speedPriority == 0.4)
    }

    @Test("SamplingMessage Content Types")
    func testSamplingMessage() throws {
        // Test image content
        let imageContent = ImageContent(
            data: "base64data",
            mimeType: "image/png"
        )
        let imageMessage = SamplingMessage(role: Role.assistant, content: .image(imageContent))

        let encoder = JSONEncoder()
        let imageData = try encoder.encode(imageMessage)
        let decoder = JSONDecoder()
        let decodedImage = try decoder.decode(SamplingMessage.self, from: imageData)

        if case .image(let content) = decodedImage.content {
            #expect(content.mimeType == "image/png")
            #expect(content.type == .image)
            #expect(content.data == "base64data")
        } else {
            Issue.record("Expected image content")
        }
        #expect(decodedImage.role == Role.assistant)

        // Test audio content
        let audioContent = AudioContent(
            data: "base64audio",
            mimeType: "audio/wav"
        )
        let audioMessage = SamplingMessage(role: Role.assistant, content: .audio(audioContent))

        let audioData = try encoder.encode(audioMessage)
        let decodedAudio = try decoder.decode(SamplingMessage.self, from: audioData)

        if case .audio(let content) = decodedAudio.content {
            #expect(content.mimeType == "audio/wav")
            #expect(content.type == .audio)
            #expect(content.data == "base64audio")
        } else {
            Issue.record("Expected audio content")
        }
        #expect(decodedAudio.role == Role.assistant)
    }

    @Test("CreateMessageRequest Encoding/Decoding")
    func testCreateMessageRequest() throws {
        let textContent = TextContent(text: "Test prompt")
        let message = SamplingMessage(role: Role.user, content: .text(textContent))

        let request = CreateMessageRequest(
            maxTokens: 100,
            messages: [message],
            includeContext: "thisServer",
            metadata: ["key": AnyCodable("value")],
            modelPreferences: ModelPreferences(
                costPriority: 0.5,
                hints: [ModelHint(name: "claude")],
                intelligencePriority: 0.7,
                speedPriority: 0.3
            ),
            stopSequences: ["END"],
            systemPrompt: "You are a helpful assistant",
            temperature: 0.7
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CreateMessageRequest.self, from: data)

        // Verify required fields
        #expect(decoded.params.maxTokens == 100)
        #expect(decoded.params.messages.count == 1)

        if case .text(let content) = decoded.params.messages[0].content {
            #expect(content.text == "Test prompt")
        } else {
            Issue.record("Expected text content in message")
        }

        // Verify optional fields
        #expect(decoded.params.includeContext == "thisServer")
        #expect(decoded.params.stopSequences == ["END"])
        #expect(decoded.params.systemPrompt == "You are a helpful assistant")
        #expect(decoded.params.temperature == 0.7)

        let prefs = decoded.params.modelPreferences
        #expect(prefs?.costPriority == 0.5)
        #expect(prefs?.hints?.first?.name == "claude")
        #expect(prefs?.intelligencePriority == 0.7)
        #expect(prefs?.speedPriority == 0.3)
    }

    @Test("CreateMessageResult Encoding/Decoding")
    func testCreateMessageResult() throws {
        let textContent = TextContent(text: "Generated response")
        let result = CreateMessageResult(
            _meta: ["key": AnyCodable("value")],
            content: .text(textContent),
            model: "claude-3-sonnet-20240229",
            role: Role.assistant,
            stopReason: "length"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CreateMessageResult.self, from: data)

        if case .text(let content) = decoded.content {
            #expect(content.text == "Generated response")
            #expect(content.type == .text)
        } else {
            Issue.record("Expected text content")
        }

        #expect(decoded.model == "claude-3-sonnet-20240229")
        #expect(decoded.role == Role.assistant)
        #expect(decoded.stopReason == "length")

        if let metaValue = decoded._meta?["key"] {
            #expect(metaValue.value as? String == "value")
        } else {
            Issue.record("Expected metadata")
        }
    }
}
