import Testing
import Foundation
@testable import AIKit

// MARK: - Response Messages Tests

@Suite("TextResponse responseMessages Property Tests")
struct ResponseMessagesTests {
    
    // MARK: - Simple Response Tests
    
    @Test("Response messages for simple text response")
    func testSimpleTextResponseMessages() async throws {
        // Create a simple text response without tool calls
        let messages: [Message] = [
            .user("What is 2+2?"),
            .assistant("4")
        ]
        
        let response = TextResponse(
            text: "The answer is 4.",
            finishReason: .stop,
            usage: Usage(promptTokens: 10, completionTokens: 5, totalTokens: 15),
            messages: messages
        )
        
        // Test responseMessages property
        let responseMessages = response.responseMessages
        
        #expect(responseMessages.count == 1)
        #expect(responseMessages[0].role == .assistant)
        #expect(responseMessages[0].content.count == 1)
        #expect(responseMessages[0].content[0].textValue == "The answer is 4.")
        #expect(responseMessages[0].toolCalls == nil)
    }
    
    @Test("Response messages for empty text response")
    func testEmptyTextResponseMessages() async throws {
        // Create response with empty text
        let response = TextResponse(
            text: "",
            finishReason: .stop,
            usage: Usage(promptTokens: 10, completionTokens: 0, totalTokens: 10),
            messages: [.user("Test")]
        )
        
        let responseMessages = response.responseMessages
        
        // Empty text should not create a message
        #expect(responseMessages.isEmpty)
    }
    
    // MARK: - Tool Call Response Tests
    
    @Test("Response messages with tool calls")
    func testResponseMessagesWithToolCalls() async throws {
        // Create response with tool calls
        let toolCall = ToolCall(
            id: "call_123",
            function: ToolCallFunction(
                name: "get_weather",
                arguments: "{\"location\":\"San Francisco\"}"
            )
        )
        
        let step = GenerationStep(
            stepType: .toolCall,
            toolCalls: [toolCall]
        )
        
        let response = TextResponse(
            text: "",
            finishReason: .toolCalls,
            usage: Usage(promptTokens: 20, completionTokens: 10, totalTokens: 30),
            messages: [.user("What's the weather?")],
            steps: [step]
        )
        
        let responseMessages = response.responseMessages
        
        #expect(responseMessages.count == 1)
        #expect(responseMessages[0].role == .assistant)
        #expect(responseMessages[0].toolCalls?.count == 1)
        #expect(responseMessages[0].toolCalls?[0].id == "call_123")
        #expect(responseMessages[0].toolCalls?[0].function.name == "get_weather")
    }
    
    @Test("Response messages with tool calls and text")
    func testResponseMessagesWithToolCallsAndText() async throws {
        // Create response with both text and tool calls
        let toolCall = ToolCall(
            id: "call_456",
            function: ToolCallFunction(
                name: "search_notes",
                arguments: "{\"query\":\"spins\"}"
            )
        )
        
        let step = GenerationStep(
            stepType: .toolCall,
            toolCalls: [toolCall]
        )
        
        let response = TextResponse(
            text: "I'll search for notes about spins.",
            finishReason: .toolCalls,
            usage: Usage(promptTokens: 30, completionTokens: 15, totalTokens: 45),
            messages: [.user("Find my notes about spins")],
            steps: [step]
        )
        
        let responseMessages = response.responseMessages
        
        #expect(responseMessages.count == 1)
        #expect(responseMessages[0].role == .assistant)
        #expect(responseMessages[0].content.count == 1)
        #expect(responseMessages[0].content[0].textValue == "I'll search for notes about spins.")
        #expect(responseMessages[0].toolCalls?.count == 1)
        #expect(responseMessages[0].toolCalls?[0].function.name == "search_notes")
    }
    
    // MARK: - Multi-Step Response Tests
    
    @Test("Response messages with multi-step tool execution")
    func testMultiStepResponseMessages() async throws {
        // Create multi-step response with tool calls and results
        let toolCall = ToolCall(
            id: "call_789",
            function: ToolCallFunction(
                name: "get_weather",
                arguments: "{\"location\":\"NYC\"}"
            )
        )
        
        let toolResult = ToolResult(
            toolCallId: "call_789",
            result: .text("Temperature: 72°F, Sunny")
        )
        
        let steps = [
            GenerationStep(
                stepType: .toolCall,
                toolCalls: [toolCall]
            ),
            GenerationStep(
                stepType: .toolResult,
                toolResults: [toolResult]
            )
        ]
        
        let response = TextResponse(
            text: "The weather in NYC is 72°F and sunny.",
            finishReason: .stop,
            usage: Usage(promptTokens: 50, completionTokens: 25, totalTokens: 75),
            messages: [.user("What's the weather in NYC?")],
            steps: steps
        )
        
        let responseMessages = response.responseMessages
        
        // Should have assistant message with tool call + tool result message
        #expect(responseMessages.count == 2)
        
        // First message: assistant with tool call
        #expect(responseMessages[0].role == .assistant)
        #expect(responseMessages[0].toolCalls?.count == 1)
        #expect(responseMessages[0].toolCalls?[0].id == "call_789")
        
        // Second message: tool result
        #expect(responseMessages[1].role == .tool)
        if let firstContent = responseMessages[1].content.first,
           case .toolResult(let result) = firstContent {
            #expect(result.toolCallId == "call_789")
            if case .text(let text) = result.result {
                #expect(text == "Temperature: 72°F, Sunny")
            } else {
                Issue.record("Expected text result")
            }
        } else {
            Issue.record("Expected tool result message")
        }
    }
    
