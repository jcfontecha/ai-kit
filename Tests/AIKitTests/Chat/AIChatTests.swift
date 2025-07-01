import XCTest
@testable import AIKit

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class AIChatTests: XCTestCase {
    
    var mockProvider: MockProvider!
    var client: AIClient!
    var model: LanguageModel!
    
    override func setUp() async throws {
        mockProvider = MockProvider()
        client = AIClient()
        model = mockProvider.languageModel("test-model")
    }
    
    // MARK: - Basic Functionality Tests
    
    func testInitialization() async {
        let chat = AIChat(client: client, model: model)
        
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.input, "")
        XCTAssertEqual(chat.status, .ready)
        XCTAssertNil(chat.error)
    }
    
    func testSendMessage() async {
        let chat = AIChat(client: client, model: model)
        
        // Set up mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "Hello! How can I help you?",
            finishReason: .stop,
            usage: .init(promptTokens: 10, completionTokens: 8, totalTokens: 18)
        ))
        
        // Send message
        chat.input = "Hello"
        let sent = await chat.sendMessage()
        
        XCTAssertTrue(sent)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].content, "Hello")
        XCTAssertEqual(chat.messages[0].role, .user)
        XCTAssertEqual(chat.messages[1].role, .assistant)
        XCTAssertEqual(chat.input, "") // Input should be cleared
    }
    
    func testStreamingResponse() async {
        let chat = AIChat(client: client, model: model)
        
        // Set up streaming mock
        let chunks: [ProviderChunk] = [
            .init(text: "Hello", finishReason: nil),
            .init(text: " there", finishReason: nil),
            .init(text: "!", finishReason: .stop)
        ]
        mockProvider.mockStreamingResponses["test-model"] = chunks
        
        // Send message
        chat.input = "Hi"
        await chat.sendMessage()
        
        // Wait for streaming to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[1].content, "Hello there!")
        XCTAssertEqual(chat.status, .ready)
    }
    
    func testStopStreaming() async {
        let chat = AIChat(client: client, model: model)
        
        // Set up slow streaming mock
        let chunks: [ProviderChunk] = Array(repeating: .init(text: ".", finishReason: nil), count: 100)
        mockProvider.mockStreamingResponses["test-model"] = chunks
        mockProvider.streamDelay = 0.01 // 10ms per chunk
        
        // Send message
        chat.input = "Test"
        Task {
            await chat.sendMessage()
        }
        
        // Wait for streaming to start
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        XCTAssertEqual(chat.status, .streaming)
        
        // Stop streaming
        chat.stop()
        XCTAssertEqual(chat.status, .ready)
    }
    
    func testErrorHandling() async {
        let chat = AIChat(client: client, model: model)
        
        var errorReceived: Error?
        let errorChat = AIChat(
            client: client,
            model: model,
            onError: { error in
                errorReceived = error
            }
        )
        
        // Set up error mock
        mockProvider.mockResponses["test-model"] = .failure(AIError.providerError(
            provider: "mock",
            message: "Test error"
        ))
        
        // Send message
        errorChat.input = "Test"
        await errorChat.sendMessage()
        
        XCTAssertEqual(errorChat.status, .error)
        XCTAssertNotNil(errorChat.error)
        XCTAssertNotNil(errorReceived)
        XCTAssertEqual(errorChat.messages.count, 1) // Only user message
    }
    
    // MARK: - Tool Execution Tests
    
    func testToolExecution() async {
        // Create a tool
        let weatherTool = Tool(
            type: .function,
            function: ToolFunction(
                name: "get_weather",
                description: "Get weather for a location",
                parameters: .object(properties: [
                    "location": .string(description: "City name")
                ])
            ),
            execute: { toolCall in
                ToolResult.success(
                    toolCallId: toolCall.id,
                    text: "Sunny, 72°F in San Francisco"
                )
            }
        )
        
        let chat = AIChat(client: client, model: model, tools: [weatherTool])
        
        // Set up mock with tool call
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "",
            toolCalls: [
                ToolCall(
                    id: "call_1",
                    name: "get_weather",
                    arguments: ["location": "San Francisco"]
                )
            ],
            finishReason: .toolCalls
        ))
        
        // Send message
        chat.input = "What's the weather in San Francisco?"
        await chat.sendMessage()
        
        // Wait for tool execution
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[1].toolCalls.count, 1)
        XCTAssertEqual(chat.messages[1].toolCalls[0].function.name, "get_weather")
    }
    
    // MARK: - Message Management Tests
    
    func testSetMessages() async {
        let chat = AIChat(client: client, model: model)
        
        let messages = [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there!")
        ]
        
        chat.setMessages(messages)
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].content, "Hello")
        XCTAssertEqual(chat.messages[1].content, "Hi there!")
    }
    
    func testClear() async {
        let chat = AIChat(client: client, model: model)
        
        // Add some messages
        chat.setMessages([
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi!")
        ])
        chat.input = "New message"
        
        // Clear
        chat.clear()
        
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.input, "")
        XCTAssertEqual(chat.status, .ready)
        XCTAssertNil(chat.error)
    }
    
    func testReload() async {
        let chat = AIChat(client: client, model: model)
        
        // Set up initial messages
        chat.setMessages([
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "First response")
        ])
        
        // Set up new mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "New response",
            finishReason: .stop
        ))
        
        // Reload
        await chat.reload()
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[1].content, "New response")
    }
    
    // MARK: - Advanced Features Tests
    
    func testMessageEditing() async {
        let chat = AIChat(client: client, model: model)
        
        let message = ChatMessage(id: "test-id", role: .user, content: "Original")
        chat.setMessages([message])
        
        chat.editMessage(id: "test-id", newContent: "Edited")
        
        XCTAssertEqual(chat.messages[0].content, "Edited")
    }
    
    func testMessageRemoval() async {
        let chat = AIChat(client: client, model: model)
        
        chat.setMessages([
            ChatMessage(id: "1", role: .user, content: "First"),
            ChatMessage(id: "2", role: .assistant, content: "Second"),
            ChatMessage(id: "3", role: .user, content: "Third")
        ])
        
        chat.removeMessage(id: "2")
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].id, "1")
        XCTAssertEqual(chat.messages[1].id, "3")
    }
    
    func testLastMessageGetters() async {
        let chat = AIChat(client: client, model: model)
        
        chat.setMessages([
            ChatMessage(role: .user, content: "User 1"),
            ChatMessage(role: .assistant, content: "Assistant 1"),
            ChatMessage(role: .user, content: "User 2"),
            ChatMessage(role: .assistant, content: "Assistant 2")
        ])
        
        XCTAssertEqual(chat.lastUserMessage?.content, "User 2")
        XCTAssertEqual(chat.lastAssistantMessage?.content, "Assistant 2")
    }
    
    func testMarkdownExport() async {
        let chat = AIChat(client: client, model: model)
        
        chat.setMessages([
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(
                role: .assistant,
                content: "Hi there!",
                toolCalls: [
                    ToolCall(name: "test_tool", arguments: [:])
                ]
            )
        ])
        
        let markdown = chat.exportAsMarkdown()
        
        XCTAssertTrue(markdown.contains("# Chat Export"))
        XCTAssertTrue(markdown.contains("## User"))
        XCTAssertTrue(markdown.contains("Hello"))
        XCTAssertTrue(markdown.contains("## Assistant"))
        XCTAssertTrue(markdown.contains("Hi there!"))
        XCTAssertTrue(markdown.contains("**Tool Calls:**"))
        XCTAssertTrue(markdown.contains("test_tool"))
    }
    
    // MARK: - Persistence Tests
    
    func testSaveAndLoad() async {
        let saveChat = AIChat(client: client, model: model)
        let loadChat = AIChat(client: client, model: model)
        
        // Add messages to save chat
        saveChat.setMessages([
            ChatMessage(role: .user, content: "Test message"),
            ChatMessage(role: .assistant, content: "Test response")
        ])
        
        // Save
        saveChat.save(to: "test-chat")
        
        // Load
        loadChat.load(from: "test-chat")
        
        XCTAssertEqual(loadChat.messages.count, 2)
        XCTAssertEqual(loadChat.messages[0].content, "Test message")
        XCTAssertEqual(loadChat.messages[1].content, "Test response")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "test-chat")
    }
    
    func testFileBasedPersistence() async throws {
        let chat = AIChat(client: client, model: model)
        
        // Add messages
        chat.setMessages([
            ChatMessage(role: .user, content: "File test")
        ])
        
        // Save to file
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-chat.json")
        try chat.save(to: url)
        
        // Load from file
        let newChat = AIChat(client: client, model: model)
        try newChat.load(from: url)
        
        XCTAssertEqual(newChat.messages.count, 1)
        XCTAssertEqual(newChat.messages[0].content, "File test")
        
        // Clean up
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Callback Tests
    
    func testOnFinishCallback() async {
        var finishMessage: ChatMessage?
        var finishDetails: FinishDetails?
        
        let chat = AIChat(
            client: client,
            model: model,
            onFinish: { message, details in
                finishMessage = message
                finishDetails = details
            }
        )
        
        // Set up mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "Finished response",
            finishReason: .stop,
            usage: .init(promptTokens: 5, completionTokens: 3, totalTokens: 8)
        ))
        
        // Send message
        chat.input = "Test"
        await chat.sendMessage()
        
        // Wait for completion
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertNotNil(finishMessage)
        XCTAssertEqual(finishMessage?.content, "Finished response")
        XCTAssertNotNil(finishDetails)
        XCTAssertEqual(finishDetails?.finishReason, .stop)
        XCTAssertEqual(finishDetails?.usage?.totalTokens, 8)
    }
}

// MARK: - SwiftUI Integration Tests

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct TestChatView: View {
    @UseChat(model: MockProvider().languageModel("test")) var chat
    
    var body: some View {
        VStack {
            ForEach(chat.messages) { message in
                Text(message.content)
            }
            
            TextField("Message", text: $chat.input)
            
            Button("Send") {
                Task {
                    await chat.sendMessage()
                }
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
final class SwiftUIIntegrationTests: XCTestCase {
    
    @MainActor
    func testUseChatPropertyWrapper() {
        let view = TestChatView()
        
        // Access the chat through property wrapper
        XCTAssertNotNil(view.chat)
        XCTAssertTrue(view.chat.messages.isEmpty)
        XCTAssertEqual(view.chat.status, .ready)
    }
}
#endif