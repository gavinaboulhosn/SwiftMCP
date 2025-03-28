import Foundation

// MARK: - TextContent

/// Text provided to or from an LLM
public struct TextContent: MCPContent {
  public let text: String
  public let type = ContentType.text
  public let annotations: Annotations?

  public init(text: String, annotations: Annotations? = nil) {
    self.text = text
    self.annotations = annotations
  }
}

// MARK: - TextResourceContents

/// Text with associated resource information
public struct TextResourceContents: MCPContent {
  public let text: String
  public let uri: String
  public let mimeType: String?
  public let type = ContentType.text
  public let annotations: Annotations?

  public init(text: String, uri: String, mimeType: String? = nil, annotations: Annotations? = nil) {
    self.text = text
    self.uri = uri
    self.mimeType = mimeType
    self.annotations = annotations
  }
}
