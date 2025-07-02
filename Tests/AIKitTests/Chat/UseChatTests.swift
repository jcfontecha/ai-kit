import XCTest
import SwiftUI
@testable import AIKit

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class UseChatTests: XCTestCase {
    
    var mockProvider: SimpleMockProvider!
    var model: LanguageModel!
    
    override func setUp() async throws {
        mockProvider = SimpleMockProvider()
        model = mockProvider.languageModel("test-model")
    }
    
    // MARK: - Basic UseChat Tests
    
    func testUseChatInitialization() {
        struct TestView: View {
            @UseChat(model: SimpleMockProvider().languageModel("test")) var chat
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = TestView()
        
        XCTAssertNotNil(view.chat)
        XCTAssertTrue(view.chat.messages.isEmpty)
        XCTAssertEqual(view.chat.input, "")
        XCTAssertEqual(view.chat.status, .ready)
    }
    
    func testUseChatWithClient() {
        let client = AIClient()
        
        struct TestView: View {
            @UseChat var chat: AIChat
            
            init(client: AIClient, model: LanguageModel) {
                self._chat = UseChat(client: client, model: model)
            }
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = TestView(client: client, model: model)
        
        XCTAssertNotNil(view.chat)
        XCTAssertEqual(view.chat.status, .ready)
    }
    
    func testUseChatWithTools() {
        let testTool = Tool(
            type: .function,
            function: ToolFunction(
                name: "test_tool",
                description: "Test tool",
                parameters: .object(properties: [:])
            ),
            execute: { _ in .success(toolCallId: "test", text: "Result") }
        )
        
        struct TestView: View {
            @UseChat var chat: AIChat
            
            init(model: LanguageModel, tools: [Tool]) {
                self._chat = UseChat(model: model, tools: tools)
            }
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = TestView(model: model, tools: [testTool])
        
        XCTAssertNotNil(view.chat)
        XCTAssertEqual(view.chat.tools.count, 1)
        XCTAssertEqual(view.chat.tools[0].function.name, "test_tool")
    }
    
    func testUseChatWithCallbacks() {
        var finishCalled = false
        var errorCalled = false
        
        struct TestView: View {
            @UseChat var chat: AIChat
            
            init(model: LanguageModel, onFinish: @escaping (ChatMessage, FinishDetails) -> Void, onError: @escaping (Error) -> Void) {
                self._chat = UseChat(
                    model: model,
                    onFinish: onFinish,
                    onError: onError
                )
            }
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = TestView(
            model: model,
            onFinish: { _, _ in finishCalled = true },
            onError: { _ in errorCalled = true }
        )
        
        XCTAssertNotNil(view.chat)
        // Callbacks are stored in the chat instance
        XCTAssertNotNil(view.chat.onFinish)
        XCTAssertNotNil(view.chat.onError)
    }
    
    func testUseChatWithMaxSteps() {
        struct TestView: View {
            @UseChat var chat: AIChat
            
            init(model: LanguageModel, maxSteps: Int) {
                self._chat = UseChat(model: model, maxSteps: maxSteps)
            }
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = TestView(model: model, maxSteps: 10)
        
        XCTAssertNotNil(view.chat)
        XCTAssertEqual(view.chat.maxSteps, 10)
    }
    
    // MARK: - Binding Tests
    
    func testUseChatInputBinding() {
        // Create a chat instance directly to test input binding
        let mockProvider = SimpleMockProvider()
        let model = mockProvider.languageModel("test")
        let chat = AIChat(client: AIClient(), model: model)
        
        // Test initial value
        XCTAssertEqual(chat.input, "")
        
        // Test setting value
        chat.input = "Hello"
        XCTAssertEqual(chat.input, "Hello")
        
        // Test clearing value
        chat.input = ""
        XCTAssertEqual(chat.input, "")
    }
    
    func testUseChatPropertyAccess() {
        struct TestView: View {
            @UseChat(model: SimpleMockProvider().languageModel("test")) var chat
            
            var isLoading: Bool {
                chat.isLoading
            }
            
            var messageCount: Int {
                chat.messages.count
            }
            
            var body: some View {
                VStack {
                    if isLoading {
                        ProgressView()
                    }
                    Text("Messages: \(messageCount)")
                }
            }
        }
        
        let view = TestView()
        
        XCTAssertFalse(view.isLoading)
        XCTAssertEqual(view.messageCount, 0)
    }
    
    // MARK: - Interaction Tests
    
    func testUseChatSendMessage() async {
        // Set up mock response first
        mockProvider.mockResponses["test-model"] = .success(ProviderResponse(
            text: "Response",
            finishReason: .stop
        ))
        
        // Create AIChat directly with our mock provider
        let client = AIClient()
        let chat = AIChat(client: client, model: model)
        
        // Send message
        chat.input = "Test message"
        await chat.sendMessage()
        
        // Wait for response
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].content, "Test message")
        XCTAssertEqual(chat.messages[0].role, .user)
        XCTAssertEqual(chat.messages[1].content, "Response")
        XCTAssertEqual(chat.messages[1].role, .assistant)
        XCTAssertEqual(chat.input, "") // Should be cleared
    }
    
    func testUseChatMethodAccess() {
        struct TestView: View {
            @UseChat(model: SimpleMockProvider().languageModel("test")) var chat
            
            func performActions() {
                // Test various methods are accessible
                chat.clear()
                chat.stop()
                chat.setMessages([
                    ChatMessage(role: .user, content: "Test")
                ])
                chat.editMessage(id: "123", newContent: "Edited")
                chat.removeMessage(id: "123")
                
                // Test getters
                _ = chat.lastUserMessage
                _ = chat.lastAssistantMessage
                _ = chat.exportAsMarkdown()
            }
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = TestView()
        view.performActions()
        
        // Methods should execute without errors
        XCTAssertNotNil(view.chat)
    }
    
    // MARK: - SwiftUI Preview Tests
    
    func testUseChatInPreview() {
        // Test that UseChat can be used in SwiftUI previews
        struct PreviewView: View {
            @UseChat(model: SimpleMockProvider().languageModel("preview-model")) var chat
            
            var body: some View {
                VStack {
                    ForEach(chat.messages) { message in
                        Text(message.content)
                    }
                    TextField("Message", text: Binding(
                        get: { chat.input },
                        set: { chat.input = $0 }
                    ))
                }
            }
        }
        
        let preview = PreviewView()
        XCTAssertNotNil(preview.chat)
        XCTAssertEqual(preview.chat.status, .ready)
    }
    
    // MARK: - Default Client Tests
    
    func testUseChatWithDefaultClient() {
        // When no client is provided, it should use the default shared client
        struct TestView: View {
            @UseChat(model: SimpleMockProvider().languageModel("test")) var chat
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = TestView()
        XCTAssertNotNil(view.chat)
        XCTAssertNotNil(view.chat.client)
    }
}