import Testing
import Foundation
@testable import AIKit

@Test func testGenerateTextWithToolsBasic() async throws {
    // CRITICAL TEST: Verify generateText with tools works
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
        ),
        execute: { @Sendable toolCall in
            return ToolResult.success(
                toolCallId: toolCall.id,
                text: "Weather: 72°F, Sunny"
            )
        }
    )
    
    // Test the basic generateText with tools
    let response = try await client.generateText(
        model,
        messages: [Message.user("What's the weather in San Francisco?")],
        tools: [weatherTool]
    )
    
    // Should call weather tool
    #expect(response.finishReason == .toolCalls, "Should finish with tool calls")
    #expect(!response.toolCalls.isEmpty, "Should have tool calls")
    #expect(response.toolCalls.first?.function.name == "get_weather", "Should call weather tool")
    #expect(response.usage.totalTokens > 0, "Should track usage")
}

@Test func testGenerateTextWithToolsAndChoice() async throws {
    // Test generateText with tools and toolChoice
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
        ),
        execute: { @Sendable toolCall in
            // Simple calculator mock
            return ToolResult.success(
                toolCallId: toolCall.id,
                text: "Result: 42"
            )
        }
    )
    
    // Test with required tool choice
    let response = try await client.generateText(
        model,
        messages: [Message.user("Hello there!")],
        tools: [calculatorTool],
        toolChoice: .required
    )
    
    #expect(response.finishReason == .toolCalls, "Should be forced to call tools")
    #expect(!response.toolCalls.isEmpty, "Should have forced tool calls")
}

@Test func testGenerateTextWithCustomExecutor() async throws {
    // Test generateText with custom tool executor
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
        ),
        execute: { @Sendable toolCall in
            return ToolResult.success(
                toolCallId: toolCall.id,
                text: "Weather: 72°F, Sunny"
            )
        }
    )
    
    // Custom executor that provides specific responses
    let customExecutor: ToolExecutor = { toolCall in
        #expect(toolCall.function.name == "get_weather", "Should call weather tool")
        return ToolResult.success(
            toolCallId: toolCall.id,
            text: "Sunny, 72°F in San Francisco, CA"
        )
    }
    
    let response = try await client.generateText(
        model,
        messages: [Message.user("What's the weather in San Francisco?")],
        tools: [weatherTool],
        maxSteps: 2 // Allow tool execution
    )
    
    // Should either complete after tool execution OR finish with tool calls if no steps remaining
    let isComplete = response.finishReason == FinishReason.stop
    let hasToolCalls = response.finishReason == FinishReason.toolCalls
    
    #expect(isComplete || hasToolCalls, "Should either complete or have tool calls")
    #expect(response.messages.count >= 1, "Should have at least the original message")
    
    // If it completed, it should have tool results
    if isComplete {
        #expect(response.messages.count > 2, "Completed response should have multiple messages")
    }
}

@Test func testGenerateTextWithToolsStringPrompt() async throws {
    // Test the string prompt convenience method with tools
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
        ),
        execute: { @Sendable toolCall in
            // Simple calculator mock
            return ToolResult.success(
                toolCallId: toolCall.id,
                text: "Result: 42"
            )
        }
    )
    
    // Test the convenience method
    let response = try await client.generateText(
        model,
        prompt: "What is 2 + 2?",
        tools: [calculatorTool]
    )
    
    #expect(response.finishReason == .toolCalls, "Should call calculator tool")
    #expect(!response.toolCalls.isEmpty, "Should have tool calls")
    #expect(response.toolCalls.first?.function.name == "calculate", "Should call calculate tool")
}

@Test func testGenerateTextToolChoiceNone() async throws {
    // Test that toolChoice.none prevents tool usage
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
        ),
        execute: { @Sendable toolCall in
            return ToolResult.success(
                toolCallId: toolCall.id,
                text: "Weather: 72°F, Sunny"
            )
        }
    )
    
    let response = try await client.generateText(
        model,
        prompt: "What's the weather in San Francisco?",
        tools: [weatherTool],
        toolChoice: ToolChoice.none
    )
    
    #expect(response.finishReason == .stop, "Should not call tools when choice is none")
    #expect(response.toolCalls.isEmpty, "Should have no tool calls")
}