import Foundation

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct OpenRouterProvider: AIProvider {
    public enum Compatibility: String, Sendable {
        case strict
        case compatible
    }
    
    public struct ReasoningOptions: Sendable {
        public enum Effort: String, Sendable {
            case high
            case medium
            case low
        }
        
        public let enabled: Bool?
        public let exclude: Bool?
        public let maxTokens: Int?
        public let effort: Effort?
        
        public init(enabled: Bool? = nil, exclude: Bool? = nil, maxTokens: Int? = nil, effort: Effort? = nil) {
            self.enabled = enabled
            self.exclude = exclude
            self.maxTokens = maxTokens
            self.effort = effort
        }
    }
    
    public struct UsageOptions: Sendable {
        public let include: Bool
        
        public init(include: Bool) {
            self.include = include
        }
    }
    
    // MARK: - Public metadata
    
    public let name = "OpenRouter"
    public let supportedGenerationModes: Set<GenerationMode> = [.auto, .json, .tool]
    public let defaultGenerationMode: GenerationMode = .json
    
    // MARK: - Private configuration
    
    private let apiKey: String
    private let baseURL: String
    private let compatibility: Compatibility
    private let customHeaders: [String: String]
    private let defaultModels: [String]?
    private let defaultReasoning: JSONValue?
    private let defaultUsage: UsageOptions?
    private let defaultIncludeReasoning: Bool?
    private let defaultUser: String?
    private let extraBody: [String: JSONValue]
    private let completionModelIds: Set<String>
    private let structuredOutputs: Bool?
    private let urlSession: URLSession
    private let debugLogging: Bool
    
    // MARK: - Initialization
    
    public init(
        apiKey: String,
        baseURL: String = "https://openrouter.ai/api/v1",
        compatibility: Compatibility = .compatible,
        headers: [String: String] = [:],
        defaultModels: [String]? = nil,
        defaultReasoning: ReasoningOptions? = nil,
        defaultUsage: UsageOptions? = nil,
        defaultIncludeReasoning: Bool? = nil,
        defaultUser: String? = nil,
        extraBody: [String: JSONValue] = [:],
        completionModelIds: Set<String> = ["openai/gpt-3.5-turbo-instruct"],
        structuredOutputs: Bool? = nil,
        urlSession: URLSession = .shared,
        debugLogging: Bool = false
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.compatibility = compatibility
        self.customHeaders = headers
        self.defaultModels = defaultModels
        self.defaultReasoning = defaultReasoning.flatMap { OpenRouterProvider.encodeReasoningOptions($0) }
        self.defaultUsage = defaultUsage
        self.defaultIncludeReasoning = defaultIncludeReasoning
        self.defaultUser = defaultUser
        self.extraBody = extraBody
        self.completionModelIds = completionModelIds
        self.structuredOutputs = structuredOutputs
        self.urlSession = urlSession
        self.debugLogging = debugLogging
    }

    private func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
        guard debugLogging else { return }
        print("[OpenRouter] \(message())")
#endif
    }
    
    // MARK: - AIProvider
    
    public func languageModel(_ modelId: String) -> LanguageModel {
        LanguageModel(provider: self, modelId: modelId)
    }
    
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        let options = try extractRequestOptions(configuration: request.configuration)
        let endpoint = endpoint(for: request.modelId, options: options)
        
        switch endpoint {
        case .chat:
            return try await performChatCompletion(request: request, options: options)
        case .completion:
            return try await performTextCompletion(request: request, options: options)
        }
    }
    
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let options = try extractRequestOptions(configuration: request.configuration)
                    let endpoint = endpoint(for: request.modelId, options: options)
                    guard endpoint == .chat else {
                        throw AIProviderError.unsupportedParameter("streaming", "Streaming is only supported for chat models in OpenRouter")
                    }
                    try await streamChatCompletion(request: request, options: options, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        if let temperature = configuration.temperature, (temperature < 0.0 || temperature > 2.0) {
            throw AIProviderError.unsupportedParameter("temperature", "Must be between 0.0 and 2.0")
        }
        
        if let maxTokens = configuration.maxTokens, maxTokens < 1 {
            throw AIProviderError.unsupportedParameter("maxTokens", "Must be greater than 0")
        }
        
        if let topP = configuration.topP, (topP < 0.0 || topP > 1.0) {
            throw AIProviderError.unsupportedParameter("topP", "Must be between 0.0 and 1.0")
        }
        
        if let topK = configuration.topK, topK < 0 {
            throw AIProviderError.unsupportedParameter("topK", "Must be greater or equal to 0")
        }
        
        if let frequencyPenalty = configuration.frequencyPenalty, (frequencyPenalty < -2.0 || frequencyPenalty > 2.0) {
            throw AIProviderError.unsupportedParameter("frequencyPenalty", "Must be between -2.0 and 2.0")
        }
        
        if let presencePenalty = configuration.presencePenalty, (presencePenalty < -2.0 || presencePenalty > 2.0) {
            throw AIProviderError.unsupportedParameter("presencePenalty", "Must be between -2.0 and 2.0")
        }
    }
    
    // MARK: - Endpoint handling
    
    private enum Endpoint {
        case chat
        case completion
    }
    
    private func endpoint(for modelId: String, options: OpenRouterRequestOptions) -> Endpoint {
        if options.forceCompletionEndpoint {
            return .completion
        }
        if completionModelIds.contains(modelId) {
            return .completion
        }
        return .chat
    }
    
    // MARK: - Request execution
    
    private func performChatCompletion(
        request: ProviderRequest,
        options: OpenRouterRequestOptions
    ) async throws -> ProviderResponse {
        let payload = try buildChatPayload(request: request, options: options)
        let data = try encodeJSON(payload)
        if let jsonString = String(data: data, encoding: .utf8) {
            debugLog("Request Payload: \(jsonString)")
        }
        let urlRequest = try buildURLRequest(path: "/chat/completions", body: data, accept: "application/json")
        let (responseData, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse("Invalid response type")
        }
        debugLog("Chat completion response status: \(httpResponse.statusCode)")
        guard httpResponse.statusCode == 200 else {
            throw try parseError(from: responseData, statusCode: httpResponse.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chatResponse = try decoder.decode(OpenRouterChatResponse.self, from: responseData)
        return try convertChatResponse(chatResponse, request: request)
    }
    
    private func performTextCompletion(
        request: ProviderRequest,
        options: OpenRouterRequestOptions
    ) async throws -> ProviderResponse {
        switch request.mode {
        case .regular(let tools, _):
            if let tools = tools, !tools.isEmpty {
                throw AIProviderError.unsupportedParameter("tools", "Tools are not supported for OpenRouter completion models")
            }
        case .objectJSON:
            throw AIProviderError.unsupportedParameter("responseFormat", "JSON schema generation is not supported for completion models")
        case .objectTool:
            throw AIProviderError.unsupportedParameter("responseFormat", "Tool forcing is not supported for completion models")
        }
        let payload = try buildCompletionPayload(request: request, options: options)
        let data = try encodeJSON(payload)
        let urlRequest = try buildURLRequest(path: "/completions", body: data, accept: "application/json")
        let (responseData, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse("Invalid response type")
        }
        guard httpResponse.statusCode == 200 else {
            throw try parseError(from: responseData, statusCode: httpResponse.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let completionResponse = try decoder.decode(OpenRouterCompletionResponse.self, from: responseData)
        return try convertCompletionResponse(completionResponse)
    }
    
    private func streamChatCompletion(
        request: ProviderRequest,
        options: OpenRouterRequestOptions,
        continuation: AsyncThrowingStream<ProviderChunk, Error>.Continuation
    ) async throws {
        var payload = try buildChatPayload(request: request, options: options)
        payload["stream"] = .bool(true)
        if compatibility == .strict {
            let includeUsage = options.usageInclude ?? defaultUsage?.include ?? true
            payload["stream_options"] = .object([
                "include_usage": .bool(includeUsage)
            ])
        }
        let data = try encodeJSON(payload)
        if let jsonString = String(data: data, encoding: .utf8) {
            debugLog("Streaming Request Payload: \(jsonString)")
        }
        var urlRequest = try buildURLRequest(path: "/chat/completions", body: data, accept: "text/event-stream")
        urlRequest.timeoutInterval = 60 * 5
        let (bytes, response) = try await urlSession.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse("Invalid response type")
        }
        debugLog("Streaming HTTP status: \(httpResponse.statusCode)")
        guard httpResponse.statusCode == 200 else {
            let collected = try await collectBody(from: bytes)
            throw try parseError(from: collected, statusCode: httpResponse.statusCode)
        }
        var accumulator = StreamingAccumulator()
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                debugLog("Streaming chunk: \(payload.prefix(200))")
                if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                    if let finalChunk = accumulator.finalize() {
                        continuation.yield(finalChunk)
                    }
                    debugLog("Received [DONE] sentinel")
                    break
                }
                guard let jsonData = payload.data(using: .utf8) else { continue }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                do {
                    let event = try decoder.decode(OpenRouterStreamEnvelope.self, from: jsonData)
                    let chunks = try accumulator.process(event: event)
                    for chunk in chunks {
                        continuation.yield(chunk)
                    }
                } catch {
                    // Ignore malformed chunk but keep streaming
                    debugLog("Failed to decode stream event: \(error.localizedDescription)")
                    continue
                }
            }
            continuation.finish()
            debugLog("Streaming finished successfully")
        } catch {
            debugLog("Streaming terminated with error: \(error)")
            continuation.finish(throwing: error)
        }
    }
    
    // MARK: - Helper: HTTP
    
    private func buildURLRequest(path: String, body: Data, accept: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw OpenRouterError.invalidRequest("Invalid base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let bodyString = String(data: body, encoding: .utf8) {
            debugLog("Prepared request to \(url.absoluteString) with Accept=\(accept), headers=\(customHeaders), body=\(bodyString)")
        }
        return request
    }

    private func parseError(from data: Data, statusCode: Int) throws -> Error {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let payload = String(data: data, encoding: .utf8) {
            debugLog("Parsing error response (status \(statusCode)): \(payload)")
        }
        if let errorResponse = try? decoder.decode(OpenRouterErrorResponse.self, from: data) {
            return AIProviderError.providerSpecific(errorResponse.error.message, underlyingError: nil)
        }
        if statusCode == 401 {
            return AIProviderError.authenticationFailed("Invalid OpenRouter API key")
        }
        if statusCode == 429 {
            return AIProviderError.rateLimitExceeded(retryAfter: nil)
        }
        return AIProviderError.providerSpecific("OpenRouter request failed with status code \(statusCode)", underlyingError: nil)
    }
    
    // MARK: - Payload construction
    
    private func buildChatPayload(
        request: ProviderRequest,
        options: OpenRouterRequestOptions
    ) throws -> [String: JSONValue] {
        var body: [String: JSONValue] = [:]
        body["model"] = .string(request.modelId)
        if let models = options.models ?? defaultModels {
            body["models"] = .array(models.map { .string($0) })
        }
        body["messages"] = .array(try convertMessages(request: request))
        body["temperature"] = request.configuration.temperature.map(JSONValue.double)
        body["max_tokens"] = request.configuration.maxTokens.map(JSONValue.int)
        body["top_p"] = request.configuration.topP.map(JSONValue.double)
        body["top_k"] = request.configuration.topK.map(JSONValue.int)
        body["frequency_penalty"] = request.configuration.frequencyPenalty.map(JSONValue.double)
        body["presence_penalty"] = request.configuration.presencePenalty.map(JSONValue.double)
        body["seed"] = request.configuration.seed.map(JSONValue.int)
        if let stop = request.configuration.stopSequences, !stop.isEmpty {
            body["stop"] = .array(stop.map { .string($0) })
        }
        if let logitBias = options.logitBias {
            body["logit_bias"] = .object(logitBias.mapValues { .double($0) })
        }
        if let logprobs = options.logprobs {
            switch logprobs {
            case .bool(let value):
                body["logprobs"] = .bool(value)
            case .top(let count):
                body["logprobs"] = .int(count)
                body["top_logprobs"] = .int(options.topLogprobs ?? count)
            }
        }
        if let parallel = options.parallelToolCalls {
            body["parallel_tool_calls"] = .bool(parallel)
        }
        if let user = options.user ?? defaultUser {
            body["user"] = .string(user)
        }
        if let includeReasoning = options.includeReasoning ?? defaultIncludeReasoning {
            body["include_reasoning"] = .bool(includeReasoning)
        }
        if let reasoning = options.reasoning ?? defaultReasoning {
            body["reasoning"] = reasoning
        }
        if let usageInclude = options.usageInclude ?? defaultUsage?.include {
            body["usage"] = .object(["include": .bool(usageInclude)])
        }
        if let plugins = options.plugins {
            body["plugins"] = .array(plugins)
        }
        if let webSearch = options.webSearchOptions {
            body["web_search_options"] = webSearch
        }
        if let providerRouting = options.providerRouting {
            body["provider"] = providerRouting
        }
        if let responseFormat = try buildResponseFormat(for: request) {
            body["response_format"] = responseFormat
        }
        if let tools = try buildTools(for: request) {
            body.merge(tools) { _, new in new }
        }
        body.merge(extraBody) { _, new in new }
        if let perRequestExtra = options.extraBody {
            body.merge(perRequestExtra) { _, new in new }
        }
        return body
    }
    
    private func buildCompletionPayload(
        request: ProviderRequest,
        options: OpenRouterRequestOptions
    ) throws -> [String: JSONValue] {
        let prompt = try convertCompletionPrompt(request: request)
        var body: [String: JSONValue] = [:]
        body["model"] = .string(request.modelId)
        if let models = options.models ?? defaultModels {
            body["models"] = .array(models.map { .string($0) })
        }
        body["prompt"] = .string(prompt)
        body["temperature"] = request.configuration.temperature.map(JSONValue.double)
        body["max_tokens"] = request.configuration.maxTokens.map(JSONValue.int)
        body["top_p"] = request.configuration.topP.map(JSONValue.double)
        body["top_k"] = request.configuration.topK.map(JSONValue.int)
        body["frequency_penalty"] = request.configuration.frequencyPenalty.map(JSONValue.double)
        body["presence_penalty"] = request.configuration.presencePenalty.map(JSONValue.double)
        body["seed"] = request.configuration.seed.map(JSONValue.int)
        if let stop = request.configuration.stopSequences, !stop.isEmpty {
            body["stop"] = .array(stop.map { .string($0) })
        }
        if let logitBias = options.logitBias {
            body["logit_bias"] = .object(logitBias.mapValues { .double($0) })
        }
        if let logprobs = options.logprobs {
            switch logprobs {
            case .bool(let value):
                body["logprobs"] = .bool(value)
            case .top(let count):
                body["logprobs"] = .int(count)
                body["top_logprobs"] = .int(options.topLogprobs ?? count)
            }
        }
        if let suffix = options.suffix {
            body["suffix"] = .string(suffix)
        }
        if let user = options.user ?? defaultUser {
            body["user"] = .string(user)
        }
        if let includeReasoning = options.includeReasoning ?? defaultIncludeReasoning {
            body["include_reasoning"] = .bool(includeReasoning)
        }
        if let reasoning = options.reasoning ?? defaultReasoning {
            body["reasoning"] = reasoning
        }
        if let usageInclude = options.usageInclude ?? defaultUsage?.include {
            body["usage"] = .object(["include": .bool(usageInclude)])
        }
        body.merge(extraBody) { _, new in new }
        if let perRequestExtra = options.extraBody {
            body.merge(perRequestExtra) { _, new in new }
        }
        return body
    }
    
    // MARK: - Message conversion
    
    private func convertMessages(request: ProviderRequest) throws -> [JSONValue] {
        var messages: [JSONValue] = []
        if let system = request.system {
            messages.append(.object([
                "role": .string("system"),
                "content": .string(system)
            ]))
        }
        for message in request.messages {
            switch message.role {
            case .system:
                messages.append(.object([
                    "role": .string("system"),
                    "content": .string(message.content.compactMap { $0.textValue }.joined(separator: "\n"))
                ]))
            case .user:
                messages.append(try convertUserMessage(message))
            case .assistant:
                messages.append(try convertAssistantMessage(message))
            case .tool:
                messages.append(try convertToolMessage(message))
            }
        }
        return messages
    }
    
    private func convertUserMessage(_ message: Message) throws -> JSONValue {
        let hasRichContent = message.content.contains { content in
            content.imageValue != nil || content.fileValue != nil
        }
        if !hasRichContent {
            let text = message.content.compactMap { $0.textValue }.joined(separator: "\n")
            return .object([
                "role": .string("user"),
                "content": .string(text)
            ])
        }
        var parts: [JSONValue] = []
        for content in message.content {
            switch content {
            case .text(let text):
                parts.append(.object([
                    "type": .string("text"),
                    "text": .string(text)
                ]))
            case .image(let image):
                guard let url = try encodeMediaContent(image.data, url: image.url, mimeType: image.mimeType) else { continue }
                parts.append(.object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string(url)])
                ]))
            case .file(let file):
                guard let fileData = try encodeMediaContent(file.data, url: file.url, mimeType: file.mimeType) else { continue }
                let filename = file.filename ?? "file"
                parts.append(.object([
                    "type": .string("file"),
                    "file": .object([
                        "filename": .string(filename),
                        "file_data": .string(fileData)
                    ])
                ]))
            case .toolCall:
                continue
            case .toolResult:
                continue
            case .reasoning,
                 .redactedReasoning,
                 .reasoningSignature,
                 .annotation:
                continue
            }
        }
        return .object([
            "role": .string("user"),
            "content": .array(parts)
        ])
    }
    
    private func convertAssistantMessage(_ message: Message) throws -> JSONValue {
        var text = message.content.compactMap { $0.textValue }.joined(separator: "\n")
        var serializedToolCalls: [JSONValue] = []
        let toolCallSource = message.toolCalls ?? message.content.compactMap { $0.toolCallValue }
        if !toolCallSource.isEmpty {
            serializedToolCalls = toolCallSource.enumerated().map { index, call in
                var functionPayload: [String: JSONValue] = [
                    "name": .string(call.function.name),
                    "arguments": .string(call.function.arguments.isEmpty ? "{}" : call.function.arguments)
                ]
                var toolPayload: [String: JSONValue] = [
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object(functionPayload)
                ]
                toolPayload["index"] = .int(index)
                return .object(toolPayload)
            }
        }
        if text.isEmpty && serializedToolCalls.isEmpty {
            text = ""
        }
        var payload: [String: JSONValue] = [
            "role": .string("assistant"),
            "content": .string(text)
        ]
        if !serializedToolCalls.isEmpty {
            payload["tool_calls"] = .array(serializedToolCalls)
        }
        return .object(payload)
    }
    
    private func convertToolMessage(_ message: Message) throws -> JSONValue {
        guard let toolResultContent = message.content.first?.toolResultValue else {
            return .object([
                "role": .string("tool"),
                "content": .string("")
            ])
        }
        let contentString: String
        switch toolResultContent.result {
        case .text(let text):
            contentString = text
        case .json(let data):
            contentString = String(data: data, encoding: .utf8) ?? ""
        case .error(let message):
            contentString = message
        case .image(let image):
            contentString = try encodeMediaContent(image.data, url: image.url, mimeType: image.mimeType) ?? ""
        case .file(let file):
            contentString = try encodeMediaContent(file.data, url: file.url, mimeType: file.mimeType) ?? ""
        case .data(let data, let mimeType):
            let base64 = data.base64EncodedString()
            contentString = "data:\(mimeType);base64,\(base64)"
        }
        return .object([
            "role": .string("tool"),
            "tool_call_id": .string(toolResultContent.toolCallId),
            "content": .string(contentString)
        ])
    }
    
    // MARK: - Builder helpers
    
    private func buildResponseFormat(for request: ProviderRequest) throws -> JSONValue? {
        let supportsStructured = supportsStructuredOutputs(for: request.modelId)
        switch request.mode {
        case .objectJSON(let schema, let name, let description):
            if supportsStructured {
                let dict = try convertJSONSchemaToDict(schema, strict: true)
                var schemaPayload: [String: JSONValue] = [
                    "name": .string(name ?? "response"),
                    "strict": .bool(true),
                    "schema": .object(dict.mapValues { JSONValue.any($0) })
                ]
                if let description = description {
                    schemaPayload["description"] = .string(description)
                }
                return .object([
                    "type": .string("json_schema"),
                    "json_schema": .object(schemaPayload)
                ])
            } else {
                return .object([
                    "type": .string("json_object")
                ])
            }
        case .objectTool:
            return nil
        case .regular:
            return nil
        }
    }
    
    private func buildTools(for request: ProviderRequest) throws -> [String: JSONValue]? {
        switch request.mode {
        case .regular(let tools, let choice):
            guard let tools = tools, !tools.isEmpty else { return nil }
            let mappedTools = try tools.map { tool -> JSONValue in
                let parameters = try convertJSONSchemaToDict(tool.function.parameters, strict: supportsStructuredOutputs(for: request.modelId))
                var functionPayload: [String: JSONValue?] = [
                    "name": .string(tool.function.name),
                    "description": tool.function.description.map(JSONValue.string),
                    "parameters": .object(parameters.mapValues { JSONValue.any($0) })
                ]
                if let strict = tool.function.strict {
                    functionPayload["strict"] = .bool(strict)
                } else {
                    functionPayload["strict"] = .bool(supportsStructuredOutputs(for: request.modelId))
                }
                return .object([
                    "type": .string("function"),
                    "function": .object(functionPayload.compactMapValues { $0 })
                ])
            }
            var payload: [String: JSONValue] = ["tools": .array(mappedTools)]
            if let choice = choice {
                payload["tool_choice"] = mapToolChoice(choice)
            }
            return payload
        case .objectTool(let tool):
            let parameters = try convertJSONSchemaToDict(tool.function.parameters, strict: supportsStructuredOutputs(for: request.modelId))
            var functionPayload: [String: JSONValue?] = [
                "name": .string(tool.function.name),
                "description": tool.function.description.map(JSONValue.string),
                "parameters": .object(parameters.mapValues { JSONValue.any($0) })
            ]
            if let strict = tool.function.strict {
                functionPayload["strict"] = .bool(strict)
            } else {
                functionPayload["strict"] = .bool(supportsStructuredOutputs(for: request.modelId))
            }
            let toolJson = JSONValue.object([
                "type": .string("function"),
                "function": .object(functionPayload.compactMapValues { $0 })
            ])
            return [
                "tools": .array([toolJson]),
                "tool_choice": .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.function.name)
                    ])
                ])
            ]
        case .objectJSON:
            return nil
        }
    }
    
    private func mapToolChoice(_ choice: ToolChoice) -> JSONValue {
        switch choice {
        case .auto:
            return .string("auto")
        case .none:
            return .string("none")
        case .required:
            return .string("required")
        case .specific(let name):
            return .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string(name)
                ])
            ])
        }
    }
    
    private func convertCompletionPrompt(request: ProviderRequest) throws -> String {
        // If there's only one user text message, use it directly
        if request.messages.count == 1,
           let message = request.messages.first,
           message.role == .user,
           message.content.count == 1,
           let text = message.content.first?.textValue {
            return text
        }
        var promptLines: [String] = []
        // Include system message at top if present
        if let system = request.system ?? request.messages.first(where: { $0.role == .system })?.content.first?.textValue {
            promptLines.append(system)
            promptLines.append("")
        }
        for message in request.messages {
            switch message.role {
            case .system:
                continue
            case .user:
                if message.content.contains(where: { $0.textValue == nil }) {
                    throw AIProviderError.unsupportedParameter("attachments", "File and image attachments are not supported for OpenRouter completion models")
                }
                let text = message.content.compactMap { $0.textValue }.joined(separator: "\n")
                promptLines.append("user:\n\(text)\n")
            case .assistant:
                if message.content.contains(where: { $0.textValue == nil }) {
                    throw AIProviderError.unsupportedParameter("attachments", "Assistant attachments are not supported for OpenRouter completion models")
                }
                let text = message.content.compactMap { $0.textValue }.joined(separator: "\n")
                promptLines.append("assistant:\n\(text)\n")
            case .tool:
                throw AIProviderError.unsupportedParameter("tool", "Tool messages are not supported for completion models")
            }
        }
        promptLines.append("assistant:\n")
        return promptLines.joined(separator: "\n")
    }
    
    // MARK: - Options parsing
    
    private func extractRequestOptions(configuration: ModelConfiguration) throws -> OpenRouterRequestOptions {
        var options = OpenRouterRequestOptions()
        guard let providerSpecific = configuration.providerSpecific else {
            return options
        }
        for (key, value) in providerSpecific {
            guard key.hasPrefix("openrouter") else { continue }
            switch key {
            case "openrouter.logit_bias":
                options.logitBias = try parseLogitBias(value)
            case "openrouter.logprobs":
                options.logprobs = parseLogprobs(value)
            case "openrouter.top_logprobs":
                options.topLogprobs = Int(value)
            case "openrouter.parallel_tool_calls":
                options.parallelToolCalls = parseBool(value)
            case "openrouter.user":
                options.user = value
            case "openrouter.models":
                options.models = try parseStringArray(value)
            case "openrouter.plugins":
                options.plugins = try parseJSONArray(value)
            case "openrouter.web_search_options":
                options.webSearchOptions = try parseJSONObject(value)
            case "openrouter.provider":
                options.providerRouting = try parseJSONObject(value)
            case "openrouter.reasoning":
                options.reasoning = try parseJSONObject(value)
            case "openrouter.include_reasoning":
                options.includeReasoning = parseBool(value)
            case "openrouter.usage.include":
                options.usageInclude = parseBool(value)
            case "openrouter.extra_body":
                options.extraBody = try parseJSONObject(value).objectValue
            case "openrouter.suffix":
                options.suffix = value
            case "openrouter.endpoint":
                if value == "completion" {
                    options.forceCompletionEndpoint = true
                }
            default:
                continue
            }
        }
        return options
    }
    
    // MARK: - Structured outputs heuristics
    
    private func supportsStructuredOutputs(for modelId: String) -> Bool {
        if let explicit = structuredOutputs {
            return explicit
        }
        if isReasoningModel(modelId: modelId) {
            return true
        }
        if isAudioModel(modelId: modelId) {
            return false
        }
        return supportsStructuredOutputsByDefault(modelId: modelId)
    }
    
    private func isReasoningModel(modelId: String) -> Bool {
        modelId.starts(with: "o")
    }
    
    private func isAudioModel(modelId: String) -> Bool {
        modelId.contains("audio")
    }
    
    private func supportsStructuredOutputsByDefault(modelId: String) -> Bool {
        modelId.hasPrefix("gpt-4o") ||
        modelId.hasPrefix("gpt-4.1") ||
        modelId.hasPrefix("gpt-4-turbo") ||
        modelId.hasPrefix("gpt-4-0125-preview") ||
        modelId.hasPrefix("gpt-4-1106-preview") ||
        modelId.hasPrefix("gpt-3.5-turbo-0125") ||
        modelId.hasPrefix("gpt-3.5-turbo-1106")
    }
    
    // MARK: - Conversion helpers
    
    private func encodeJSON(_ payload: [String: JSONValue]) throws -> Data {
        let jsonObject = payload.toJSONObject()
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw OpenRouterError.invalidRequest("Payload contains non-JSON encodable values")
        }
        return try JSONSerialization.data(withJSONObject: jsonObject, options: [])
    }
    
    private func encodeMediaContent(_ data: Data?, url: URL?, mimeType: String) throws -> String? {
        if let urlString = url?.absoluteString {
            return urlString
        }
        guard let data = data else { return nil }
        let base64 = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }
    
    private func convertChatResponse(_ response: OpenRouterChatResponse, request: ProviderRequest) throws -> ProviderResponse {
        guard let choice = response.choices.first else {
            throw OpenRouterError.invalidResponse("No choices in OpenRouter response")
        }
        let content = choice.message.content ?? ""
        let toolCalls = choice.message.toolCalls?.enumerated().map { index, call in
            ToolCall(
                id: call.id ?? UUID().uuidString,
                function: ToolCallFunction(
                    name: call.function.name,
                    arguments: call.function.arguments
                ),
                index: index
            )
        }
        let usage = Usage(
            promptTokens: response.usage?.promptTokens ?? 0,
            completionTokens: response.usage?.completionTokens ?? 0,
            totalTokens: response.usage?.totalTokens ?? (response.usage?.promptTokens ?? 0) + (response.usage?.completionTokens ?? 0),
            promptCost: nil,
            completionCost: nil,
            totalCost: response.usage?.cost,
            currency: "USD",
            details: response.usage?.detailsDictionary
        )
        let finishReason = mapOpenRouterFinishReason(choice.finishReason)
        var additionalOutputs: [String: String] = [:]
        if let reasoning = choice.message.reasoning, !reasoning.isEmpty {
            additionalOutputs["openrouter.reasoning"] = reasoning
        }
        if let details = choice.message.reasoningDetails, !details.isEmpty {
            let encoded = try JSONEncoder().encode(details)
            if let jsonString = String(data: encoded, encoding: .utf8) {
                additionalOutputs["openrouter.reasoning_details"] = jsonString
            }
        }
        if let annotations = choice.message.annotations, !annotations.isEmpty {
            let encoded = try JSONEncoder().encode(annotations)
            if let jsonString = String(data: encoded, encoding: .utf8) {
                additionalOutputs["openrouter.annotations"] = jsonString
            }
        }
        if additionalOutputs.isEmpty {
            additionalOutputs = [:]
        }
        var providerMetadata: [String: String] = [:]
        if let provider = response.provider {
            providerMetadata["provider"] = provider
        }
        if let model = response.model {
            providerMetadata["model"] = model
        }
        if let cost = response.usage?.cost {
            providerMetadata["usage.cost"] = String(cost)
        }
        return ProviderResponse(
            content: content,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            additionalOutputs: additionalOutputs.isEmpty ? nil : additionalOutputs,
            responseId: response.id,
            providerMetadata: providerMetadata.isEmpty ? nil : providerMetadata
        )
    }
    
    private func convertCompletionResponse(_ response: OpenRouterCompletionResponse) throws -> ProviderResponse {
        guard let choice = response.choices.first else {
            throw OpenRouterError.invalidResponse("No choices in completion response")
        }
        let usage = Usage(
            promptTokens: response.usage?.promptTokens ?? 0,
            completionTokens: response.usage?.completionTokens ?? 0,
            totalTokens: response.usage?.totalTokens ?? (response.usage?.promptTokens ?? 0) + (response.usage?.completionTokens ?? 0),
            promptCost: nil,
            completionCost: nil,
            totalCost: response.usage?.cost,
            currency: "USD",
            details: response.usage?.detailsDictionary
        )
        let finishReason = mapOpenRouterFinishReason(choice.finishReason)
        return ProviderResponse(
            content: choice.text ?? "",
            usage: usage,
            finishReason: finishReason,
            responseId: response.id,
            providerMetadata: response.model.map { ["model": $0] }
        )
    }
    
    // MARK: - Streaming accumulator
    
    private struct StreamingAccumulator {
        private var toolCalls: [Int: StreamingToolCall] = [:]
        private var accumulatedUsage: Usage?
        private var lastFinishReason: FinishReason?
        private var chunkIndex: Int = 0
        
        mutating func process(event: OpenRouterStreamEnvelope) throws -> [ProviderChunk] {
            if let error = event.error {
                throw AIProviderError.providerSpecific(error.message, underlyingError: nil)
            }
            var chunks: [ProviderChunk] = []
            if let usage = event.usage?.toUsage() {
                accumulatedUsage = usage
            }
            if let provider = event.provider {
                // Provider metadata event, emit chunk with metadata in additional outputs
                let chunk = ProviderChunk(
                    delta: "",
                    usage: nil,
                    additionalOutputs: ["openrouter.provider": provider],
                    chunkIndex: chunkIndex
                )
                chunkIndex += 1
                chunks.append(chunk)
            }
            guard let choices = event.choices else {
                return chunks
            }
            for choice in choices {
                if let finish = choice.finishReason {
                    lastFinishReason = mapOpenRouterFinishReason(finish)
                }
                if let delta = choice.delta {
                    chunks.append(contentsOf: processDelta(delta, index: choice.index ?? 0))
                }
            }
            return chunks
        }
        
        func finalize() -> ProviderChunk? {
            if accumulatedUsage == nil && lastFinishReason == nil {
                return nil
            }
            return ProviderChunk(
                delta: "",
                usage: accumulatedUsage,
                finishReason: lastFinishReason,
                chunkIndex: chunkIndex
            )
        }
        
        private mutating func processDelta(_ delta: OpenRouterStreamDelta, index: Int) -> [ProviderChunk] {
            var chunks: [ProviderChunk] = []
            if let text = delta.content, !text.isEmpty {
                let chunk = ProviderChunk(
                    delta: text,
                    chunkIndex: chunkIndex
                )
                chunkIndex += 1
                chunks.append(chunk)
            }
            if let reasoning = delta.reasoning, !reasoning.isEmpty {
                let chunk = ProviderChunk(
                    delta: "",
                    additionalOutputs: ["openrouter.reasoning_delta": reasoning],
                    chunkIndex: chunkIndex
                )
                chunkIndex += 1
                chunks.append(chunk)
            }
            if let images = delta.images, !images.isEmpty {
                if let data = try? JSONEncoder().encode(images), let jsonString = String(data: data, encoding: .utf8) {
                    let chunk = ProviderChunk(
                        delta: "",
                        additionalOutputs: ["openrouter.images": jsonString],
                        chunkIndex: chunkIndex
                    )
                    chunkIndex += 1
                    chunks.append(chunk)
                }
            }
            if let annotations = delta.annotations, !annotations.isEmpty {
                if let data = try? JSONEncoder().encode(annotations), let jsonString = String(data: data, encoding: .utf8) {
                    let chunk = ProviderChunk(
                        delta: "",
                        additionalOutputs: ["openrouter.annotations": jsonString],
                        chunkIndex: chunkIndex
                    )
                    chunkIndex += 1
                    chunks.append(chunk)
                }
            }
            if let toolCallDeltas = delta.toolCalls {
                for toolCallDelta in toolCallDeltas {
                    chunks.append(contentsOf: processToolCallDelta(toolCallDelta, index: index))
                }
            }
            return chunks
        }
        
        private mutating func processToolCallDelta(_ delta: OpenRouterStreamingToolCall, index: Int) -> [ProviderChunk] {
            var chunks: [ProviderChunk] = []
            let callIndex = delta.index ?? index
            if toolCalls[callIndex] == nil {
                let id = delta.id ?? UUID().uuidString
                let name = delta.function?.name ?? ""
                toolCalls[callIndex] = StreamingToolCall(id: id, name: name, arguments: "")
                let startChunk = ProviderChunk(
                    delta: "",
                    chunkIndex: chunkIndex,
                    toolCallStreamingStart: ProviderChunk.ToolCallStreamingStart(toolCallId: id, toolName: name)
                )
                chunkIndex += 1
                chunks.append(startChunk)
            }
            if let argumentsDelta = delta.function?.arguments {
                if var toolCall = toolCalls[callIndex] {
                    toolCall.arguments.append(argumentsDelta)
                    toolCalls[callIndex] = toolCall

                    let deltaChunk = ProviderChunk(
                        delta: "",
                        chunkIndex: chunkIndex,
                        toolCallDelta: ProviderChunk.ToolCallDelta(
                            toolCallId: toolCall.id,
                            toolName: toolCall.name,
                            argsTextDelta: argumentsDelta
                        )
                    )
                    chunkIndex += 1
                    chunks.append(deltaChunk)

                    if !toolCall.isFinished && isValidJSON(toolCall.arguments) {
                        let completed = ToolCall(
                            id: toolCall.id,
                            function: ToolCallFunction(name: toolCall.name, arguments: toolCall.arguments)
                        )
                        let toolCallChunk = ProviderChunk(
                            delta: "",
                            toolCall: completed,
                            chunkIndex: chunkIndex
                        )
                        chunkIndex += 1
                        chunks.append(toolCallChunk)
                        toolCall.isFinished = true
                        toolCalls[callIndex] = toolCall
                    }
                }
            }
            return chunks
        }
        
        private func isValidJSON(_ text: String) -> Bool {
            guard let data = text.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        }
    }
    
    private struct StreamingToolCall {
        let id: String
        let name: String
        var arguments: String
        var isFinished: Bool = false
    }
}

