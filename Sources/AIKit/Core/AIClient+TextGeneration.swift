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
        precondition(maxSteps >= 1, "maxSteps must be at least 1")

        enum LoopStepState {
            case initial
            case toolResult
            case `continue`
            case done

            var generationStepType: StepType {
                switch self {
                case .initial:
                    return .initial
                case .toolResult:
                    return .toolResult
                case .continue:
                    return .continue
                case .done:
                    // `.done` is only used as an exit sentinel and should never be recorded.
                    return .initial
                }
            }
        }

        let debugParity = ProcessInfo.processInfo.environment["VERCEL_PARITY_DEBUG"] == "1"

        var conversationMessages = messages
        var responseMessages: [Message] = []
        var generationSteps: [GenerationStep] = []
        var accumulatedUsage: Usage? = nil
        var stepCount = 0
        var loopStep: LoopStepState = .initial
        var finalText = ""
        var finalFinishReason: FinishReason = .stop
        var finalResponseId: String?
        var finalTimestamp = Date()

        repeat {
            if debugParity {
                print("[AIKit] Step \(stepCount) (\(loopStep)) input messages:")
                for message in conversationMessages {
                    print("  - \(message.role.rawValue):", message.content)
                }
            }

            // Determine tool choice for this request, mirroring Vercel SDK defaults.
            let effectiveToolChoice: ToolChoice? = {
                if let explicit = toolChoice {
                    return explicit
                } else if let tools, !tools.isEmpty {
                    return .auto
                } else {
                    return nil
                }
            }()

            let mode: ProviderMode = {
                if let tools, !tools.isEmpty {
                    return .regular(tools: tools, toolChoice: effectiveToolChoice)
                } else {
                    return .regular(tools: nil, toolChoice: effectiveToolChoice)
                }
            }()

            let request = ProviderRequest(
                modelId: model.modelId,
                messages: conversationMessages,
                configuration: model.configuration,
                tools: tools,
                mode: mode
            )

            let processedRequest = try await applyRequestMiddleware(request)
            let providerResponse = try await model.provider.generateTextRaw(processedRequest)

            if debugParity {
                print(
                    "[AIKit] Step \(stepCount) finishReason=\(providerResponse.finishReason.rawValue) toolCalls=\(providerResponse.toolCalls?.count ?? 0) textLength=\(providerResponse.content.count)"
                )
            }

            accumulatedUsage = mergeUsage(accumulatedUsage, with: providerResponse.usage)
            finalFinishReason = providerResponse.finishReason
            finalResponseId = providerResponse.responseId
            finalTimestamp = providerResponse.timestamp

            let toolCalls = providerResponse.toolCalls ?? []
            var toolResults: [ToolResult] = []
            if !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    let result = try await executeToolCall(toolCall, tools: tools)
                    toolResults.append(result)
                }
            }

            let stepText = providerResponse.content

            stepCount += 1
            var nextLoopStep: LoopStepState = .done
            if stepCount < maxSteps {
                if !toolCalls.isEmpty && toolResults.count == toolCalls.count {
                    nextLoopStep = .toolResult
                }
            }

            let stepMessages = StepMessageBuilder.buildMessages(
                text: stepText,
                toolCalls: toolCalls,
                toolResults: toolResults,
                messageId: providerResponse.responseId ?? UUID().uuidString
            )

            responseMessages.append(contentsOf: stepMessages)
            conversationMessages = messages + responseMessages

            if !stepText.isEmpty {
                if loopStep == .continue || nextLoopStep == .continue {
                    finalText += stepText
                } else {
                    finalText = stepText
                }
            }

            let recordedStep = GenerationStep(
                stepType: loopStep.generationStepType,
                timestamp: providerResponse.timestamp,
                usage: providerResponse.usage,
                messages: stepMessages.isEmpty ? nil : stepMessages,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                toolResults: toolResults.isEmpty ? nil : toolResults,
                metadata: providerResponse.providerMetadata
            )
            generationSteps.append(recordedStep)

            if debugParity {
                print(
                    "[AIKit] Recorded step type=\(recordedStep.stepType.rawValue) toolCalls=\(toolCalls.count) toolResults=\(toolResults.count)"
                )
            }

            loopStep = nextLoopStep
        } while loopStep != .done

        let normalizedSteps = mergeToolOnlyContinuationSteps(generationSteps)

        if debugParity {
            print("[AIKit] Final step sequence:", normalizedSteps.map { $0.stepType.rawValue })
            for (index, step) in normalizedSteps.enumerated() {
                let ids = step.toolCalls?.map { $0.id } ?? []
                let resultCount = step.toolResults?.count ?? 0
                let hasText = stepContainsText(step)
                print("[AIKit] Step #\(index) type=\(step.stepType.rawValue) callIds=\(ids) resultCount=\(resultCount) hasText=\(hasText)")
            }
        }

        let finalUsage = accumulatedUsage ?? Usage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
        let response = TextResponse(
            text: finalText,
            finishReason: finalFinishReason,
            usage: finalUsage,
            messages: conversationMessages,
            steps: normalizedSteps.isEmpty ? nil : normalizedSteps,
            responseId: finalResponseId,
            modelId: model.modelId,
            timestamp: finalTimestamp,
            warnings: nil,
            responseHeaders: nil
        )

        return try await applyResponseMiddleware(response)
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

// MARK: - Usage Helpers

private func mergeUsage(_ existing: Usage?, with additional: Usage) -> Usage {
    guard let existing else { return additional }
    return Usage(
        promptTokens: existing.promptTokens + additional.promptTokens,
        completionTokens: existing.completionTokens + additional.completionTokens,
        totalTokens: existing.totalTokens + additional.totalTokens,
        promptCost: sumOptionals(existing.promptCost, additional.promptCost),
        completionCost: sumOptionals(existing.completionCost, additional.completionCost),
        totalCost: sumOptionals(existing.totalCost, additional.totalCost),
        currency: existing.currency ?? additional.currency,
        details: mergeDetails(existing.details, additional.details)
    )
}

private func mergeToolOnlyContinuationSteps(_ steps: [GenerationStep]) -> [GenerationStep] {
    return steps
}

private func stepContainsText(_ step: GenerationStep) -> Bool {
    guard let messages = step.messages else { return false }
    return messages.flatMap { $0.content }.contains { content in
        if case .text(let value) = content {
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}

private func mergeMetadataDictionaries(_ lhs: [String: String]?, _ rhs: [String: String]?) -> [String: String]? {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l.merging(r) { _, new in new }
    case (let l?, nil):
        return l
    case (nil, let r?):
        return r
    default:
        return nil
    }
}

private func sumOptionals(_ lhs: Double?, _ rhs: Double?) -> Double? {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l + r
    case (let l?, nil):
        return l
    case (nil, let r?):
        return r
    default:
        return nil
    }
}

private func mergeDetails(_ lhs: [String: String]?, _ rhs: [String: String]?) -> [String: String]? {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l.merging(r, uniquingKeysWith: { _, new in new })
    case (let l?, nil):
        return l
    case (nil, let r?):
        return r
    default:
        return nil
    }
}
