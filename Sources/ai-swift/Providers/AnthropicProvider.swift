import Foundation

// MARK: - Anthropic Provider Implementation

/// Anthropic provider for the Swift AI SDK.
///
/// `AnthropicProvider` implements the `AIProvider` protocol to provide integration
/// with Anthropic's Claude API, including streaming, and tool calling.
/// This implementation follows the patterns established by the Vercel AI SDK.
///
/// ## Features
/// - Support for all Claude models (Claude 3, Claude 3.5, Claude 4)
/// - Streaming text generation with Server-Sent Events
/// - Tool calling and function execution
/// - Comprehensive error handling
/// - Proper token usage tracking
/// - Cache control and reasoning support
/// - Configurable API endpoints and authentication
///
/// ## Supported Models
/// - Claude 3 (Haiku, Sonnet, Opus)
/// - Claude 3.5 (Sonnet, Haiku)
/// - Claude 4 (with reasoning support)
/// - Future Claude models
///
/// ## Usage Examples
///
/// ### Basic Setup
/// ```swift
/// let provider = AnthropicProvider(apiKey: "your-api-key")
/// let model = provider.languageModel("claude-3-5-sonnet-20241022")
/// let client = AIClient()
/// 
/// let response = try await client.generateText(model, prompt: "Hello!")
/// print(response.text)
/// ```
///
/// ### With Custom Configuration
/// ```swift
/// let provider = AnthropicProvider(
///     apiKey: "your-api-key",
///     baseURL: "https://api.anthropic.com/v1",
///     version: "2023-06-01"
/// )
/// 
/// let model = provider.languageModel("claude-3-5-sonnet-20241022")
///     .temperature(0.8)
///     .maxTokens(1500)
/// ```
///
/// ### Streaming
/// ```swift
/// let stream = client.streamText(model, prompt: "Write a story")
/// for try await chunk in stream {
///     print(chunk.delta, terminator: "")
/// }
/// ```
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct AnthropicProvider: AIProvider {
    
    // MARK: - Properties
    
    /// Provider name for identification and logging.
    public let name = "Anthropic"
    
    /// Provider capabilities for mode support
    public let supportedGenerationModes: Set<GenerationMode> = [.auto, .tool]
    
    /// Default generation mode for this provider - follows Vercel AI SDK pattern
    public let defaultGenerationMode: GenerationMode = .tool
    
    /// Anthropic API key for authentication.
    private let apiKey: String
    
    /// Base URL for the Anthropic API.
    private let baseURL: String
    
    /// Anthropic API version.
    private let version: String
    
    /// Beta features to enable.
    private let betaFeatures: [String]
    
    /// Custom headers to include in requests.
    private let customHeaders: [String: String]
    
    /// URLSession for making HTTP requests.
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    /// Creates a new Anthropic provider with the specified configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic API key (required)
    ///   - baseURL: Base URL for the API (defaults to Anthropic's endpoint)
    ///   - version: API version (defaults to "2023-06-01")
    ///   - betaFeatures: Beta features to enable (e.g., ["computer-use-2024-10-22"])
    ///   - customHeaders: Additional headers to include in requests
    ///   - urlSession: Custom URLSession (defaults to shared)
    public init(
        apiKey: String,
        baseURL: String = "https://api.anthropic.com/v1",
        version: String = "2023-06-01",
        betaFeatures: [String] = [],
        customHeaders: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.version = version
        self.betaFeatures = betaFeatures
        self.customHeaders = customHeaders
        self.urlSession = urlSession
    }
    
    // MARK: - AIProvider Implementation
    
    /// Create a configured language model instance.
    ///
    /// - Parameter modelId: Anthropic model identifier (e.g., "claude-3-5-sonnet-20241022")
    /// - Returns: A configured LanguageModel ready for use
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    /// Execute raw text generation with Anthropic API.
    ///
    /// Transforms the standard request to Anthropic's format, makes the API call,
    /// and converts the response back to the standard format.
    ///
    /// - Parameter request: The standardized request
    /// - Returns: Anthropic response converted to standard format
    /// - Throws: Anthropic-specific errors
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Convert request to Anthropic format
        let anthropicRequest = try convertToAnthropicRequest(request)
        
        // Create HTTP request
        let url = URL(string: "\(baseURL)/messages")!
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        httpRequest.setValue(version, forHTTPHeaderField: "anthropic-version")
        
        // Add beta features if any
        if !betaFeatures.isEmpty {
            httpRequest.setValue(betaFeatures.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        
        // Add custom headers
        for (key, value) in customHeaders {
            httpRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // Encode request body
        let requestData = try JSONEncoder().encode(anthropicRequest)
        httpRequest.httpBody = requestData
        
        // Make HTTP request
        let (data, response) = try await urlSession.data(for: httpRequest)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse("Invalid response type")
        }
        
        if httpResponse.statusCode != 200 {
            let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data)
            let errorMessage = errorResponse?.error.message ?? "HTTP \(httpResponse.statusCode)"
            throw AnthropicError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        // Decode response
        let anthropicResponse = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        
        // Convert to standard format
        return try convertFromAnthropicResponse(anthropicResponse, requestId: request.requestId)
    }
    
    /// Execute raw streaming text generation with Anthropic API.
    ///
    /// Establishes a streaming connection to Anthropic and processes Server-Sent Events
    /// in real-time, converting each chunk to the standard format.
    ///
    /// - Parameter request: The standardized request
    /// - Returns: AsyncThrowingStream of response chunks
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Convert request to Anthropic format with streaming enabled
                    var anthropicRequest = try convertToAnthropicRequest(request)
                    anthropicRequest.stream = true
                    
                    // Create HTTP request
                    let url = URL(string: "\(baseURL)/messages")!
                    var httpRequest = URLRequest(url: url)
                    httpRequest.httpMethod = "POST"
                    httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    httpRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    httpRequest.setValue(version, forHTTPHeaderField: "anthropic-version")
                    httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    // Add beta features if any
                    if !betaFeatures.isEmpty {
                        httpRequest.setValue(betaFeatures.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
                    }
                    
                    // Add custom headers
                    for (key, value) in customHeaders {
                        httpRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    
                    // Encode request body
                    let requestData = try JSONEncoder().encode(anthropicRequest)
                    httpRequest.httpBody = requestData
                    
                    // Make streaming HTTP request
                    let (asyncBytes, response) = try await urlSession.bytes(for: httpRequest)
                    
                    // Check HTTP status
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AnthropicError.invalidResponse("Invalid response type")
                    }
                    
                    if httpResponse.statusCode != 200 {
                        throw AnthropicError.apiError(httpResponse.statusCode, "Streaming request failed")
                    }
                    
                    // Process Server-Sent Events
                    var chunkIndex = 0
                    var currentContent = ""
                    
                    for try await line in asyncBytes.lines {
                        // Process SSE event lines
                        if line.hasPrefix("event: ") {
                            // Skip event type lines - we parse the data directly
                            continue
                        } else if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6)) // Remove "data: " prefix
                            
                            // Skip empty data lines
                            if jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                continue
                            }
                            
                            // Parse event JSON
                            guard let eventData = jsonString.data(using: .utf8) else { continue }
                            
                            do {
                                let event = try JSONDecoder().decode(AnthropicStreamEvent.self, from: eventData)
                                
                                // Process the event
                                if let providerChunk = try processStreamEvent(event, chunkIndex: chunkIndex, currentContent: &currentContent) {
                                    continuation.yield(providerChunk)
                                    chunkIndex += 1
                                }
                                
                                // Check for stream end
                                if case .messageStop = event.type {
                                    break
                                }
                            } catch {
                                // Skip malformed events but continue processing
                                continue
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Validate that the given configuration is supported by Anthropic.
    ///
    /// - Parameter configuration: Configuration to validate
    /// - Throws: AIProviderError if configuration is invalid
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // Validate temperature
        if let temperature = configuration.temperature {
            if temperature < 0.0 || temperature > 1.0 {
                throw AIProviderError.unsupportedParameter("temperature", "Must be between 0.0 and 1.0")
            }
        }
        
        // Validate maxTokens
        if let maxTokens = configuration.maxTokens {
            if maxTokens < 1 {
                throw AIProviderError.unsupportedParameter("maxTokens", "Must be greater than 0")
            }
        }
        
        // Validate topP
        if let topP = configuration.topP {
            if topP < 0.0 || topP > 1.0 {
                throw AIProviderError.unsupportedParameter("topP", "Must be between 0.0 and 1.0")
            }
        }
        
        // Validate topK
        if let topK = configuration.topK {
            if topK < 1 {
                throw AIProviderError.unsupportedParameter("topK", "Must be greater than 0")
            }
        }
        
        // Anthropic doesn't support frequency/presence penalties
        if configuration.frequencyPenalty != nil {
            throw AIProviderError.unsupportedParameter("frequencyPenalty", "Not supported by Anthropic")
        }
        
        if configuration.presencePenalty != nil {
            throw AIProviderError.unsupportedParameter("presencePenalty", "Not supported by Anthropic")
        }
        
        // Anthropic doesn't support seed
        if configuration.seed != nil {
            throw AIProviderError.unsupportedParameter("seed", "Not supported by Anthropic")
        }
    }
}

