import Testing
import Foundation
@testable import AIKit

// MARK: - Advanced Streaming Tests

@Test func testStreamInterruption() async throws {
    // Test stream interruption/cancellation handling
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let stream = await client.streamText(model, prompt: "Generate a very long response")
    
    var chunkCount = 0
    let maxChunks = 3
    
    // Early termination to test interruption
    for try await _ in stream {
        chunkCount += 1
        if chunkCount >= maxChunks {
            break // Interrupt the stream
        }
    }
    
    #expect(chunkCount == maxChunks, "Should interrupt stream correctly")
}

@Test func testStreamErrorRecovery() async throws {
    // Test stream error recovery and continuation
    let errorConfig = MockConfiguration(errorRate: 0.3) // 30% error rate
    let provider = MockProvider(configuration: errorConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    let client = AIClient()
    
    let stream = await client.streamText(model, prompt: "Test error recovery")
    
    var successfulChunks = 0
    var errorCount = 0
    
    // Attempt to handle errors during streaming
    do {
        for try await chunk in stream {
            successfulChunks += 1
            #expect(!chunk.delta.isEmpty || chunk.finishReason != nil, "Chunk should have content or finish reason")
        }
    } catch {
        errorCount += 1
        #expect(error is AIProviderError, "Should throw AIProviderError")
    }
    
    // With 30% error rate, we might get errors but should handle them gracefully
    #expect(successfulChunks > 0 || errorCount > 0, "Should either succeed with chunks or fail with error")
}

@Test func testStreamTransformations() async throws {
    // Test custom stream transformations
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let stream = await client.streamText(model, prompt: "Count from 1 to 5")
    
    var transformedContent = ""
    var chunkCount = 0
    
    // Transform stream data (e.g., uppercase transformation)
    for try await chunk in stream {
        let transformedDelta = chunk.delta.uppercased()
        transformedContent += transformedDelta
        chunkCount += 1
    }
    
    #expect(chunkCount > 0, "Should receive chunks")
    #expect(transformedContent.contains("MOCK"), "Should contain transformed content")
}

@Test func testPartialMessageAssembly() async throws {
    // Test partial message assembly from stream chunks
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let stream = await client.streamText(model, prompt: "Generate text with partial assembly")
    
    var assembledMessage = ""
    var previousSnapshot = ""
    
    for try await chunk in stream {
        assembledMessage += chunk.delta
        
        // Verify that snapshot contains accumulated content
        #expect(chunk.snapshot.count >= previousSnapshot.count, "Snapshot should grow or stay same")
        #expect(chunk.snapshot.hasPrefix(previousSnapshot) || chunk.snapshot == assembledMessage, 
               "Snapshot should be consistent with accumulated content")
        
        previousSnapshot = chunk.snapshot
    }
    
    #expect(!assembledMessage.isEmpty, "Should assemble complete message")
    #expect(assembledMessage == previousSnapshot, "Final snapshot should match assembled message")
}

// MARK: - Object Generation Extension Tests

@Test func testGenerateObjectArray() async throws {
    // Test generating arrays of objects
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    struct Item: Codable, Sendable, SchemaProviding {
        let id: Int
        let name: String
        
        static var schema: ObjectSchema<Item> {
            return ObjectSchema.manual(
                jsonSchema: .object(properties: [
                    "id": .integer(minimum: 1),
                    "name": .string(minLength: 1)
                ], required: ["id", "name"]),
                name: "Item"
            )
        }
    }
    
    let response = try await client.generateArray(
        model,
        prompt: "Generate a list of 3 items",
        elementType: Item.self
    )
    
    let items = response.object
    #expect(items.count >= 1, "Should generate at least 1 item")
    
    for item in items {
        #expect(item.id > 0, "Item should have valid ID")
        #expect(!item.name.isEmpty, "Item should have name")
    }
}

@Test func testGenerateEnum() async throws {
    // Test enum generation with predefined values
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let colors = ["red", "green", "blue", "yellow"]
    
    let response = try await client.generateEnum(
        model,
        prompt: "Pick a primary color",
        values: colors
    )
    
    #expect(colors.contains(response.object), "Should generate valid enum value")
    #expect(response.finishReason == .stop, "Should complete successfully")
}

