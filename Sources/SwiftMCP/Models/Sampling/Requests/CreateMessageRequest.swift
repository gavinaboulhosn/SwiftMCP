import Foundation

/// A request from the server to sample an LLM via the client. The client has full discretion
/// over which model to select. The client should also inform the user before beginning sampling,
/// to allow them to inspect the request (human in the loop) and decide whether to approve it.
public struct CreateMessageRequest: MCPRequest {
    // MARK: Lifecycle

    public init(
        maxTokens: Int,
        messages: [SamplingMessage],
        includeContext: String? = nil,
        metadata: [String: AnyCodable]? = nil,
        modelPreferences: ModelPreferences? = nil,
        stopSequences: [String]? = nil,
        systemPrompt: String? = nil,
        temperature: Double? = nil
    ) {
        params = Params(
            includeContext: includeContext,
            maxTokens: maxTokens,
            messages: messages,
            metadata: metadata,
            modelPreferences: modelPreferences,
            stopSequences: stopSequences,
            systemPrompt: systemPrompt,
            temperature: temperature
        )
    }

    // MARK: Public

    public typealias Response = CreateMessageResult

    public struct Params: MCPRequestParams {
        public var _meta: RequestMeta?
        /// A request to include context from one or more MCP servers (including the caller),
        /// to be attached to the prompt. The client MAY ignore this request.
        public let includeContext: String?
        /// The maximum number of tokens to sample, as requested by the server.
        /// The client MAY choose to sample fewer tokens than requested.
        public let maxTokens: Int
        /// The messages to be processed by the LLM
        public let messages: [SamplingMessage]
        /// Optional metadata to pass through to the LLM provider.
        /// The format of this metadata is provider-specific.
        public let metadata: [String: AnyCodable]?
        /// The server's preferences for which model to select.
        /// The client MAY ignore these preferences.
        public let modelPreferences: ModelPreferences?
        /// Optional stop sequences for the LLM to use
        public let stopSequences: [String]?
        /// An optional system prompt the server wants to use for sampling.
        /// The client MAY modify or omit this prompt.
        public let systemPrompt: String?
        /// Optional temperature parameter for sampling
        public let temperature: Double?

        public init(
            _meta: RequestMeta? = nil,
            includeContext: String? = nil,
            maxTokens: Int,
            messages: [SamplingMessage],
            metadata: [String: AnyCodable]? = nil,
            modelPreferences: ModelPreferences? = nil,
            stopSequences: [String]? = nil,
            systemPrompt: String? = nil,
            temperature: Double? = nil
        ) {
            self._meta = _meta
            self.includeContext = includeContext
            self.maxTokens = maxTokens
            self.messages = messages
            self.metadata = metadata
            self.modelPreferences = modelPreferences
            self.stopSequences = stopSequences
            self.systemPrompt = systemPrompt
            self.temperature = temperature
        }
    }

    public static let method = "sampling/createMessage"

    public var params: Params
}
