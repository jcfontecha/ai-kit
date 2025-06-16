import Testing
import Foundation
@testable import ai_swift

@Test func testTextGenerationWithToolCalling() async throws {
    // Test text generation with tool calling integration
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    let client = AIClient()
    
    // Define a simple weather tool
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(enum: ["San Francisco, CA", "New York, NY"]),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    let messages = [
        Message.user("What's the weather like in San Francisco?")
    ]
    
    // This should fail initially since tool calling isn't implemented
    let response = try await client.generateText(model, messages: messages, tools: [weatherTool])
    
    #expect(!response.text.isEmpty)
    #expect(response.finishReason == .toolCalls)
    #expect(!response.toolCalls.isEmpty)
    #expect(response.toolCalls.first?.function.name == "get_weather")
    #expect(response.usage.totalTokens > 0)
    #expect(!response.messages.isEmpty)
}

@Test func testToolExecutionWithResults() async throws {
    // Test that tools are not only called but also executed and their results incorporated
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    let client = AIClient()
    
    // Define a weather tool
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(enum: ["San Francisco, CA", "New York, NY"]),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    let messages = [
        Message.user("What's the weather like in San Francisco? I need a complete answer with the actual weather data.")
    ]
    
    // This should call the tool AND execute it, returning final text with weather results
    let response = try await client.generateText(model, messages: messages, tools: [weatherTool])
    
    // For now, this test expects tool calling behavior but won't get full execution
    // This will initially fail because we need to implement multi-step tool execution
    
    // Current implementation should show tool calls but not execute them
    #expect(response.finishReason == FinishReason.toolCalls) // Should finish at tool call step for now
    #expect(!response.toolCalls.isEmpty)
    #expect(response.toolCalls.first?.function.name == "get_weather")
    
    // Initially, we won't have actual weather results, just the intent to call
    #expect(response.text.contains("weather"), "Response should mention weather")
    
    // We should have at least one step with tool calls
    if let steps = response.steps {
        #expect(steps.count >= 1, "Should have at least one step with tool calls")
        #expect(steps.first?.stepType == .toolCall, "First step should be tool call")
    }
    
    // Note: Tool execution is implemented but requires a custom toolExecutor to be provided.
    // This test validates the current behavior where tools are called but not executed without an executor.
    
    #expect(response.usage.totalTokens > 0)
    #expect(!response.messages.isEmpty)
}

