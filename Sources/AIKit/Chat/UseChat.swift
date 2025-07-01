import SwiftUI

/// A property wrapper that provides chat functionality in SwiftUI views.
///
/// `@UseChat` is the SwiftUI equivalent of Vercel AI SDK's `useChat` hook,
/// providing automatic state management and UI bindings for chat interfaces.
///
/// ## Basic Usage
///
/// ```swift
/// struct ChatView: View {
///     @UseChat(model: openai("gpt-4")) var chat
///     
///     var body: some View {
///         VStack {
///             ScrollView {
///                 ForEach(chat.messages) { message in
///                     MessageRow(message: message)
///                 }
///             }
///             
///             ChatInput(chat: chat)
///         }
///     }
/// }
/// ```
///
/// ## With Tools
///
/// ```swift
/// @UseChat(
///     model: openai("gpt-4"),
///     tools: [weatherTool, calculatorTool]
/// ) var chat
/// ```
///
/// ## With Callbacks
///
/// ```swift
/// @UseChat(
///     model: openai("gpt-4"),
///     onFinish: { message, details in
///         print("Message completed: \(message.content)")
///         print("Tokens used: \(details.usage?.totalTokens ?? 0)")
///     }
/// ) var chat
/// ```
@available(iOS 16.0, macOS 13.0, *)
@propertyWrapper
@MainActor
public struct UseChat: DynamicProperty {
    @StateObject private var chat: AIChat
    
    /// The wrapped AIChat instance
    @MainActor
    public var wrappedValue: AIChat {
        chat
    }
    
    /// The projected value provides direct access to the AIChat instance
    @MainActor
    public var projectedValue: AIChat {
        chat
    }
    
    /// Initialize with an existing AIClient instance
    @MainActor
    public init(
        client: AIClient? = nil,
        model: LanguageModel,
        api: String? = nil,
        tools: [Tool] = [],
        maxSteps: Int = 5,
        onFinish: ((ChatMessage, FinishDetails) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        onResponse: ((HTTPURLResponse) -> Void)? = nil
    ) {
        _chat = StateObject(wrappedValue: AIChat(
            client: client ?? AIClient(),
            model: model,
            api: api,
            tools: tools,
            maxSteps: maxSteps,
            onFinish: onFinish,
            onError: onError,
            onResponse: onResponse
        ))
    }
}

// MARK: - SwiftUI View Extensions

@available(iOS 16.0, macOS 13.0, *)
public extension View {
    /// Provides chat functionality to a view
    /// - Parameters:
    ///   - client: The AI client to use
    ///   - model: The language model to use
    ///   - tools: Available tools for the AI
    ///   - content: The content closure that receives the chat instance
    func withChat<ContentView: View>(
        client: AIClient? = nil,
        model: LanguageModel,
        tools: [Tool] = [],
        @ViewBuilder content: @escaping (AIChat) -> ContentView
    ) -> some View {
        modifier(ChatModifier(
            client: client,
            model: model,
            tools: tools,
            content: content
        ))
    }
}

// MARK: - Chat Modifier

@available(iOS 16.0, macOS 13.0, *)
@MainActor
struct ChatModifier<ContentView: View>: ViewModifier {
    @StateObject private var chat: AIChat
    let contentBuilder: (AIChat) -> ContentView
    
    @MainActor
    init(
        client: AIClient?,
        model: LanguageModel,
        tools: [Tool],
        content: @escaping (AIChat) -> ContentView
    ) {
        _chat = StateObject(wrappedValue: AIChat(
            client: client ?? AIClient(),
            model: model,
            tools: tools
        ))
        self.contentBuilder = content
    }
    
    func body(content: Content) -> some View {
        contentBuilder(chat)
    }
}

// MARK: - Convenience Views

/// A basic chat input view that works with AIChat
@available(iOS 16.0, macOS 13.0, *)
public struct ChatInput: View {
    @ObservedObject var chat: AIChat
    @FocusState private var isFocused: Bool
    
    public init(chat: AIChat) {
        self.chat = chat
    }
    
    public var body: some View {
        HStack {
            TextField("Type a message...", text: $chat.input)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(chat.status != .ready)
                .focused($isFocused)
                .onSubmit {
                    Task {
                        await chat.sendMessage()
                    }
                }
            
            if chat.isLoading {
                Button("Stop") {
                    chat.stop()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Send") {
                    Task {
                        await chat.sendMessage()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(chat.input.isEmpty || chat.status != .ready)
            }
        }
        .padding()
    }
}

/// A basic message view for displaying chat messages
@available(iOS 16.0, macOS 13.0, *)
public struct ChatMessageView: View {
    let message: ChatMessage
    
    public init(message: ChatMessage) {
        self.message = message
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(message.role == .user ? Color.blue : Color.gray)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(message.role == .user ? "U" : "AI")
                        .font(.caption)
                        .foregroundColor(.white)
                )
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                
                // Tool calls
                if !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.toolCalls, id: \.id) { toolCall in
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.caption)
                                Text(toolCall.function.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

/// A complete chat interface view
@available(iOS 16.0, macOS 13.0, *)
public struct ChatView: View {
    @UseChat var chat: AIChat
    
    public init(model: LanguageModel, tools: [Tool] = []) {
        _chat = UseChat(model: model, tools: tools)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(chat.messages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                            
                            Divider()
                        }
                    }
                }
                .onChange(of: chat.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(chat.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            // Error display
            if chat.error != nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("An error occurred")
                        .font(.caption)
                    Spacer()
                    Button("Retry") {
                        Task {
                            await chat.reload()
                        }
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }
            
            Divider()
            
            // Input
            ChatInput(chat: chat)
        }
    }
}