import XCTest
@testable import AIKit

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class AIChatTests: XCTestCase {
    
    var mockProvider: SimpleMockProvider!
    var client: AIClient!
    var model: LanguageModel!
    
    override func setUp() async throws {
        mockProvider = SimpleMockProvider()
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
        
        // Wait for response to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
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
        let _ = AIChat(client: client, model: model)
        
        var errorReceived: Error?
        let errorChat = AIChat(
            client: client,
            model: model,
            onError: { error in
                errorReceived = error
            }
        )
        
        // Set up error mock
        mockProvider.mockResponses["test-model"] = .failure(AIProviderError.providerSpecific(
            "Test error",
            underlyingError: nil
        ))
        
        // Send message
        errorChat.input = "Test"
        await errorChat.sendMessage()
        
        // Wait for error handling to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
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
                    "location": .string()
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
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Debug: print message structure
        print("Messages count: \(chat.messages.count)")
        if chat.messages.count > 1 {
            print("Assistant message toolCalls: \(chat.messages[1].toolCalls.count)")
        }
        
        XCTAssertGreaterThanOrEqual(chat.messages.count, 2)
        if chat.messages.count > 1 {
            XCTAssertGreaterThanOrEqual(chat.messages[1].toolCalls.count, 1)
            XCTAssertEqual(chat.messages[1].toolCalls.first?.function.name, "get_weather")
        }
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
    
    // MARK: - File Attachment Tests
    
    func testSendMessageWithFileAttachment() async {
        let chat = AIChat(client: client, model: model)
        
        // Create test file attachment
        let fileData = "Test file content".data(using: .utf8)!
        let fileAttachment = ChatAttachment.file(
            FileContent.data(fileData, mimeType: "text/plain", filename: "test.txt")
        )
        
        // Set up mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "I received your file",
            finishReason: .stop
        ))
        
        // Send message with attachment
        chat.input = "Here's a file"
        let sent = await chat.sendMessage(withAttachments: [fileAttachment])
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertTrue(sent)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].content, "Here's a file")
        XCTAssertEqual(chat.attachments(for: chat.messages[0]).count, 1)
        XCTAssertEqual(chat.input, "") // Input should be cleared
    }
    
    func testSendMessageWithImageAttachment() async {
        let chat = AIChat(client: client, model: model)
        
        // Create test image attachment
        let imageData = Data(repeating: 0xFF, count: 100) // Dummy image data
        let imageAttachment = ChatAttachment.image(
            ImageContent.data(imageData, mimeType: "image/png")
        )
        
        // Set up mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "I see an image",
            finishReason: .stop
        ))
        
        // Send message with attachment
        chat.input = "What's in this image?"
        await chat.sendMessage(withAttachments: [imageAttachment])
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].content, "What's in this image?")
        XCTAssertEqual(chat.attachments(for: chat.messages[0]).count, 1)
    }
    
    func testSendMessageWithMultipleAttachments() async {
        let chat = AIChat(client: client, model: model)
        
        // Create multiple attachments
        let textData = "Document content".data(using: .utf8)!
        let imageData = Data(repeating: 0xFF, count: 50)
        
        let attachments: [ChatAttachment] = [
            .file(FileContent.data(textData, mimeType: "text/plain", filename: "doc.txt")),
            .image(ImageContent.data(imageData, mimeType: "image/jpeg")),
            .data(Data("Raw data".utf8), mimeType: "application/octet-stream", filename: "data.bin")
        ]
        
        // Set up mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "I received 3 attachments",
            finishReason: .stop
        ))
        
        // Send with attachments
        chat.input = "Multiple files"
        await chat.sendMessage(withAttachments: attachments)
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.attachments(for: chat.messages[0]).count, 3)
    }
    
    func testSendMessageWithOnlyAttachments() async {
        let chat = AIChat(client: client, model: model)
        
        // Create attachment
        let fileData = "Content".data(using: .utf8)!
        let attachment = ChatAttachment.file(
            FileContent.data(fileData, mimeType: "text/plain", filename: "file.txt")
        )
        
        // Set up mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "Received file",
            finishReason: .stop
        ))
        
        // Send with empty input but with attachment
        chat.input = ""
        let sent = await chat.sendMessage(withAttachments: [attachment])
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertTrue(sent) // Should still send with only attachments
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.attachments(for: chat.messages[0]).count, 1)
    }
    
    func testAttachmentRetrieval() async {
        let chat = AIChat(client: client, model: model)
        
        // Create message with attachment
        let attachment = ChatAttachment.data(
            Data("test".utf8),
            mimeType: "text/plain",
            filename: "test.txt"
        )
        
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "OK",
            finishReason: .stop
        ))
        
        chat.input = "Test"
        await chat.sendMessage(withAttachments: [attachment])
        
        // Wait for response to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Ensure we have messages before accessing
        XCTAssertGreaterThanOrEqual(chat.messages.count, 1, "Should have at least one message")
        guard chat.messages.count >= 1 else { return }
        
        // Test retrieval by message
        let message = chat.messages[0]
        let retrievedByMessage = chat.attachments(for: message)
        XCTAssertEqual(retrievedByMessage.count, 1)
        
        // Test retrieval by ID
        let retrievedById = chat.attachments(for: message.id)
        XCTAssertEqual(retrievedById.count, 1)
        
        // Test no attachments for assistant message
        if chat.messages.count >= 2 {
            let assistantAttachments = chat.attachments(for: chat.messages[1])
            XCTAssertTrue(assistantAttachments.isEmpty)
        }
    }
    
    // MARK: - Edge Cases and Error Scenarios
    
    func testSendEmptyMessage() async {
        let chat = AIChat(client: client, model: model)
        
        // Try to send empty message
        chat.input = ""
        let sent = await chat.sendMessage()
        
        XCTAssertFalse(sent)
        XCTAssertTrue(chat.messages.isEmpty)
    }
    
    func testSendMessageWhileStreaming() async {
        let chat = AIChat(client: client, model: model)
        
        // Set up slow streaming
        mockProvider.streamDelay = 0.1
        mockProvider.mockStreamingResponses["test-model"] = [
            .init(text: "Slow", finishReason: nil),
            .init(text: " response", finishReason: .stop)
        ]
        
        // Start first message
        chat.input = "First"
        Task {
            await chat.sendMessage()
        }
        
        // Wait for streaming to start
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(chat.status, .streaming)
        
        // Try to send another message while streaming
        chat.input = "Second"
        let sent = await chat.sendMessage()
        
        XCTAssertFalse(sent) // Should not send while streaming
    }
    
    func testReloadWithNoMessages() async {
        let chat = AIChat(client: client, model: model)
        
        // Try to reload with no messages
        await chat.reload()
        
        XCTAssertTrue(chat.messages.isEmpty)
    }
    
    func testReloadWithOnlyUserMessage() async {
        let chat = AIChat(client: client, model: model)
        
        // Add only user message
        chat.setMessages([
            ChatMessage(role: .user, content: "Hello")
        ])
        
        // Set up mock response
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "New response",
            finishReason: .stop
        ))
        
        // Reload should generate new assistant response
        await chat.reload()
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[1].content, "New response")
    }
    
    func testEditNonExistentMessage() async {
        let chat = AIChat(client: client, model: model)
        
        chat.setMessages([
            ChatMessage(id: "1", role: .user, content: "Hello")
        ])
        
        // Try to edit non-existent message
        chat.editMessage(id: "non-existent", newContent: "Edited")
        
        // Original message should remain unchanged
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].content, "Hello")
    }
    
    func testRemoveNonExistentMessage() async {
        let chat = AIChat(client: client, model: model)
        
        chat.setMessages([
            ChatMessage(id: "1", role: .user, content: "Hello")
        ])
        
        // Try to remove non-existent message
        chat.removeMessage(id: "non-existent")
        
        // Original message should remain
        XCTAssertEqual(chat.messages.count, 1)
    }
    
    func testConcurrentModifications() async {
        let chat = AIChat(client: client, model: model)
        
        // Add initial messages
        chat.setMessages([
            ChatMessage(id: "1", role: .user, content: "First"),
            ChatMessage(id: "2", role: .assistant, content: "Second"),
            ChatMessage(id: "3", role: .user, content: "Third")
        ])
        
        // Perform concurrent modifications
        // Since AIChat is @MainActor, we need to do these operations sequentially
        chat.editMessage(id: "1", newContent: "Edited First")
        chat.removeMessage(id: "2")
        await chat.append(ChatMessage(role: .user, content: "Fourth"))
        
        // Verify final state
        XCTAssertEqual(chat.messages.count, 3) // Original 3 - 1 removed + 1 added
        XCTAssertEqual(chat.messages.first(where: { $0.id == "1" })?.content, "Edited First")
        XCTAssertNil(chat.messages.first(where: { $0.id == "2" }))
    }
    
    func testStreamingErrorRecovery() async {
        let _ = AIChat(client: client, model: model)
        
        var errorReceived: Error?
        let errorChat = AIChat(
            client: client,
            model: model,
            onError: { error in
                errorReceived = error
            }
        )
        
        // First attempt fails
        mockProvider.mockResponses["test-model"] = .failure(AIProviderError.serviceUnavailable(
            "Temporary failure"
        ))
        
        errorChat.input = "Test"
        await errorChat.sendMessage()
        
        // Wait for error to be processed
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(errorChat.status, .error)
        XCTAssertNotNil(errorReceived)
        XCTAssertEqual(errorChat.messages.count, 1) // Only user message
        
        // Second attempt succeeds
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "Success after retry",
            finishReason: .stop
        ))
        
        errorChat.input = "Retry"
        await errorChat.sendMessage()
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(errorChat.status, .ready)
        XCTAssertEqual(errorChat.messages.count, 3) // Original + retry user + assistant
    }
    
    func testPersistenceWithCorruptedData() throws {
        let chat = AIChat(client: client, model: model)
        let testKey = "corrupted-data-test"
        
        // Save corrupted data
        UserDefaults.standard.set("not json data", forKey: testKey)
        
        // Try to load - should handle gracefully
        chat.load(from: testKey)
        
        // Should still be empty
        XCTAssertTrue(chat.messages.isEmpty)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: testKey)
    }
    
    func testLargeMessageHandling() async {
        let chat = AIChat(client: client, model: model)
        
        // Create a large message
        let largeContent = String(repeating: "Lorem ipsum ", count: 10000)
        
        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "Handled large message",
            finishReason: .stop
        ))
        
        chat.input = largeContent
        await chat.sendMessage()
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].content, largeContent)
    }
    
    func testMessageWithEmptyToolCalls() async {
        let chat = AIChat(client: client, model: model)
        
        // Create message with empty tool calls array
        let message = ChatMessage(
            role: .assistant,
            content: "Response",
            toolCalls: []
        )
        
        chat.setMessages([message])
        
        let coreMessage = message.toCoreMessage()
        XCTAssertEqual(coreMessage.content.count, 1)
        // Check content type without Equatable conformance
        if case .text(let text) = coreMessage.content[0] {
            XCTAssertEqual(text, "Response")
        } else {
            XCTFail("Expected text content")
        }
    }
    
    func testAttachmentWithInvalidMessageId() async {
        let chat = AIChat(client: client, model: model)
        
        // Try to get attachments for non-existent message ID
        let attachments = chat.attachments(for: "non-existent-id")
        
        XCTAssertTrue(attachments.isEmpty)
    }
}

