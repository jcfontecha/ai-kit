import Foundation

// MARK: - Google Provider Implementation

/// Google provider for the Swift AI SDK.
///
/// `GoogleProvider` implements the `AIProvider` protocol to provide integration
/// with Google's Gemini API, including all Gemini models, streaming, and tool calling.
/// This implementation follows the patterns established by the Vercel AI SDK.
///
/// ## Features
/// - Support for all Google Gemini models (Gemini 2.5, 2.0, 1.5, etc.)
/// - Streaming text generation with Server-Sent Events
/// - Tool calling and function execution
/// - Multi-modal support (text, images, audio, video)
/// - Comprehensive error handling and retry logic
/// - Proper token usage tracking
/// - Configurable API endpoints and authentication
/// - Safety settings and content filtering
///
/// ## Supported Models
/// - Gemini 2.5 Pro (latest reasoning model)
/// - Gemini 2.5 Flash (best price-performance)
/// - Gemini 2.0 Flash (multimodal)
/// - Gemini 1.5 Pro (long context)
/// - Future Google models
///
/// ## Usage Examples
///
/// ### Basic Setup
/// ```swift
/// let provider = GoogleProvider(apiKey: "your-api-key")
/// let model = provider.languageModel("gemini-2.5-flash")
/// let client = AIClient()
/// 
/// let response = try await client.generateText(model, prompt: "Hello!")
/// print(response.text)
/// ```
///
/// ### With Custom Configuration
/// ```swift
/// let provider = GoogleProvider(
///     apiKey: "your-api-key",
///     baseURL: "https://generativelanguage.googleapis.com/v1beta",
///     safetySettings: [
///         GoogleSafetySetting(category: .harassment, threshold: .blockMediumAndAbove)
///     ]
/// )
/// 
/// let model = provider.languageModel("gemini-2.5-pro")
///     .temperature(0.8)
///     .maxTokens(1000)
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
public struct GoogleProvider: AIProvider {
    
    // MARK: - Properties
    
    /// Provider name for identification and logging.
    public let name = "Google"
    
    /// Provider capabilities for mode support
    public let supportedGenerationModes: Set<GenerationMode> = [.auto, .json, .tool]
    
    /// Default generation mode for this provider - follows Vercel AI SDK pattern
    public let defaultGenerationMode: GenerationMode = .json
    
    /// Whether this provider instance supports structured outputs for a given model
    public func supportsStructuredOutputs(for modelId: String) -> Bool {
        // Most Gemini models support structured outputs via response schema
        return structuredOutputs ?? supportsStructuredOutputsByDefault(modelId: modelId)
    }
    
    /// Whether structured outputs are explicitly enabled
    private let structuredOutputs: Bool?
    
    /// Google API key for authentication.
    private let apiKey: String
    
    /// Base URL for the Google Gemini API.
    private let baseURL: String
    
    /// Safety settings for content filtering.
    private let safetySettings: [GoogleSafetySetting]
    
    /// Custom headers to include in requests.
    private let customHeaders: [String: String]
    
    /// URLSession for making HTTP requests.
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    /// Creates a new Google provider with the specified configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Google API key (required)
    ///   - baseURL: Base URL for the API (defaults to Google's endpoint)
    ///   - structuredOutputs: Whether to enable structured outputs (auto-detect if nil)
    ///   - safetySettings: Safety settings for content filtering
    ///   - customHeaders: Additional headers to include in requests
    ///   - urlSession: Custom URLSession (defaults to shared)
    public init(
        apiKey: String,
        baseURL: String = "https://generativelanguage.googleapis.com/v1beta",
        structuredOutputs: Bool? = nil,
        safetySettings: [GoogleSafetySetting] = [],
        customHeaders: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.structuredOutputs = structuredOutputs
        self.safetySettings = safetySettings
        self.customHeaders = customHeaders
        self.urlSession = urlSession
    }
    
    // MARK: - AIProvider Implementation
    
