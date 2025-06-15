import Foundation

// MARK: - Text Generation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AIClient {
    
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
    func generateText(_ model: LanguageModel, messages: [Message], tools: [Tool]? = nil, maxSteps: Int = 1) async throws -> TextResponse {
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
    func generateText(_ model: LanguageModel, prompt: String) async throws -> TextResponse {
        let messages = [Message.user(prompt)]
        return try await generateText(model, messages: messages)
    }
}