// MARK: - Private Helper Methods

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private extension AnthropicProvider {
    
    /// Convert ProviderRequest to Anthropic API format following Vercel AI SDK patterns.
    func convertToAnthropicRequest(_ request: ProviderRequest) throws -> AnthropicMessagesRequest {
        // Group messages by role and extract system messages
        let (systemMessages, conversationMessages) = groupMessages(request.messages, systemPrompt: request.system)
        
        // Convert tools if present
        var tools: [AnthropicTool]? = nil
        var toolChoice: AnthropicToolChoice? = nil
        
        switch request.mode {
        case .regular(let requestTools, let requestToolChoice):
            // Regular tool calling
            tools = try requestTools?.map { tool in
                AnthropicTool(
                    name: tool.function.name,
                    description: tool.function.description ?? "",
                    inputSchema: try convertJSONSchemaToDict(tool.function.parameters)
                )
            }
            
            // Convert ToolChoice to Anthropic format
            if let tools = tools, !tools.isEmpty {
                if let requestToolChoice = requestToolChoice {
                    switch requestToolChoice {
                    case .auto:
                        toolChoice = AnthropicToolChoice(type: "auto")
                    case .none:
                        // Anthropic doesn't support "none" - remove tools entirely
                        // Keep tools as nil and toolChoice as nil
                        break
                    case .required:
                        toolChoice = AnthropicToolChoice(type: "any")
                    case .specific(let toolName):
                        toolChoice = AnthropicToolChoice(type: "tool", name: toolName)
                    }
                } else {
                    toolChoice = AnthropicToolChoice(type: "auto")
                }
            }
            
        case .objectJSON(_, _, _):
            // Anthropic doesn't support structured output via response_format
            throw AIProviderError.unsupportedParameter("responseFormat", "JSON schema not supported by Anthropic")
            
        case .objectTool(let tool):
            // Structured output using tool calling
            tools = [AnthropicTool(
                name: tool.function.name,
                description: tool.function.description ?? "",
                inputSchema: try convertJSONSchemaToDict(tool.function.parameters)
            )]
            toolChoice = AnthropicToolChoice(type: "tool", name: tool.function.name)
        }
        
        return AnthropicMessagesRequest(
            model: request.modelId,
            maxTokens: request.configuration.maxTokens ?? 4096,
            system: systemMessages.isEmpty ? nil : systemMessages,
            messages: conversationMessages,
            temperature: request.configuration.temperature,
            topK: request.configuration.topK,
            topP: request.configuration.topP,
            stopSequences: request.configuration.stopSequences,
            tools: tools,
            toolChoice: toolChoice,
            stream: false
        )
    }
    
    /// Group messages by role and extract system messages following Vercel AI SDK patterns.
    func groupMessages(_ messages: [Message], systemPrompt: String?) -> ([AnthropicContent], [AnthropicMessage]) {
        var systemMessages: [AnthropicContent] = []
        var conversationMessages: [AnthropicMessage] = []
        
        // Add system prompt if provided
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            systemMessages.append(AnthropicContent(type: "text", text: systemPrompt))
        }
        
        // Group consecutive messages of the same role
        var currentRole: MessageRole?
        var currentContent: [AnthropicContent] = []
        
        for message in messages {
            // Skip system messages - they're handled separately in Anthropic
            if message.role == .system {
                let textContent = message.content.compactMap { $0.textValue }.joined(separator: "\n")
                if !textContent.isEmpty {
                    systemMessages.append(AnthropicContent(type: "text", text: textContent))
                }
                continue
            }
            
            if currentRole == message.role {
                // Same role - add to current content
                currentContent.append(contentsOf: convertMessageContent(message))
            } else {
                // Different role - finish current message and start new one
                if let role = currentRole, !currentContent.isEmpty {
                    conversationMessages.append(AnthropicMessage(
                        role: role == .user ? "user" : "assistant",
                        content: currentContent
                    ))
                }
                
                currentRole = message.role
                currentContent = convertMessageContent(message)
            }
        }
        
        // Add final message if any
        if let role = currentRole, !currentContent.isEmpty {
            conversationMessages.append(AnthropicMessage(
                role: role == .user ? "user" : "assistant", 
                content: currentContent
            ))
        }
        
        return (systemMessages, conversationMessages)
    }
    
    /// Convert SDK message content to Anthropic format.
    func convertMessageContent(_ message: Message) -> [AnthropicContent] {
        var content: [AnthropicContent] = []
        
        // Convert regular content
        for item in message.content {
            switch item {
            case .text(let text):
                content.append(AnthropicContent(type: "text", text: text))
            case .toolResult(let result):
                // Tool results are handled as tool_result content
                let resultText: String
                switch result.result {
                case .text(let text):
                    resultText = text
                case .json(let data):
                    resultText = String(data: data, encoding: .utf8) ?? "Invalid JSON"
                case .error(let error):
                    resultText = "Error: \(error)"
                default:
                    resultText = "Unsupported result type"
                }
                content.append(AnthropicContent(
                    type: "tool_result",
                    text: resultText,
                    toolUseId: result.toolCallId
                ))
            default:
                // Handle other content types as text
                if let textValue = item.textValue {
                    content.append(AnthropicContent(type: "text", text: textValue))
                }
            }
        }
        
        // Convert tool calls
        if let toolCalls = message.toolCalls {
            for toolCall in toolCalls {
                content.append(AnthropicContent(
                    type: "tool_use",
                    id: toolCall.id,
                    name: toolCall.function.name,
                    input: toolCall.function.parsedArguments ?? [:]
                ))
            }
        }
        
        return content
    }
    
    /// Convert Anthropic response to standard format.
    func convertFromAnthropicResponse(_ response: AnthropicMessagesResponse, requestId: String) throws -> ProviderResponse {
        var content = ""
        var toolCalls: [ToolCall] = []
        
        // Process content blocks
        for contentBlock in response.content {
            switch contentBlock.type {
            case "text":
                if let text = contentBlock.text {
                    content += text
                }
            case "tool_use":
                if let id = contentBlock.id,
                   let name = contentBlock.name,
                   let input = contentBlock.input {
                    let argumentsString = String(data: try JSONSerialization.data(withJSONObject: input, options: []), encoding: .utf8) ?? "{}"
                    let toolCall = ToolCall(
                        id: id,
                        function: ToolCallFunction(
                            name: name,
                            arguments: argumentsString
                        )
                    )
                    toolCalls.append(toolCall)
                }
            default:
                // Skip unknown content types
                break
            }
        }
        
        // Convert usage
        let usage = Usage(
            promptTokens: response.usage.inputTokens,
            completionTokens: response.usage.outputTokens,
            promptCost: nil,
            completionCost: nil,
            currency: "USD"
        )
        
        // Convert stop reason
        let finishReason: FinishReason
        switch response.stopReason {
        case "end_turn":
            finishReason = .stop
        case "max_tokens":
            finishReason = .length
        case "tool_use":
            finishReason = .toolCalls
        case "stop_sequence":
            finishReason = .stop
        default:
            finishReason = .other
        }
        
        return ProviderResponse(
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            usage: usage,
            finishReason: finishReason,
            responseId: response.id,
            providerMetadata: [
                "model": response.model,
                "role": response.role
            ]
        )
    }
    
    /// Process a streaming event from Anthropic.
    func processStreamEvent(_ event: AnthropicStreamEvent, chunkIndex: Int, currentContent: inout String) throws -> ProviderChunk? {
        switch event.type {
        case .messageStart:
            // Initialize with usage if present
            if let message = event.message,
               let usage = message.usage {
                return ProviderChunk(
                    delta: "",
                    usage: Usage(
                        promptTokens: usage.inputTokens,
                        completionTokens: usage.outputTokens,
                        promptCost: nil,
                        completionCost: nil,
                        currency: "USD"
                    ),
                    finishReason: nil,
                    chunkIndex: chunkIndex
                )
            }
            return nil
            
        case .contentBlockStart:
            // Start of content block - no delta yet
            return nil
            
        case .contentBlockDelta:
            // Content delta
            if let delta = event.delta {
                if delta.type == "text_delta", let text = delta.text {
                    currentContent += text
                    return ProviderChunk(
                        delta: text,
                        usage: nil,
                        finishReason: nil,
                        chunkIndex: chunkIndex
                    )
                }
            }
            return nil
            
        case .contentBlockStop:
            // End of content block
            return nil
            
        case .messageDelta:
            // Message delta with updated usage and stop reason
            var usage: Usage? = nil
            var finishReason: FinishReason? = nil
            
            if let delta = event.delta {
                if let deltaUsage = delta.usage {
                    usage = Usage(
                        promptTokens: deltaUsage.inputTokens,
                        completionTokens: deltaUsage.outputTokens,
                        promptCost: nil,
                        completionCost: nil,
                        currency: "USD"
                    )
                }
                
                if let stopReason = delta.stopReason {
                    switch stopReason {
                    case "end_turn":
                        finishReason = .stop
                    case "max_tokens":
                        finishReason = .length
                    case "tool_use":
                        finishReason = .toolCalls
                    case "stop_sequence":
                        finishReason = .stop
                    default:
                        finishReason = .other
                    }
                }
            }
            
            if usage != nil || finishReason != nil {
                return ProviderChunk(
                    delta: "",
                    usage: usage,
                    finishReason: finishReason,
                    chunkIndex: chunkIndex
                )
            }
            return nil
            
        case .messageStop:
            // End of stream
            return nil
        }
    }
    
    /// Convert JSONSchema to dictionary format for Anthropic API.
    func convertJSONSchemaToDict(_ schema: JSONSchema) throws -> [String: Any] {
        return try convertSchemaDefinitionToDict(schema.definition)
    }
    
    /// Recursively convert SchemaDefinition to dictionary.
    private func convertSchemaDefinitionToDict(_ definition: SchemaDefinition) throws -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // Basic properties
        dict["type"] = definition.type.rawValue
        
        if let properties = definition.properties {
            var propertiesDict: [String: Any] = [:]
            for (key, schema) in properties {
                propertiesDict[key] = try convertJSONSchemaToDict(schema)
            }
            dict["properties"] = propertiesDict
        }
        
        if let items = definition.items {
            dict["items"] = try convertJSONSchemaToDict(items)
        }
        
        if let required = definition.required {
            dict["required"] = required
        }
        
        if let enumValues = definition.enum {
            dict["enum"] = try enumValues.map { try convertJSONSchemaValueToAny($0) }
        }
        
        // Optional properties
        if let title = definition.title { dict["title"] = title }
        if let description = definition.description { dict["description"] = description }
        if let minimum = definition.minimum { dict["minimum"] = minimum }
        if let maximum = definition.maximum { dict["maximum"] = maximum }
        if let minLength = definition.minLength { dict["minLength"] = minLength }
        if let maxLength = definition.maxLength { dict["maxLength"] = maxLength }
        
        return dict
    }
    
    /// Convert JSONSchemaValue to Swift Any for dictionary
    private func convertJSONSchemaValueToAny(_ value: JSONSchemaValue) throws -> Any {
        switch value {
        case .string(let str):
            return str
        case .integer(let int):
            return int
        case .number(let double):
            return double
        case .boolean(let bool):
            return bool
        case .null:
            return NSNull()
        }
    }
}