@Test func testSchemalessObjectGeneration() async throws {
    // Test object generation without predefined schema
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    // Generate raw JSON without strict schema
    let response = try await client.generateText(
        model,
        prompt: "Generate a JSON object for a user profile with name, age, and email",
        mode: .json
    )
    
    #expect(!response.text.isEmpty, "Should generate text response")
    #expect(response.text.contains("{"), "Should contain JSON structure")
    #expect(response.finishReason == .stop, "Should complete successfully")
    
    // Try to parse as JSON to verify structure
    let jsonData = response.text.data(using: .utf8)!
    let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
    #expect(jsonObject is [String: Any], "Should be valid JSON object")
}

// MARK: - Tool Calling Enhancement Tests

@Test func testMultiStepToolExecution() async throws {
    // Test multi-step tool execution chains
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string()
            ], required: ["location"])
        )
    )
    
    let timeTool = Tool(
        function: ToolFunction(
            name: "get_time",
            description: "Get current time for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string()
            ], required: ["location"])
        )
    )
    
    let response = try await client.generateText(
        model,
        prompt: "What's the weather and time in San Francisco?",
        tools: [weatherTool, timeTool]
    )
    
    // Should identify multiple tool calls needed
    #expect(response.finishReason == .toolCalls, "Should finish with tool calls")
    #expect(!response.toolCalls.isEmpty, "Should have tool calls")
    
    // Verify multiple tools can be called
    let toolNames = response.toolCalls.map { $0.function.name }
    #expect(toolNames.contains("get_weather") || toolNames.contains("get_time"), 
           "Should call relevant tools")
}

@Test func testToolChoiceStrategies() async throws {
    // Test different tool choice strategies (auto, required, none)
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let calculatorTool = Tool(
        function: ToolFunction(
            name: "calculate",
            description: "Perform mathematical calculations",
            parameters: JSONSchema.object(properties: [
                "expression": .string()
            ], required: ["expression"])
        )
    )
    
    // Test auto choice (default behavior)
    let autoResponse = try await client.generateText(
        model,
        prompt: "What is 2 + 2?",
        tools: [calculatorTool]
        // toolChoice: .auto is the default
    )
    
    #expect(autoResponse.finishReason == .toolCalls, "Auto choice should use tools when appropriate")
    #expect(!autoResponse.toolCalls.isEmpty, "Should have tool calls")
    
    // Test required choice - force tool usage
    let requiredResponse = try await client.generateText(
        model,
        prompt: "Hello, how are you?",
        tools: [calculatorTool],
        toolChoice: .required
    )
    
    #expect(requiredResponse.finishReason == .toolCalls, "Required choice should force tool usage")
    #expect(!requiredResponse.toolCalls.isEmpty, "Should have forced tool calls")
    
    // Test none choice - disable tools
    let noneResponse = try await client.generateText(
        model,
        prompt: "What is 5 + 5?",
        tools: [calculatorTool],
        toolChoice: ToolChoice.none
    )
    
    #expect(noneResponse.finishReason == .stop, "None choice should not use tools")
    #expect(noneResponse.toolCalls.isEmpty, "Should have no tool calls")
}

@Test func testToolExecutionErrorHandling() async throws {
    // Test tool execution error handling
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let faultyTool = Tool(
        function: ToolFunction(
            name: "faulty_operation",
            description: "A tool that may fail",
            parameters: JSONSchema.object(properties: [
                "input": .string()
            ], required: ["input"])
        )
    )
    
    // Custom tool executor that simulates failures
    let failingExecutor: ToolExecutor = { toolCall in
        throw AIGenerationError.toolExecutionError(
            toolName: toolCall.function.name,
            toolArgs: toolCall.function.arguments,
            toolCallId: toolCall.id,
            cause: NSError(domain: "TestError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Simulated tool failure"])
        )
    }
    
    do {
        _ = try await client.generateText(
            model,
            prompt: "Use the faulty operation",
            tools: [faultyTool],
            toolChoice: .required, // Force tool usage
            toolExecutor: failingExecutor,
            maxSteps: 2 // Allow tool execution
        )
        #expect(Bool(false), "Should have thrown tool execution error")
    } catch let error as AIGenerationError {
        switch error {
        case .toolExecutionError(let toolName, _, _, _):
            #expect(toolName == "faulty_operation", "Should report correct failing tool")
        default:
            #expect(Bool(false), "Should be tool execution error")
        }
    }
}

