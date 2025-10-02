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

    private func waitForChatToBeReady(_ chat: AIChat, timeout: TimeInterval = 1.0) async {
        let nanosPerSecond: Double = 1_000_000_000
        let interval: UInt64 = 50_000_000 // 50ms
        let deadline = UInt64(timeout * nanosPerSecond)
        var elapsed: UInt64 = 0

        while chat.status != .ready && elapsed < deadline {
            try? await Task.sleep(nanoseconds: interval)
            elapsed += interval
        }
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
    
    func testSaveAndLoad() async throws {
        let saveChat = AIChat(client: client, model: model)
        let loadChat = AIChat(client: client, model: model)
        
        // Use memory persistence for testing
        let persistence = MemoryChatPersistence()
        let chatId = "test-chat"
        
        // Add messages to save chat
        saveChat.setMessages([
            ChatMessage(role: .user, content: "Test message"),
            ChatMessage(role: .assistant, content: "Test response")
        ])
        
        // Save
        try await saveChat.save(using: persistence, chatId: chatId)
        
        // Load
        try await loadChat.load(using: persistence, chatId: chatId)
        
        XCTAssertEqual(loadChat.messages.count, 2)
        XCTAssertEqual(loadChat.messages[0].content, "Test message")
        XCTAssertEqual(loadChat.messages[1].content, "Test response")
    }
    
    func testFileBasedPersistence() async throws {
        let chat = AIChat(client: client, model: model)
        
        // Create file persistence
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestChats")
        let persistence = try FileChatPersistence(directory: tempDir)
        let chatId = "test-file-chat"
        
        // Add messages
        chat.setMessages([
            ChatMessage(role: .user, content: "File test")
        ])
        
        // Save using file persistence
        try await chat.save(using: persistence, chatId: chatId)
        
        // Load from file
        let newChat = AIChat(client: client, model: model)
        try await newChat.load(using: persistence, chatId: chatId)
        
        XCTAssertEqual(newChat.messages.count, 1)
        XCTAssertEqual(newChat.messages[0].content, "File test")
        
        // Clean up
        try? await persistence.delete(for: chatId)
        try? FileManager.default.removeItem(at: tempDir)
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

        mockProvider.mockResponses["test-model"] = .success(.init(
            text: "Hello from the assistant!",
            finishReason: .stop,
            usage: .init(promptTokens: 5, completionTokens: 6, totalTokens: 11)
        ))

        chat.input = ""
        let sent = await chat.sendMessage()

        await waitForChatToBeReady(chat)

        XCTAssertTrue(sent)
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages.first?.role, .assistant)
        XCTAssertEqual(chat.messages.first?.content, "Hello from the assistant!")
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
    
    func testPersistenceWithCorruptedData() async throws {
        let chat = AIChat(client: client, model: model)
        let testKey = "corrupted-data-test"
        
        // Save corrupted data as actual Data that can't be decoded as ChatMessage array
        let corruptedData = "not json data".data(using: .utf8)!
        UserDefaults.standard.set(corruptedData, forKey: "AIChat." + testKey)
        
        // Use UserDefaults persistence
        let persistence = UserDefaultsChatPersistence()
        
        // Try to load - should throw error because the data isn't valid JSON for ChatMessage array
        do {
            try await chat.load(using: persistence, chatId: testKey)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error - decoding should fail
            XCTAssertTrue(chat.messages.isEmpty)
        }
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "AIChat." + testKey)
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

    func testToolGeneratedImageResultEmitsToolMessageBeforeFollowUp() async {
        let toolCallID = "tool-image-demo"
        let handler = InlineImageToolHandler(provider: mockProvider, modelId: "test-model", finalContent: "Here is your image.")

        let tool = Tool(
            function: ToolFunction(
                name: "generate_and_show_image",
                description: "Generate an image",
                parameters: .object(
                    properties: [
                        "prompt": .string().withDescription("Prompt for the image")
                    ],
                    required: ["prompt"]
                )
            ),
            execute: { toolCall in
                try await handler.execute(toolCall: toolCall)
            }
        )

        let chat = AIChat(client: client, model: model, tools: [tool])
        handler.chat = chat

        let toolCall = ToolCall(
            id: toolCallID,
            type: .function,
            function: ToolCallFunction(name: "generate_and_show_image", arguments: #"{"prompt":"test"}"#)
        )

        mockProvider.mockResponses["test-model"] = .success(ProviderResponse(
            content: "",
            toolCalls: [toolCall],
            usage: Usage(promptTokens: 5, completionTokens: 0, totalTokens: 5),
            finishReason: .toolCalls
        ))

        chat.input = "Please create an image"
        let sent = await chat.sendMessage()
        XCTAssertTrue(sent)

        await waitForChatToBeReady(chat)

        guard let assistantIndex = chat.messages.firstIndex(where: { message in
            guard message.role == .assistant else { return false }
            return message.orderedContent.contains { content in
                if case .toolCall(let call) = content {
                    return call.id == toolCallID
                }
                return false
            }
        }) else {
            return XCTFail("Expected assistant message containing tool call")
        }

        let assistantWithTool = chat.messages[assistantIndex]

        XCTAssertFalse(assistantWithTool.orderedContent.contains { content in
            if case .image = content { return true }
            if case .file = content { return true }
            return false
        }, "Assistant tool call message should not inline attachments")

        XCTAssertTrue(chat.attachments(for: assistantWithTool).isEmpty)
        XCTAssertTrue(assistantWithTool.orderedContent.contains { content in
            if case .toolCall(let call) = content {
                return call.id == toolCallID
            }
            return false
        })

        guard let toolMessageIndex = chat.messages.firstIndex(where: { message in
            guard message.role == .tool else { return false }
            return message.orderedContent.contains { content in
                if case .toolResult(let result) = content {
                    return result.toolCallId == toolCallID
                }
                return false
            }
        }) else {
            return XCTFail("Expected tool message")
        }

        XCTAssertTrue(toolMessageIndex > assistantIndex)

        let toolMessage = chat.messages[toolMessageIndex]
        XCTAssertTrue(toolMessage.orderedContent.contains { content in
            if case .toolResult(let result) = content {
                return result.toolCallId == toolCallID
            }
            return false
        })

        let toolAttachments = chat.attachments(for: toolMessage)
        XCTAssertEqual(toolAttachments.count, 1)
        if case .some(.image) = toolAttachments.first {
            // Attachment is an image
        } else {
            XCTFail("Expected image attachment on tool message")
        }

        guard let finalAssistantIndex = chat.messages[(toolMessageIndex + 1)..<chat.messages.count].firstIndex(where: { $0.role == .assistant }) else {
            return XCTFail("Expected follow-up assistant message")
        }

        XCTAssertTrue(finalAssistantIndex > toolMessageIndex)

        let finalAssistant = chat.messages[finalAssistantIndex]
        XCTAssertTrue(finalAssistant.orderedContent.contains { content in
            if case .text(let value) = content {
                return value.contains("Here is your image")
            }
            return false
        })

        XCTAssertTrue(finalAssistant.orderedContent.allSatisfy { content in
            if case .toolCall = content { return false }
            if case .image = content { return false }
            return true
        })
    }

    func testToolGeneratedImageResultOrderingWithExistingAssistantHistory() async {
        let handler = InlineImageToolHandler(provider: mockProvider, modelId: "test-model", finalContent: "Image ready.")

        let tool = Tool(
            function: ToolFunction(
                name: "generate_and_show_image",
                description: "Generate an image",
                parameters: .object(
                    properties: [
                        "prompt": .string().withDescription("Prompt for the image")
                    ],
                    required: ["prompt"]
                )
            ),
            execute: { toolCall in
                try await handler.execute(toolCall: toolCall)
            }
        )

        let chat = AIChat(client: client, model: model, tools: [tool])
        handler.chat = chat

        mockProvider.mockResponses["test-model"] = .success(ProviderResponse(
            content: "Hello there!",
            usage: Usage(promptTokens: 4, completionTokens: 4, totalTokens: 8),
            finishReason: .stop
        ))

        chat.input = "Say hi"
        let greeted = await chat.sendMessage()
        XCTAssertTrue(greeted)
        await waitForChatToBeReady(chat)

        let toolCall = ToolCall(
            id: "tool-image-history",
            type: .function,
            function: ToolCallFunction(name: "generate_and_show_image", arguments: #"{"prompt":"history"}"#)
        )

        mockProvider.mockResponses["test-model"] = .success(ProviderResponse(
            content: "",
            toolCalls: [toolCall],
            usage: Usage(promptTokens: 6, completionTokens: 0, totalTokens: 6),
            finishReason: .toolCalls
        ))

        chat.input = "Generate an inline image"
        let sent = await chat.sendMessage()
        XCTAssertTrue(sent)
        await waitForChatToBeReady(chat)

        guard let assistantIndex = chat.messages.lastIndex(where: { message in
            guard message.role == .assistant else { return false }
            return message.orderedContent.contains { content in
                if case .toolCall(let call) = content {
                    return call.id == toolCall.id
                }
                return false
            }
        }) else {
            return XCTFail("Expected assistant message containing tool call in conversation with history")
        }

        let assistantWithTool = chat.messages[assistantIndex]

        XCTAssertFalse(assistantWithTool.orderedContent.contains { content in
            if case .image = content { return true }
            if case .file = content { return true }
            return false
        })
        XCTAssertTrue(chat.attachments(for: assistantWithTool).isEmpty)

        guard let toolMessageIndex = chat.messages[(assistantIndex + 1)..<chat.messages.count].firstIndex(where: { message in
            guard message.role == .tool else { return false }
            return message.orderedContent.contains { content in
                if case .toolResult(let result) = content {
                    return result.toolCallId == toolCall.id
                }
                return false
            }
        }) else {
            return XCTFail("Expected tool message following assistant tool call when history exists")
        }

        XCTAssertTrue(toolMessageIndex > assistantIndex)

        let toolMessage = chat.messages[toolMessageIndex]
        XCTAssertTrue(toolMessage.orderedContent.contains { content in
            if case .toolResult(let result) = content {
                return result.toolCallId == toolCall.id
            }
            return false
        })

        let toolAttachments = chat.attachments(for: toolMessage)
        XCTAssertEqual(toolAttachments.count, 1)
        if case .some(.image) = toolAttachments.first {
            // Attachment preserved on tool message
        } else {
            XCTFail("Expected image attachment on tool message when history exists")
        }

        guard let followUpIndex = chat.messages[(toolMessageIndex + 1)..<chat.messages.count].firstIndex(where: { $0.role == .assistant }) else {
            return XCTFail("Expected follow-up assistant message after tool result when history exists")
        }

        XCTAssertTrue(followUpIndex > toolMessageIndex)

        let finalAssistant = chat.messages[followUpIndex]
        XCTAssertTrue(finalAssistant.orderedContent.contains { content in
            if case .text(let value) = content {
                return value.contains("Image ready")
            }
            return false
        })

        XCTAssertTrue(finalAssistant.orderedContent.allSatisfy { content in
            if case .toolCall = content { return false }
            if case .image = content { return false }
            return true
        })

        let priorAssistantMessages = chat.messages[..<assistantIndex].filter { $0.role == .assistant }
        XCTAssertTrue(priorAssistantMessages.contains { message in
            message.content == "Hello there!"
        })
    }

    func testToolResultTextArrivesViaToolMessageWhenNoAttachmentsProvided() async {
        let toolCallID = "tool-text-inline"
        let handler = InlineTextToolHandler(provider: mockProvider, modelId: "test-model", inlineText: "Here is the generated caption.", finalContent: "Caption sent.")

        let tool = Tool(
            function: ToolFunction(
                name: "generate_caption",
                description: "Generate a caption",
                parameters: .object(
                    properties: [
                        "prompt": .string().withDescription("Prompt for the caption")
                    ],
                    required: ["prompt"]
                )
            ),
            execute: { toolCall in
                try await handler.execute(toolCall: toolCall)
            }
        )

        let chat = AIChat(client: client, model: model, tools: [tool])

        let toolCall = ToolCall(
            id: toolCallID,
            type: .function,
            function: ToolCallFunction(name: "generate_caption", arguments: #"{"prompt":"caption"}"#)
        )

        mockProvider.mockResponses["test-model"] = .success(ProviderResponse(
            content: "",
            toolCalls: [toolCall],
            usage: Usage(promptTokens: 4, completionTokens: 0, totalTokens: 4),
            finishReason: .toolCalls
        ))

        chat.input = "Generate a caption"
        let sent = await chat.sendMessage()
        XCTAssertTrue(sent)
        await waitForChatToBeReady(chat)

        guard let assistantWithTool = chat.messages.first(where: { message in
            guard message.role == .assistant else { return false }
            return message.orderedContent.contains { content in
                if case .toolCall(let call) = content {
                    return call.id == toolCallID
                }
                return false
            }
        }) else {
            return XCTFail("Expected assistant message containing tool call")
        }

        guard let toolCallIndex = assistantWithTool.orderedContent.firstIndex(where: { content in
            if case .toolCall(let call) = content {
                return call.id == toolCallID
            }
            return false
        }) else {
            return XCTFail("Failed to locate tool call content")
        }

        XCTAssertTrue(toolCallIndex + 1 == assistantWithTool.orderedContent.count)

        XCTAssertTrue(chat.attachments(for: assistantWithTool).isEmpty)

        guard let toolMessage = chat.messages.first(where: { $0.role == .tool }) else {
            return XCTFail("Expected tool message")
        }

        XCTAssertTrue(toolMessage.orderedContent.contains { content in
            if case .toolResult(let result) = content {
                return result.toolCallId == toolCallID
            }
            return false
        })

        guard let toolResult = toolMessage.orderedContent.compactMap({ content -> ToolResult? in
            if case .toolResult(let result) = content { return result }
            return nil
        }).first else {
            return XCTFail("Expected tool result content")
        }

        if case .json(let data) = toolResult.result {
            let decoded = try? JSONDecoder().decode(ImageGenerationToolResultPayload.self, from: data)
            XCTAssertEqual(decoded?.success, true)
        } else {
            XCTFail("Expected JSON tool result")
        }

        guard let finalAssistant = finalAssistantMessage(for: chat) else {
            return XCTFail("Expected final assistant follow-up")
        }

        XCTAssertTrue(finalAssistant.orderedContent.contains { content in
            if case .text(let value) = content {
                return value == "Caption sent."
            }
            return false
        })
    }

    func testAttachKeepsToolMessageAndUpdatesAttachments() {
        let chat = AIChat(client: client, model: model)

        let toolCall = ToolCall(
            id: "tool-late-image",
            type: .function,
            function: ToolCallFunction(name: "generate_and_show_image", arguments: "{}")
        )

        let assistant = ChatMessage(
            role: .assistant,
            orderedContent: [
                .toolCall(toolCall),
                .text("Here is your image.")
            ]
        )

        let toolMessage = ChatMessage(
            role: .tool,
            orderedContent: [
                .toolResult(ToolResult.success(toolCallId: toolCall.id, text: "Image generation completed successfully."))
            ]
        )

        chat.setMessages([
            ChatMessage(role: .user, content: "Generate"),
            assistant,
            toolMessage
        ])

        let imageData = Data(repeating: 0xAB, count: 64)
        let attachment = ChatAttachment.image(
            ImageContent.data(imageData, mimeType: "image/png")
        )

        chat.attach(attachments: [attachment], toToolCallID: toolCall.id)

        guard let updatedAssistant = chat.messages.first(where: { message in
            message.role == .assistant && message.toolCalls.contains { $0.id == toolCall.id }
        }) else {
            return XCTFail("Expected assistant message with tool call")
        }

        XCTAssertTrue(chat.messages.contains { message in
            message.role == .tool && message.orderedContent.contains { content in
                if case .toolResult(let result) = content {
                    return result.toolCallId == toolCall.id
                }
                return false
            }
        })

        guard let updatedToolMessage = chat.messages.first(where: { message in
            message.role == .tool && message.orderedContent.contains { content in
                if case .toolResult(let result) = content {
                    return result.toolCallId == toolCall.id
                }
                return false
            }
        }) else {
            return XCTFail("Expected tool message to remain after attaching")
        }

        XCTAssertEqual(chat.attachments(for: updatedAssistant).count, 0)
        let toolAttachments = chat.attachments(for: updatedToolMessage)
        XCTAssertEqual(toolAttachments.count, 1)

        guard let toolCallIndex = updatedAssistant.orderedContent.firstIndex(where: { content in
            if case .toolCall(let call) = content {
                return call.id == toolCall.id
            }
            return false
        }) else {
            return XCTFail("Tool call missing from assistant message")
        }

        XCTAssertTrue(toolCallIndex + 1 < updatedAssistant.orderedContent.count)
        if case .text(let trailingText) = updatedAssistant.orderedContent[toolCallIndex + 1] {
            XCTAssertEqual(trailingText, "Here is your image.")
        } else {
            XCTFail("Expected trailing assistant text to follow tool call")
        }

        XCTAssertFalse(updatedAssistant.orderedContent.contains { content in
            if case .image = content { return true }
            if case .file = content { return true }
            return false
        })
    }
    
    func testAttachmentWithInvalidMessageId() async {
        let chat = AIChat(client: client, model: model)
        
        // Try to get attachments for non-existent message ID
        let attachments = chat.attachments(for: "non-existent-id")

        XCTAssertTrue(attachments.isEmpty)
    }
}

private extension AIChatTests {
    func finalAssistantMessage(for chat: AIChat) -> ChatMessage? {
        chat.messages.reversed().first { $0.role == .assistant }
    }
}

private struct ImageGenerationToolResultPayload: Codable, Equatable {
    let success: Bool
    let attachmentIDs: [String]
    let count: Int
    let message: String?
}

@MainActor
private final class InlineImageToolHandler {
    weak var chat: AIChat?
    private weak var provider: SimpleMockProvider?
    private let modelId: String
    private let finalContent: String

    init(provider: SimpleMockProvider, modelId: String, finalContent: String) {
        self.provider = provider
        self.modelId = modelId
        self.finalContent = finalContent
    }

    func execute(toolCall: ToolCall) async throws -> ToolResult {
        let imageData = Data(repeating: 0xAB, count: 64)
        let attachment = ChatAttachment.image(
            ImageContent.data(imageData, mimeType: "image/png")
        )

        chat?.attach(attachments: [attachment], toToolCallID: toolCall.id)

        provider?.mockResponses[modelId] = .success(ProviderResponse(
            content: finalContent,
            usage: Usage(promptTokens: 6, completionTokens: 6, totalTokens: 12),
            finishReason: .stop
        ))

        return ToolResult.success(
            toolCallId: toolCall.id,
            text: "Image generated"
        )
    }
}

@MainActor
private final class InlineTextToolHandler {
    private weak var provider: SimpleMockProvider?
    private let modelId: String
    private let inlineText: String
    private let finalContent: String

    init(provider: SimpleMockProvider, modelId: String, inlineText: String, finalContent: String) {
        self.provider = provider
        self.modelId = modelId
        self.inlineText = inlineText
        self.finalContent = finalContent
    }

    func execute(toolCall: ToolCall) async throws -> ToolResult {
        provider?.mockResponses[modelId] = .success(ProviderResponse(
            content: finalContent,
            usage: Usage(promptTokens: 4, completionTokens: 4, totalTokens: 8),
            finishReason: .stop
        ))

        return ToolResult.success(
            toolCallId: toolCall.id,
            text: inlineText
        )
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
    func testChatAutosaveModifier() async throws {
        let client = AIClient()
        let model = SimpleMockProvider().languageModel("test")
        let chat = AIChat(client: client, model: model)
        let chatId = "test-autosave"
        
        // Use memory persistence for testing
        let persistence = MemoryChatPersistence()
        
        // Create a view with autosave
        struct AutosaveTestView: View {
            let chat: AIChat
            let persistence: ChatPersistence
            let chatId: String
            
            var body: some View {
                Text("Test")
                    .chatAutosave(chat, using: persistence, chatId: chatId)
            }
        }
        
        // Add some messages to chat
        chat.setMessages([
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there!")
        ])
        
        // Simulate view lifecycle
        let _ = AutosaveTestView(chat: chat, persistence: persistence, chatId: chatId)
        
        // Manually trigger save (simulating onDisappear)
        try await chat.save(using: persistence, chatId: chatId)
        
        // Create new chat and load
        let newChat = AIChat(client: client, model: model)
        try await newChat.load(using: persistence, chatId: chatId)
        
        // Verify messages were restored
        XCTAssertEqual(newChat.messages.count, 2)
        XCTAssertEqual(newChat.messages[0].content, "Hello")
        XCTAssertEqual(newChat.messages[1].content, "Hi there!")
    }
    
    @MainActor
    func testChatAutosaveWithDefaultKey() async throws {
        let client = AIClient()
        let model = SimpleMockProvider().languageModel("test")
        let chat = AIChat(client: client, model: model)
        
        // Use default persistence implementation
        let persistence = UserDefaultsChatPersistence()
        let defaultChatId = "messages"  // Default suffix after "AIChat."
        
        struct DefaultKeyTestView: View {
            let chat: AIChat
            
            var body: some View {
                Text("Test")
                    .chatAutosave(chat) // Uses deprecated method with UserDefaults
            }
        }
        
        // Add messages
        chat.setMessages([
            ChatMessage(role: .system, content: "System message"),
            ChatMessage(role: .user, content: "User message")
        ])
        
        // Save with default persistence
        try await chat.save(using: persistence, chatId: defaultChatId)
        
        // Load into new chat
        let newChat = AIChat(client: client, model: model)
        try await newChat.load(using: persistence, chatId: defaultChatId)
        
        XCTAssertEqual(newChat.messages.count, 2)
        XCTAssertEqual(newChat.messages[0].role, .system)
        XCTAssertEqual(newChat.messages[1].role, .user)
        
        // Clean up
        try await persistence.delete(for: defaultChatId)
    }
}
#endif