// MARK: - Anthropic API Types

/// Anthropic Messages API request structure.
private struct AnthropicMessagesRequest: Codable {
    let model: String
    let maxTokens: Int
    let system: [AnthropicContent]?
    let messages: [AnthropicMessage]
    let temperature: Double?
    let topK: Int?
    let topP: Double?
    let stopSequences: [String]?
    let tools: [AnthropicTool]?
    let toolChoice: AnthropicToolChoice?
    var stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system, messages, temperature
        case topK = "top_k"
        case topP = "top_p"
        case stopSequences = "stop_sequences"
        case tools
        case toolChoice = "tool_choice"
        case stream
    }
}

/// Anthropic message structure.
private struct AnthropicMessage: Codable {
    let role: String
    let content: [AnthropicContent]
}

/// Anthropic content structure.
private struct AnthropicContent: Codable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: Any]?
    let toolUseId: String?
    
    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
    }
    
    init(type: String, text: String? = nil, id: String? = nil, name: String? = nil, input: [String: Any]? = nil, toolUseId: String? = nil) {
        self.type = type
        self.text = text
        self.id = id
        self.name = name
        self.input = input
        self.toolUseId = toolUseId
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(toolUseId, forKey: .toolUseId)
        
        if let input = input {
            try container.encode(AnyCodable(input), forKey: .input)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
        
        if let inputValue = try container.decodeIfPresent(AnyCodable.self, forKey: .input) {
            input = inputValue.value as? [String: Any]
        } else {
            input = nil
        }
    }
}