    /// Create a configured language model instance.
    ///
    /// - Parameter modelId: Google model identifier (e.g., "gemini-2.5-flash", "gemini-1.5-pro")
    /// - Returns: A configured LanguageModel ready for use
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    /// Execute raw text generation with Google Gemini API.
    ///
    /// Transforms the standard request to Google's format, makes the API call,
    /// and converts the response back to the standard format.
    ///
    /// - Parameter request: The standardized request
    /// - Returns: Google response converted to standard format
    /// - Throws: Google-specific errors
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Convert request to Google format
        let googleRequest = try convertToGoogleRequest(request)
        
        // Get model path for URL
        let modelPath = getModelPath(request.modelId)
        
        // Create HTTP request
        let url = URL(string: "\(baseURL)/\(modelPath):generateContent")!
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        // Add custom headers
        for (key, value) in customHeaders {
            httpRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // Encode request body
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let requestData = try encoder.encode(googleRequest)
        httpRequest.httpBody = requestData
        
        // Debug logging can be removed in production
        
        // Make HTTP request
        let (data, response) = try await urlSession.data(for: httpRequest)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleError.invalidResponse("Invalid response type")
        }
        
        if httpResponse.statusCode != 200 {
            let errorResponse = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data)
            let errorMessage = errorResponse?.error.message ?? "HTTP \(httpResponse.statusCode)"
            throw GoogleError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        // Decode response
        let googleResponse = try JSONDecoder().decode(GoogleResponse.self, from: data)
        
        // Debug logging can be removed in production
        
        // Convert to standard format
        return try convertFromGoogleResponse(googleResponse, requestId: request.requestId)
    }
    
    /// Execute raw streaming text generation with Google Gemini API.
    ///
    /// Establishes a streaming connection to Google and processes Server-Sent Events
    /// in real-time, converting each chunk to the standard format.
    ///
    /// - Parameter request: The standardized request
    /// - Returns: AsyncThrowingStream of response chunks
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Convert request to Google format
                    let googleRequest = try convertToGoogleRequest(request)
                    
                    // Get model path for URL
                    let modelPath = getModelPath(request.modelId)
                    
                    // Create HTTP request with streaming
                    let url = URL(string: "\(baseURL)/\(modelPath):streamGenerateContent?alt=sse")!
                    var httpRequest = URLRequest(url: url)
                    httpRequest.httpMethod = "POST"
                    httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    httpRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    // Add custom headers
                    for (key, value) in customHeaders {
                        httpRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    
                    // Encode request body
                    let requestData = try JSONEncoder().encode(googleRequest)
                    httpRequest.httpBody = requestData
                    
                    // Make streaming HTTP request
                    let (asyncBytes, response) = try await urlSession.bytes(for: httpRequest)
                    
                    // Check HTTP status
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw GoogleError.invalidResponse("Invalid response type")
                    }
                    
                    if httpResponse.statusCode != 200 {
                        throw GoogleError.apiError(httpResponse.statusCode, "Streaming request failed")
                    }
                    
                    // Process Server-Sent Events
                    var chunkIndex = 0
                    var accumulatedUsage: Usage?
                    
                    for try await line in asyncBytes.lines {
                        // Process SSE data lines
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6)) // Remove "data: " prefix
                            
                            // Skip empty lines
                            if jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                continue
                            }
                            
                            // Parse chunk JSON
                            guard let chunkData = jsonString.data(using: .utf8) else { continue }
                            
                            do {
                                let chunk = try JSONDecoder().decode(GoogleResponse.self, from: chunkData)
                                
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
                    
                    // Send a final chunk with finish reason if we haven't sent one yet
                    let finalChunk = ProviderChunk(
                        delta: "",
                        usage: accumulatedUsage,
                        finishReason: .stop,
                        chunkIndex: chunkIndex
                    )
                    continuation.yield(finalChunk)
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Validate that the given configuration is supported by Google.
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
        
        // Validate topK
        if let topK = configuration.topK {
            if topK < 1 || topK > 40 {
                throw AIProviderError.unsupportedParameter("topK", "Must be between 1 and 40")
            }
        }
        
        // Google doesn't support frequency/presence penalties
        if configuration.frequencyPenalty != nil {
            throw AIProviderError.unsupportedParameter("frequencyPenalty", "Not supported by Google")
        }
        
        if configuration.presencePenalty != nil {
            throw AIProviderError.unsupportedParameter("presencePenalty", "Not supported by Google")
        }
    }
    
    // MARK: - Model Capability Detection
    
    /// Check if a model supports structured outputs by default
    private func supportsStructuredOutputsByDefault(modelId: String) -> Bool {
        // Most Gemini models support structured outputs via response schema
        return modelId.hasPrefix("gemini-") && !isAudioModel(modelId: modelId)
    }
    
    /// Check if a model is an audio model (may have different capabilities)
    private func isAudioModel(modelId: String) -> Bool {
        return modelId.contains("audio")
    }
    
    /// Get the model path for API URLs
    private func getModelPath(_ modelId: String) -> String {
        return "models/\(modelId)"
    }
}