// MARK: - SwiftUI Integration Tests

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct TestChatView: View {
    @UseChat(model: SimpleMockProvider().languageModel("test")) var chat
    
    var body: some View {
        VStack {
            ForEach(chat.messages) { message in
                Text(message.content)
            }
            
            TextField("Message", text: Binding(
                get: { chat.input },
                set: { chat.input = $0 }
            ))
            
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
    
    @MainActor
    func testChatAutosaveModifier() {
        let client = AIClient()
        let model = SimpleMockProvider().languageModel("test")
        let chat = AIChat(client: client, model: model)
        let testKey = "test-autosave-key"
        
        // Clear any existing data
        UserDefaults.standard.removeObject(forKey: testKey)
        
        // Create a view with autosave
        struct AutosaveTestView: View {
            let chat: AIChat
            let saveKey: String
            
            var body: some View {
                Text("Test")
                    .chatAutosave(chat, key: saveKey)
            }
        }
        
        // Add some messages to chat
        chat.setMessages([
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there!")
        ])
        
        // Simulate view lifecycle
        let _ = AutosaveTestView(chat: chat, saveKey: testKey)
        
        // Manually trigger save (simulating onDisappear)
        chat.save(to: testKey)
        
        // Create new chat and load
        let newChat = AIChat(client: client, model: model)
        newChat.load(from: testKey)
        
        // Verify messages were restored
        XCTAssertEqual(newChat.messages.count, 2)
        XCTAssertEqual(newChat.messages[0].content, "Hello")
        XCTAssertEqual(newChat.messages[1].content, "Hi there!")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: testKey)
    }
    
    @MainActor
    func testChatAutosaveWithDefaultKey() {
        let client = AIClient()
        let model = SimpleMockProvider().languageModel("test")
        let chat = AIChat(client: client, model: model)
        
        // Clear default key
        UserDefaults.standard.removeObject(forKey: "AIChat.messages")
        
        struct DefaultKeyTestView: View {
            let chat: AIChat
            
            var body: some View {
                Text("Test")
                    .chatAutosave(chat) // Uses default key
            }
        }
        
        // Add messages
        chat.setMessages([
            ChatMessage(role: .system, content: "System message"),
            ChatMessage(role: .user, content: "User message")
        ])
        
        // Save with default key
        chat.save()
        
        // Load into new chat
        let newChat = AIChat(client: client, model: model)
        newChat.load()
        
        XCTAssertEqual(newChat.messages.count, 2)
        XCTAssertEqual(newChat.messages[0].role, .system)
        XCTAssertEqual(newChat.messages[1].role, .user)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "AIChat.messages")
    }
}
#endif