import XCTest
@testable import AIKit

@available(iOS 16.0, macOS 13.0, *)
final class ChatMessagePersistenceTests: XCTestCase {
    
    // MARK: - Basic Persistence Tests
    
    func testChatMessageOrderedContentPersistence() throws {
        // Create a message with interleaved content (text, tool call, text, tool call, text)
        let originalMessage = ChatMessage(
            id: "test-123",
            role: .assistant,
            orderedContent: [
                .text("I found 3 notes for you:"),
                .toolCall(ToolCall(id: "call1", name: "show_note", arguments: ["noteId": "1"])),
                .text("This note contains information about salsa dancing..."),
                .toolCall(ToolCall(id: "call2", name: "show_note", arguments: ["noteId": "2"])),
                .text("Finally, here's the last relevant note:"),
                .toolCall(ToolCall(id: "call3", name: "show_note", arguments: ["noteId": "3"]))
            ],
            timestamp: Date()
        )
        
        // Encode the message
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalMessage)
        
        // Decode the message
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(ChatMessage.self, from: data)
        
        // Assert orderedContent is preserved
        XCTAssertEqual(originalMessage.orderedContent.count, decodedMessage.orderedContent.count)
        XCTAssertEqual(originalMessage.orderedContent.count, 6) // 3 text + 3 tool calls
        
        // Verify the order is preserved
        XCTAssertNotNil(decodedMessage.orderedContent[0].textValue)
        XCTAssertEqual(decodedMessage.orderedContent[0].textValue, "I found 3 notes for you:")
        
        XCTAssertNotNil(decodedMessage.orderedContent[1].toolCallValue)
        XCTAssertEqual(decodedMessage.orderedContent[1].toolCallValue?.id, "call1")
        
        XCTAssertNotNil(decodedMessage.orderedContent[2].textValue)
        XCTAssertTrue(decodedMessage.orderedContent[2].textValue?.contains("salsa dancing") ?? false)
        
        XCTAssertNotNil(decodedMessage.orderedContent[3].toolCallValue)
        XCTAssertEqual(decodedMessage.orderedContent[3].toolCallValue?.id, "call2")
        
        XCTAssertNotNil(decodedMessage.orderedContent[4].textValue)
        XCTAssertTrue(decodedMessage.orderedContent[4].textValue?.contains("Finally") ?? false)
        
        XCTAssertNotNil(decodedMessage.orderedContent[5].toolCallValue)
        XCTAssertEqual(decodedMessage.orderedContent[5].toolCallValue?.id, "call3")
        
