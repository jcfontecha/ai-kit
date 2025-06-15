import Foundation

// MARK: - AIClient

/// The concrete framework that executes all AI operations and contains the core logic.
///
/// AIClient is the primary interface for interacting with AI models in the Swift AI SDK.
/// It follows the Vercel AI SDK patterns while being thoroughly Swift-native, using actors
/// for concurrency safety and providing type-safe interfaces for all operations.
///
/// ## Responsibilities
/// - Apply middleware chain for request/response transformation
/// - JSON schema validation and parsing for structured outputs
/// - Tool execution and orchestration
/// - Framework-level response parsing and error handling
/// - Streaming management with AsyncSequence
/// - All framework orchestration logic
///
/// ## Usage Examples
///
/// ### Simple Text Generation
/// ```swift
/// let client = AIClient()
/// let model = provider.languageModel("gpt-4")
/// let response = try await client.generateText(model, prompt: "Explain quantum computing")
/// ```
///
/// ### Streaming with Tools
/// ```swift
/// let stream = client.streamText(model, prompt: "What's the weather today?")
/// for try await chunk in stream {
///     print(chunk.delta, terminator: "")
/// }
/// ```
///
/// ### Object Generation
/// ```swift
/// let response = try await client.generateObject(
///     model,
///     prompt: "Create a recipe",
///     schema: ObjectSchema<Recipe>()
/// )
/// let recipe: Recipe = response.object
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public actor AIClient {
    
    // MARK: - Properties
    
    /// The middleware chain applied to all requests and responses
    private let middleware: [any AIMiddleware]
    
    /// Optional tool executor provided by the caller for custom tool execution
    private let toolExecutor: ((ToolCall) async throws -> ToolResult)?
    
    // MARK: - Initialization
    
    /// Creates a new AIClient with optional middleware chain and tool executor.
    ///
    /// - Parameters:
    ///   - middleware: Array of middleware to apply to requests and responses.
    ///     Middleware is applied in order for requests and reverse order for responses.
    ///   - toolExecutor: Optional custom tool executor provided by the caller.
    ///     If provided, this will be used instead of the default hardcoded tool execution.
    public init(middleware: [any AIMiddleware] = [], toolExecutor: ((ToolCall) async throws -> ToolResult)? = nil) {
        self.middleware = middleware
        self.toolExecutor = toolExecutor
    }
    
    // MARK: - Core Operations
    
    /// Generate a text response from the given model and messages.
    ///
    /// This method handles the complete text generation pipeline:
    /// 1. Applies request middleware
    /// 2. Calls the provider's raw generation method
    /// 3. Applies response middleware
    /// 4. Handles any tool calls if present
    /// 5. Returns a typed response
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - tools: Optional array of tools available for the model to call
    ///   - maxSteps: Maximum number of tool execution steps (default: 1 for single call)
    /// - Returns: A `TextResponse` containing the generated text and metadata
    /// - Throws: `AIError` for various failure conditions
    public func generateText(_ model: LanguageModel, messages: [Message], tools: [Tool]? = nil, maxSteps: Int = 1) async throws -> TextResponse {
        // Multi-step execution implementation following Vercel AI SDK pattern
        var currentMessages = messages
        var allSteps: [GenerationStep] = []
        var totalUsage = Usage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
        
        for stepIndex in 0..<maxSteps {
            // 1. Create provider request for this step
            let request = ProviderRequest(
                modelId: model.modelId,
                messages: currentMessages,
                configuration: model.configuration,
                tools: tools
            )
            
            // 2. Apply request middleware
            let processedRequest = try await applyRequestMiddleware(request)
            
            // 3. Call provider
            let providerResponse = try await model.provider.generateTextRaw(processedRequest)
            
            // 4. Accumulate usage
            totalUsage = Usage(
                promptTokens: totalUsage.promptTokens + providerResponse.usage.promptTokens,
                completionTokens: totalUsage.completionTokens + providerResponse.usage.completionTokens,
                totalTokens: totalUsage.totalTokens + providerResponse.usage.totalTokens
            )
            
            // 5. Handle the response based on finish reason
            if let toolCalls = providerResponse.toolCalls, !toolCalls.isEmpty, providerResponse.finishReason == .toolCalls {
                // Step 1: Record the tool call step
                let toolCallStep = GenerationStep(
                    stepType: .toolCall,
                    usage: providerResponse.usage,
                    messages: [Message.assistant(providerResponse.content)],
                    toolCalls: toolCalls
                )
                allSteps.append(toolCallStep)
                
                // Check if we have more steps available for tool execution
                if stepIndex + 1 < maxSteps {
                    // Step 2: Execute tools and create tool result messages
                    var toolResults: [ToolResult] = []
                    for toolCall in toolCalls {
                        let result = try await executeToolCall(toolCall)
                        toolResults.append(result)
                    }
                    
                    // Step 3: Add tool results to conversation
                    currentMessages.append(Message.assistant(providerResponse.content))
                    for result in toolResults {
                        currentMessages.append(Message.tool(result: result))
                    }
                    
                    // Step 4: Record the tool result processing step
                    let toolResultStep = GenerationStep(
                        stepType: .toolResult,
                        messages: toolResults.map { Message.tool(result: $0) },
                        toolResults: toolResults
                    )
                    allSteps.append(toolResultStep)
                    
                    // Continue to next step for final generation
                    continue
                } else {
                    // No more steps available, return with tool calls
                    currentMessages.append(Message.assistant(providerResponse.content))
                    
                    let textResponse = TextResponse(
                        text: providerResponse.content,
                        finishReason: providerResponse.finishReason,
                        usage: totalUsage,
                        messages: currentMessages,
                        steps: allSteps.isEmpty ? nil : allSteps,
                        responseId: nil,
                        modelId: model.modelId,
                        timestamp: Date(),
                        warnings: nil,
                        responseHeaders: nil
                    )
                    
                    return try await applyResponseMiddleware(textResponse)
                }
                
            } else {
                // Final step: regular completion
                currentMessages.append(Message.assistant(providerResponse.content))
                
                let finalStep = GenerationStep(
                    stepType: stepIndex == 0 ? .initial : .continue,
                    usage: providerResponse.usage,
                    messages: [Message.assistant(providerResponse.content)]
                )
                allSteps.append(finalStep)
                
                // Build final response
                let textResponse = TextResponse(
                    text: providerResponse.content,
                    finishReason: providerResponse.finishReason,
                    usage: totalUsage,
                    messages: currentMessages,
                    steps: allSteps.isEmpty ? nil : allSteps,
                    responseId: nil,
                    modelId: model.modelId,
                    timestamp: Date(),
                    warnings: nil,
                    responseHeaders: nil
                )
                
                // Apply response middleware and return
                return try await applyResponseMiddleware(textResponse)
            }
        }
        
        // If we reached maxSteps without completion
        let finalResponse = TextResponse(
            text: "Maximum steps reached without completion",
            finishReason: .length,
            usage: totalUsage,
            messages: currentMessages,
            steps: allSteps.isEmpty ? nil : allSteps,
            responseId: nil,
            modelId: model.modelId,
            timestamp: Date(),
            warnings: ["Reached maximum steps limit"],
            responseHeaders: nil
        )
        
        return try await applyResponseMiddleware(finalResponse)
    }
    
    /// Execute a tool call and return the result.
    ///
    /// This method handles the execution of individual tool calls. If a custom tool executor
    /// was provided during initialization, it will be used. Otherwise, falls back to
    /// generic mock implementations for testing purposes.
    ///
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The result of the tool execution
    /// - Throws: Any errors from tool execution
    private func executeToolCall(_ toolCall: ToolCall) async throws -> ToolResult {
        // Use caller-provided tool executor if available
        if let toolExecutor = self.toolExecutor {
            return try await toolExecutor(toolCall)
        }
        
        // No tool executor provided - this is an error in production
        throw AIGenerationError.toolExecutionFailed(
            toolName: toolCall.function.name,
            error: NSError(domain: "AIClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No tool executor provided. Tool execution requires a custom toolExecutor to be provided during AIClient initialization."
            ])
        )
    }
    
    /// Stream text response from the given model and messages.
    ///
    /// This method provides real-time streaming of text generation:
    /// 1. Applies request middleware
    /// 2. Creates streaming connection to provider
    /// 3. Applies chunk middleware to each received chunk
    /// 4. Handles tool calls within the stream
    /// 5. Returns an AsyncThrowingStream of text chunks
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    /// - Returns: AsyncThrowingStream of `TextChunk` objects
    public func streamText(_ model: LanguageModel, messages: [Message]) -> AsyncThrowingStream<TextChunk, Error> {
        // Minimal implementation to make tests pass - apply middleware, call provider, transform chunks
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Create provider request
                    let request = ProviderRequest(
                        modelId: model.modelId,
                        messages: messages,
                        configuration: model.configuration
                    )
                    
                    // 2. Apply request middleware
                    let processedRequest = try await applyRequestMiddleware(request)
                    
                    // 3. Stream from provider and transform to TextChunk
                    let providerStream = model.provider.streamTextRaw(processedRequest)
                    var accumulatedText = ""
                    
                    for try await providerChunk in providerStream {
                        accumulatedText += providerChunk.delta
                        
                        // Transform ProviderChunk to TextChunk
                        let textChunk = TextChunk(
                            delta: providerChunk.delta,
                            snapshot: accumulatedText,
                            finishReason: providerChunk.finishReason,
                            usage: providerChunk.usage,
                            chunkId: UUID().uuidString,
                            timestamp: Date(),
                            stepId: nil
                        )
                        
                        // 4. Apply chunk middleware and yield
                        let processedChunk = try await applyChunkMiddleware(textChunk)
                        continuation.yield(processedChunk)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Framework-Centralized Structured Output Helpers
    
    /// Determine the effective generation mode based on requested mode and provider capabilities
    private func determineEffectiveMode(requestedMode: GenerationMode, provider: any AIProvider) -> GenerationMode {
        // If auto mode, use provider's default
        if requestedMode == .auto {
            return provider.defaultGenerationMode
        }
        
        // Check if provider supports the requested mode
        if provider.supportedGenerationModes.contains(requestedMode) {
            return requestedMode
        }
        
        // Fall back to provider's default if requested mode is not supported
        return provider.defaultGenerationMode
    }
    
    /// Create provider mode based on generation mode and output strategy
    private func createProviderMode<T: Codable>(
        generationMode: GenerationMode,
        outputStrategy: OutputStrategy,
        schema: ObjectSchema<T>
    ) -> ProviderMode {
        switch generationMode {
        case .json:
            return .objectJSON(
                schema: schema.jsonSchema,
                name: schema.name,
                description: schema.description
            )
        case .tool:
            // Create a tool that represents the schema
            let tool = createToolFromSchema(schema: schema, outputStrategy: outputStrategy)
            return .objectTool(tool: tool)
        case .auto:
            // This shouldn't happen as auto should be resolved by determineEffectiveMode
            return .objectJSON(
                schema: schema.jsonSchema,
                name: schema.name,
                description: schema.description
            )
        }
    }
    
    /// Extract tools from provider mode if applicable
    private func extractToolsFromMode(_ mode: ProviderMode) -> [Tool]? {
        switch mode {
        case .regular(let tools, _):
            return tools
        case .objectTool(let tool):
            return [tool]
        case .objectJSON:
            return nil
        }
    }
    
    /// Create a tool from schema for tool-based structured output
    private func createToolFromSchema<T: Codable>(
        schema: ObjectSchema<T>,
        outputStrategy: OutputStrategy
    ) -> Tool {
        let functionName = schema.name ?? "generate_object"
        let description = schema.description ?? "Generate a structured object"
        
        return Tool(
            type: .function,
            function: ToolFunction(
                name: functionName,
                description: description,
                parameters: schema.jsonSchema
            )
        )
    }
    
    /// Create provider mode for enum generation
    private func createProviderModeForEnum(
        generationMode: GenerationMode,
        values: [String]
    ) -> ProviderMode {
        switch generationMode {
        case .json:
            // Create a simple schema for enum values
            let enumSchema = JSONSchema.string(enum: values)
            return .objectJSON(
                schema: enumSchema,
                name: "enum_value",
                description: "Select one value from the allowed options"
            )
        case .tool:
            // Create a tool for enum selection
            let tool = createToolFromEnum(values: values)
            return .objectTool(tool: tool)
        case .auto:
            // Default to JSON mode for enums
            let enumSchema = JSONSchema.string(enum: values)
            return .objectJSON(
                schema: enumSchema,
                name: "enum_value",
                description: "Select one value from the allowed options"
            )
        }
    }
    
    /// Create a tool from enum values for tool-based enum selection
    private func createToolFromEnum(values: [String]) -> Tool {
        let enumSchema = JSONSchema.string(enum: values)
        
        return Tool(
            type: .function,
            function: ToolFunction(
                name: "select_enum_value",
                description: "Select one value from the available options",
                parameters: JSONSchema.object(properties: [
                    "value": enumSchema
                ], required: ["value"])
            )
        )
    }
    
    /// Generate a structured object response from the given model, messages, and schema.
    ///
    /// This method handles structured data generation with JSON schema validation:
    /// 1. Applies request middleware
    /// 2. Validates the provided schema
    /// 3. Calls provider with schema-constrained generation
    /// 4. Validates response against schema
    /// 5. Deserializes to the specified type
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - schema: The schema defining the structure of the expected object
    /// - Returns: An `ObjectResponse<T>` containing the generated object and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    public func generateObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<T> {
        // 1. Determine the actual mode to use
        let effectiveMode = determineEffectiveMode(requestedMode: mode, provider: model.provider)
        
        // 2. Create provider mode based on effective generation mode  
        let providerMode = createProviderMode(
            generationMode: effectiveMode,
            outputStrategy: .object,
            schema: schema
        )
        
        // 3. Create provider request with the determined mode
        let request = ProviderRequest(
            modelId: model.modelId,
            messages: messages,
            configuration: model.configuration,
            tools: extractToolsFromMode(providerMode),
            mode: providerMode
        )
        
        // 4. Apply request middleware
        let processedRequest = try await applyRequestMiddleware(request)
        
        // 5. Call provider's raw text generation with mode information
        let providerResponse = try await model.provider.generateTextRaw(processedRequest)
        
        // 6. Parse the JSON response into the target type (framework responsibility)
        let jsonObject = try parseJSONResponse(providerResponse.content, as: T.self)
        
        // 6. Validate the object against schema
        let validationResult = schema.validate(jsonObject)
        
        // 7. Build final ObjectResponse
        let finalMessages = messages + [Message.assistant(providerResponse.content)]
        
        let objectResponse = ObjectResponse<T>(
            object: jsonObject,
            finishReason: providerResponse.finishReason,
            usage: providerResponse.usage,
            messages: finalMessages,
            steps: nil,
            responseId: nil,
            modelId: model.modelId,
            timestamp: Date(),
            warnings: nil,
            responseHeaders: nil,
            rawJSON: providerResponse.content,
            validationResult: validationResult
        )
        
        // 8. Apply response middleware and return
        return try await applyResponseMiddleware(objectResponse)
    }
    
    /// Convenience method for object generation from a simple prompt
    public func generateObject<T: Codable>(_ model: LanguageModel, prompt: String, schema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<T> {
        let messages = [Message.user(prompt)]
        return try await generateObject(model, messages: messages, schema: schema, mode: mode)
    }
    
    /// Generate an array of structured objects from the given model, messages, and element schema.
    ///
    /// This method specializes in generating arrays of objects with the provider's optimal approach:
    /// 1. Determines effective generation mode based on provider capabilities
    /// 2. Creates provider request with array output strategy  
    /// 3. Calls provider's raw text generation with mode information
    /// 4. Parses the JSON array response into the specified element type
    /// 5. Validates each element against the provided schema
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - elementSchema: The schema defining the structure of each array element
    ///   - mode: The generation mode (auto, json, tool) - defaults to auto
    /// - Returns: An `ObjectResponse<[T]>` containing the generated array and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    public func generateArray<T: Codable>(_ model: LanguageModel, messages: [Message], elementSchema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]> {
        // 1. Determine the actual mode to use
        let effectiveMode = determineEffectiveMode(requestedMode: mode, provider: model.provider)
        
        // 2. Create provider mode based on effective generation mode  
        let providerMode = createProviderMode(
            generationMode: effectiveMode,
            outputStrategy: .array,
            schema: elementSchema
        )
        
        // 3. Create provider request with the determined mode
        let request = ProviderRequest(
            modelId: model.modelId,
            messages: messages,
            configuration: model.configuration,
            tools: extractToolsFromMode(providerMode),
            mode: providerMode
        )
        
        // 4. Apply request middleware
        let processedRequest = try await applyRequestMiddleware(request)
        
        // 5. Call provider's raw text generation with mode information
        let providerResponse = try await model.provider.generateTextRaw(processedRequest)
        
        // 6. Parse the JSON response into the target array type (framework responsibility)
        let jsonArray = try parseJSONResponse(providerResponse.content, as: [T].self)
        
        // 7. Validate each element against the schema
        var validationResults: [ObjectValidationResult] = []
        for element in jsonArray {
            validationResults.append(elementSchema.validate(element))
        }
        
        // 8. Build final ObjectResponse
        let finalMessages = messages + [Message.assistant(providerResponse.content)]
        
        let objectResponse = ObjectResponse<[T]>(
            object: jsonArray,
            finishReason: providerResponse.finishReason,
            usage: providerResponse.usage,
            messages: finalMessages,
            steps: nil,
            responseId: nil,
            modelId: model.modelId,
            timestamp: Date(),
            warnings: nil,
            responseHeaders: nil,
            rawJSON: providerResponse.content,
            validationResult: validationResults.first // Use first validation result for compatibility
        )
        
        // 9. Apply response middleware and return
        return try await applyResponseMiddleware(objectResponse)
    }
    
    /// Convenience method for array generation from a simple prompt
    public func generateArray<T: Codable>(_ model: LanguageModel, prompt: String, elementSchema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]> {
        let messages = [Message.user(prompt)]
        return try await generateArray(model, messages: messages, elementSchema: elementSchema, mode: mode)
    }
    
    /// Generate an enum value from a predefined set of options.
    ///
    /// This method handles enum generation by constraining the model to select from
    /// a specific set of predefined values:
    /// 1. Determines effective generation mode based on provider capabilities
    /// 2. Creates provider request with enum output strategy
    /// 3. Calls provider's raw text generation with mode information
    /// 4. Validates the response against the allowed values
    /// 5. Returns the selected enum value
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - values: Array of allowed enum values
    ///   - mode: The generation mode (auto, json, tool) - defaults to auto
    /// - Returns: An `ObjectResponse<String>` containing the selected enum value
    /// - Throws: `AIError` if the response doesn't match any allowed values
    public func generateEnum(_ model: LanguageModel, messages: [Message], values: [String], mode: GenerationMode = .auto) async throws -> ObjectResponse<String> {
        // 1. Determine the actual mode to use
        let effectiveMode = determineEffectiveMode(requestedMode: mode, provider: model.provider)
        
        // 2. Create provider mode based on effective generation mode
        let providerMode = createProviderModeForEnum(
            generationMode: effectiveMode,
            values: values
        )
        
        // 3. Create provider request with the determined mode
        let request = ProviderRequest(
            modelId: model.modelId,
            messages: messages,
            configuration: model.configuration,
            tools: extractToolsFromMode(providerMode),
            mode: providerMode
        )
        
        // 4. Apply request middleware
        let processedRequest = try await applyRequestMiddleware(request)
        
        // 5. Call provider's raw text generation with mode information
        let providerResponse = try await model.provider.generateTextRaw(processedRequest)
        
        // 6. Extract and validate the enum value
        let selectedValue = providerResponse.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Remove potential JSON quotes if present
        let cleanValue = selectedValue.hasPrefix("\"") && selectedValue.hasSuffix("\"") 
            ? String(selectedValue.dropFirst().dropLast())
            : selectedValue
        
        // Validate against allowed values
        guard values.contains(cleanValue) else {
            throw AIGenerationError.schemaValidationError(
                objectData: providerResponse.content,
                validationErrors: ["Generated value '\(cleanValue)' is not in allowed values: \(values.joined(separator: ", "))"]
            )
        }
        
        // 7. Build final ObjectResponse
        let finalMessages = messages + [Message.assistant(providerResponse.content)]
        
        let objectResponse = ObjectResponse<String>(
            object: cleanValue,
            finishReason: providerResponse.finishReason,
            usage: providerResponse.usage,
            messages: finalMessages,
            steps: nil,
            responseId: nil,
            modelId: model.modelId,
            timestamp: Date(),
            warnings: nil,
            responseHeaders: nil,
            rawJSON: providerResponse.content,
            validationResult: ObjectValidationResult(isValid: true) // Enum validation passed
        )
        
        // 8. Apply response middleware and return
        return try await applyResponseMiddleware(objectResponse)
    }
    
    /// Convenience method for enum generation from a simple prompt
    public func generateEnum(_ model: LanguageModel, prompt: String, values: [String], mode: GenerationMode = .auto) async throws -> ObjectResponse<String> {
        let messages = [Message.user(prompt)]
        return try await generateEnum(model, messages: messages, values: values, mode: mode)
    }
    
    /// Parse JSON response content into the specified type with proper error handling
    private func parseJSONResponse<T: Codable>(_ content: String, as type: T.Type) throws -> T {
        // Extract JSON from the response content
        // Some providers might include extra text, so we need to find the JSON portion
        let jsonString = extractJSONFromResponse(content)
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIGenerationError.jsonParseError(
                text: content,
                parseError: NSError(domain: "AIClient", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not convert response to UTF-8 data"
                ])
            )
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: jsonData)
        } catch let decodingError as DecodingError {
            throw AIGenerationError.jsonParseError(
                text: content,
                parseError: decodingError
            )
        } catch {
            throw AIGenerationError.jsonParseError(
                text: content, 
                parseError: error
            )
        }
    }
    
    /// Extract JSON content from response text that might contain additional content
    private func extractJSONFromResponse(_ content: String) -> String {
        // Look for JSON object boundaries
        if let startIndex = content.firstIndex(of: "{") {
            // Find the matching closing brace by counting braces
            var braceCount = 0
            var endIndex = startIndex
            
            for (index, char) in content[startIndex...].enumerated() {
                let currentIndex = content.index(startIndex, offsetBy: index)
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = currentIndex
                        break
                    }
                }
            }
            
            if braceCount == 0 {
                return String(content[startIndex...endIndex])
            }
        }
        
        // If no valid JSON object found, return the original content
        return content
    }
    
    /// Stream structured object generation from the given model, messages, and schema.
    ///
    /// This method provides real-time streaming of structured object generation:
    /// 1. Applies request middleware
    /// 2. Validates the provided schema
    /// 3. Creates streaming connection with partial object parsing
    /// 4. Validates partial objects during generation
    /// 5. Returns an AsyncThrowingStream of object chunks
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - schema: The schema defining the structure of the expected object
    /// - Returns: AsyncThrowingStream of `ObjectChunk<T>` objects
    public func streamObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>) -> AsyncThrowingStream<ObjectChunk<T>, Error> {
        // TODO: Implement streaming object generation with partial validation
        fatalError("AIClient.streamObject not implemented")
    }
    
    // MARK: - Convenience Methods
    
    /// Generate text from a simple string prompt.
    ///
    /// This is a convenience method that wraps the prompt in a user message
    /// and calls the full `generateText` method.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    /// - Returns: A `TextResponse` containing the generated text and metadata
    /// - Throws: `AIError` for various failure conditions
    public func generateText(_ model: LanguageModel, prompt: String) async throws -> TextResponse {
        let messages = [Message.user(prompt)]
        return try await generateText(model, messages: messages)
    }
    
    /// Stream text from a simple string prompt.
    ///
    /// This is a convenience method that wraps the prompt in a user message
    /// and calls the full `streamText` method.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    /// - Returns: AsyncThrowingStream of `TextChunk` objects
    public func streamText(_ model: LanguageModel, prompt: String) -> AsyncThrowingStream<TextChunk, Error> {
        let messages = [Message.user(prompt)]
        return streamText(model, messages: messages)
    }
    
    /// Generate a structured object from a simple string prompt.
    ///
    /// This is a convenience method that wraps the prompt in a user message
    /// and calls the full `generateObject` method.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    ///   - schema: The schema defining the structure of the expected object
    /// - Returns: An `ObjectResponse<T>` containing the generated object and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    public func generateObject<T: Codable>(_ model: LanguageModel, prompt: String, schema: ObjectSchema<T>) async throws -> ObjectResponse<T> {
        let messages = [Message.user(prompt)]
        return try await generateObject(model, messages: messages, schema: schema)
    }
}

