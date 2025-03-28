import Foundation

/// Audio provided to or from an LLM
public struct AudioContent: BinaryContent {
  /// The base64-encoded audio data
  public let data: String

  /// The MIME type of the audio. Different providers may support different audio types.
  public let mimeType: String

  public let type = ContentType.audio
  public let annotations: Annotations?

  public init(data: String, mimeType: String, annotations: Annotations? = nil) {
    self.data = data
    self.mimeType = mimeType
    self.annotations = annotations
  }
}