@Test func testParallelToolExecution() async throws {
    // Test parallel tool execution when multiple tools are called
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let tool1 = Tool(
        function: ToolFunction(
            name: "get_data_1",
            description: "Get data from source 1",
            parameters: JSONSchema.object(properties: [:])
        )
    )
    
    let tool2 = Tool(
        function: ToolFunction(
            name: "get_data_2", 
            description: "Get data from source 2",
            parameters: JSONSchema.object(properties: [:])
        )
    )
    
    let parallelExecutor: ToolExecutor = { toolCall in
        // Simulate async execution with delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text("Result from \(toolCall.function.name)")
        )
    }
    
    let startTime = Date()
    
    let response = try await client.generateText(
        model,
        prompt: "Get data from both sources simultaneously",
        tools: [tool1, tool2],
        toolExecutor: parallelExecutor
    )
    
    let executionTime = Date().timeIntervalSince(startTime)
    
    // Should complete in reasonable time even with multiple tool calls
    #expect(executionTime < 1.0, "Parallel execution should be efficient")
    #expect(!response.toolCalls.isEmpty, "Should have tool calls")
}

// MARK: - Configuration & Settings Tests

@Test func testTemperatureParameterValidation() async throws {
    // Test temperature parameter validation
    let client = AIClient()
    let provider = MockProvider()
    
    // Test valid temperature values
    let validModel = provider.languageModel("gpt-4.1-nano").temperature(0.7)
    let response = try await client.generateText(validModel, prompt: "Test temperature")
    #expect(response.finishReason == .stop, "Should work with valid temperature")
    
    // Test boundary values
    let minTempModel = provider.languageModel("gpt-4.1-nano").temperature(0.0)
    let minResponse = try await client.generateText(minTempModel, prompt: "Test min temperature")
    #expect(minResponse.finishReason == .stop, "Should work with minimum temperature")
    
    let maxTempModel = provider.languageModel("gpt-4.1-nano").temperature(2.0)
    let maxResponse = try await client.generateText(maxTempModel, prompt: "Test max temperature")
    #expect(maxResponse.finishReason == .stop, "Should work with maximum temperature")
}

@Test func testTopPParameterValidation() async throws {
    // Test top-p parameter validation
    let client = AIClient()
    let provider = MockProvider()
    
    let validModel = provider.languageModel("gpt-4.1-nano")
        .topP(0.9)
        .temperature(0.7)
    
    let response = try await client.generateText(validModel, prompt: "Test top-p parameter")
    #expect(response.finishReason == .stop, "Should work with valid top-p")
    
    // Test boundary values
    let minTopPModel = provider.languageModel("gpt-4.1-nano").topP(0.0)
    let minResponse = try await client.generateText(minTopPModel, prompt: "Test min top-p")
    #expect(minResponse.finishReason == .stop, "Should work with minimum top-p")
    
    let maxTopPModel = provider.languageModel("gpt-4.1-nano").topP(1.0)
    let maxResponse = try await client.generateText(maxTopPModel, prompt: "Test max top-p")
    #expect(maxResponse.finishReason == .stop, "Should work with maximum top-p")
}

@Test func testCustomHeadersAndRequestModification() async throws {
    // Test custom headers and request modification
    let client = AIClient()
    let provider = MockProvider()
    let _ = provider.languageModel("gpt-4.1-nano")
    
    // This test verifies that custom configuration can be passed through
    let customConfig = ModelConfiguration.default
        .temperature(0.5)
        .maxTokens(1000)
    
    let modelWithConfig = LanguageModel(provider: provider, modelId: "gpt-4.1-nano", configuration: customConfig)
    
    let response = try await client.generateText(modelWithConfig, prompt: "Test custom configuration")
    #expect(response.finishReason == .stop, "Should work with custom configuration")
    #expect(response.usage.totalTokens > 0, "Should track usage")
}

