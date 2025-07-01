# AIKit Chat Utility - Revised Proposal

*Building on existing AIKit infrastructure for a Swift-first chat experience*

## 🎯 Overview

This revised proposal creates a chat utility that leverages AIKit's existing types and infrastructure rather than duplicating functionality. The focus is on providing a high-level, SwiftUI-friendly abstraction for chat applications.

## 🏗️ Core Design

### `AIChat` - High-Level Chat Orchestrator

```swift
@MainActor
public class AIChat: ObservableObject {
    // MARK: - State built on existing types
    @Published private(set) var messages: [CoreMessage] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var error: AIError?
    @Published var draft = ""
    
    // MARK: - Core dependencies
    private let client: AIClient
    private let model: LanguageModel
    private var streamTask: Task<Void, Never>?
    
    // MARK: - Configuration
    public struct Configuration {
        var systemMessage: String?
        var maxSteps: Int = 1
        var tools: [String: Tool] = [:]
        var onToolCall: ((ToolCall) async throws -> ToolResult)?
        
        public static let `default` = Configuration()
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    public init(
        client: AIClient,
        model: LanguageModel,
        configuration: Configuration = .default
    ) {
        self.client = client
        self.model = model
        self.configuration = configuration
        
        // Add system message if configured
        if let system = configuration.systemMessage {
            messages.append(CoreMessage.system(system))
        }
    }
}
```

### Core Methods - Leveraging Existing Infrastructure

```swift
extension AIChat {
    // Send a message and handle the response
    public func send(_ content: String) async throws {
        guard !content.isEmpty else { return }
        
        // Add user message using existing CoreMessage
        let userMessage = CoreMessage.user(content)
        messages.append(userMessage)
        draft = ""
        
        // Stream the response using existing infrastructure
        isStreaming = true
        defer { isStreaming = false }
        
        do {
            let stream = try await client.streamText(
                model,
                messages: messages,
                tools: Array(configuration.tools.values),
                maxSteps: configuration.maxSteps
            )
            
            // Use StreamTextResult's built-in message tracking
            for try await _ in stream {
                // The stream automatically tracks messages
            }
            
            // Add the accumulated messages
            if let responseMessages = stream.responseMessages {
                messages.append(contentsOf: responseMessages)
            }
            
            error = nil
        } catch {
            self.error = error as? AIError ?? .unknown(error)
            throw error
        }
    }
    
    // Regenerate the last assistant response
    public func regenerate() async throws {
        // Remove last assistant message
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.removeSubrange(lastIndex...)
        }
        
        // Resend
        try await streamResponse()
    }
    
    // Stop ongoing generation
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    // Clear conversation (preserving system message)
    public func clear() {
        messages.removeAll { $0.role != .system }
        error = nil
    }
}
```

### SwiftUI Integration

```swift
// MARK: - SwiftUI Environment
private struct AIChatKey: EnvironmentKey {
    static let defaultValue: AIChat? = nil
}

extension EnvironmentValues {
    public var aiChat: AIChat? {
        get { self[AIChatKey.self] }
        set { self[AIChatKey.self] = newValue }
    }
}

// MARK: - View Modifiers
extension View {
    public func aiChat(_ chat: AIChat) -> some View {
        self.environment(\.aiChat, chat)
    }
}

// MARK: - Convenience Views
public struct AIChatView: View {
    @ObservedObject var chat: AIChat
    
    public var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: chat.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(chat.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input area
            AIChatInputView(chat: chat)
        }
        .alert("Error", isPresented: .constant(chat.error != nil)) {
            Button("OK") { chat.error = nil }
        } message: {
            Text(chat.error?.localizedDescription ?? "An error occurred")
        }
    }
}
```

### Message Rendering - Using Existing Types

```swift
struct MessageView: View {
    let message: CoreMessage
    
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Render content using existing MessageContent enum
                ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                    MessageContentView(content: content)
                }
                
                // Show tool calls if present
                if let toolCalls = message.toolCalls {
                    ForEach(toolCalls, id: \.id) { toolCall in
                        ToolCallView(toolCall: toolCall)
                    }
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(message.role == .user ? .white : .primary)
            .cornerRadius(16)
            
            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }
}

struct MessageContentView: View {
    let content: MessageContent
    
    var body: some View {
        switch content {
        case .text(let text):
            Text(text)
        case .image(let imageContent):
            AsyncImage(url: imageContent.url) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView()
            }
            .frame(maxHeight: 200)
        case .file(let fileContent):
            FileAttachmentView(file: fileContent)
        case .toolCall(let call):
            ToolCallView(toolCall: call)
        case .toolResult(let result):
            ToolResultView(result: result)
        }
    }
}
```

## 🔧 Tool Integration Enhancements

Building on the existing Tool system with chat-specific enhancements:

```swift
extension AIChat {
    // Register a tool with inline handler
    public func withTool<T: Codable>(
        _ tool: Tool,
        handler: @escaping (T) async throws -> ToolResult
    ) -> Self {
        var updatedTools = configuration.tools
        updatedTools[tool.name] = tool
        
        // Store handler for execution
        // Implementation detail...
        
        return self
    }
    
    // Handle tool calls with SwiftUI integration
    public func onToolCall(
        _ handler: @escaping (ToolCall) async throws -> ToolResult
    ) -> Self {
        // Update configuration with handler
        return self
    }
}
```

## 🎨 Advanced Features

### Conversation Persistence

```swift
extension AIChat {
    // Save conversation using existing types
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(messages)
        try data.write(to: url)
    }
    
    // Load conversation
    public func load(from url: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        self.messages = try decoder.decode([CoreMessage].self, from: data)
    }
}
```

### Streaming UI Updates

```swift
public struct StreamingMessageView: View {
    @ObservedObject var chat: AIChat
    
    var body: some View {
        VStack(alignment: .leading) {
            if chat.isStreaming,
               let lastMessage = chat.messages.last,
               lastMessage.role == .assistant {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("AI is typing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
```

## 📦 Integration with Existing AIKit

This chat utility:
- **Uses existing message types** (`CoreMessage`, `MessageContent`)
- **Leverages streaming infrastructure** (`StreamTextResult`, `StreamingMessageTracker`)
- **Works with AIClient** for all AI operations
- **Supports existing tools** with enhanced SwiftUI integration
- **Maintains provider abstraction** without reimplementing

## 🎯 Benefits

1. **No Duplication**: Builds on existing types rather than creating new ones
2. **SwiftUI Native**: First-class support for iOS apps
3. **Type Safe**: Leverages existing strongly-typed messages
4. **Streaming Ready**: Uses proven streaming infrastructure
5. **Tool Compatible**: Works with existing tool system
6. **Lightweight**: Thin orchestration layer over AIKit

## 📚 Example Usage

```swift
struct ContentView: View {
    @StateObject private var chat = AIChat(
        client: AIClient(),
        model: OpenAIProvider().languageModel("gpt-4"),
        configuration: .default
            .with(systemMessage: "You are a helpful assistant")
            .with(maxSteps: 3)
    )
    
    var body: some View {
        AIChatView(chat: chat)
            .navigationTitle("AI Chat")
    }
}
```

This revised proposal provides a focused, SwiftUI-friendly chat abstraction that complements rather than duplicates AIKit's existing infrastructure.