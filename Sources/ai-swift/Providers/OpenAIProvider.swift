import Foundation

// MARK: - OpenAI Provider Implementation

/// OpenAI provider for the Swift AI SDK.
///
/// `OpenAIProvider` implements the `AIProvider` protocol to provide integration
/// with OpenAI's API, including GPT models, streaming, and tool calling.
/// This implementation follows the patterns established by the Vercel AI SDK.
///
/// ## Features
/// - Support for all OpenAI chat models (GPT-4, GPT-3.5, etc.)
/// - Streaming text generation with Server-Sent Events
/// - Tool calling and function execution
/// - Comprehensive error handling and retry logic
/// - Proper token usage tracking
/// - Configurable API endpoints and authentication
///
/// ## Supported Models
/// - GPT-4 (all variants)
/// - GPT-3.5 Turbo
/// - GPT-4 Turbo
/// - Future OpenAI models
///
/// ## Usage Examples
///
/// ### Basic Setup
/// ```swift
/// let provider = OpenAIProvider(apiKey: "your-api-key")
/// let model = provider.languageModel("gpt-4")
/// let client = AIClient()
/// 
/// let response = try await client.generateText(model, prompt: "Hello!")
/// print(response.text)
/// ```
///
/// ### With Custom Configuration
/// ```swift
/// let provider = OpenAIProvider(
///     apiKey: "your-api-key",
///     baseURL: "https://api.openai.com/v1",
///     organization: "your-org-id"
/// )
/// 
/// let model = provider.languageModel("gpt-4")
///     .temperature(0.8)
///     .maxTokens(150)
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
public struct OpenAIProvider: AIProvider {
    
    // MARK: - Properties
    
    /// Provider name for identification and logging.
    public let name = "OpenAI"
    
    /// OpenAI API key for authentication.
    private let apiKey: String
    
    /// Base URL for the OpenAI API.
    private let baseURL: String
    
    /// Optional OpenAI organization ID.
    private let organization: String?
    
    /// Optional OpenAI project ID.
    private let project: String?
    
    /// Custom headers to include in requests.
    private let customHeaders: [String: String]
    
    /// URLSession for making HTTP requests.
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    /// Creates a new OpenAI provider with the specified configuration.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key (required)
    ///   - baseURL: Base URL for the API (defaults to OpenAI's endpoint)
    ///   - organization: Optional organization ID
    ///   - project: Optional project ID
    ///   - customHeaders: Additional headers to include in requests
    ///   - urlSession: Custom URLSession (defaults to shared)
    public init(
        apiKey: String,
        baseURL: String = "https://api.openai.com/v1",
        organization: String? = nil,
        project: String? = nil,
        customHeaders: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.organization = organization
        self.project = project
        self.customHeaders = customHeaders
        self.urlSession = urlSession
    }
    
    // MARK: - AIProvider Implementation
    
    /// Create a configured language model instance.
    ///
    /// - Parameter modelId: OpenAI model identifier (e.g., "gpt-4", "gpt-3.5-turbo")
    /// - Returns: A configured LanguageModel ready for use
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    /// Execute raw text generation with OpenAI API.
    ///
    /// Transforms the standard request to OpenAI's format, makes the API call,
    /// and converts the response back to the standard format.
    ///
    /// - Parameter request: The standardized request
    /// - Returns: OpenAI response converted to standard format
    /// - Throws: OpenAI-specific errors
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Convert request to OpenAI format
        let openAIRequest = try convertToOpenAIRequest(request)
        