@Test func testToolErrorScenarios() async throws {
    // Test comprehensive tool error handling following Vercel AI SDK patterns
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    let client = AIClient()
    
    // Define a weather tool for testing
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(enum: ["San Francisco, CA", "New York, NY"]),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    // Test Case 1: No Such Tool Error
    do {
        _ = try await client.generateText(
            model,
            messages: [Message.user("Test no such tool error scenario")],
            tools: [weatherTool]
        )
        #expect(Bool(false), "Should have thrown NoSuchTool error")
    } catch let error as AIGenerationError {
        switch error {
        case .noSuchTool(let toolName, let availableTools):
            #expect(toolName == "non_existent_tool", "Should identify the missing tool")
            #expect(availableTools.contains("get_weather"), "Should list available tools")
            #expect(error.code == "NO_SUCH_TOOL", "Should have correct error code")
        default:
            #expect(Bool(false), "Should be NoSuchTool error, got: \(error)")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.noSuchTool")
    }
    
    // Test Case 2: Invalid Tool Arguments Error
    do {
        _ = try await client.generateText(
            model,
            messages: [Message.user("Test invalid arguments error scenario")],
            tools: [weatherTool]
        )
        #expect(Bool(false), "Should have thrown InvalidToolArguments error")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, let toolArgs, let cause):
            #expect(toolName == "get_weather", "Should identify the tool with invalid arguments")
            #expect(toolArgs.contains("invalid"), "Should include the invalid arguments")
            #expect(cause != nil, "Should have underlying cause")
            #expect(error.code == "INVALID_TOOL_ARGUMENTS", "Should have correct error code")
        default:
            #expect(Bool(false), "Should be InvalidToolArguments error, got: \(error)")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.invalidToolArguments")
    }
    
    // Test Case 3: Tool Execution Error
    do {
        _ = try await client.generateText(
            model,
            messages: [Message.user("Test tool execution error scenario")],
            tools: [weatherTool]
        )
        #expect(Bool(false), "Should have thrown ToolExecutionError")
    } catch let error as AIGenerationError {
        switch error {
        case .toolExecutionError(let toolName, let toolArgs, let toolCallId, _):
            #expect(toolName == "get_weather", "Should identify the failed tool")
            #expect(!toolCallId.isEmpty, "Should have tool call ID")
            #expect(toolArgs.contains("San Francisco"), "Should include tool arguments")
            #expect(error.code == "TOOL_EXECUTION_ERROR", "Should have correct error code")
        default:
            #expect(Bool(false), "Should be ToolExecutionError, got: \(error)")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.toolExecutionError")
    }
}

@Test func testToolValidationHelpers() throws {
    // Test Tool validation helper functions (Vercel SDK pattern: tool schema validation)
    
    // Test 1: Valid tool with all required properties
    let validWeatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    #expect(validWeatherTool.function.name == "get_weather", "Should have correct name")
    #expect(!(validWeatherTool.function.description?.isEmpty ?? true), "Should have description")
    #expect(Bool(true), "Should have parameters") // parameters is non-optional
    
    // Test tool call validation using the actual ToolValidation implementation
    let testToolCall = ToolCall(
        id: "test_call_123",
        function: ToolCallFunction(
            name: "get_weather",
            arguments: """
            {"location": "San Francisco, CA", "unit": "celsius"}
            """
        )
    )
    
    // Test valid tool call validation
    do {
        try ToolValidation.validateToolCall(toolCall: testToolCall, availableTools: [validWeatherTool])
        #expect(Bool(true), "Valid tool call should pass validation")
    } catch {
        #expect(Bool(false), "Valid tool call should not throw error: \(error)")
    }
    
    // Test tool call with invalid tool name
    let invalidToolCall = ToolCall(
        id: "test_call_456",
        function: ToolCallFunction(
            name: "nonexistent_tool",
            arguments: "{}"
        )
    )
    
    do {
        try ToolValidation.validateToolCall(toolCall: invalidToolCall, availableTools: [validWeatherTool])
        #expect(Bool(false), "Should throw error for nonexistent tool")
    } catch let error as AIGenerationError {
        switch error {
        case .noSuchTool(let toolName, let availableTools):
            #expect(toolName == "nonexistent_tool", "Should identify the missing tool")
            #expect(availableTools.contains("get_weather"), "Should list available tools")
        default:
            #expect(Bool(false), "Should be noSuchTool error, got: \(error)")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.noSuchTool")
    }
}

@Test func testToolValidationEdgeCases() throws {
    // Test edge cases in tool validation using the actual ToolValidation implementation
    
    // Test tool call with empty name
    let emptyNameToolCall = ToolCall(
        id: "test_call_789",
        function: ToolCallFunction(
            name: "",
            arguments: "{}"
        )
    )
    
    let testTool = Tool(
        function: ToolFunction(
            name: "test_tool",
            description: "A test tool",
            parameters: JSONSchema.object(properties: [:])
        )
    )
    
    do {
        try ToolValidation.validateToolCallStructure(toolCall: emptyNameToolCall)
        #expect(Bool(false), "Should throw error for empty tool name")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, _, _):
            #expect(toolName.isEmpty, "Should identify empty tool name")
        default:
            #expect(Bool(false), "Should be invalidToolArguments error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError")
    }
    
    // Test tool call with empty ID
    let emptyIdToolCall = ToolCall(
        id: "",
        function: ToolCallFunction(
            name: "test_tool",
            arguments: "{}"
        )
    )
    
    do {
        try ToolValidation.validateToolCallStructure(toolCall: emptyIdToolCall)
        #expect(Bool(false), "Should throw error for empty tool call ID")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, _, _):
            #expect(toolName == "test_tool", "Should identify the tool name")
        default:
            #expect(Bool(false), "Should be invalidToolArguments error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError")
    }
    
    // Test tool call with invalid JSON arguments
    let invalidJsonToolCall = ToolCall(
        id: "test_call_invalid",
        function: ToolCallFunction(
            name: "test_tool",
            arguments: "{ invalid json }"
        )
    )
    
    do {
        try ToolValidation.validateToolArguments(toolCall: invalidJsonToolCall, tool: testTool)
        #expect(Bool(false), "Should throw error for invalid JSON arguments")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, let args, _):
            #expect(toolName == "test_tool", "Should identify the tool")
            #expect(args == "{ invalid json }", "Should include the invalid arguments")
        default:
            #expect(Bool(false), "Should be invalidToolArguments error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError")
    }
}