// MARK: - Supporting Types

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterRequestOptions: Sendable {
    var logitBias: [String: Double]? = nil
    var logprobs: Logprobs? = nil
    var topLogprobs: Int? = nil
    var parallelToolCalls: Bool? = nil
    var user: String? = nil
    var models: [String]? = nil
    var plugins: [JSONValue]? = nil
    var webSearchOptions: JSONValue? = nil
    var providerRouting: JSONValue? = nil
    var reasoning: JSONValue? = nil
    var includeReasoning: Bool? = nil
    var usageInclude: Bool? = nil
    var extraBody: [String: JSONValue]? = nil
    var suffix: String? = nil
    var forceCompletionEndpoint: Bool = false
    
    enum Logprobs: Sendable {
        case bool(Bool)
        case top(Int)
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            struct ToolCall: Codable {
                struct FunctionCall: Codable {
                    let name: String
                    let arguments: String
                }
                let id: String?
                let function: FunctionCall
            }
            struct Annotation: Codable {
                struct URLCitation: Codable {
                    let url: String
                    let title: String
                    let content: String?
                }
                let type: String
                let urlCitation: URLCitation?
            }
            struct ReasoningDetail: Codable {
                let type: String
                let text: String?
                let summary: String?
                let data: String?
            }
            let role: String
            let content: String?
            let reasoning: String?
            let reasoningDetails: [ReasoningDetail]?
            let toolCalls: [ToolCall]?
            let annotations: [Annotation]?
        }
        let message: Message
        let finishReason: String?
    }
    struct Usage: Decodable {
        struct PromptDetails: Decodable {
            let cachedTokens: Int?
        }
        struct CompletionDetails: Decodable {
            let reasoningTokens: Int?
        }
        struct CostDetails: Decodable {
            let upstreamInferenceCost: Double?
        }
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let cost: Double?
        let promptTokensDetails: PromptDetails?
        let completionTokensDetails: CompletionDetails?
        let costDetails: CostDetails?
        
        var detailsDictionary: [String: String]? {
            var dict: [String: String] = [:]
            if let cached = promptTokensDetails?.cachedTokens {
                dict["prompt.cached_tokens"] = String(cached)
            }
            if let reasoning = completionTokensDetails?.reasoningTokens {
                dict["completion.reasoning_tokens"] = String(reasoning)
            }
            if let upstream = costDetails?.upstreamInferenceCost {
                dict["cost.upstream_inference"] = String(upstream)
            }
            return dict.isEmpty ? nil : dict
        }
    }
    let id: String?
    let model: String?
    let provider: String?
    let choices: [Choice]
    let usage: Usage?
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterCompletionResponse: Decodable {
    struct Choice: Decodable {
        let text: String?
        let finishReason: String?
    }
    struct Usage: Decodable {
        struct PromptDetails: Decodable {
            let cachedTokens: Int?
        }
        struct CompletionDetails: Decodable {
            let reasoningTokens: Int?
        }
        struct CostDetails: Decodable {
            let upstreamInferenceCost: Double?
        }
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let cost: Double?
        let promptTokensDetails: PromptDetails?
        let completionTokensDetails: CompletionDetails?
        let costDetails: CostDetails?
        
        var detailsDictionary: [String: String]? {
            var dict: [String: String] = [:]
            if let cached = promptTokensDetails?.cachedTokens {
                dict["prompt.cached_tokens"] = String(cached)
            }
            if let reasoning = completionTokensDetails?.reasoningTokens {
                dict["completion.reasoning_tokens"] = String(reasoning)
            }
            if let upstream = costDetails?.upstreamInferenceCost {
                dict["cost.upstream_inference"] = String(upstream)
            }
            return dict.isEmpty ? nil : dict
        }
    }
    let id: String?
    let model: String?
    let choices: [Choice]
    let usage: Usage?
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterErrorResponse: Decodable {
    struct ErrorInfo: Decodable {
        let message: String
    }
    let error: ErrorInfo
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterStreamEnvelope: Decodable {
    struct Choice: Decodable {
        let index: Int?
        let delta: OpenRouterStreamDelta?
        let finishReason: String?
    }
    let id: String?
    let model: String?
    let provider: String?
    let usage: OpenRouterStreamUsage?
    let choices: [Choice]?
    let error: OpenRouterErrorResponse.ErrorInfo?
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterStreamUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let cost: Double?
    
    func toUsage() -> Usage {
        Usage(
            promptTokens: promptTokens ?? 0,
            completionTokens: completionTokens ?? 0,
            totalTokens: totalTokens ?? (promptTokens ?? 0) + (completionTokens ?? 0),
            promptCost: cost,
            completionCost: nil,
            totalCost: cost,
            currency: "USD"
        )
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterStreamDelta: Decodable {
    let role: String?
    let content: String?
    let reasoning: String?
    let reasoningDetails: [OpenRouterChatResponse.Choice.Message.ReasoningDetail]?
    let images: [OpenRouterImage]?
    let annotations: [OpenRouterChatResponse.Choice.Message.Annotation]?
    let toolCalls: [OpenRouterStreamingToolCall]?
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterImage: Codable {
    struct ImageURL: Codable {
        let url: String
    }
    let imageUrl: ImageURL
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private struct OpenRouterStreamingToolCall: Decodable {
    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }
    let index: Int?
    let id: String?
    let function: FunctionDelta?
}

// MARK: - JSONValue representation

public enum JSONValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    
    static func any(_ value: Any) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let dict as [String: Any]:
            return .object(dict.mapValues { JSONValue.any($0) })
        case let array as [Any]:
            return .array(array.map { JSONValue.any($0) })
        default:
            return .null
        }
    }
    
    func toJSONObject() -> Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value):
            if value.rounded() == value {
                return Int(value)
            }
            return value
        case .bool(let value): return value
        case .object(let dict): return dict.mapValues { $0.toJSONObject() }
        case .array(let array): return array.map { $0.toJSONObject() }
        case .null: return NSNull()
        }
    }
    
    var objectValue: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func toJSONObject() -> [String: Any] {
        mapValues { $0.toJSONObject() }
    }
}