/// Anthropic tool definition.
private struct AnthropicTool: Codable {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(AnyCodable(inputSchema), forKey: .inputSchema)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        
        let schemaValue = try container.decode(AnyCodable.self, forKey: .inputSchema)
        inputSchema = schemaValue.value as? [String: Any] ?? [:]
    }
    
    init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Anthropic tool choice structure.
private struct AnthropicToolChoice: Codable {
    let type: String
    let name: String?
    
    init(type: String, name: String? = nil) {
        self.type = type
        self.name = name
    }
}

/// Anthropic Messages API response structure.
private struct AnthropicMessagesResponse: Codable {
    let id: String
    let type: String
    let role: String
    let model: String
    let content: [AnthropicResponseContent]
    let stopReason: String?
    let stopSequence: String?
    let usage: AnthropicUsage
    
    enum CodingKeys: String, CodingKey {
        case id, type, role, model, content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

/// Anthropic response content structure.
private struct AnthropicResponseContent: Codable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: Any]?
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        
        if let input = input {
            try container.encode(AnyCodable(input), forKey: .input)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        
        if let inputValue = try container.decodeIfPresent(AnyCodable.self, forKey: .input) {
            input = inputValue.value as? [String: Any]
        } else {
            input = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
    }
}

/// Anthropic usage structure.
private struct AnthropicUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - Streaming Event Types

/// Anthropic streaming event structure.
private struct AnthropicStreamEvent: Codable {
    let type: AnthropicStreamEventType
    let message: AnthropicStreamMessage?
    let index: Int?
    let contentBlock: AnthropicStreamContentBlock?
    let delta: AnthropicStreamDelta?
    