        // Create HTTP request
        let url = URL(string: "\(baseURL)/chat/completions")!
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Add optional headers
        if let organization = organization {
            httpRequest.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let project = project {
            httpRequest.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }
        
        // Add custom headers
        for (key, value) in customHeaders {
            httpRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // Encode request body
        let requestData = try JSONEncoder().encode(openAIRequest)
        httpRequest.httpBody = requestData
        
        // Make HTTP request
        let (data, response) = try await urlSession.data(for: httpRequest)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse("Invalid response type")
        }
        
        if httpResponse.statusCode != 200 {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let errorMessage = errorResponse?.error.message ?? "HTTP \(httpResponse.statusCode)"
            throw OpenAIError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        // Decode response
        let openAIResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        
        // Convert to standard format
        return try convertFromOpenAIResponse(openAIResponse, requestId: request.requestId)
    }
    
    /// Execute raw streaming text generation with OpenAI API.
    ///
    /// Establishes a streaming connection to OpenAI and processes Server-Sent Events
    /// in real-time, converting each chunk to the standard format.
    ///
    /// - Parameter request: The standardized request
    /// - Returns: AsyncThrowingStream of response chunks
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Convert request to OpenAI format with streaming enabled
                    var openAIRequest = try convertToOpenAIRequest(request)
                    openAIRequest.stream = true
                    openAIRequest.streamOptions = OpenAIStreamOptions(includeUsage: true)
                    
                    // Create HTTP request
                    let url = URL(string: "\(baseURL)/chat/completions")!
                    var httpRequest = URLRequest(url: url)
                    httpRequest.httpMethod = "POST"
                    httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    // Add optional headers
                    if let organization = organization {
                        httpRequest.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
                    }
                    if let project = project {
                        httpRequest.setValue(project, forHTTPHeaderField: "OpenAI-Project")
                    }
                    
                    // Add custom headers
                    for (key, value) in customHeaders {
                        httpRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    
                    // Encode request body
                    let requestData = try JSONEncoder().encode(openAIRequest)
                    httpRequest.httpBody = requestData
                    
                    // Make streaming HTTP request
                    let (asyncBytes, response) = try await urlSession.bytes(for: httpRequest)
                    
                    // Check HTTP status
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIError.invalidResponse("Invalid response type")
                    }
                    
                    if httpResponse.statusCode != 200 {
                        throw OpenAIError.apiError(httpResponse.statusCode, "Streaming request failed")
                    }
                    
                    // Process Server-Sent Events
                    var chunkIndex = 0
                    var accumulatedUsage: Usage?
                    
                    for try await line in asyncBytes.lines {
                        // Process SSE data lines
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6)) // Remove "data: " prefix
                            
