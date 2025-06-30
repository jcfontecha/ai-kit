import Foundation

// MARK: - Text Generation

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
    ///   - toolChoice: Strategy for tool selection (auto, required, none, or specific tool)
    ///   - maxSteps: Maximum number of tool execution steps (default: 1 for single call)
    /// - Returns: A `TextResponse` containing the generated text and metadata
    /// - Throws: `AIError` for various failure conditions
    func generateText(_ model: LanguageModel, messages: [Message], tools: [Tool]? = nil, toolChoice: ToolChoice? = nil, maxSteps: Int = 1) async throws -> TextResponse {
        // Multi-step execution implementation following Vercel AI SDK pattern
        var currentMessages = messages
        var allSteps: [GenerationStep] = []
        var totalUsage = Usage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
        
        for stepIndex in 0..<maxSteps {
            // 1. Create provider request for this step
            // Use provided toolChoice or default to 'auto' when tools are provided
            let effectiveToolChoice: ToolChoice? = {
                if let explicitChoice = toolChoice {
                    return explicitChoice
                } else if let tools = tools, !tools.isEmpty {
                    return .auto
                } else {
                    return nil
                }
            }()
            
            let mode: ProviderMode = {
                if let tools = tools, !tools.isEmpty {
                    return .regular(tools: tools, toolChoice: effectiveToolChoice)
                } else {
                    return .regular(tools: nil, toolChoice: effectiveToolChoice)
                }
            }()
            
            let request = ProviderRequest(
                modelId: model.modelId,
                messages: currentMessages,
                configuration: model.configuration,
                tools: tools,
                mode: mode
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
                        let result = try await executeToolCall(toolCall, tools: tools)
                        toolResults.append(result)
                    }
                    
                    // Step 3: Add assistant message with tool calls, then tool results to conversation
                    // Create assistant message with both text content and tool calls if text exists
                    let assistantContent: [MessageContent]
                    if !providerResponse.content.isEmpty {
                        // Include both text and tool calls
                        assistantContent = [.text(providerResponse.content)] + toolCalls.map { .toolCall($0) }
                    } else {
                        // Just tool calls
                        assistantContent = toolCalls.map { .toolCall($0) }
                    }
                    
                    let assistantMessage = Message(
                        role: .assistant,
                        content: assistantContent,
                        toolCalls: toolCalls
                    )
                    currentMessages.append(assistantMessage)
                    
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
                    // Create assistant message with both text content and tool calls if text exists
                    let assistantContent: [MessageContent]
                    if !providerResponse.content.isEmpty {
                        // Include both text and tool calls
                        assistantContent = [.text(providerResponse.content)] + toolCalls.map { .toolCall($0) }
                    } else {
                        // Just tool calls
                        assistantContent = toolCalls.map { .toolCall($0) }
                    }
                    
                    let assistantMessage = Message(
                        role: .assistant,
                        content: assistantContent,
                        toolCalls: toolCalls
                    )
                    currentMessages.append(assistantMessage)
                    
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
    
    /// Generate text from a simple string prompt with tools support.
    ///
    /// This is a convenience method that wraps the prompt in a user message
    /// and calls the full `generateText` method with tools.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    ///   - tools: Optional array of tools available for the model to call
    ///   - toolChoice: Strategy for tool selection (auto, required, none, or specific tool)
    ///   - maxSteps: Maximum number of tool execution steps (default: 1 for single call)
    /// - Returns: A `TextResponse` containing the generated text and metadata
    /// - Throws: `AIError` for various failure conditions
    func generateText(_ model: LanguageModel, prompt: String, tools: [Tool], toolChoice: ToolChoice? = nil, maxSteps: Int = 1) async throws -> TextResponse {
        let messages = [Message.user(prompt)]
        return try await generateText(model, messages: messages, tools: tools, toolChoice: toolChoice, maxSteps: maxSteps)
    }
    
    /// Generate text with explicit JSON mode.
    ///
    /// This method forces the model to respond in JSON format by setting the
    /// generation mode explicitly.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    ///   - mode: The generation mode (e.g., .json for JSON output)
    /// - Returns: A `TextResponse` containing the generated text and metadata
    /// - Throws: `AIError` for various failure conditions
    func generateText(_ model: LanguageModel, prompt: String, mode: GenerationMode) async throws -> TextResponse {
        let messages = [Message.user(prompt)]
        
        // For JSON mode, we need to create a provider request with explicit JSON mode
        if mode == .json {
            // Create a special request that forces JSON output
            let request = ProviderRequest(
                modelId: model.modelId,
                messages: messages,
                configuration: model.configuration,
                mode: .objectJSON(
                    schema: JSONSchema.object(properties: [:]),
                    name: nil,
                    description: "Generate a valid JSON object"
                )
            )
            
            // Apply request middleware
            let processedRequest = try await applyRequestMiddleware(request)
            
            // Call provider directly for JSON mode
            let providerResponse = try await model.provider.generateTextRaw(processedRequest)
            
            // Build response
            let textResponse = TextResponse(
                text: providerResponse.content,
                finishReason: providerResponse.finishReason,
                usage: Usage(
                    promptTokens: providerResponse.usage.promptTokens,
                    completionTokens: providerResponse.usage.completionTokens,
                    totalTokens: providerResponse.usage.totalTokens
                ),
                messages: messages + [Message.assistant(providerResponse.content)],
                steps: nil,
                responseId: nil,
                modelId: model.modelId,
                timestamp: Date(),
                warnings: nil,
                responseHeaders: nil
            )
            
            return try await applyResponseMiddleware(textResponse)
        } else {
            // For other modes, use the basic method
            return try await generateText(model, messages: messages)
        }
    }
}