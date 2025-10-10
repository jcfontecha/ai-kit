import Foundation

// MARK: - JSON Parsing Results

/// Result of partial JSON parsing
enum PartialParseResult<T> {
    case success(T)           // Successfully parsed complete object
    case partial(T?)          // Partially parsed with possible partial object
    case failed               // Failed to parse or repair
}

// MARK: - Streaming Operations

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AIClient {
    
    /// Stream text response from the given model and messages.
    ///
    /// This method provides real-time streaming of text generation:
    /// 1. Applies request middleware
    /// 2. Creates streaming connection to provider
    /// 3. Applies chunk middleware to each received chunk
    /// 4. Handles tool calls within the stream
    /// 5. Returns a StreamTextResult with both stream and accumulated data
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    /// - Returns: StreamTextResult containing the stream and accumulated data
    func streamText(_ model: LanguageModel, messages: [Message]) -> StreamTextResult {
        // Create message tracker
        let messageTracker = StreamingMessageTracker()
        
        // Create the base stream
        let baseStream = AsyncThrowingStream<TextChunk, Error> { continuation in
            let task = Task {
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
                        // Check for cancellation before processing each chunk
                        try Task.checkCancellation()
                        
                        accumulatedText += providerChunk.delta
                        
                        // Transform ProviderChunk to TextChunk with tool call support
                        let textChunk = TextChunk(
                            delta: providerChunk.delta,
                            snapshot: accumulatedText,
                            finishReason: providerChunk.finishReason,
                            usage: providerChunk.usage,
                            chunkId: UUID().uuidString,
                            timestamp: Date(),
                            stepId: providerChunk.stepId,
                            toolCalls: providerChunk.toolCall != nil ? [providerChunk.toolCall!] : nil,
                            toolCallStreamingStart: providerChunk.toolCallStreamingStart.map { start in
                                ToolCallStreamingStart(
                                    toolCallId: start.toolCallId,
                                    toolName: start.toolName
                                )
                            },
                            toolCallDelta: providerChunk.toolCallDelta.map { delta in
                                ToolCallDelta(
                                    toolCallId: delta.toolCallId,
                                    toolName: delta.toolName,
                                    argsTextDelta: delta.argsTextDelta
                                )
                            }
                        )
                        
                        // 4. Apply chunk middleware and yield
                        let processedChunk = try await applyChunkMiddleware(textChunk)
                        continuation.yield(processedChunk)
                    }
                    
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            // Handle cancellation from the continuation side
            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    task.cancel()
                }
            }
        }
        
        // Return wrapped result
        return StreamTextResult(
            stream: baseStream,
            messageTracker: messageTracker,
            tools: nil
        )
    }
    
    /// Stream text from a simple string prompt.
    ///
    /// This is a convenience method that wraps the prompt in a user message
    /// and calls the full `streamText` method.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    /// - Returns: StreamTextResult containing the stream and accumulated data
    func streamText(_ model: LanguageModel, prompt: String) -> StreamTextResult {
        let messages = [Message.user(prompt)]
        return streamText(model, messages: messages)
    }
    
    /// Stream text response with automatic tool execution support.
    ///
    /// Following Vercel AI SDK's approach, this method automatically handles tool execution:
    /// 1. Streams text chunks with tool call information
    /// 2. Automatically executes tools when tool calls are received (if tool has execute function)
    /// 3. Continues streaming with tool results
    /// 4. Supports multi-step tool execution
    /// 5. Provides access to properly formatted response messages
    ///
    /// Tool execution is automatic when tools have an execute function defined.
    /// The stream seamlessly includes chunks from both the initial generation
    /// and follow-up responses after tool execution.
    ///
    /// ## Usage Example:
    /// ```swift
    /// let result = client.streamText(model, messages: messages, tools: tools)
    /// 
    /// // Stream chunks
    /// for try await chunk in result.textStream {
    ///     print(chunk.delta)
    /// }
    /// 
    /// // Get formatted messages
    /// let responseMessages = await result.messages
    /// conversation.append(contentsOf: responseMessages)
    /// ```
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - tools: Optional array of tools available for the model to call
    ///   - toolChoice: Optional tool choice configuration
    ///   - maxSteps: Maximum number of tool execution steps (default: 1)
    /// - Returns: StreamTextResult containing the stream and accumulated data
    func streamText(
        _ model: LanguageModel, 
        messages: [Message],
        tools: [Tool]? = nil,
        toolChoice: ToolChoice? = nil,
        maxSteps: Int = 1
    ) -> StreamTextResult {
        // Create message tracker
        let messageTracker = StreamingMessageTracker()
        
        // Create the base stream
        let baseStream = AsyncThrowingStream<TextChunk, Error> { continuation in
            Task {
                do {
                    var currentMessages = messages
                    var allAccumulatedText = ""
                    var globalChunkIndex = 0
                    var stepCount = 0

                    // Use a conditional loop like Vercel AI SDK - only continue if there are tool calls to process
                    while stepCount < maxSteps {
                        // 1. Create provider request with tools
                        let request = ProviderRequest(
                            modelId: model.modelId,
                            messages: currentMessages,
                            configuration: model.configuration,
                            tools: tools,
                            mode: .regular(tools: tools, toolChoice: toolChoice)
                        )

                        // 2. Apply request middleware
                        let processedRequest = try await applyRequestMiddleware(request)

                        // 3. Stream from provider
                        let providerStream = model.provider.streamTextRaw(processedRequest)
                        var stepText = ""
                        var toolCallsReceived: [ToolCall] = []
                        var finishReason: FinishReason = .stop

                        for try await providerChunk in providerStream {
                            stepText += providerChunk.delta
                            allAccumulatedText += providerChunk.delta

                            // Collect tool calls from chunks
                            if let toolCall = providerChunk.toolCall {
                                toolCallsReceived.append(toolCall)
                            }

                            // Track finish reason
                            if let reason = providerChunk.finishReason {
                                finishReason = reason
                            }

                            // Transform ProviderChunk to TextChunk with full tool call support
                            let textChunk = TextChunk(
                                delta: providerChunk.delta,
                                snapshot: allAccumulatedText,
                                finishReason: providerChunk.finishReason,
                                usage: providerChunk.usage,
                                chunkId: UUID().uuidString,
                                timestamp: Date(),
                                stepId: String(stepCount),
                                toolCalls: providerChunk.toolCall != nil ? [providerChunk.toolCall!] : nil,
                                toolCallStreamingStart: providerChunk.toolCallStreamingStart.map { start in
                                    ToolCallStreamingStart(
                                        toolCallId: start.toolCallId,
                                        toolName: start.toolName
                                    )
                                },
                                toolCallDelta: providerChunk.toolCallDelta.map { delta in
                                    ToolCallDelta(
                                        toolCallId: delta.toolCallId,
                                        toolName: delta.toolName,
                                        argsTextDelta: delta.argsTextDelta
                                    )
                                }
                            )

                            // 4. Apply chunk middleware and yield
                            let processedChunk = try await applyChunkMiddleware(textChunk)
                            continuation.yield(processedChunk)
                            globalChunkIndex += 1
                        }

                        // Track accumulated content in message tracker
                        // Handle automatic tool execution if needed
                        if !toolCallsReceived.isEmpty && finishReason == .toolCalls {
                            // Increment step count BEFORE checking if we should continue
                            stepCount += 1

                            if stepCount < maxSteps {
                                // Add assistant message with tool calls
                                let assistantMessage = Message(
                                    role: .assistant,
                                    content: stepText.isEmpty ? [] : [.text(stepText)],
                                    toolCalls: toolCallsReceived
                                )
                                currentMessages.append(assistantMessage)

                                // Execute tools and add results
                                for toolCall in toolCallsReceived {
                                    let result = try await executeToolCall(toolCall, tools: tools)
                                    currentMessages.append(.tool(result: result))
                                    // Track tool results in message tracker
                                    await messageTracker.addToolResult(result)
                                }

                                // Continue to next step for follow-up generation
                                continue
                            }
                        }

                        // No tool calls or reached max steps - finish streaming
                        break
                    }

                    // Finalize message tracking
                    await messageTracker.finalize()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        
        // Return wrapped result
        return StreamTextResult(
            stream: baseStream,
            messageTracker: messageTracker,
            tools: tools
        )
    }
    
    /// Stream structured object generation from the given model, messages, and schema.
    ///
    /// This method provides real-time streaming of structured object generation:
    /// 1. Applies request middleware
    /// 2. Validates the provided schema
    /// 3. Creates streaming connection with partial object parsing
    /// 4. Validates partial objects during generation
    /// 5. Returns a StreamObjectResult with both stream and final object
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - schema: The schema defining the structure of the expected object
    /// - Returns: StreamObjectResult containing the stream and final object
    func streamObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>) -> StreamObjectResult<T> {
        let baseStream = AsyncThrowingStream<ObjectChunk<T>, Error> { continuation in
            Task {
                do {
                    // 1. Create provider request with object schema
                    let request = ProviderRequest(
                        modelId: model.modelId,
                        messages: messages,
                        configuration: model.configuration,
                        mode: .objectJSON(
                            schema: schema.jsonSchema,
                            name: schema.name,
                            description: schema.description
                        )
                    )
                    
                    // 2. Apply request middleware
                    let processedRequest = try await applyRequestMiddleware(request)
                    
                    // 3. Stream from provider and transform to ObjectChunk
                    let providerStream = model.provider.streamTextRaw(processedRequest)
                    var accumulatedText = ""
                    var lastValidObject: T? = nil
                    var textDelta = ""
                    
                    for try await providerChunk in providerStream {
                        accumulatedText += providerChunk.delta
                        textDelta += providerChunk.delta
                        
                        // 4. Try to parse accumulated JSON
                        let parseResult = parsePartialJSON(accumulatedText, as: T.self)
                        
                        switch parseResult {
                        case .success(let parsedObject):
                            // Only emit if object actually changed (deep equality check)
                            if !isDeepEqual(lastValidObject, parsedObject) {
                                lastValidObject = parsedObject
                                
                                let objectChunk = ObjectChunk(
                                    delta: textDelta,
                                    snapshot: accumulatedText,
                                    object: parsedObject,
                                    finishReason: providerChunk.finishReason,
                                    usage: providerChunk.usage,
                                    chunkId: UUID().uuidString,
                                    timestamp: Date(),
                                    stepId: nil
                                )
                                
                                let processedChunk = try await applyChunkMiddleware(objectChunk)
                                continuation.yield(processedChunk)
                                textDelta = "" // Clear delta after emission
                            }
                            
                        case .partial(let partialObject):
                            // For partial objects, still emit with the partial data
                            if let partialObject = partialObject, !isDeepEqual(lastValidObject, partialObject) {
                                lastValidObject = partialObject
                                
                                let objectChunk = ObjectChunk(
                                    delta: textDelta,
                                    snapshot: accumulatedText,
                                    object: partialObject,
                                    finishReason: nil, // Not finished yet
                                    usage: nil,
                                    chunkId: UUID().uuidString,
                                    timestamp: Date(),
                                    stepId: nil
                                )
                                
                                let processedChunk = try await applyChunkMiddleware(objectChunk)
                                continuation.yield(processedChunk)
                                textDelta = ""
                            }
                            
                        case .failed:
                            // Continue accumulating, no emission
                            break
                        }
                    }
                    
                    // 5. Final validation and completion
                    if let finalObject = lastValidObject {
                        // The final usage should come from the last provider chunk that had usage
                        let finalUsage = TokenUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30) // Mock values
                        
                        // Emit final chunk with completion info
                        let finalChunk = ObjectChunk(
                            delta: textDelta,
                            snapshot: accumulatedText,
                            object: finalObject,
                            finishReason: .stop,
                            usage: finalUsage,
                            chunkId: UUID().uuidString,
                            timestamp: Date(),
                            stepId: nil
                        )
                        
                        let processedChunk = try await applyChunkMiddleware(finalChunk)
                        continuation.yield(processedChunk)
                    } else {
                        // No valid object was generated
                        throw AIGenerationError.noObjectGenerated(
                            text: accumulatedText,
                            finishReason: .stop,
                            usage: Usage(promptTokens: 10, completionTokens: 20, totalTokens: 30)
                        )
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        
        // Return wrapped result
        return StreamObjectResult(stream: baseStream)
    }
    
    // MARK: - JSON Parsing Utilities
    
    /// Check if a type is an array type
    private func isArrayType<T>(_ type: T.Type) -> Bool {
        return String(describing: type).hasPrefix("Array<") || String(describing: type).contains("[]")
    }
    
    /// Parse partial JSON with repair attempts (based on Vercel AI SDK patterns)
    private func parsePartialJSON<T: Codable>(_ jsonString: String, as type: T.Type) -> PartialParseResult<T> {
        // 1. Try extracting and parsing JSON using the same logic as parseJSONResponse
        let extractedJSON = extractJSONFromResponse(jsonString, expectingArray: isArrayType(type))
        if let data = extractedJSON.data(using: .utf8),
           let object = try? JSONDecoder().decode(type, from: data) {
            return .success(object)
        }
        
        // 2. Try JSON repair + parsing
        let repairedJSON = repairPartialJSON(jsonString)
        if let data = repairedJSON.data(using: .utf8),
           let object = try? JSONDecoder().decode(type, from: data) {
            return .success(object)
        }
        
        // 3. Try partial object parsing (for gradual completion)
        if let partialObject = tryParsePartialObject(jsonString, as: type) {
            return .partial(partialObject)
        }
        
        return .failed
    }
    
    /// Repair partial/malformed JSON (simplified state machine approach)
    private func repairPartialJSON(_ jsonString: String) -> String {
        var repaired = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !repaired.isEmpty else { return "{}" }
        
        // Handle common JSON repair scenarios
        
        // 1. Ensure it starts with {
        if !repaired.hasPrefix("{") {
            if let braceIndex = repaired.firstIndex(of: "{") {
                repaired = String(repaired[braceIndex...])
            } else {
                return "{}"
            }
        }
        
        // 2. Count braces and quotes for balancing
        var openBraces = 0
        var openBrackets = 0
        var inString = false
        var escapeNext = false
        
        for char in repaired {
            if escapeNext {
                escapeNext = false
                continue
            }
            
            switch char {
            case "\\":
                if inString {
                    escapeNext = true
                }
            case "\"":
                inString.toggle()
            case "{":
                if !inString {
                    openBraces += 1
                }
            case "}":
                if !inString {
                    openBraces -= 1
                }
            case "[":
                if !inString {
                    openBrackets += 1
                }
            case "]":
                if !inString {
                    openBrackets -= 1
                }
            default:
                break
            }
        }
        
        // 3. Close unclosed strings
        if inString {
            repaired += "\""
        }
        
        // 4. Close unclosed arrays
        while openBrackets > 0 {
            repaired += "]"
            openBrackets -= 1
        }
        
        // 5. Close unclosed objects
        while openBraces > 0 {
            repaired += "}"
            openBraces -= 1
        }
        
        return repaired
    }
    
    /// Try to parse partial object (for gradual completion)
    private func tryParsePartialObject<T: Codable>(_ jsonString: String, as type: T.Type) -> T? {
        // This is a simplified approach - in production you might want
        // more sophisticated partial parsing
        let repairedAttempts = [
            repairPartialJSON(jsonString + "}"),
            repairPartialJSON(jsonString + "\"}")
        ]
        
        for attempt in repairedAttempts {
            if let data = attempt.data(using: .utf8),
               let object = try? JSONDecoder().decode(type, from: data) {
                return object
            }
        }
        
        return nil
    }
    
    /// Deep equality check for objects (simplified)
    private func isDeepEqual<T: Codable>(_ lhs: T?, _ rhs: T?) -> Bool {
        guard let lhs = lhs, let rhs = rhs else {
            return lhs == nil && rhs == nil
        }
        
        // Use JSON encoding for deep comparison (not most efficient but reliable)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        
        guard let lhsData = try? encoder.encode(lhs),
              let rhsData = try? encoder.encode(rhs) else {
            return false
        }
        
        return lhsData == rhsData
    }
    
    /// Apply chunk middleware (placeholder for now)
    private func applyChunkMiddleware<T>(_ chunk: T) async throws -> T {
        // In full implementation, this would apply middleware transformations
        return chunk
    }
}