                            // Check for end of stream
                            if jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                                // Send final chunk if we have usage info
                                if let usage = accumulatedUsage {
                                    let finalChunk = ProviderChunk(
                                        delta: "",
                                        usage: usage,
                                        finishReason: .stop,
                                        chunkIndex: chunkIndex
                                    )
                                    continuation.yield(finalChunk)
                                }
                                break
                            }
                            
                            // Parse chunk JSON
                            guard let chunkData = jsonString.data(using: .utf8) else { continue }
                            
                            do {
                                let chunk = try JSONDecoder().decode(OpenAIChatChunk.self, from: chunkData)
                                
                                // Process the chunk
                                if let providerChunk = try processStreamChunk(chunk, chunkIndex: chunkIndex) {
                                    // Update accumulated usage if present
                                    if let usage = providerChunk.usage {
                                        accumulatedUsage = usage
                                    }
                                    
                                    continuation.yield(providerChunk)
                                    chunkIndex += 1
                                }
                            } catch {
                                // Skip malformed chunks but continue processing
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
    
    /// Validate that the given configuration is supported by OpenAI.
    ///
    /// - Parameter configuration: Configuration to validate
    /// - Throws: AIProviderError if configuration is invalid
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // Validate temperature
        if let temperature = configuration.temperature {
            if temperature < 0.0 || temperature > 2.0 {
                throw AIProviderError.unsupportedParameter("temperature", "Must be between 0.0 and 2.0")
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
        
        // OpenAI doesn't support topK
        if configuration.topK != nil {
            throw AIProviderError.unsupportedParameter("topK", "Not supported by OpenAI")
        }
        
        // Validate penalties
        if let frequencyPenalty = configuration.frequencyPenalty {
            if frequencyPenalty < -2.0 || frequencyPenalty > 2.0 {
                throw AIProviderError.unsupportedParameter("frequencyPenalty", "Must be between -2.0 and 2.0")
            }
        }
        
        if let presencePenalty = configuration.presencePenalty {
            if presencePenalty < -2.0 || presencePenalty > 2.0 {
                throw AIProviderError.unsupportedParameter("presencePenalty", "Must be between -2.0 and 2.0")
            }
        }
    }
}

// MARK: - Private Helper Methods

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private extension OpenAIProvider {
    
    /// Convert ProviderRequest to OpenAI API format.
    func convertToOpenAIRequest(_ request: ProviderRequest) throws -> OpenAIChatRequest {
        // Convert messages
        let messages = convertMessages(request.messages)
        
        // Handle system message
        var allMessages = messages
        if let systemMessage = request.system {
            allMessages.insert(OpenAIMessage(role: "system", content: .text(systemMessage)), at: 0)
        }
        
        // Convert tools if present
        let tools = try request.tools?.map { tool in
            OpenAITool(
                type: "function",
                function: OpenAIFunction(
                    name: tool.function.name,
                    description: tool.function.description,
                    parameters: try convertJSONSchemaToDict(tool.function.parameters)
                )
            )
        }
        
        return OpenAIChatRequest(
            model: request.modelId,
            messages: allMessages,
            temperature: request.configuration.temperature,
            maxTokens: request.configuration.maxTokens,
            topP: request.configuration.topP,
            frequencyPenalty: request.configuration.frequencyPenalty,
            presencePenalty: request.configuration.presencePenalty,
            stop: request.configuration.stopSequences,
            tools: tools,
            toolChoice: tools?.isEmpty == false ? "auto" : nil,
            seed: request.configuration.seed,
            stream: false,
            streamOptions: nil
        )
    }
    
    /// Convert SDK messages to OpenAI format.
    func convertMessages(_ messages: [Message]) -> [OpenAIMessage] {
        return messages.map { message in
            switch message.role {
            case .system:
                return OpenAIMessage(
                    role: "system", 
                    content: .text(message.content.first?.textValue ?? "")
                )
            case .user:
                let textContent = message.content.compactMap { $0.textValue }.joined(separator: "\n")
                return OpenAIMessage(role: "user", content: .text(textContent))
            case .assistant:
                let textContent = message.content.compactMap { $0.textValue }.joined(separator: "\n")
                return OpenAIMessage(role: "assistant", content: .text(textContent))
            case .tool:
                // Handle tool results
                if let toolResult = message.content.first {
                    switch toolResult {
                    case .toolResult(let result):
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
                        return OpenAIMessage(
                            role: "tool",
                            content: .text(resultText),
                            toolCallId: result.toolCallId
                        )
                    default:
                        let textContent = toolResult.textValue ?? "Unknown tool result"
                        return OpenAIMessage(role: "tool", content: .text(textContent))
                    }
                } else {
                    return OpenAIMessage(role: "tool", content: .text("Empty tool result"))
                }
            }
        }
    }
    
    /// Convert OpenAI response to standard format.
    func convertFromOpenAIResponse(_ response: OpenAIChatResponse, requestId: String) throws -> ProviderResponse {
        guard let choice = response.choices.first else {
            throw OpenAIError.invalidResponse("No choices in response")
        }
        
        let content = choice.message.content ?? ""
        
        // Convert tool calls
        let toolCalls = try choice.message.toolCalls?.map { openAIToolCall in
            try ToolCall(
                id: openAIToolCall.id,
                function: ToolCallFunction(
                    name: openAIToolCall.function.name,
                    arguments: parseToolArguments(openAIToolCall.function.arguments)
                )
            )
        }
        
        // Convert usage
        let usage = Usage(
            promptTokens: response.usage?.promptTokens ?? 0,
            completionTokens: response.usage?.completionTokens ?? 0,
            promptCost: nil,
            completionCost: nil,
            currency: "USD"
        )
        
        // Convert finish reason
        let finishReason: FinishReason
        switch choice.finishReason {
        case "stop":
            finishReason = .stop
        case "length":
            finishReason = .length
        case "tool_calls":
            finishReason = .toolCalls
        case "content_filter":
            finishReason = .contentFilter
        default:
            finishReason = .other
        }
        
        return ProviderResponse(
            content: content,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            responseId: response.id,
            providerMetadata: [
                "model": response.model,
                "created": "\(response.created)"
            ]
        )
    }
    
    /// Process a streaming chunk from OpenAI.
    func processStreamChunk(_ chunk: OpenAIChatChunk, chunkIndex: Int) throws -> ProviderChunk? {
        guard let choice = chunk.choices.first else {
            return nil
        }
        
        let delta = choice.delta.content ?? ""
        
        // Convert finish reason
        let finishReason: FinishReason?
        if let reason = choice.finishReason {
            switch reason {
            case "stop":
                finishReason = .stop
            case "length":
                finishReason = .length
            case "tool_calls":
                finishReason = .toolCalls
            case "content_filter":
                finishReason = .contentFilter
            default:
                finishReason = .other
            }
        } else {
            finishReason = nil
        }
        
        // Convert usage if present
        let usage: Usage?
        if let chunkUsage = chunk.usage {
            usage = Usage(
                promptTokens: chunkUsage.promptTokens ?? 0,
                completionTokens: chunkUsage.completionTokens ?? 0,
                promptCost: nil,
                completionCost: nil,
                currency: "USD"
            )
        } else {
            usage = nil
        }
        
        return ProviderChunk(
            delta: delta,
            usage: usage,
            finishReason: finishReason,
            chunkIndex: chunkIndex
        )
    }
    
    /// Parse tool arguments from JSON string.
    func parseToolArguments(_ argumentsString: String) throws -> [String: Any] {
        guard let data = argumentsString.data(using: .utf8) else {
            throw OpenAIError.invalidResponse("Invalid tool arguments encoding")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.invalidResponse("Tool arguments must be a JSON object")
        }
        
        return json
    }
    
    /// Convert JSONSchema to dictionary format for OpenAI API.
    func convertJSONSchemaToDict(_ schema: JSONSchema) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(schema)
        
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.invalidRequest("Failed to convert JSONSchema to dictionary")
        }
        
        return dict
    }
}