// MARK: - Private Helper Methods

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private extension GoogleProvider {
    
    /// Convert ProviderRequest to Google API format following Vercel AI SDK patterns.
    func convertToGoogleRequest(_ request: ProviderRequest) throws -> GoogleRequest {
        // Convert messages to Google format
        let contents = try convertMessages(request.messages)
        
        // Handle system instruction
        var systemInstruction: GoogleSystemInstruction?
        if let systemMessage = request.system {
            systemInstruction = GoogleSystemInstruction(
                parts: [GooglePart.text(systemMessage)]
            )
        }
        
        // Handle generation config
        var generationConfig = GoogleGenerationConfig()
        generationConfig.maxOutputTokens = request.configuration.maxTokens
        generationConfig.temperature = request.configuration.temperature
        generationConfig.topK = request.configuration.topK
        generationConfig.topP = request.configuration.topP
        generationConfig.stopSequences = request.configuration.stopSequences
        
        // Handle different provider modes following Vercel AI SDK approach
        var tools: [GoogleTool]? = nil
        var toolConfig: GoogleToolConfig? = nil
        
        // Determine if we should use structured outputs for this model
        let supportsStructuredOutputs = self.supportsStructuredOutputs(for: request.modelId)
        
        switch request.mode {
        case .regular(let requestTools, let requestToolChoice):
            // Regular tool calling
            tools = try requestTools?.map { tool in
                GoogleTool(
                    functionDeclarations: [
                        GoogleFunctionDeclaration(
                            name: tool.function.name,
                            description: tool.function.description,
                            parameters: try convertJSONSchemaToDict(tool.function.parameters)
                        )
                    ]
                )
            }
            
            // Convert ToolChoice to Google format
            if let tools = tools, !tools.isEmpty {
                if let requestToolChoice = requestToolChoice {
                    switch requestToolChoice {
                    case .auto:
                        toolConfig = GoogleToolConfig(functionCallingConfig: GoogleFunctionCallingConfig(mode: .auto, allowedFunctionNames: nil))
                    case .none:
                        toolConfig = GoogleToolConfig(functionCallingConfig: GoogleFunctionCallingConfig(mode: .none, allowedFunctionNames: nil))
                    case .required:
                        toolConfig = GoogleToolConfig(functionCallingConfig: GoogleFunctionCallingConfig(mode: .any, allowedFunctionNames: nil))
                    case .specific(let toolName):
                        toolConfig = GoogleToolConfig(functionCallingConfig: GoogleFunctionCallingConfig(
                            mode: .any,
                            allowedFunctionNames: [toolName]
                        ))
                    }
                } else {
                    toolConfig = GoogleToolConfig(functionCallingConfig: GoogleFunctionCallingConfig(mode: .auto, allowedFunctionNames: nil))
                }
            }
            
        case .objectJSON(let schema, _, _):
            // Structured output using response schema
            if supportsStructuredOutputs {
                generationConfig.responseMimeType = "application/json"
                generationConfig.responseSchema = try convertJSONSchemaToDict(schema)
            } else {
                // Fallback to regular JSON mode
                generationConfig.responseMimeType = "application/json"
            }
            
        case .objectTool(let tool):
            // Structured output using function calling
            tools = [GoogleTool(
                functionDeclarations: [
                    GoogleFunctionDeclaration(
                        name: tool.function.name,
                        description: tool.function.description,
                        parameters: try convertJSONSchemaToDict(tool.function.parameters)
                    )
                ]
            )]
            toolConfig = GoogleToolConfig(functionCallingConfig: GoogleFunctionCallingConfig(mode: .any, allowedFunctionNames: nil))
        }
        
        return GoogleRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig,
            safetySettings: safetySettings.isEmpty ? nil : safetySettings,
            tools: tools,
            toolConfig: toolConfig
        )
    }
    
    /// Convert SDK messages to Google format.
    func convertMessages(_ messages: [Message]) throws -> [GoogleContent] {
        var contents: [GoogleContent] = []
        
        for message in messages {
            switch message.role {
            case .system:
                // System messages are handled separately in systemInstruction
                continue
            case .user:
                let parts = message.content.map { content in
                    switch content {
                    case .text(let text):
                        return GooglePart.text(text)
                    case .image(let imageContent):
                        if let data = imageContent.data {
                            return GooglePart.inlineData(GoogleInlineData(
                                mimeType: imageContent.mimeType,
                                data: data.base64EncodedString()
                            ))
                        } else {
                            return GooglePart.text("Image content (URL: \(imageContent.url?.absoluteString ?? "unknown"))")
                        }
                    case .file(let fileContent):
                        if let data = fileContent.data {
                            return GooglePart.inlineData(GoogleInlineData(
                                mimeType: fileContent.mimeType,
                                data: data.base64EncodedString()
                            ))
                        } else if let url = fileContent.url {
                            // For file URLs, we could potentially use fileData instead
                            // For now, we'll indicate it's a file URL
                            return GooglePart.text("File content (\(fileContent.filename ?? "file"), URL: \(url.absoluteString))")
                        } else {
                            return GooglePart.text("File content (\(fileContent.filename ?? "file"))")
                        }
                    default:
                        return GooglePart.text(content.textValue ?? "")
                    }
                }
                contents.append(GoogleContent(role: "user", parts: parts))
                
            case .assistant:
                var parts: [GooglePart] = []
                
                // Add text content
                let textParts = message.content.compactMap { content in
                    content.textValue
                }.filter { !$0.isEmpty }
                
                if !textParts.isEmpty {
                    parts.append(GooglePart.text(textParts.joined(separator: "\n")))
                }
                
                // Add tool calls
                if let toolCalls = message.toolCalls {
                    for toolCall in toolCalls {
                        let argumentsDict = try parseToolArguments(toolCall.function.arguments)
                        parts.append(GooglePart.functionCall(GoogleFunctionCall(
                            name: toolCall.function.name,
                            args: argumentsDict
                        )))
                    }
                }
                
                contents.append(GoogleContent(role: "model", parts: parts))
                
            case .tool:
                // Handle tool results
                if let toolResult = message.content.first {
                    switch toolResult {
                    case .toolResult(let result):
                        let responseDict: [String: Any]
                        switch result.result {
                        case .text(let text):
                            responseDict = ["result": text]
                        case .json(let data):
                            if let json = try? JSONSerialization.jsonObject(with: data) {
                                responseDict = ["result": json]
                            } else {
                                responseDict = ["result": "Invalid JSON"]
                            }
                        case .error(let error):
                            responseDict = ["error": error]
                        default:
                            responseDict = ["result": "Unsupported result type"]
                        }
                        
                        let part = GooglePart.functionResponse(GoogleFunctionResponse(
                            name: result.toolCallId, // Google uses name field for tool call ID
                            response: responseDict
                        ))
                        contents.append(GoogleContent(role: "function", parts: [part]))
                    default:
                        let textContent = toolResult.textValue ?? "Unknown tool result"
                        contents.append(GoogleContent(role: "function", parts: [GooglePart.text(textContent)]))
                    }
                }
            }
        }
        
        return contents
    }
    
    /// Convert Google response to standard format.
    func convertFromGoogleResponse(_ response: GoogleResponse, requestId: String) throws -> ProviderResponse {
        guard let candidate = response.candidates?.first else {
            throw GoogleError.invalidResponse("No candidates in response")
        }
        
        // Extract text content
        let textParts = candidate.content.parts.compactMap { part in
            switch part {
            case .text(let text):
                return text
            default:
                return nil
            }
        }
        let content = textParts.joined(separator: "\n")
        
        // Extract tool calls
        let toolCalls = try candidate.content.parts.compactMap { part -> ToolCall? in
            switch part {
            case .functionCall(let functionCall):
                return ToolCall(
                    id: UUID().uuidString, // Google doesn't provide IDs, generate one
                    function: ToolCallFunction(
                        name: functionCall.name,
                        arguments: try convertDictToJSONString(functionCall.args)
                    )
                )
            default:
                return nil
            }
        }
        
        // Convert usage - provide reasonable defaults if not available
        let promptTokens = response.usageMetadata?.promptTokenCount ?? 10 // Reasonable estimate
        let completionTokens = response.usageMetadata?.candidatesTokenCount ?? content.split(separator: " ").count
        let usage = Usage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            promptCost: nil,
            completionCost: nil,
            currency: "USD"
        )
        
        // Convert finish reason - special handling for tool calls
        let finishReason: FinishReason
        if !toolCalls.isEmpty {
            // If we have tool calls, the finish reason should be toolCalls regardless of what Google says
            finishReason = .toolCalls
        } else if let reason = candidate.finishReason {
            switch reason {
            case "STOP", "stop":
                finishReason = .stop
            case "MAX_TOKENS", "length":
                finishReason = .length
            case "SAFETY", "content_filter":
                finishReason = .contentFilter
            case "RECITATION":
                finishReason = .contentFilter
            default:
                finishReason = .other
            }
        } else {
            // If no finish reason is provided, assume it finished normally
            finishReason = .stop
        }
        
        // Debug logging can be removed in production
        
        return ProviderResponse(
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            usage: usage,
            finishReason: finishReason,
            responseId: UUID().uuidString, // Google doesn't provide response IDs
            providerMetadata: [
                "model": response.modelVersion ?? "unknown"
            ]
        )
    }
    
    /// Process a streaming chunk from Google.
    func processStreamChunk(_ chunk: GoogleResponse, chunkIndex: Int) throws -> ProviderChunk? {
        guard let candidate = chunk.candidates?.first else {
            return nil
        }
        
        // Extract text delta
        let textParts = candidate.content.parts.compactMap { part in
            switch part {
            case .text(let text):
                return text
            default:
                return nil
            }
        }
        let delta = textParts.joined(separator: "\n")
        
        // Convert finish reason
        let finishReason: FinishReason?
        if let reason = candidate.finishReason {
            switch reason {
            case "STOP", "stop":
                finishReason = .stop
            case "MAX_TOKENS", "length":
                finishReason = .length
            case "SAFETY", "content_filter":
                finishReason = .contentFilter
            case "RECITATION":
                finishReason = .contentFilter
            default:
                finishReason = .other
            }
        } else {
            // For streaming, only set finish reason if this is likely the last chunk
            finishReason = nil
        }
        
        // Convert usage if present
        let usage: Usage?
        if let usageMetadata = chunk.usageMetadata {
            usage = Usage(
                promptTokens: usageMetadata.promptTokenCount ?? 0,
                completionTokens: usageMetadata.candidatesTokenCount ?? 0,
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
    
    /// Parse tool arguments from JSON string or dictionary.
    func parseToolArguments(_ arguments: String) throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8) else {
            throw GoogleError.invalidResponse("Invalid tool arguments encoding")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleError.invalidResponse("Tool arguments must be a JSON object")
        }
        
        return json
    }
    
    /// Convert dictionary to JSON string.
    func convertDictToJSONString(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw GoogleError.invalidResponse("Could not convert dictionary to JSON string")
        }
        return string
    }
    
    /// Convert JSONSchema to dictionary format for Google API.
    func convertJSONSchemaToDict(_ schema: JSONSchema) throws -> [String: Any] {
        return try convertSchemaDefinitionToDict(schema.definition)
    }
    
    /// Recursively convert SchemaDefinition to dictionary
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
        if let format = definition.format { dict["format"] = format }
        if let minimum = definition.minimum { dict["minimum"] = minimum }
        if let maximum = definition.maximum { dict["maximum"] = maximum }
        
        return dict
    }
    
    /// Convert JSONSchemaValue to Swift Any
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