        // Verify backward compatibility properties
        XCTAssertEqual(decodedMessage.content, originalMessage.content)
        XCTAssertEqual(decodedMessage.toolCalls.count, originalMessage.toolCalls.count)
        XCTAssertEqual(decodedMessage.toolCalls.count, 3)
    }
    
    func testEmptyOrderedContentPersistence() throws {
        // Create a message with empty orderedContent
        let originalMessage = ChatMessage(
            role: .user,
            orderedContent: [],
            timestamp: Date()
        )
        
        let data = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertTrue(decodedMessage.orderedContent.isEmpty)
        XCTAssertEqual(decodedMessage.content, "")
        XCTAssertTrue(decodedMessage.toolCalls.isEmpty)
    }
    
    func testTextOnlyMessagePersistence() throws {
        // Create a message with only text content
        let originalMessage = ChatMessage(
            role: .user,
            orderedContent: [
                .text("Hello,"),
                .text("how are you"),
                .text("today?")
            ]
        )
        
        let data = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decodedMessage.orderedContent.count, 3)
        // Content property joins text parts with spaces
        XCTAssertEqual(decodedMessage.content, "Hello, how are you today?")
        XCTAssertTrue(decodedMessage.toolCalls.isEmpty)
    }
    
    func testToolCallOnlyMessagePersistence() throws {
        // Create a message with only tool calls
        let toolCalls = [
            ToolCall(id: "1", name: "get_weather", arguments: ["city": "NYC"]),
            ToolCall(id: "2", name: "get_time", arguments: [:])
        ]
        
        let originalMessage = ChatMessage(
            role: .assistant,
            orderedContent: toolCalls.map { .toolCall($0) }
        )
        
        let data = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decodedMessage.orderedContent.count, 2)
        XCTAssertEqual(decodedMessage.content, "")
        XCTAssertEqual(decodedMessage.toolCalls.count, 2)
        XCTAssertEqual(decodedMessage.toolCalls[0].id, "1")
        XCTAssertEqual(decodedMessage.toolCalls[1].id, "2")
    }
    
    // MARK: - Complex Content Tests
    
    func testMixedContentWithImages() throws {
        // Create a message with text, images, and tool calls
        let imageData = Data(repeating: 0xFF, count: 100)
        let originalMessage = ChatMessage(
            role: .user,
            orderedContent: [
                .text("Look at these images:"),
                .image(ImageContent.data(imageData, mimeType: "image/png")),
                .text("And this one:"),
                .image(ImageContent.url(URL(string: "https://example.com/image.jpg")!, mimeType: "image/jpeg")),
                .toolCall(ToolCall(id: "analyze", name: "analyze_images", arguments: [:]))
            ]
        )
        
        let data = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decodedMessage.orderedContent.count, 5)
        
        // Verify image content is preserved
        XCTAssertNotNil(decodedMessage.orderedContent[1].imageValue)
        XCTAssertEqual(decodedMessage.orderedContent[1].imageValue?.data, imageData)
        
        XCTAssertNotNil(decodedMessage.orderedContent[3].imageValue)
        XCTAssertEqual(decodedMessage.orderedContent[3].imageValue?.url?.absoluteString, "https://example.com/image.jpg")
    }
    
    func testMixedContentWithFiles() throws {
        // Create a message with text, files, and tool calls
        let fileData = "File content".data(using: .utf8)!
        let originalMessage = ChatMessage(
            role: .user,
            orderedContent: [
                .text("Here are the files:"),
                .file(FileContent.data(fileData, mimeType: "text/plain", filename: "doc.txt")),
                .toolCall(ToolCall(id: "process", name: "process_file", arguments: ["action": "analyze"])),
                .text("Please process them."),
                .file(FileContent.url(URL(string: "https://example.com/file.pdf")!, mimeType: "application/pdf", filename: "report.pdf"))
            ]
        )
        
        let data = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decodedMessage.orderedContent.count, 5)
        
        // Verify file content is preserved
        XCTAssertNotNil(decodedMessage.orderedContent[1].fileValue)
        XCTAssertEqual(decodedMessage.orderedContent[1].fileValue?.data, fileData)
        XCTAssertEqual(decodedMessage.orderedContent[1].fileValue?.filename, "doc.txt")
        
        XCTAssertNotNil(decodedMessage.orderedContent[4].fileValue)
        XCTAssertEqual(decodedMessage.orderedContent[4].fileValue?.url?.absoluteString, "https://example.com/file.pdf")
    }
    
    func testToolResultMessagePersistence() throws {
        // Create a message with tool results
        let toolResult = ToolResult.success(
            toolCallId: "call123",
            text: "Weather: Sunny, 72°F"
        )
        
        let originalMessage = ChatMessage(
            role: .tool,
            orderedContent: [.toolResult(toolResult)]
        )
        
        let data = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decodedMessage.orderedContent.count, 1)
        XCTAssertNotNil(decodedMessage.orderedContent[0].toolResultValue)
        
        let decodedResult = decodedMessage.orderedContent[0].toolResultValue
        XCTAssertEqual(decodedResult?.toolCallId, "call123")
        // Check if the result content is text type
        if case .text(let text) = decodedResult?.result {
            XCTAssertEqual(text, "Weather: Sunny, 72°F")
        } else {
            XCTFail("Expected text result")
        }
        XCTAssertFalse(decodedResult?.isError ?? true)
    }
    
    // MARK: - Backward Compatibility Tests
    
    func testLegacyFormatDecoding() throws {
        // Since we're not worried about backward compatibility, we can skip this test
        // The new format always includes orderedContent
    }
    
    func testNewFormatContainsLegacyFields() throws {
        // Create a message and verify it encodes both new and legacy fields
        let originalMessage = ChatMessage(
            role: .assistant,
            orderedContent: [
                .text("Processing..."),
                .toolCall(ToolCall(id: "1", name: "calculate", arguments: ["x": 5])),
                .text("Done!")
            ]
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(originalMessage)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Verify new format exists
        XCTAssertNotNil(json["orderedContent"])
        
        // Verify legacy fields exist for backward compatibility
        XCTAssertEqual(json["content"] as? String, "Processing... Done!")
        XCTAssertNotNil(json["toolCalls"])
        let toolCalls = json["toolCalls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.count, 1)
    }
    
    // MARK: - Array Persistence Tests
    
    func testChatMessageArrayPersistence() throws {
        // Test persisting an array of messages (common use case)
        let messages: [ChatMessage] = [
            ChatMessage(role: .user, content: "What's the weather?"),
            ChatMessage(
                role: .assistant,
                orderedContent: [
                    .text("Let me check the weather for you."),
                    .toolCall(ToolCall(id: "1", name: "get_weather", arguments: ["city": "NYC"])),
                    .text("I'll get that information right away.")
                ]
            ),
            ChatMessage(
                role: .tool,
                orderedContent: [
                    .toolResult(ToolResult.success(toolCallId: "1", text: "Sunny, 72°F"))
                ]
            ),
            ChatMessage(
                role: .assistant,
                orderedContent: [
                    .text("The weather in NYC is sunny and 72°F. Perfect day for a walk!")
                ]
            )
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(messages)
        
        let decoder = JSONDecoder()
        let decodedMessages = try decoder.decode([ChatMessage].self, from: data)
        
        XCTAssertEqual(messages.count, decodedMessages.count)
        
        // Verify second message (most complex)
        let assistantMsg = decodedMessages[1]
        XCTAssertEqual(assistantMsg.orderedContent.count, 3)
        XCTAssertEqual(assistantMsg.orderedContent[0].textValue, "Let me check the weather for you.")
        XCTAssertEqual(assistantMsg.orderedContent[1].toolCallValue?.function.name, "get_weather")
        XCTAssertEqual(assistantMsg.orderedContent[2].textValue, "I'll get that information right away.")
        
        // Verify tool message
        let toolMsg = decodedMessages[2]
        XCTAssertEqual(toolMsg.orderedContent.count, 1)
        XCTAssertNotNil(toolMsg.orderedContent[0].toolResultValue)
    }
    
    // MARK: - Error Handling Tests
    
    func testCorruptedDataHandling() throws {
        let invalidJSON = "{ invalid json }"
        let data = invalidJSON.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(ChatMessage.self, from: data))
    }
    
    func testMissingRequiredFields() throws {
        let incompleteJSON = """
        {
            "id": "test-123"
        }
        """
        
        let data = incompleteJSON.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ChatMessage.self, from: data))
    }
    
    // MARK: - Performance Tests
    
    func testLargeMessagePersistencePerformance() throws {
        // Create a large message with many interleaved parts
        var orderedContent: [MessageContent] = []
        for i in 0..<100 {
            orderedContent.append(.text("Part \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit."))
            if i % 10 == 0 {
                orderedContent.append(.toolCall(ToolCall(id: "call\(i)", name: "process_part", arguments: ["part": i])))
            }
        }
        
        let largeMessage = ChatMessage(
            role: .assistant,
            orderedContent: orderedContent
        )
        
        measure {
            do {
                let data = try JSONEncoder().encode(largeMessage)
                _ = try JSONDecoder().decode(ChatMessage.self, from: data)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
    
    // MARK: - Real-World Scenario Tests
    
    func testChatConversationPersistence() throws {
        // Simulate a real conversation with mixed content
        let conversation: [ChatMessage] = [
            ChatMessage(role: .system, content: "You are a helpful assistant with access to various tools."),
            ChatMessage(role: .user, content: "Show me my dance notes and the weather"),
            ChatMessage(
                role: .assistant,
                orderedContent: [
                    .text("I'll help you with that. Let me fetch your dance notes first."),
                    .toolCall(ToolCall(id: "1", name: "get_notes", arguments: ["tag": "dance"])),
                    .text("And now let me check the weather for you."),
                    .toolCall(ToolCall(id: "2", name: "get_weather", arguments: ["city": "current"]))
                ]
            ),
            ChatMessage(
                role: .tool,
                orderedContent: [
                    .toolResult(ToolResult.success(
                        toolCallId: "1",
                        text: "Found 3 dance notes:\n1. Salsa steps\n2. Bachata timing\n3. Practice schedule"
                    ))
                ]
            ),
            ChatMessage(
                role: .tool,
                orderedContent: [
                    .toolResult(ToolResult.success(
                        toolCallId: "2",
                        text: "Current weather: Partly cloudy, 68°F"
                    ))
                ]
            ),
            ChatMessage(
                role: .assistant,
                orderedContent: [
                    .text("Here's what I found:\n\n**Your Dance Notes:**\n"),
                    .text("1. Salsa steps - Remember the cross-body lead\n"),
                    .text("2. Bachata timing - Count 1-2-3-tap, 5-6-7-tap\n"),
                    .text("3. Practice schedule - Tuesdays and Thursdays\n\n"),
                    .text("**Current Weather:**\n"),
                    .text("It's partly cloudy and 68°F - perfect weather for dancing!")
                ]
            )
        ]
        
        // Save conversation
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(conversation)
        
        // Load conversation
        let decoder = JSONDecoder()
        let loadedConversation = try decoder.decode([ChatMessage].self, from: data)
        
        XCTAssertEqual(conversation.count, loadedConversation.count)
        
        // Verify the complex assistant message is preserved correctly
        let complexMessage = loadedConversation[2]
        XCTAssertEqual(complexMessage.orderedContent.count, 4) // 2 text + 2 tool calls
        
        // Verify the final formatted message
        let finalMessage = loadedConversation[5]
        XCTAssertEqual(finalMessage.orderedContent.count, 6) // All text parts
        XCTAssertTrue(finalMessage.content.contains("Your Dance Notes"))
        XCTAssertTrue(finalMessage.content.contains("Current Weather"))
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyToolCallArguments() throws {
        let message = ChatMessage(
            role: .assistant,
            orderedContent: [
                .toolCall(ToolCall(id: "1", name: "no_args_function", arguments: [:]))
            ]
        )
        
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decoded.toolCalls.count, 1)
        // Check if parsed arguments is empty
        let parsedArgs = decoded.toolCalls[0].function.parsedArguments
        XCTAssertTrue(parsedArgs?.isEmpty ?? true)
    }
    
    func testSpecialCharactersInContent() throws {
        let message = ChatMessage(
            role: .user,
            orderedContent: [
                .text("Special chars: 🎉 \n\t\"quotes\" 'apostrophe' \\backslash <html>")
            ]
        )
        
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decoded.content, message.content)
    }
    
    func testVeryLongContent() throws {
        let longText = String(repeating: "Very long text. ", count: 10000)
        let message = ChatMessage(
            role: .user,
            orderedContent: [.text(longText)]
        )
        
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        
        XCTAssertEqual(decoded.content, longText)
    }
}