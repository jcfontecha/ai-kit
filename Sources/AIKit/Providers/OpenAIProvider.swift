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
    
    /// Provider capabilities for mode support
    public let supportedGenerationModes: Set<GenerationMode> = [.auto, .json, .tool]
    
    /// Default generation mode for this provider - follows Vercel AI SDK pattern
    public let defaultGenerationMode: GenerationMode = .json
    
    /// Whether this provider instance supports OpenAI's structured outputs for a given model
    public func supportsStructuredOutputs(for modelId: String) -> Bool {
        // Reasoning models (o1, o3, o4) and gpt-4.1 series support structured outputs
        return structuredOutputs ?? (isReasoningModel(modelId: modelId) || supportsStructuredOutputsByDefault(modelId: modelId))
    }
    
    /// Whether structured outputs are explicitly enabled
    private let structuredOutputs: Bool?
    
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
    ///   - structuredOutputs: Whether to enable structured outputs (auto-detect if nil)
    ///   - customHeaders: Additional headers to include in requests
    ///   - urlSession: Custom URLSession (defaults to shared)
    public init(
        apiKey: String,
        baseURL: String = "https://api.openai.com/v1",
        organization: String? = nil,
        project: String? = nil,
        structuredOutputs: Bool? = nil,
        customHeaders: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.organization = organization
        self.project = project
        self.structuredOutputs = structuredOutputs
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
    
    // MARK: - Model Capability Detection
    
    /// Check if a model is a reasoning model (supports structured outputs by default)
    private func isReasoningModel(modelId: String) -> Bool {
        return modelId.hasPrefix("o")  // o1, o3, o4 series
    }
    
    /// Check if a model is an audio model (doesn't support structured outputs)
    private func isAudioModel(modelId: String) -> Bool {
        return modelId.contains("audio-preview")
    }
    
    /// Check if a model supports structured outputs by default (following Vercel AI SDK patterns)
    private func supportsStructuredOutputsByDefault(modelId: String) -> Bool {
        // Audio models don't support structured outputs
        if isAudioModel(modelId: modelId) {
            return false
        }
        
        // Models that support structured outputs according to OpenAI docs
        return modelId.hasPrefix("gpt-4o") ||
               modelId.hasPrefix("gpt-4.1") ||
               modelId.hasPrefix("gpt-4-turbo") ||
               modelId.hasPrefix("gpt-4-0125-preview") ||
               modelId.hasPrefix("gpt-4-1106-preview") ||
               modelId.hasPrefix("gpt-3.5-turbo-0125") ||
               modelId.hasPrefix("gpt-3.5-turbo-1106")
    }
    
    // MARK: - Transcription Methods
    
    /// Create a transcription model for OpenAI Whisper models.
    ///
    /// Overrides the default implementation to provide OpenAI-specific transcription capabilities.
    /// Supports Whisper models and other OpenAI transcription models.
    ///
    /// - Parameter modelId: The OpenAI transcription model ID (e.g., "whisper-1")
    /// - Returns: A configured TranscriptionModel for use with AIClient
    public func transcriptionModel(_ modelId: String) -> TranscriptionModel {
        return TranscriptionModel(provider: self, modelId: modelId)
    }
    
    /// Execute transcription using OpenAI's transcription API.
    ///
    /// This method implements the OpenAI Whisper API for audio transcription,
    /// following the Vercel AI SDK patterns and supporting all OpenAI transcription features.
    ///
    /// - Parameter request: The standardized transcription request
    /// - Returns: A standardized transcription response
    /// - Throws: OpenAI-specific errors converted to TranscriptionError
    public func transcribeRaw(_ request: TranscriptionProviderRequest) async throws -> TranscriptionProviderResponse {
        let startTime = Date()
        
        do {
            // Convert request to OpenAI transcription API format
            let openAIRequest = try await convertToOpenAITranscriptionRequest(request)
            
            // Create multipart form data
            let boundary = "----formdata-swift-\(UUID().uuidString)"
            let httpBody = try await createTranscriptionFormData(openAIRequest, boundary: boundary)
            
            // Prepare the HTTP request
            var urlRequest = URLRequest(url: URL(string: "\(baseURL)/audio/transcriptions")!)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            if let organization = organization {
                urlRequest.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
            }
            
            // Add custom headers from request
            if let customHeaders = request.headers {
                for (key, value) in customHeaders {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }
            }
            
            urlRequest.httpBody = httpBody
            
            // Make the API call
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.networkError(NSError(domain: "InvalidResponse", code: 0))
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = try? parseOpenAIError(data)
                throw TranscriptionError.providerSpecific(
                    errorMessage ?? "HTTP \(httpResponse.statusCode)",
                    underlyingError: nil
                )
            }
            
            // Parse the response
            let openAIResponse = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
            
            // Convert to standard format
            let responseMetadata = TranscriptionResponseMetadata(
                timestamp: startTime,
                modelId: request.modelId,
                headers: Dictionary(uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                    guard let keyString = key as? String, let valueString = value as? String else { return nil }
                    return (keyString, valueString)
                }),
                duration: Date().timeIntervalSince(startTime)
            )
            
            return TranscriptionProviderResponse(
                text: openAIResponse.text,
                segments: openAIResponse.segments?.map { segment in
                    TranscriptionSegment(
                        text: segment.text,
                        startSecond: segment.start,
                        endSecond: segment.end
                    )
                } ?? [],
                language: openAIResponse.language,
                durationInSeconds: openAIResponse.duration,
                warnings: [], // OpenAI doesn't typically return warnings for transcription
                responseMetadata: responseMetadata,
                providerMetadata: [
                    "model": openAIResponse.model ?? request.modelId,
                    "task": openAIResponse.task ?? "transcribe"
                ]
            )
            
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.providerSpecific(
                "OpenAI transcription failed: \(error.localizedDescription)",
                underlyingError: error
            )
        }
    }
}