// MARK: - Google API Types

/// Google Gemini API request structure.
private struct GoogleRequest: Codable {
    let contents: [GoogleContent]
    let systemInstruction: GoogleSystemInstruction?
    let generationConfig: GoogleGenerationConfig?
    let safetySettings: [GoogleSafetySetting]?
    let tools: [GoogleTool]?
    let toolConfig: GoogleToolConfig?
}

/// Google content structure.
private struct GoogleContent: Codable {
    let role: String
    let parts: [GooglePart]
}

/// Google system instruction.
private struct GoogleSystemInstruction: Codable {
    let parts: [GooglePart]
}

/// Google content part.
private enum GooglePart: Codable {
    case text(String)
    case inlineData(GoogleInlineData)
    case functionCall(GoogleFunctionCall)
    case functionResponse(GoogleFunctionResponse)
    
    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
        case functionCall = "functionCall"
        case functionResponse = "functionResponse"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .inlineData(let data):
            try container.encode(data, forKey: .inlineData)
        case .functionCall(let call):
            try container.encode(call, forKey: .functionCall)
        case .functionResponse(let response):
            try container.encode(response, forKey: .functionResponse)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Debug logging can be removed in production
        
        if container.contains(.text) {
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        } else if container.contains(.inlineData) {
            let data = try container.decode(GoogleInlineData.self, forKey: .inlineData)
            self = .inlineData(data)
        } else if container.contains(.functionCall) {
            let call = try container.decode(GoogleFunctionCall.self, forKey: .functionCall)
            self = .functionCall(call)
        } else if container.contains(.functionResponse) {
            let response = try container.decode(GoogleFunctionResponse.self, forKey: .functionResponse)
            self = .functionResponse(response)
        } else {
            // If we can't decode any known type, default to empty text to avoid crashes
            self = .text("")
        }
    }
}