    enum CodingKeys: String, CodingKey {
        case type, message, index
        case contentBlock = "content_block"
        case delta
    }
}

/// Anthropic stream event types.
private enum AnthropicStreamEventType: String, Codable {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
}

/// Anthropic stream message structure.
private struct AnthropicStreamMessage: Codable {
    let id: String?
    let type: String?
    let role: String?
    let model: String?
    let content: [AnthropicContent]?
    let stopReason: String?
    let stopSequence: String?
    let usage: AnthropicUsage?
    
    enum CodingKeys: String, CodingKey {
        case id, type, role, model, content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

/// Anthropic stream content block structure.
private struct AnthropicStreamContentBlock: Codable {
    let type: String
    let text: String?
}

/// Anthropic stream delta structure.
private struct AnthropicStreamDelta: Codable {
    let type: String?
    let text: String?
    let stopReason: String?
    let usage: AnthropicUsage?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case stopReason = "stop_reason"
        case usage
    }
}

/// Anthropic error response structure.
private struct AnthropicErrorResponse: Codable {
    let type: String
    let error: AnthropicErrorDetail
}

/// Anthropic error detail structure.
private struct AnthropicErrorDetail: Codable {
    let type: String
    let message: String
}

// MARK: - Anthropic Errors

/// Anthropic-specific errors.
private enum AnthropicError: Error, LocalizedError {
    case invalidResponse(String)
    case apiError(Int, String)
    case authenticationFailed
    case rateLimitExceeded
    case invalidRequest(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid Anthropic response: \(message)"
        case .apiError(let code, let message):
            return "Anthropic API error (\(code)): \(message)"
        case .authenticationFailed:
            return "Anthropic authentication failed"
        case .rateLimitExceeded:
            return "Anthropic rate limit exceeded"
        case .invalidRequest(let message):
            return "Invalid Anthropic request: \(message)"
        }
    }
}

// MARK: - Helper Types

/// Type-erased codable wrapper for handling arbitrary JSON.
private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let arrayValue = value as? [Any] {
            try container.encode(arrayValue.map { AnyCodable($0) })
        } else if let dictValue = value as? [String: Any] {
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
}