// MARK: - Private Helper Methods

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private extension OpenAIProvider {
    
    /// Convert ProviderRequest to OpenAI API format following Vercel AI SDK patterns.
    func convertToOpenAIRequest(_ request: ProviderRequest) throws -> OpenAIChatRequest {
        // Convert messages
        let messages = convertMessages(request.messages)
        
        // Handle system message
        var allMessages = messages
        if let systemMessage = request.system {
            allMessages.insert(OpenAIMessage(role: "system", content: .text(systemMessage)), at: 0)
        }
        
        
        // Handle different provider modes following Vercel AI SDK approach
        var tools: [OpenAITool]? = nil
        var toolChoice: String? = nil
        var responseFormat: OpenAIResponseFormat? = nil
        
        // Determine if we should use structured outputs for this model
        let supportsStructuredOutputs = self.supportsStructuredOutputs(for: request.modelId)
        
        switch request.mode {
        case .regular(let requestTools, let requestToolChoice):
            // Regular tool calling - follow Vercel AI SDK pattern for tool_choice
            tools = try requestTools?.map { tool in
                OpenAITool(
                    type: "function",
                    function: OpenAIFunction(
                        name: tool.function.name,
                        description: tool.function.description,
                        parameters: try convertJSONSchemaToDict(tool.function.parameters, forStrictMode: supportsStructuredOutputs),
                        strict: supportsStructuredOutputs ? true : nil
                    )
                )
            }
            
            // Convert ToolChoice to OpenAI format
            if let tools = tools, !tools.isEmpty {
                if let requestToolChoice = requestToolChoice {
                    switch requestToolChoice {
                    case .auto:
                        toolChoice = "auto"
                    case .none:
                        toolChoice = "none"
                    case .required:
                        toolChoice = "required"
                    case .specific(let toolName):
                        toolChoice = "{\"type\": \"function\", \"function\": {\"name\": \"\(toolName)\"}}"
                    }
                } else {
                    toolChoice = nil
                }
            } else {
                toolChoice = nil
            }
            
        case .objectJSON(let schema, let name, let description):
            // Structured output using response_format - follows Vercel AI SDK pattern
            if supportsStructuredOutputs {
                responseFormat = OpenAIResponseFormat(
                    type: "json_schema",
                    jsonSchema: OpenAIJSONSchema(
                        name: name ?? "response",
                        schema: try convertJSONSchemaToDict(schema, forStrictMode: true),
                        description: description,
                        strict: true
                    )
                )
            } else {
                // Fallback to json_object mode for models without structured outputs
                responseFormat = OpenAIResponseFormat(type: "json_object", jsonSchema: nil)
            }
            
        case .objectTool(let tool):
            // Structured output using function calling
            tools = [OpenAITool(
                type: "function",
                function: OpenAIFunction(
                    name: tool.function.name,
                    description: tool.function.description,
                    parameters: try convertJSONSchemaToDict(tool.function.parameters, forStrictMode: supportsStructuredOutputs),
                    strict: supportsStructuredOutputs ? true : nil
                )
            )]
            toolChoice = "required"
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
            toolChoice: toolChoice,
            responseFormat: responseFormat,
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
                // Check if we have image content
                let hasImages = message.content.contains { $0.imageValue != nil }
                
                if hasImages {
                    // Multi-part content with images
                    var parts: [OpenAIContentPart] = []
                    
                    for content in message.content {
                        switch content {
                        case .text(let text):
                            parts.append(OpenAIContentPart(type: "text", text: text, imageUrl: nil))
                        case .image(let imageContent):
                            if let imageUrl = imageContent.url {
                                // URL-based image
                                parts.append(OpenAIContentPart(
                                    type: "image_url",
                                    text: nil,
                                    imageUrl: OpenAIImageURL(url: imageUrl.absoluteString, detail: nil)
                                ))
                            } else if let imageData = imageContent.data {
                                // Data-based image - convert to base64 data URL
                                let base64String = imageData.base64EncodedString()
                                let dataUrl = "data:\(imageContent.mimeType);base64,\(base64String)"
                                parts.append(OpenAIContentPart(
                                    type: "image_url",
                                    text: nil,
                                    imageUrl: OpenAIImageURL(url: dataUrl, detail: nil)
                                ))
                            }
                        default:
                            // Skip other content types for user messages
                            break
                        }
                    }
                    
                    return OpenAIMessage(role: "user", content: .array(parts))
                } else {
                    // Text-only content
                    let textContent = message.content.compactMap { $0.textValue }.joined(separator: "\n")
                    return OpenAIMessage(role: "user", content: .text(textContent))
                }
            case .assistant:
                let textContent = message.content.compactMap { $0.textValue }.joined(separator: "\n")
                
                // Convert tool calls if present
                let openAIToolCalls = message.toolCalls?.map { toolCall in
                    // Arguments are already a JSON string in our ToolCallFunction
                    let argumentsString = toolCall.function.arguments.isEmpty ? "{}" : toolCall.function.arguments
                    
                    return OpenAIToolCall(
                        id: toolCall.id,
                        type: "function",
                        function: OpenAIFunctionCall(
                            name: toolCall.function.name,
                            arguments: argumentsString
                        )
                    )
                }
                
                // Create assistant message with tool calls
                // OpenAI accepts empty content with tool calls
                return OpenAIMessage(
                    role: "assistant",
                    content: textContent.isEmpty ? .text("") : .text(textContent),
                    toolCallId: nil,
                    toolCalls: openAIToolCalls
                )
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
    /// Following Vercel AI SDK approach: recursively unwrap schema enums to plain dictionaries.
    func convertJSONSchemaToDict(_ schema: JSONSchema, forStrictMode: Bool = false) throws -> [String: Any] {
        let dict = try convertSchemaDefinitionToDict(schema.definition, forStrictMode: forStrictMode)
        
        
        return dict
    }
    
    /// Recursively convert SchemaDefinition to dictionary, unwrapping nested schemas
    private func convertSchemaDefinitionToDict(_ definition: SchemaDefinition, forStrictMode: Bool = false) throws -> [String: Any] {
        var dict: [String: Any] = [:]
        
        // Basic properties
        dict["type"] = definition.type.rawValue
        
        if let properties = definition.properties {
            var propertiesDict: [String: Any] = [:]
            for (key, schema) in properties {
                propertiesDict[key] = try convertJSONSchemaToDict(schema, forStrictMode: forStrictMode)
            }
            dict["properties"] = propertiesDict
            
            // For OpenAI strict mode, ALL properties must be in the required array
            if forStrictMode && definition.type == .object {
                dict["required"] = Array(properties.keys).sorted()
            }
        }
        
        if let items = definition.items {
            dict["items"] = try convertJSONSchemaToDict(items, forStrictMode: forStrictMode)
        }
        
        // Only set required if not already set by strict mode above
        if dict["required"] == nil, let required = definition.required {
            dict["required"] = required
        }
        
        if let enumValues = definition.enum {
            dict["enum"] = try enumValues.map { try convertJSONSchemaValueToAny($0) }
        }
        
        if let const = definition.const {
            dict["const"] = try convertJSONSchemaValueToAny(const)
        }
        
        // Optional string properties
        if let title = definition.title { dict["title"] = title }
        if let description = definition.description { dict["description"] = description }
        if let format = definition.format { dict["format"] = format }
        if let pattern = definition.pattern { dict["pattern"] = pattern }
        
        // Optional numeric properties
        if let minimum = definition.minimum { dict["minimum"] = minimum }
        if let maximum = definition.maximum { dict["maximum"] = maximum }
        if let exclusiveMinimum = definition.exclusiveMinimum { dict["exclusiveMinimum"] = exclusiveMinimum }
        if let exclusiveMaximum = definition.exclusiveMaximum { dict["exclusiveMaximum"] = exclusiveMaximum }
        
        // Optional integer properties
        if let minLength = definition.minLength { dict["minLength"] = minLength }
        if let maxLength = definition.maxLength { dict["maxLength"] = maxLength }
        if let minItems = definition.minItems { dict["minItems"] = minItems }
        if let maxItems = definition.maxItems { dict["maxItems"] = maxItems }
        if let minProperties = definition.minProperties { dict["minProperties"] = minProperties }
        if let maxProperties = definition.maxProperties { dict["maxProperties"] = maxProperties }
        
        // Optional boolean properties
        if let uniqueItems = definition.uniqueItems { dict["uniqueItems"] = uniqueItems }
        
        // Additional properties - ensure proper boolean encoding
        if let additionalProperties = definition.additionalProperties {
            switch additionalProperties {
            case .boolean(let value):
                // Explicitly ensure boolean is not encoded as integer
                dict["additionalProperties"] = value ? true : false
            case .schema(let schema):
                dict["additionalProperties"] = try convertJSONSchemaToDict(schema, forStrictMode: forStrictMode)
            }
        } else if definition.type == .object {
            // For structured outputs, OpenAI requires additionalProperties to be explicitly false
            dict["additionalProperties"] = false
        }
        
        // Schema composition
        if let oneOf = definition.oneOf {
            dict["oneOf"] = try oneOf.map { try convertJSONSchemaToDict($0, forStrictMode: forStrictMode) }
        }
        if let anyOf = definition.anyOf {
            dict["anyOf"] = try anyOf.map { try convertJSONSchemaToDict($0, forStrictMode: forStrictMode) }
        }
        if let allOf = definition.allOf {
            dict["allOf"] = try allOf.map { try convertJSONSchemaToDict($0, forStrictMode: forStrictMode) }
        }
        if let not = definition.not {
            dict["not"] = try convertJSONSchemaToDict(not, forStrictMode: forStrictMode)
        }
        
        if let examples = definition.examples {
            dict["examples"] = try examples.map { try convertJSONSchemaValueToAny($0) }
        }
        
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
    
    /// Convert TranscriptionProviderRequest to OpenAI transcription API format.
    func convertToOpenAITranscriptionRequest(_ request: TranscriptionProviderRequest) async throws -> OpenAITranscriptionRequest {
        // Get audio data
        let audioData = try await request.audio.audioData()
        
        // Determine filename and mime type from audio input
        let (filename, mimeType) = getAudioFileInfo(for: request.audio)
        
        // Check if this model supports timestamps
        let supportsTimestamps = modelSupportsTimestamps(request.modelId)
        
        // For models that don't support timestamps, exclude timestamp-related parameters
        let timestampGranularities: [String]?
        let responseFormat: String
        
        if supportsTimestamps {
            // Get timestampGranularities from provider options (OpenAI-specific)
            timestampGranularities = extractTimestampGranularitiesFromProviderOptions(request.providerOptions)
            responseFormat = request.configuration.responseFormat?.rawValue ?? "json"
        } else {
            // Models like gpt-4o-mini-transcribe don't support timestamps
            timestampGranularities = nil
            
            // If verbose_json was requested but timestamps aren't supported, use regular json
            let requestedFormat = request.configuration.responseFormat?.rawValue ?? "json"
            responseFormat = (requestedFormat == "verbose_json") ? "json" : requestedFormat
        }
        
        return OpenAITranscriptionRequest(
            file: audioData,
            filename: filename,
            mimeType: mimeType,
            model: request.modelId,
            language: request.configuration.language,
            prompt: request.configuration.prompt,
            responseFormat: responseFormat,
            temperature: request.configuration.temperature,
            timestampGranularities: timestampGranularities
        )
    }
    
    /// Check if a transcription model supports timestamp features.
    func modelSupportsTimestamps(_ modelId: String) -> Bool {
        // Based on OpenAI documentation, gpt-4o-mini-transcribe doesn't support timestamps
        // while whisper-1 and other models do
        switch modelId.lowercased() {
        case "gpt-4o-mini-transcribe":
            return false
        default:
            return true
        }
    }
    
    /// Extract timestampGranularities from provider options following Vercel AI SDK pattern.
    func extractTimestampGranularitiesFromProviderOptions(_ providerOptions: [String: String]?) -> [String]? {
        guard let providerOptions = providerOptions,
              let openaiOptions = providerOptions["openai"],
              let timestampGranularitiesString = parseProviderOptionValue(openaiOptions, key: "timestampGranularities") else {
            return nil
        }
        
        // Parse the timestamp granularities string (could be comma-separated or JSON array)
        if timestampGranularitiesString.hasPrefix("[") {
            // JSON array format: ["word", "segment"]
            return parseJSONArrayString(timestampGranularitiesString)
        } else {
            // Comma-separated format: "word,segment" 
            return timestampGranularitiesString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
    
    /// Parse a provider option value from a string representation.
    private func parseProviderOptionValue(_ optionString: String, key: String) -> String? {
        // For now, assume simple key=value format within the option string
        // In a real implementation, this might be JSON parsing
        let components = optionString.components(separatedBy: "=")
        if components.count == 2 && components[0] == key {
            return components[1]
        }
        return nil
    }
    
    /// Parse a JSON array string into an array of strings.
    private func parseJSONArrayString(_ jsonString: String) -> [String]? {
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return nil
        }
        return array
    }
    
    /// Get filename and MIME type information for audio input.
    func getAudioFileInfo(for audio: AudioInput) -> (filename: String, mimeType: String) {
        switch audio {
        case .fileURL(let url):
            let filename = url.lastPathComponent
            let mimeType = mimeTypeForFileExtension(url.pathExtension)
            return (filename, mimeType)
        case .url(let url):
            let filename = url.lastPathComponent.isEmpty ? "audio.mp3" : url.lastPathComponent
            let mimeType = mimeTypeForFileExtension(URL(string: filename)?.pathExtension ?? "mp3")
            return (filename, mimeType)
        case .data(_):
            return ("audio.mp3", "audio/mpeg")
        case .base64String(_):
            return ("audio.mp3", "audio/mpeg")
        }
    }
    
    /// Get MIME type for file extension.
    func mimeTypeForFileExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        case "webm":
            return "audio/webm"
        default:
            return "audio/mpeg"
        }
    }
    
    /// Create multipart form data for transcription request.
    func createTranscriptionFormData(_ request: OpenAITranscriptionRequest, boundary: String) async throws -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        
        // Helper function to add form field
        func addFormField(name: String, value: String) {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }
        
        // Add file data
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(request.filename)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: \(request.mimeType)\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(request.file)
        body.append(lineBreak.data(using: .utf8)!)
        
        // Add model
        addFormField(name: "model", value: request.model)
        
        // Add optional fields
        if let language = request.language {
            addFormField(name: "language", value: language)
        }
        
        if let prompt = request.prompt {
            addFormField(name: "prompt", value: prompt)
        }
        
        addFormField(name: "response_format", value: request.responseFormat)
        
        if let temperature = request.temperature {
            addFormField(name: "temperature", value: String(temperature))
        }
        
        if let granularities = request.timestampGranularities, !granularities.isEmpty {
            for granularity in granularities {
                addFormField(name: "timestamp_granularities[]", value: granularity)
            }
        }
        
        // Close boundary
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        
        return body
    }
    
    /// Parse OpenAI error response.
    func parseOpenAIError(_ data: Data) throws -> String {
        if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
            return errorResponse.error.message
        } else if let errorString = String(data: data, encoding: .utf8) {
            return errorString
        } else {
            return "Unknown OpenAI error"
        }
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
    let responseFormat: OpenAIResponseFormat?
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
        case responseFormat = "response_format"
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
    case array([OpenAIContentPart])
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .array(let parts):
            try container.encode(parts)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let array = try? container.decode([OpenAIContentPart].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid content format")
            )
        }
    }
}