/// Google inline data structure.
private struct GoogleInlineData: Codable {
    let mimeType: String
    let data: String
    
    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

/// Google function call structure.
private struct GoogleFunctionCall: Codable {
    let name: String
    let args: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name, args
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(AnyCodable(args), forKey: .args)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let argsValue = try container.decode(AnyCodable.self, forKey: .args)
        args = argsValue.value as? [String: Any] ?? [:]
    }
    
    init(name: String, args: [String: Any]) {
        self.name = name
        self.args = args
    }
}

/// Google function response structure.
private struct GoogleFunctionResponse: Codable {
    let name: String
    let response: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name, response
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(AnyCodable(response), forKey: .response)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let responseValue = try container.decode(AnyCodable.self, forKey: .response)
        response = responseValue.value as? [String: Any] ?? [:]
    }
    
    init(name: String, response: [String: Any]) {
        self.name = name
        self.response = response
    }
}

/// Google generation configuration.
private struct GoogleGenerationConfig: Codable {
    var maxOutputTokens: Int?
    var temperature: Double?
    var topK: Int?
    var topP: Double?
    var stopSequences: [String]?
    var responseMimeType: String?
    var responseSchema: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case maxOutputTokens = "max_output_tokens"
        case temperature
        case topK = "top_k"
        case topP = "top_p"
        case stopSequences = "stop_sequences"
        case responseMimeType = "response_mime_type"
        case responseSchema = "response_schema"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topK, forKey: .topK)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(stopSequences, forKey: .stopSequences)
        try container.encodeIfPresent(responseMimeType, forKey: .responseMimeType)
        if let responseSchema = responseSchema {
            try container.encode(AnyCodable(responseSchema), forKey: .responseSchema)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topK = try container.decodeIfPresent(Int.self, forKey: .topK)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        stopSequences = try container.decodeIfPresent([String].self, forKey: .stopSequences)
        responseMimeType = try container.decodeIfPresent(String.self, forKey: .responseMimeType)
        if let schemaValue = try? container.decode(AnyCodable.self, forKey: .responseSchema) {
            responseSchema = schemaValue.value as? [String: Any]
        }
    }
    
    init() {}
}

