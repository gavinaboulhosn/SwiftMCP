import Foundation

/// An image provided to or from an LLM
public struct ImageContent: BinaryContent {
    /// The base64-encoded image data
    public let data: String

    /// The MIME type of the image. Different providers may support different image types.
    public let mimeType: String

    public let type: ContentType = .image
    public let annotations: Annotations?

    public init(data: String, mimeType: String, annotations: Annotations? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }
}