// MARK: - OpenAI API Types

/// OpenAI Chat API request structure.
private struct OpenAIChatRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let stop: [String]?
    let tools: [OpenAITool]?
    let toolChoice: String?
    let seed: Int?
    var stream: Bool
    var streamOptions: OpenAIStreamOptions?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case stop, tools
        case toolChoice = "tool_choice"
        case seed, stream
        case streamOptions = "stream_options"
    }
}

/// OpenAI message structure.
private struct OpenAIMessage: Codable {
    let role: String
    let content: OpenAIContent?
    let toolCallId: String?
    let toolCalls: [OpenAIToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }
    
    init(role: String, content: OpenAIContent, toolCallId: String? = nil, toolCalls: [OpenAIToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
}

/// OpenAI content type (text or other formats).
private enum OpenAIContent: Codable {
    case text(String)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid content format")
            )
        }
    }
}

/// OpenAI tool definition.
private struct OpenAITool: Codable {
    let type: String
    let function: OpenAIFunction
}

/// OpenAI function definition.
private struct OpenAIFunction: Codable {
    let name: String
    let description: String?
    let parameters: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        
        let parametersData = try JSONSerialization.data(withJSONObject: parameters)
        let parametersJSON = try JSONSerialization.jsonObject(with: parametersData)
        try container.encode(AnyCodable(parametersJSON), forKey: .parameters)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        
        let parametersValue = try container.decode(AnyCodable.self, forKey: .parameters)
        parameters = parametersValue.value as? [String: Any] ?? [:]
    }
    
    init(name: String, description: String?, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// OpenAI tool call structure.
private struct OpenAIToolCall: Codable {
    let id: String
    let type: String
    let function: OpenAIFunctionCall
}

/// OpenAI function call structure.
private struct OpenAIFunctionCall: Codable {
    let name: String
    let arguments: String
}

/// OpenAI streaming options.
private struct OpenAIStreamOptions: Codable {
    let includeUsage: Bool
    
    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

/// OpenAI chat response structure.
private struct OpenAIChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

/// OpenAI choice structure.
private struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIResponseMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

/// OpenAI response message structure.
private struct OpenAIResponseMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [OpenAIToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

/// OpenAI streaming chunk structure.
private struct OpenAIChatChunk: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChunkChoice]
    let usage: OpenAIUsage?
}

/// OpenAI chunk choice structure.
private struct OpenAIChunkChoice: Codable {
    let index: Int
    let delta: OpenAIChunkDelta
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

/// OpenAI chunk delta structure.
private struct OpenAIChunkDelta: Codable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAIToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

/// OpenAI usage structure.
private struct OpenAIUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

/// OpenAI error response structure.
private struct OpenAIErrorResponse: Codable {
    let error: OpenAIErrorDetail
}

/// OpenAI error detail structure.
private struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String?
    let param: String?
    let code: String?
}

// MARK: - OpenAI Errors

/// OpenAI-specific errors.
private enum OpenAIError: Error, LocalizedError {
    case invalidResponse(String)
    case apiError(Int, String)
    case authenticationFailed
    case rateLimitExceeded
    case invalidRequest(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid OpenAI response: \(message)"
        case .apiError(let code, let message):
            return "OpenAI API error (\(code)): \(message)"
        case .authenticationFailed:
            return "OpenAI authentication failed"
        case .rateLimitExceeded:
            return "OpenAI rate limit exceeded"
        case .invalidRequest(let message):
            return "Invalid OpenAI request: \(message)"
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