import Foundation

enum RequestFactory {
  // We'll handle all client and server requests defined:
  // ClientRequests:
  // initialize, ping, prompts/list, prompts/get, resources/list, resources/read,
  // resources/templates/list, tools/list, tools/call, logging/setLevel,
  // completion/complete, prompts/list, prompts/get, etc.
  // server requests:
  // roots/list, sampling/createMessage

  static func makeRequest(
    method: String,
    params: [String: AnyCodable]?)
    -> (any MCPRequest)?
  {
    switch method {
    case InitializeRequest.method:
      if let params = decodeParams(InitializeRequest.Params.self, from: params) {
        return InitializeRequest(params: params)
      }

    case PingRequest.method:
      return PingRequest()

    case ListPromptsRequest.method:
      if let params = decodeParams(ListPromptsRequest.Params.self, from: params) {
        return ListPromptsRequest(cursor: params.cursor)
      } else {
        return ListPromptsRequest()
      }

    case GetPromptRequest.method:
      if let params = decodeParams(GetPromptRequest.Params.self, from: params) {
        return GetPromptRequest(name: params.name, arguments: params.arguments)
      }

    case ListResourcesRequest.method:
      if let params = decodeParams(ListResourcesRequest.Params.self, from: params) {
        return ListResourcesRequest(cursor: params.cursor)
      } else {
        return ListResourcesRequest()
      }

    case ReadResourceRequest.method:
      if let params = decodeParams(ReadResourceRequest.Params.self, from: params) {
        return ReadResourceRequest(uri: params.uri)
      }

    case ListResourceTemplatesRequest.method:
      if let params = decodeParams(ListResourceTemplatesRequest.Params.self, from: params) {
        return ListResourceTemplatesRequest(cursor: params.cursor)
      } else {
        return ListResourceTemplatesRequest()
      }

    case SubscribeRequest.method:
      if let params = decodeParams(SubscribeRequest.Params.self, from: params) {
        return SubscribeRequest(uri: params.uri)
      }

    case UnsubscribeRequest.method:
      if let params = decodeParams(UnsubscribeRequest.Params.self, from: params) {
        return UnsubscribeRequest(uri: params.uri)
      }

    case ListToolsRequest.method:
      if let params = decodeParams(ListToolsRequest.Params.self, from: params) {
        return ListToolsRequest(cursor: params.cursor)
      } else {
        return ListToolsRequest()
      }

    case CallToolRequest.method:
      if let params = decodeParams(CallToolRequest.Params.self, from: params) {
        return CallToolRequest(name: params.name, arguments: params.arguments)
      }

    case SetLevelRequest.method:
      if let params = decodeParams(SetLevelRequest.Params.self, from: params) {
        return SetLevelRequest(level: params.level)
      }

    case CompleteRequest.method:
      if let params = decodeParams(CompleteRequest.Params.self, from: params) {
        return CompleteRequest(argument: params.argument, ref: params.ref)
      }

    case CreateMessageRequest.method:
      if let params = decodeParams(CreateMessageRequest.Params.self, from: params) {
        return CreateMessageRequest(
          maxTokens: params.maxTokens, messages: params.messages,
          includeContext: params.includeContext,
          metadata: params.metadata, modelPreferences: params.modelPreferences,
          stopSequences: params.stopSequences,
          systemPrompt: params.systemPrompt, temperature: params.temperature)
      }

    case ListRootsRequest.method:
      // no required params
      return ListRootsRequest()

    default:
      return nil
    }
    return nil
  }
}