    @Test("Response messages with multiple tool calls")
    func testMultipleToolCallsResponseMessages() async throws {
        // Create response with multiple tool calls
        let toolCalls = [
            ToolCall(
                id: "call_1",
                function: ToolCallFunction(
                    name: "tool_1",
                    arguments: "{}"
                )
            ),
            ToolCall(
                id: "call_2",
                function: ToolCallFunction(
                    name: "tool_2",
                    arguments: "{}"
                )
            )
        ]
        
        let toolResults = [
            ToolResult(toolCallId: "call_1", result: .text("Result 1")),
            ToolResult(toolCallId: "call_2", result: .text("Result 2"))
        ]
        
        let steps = [
            GenerationStep(
                stepType: .toolCall,
                messages: [.assistant("Calling tools...")],
                toolCalls: toolCalls
            ),
            GenerationStep(
                stepType: .toolResult,
                toolResults: toolResults
            )
        ]
        
        let response = TextResponse(
            text: "Calling tools...",
            finishReason: .stop,
            usage: Usage(promptTokens: 60, completionTokens: 30, totalTokens: 90),
            messages: [.user("Do multiple things")],
            steps: steps
        )
        
        let responseMessages = response.responseMessages
        
        // Should have: assistant message with 2 tool calls + 2 tool result messages
        #expect(responseMessages.count == 3)
        
        // Assistant message with tool calls
        #expect(responseMessages[0].role == .assistant)
        #expect(responseMessages[0].toolCalls?.count == 2)
        
        // Tool result messages
        #expect(responseMessages[1].role == .tool)
        #expect(responseMessages[2].role == .tool)
    }
    
    // MARK: - Edge Cases
    
    @Test("Response messages handles nil steps")
    func testResponseMessagesWithNilSteps() async throws {
        let response = TextResponse(
            text: "Simple response",
            finishReason: .stop,
            usage: Usage(promptTokens: 10, completionTokens: 5, totalTokens: 15),
            messages: [.user("Test")],
            steps: nil
        )
        
        let responseMessages = response.responseMessages
        
        #expect(responseMessages.count == 1)
        #expect(responseMessages[0].content[0].textValue == "Simple response")
    }
    
    @Test("Response messages handles empty steps")
    func testResponseMessagesWithEmptySteps() async throws {
        let response = TextResponse(
            text: "Response with empty steps",
            finishReason: .stop,
            usage: Usage(promptTokens: 10, completionTokens: 5, totalTokens: 15),
            messages: [.user("Test")],
            steps: []
        )
        
        let responseMessages = response.responseMessages
        
        #expect(responseMessages.count == 1)
        #expect(responseMessages[0].content[0].textValue == "Response with empty steps")
    }
    
    // MARK: - Integration Test
    
    @Test("Response messages integration with conversation history")
    func testResponseMessagesConversationIntegration() async throws {
        // Simulate a conversation with tool calls
        var conversation: [Message] = [
            .system("You are a helpful assistant."),
            .user("What's the weather in Paris?")
        ]
        
        // Create response with tool call
        let toolCall = ToolCall(
            id: "call_paris",
            function: ToolCallFunction(
                name: "get_weather",
                arguments: "{\"location\":\"Paris\",\"unit\":\"celsius\"}"
            )
        )
        
        let toolResult = ToolResult(
            toolCallId: "call_paris",
            result: .text("18°C, Cloudy")
        )
        
        let steps = [
            GenerationStep(
                stepType: .toolCall,
                messages: [.assistant("Let me check the weather in Paris for you.")],
                toolCalls: [toolCall]
            ),
            GenerationStep(
                stepType: .toolResult,
                messages: [.tool(result: toolResult)],
                toolResults: [toolResult]
            )
        ]
        
        let response = TextResponse(
            text: "Let me check the weather in Paris for you.",
            finishReason: .stop,
            usage: Usage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            messages: conversation,
            steps: steps
        )
        
        // Use responseMessages to update conversation
        conversation.append(contentsOf: response.responseMessages)
        
        // Verify conversation history is correct
        #expect(conversation.count == 4) // system + user + assistant + tool
        #expect(conversation[2].role == .assistant)
        #expect(conversation[2].toolCalls?.count == 1)
        #expect(conversation[3].role == .tool)
        
        // Verify this matches manual formatting
        let manualAssistantMessage = Message(
            role: .assistant,
            content: [.text("Let me check the weather in Paris for you.")],
            toolCalls: [toolCall]
        )
        
        #expect(conversation[2].role == manualAssistantMessage.role)
        #expect(conversation[2].content.count == manualAssistantMessage.content.count)
        #expect(conversation[2].toolCalls?.count == manualAssistantMessage.toolCalls?.count)
    }
}