/// OpenAI content part for multi-modal messages.
private struct OpenAIContentPart: Codable {
    let type: String
    let text: String?
    let imageUrl: OpenAIImageURL?
    
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }
}

/// OpenAI image URL structure.
private struct OpenAIImageURL: Codable {
    let url: String
    let detail: String?
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
    let strict: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name, description, parameters, strict
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(strict, forKey: .strict)
        
        try container.encode(AnyCodable(parameters), forKey: .parameters)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        strict = try container.decodeIfPresent(Bool.self, forKey: .strict)
        
        let parametersValue = try container.decode(AnyCodable.self, forKey: .parameters)
        parameters = parametersValue.value as? [String: Any] ?? [:]
    }
    
    init(name: String, description: String?, parameters: [String: Any], strict: Bool? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
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

/// OpenAI response format for structured output.
private struct OpenAIResponseFormat: Codable {
    let type: String
    let jsonSchema: OpenAIJSONSchema?
    
    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

/// OpenAI JSON schema structure for structured output.
private struct OpenAIJSONSchema: Codable {
    let name: String
    let schema: [String: Any]
    let description: String?
    let strict: Bool?
    
    enum CodingKeys: String, CodingKey {
        case name, schema, description, strict
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(strict, forKey: .strict)
        
        try container.encode(AnyCodable(schema), forKey: .schema)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        strict = try container.decodeIfPresent(Bool.self, forKey: .strict)
        
        let schemaValue = try container.decode(AnyCodable.self, forKey: .schema)
        schema = schemaValue.value as? [String: Any] ?? [:]
    }
    
    init(name: String, schema: [String: Any], description: String? = nil, strict: Bool? = nil) {
        self.name = name
        self.schema = schema
        self.description = description
        self.strict = strict
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

// MARK: - OpenAI Transcription API Types

/// OpenAI transcription request structure (for multipart form data).
private struct OpenAITranscriptionRequest {
    let file: Data
    let filename: String
    let mimeType: String
    let model: String
    let language: String?
    let prompt: String?
    let responseFormat: String
    let temperature: Double?
    let timestampGranularities: [String]?
}

/// OpenAI transcription response structure.
private struct OpenAITranscriptionResponse: Codable {
    let text: String
    let language: String?
    let duration: Double?
    let segments: [OpenAITranscriptionSegment]?
    let task: String?
    let model: String?
}

/// OpenAI transcription segment structure.
private struct OpenAITranscriptionSegment: Codable {
    let id: Int
    let seek: Int
    let start: Double
    let end: Double
    let text: String
    let tokens: [Int]
    let temperature: Double
    let avgLogprob: Double
    let compressionRatio: Double
    let noSpeechProb: Double
    
    enum CodingKeys: String, CodingKey {
        case id, seek, start, end, text, tokens, temperature
        case avgLogprob = "avg_logprob"
        case compressionRatio = "compression_ratio"
        case noSpeechProb = "no_speech_prob"
    }
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