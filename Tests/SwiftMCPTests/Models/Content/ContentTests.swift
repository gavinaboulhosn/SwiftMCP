import Foundation
import Testing
@testable import SwiftMCP

@Suite("Content Model Tests")
struct ContentTests {
    @Test("Content Types")
    func testContentTypes() async throws {
        // Test basic content types
        let text = TextContent(text: "Hello", annotations: nil)
        #expect(text.type == .text)
        #expect(text.text == "Hello")
        #expect(text.annotations == nil)

        let image = ImageContent(data: "base64", mimeType: "image/png", annotations: nil)
        #expect(image.type == .image)
        #expect(image.data == "base64")
        #expect(image.mimeType == "image/png")
        #expect(image.annotations == nil)

        let audio = AudioContent(data: "base64", mimeType: "audio/mp3", annotations: nil)
        #expect(audio.type == .audio)
        #expect(audio.data == "base64")
        #expect(audio.mimeType == "audio/mp3")
        #expect(audio.annotations == nil)

        // Test resource content
        let textResource = TextResourceContents(
            text: "Resource text",
            uri: "file://test.txt",
            mimeType: "text/plain",
            annotations: nil
        )
        #expect(textResource.type == .text)
        #expect(textResource.text == "Resource text")
        #expect(textResource.uri == "file://test.txt")
        #expect(textResource.mimeType == "text/plain")
        #expect(textResource.annotations == nil)

        let blobResource = BlobResourceContents(
            blob: "base64",
            uri: "file://test.bin",
            mimeType: "application/octet-stream",
            annotations: nil
        )
        #expect(blobResource.type == .resource)
        #expect(blobResource.blob == "base64")
        #expect(blobResource.uri == "file://test.bin")
        #expect(blobResource.mimeType == "application/octet-stream")
        #expect(blobResource.annotations == nil)

        // Test embedded resource
        let embedded = EmbeddedResourceContent(
            resource: .text(textResource),
            annotations: nil
        )
        #expect(embedded.type == .resource)
        #expect(embedded.annotations == nil)

        if case .text(let content) = embedded.resource {
            #expect(content.text == "Resource text")
            #expect(content.uri == "file://test.txt")
        } else {
            Issue.record("Expected text resource")
        }
    }

    @Test("Content Metadata")
    func testContentMetadata() async throws {
        let annotations = Annotations(
            audience: [.user],
            priority: 1.0
        )

        let text = TextContent(
            text: "Hello",
            annotations: annotations
        )

        #expect(text.annotations?.audience == [.user])
        #expect(text.annotations?.priority == 1.0)
    }

    @Test("Content Coding")
    func testContentCoding() async throws {
        let text = TextContent(
            text: "Hello",
            annotations: Annotations(audience: [.user], priority: 1.0)
        )

        let encoded = try JSONEncoder().encode(text)
        let decoded = try JSONDecoder().decode(TextContent.self, from: encoded)

        #expect(text.text == decoded.text)
        #expect(text.type == decoded.type)
        #expect(text.annotations?.audience == decoded.annotations?.audience)
        #expect(text.annotations?.priority == decoded.annotations?.priority)
    }
}