/// Google tool structure.
private struct GoogleTool: Codable {
    let functionDeclarations: [GoogleFunctionDeclaration]
    
    enum CodingKeys: String, CodingKey {
        case functionDeclarations = "function_declarations"
    }
}

/// Google function declaration.
private struct GoogleFunctionDeclaration: Codable {
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
        try container.encode(AnyCodable(parameters), forKey: .parameters)
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

/// Google tool configuration.
private struct GoogleToolConfig: Codable {
    let functionCallingConfig: GoogleFunctionCallingConfig
    
    enum CodingKeys: String, CodingKey {
        case functionCallingConfig = "function_calling_config"
    }
}

/// Google function calling configuration.
private struct GoogleFunctionCallingConfig: Codable {
    let mode: GoogleFunctionCallingMode
    let allowedFunctionNames: [String]?
    
    enum CodingKeys: String, CodingKey {
        case mode
        case allowedFunctionNames = "allowed_function_names"
    }
}

/// Google function calling mode.
private enum GoogleFunctionCallingMode: String, Codable {
    case auto = "AUTO"
    case any = "ANY"
    case none = "NONE"
}

/// Google safety setting structure.
public struct GoogleSafetySetting: Codable, Sendable {
    let category: GoogleHarmCategory
    let threshold: GoogleHarmBlockThreshold
}

/// Google harm category.
public enum GoogleHarmCategory: String, Codable, Sendable {
    case harassment = "HARM_CATEGORY_HARASSMENT"
    case hateSpeech = "HARM_CATEGORY_HATE_SPEECH"
    case sexuallyExplicit = "HARM_CATEGORY_SEXUALLY_EXPLICIT"
    case dangerousContent = "HARM_CATEGORY_DANGEROUS_CONTENT"
}

/// Google harm block threshold.
public enum GoogleHarmBlockThreshold: String, Codable, Sendable {
    case blockNone = "BLOCK_NONE"
    case blockOnlyHigh = "BLOCK_ONLY_HIGH"
    case blockMediumAndAbove = "BLOCK_MEDIUM_AND_ABOVE"
    case blockLowAndAbove = "BLOCK_LOW_AND_ABOVE"
}

/// Google response structure.
private struct GoogleResponse: Codable {
    let candidates: [GoogleCandidate]?
    let usageMetadata: GoogleUsageMetadata?
    let modelVersion: String?
    