// MARK: - Parsing helpers

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func parseBool(_ value: String) -> Bool? {
    if let bool = Bool(value.lowercased()) {
        return bool
    }
    if value == "1" { return true }
    if value == "0" { return false }
    return nil
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func parseLogitBias(_ value: String) throws -> [String: Double] {
    let json = try parseJSONObject(value)
    guard case .object(let dict) = json else {
        throw AIProviderError.providerSpecific("openrouter.logit_bias must be a JSON object", underlyingError: nil)
    }
    var result: [String: Double] = [:]
    for (key, value) in dict {
        switch value {
        case .double(let d): result[key] = d
        case .int(let i): result[key] = Double(i)
        case .string(let s):
            if let number = Double(s) {
                result[key] = number
            }
        default:
            continue
        }
    }
    return result
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func parseLogprobs(_ value: String) -> OpenRouterRequestOptions.Logprobs? {
    if let bool = parseBool(value) {
        return .bool(bool)
    }
    if let int = Int(value) {
        return .top(int)
    }
    return nil
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func parseStringArray(_ value: String) throws -> [String] {
    let json = try parseJSONObject(value)
    guard case .array(let array) = json else {
        throw AIProviderError.providerSpecific("Expected JSON array", underlyingError: nil)
    }
    return array.compactMap { element in
        if case .string(let string) = element {
            return string
        }
        return nil
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func parseJSONArray(_ value: String) throws -> [JSONValue] {
    let json = try parseJSONObject(value)
    guard case .array(let array) = json else {
        throw AIProviderError.providerSpecific("Expected JSON array", underlyingError: nil)
    }
    return array
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func parseJSONObject(_ value: String) throws -> JSONValue {
    guard let data = value.data(using: .utf8) else {
        throw AIProviderError.providerSpecific("Invalid UTF-8 string", underlyingError: nil)
    }
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    return JSONValue.any(object)
}

// MARK: - Schema conversion

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func convertJSONSchemaToDict(_ schema: JSONSchema, strict: Bool) throws -> [String: Any] {
    try convertSchemaDefinitionToDict(schema.definition, strict: strict)
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func convertSchemaDefinitionToDict(_ definition: SchemaDefinition, strict: Bool) throws -> [String: Any] {
    var dict: [String: Any] = [:]
    dict["type"] = definition.type.rawValue
    if let properties = definition.properties {
        var propertiesDict: [String: Any] = [:]
        for (key, schema) in properties {
            propertiesDict[key] = try convertJSONSchemaToDict(schema, strict: strict)
        }
        dict["properties"] = propertiesDict
        if strict && definition.type == .object {
            dict["required"] = Array(properties.keys)
        }
    }
    if let items = definition.items {
        dict["items"] = try convertJSONSchemaToDict(items, strict: strict)
    }
    if dict["required"] == nil, let required = definition.required {
        dict["required"] = required
    }
    if let uniqueItems = definition.uniqueItems {
        dict["uniqueItems"] = uniqueItems
    }
    if let minProperties = definition.minProperties {
        dict["minProperties"] = minProperties
    }
    if let maxProperties = definition.maxProperties {
        dict["maxProperties"] = maxProperties
    }
    if let enumValues = definition.enum {
        dict["enum"] = enumValues.map { convertJSONSchemaValueToAny($0) }
    }
    if let const = definition.const {
        dict["const"] = convertJSONSchemaValueToAny(const)
    }
    if let title = definition.title { dict["title"] = title }
    if let description = definition.description { dict["description"] = description }
    if let minItems = definition.minItems { dict["minItems"] = minItems }
    if let maxItems = definition.maxItems { dict["maxItems"] = maxItems }
    if let minimum = definition.minimum { dict["minimum"] = minimum }
    if let maximum = definition.maximum { dict["maximum"] = maximum }
    if let pattern = definition.pattern { dict["pattern"] = pattern }
    if let format = definition.format { dict["format"] = format }
    if let examples = definition.examples {
        dict["examples"] = examples.map { convertJSONSchemaValueToAny($0) }
    }
    if let minLength = definition.minLength { dict["minLength"] = minLength }
    if let maxLength = definition.maxLength { dict["maxLength"] = maxLength }
    if let exclusiveMinimum = definition.exclusiveMinimum { dict["exclusiveMinimum"] = exclusiveMinimum }
    if let exclusiveMaximum = definition.exclusiveMaximum { dict["exclusiveMaximum"] = exclusiveMaximum }
    if let additional = definition.additionalProperties {
        dict["additionalProperties"] = try convertAdditionalPropertiesToAny(additional, strict: strict)
    } else if strict && definition.type == .object {
        dict["additionalProperties"] = false
    }
    if let oneOf = definition.oneOf {
        dict["oneOf"] = try oneOf.map { try convertJSONSchemaToDict($0, strict: strict) }
    }
    if let anyOf = definition.anyOf {
        dict["anyOf"] = try anyOf.map { try convertJSONSchemaToDict($0, strict: strict) }
    }
    if let allOf = definition.allOf {
        dict["allOf"] = try allOf.map { try convertJSONSchemaToDict($0, strict: strict) }
    }
    if let not = definition.not {
        dict["not"] = try convertJSONSchemaToDict(not, strict: strict)
    }
    return dict
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func convertJSONSchemaValueToAny(_ value: JSONSchemaValue) -> Any {
    switch value {
    case .string(let string): return string
    case .number(let number): return number
    case .integer(let int): return int
    case .boolean(let bool): return bool
    case .null: return NSNull()
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func convertAdditionalPropertiesToAny(_ additional: AdditionalProperties, strict: Bool) throws -> Any {
    switch additional {
    case .boolean(let value):
        return value
    case .schema(let schema):
        return try convertJSONSchemaToDict(schema, strict: strict)
    }
}

// MARK: - Reasoning encoding

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private extension OpenRouterProvider {
    static func encodeReasoningOptions(_ options: ReasoningOptions) -> JSONValue {
        var dict: [String: JSONValue] = [:]
        if let enabled = options.enabled { dict["enabled"] = .bool(enabled) }
        if let exclude = options.exclude { dict["exclude"] = .bool(exclude) }
        if let maxTokens = options.maxTokens {
            dict["max_tokens"] = .int(maxTokens)
        } else if let effort = options.effort {
            dict["effort"] = .string(effort.rawValue)
        }
        return .object(dict)
    }
}

// MARK: - Error definitions

private enum OpenRouterError: Error, LocalizedError {
    case invalidResponse(String)
    case invalidRequest(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid OpenRouter response: \(message)"
        case .invalidRequest(let message):
            return "Invalid OpenRouter request: \(message)"
        }
    }
}

private extension Dictionary where Value == JSONValue {
    mutating func merge(_ other: [Key: JSONValue]) {
        for (key, value) in other {
            self[key] = value
        }
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func mapOpenRouterFinishReason(_ reason: String?) -> FinishReason {
    switch reason {
    case "stop":
        return .stop
    case "length":
        return .length
    case "content_filter":
        return .contentFilter
    case "tool_calls", "function_call":
        return .toolCalls
    case .some:
        return .unknown
    default:
        return .unknown
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func collectBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()
    for try await chunk in bytes {
        data.append(chunk)
    }
    return data
}
