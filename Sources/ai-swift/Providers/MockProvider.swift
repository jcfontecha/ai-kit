import Foundation

// MARK: - Mock Provider Implementation

/// Mock provider for testing and development.
///
/// `MockProvider` is a complete implementation of the `AIProvider` protocol that
/// provides realistic mock responses without making actual API calls. It's designed
/// for testing, development, and demonstration purposes.
///
/// ## Features
/// - Realistic mock responses with configurable behavior
/// - Streaming support with simulated delays
/// - Tool calling simulation
/// - Usage information tracking
/// - Error simulation capabilities
/// - Support for all standard model parameters
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// let provider = MockProvider(apiKey: "mock-key")
/// let model = provider.languageModel("mock-gpt-4")
/// let client = AIClient()
/// 
/// let response = try await client.generateText(model, prompt: "Hello!")
/// print(response.text) // "Mock response to: Hello!"
/// ```
///
/// ### With Configuration
/// ```swift
/// let model = provider.languageModel("mock-claude")
///     .temperature(0.8)
///     .maxTokens(150)
/// 
/// let response = try await client.generateText(model, prompt: "Write a story")
/// ```
///
/// ### Streaming
/// ```swift
/// let stream = client.streamText(model, prompt: "Count to 10")
/// for try await chunk in stream {
///     print(chunk.delta, terminator: "")
/// }
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct MockProvider: AIProvider {
    
    // MARK: - Properties
    
    /// Provider name for identification and logging.
    public let name = "Mock Provider"
    
    /// Provider capabilities for mode support
    public let supportedGenerationModes: Set<GenerationMode> = [.auto, .json, .tool]
    
    /// Default generation mode for this provider
    public let defaultGenerationMode: GenerationMode = .json
    
    /// Mock API key (not used for actual authentication).
    private let apiKey: String
    
    /// Configuration for mock behavior.
    private let configuration: MockConfiguration
    
    // MARK: - Initialization
    
    /// Creates a new mock provider with the specified API key and configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Mock API key (any string is accepted)
    ///   - configuration: Configuration for mock behavior
    public init(apiKey: String = "mock-api-key", configuration: MockConfiguration = .default) {
        self.apiKey = apiKey
        self.configuration = configuration
    }
    
    // MARK: - AIProvider Implementation
    
    /// Create a configured language model instance.
    ///
    /// The mock provider accepts any model ID and creates a working model instance.
    /// Common mock model IDs include "mock-gpt-4", "mock-claude-3", etc.
    ///
    /// - Parameter modelId: Any model identifier
    /// - Returns: A configured LanguageModel ready for use
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    /// Execute raw text generation with mock responses.
    ///
    /// Generates realistic mock responses based on the input prompt and configuration.
    /// The response includes simulated token usage and respects configuration parameters.
    ///
    /// - Parameter request: The provider request to process
    /// - Returns: A mock response with generated content
    /// - Throws: Simulated errors based on configuration
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Simulate API delay if configured
        if let delay = configuration.responseDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Check for specific error model IDs (for testing error handling)
        if request.modelId == "malformed-json-model" {
            throw AIGenerationError.jsonParseError(
                text: "{\"name\": \"Test Product\", \"price\": 99.99, \"category\": \"Electronics\"",
                parseError: NSError(domain: "JSONParseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected end of JSON input"])
            )
        }
        
        if request.modelId == "invalid-schema-model" {
            throw AIGenerationError.schemaValidationError(
                objectData: "{\"name\": \"Test Product\", \"price\": -5.0, \"category\": \"\"}",
                validationErrors: ["price must be >= 0", "category cannot be empty", "missing required field: id"]
            )
        }
        
        if request.modelId == "no-object-model" {
            let usage = generateMockUsage(prompt: "Generate a product", response: "Sorry, I cannot generate that object right now.")
            throw AIGenerationError.noObjectGenerated(
                text: "Sorry, I cannot generate that object right now. Please try again later.",
                finishReason: .stop,
                usage: usage
            )
        }
        
        // Check for simulated errors
        if let errorRate = configuration.errorRate, Double.random(in: 0...1) < errorRate {
            throw AIProviderError.serviceUnavailable("Simulated error for testing")
        }
        
        // Check if conversation has tool results (indicates this is a follow-up call)
        let hasToolResults = request.messages.contains { $0.role == .tool }
        
        if hasToolResults {
            // Generate synthesized response based on tool results
            let toolResults = request.messages.filter { $0.role == .tool }
            var synthesizedResponse = "Based on the tool results, here's what I found:\n\n"
            
            for toolMessage in toolResults {
                if let firstContent = toolMessage.content.first {
                    switch firstContent {
                    case .toolResult(let toolResult):
                        // Extract text from tool result
                        switch toolResult.result {
                        case .text(let textContent):
                            // Try to parse weather data if it looks like JSON
                            if textContent.contains("temperature") && textContent.contains("location") {
                                synthesizedResponse += "The weather information shows current conditions with temperature and humidity data. "
                            } else {
                                synthesizedResponse += "Tool executed successfully with results. "
                            }
                        case .json(_):
                            synthesizedResponse += "Tool returned JSON data. "
                        case .error(_):
                            synthesizedResponse += "Tool execution encountered an error. "
                        case .image(_):
                            synthesizedResponse += "Tool returned image data. "
                        case .file(_):
                            synthesizedResponse += "Tool returned file data. "
                        case .data(_, mimeType: let mimeType):
                            synthesizedResponse += "Tool returned binary data (\(mimeType)). "
                        }
                        
                    case .text(let textContent):
                        if textContent.contains("temperature") && textContent.contains("location") {
                            synthesizedResponse += "The weather information shows current conditions with temperature and humidity data. "
                        } else {
                            synthesizedResponse += "Tool executed successfully with results. "
                        }
                        
                    default:
                        synthesizedResponse += "Tool executed with unknown content type. "
                    }
                }
            }
            
            synthesizedResponse += "This information should help answer your question."
            
            let usage = generateMockUsage(prompt: "tool synthesis", response: synthesizedResponse)
            
            return ProviderResponse(
                content: synthesizedResponse,
                usage: usage,
                finishReason: .stop,
                providerMetadata: [
                    "mock_provider": "true",
                    "model_id": request.modelId,
                    "synthesized_from_tools": "true"
                ]
            )
        }
        
        // Generate mock response based on the last user message
        let userMessage = request.messages.last { $0.role == .user }
        let prompt = userMessage?.content.first?.textValue ?? "unknown input"
        
        // Handle structured output based on provider mode
        switch request.mode {
        case .objectJSON(let schema, let name, let description):
            return try generateMockJSONResponse(for: request.modelId, prompt: prompt, schema: schema, name: name, description: description)
        case .objectTool(let tool):
            return try generateMockToolResponse(for: request.modelId, prompt: prompt, tool: tool)
        case .regular(_, _):
            // Continue with regular flow, handle tools if present
            break
        }
        
        // Check if we should simulate tool calls
        if let tools = request.tools, !tools.isEmpty, configuration.supportsTools {
            // Simulate tool error scenarios for testing
            if prompt.lowercased().contains("no such tool") {
                throw AIGenerationError.noSuchTool(
                    toolName: "non_existent_tool",
                    availableTools: tools.map { $0.function.name }
                )
            }
            
            if prompt.lowercased().contains("invalid arguments") {
                throw AIGenerationError.invalidToolArguments(
                    toolName: "get_weather",
                    toolArgs: "{\"invalid\": \"json\", \"missing_required_field",
                    cause: NSError(domain: "JSONError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Malformed JSON"])
                )
            }
            
            if prompt.lowercased().contains("tool execution error") {
                throw AIGenerationError.toolExecutionError(
                    toolName: "get_weather",
                    toolArgs: "{\"location\": \"San Francisco, CA\"}",
                    toolCallId: "tool_call_12345",
                    cause: NSError(domain: "WeatherAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Weather service unavailable"])
                )
            }
            
            // Simulate tool calling for weather queries
            if prompt.lowercased().contains("weather") {
                if tools.contains(where: { $0.function.name == "get_weather" }) {
                    let toolCall = ToolCall(
                        id: "tool_call_\(UUID().uuidString.prefix(8))",
                        function: try ToolCallFunction(
                            name: "get_weather",
                            arguments: ["location": "San Francisco, CA", "unit": "celsius"]
                        )
                    )
                    
                    let usage = generateMockUsage(prompt: prompt, response: "I'll get the weather for you.")
                    
                    return ProviderResponse(
                        content: "I'll check the weather for you.",
                        toolCalls: [toolCall],
                        usage: usage,
                        finishReason: .toolCalls,
                        providerMetadata: [
                            "mock_provider": "true",
                            "model_id": request.modelId,
                            "prompt_length": "\(prompt.count)",
                            "tool_calls_simulated": "true"
                        ]
                    )
                }
            }
        }
        
        // Regular text response
        let responseText = generateMockResponse(for: prompt, configuration: request.configuration)
        let usage = generateMockUsage(prompt: prompt, response: responseText)
        
        return ProviderResponse(
            content: responseText,
            usage: usage,
            finishReason: .stop,
            providerMetadata: [
                "mock_provider": "true",
                "model_id": request.modelId,
                "prompt_length": "\(prompt.count)"
            ]
        )
    }
    
    /// Execute raw streaming text generation with mock chunks.
    ///
    /// Provides realistic streaming simulation with configurable chunk sizes and delays.
    /// Useful for testing streaming UI components and error handling.
    ///
    /// - Parameter request: The provider request to process
    /// - Returns: AsyncThrowingStream of mock response chunks
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Simulate API delay
                    if let delay = configuration.responseDelay {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    
                    // Check for simulated errors
                    if let errorRate = configuration.errorRate, Double.random(in: 0...1) < errorRate {
                        throw AIProviderError.serviceUnavailable("Simulated streaming error")
                    }
                    
                    // Generate mock response
                    let userMessage = request.messages.last { $0.role == .user }
                    let prompt = userMessage?.content.first?.textValue ?? "unknown input"
                    
                    // Check if we should simulate streaming tool calls first
                    if let tools = request.tools, !tools.isEmpty, configuration.supportsTools {
                        if prompt.lowercased().contains("weather") || prompt.lowercased().contains("tool streaming") {
                            try await streamToolCallsAndText(
                                continuation: continuation,
                                prompt: prompt,
                                tools: tools,
                                modelId: request.modelId
                            )
                            return
                        }
                    }
                    
                    // Handle object JSON streaming differently
                    let responseText: String
                    if case .objectJSON(let schema, let name, let description) = request.mode {
                        // Get JSON response for object streaming
                        let jsonResponse = try generateMockJSONResponse(for: request.modelId, prompt: prompt, schema: schema, name: name, description: description)
                        responseText = jsonResponse.content
                    } else {
                        responseText = generateMockResponse(for: prompt, configuration: request.configuration)
                    }
                    
                    // Split response for streaming
                    let streamChunks: [String]
                    if case .objectJSON = request.mode {
                        // For JSON, stream character by character to simulate gradual JSON completion
                        streamChunks = responseText.map { String($0) }
                    } else {
                        // For regular text, stream word by word
                        let words = responseText.split(separator: " ")
                        streamChunks = words.enumerated().map { (index, word) in
                            return (index == 0 ? "" : " ") + String(word)
                        }
                    }
                    
                    for (index, chunkText) in streamChunks.enumerated() {
                        let chunk = ProviderChunk(
                            delta: chunkText,
                            usage: index == streamChunks.count - 1 ? generateMockUsage(prompt: prompt, response: responseText) : nil,
                            finishReason: index == streamChunks.count - 1 ? .stop : nil,
                            chunkIndex: index
                        )
                        
                        continuation.yield(chunk)
                        
                        // Simulate streaming delay between chunks
                        if let chunkDelay = configuration.chunkDelay {
                            try await Task.sleep(nanoseconds: UInt64(chunkDelay * 1_000_000_000))
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Validate configuration parameters (mock implementation).
    ///
    /// The mock provider accepts all configuration parameters but can be configured
    /// to simulate validation errors for testing purposes.
    ///
    /// - Parameter configuration: Configuration to validate
    /// - Throws: Simulated validation errors if configured
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // Mock validation - can be configured to throw errors for testing
        if self.configuration.strictValidation {
            if let temp = configuration.temperature, temp > 2.0 {
                throw AIProviderError.unsupportedParameter("temperature", "Mock provider supports max 2.0")
            }
            if let maxTokens = configuration.maxTokens, maxTokens > 4000 {
                throw AIProviderError.unsupportedParameter("maxTokens", "Mock provider supports max 4000 tokens")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Generate a mock response based on the input prompt.
    private func generateMockResponse(for prompt: String, configuration: ModelConfiguration) -> String {
        // Generate contextual responses based on prompt content
        let lowercasePrompt = prompt.lowercased()
        
        if lowercasePrompt.contains("weather") {
            return "I don't have access to real-time weather data in this mock environment, but I can help you understand how to get weather information."
        } else if lowercasePrompt.contains("calculate") || lowercasePrompt.contains("math") {
            return "I can help with calculations! For example, 2 + 2 = 4. What specific calculation would you like me to help with?"
        } else if lowercasePrompt.contains("story") || lowercasePrompt.contains("write") {
            return "Once upon a time, in a world where AI assistants learned to dream, there was a helpful assistant who loved to create stories and help humans with their creative endeavors."
        } else if lowercasePrompt.contains("hello") || lowercasePrompt.contains("hi") {
            return "Hello! I'm a mock AI assistant. I'm here to help demonstrate the capabilities of the Swift AI SDK."
        } else if lowercasePrompt.contains("explain") {
            return "I'd be happy to explain that topic! In this mock environment, I can provide general explanations and demonstrate how AI responses would work."
        } else {
            // Default response with prompt echo
            return "Mock response to: \(prompt)"
        }
    }
    
    /// Simulate streaming tool calls and text response for testing purposes.
    ///
    /// This method demonstrates the Vercel AI SDK pattern for streaming tool calls,
    /// including tool call start, argument streaming, and final response text.
    private func streamToolCallsAndText(
        continuation: AsyncThrowingStream<ProviderChunk, Error>.Continuation,
        prompt: String,
        tools: [Tool],
        modelId: String
    ) async throws {
        let toolCallId = "tool_call_\(UUID().uuidString.prefix(8))"
        let stepId = "step_\(UUID().uuidString.prefix(8))"
        
        // Simulate step start
        let stepStartChunk = ProviderChunk(
            delta: "",
            chunkIndex: 0,
            stepStart: ProviderChunk.StepStart(stepId: stepId)
        )
        continuation.yield(stepStartChunk)
        
        // Small delay for step start
        if let delay = configuration.chunkDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Find weather tool or use first available tool
        let weatherTool = tools.first { $0.function.name == "get_weather" } ?? tools.first!
        
        // Tool call streaming start
        let toolStartChunk = ProviderChunk(
            delta: "",
            chunkIndex: 1,
            stepId: stepId,
            toolCallStreamingStart: ProviderChunk.ToolCallStreamingStart(
                toolCallId: toolCallId,
                toolName: weatherTool.function.name
            )
        )
        continuation.yield(toolStartChunk)
        
        if let delay = configuration.chunkDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Stream tool call arguments gradually
        let argumentsJSON = "{\"location\": \"San Francisco, CA\", \"unit\": \"celsius\"}"
        let argumentChunks = argumentsJSON.map { String($0) }
        
        for (index, argChunk) in argumentChunks.enumerated() {
            let toolDeltaChunk = ProviderChunk(
                delta: "",
                chunkIndex: index + 2,
                stepId: stepId,
                toolCallDelta: ProviderChunk.ToolCallDelta(
                    toolCallId: toolCallId,
                    toolName: weatherTool.function.name,
                    argsTextDelta: argChunk
                )
            )
            continuation.yield(toolDeltaChunk)
            
            if let delay = configuration.chunkDelay {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000 / 2)) // Faster for args
            }
        }
        
        // Complete tool call (atomic)
        let completeToolCall = ToolCall(
            id: toolCallId,
            function: try ToolCallFunction(
                name: weatherTool.function.name,
                arguments: ["location": "San Francisco, CA", "unit": "celsius"]
            )
        )
        
        let toolCallChunk = ProviderChunk(
            delta: "",
            toolCall: completeToolCall,
            finishReason: .toolCalls,
            chunkIndex: argumentChunks.count + 2,
            stepId: stepId
        )
        continuation.yield(toolCallChunk)
        
        if let delay = configuration.chunkDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Simulate step finish for tool calls
        let stepFinishChunk = ProviderChunk(
            delta: "",
            chunkIndex: argumentChunks.count + 3,
            stepFinish: ProviderChunk.StepFinish(
                stepId: stepId,
                finishReason: .toolCalls,
                usage: generateMockUsage(prompt: prompt, response: "Tool call execution")
            )
        )
        continuation.yield(stepFinishChunk)
        
        if let delay = configuration.chunkDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Final text response explaining what would happen
        let responseText = "I've initiated a weather check for San Francisco, CA. In a real implementation, this would return the current weather conditions."
        let words = responseText.split(separator: " ")
        let finalStepId = "step_\(UUID().uuidString.prefix(8))"
        
        // Step start for final response
        let finalStepStartChunk = ProviderChunk(
            delta: "",
            chunkIndex: argumentChunks.count + 4,
            stepStart: ProviderChunk.StepStart(stepId: finalStepId)
        )
        continuation.yield(finalStepStartChunk)
        
        // Stream final text response
        for (index, word) in words.enumerated() {
            let wordText = (index == 0 ? "" : " ") + String(word)
            let textChunk = ProviderChunk(
                delta: wordText,
                chunkIndex: argumentChunks.count + 5 + index,
                stepId: finalStepId
            )
            continuation.yield(textChunk)
            
            if let delay = configuration.chunkDelay {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // Final step finish with complete usage
        let finalStepFinishChunk = ProviderChunk(
            delta: "",
            usage: generateMockUsage(prompt: prompt, response: responseText),
            finishReason: .stop,
            chunkIndex: argumentChunks.count + 5 + words.count,
            stepFinish: ProviderChunk.StepFinish(
                stepId: finalStepId,
                finishReason: .stop,
                usage: generateMockUsage(prompt: prompt, response: responseText)
            )
        )
        continuation.yield(finalStepFinishChunk)
        
        // IMPORTANT: Finish the stream to prevent hanging
        continuation.finish()
    }
    
    /// Generate realistic mock usage information.
    private func generateMockUsage(prompt: String, response: String) -> Usage {
        // Simulate realistic token counts (roughly 1 token per 4 characters)
        let promptTokens = max(1, prompt.count / 4)
        let completionTokens = max(1, response.count / 4)
        
        return Usage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            promptCost: Double(promptTokens) * 0.00001, // $0.01 per 1K tokens
            completionCost: Double(completionTokens) * 0.00002, // $0.02 per 1K tokens
            currency: "USD"
        )
    }
}

// MARK: - Extended Provider Implementation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension MockProvider: ExtendedAIProvider {
    
    /// Mock provider capabilities.
    public var capabilities: ProviderCapabilities {
        return ProviderCapabilities(
            supportedModels: Set([
                "mock-gpt-4", "mock-gpt-3.5", "mock-claude-3", "mock-claude-2",
                "mock-llama-2", "mock-gemini", "mock-test-model"
            ]),
            supportsStreaming: true,
            supportsTools: configuration.supportsTools,
            supportsObjectGeneration: configuration.supportsObjectGeneration,
            supportsImageInputs: configuration.supportsImageInputs,
            supportsEmbeddings: false,
            supportedParameters: Set([
                "temperature", "maxTokens", "topP", "topK",
                "frequencyPenalty", "presencePenalty", "stopSequences", "seed"
            ]),
            maxTokens: 4000,
            maxContextLength: 8000
        )
    }
    
    /// Get mock model information.
    public func modelInfo(_ modelId: String) throws -> ModelInfo {
        // Return mock model info based on model ID
        let contextLength: Int
        let maxOutputTokens: Int
        let name: String
        let description: String
        
        if modelId.contains("gpt-4") {
            name = "Mock GPT-4"
            description = "Mock version of GPT-4 for testing and development"
            contextLength = 8000
            maxOutputTokens = 4000
        } else if modelId.contains("claude") {
            name = "Mock Claude"
            description = "Mock version of Claude for testing and development"
            contextLength = 100000
            maxOutputTokens = 4000
        } else {
            name = "Mock Model"
            description = "Generic mock model for testing"
            contextLength = 4000
            maxOutputTokens = 2000
        }
        
        return ModelInfo(
            id: modelId,
            name: name,
            description: description,
            contextLength: contextLength,
            maxOutputTokens: maxOutputTokens,
            supportsTools: configuration.supportsTools,
            supportsImages: configuration.supportsImageInputs,
            knowledgeCutoff: Date(),
            pricing: ModelPricing(inputTokenCost: 0.00001, outputTokenCost: 0.00002)
        )
    }
    
    /// Check if a model is supported (all models are supported in mock).
    public func supportsModel(_ modelId: String) -> Bool {
        return true // Mock provider supports any model ID
    }
    
    /// Generate mock JSON response for object generation requests
    private func generateMockJSONResponse(for modelId: String, prompt: String, schema: JSONSchema? = nil, name: String? = nil, description: String? = nil) throws -> ProviderResponse {
        
        // Handle enum generation case - return simple string value, not JSON
        if let name = name, name == "enum_value" {
            // For enum generation, return just the enum value based on prompt sentiment
            let enumValue: String
            if prompt.lowercased().contains("love") || prompt.lowercased().contains("great") || prompt.lowercased().contains("awesome") {
                enumValue = "positive"
            } else if prompt.lowercased().contains("hate") || prompt.lowercased().contains("terrible") || prompt.lowercased().contains("awful") {
                enumValue = "negative"
            } else {
                enumValue = "neutral"
            }
            
            let usage = generateMockUsage(prompt: prompt, response: enumValue)
            
            return ProviderResponse(
                content: enumValue,
                usage: usage,
                finishReason: .stop,
                providerMetadata: ["model_id": modelId]
            )
        }
        let mockJSONOptions = [
            // Complex Recipe object (for nested object test)
            """
            {
                "name": "Vegetarian Pasta Primavera",
                "description": "A delicious and colorful pasta dish loaded with fresh vegetables and herbs, perfect for a healthy weeknight dinner.",
                "prepTime": 15,
                "cookTime": 25,
                "difficulty": "easy",
                "ingredients": [
                    {
                        "name": "penne pasta",
                        "amount": "8 oz",
                        "optional": false
                    },
                    {
                        "name": "olive oil",
                        "amount": "2 tbsp",
                        "optional": false
                    },
                    {
                        "name": "bell peppers",
                        "amount": "2 large",
                        "optional": false
                    },
                    {
                        "name": "zucchini",
                        "amount": "1 medium",
                        "optional": false
                    },
                    {
                        "name": "fresh basil",
                        "amount": "1/4 cup",
                        "optional": true
                    }
                ],
                "steps": [
                    "Cook pasta according to package directions until al dente",
                    "Heat olive oil in a large skillet over medium-high heat",
                    "Add bell peppers and zucchini, cook for 5-7 minutes until tender",
                    "Drain pasta and add to the vegetable mixture",
                    "Toss with fresh basil and serve immediately"
                ],
                "nutritionInfo": {
                    "calories": 385,
                    "protein": 12.5,
                    "carbs": 58.3,
                    "fat": 14.2
                },
                "tags": ["vegetarian", "quick", "healthy", "pasta", "vegetables"]
            }
            """,
            // UserProfile-like object (for schema validation test)
            """
            {
                "name": "John Doe",
                "age": 30,
                "email": "john@example.com",
                "isActive": true
            }
            """,
            // Simple Recipe object (for basic tests)
            """
            {
                "name": "Simple Pasta",
                "ingredients": ["pasta", "tomato sauce", "cheese"],
                "instructions": ["Boil water", "Cook pasta", "Add sauce", "Serve hot"],
                "cookingTime": 20
            }
            """,
            // Product object (for error testing)
            """
            {
                "name": "Test Product",
                "price": 99.99,
                "category": "Electronics"
            }
            """,
            // TestData object (for JSON completion testing)
            """
            {
                "name": "JSON Completion Test",
                "value": 42,
                "active": true
            }
            """,
            // StreamData object (for streaming error recovery)
            """
            {
                "id": "stream-data-123",
                "content": "This is streaming data content for recovery testing"
            }
            """
        ]
        
        // Person object (for basic object generation tests)
        let personJSON = """
        {
            "name": "John Smith",
            "age": 30,
            "occupation": "Software Engineer"
        }
        """
        
        // Employee object (for complex schema tests)
        let employeeJSON = """
        {
            "id": "EMP-12345",
            "name": "Jane Doe",
            "department": "Engineering",
            "salary": 95000.0,
            "address": {
                "street": "123 Market Street",
                "city": "San Francisco",
                "zipCode": "94105"
            },
            "contact": {
                "email": "jane.doe@company.com",
                "phone": "+1-555-0123"
            },
            "skills": ["Swift", "iOS Development", "Software Architecture", "Team Leadership"],
            "isActive": true
        }
        """
        
        // Products array (for array generation tests)
        let productsArrayJSON = """
        [
            {
                "name": "Wireless Headphones",
                "price": 99.99,
                "category": "Electronics",
                "inStock": true
            },
            {
                "name": "Bluetooth Speaker",
                "price": 49.99,
                "category": "Electronics", 
                "inStock": true
            },
            {
                "name": "USB-C Cable",
                "price": 19.99,
                "category": "Electronics",
                "inStock": false
            }
        ]
        """
        
        // SimpleData object (for generation modes tests)
        let simpleDataJSON = """
        {
            "value": "Test Data String",
            "number": 42
        }
        """
        
        // Choose appropriate JSON based on prompt or model and generation mode
        let selectedJSON: String
        if prompt.lowercased().contains("vegetarian") || prompt.lowercased().contains("primavera") {
            selectedJSON = mockJSONOptions[0] // Complex Recipe
        } else if (prompt.lowercased().contains("user") || prompt.lowercased().contains("profile")) && !prompt.lowercased().contains("person") && !prompt.lowercased().contains("employee") {
            selectedJSON = mockJSONOptions[1] // UserProfile
        } else if prompt.lowercased().contains("employee") || prompt.lowercased().contains("software engineer in san francisco") {
            selectedJSON = employeeJSON // Employee object
        } else if prompt.lowercased().contains("person") || prompt.lowercased().contains("john smith") {
            selectedJSON = personJSON // Person object
        } else if prompt.lowercased().contains("electronic products") || prompt.lowercased().contains("online store") {
            selectedJSON = productsArrayJSON // Products array for generateArray tests
        } else if prompt.lowercased().contains("simple test data") {
            selectedJSON = simpleDataJSON // SimpleData for generation modes tests
        } else if prompt.lowercased().contains("streaming data") || name == "StreamData" {
            selectedJSON = mockJSONOptions[5] // StreamData for streaming error recovery tests
        } else if prompt.lowercased().contains("create a simple pasta recipe") && !prompt.lowercased().contains("streaming") && name != "Recipe" {
            // For the basic testAIClientGenerateObject test that expects only 3 fields
            // But exclude when name is "Recipe" which indicates streaming object mode
            selectedJSON = """
            {
                "name": "Simple Pasta",
                "ingredients": ["pasta", "tomato sauce", "cheese"],
                "cookingTime": 20
            }
            """
        } else if prompt.lowercased().contains("recipe") || prompt.lowercased().contains("pasta") || prompt.lowercased().contains("streaming") {
            selectedJSON = mockJSONOptions[2] // Full Recipe with instructions for streaming tests
        } else if prompt.lowercased().contains("json completion") || prompt.lowercased().contains("test data") {
            selectedJSON = mockJSONOptions[4] // TestData for JSON completion
        } else {
            selectedJSON = mockJSONOptions[3] // Product
        }
        
        let usage = generateMockUsage(prompt: prompt, response: selectedJSON)
        
        return ProviderResponse(
            content: selectedJSON,
            usage: usage,
            finishReason: .stop,
            providerMetadata: [
                "mock_provider": "true",
                "model_id": modelId,
                "json_generation": "true"
            ]
        )
    }
    
    /// Generate mock tool response for tool-based structured output requests
    private func generateMockToolResponse(for modelId: String, prompt: String, tool: Tool) throws -> ProviderResponse {
        // For object generation tools, return the JSON directly instead of tool calls
        // This simulates the tool being executed and returning structured data
        
        // Check if this is an object generation tool (based on function name patterns)
        // For object generation, we want to return JSON content directly
        if tool.function.name.contains("generate_object") || 
           tool.function.name.contains("select_enum") ||
           prompt.lowercased().contains("simple test data") ||
           tool.function.description?.lowercased().contains("data structure") == true {
            // Return JSON content directly for object generation tools
            return try generateMockJSONResponse(for: modelId, prompt: prompt, schema: nil, name: tool.function.name, description: tool.function.description)
        }
        
        // For regular tools, create a mock tool call
        let toolCall = ToolCall(
            id: "tool_call_\(UUID().uuidString.prefix(8))",
            function: try ToolCallFunction(
                name: tool.function.name,
                arguments: generateMockToolArguments(for: tool, prompt: prompt)
            )
        )
        
        let usage = generateMockUsage(prompt: prompt, response: "I'll use the \(tool.function.name) tool to help with that.")
        
        return ProviderResponse(
            content: "I'll use the \(tool.function.name) tool to help with that.",
            toolCalls: [toolCall],
            usage: usage,
            finishReason: .toolCalls,
            providerMetadata: [
                "mock_provider": "true",
                "model_id": modelId,
                "tool_generation": "true",
                "tool_name": tool.function.name
            ]
        )
    }
    
    /// Generate mock arguments for a tool call based on the tool schema
    private func generateMockToolArguments(for tool: Tool, prompt: String) -> [String: Any] {
        // For now, return simple mock arguments based on the tool name
        // In a real implementation, this would analyze the JSONSchema to generate appropriate mock data
        switch tool.function.name {
        case "generate_object":
            return ["object": ["name": "Mock Object", "value": "Generated from prompt: \(prompt.prefix(50))"]]
        case "select_enum_value":
            return ["value": "option1"] // Default to first option
        default:
            return ["result": "Mock result for \(tool.function.name)"]
        }
    }
}

// MARK: - Mock Configuration

/// Configuration for mock provider behavior.
///
/// Allows customization of how the mock provider behaves, including
/// error simulation, delays, and feature support.
public struct MockConfiguration: Sendable {
    
    /// Delay before responding (in seconds).
    public let responseDelay: TimeInterval?
    
    /// Delay between streaming chunks (in seconds).
    public let chunkDelay: TimeInterval?
    
    /// Rate of simulated errors (0.0 to 1.0).
    public let errorRate: Double?
    
    /// Whether to perform strict validation.
    public let strictValidation: Bool
    
    /// Whether to simulate tool calling support.
    public let supportsTools: Bool
    
    /// Whether to simulate object generation support.
    public let supportsObjectGeneration: Bool
    
    /// Whether to simulate image input support.
    public let supportsImageInputs: Bool
    
    /// Maximum response length in characters.
    public let maxResponseLength: Int
    
    public init(
        responseDelay: TimeInterval? = nil,
        chunkDelay: TimeInterval? = nil,
        errorRate: Double? = nil,
        strictValidation: Bool = false,
        supportsTools: Bool = true,
        supportsObjectGeneration: Bool = true,
        supportsImageInputs: Bool = false,
        maxResponseLength: Int = 1000
    ) {
        self.responseDelay = responseDelay
        self.chunkDelay = chunkDelay
        self.errorRate = errorRate
        self.strictValidation = strictValidation
        self.supportsTools = supportsTools
        self.supportsObjectGeneration = supportsObjectGeneration
        self.supportsImageInputs = supportsImageInputs
        self.maxResponseLength = maxResponseLength
    }
    
    /// Default configuration with no delays or errors.
    public static let `default` = MockConfiguration()
    
    /// Configuration with realistic delays for testing.
    public static let realistic = MockConfiguration(
        responseDelay: 0.5,
        chunkDelay: 0.1
    )
    
    /// Configuration that simulates errors for testing error handling.
    public static let errorProne = MockConfiguration(
        errorRate: 0.1,
        strictValidation: true
    )
    
    /// Fast configuration with minimal delays.
    public static let fast = MockConfiguration(
        responseDelay: 0.01,
        chunkDelay: 0.001
    )
}