import Foundation

/// A binary resource with associated metadata
public struct BlobResourceContents: MCPContent {
    public let blob: String
    public let uri: String
    public let mimeType: String?
    public let type: ContentType = .resource
    public let annotations: Annotations?

    public init(blob: String, uri: String, mimeType: String? = nil, annotations: Annotations? = nil) {
        self.blob = blob
        self.uri = uri
        self.mimeType = mimeType
        self.annotations = annotations
    }
}