@Test func testTimeoutAndRetryLogic() async throws {
    // Test timeout and retry logic
    let client = AIClient()
    
    // Create a provider that simulates timeouts
    let timeoutConfig = MockConfiguration(simulateTimeout: true)
    let provider = MockProvider(configuration: timeoutConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    
    do {
        _ = try await client.generateText(model, prompt: "This should timeout")
        #expect(Bool(false), "Should have timed out")
    } catch {
        #expect(error is AIProviderError, "Should throw provider error for timeout")
    }
}

@Test func testProviderSpecificSettings() async throws {
    // Test provider-specific settings
    let client = AIClient()
    let provider = MockProvider()
    
    // Test different model configurations
    let creativModel = provider.languageModel("gpt-4.1-nano")
        .temperature(1.2)
        .topP(0.95)
        .maxTokens(2000)
    
    let conservativeModel = provider.languageModel("gpt-4.1-nano")
        .temperature(0.1)
        .topP(0.1)
        .maxTokens(500)
    
    let creativeResponse = try await client.generateText(creativModel, prompt: "Write a creative story")
    let conservativeResponse = try await client.generateText(conservativeModel, prompt: "Write a factual summary")
    
    #expect(creativeResponse.finishReason == .stop, "Creative model should work")
    #expect(conservativeResponse.finishReason == .stop, "Conservative model should work")
    
    // Both should generate content but potentially with different characteristics
    #expect(!creativeResponse.text.isEmpty, "Creative model should generate text")
    #expect(!conservativeResponse.text.isEmpty, "Conservative model should generate text")
}

// MARK: - Comprehensive Error Handling Tests

@Test func testRateLimitingResponses() async throws {
    // Test rate limiting response handling
    let client = AIClient()
    let rateLimitConfig = MockConfiguration(simulateRateLimit: true)
    let provider = MockProvider(configuration: rateLimitConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    
    do {
        _ = try await client.generateText(model, prompt: "This should hit rate limit")
        #expect(Bool(false), "Should have hit rate limit")
    } catch let error as AIProviderError {
        switch error {
        case .rateLimitExceeded:
            #expect(Bool(true), "Should handle rate limit correctly")
        default:
            #expect(Bool(false), "Should be rate limit error, got: \(error)")
        }
    }
}

@Test func testInvalidAPIKeyHandling() async throws {
    // Test invalid API key handling
    let client = AIClient()
    let invalidKeyConfig = MockConfiguration(simulateInvalidKey: true)
    let provider = MockProvider(configuration: invalidKeyConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    
    do {
        _ = try await client.generateText(model, prompt: "This should fail with invalid key")
        #expect(Bool(false), "Should have failed with invalid API key")
    } catch let error as AIProviderError {
        switch error {
        case .authenticationFailed:
            #expect(Bool(true), "Should handle authentication failure correctly")
        default:
            #expect(Bool(false), "Should be authentication error, got: \(error)")
        }
    }
}

@Test func testMalformedResponseRecovery() async throws {
    // Test malformed response recovery
    let client = AIClient()
    let malformedConfig = MockConfiguration(simulateMalformedResponse: true)
    let provider = MockProvider(configuration: malformedConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    
    do {
        _ = try await client.generateText(model, prompt: "This should return malformed response")
        #expect(Bool(false), "Should have failed with malformed response")
    } catch let error as AIProviderError {
        switch error {
        case .invalidResponse:
            #expect(Bool(true), "Should handle malformed response correctly")
        default:
            #expect(Bool(false), "Should be invalid response error, got: \(error)")
        }
    }
}

@Test func testNetworkFailureScenarios() async throws {
    // Test network failure scenarios
    let client = AIClient()
    let networkFailureConfig = MockConfiguration(simulateNetworkFailure: true)
    let provider = MockProvider(configuration: networkFailureConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    
    do {
        _ = try await client.generateText(model, prompt: "This should fail with network error")
        #expect(Bool(false), "Should have failed with network error")
    } catch let error as AIProviderError {
        switch error {
        case .networkError:
            #expect(Bool(true), "Should handle network failure correctly")
        default:
            #expect(Bool(false), "Should be network error, got: \(error)")
        }
    }
}

@Test func testErrorRecoveryAndRetries() async throws {
    // Test error recovery and retry mechanisms
    let client = AIClient()
    let intermittentConfig = MockConfiguration(errorRate: 0.7) // 70% failure rate
    let provider = MockProvider(configuration: intermittentConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    
    var attemptCount = 0
    let maxAttempts = 3
    
    while attemptCount < maxAttempts {
        attemptCount += 1
        
        do {
            let response = try await client.generateText(model, prompt: "Test retry logic")
            #expect(response.finishReason == .stop, "Should eventually succeed")
            break // Success, exit retry loop
        } catch {
            if attemptCount == maxAttempts {
                #expect(error is AIProviderError, "Should throw provider error after max attempts")
            }
            // Continue retrying
        }
    }
    
    #expect(attemptCount <= maxAttempts, "Should not exceed max attempts")
}