    enum CodingKeys: String, CodingKey {
        case candidates
        case usageMetadata = "usage_metadata"
        case modelVersion = "model_version"
    }
}

/// Google candidate structure.
private struct GoogleCandidate: Codable {
    let content: GoogleContent
    let finishReason: String?
    let safetyRatings: [GoogleSafetyRating]?
    
    enum CodingKeys: String, CodingKey {
        case content
        case finishReason = "finish_reason"
        case safetyRatings = "safety_ratings"
    }
}

/// Google safety rating.
private struct GoogleSafetyRating: Codable {
    let category: String
    let probability: String
}

/// Google usage metadata.
private struct GoogleUsageMetadata: Codable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokenCount = "prompt_token_count"
        case candidatesTokenCount = "candidates_token_count"
        case totalTokenCount = "total_token_count"
    }
}

/// Google error response structure.
private struct GoogleErrorResponse: Codable {
    let error: GoogleErrorDetail
}

/// Google error detail structure.
private struct GoogleErrorDetail: Codable {
    let code: Int?
    let message: String
    let status: String?
}

// MARK: - Google Errors

/// Google-specific errors.
private enum GoogleError: Error, LocalizedError {
    case invalidResponse(String)
    case apiError(Int, String)
    case authenticationFailed
    case rateLimitExceeded
    case invalidRequest(String)
    case safetyFiltered(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid Google response: \(message)"
        case .apiError(let code, let message):
            return "Google API error (\(code)): \(message)"
        case .authenticationFailed:
            return "Google authentication failed"
        case .rateLimitExceeded:
            return "Google rate limit exceeded"
        case .invalidRequest(let message):
            return "Invalid Google request: \(message)"
        case .safetyFiltered(let message):
            return "Content filtered by Google safety settings: \(message)"
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