// MARK: - AIClient Extensions

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AIClient {
    
    /// Execute middleware chain for request transformation.
    ///
    /// This internal method applies all configured middleware to transform
    /// a request before sending it to the provider.
    ///
    /// - Parameter request: The request to transform
    /// - Returns: The transformed request
    /// - Throws: Any errors from middleware transformation
    private func applyRequestMiddleware<T: AIRequest>(_ request: T) async throws -> T {
        if middleware.isEmpty {
            return request
        }
        
        // Create middleware chain and execute request transformation
        let chain = MiddlewareChain(middlewares: middleware)
        let context = MiddlewareContext(
            requestId: request.requestId,
            operationType: .generateText, // TODO: determine actual operation type
            modelId: "unknown", // TODO: extract from request context
            providerId: "unknown" // TODO: extract from provider
        )
        
        return try await chain.transformRequest(request, context: context)
    }
    
    /// Execute middleware chain for response transformation.
    ///
    /// This internal method applies all configured middleware to transform
    /// a response after receiving it from the provider.
    ///
    /// - Parameter response: The response to transform
    /// - Returns: The transformed response
    /// - Throws: Any errors from middleware transformation
    private func applyResponseMiddleware<T: AIResponse>(_ response: T) async throws -> T {
        if middleware.isEmpty {
            return response
        }
        
        // Create middleware chain and execute response transformation
        let chain = MiddlewareChain(middlewares: middleware)
        let context = MiddlewareContext(
            requestId: response.responseId ?? "unknown",
            operationType: .generateText, // TODO: determine actual operation type
            modelId: "unknown", // TODO: extract from response context
            providerId: "unknown" // TODO: extract from provider
        )
        
        return try await chain.transformResponse(response, context: context)
    }
    
    /// Execute middleware chain for streaming chunk transformation.
    ///
    /// This internal method applies all configured middleware to transform
    /// each streaming chunk as it's received from the provider.
    ///
    /// - Parameter chunk: The chunk to transform
    /// - Returns: The transformed chunk
    /// - Throws: Any errors from middleware transformation
    private func applyChunkMiddleware<T: StreamChunk>(_ chunk: T) async throws -> T {
        // TODO: Implement middleware chain execution
        return chunk
    }
}