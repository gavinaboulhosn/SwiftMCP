import Foundation

/// The contents of a resource, embedded into a prompt or tool call result.
/// It is up to the client how best to render embedded resources for the benefit
/// of the LLM and/or the user.
public struct EmbeddedResourceContent: MCPContent {
    public let type: ContentType = .resource
    public let annotations: Annotations?
    public let resource: ResourceContentVariant

    public init(resource: ResourceContentVariant, annotations: Annotations? = nil) {
        self.resource = resource
        self.annotations = annotations
    }
}
