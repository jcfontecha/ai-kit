import Foundation
import Combine

/// A chat manager that provides real-time streaming chat functionality with AI models.
///
/// `AIChat` is the Swift equivalent of Vercel AI SDK's `useChat` hook, providing:
/// - Message streaming from AI providers
/// - Automatic state management (messages, input, status, errors)
/// - Tool execution support
/// - Seamless SwiftUI integration
///
/// ## Basic Usage
///
/// ```swift
/// @StateObject private var chat = AIChat(
///     client: aiClient,
///     model: openai("gpt-4"),
///     api: "/api/chat"  // Optional: for server-side streaming
/// )
///
/// var body: some View {
///     VStack {
///         ScrollView {
///             ForEach(chat.messages) { message in
///                 MessageView(message: message)
///             }
///         }
///         
///         HStack {
///             TextField("Type a message...", text: $chat.input)
///                 .disabled(chat.status != .ready)
///             
///             Button("Send") {
///                 await chat.sendMessage()
///             }
///             .disabled(chat.status != .ready || chat.input.isEmpty)
///         }
///     }
/// }
/// ```
@available(iOS 16.0, macOS 13.0, *)
@MainActor
public class AIChat: ObservableObject {
    
    // MARK: - Published Properties
    
    /// The list of messages in the chat
    @Published public internal(set) var messages: [ChatMessage] = []
    
    /// The current input text
    @Published public var input: String = ""
    
    /// The current status of the chat
    @Published public internal(set) var status: ChatStatus = .ready
    
    /// The current error, if any
    @Published public internal(set) var error: Error?
    
    /// Whether the chat is currently loading
    public var isLoading: Bool {
        status == .submitted || status == .streaming
    }
    
    // MARK: - Private Properties
    
    internal let client: AIClient
    internal let model: LanguageModel
    internal let api: String?
    internal let tools: [Tool]
    internal let maxSteps: Int
    internal let onFinish: ((ChatMessage, FinishDetails) -> Void)?
    internal let onError: ((Error) -> Void)?
    internal let onResponse: ((HTTPURLResponse) -> Void)?
    internal var streamTask: Task<Void, Never>?
    
    // Track attachments per message ID
    internal var messageAttachments: [String: [ChatAttachment]] = [:]
    
    // MARK: - Initialization
    
    /// Creates a new AIChat instance
    /// - Parameters:
    ///   - client: The AI client to use for generating responses
    ///   - model: The language model to use
    ///   - api: Optional API endpoint for server-side streaming
    ///   - tools: Tools available for the AI to use
    ///   - maxSteps: Maximum number of tool execution steps
    ///   - onFinish: Callback when a message is completed
    ///   - onError: Callback when an error occurs
    ///   - onResponse: Callback when HTTP response is received
    public init(
        client: AIClient,
        model: LanguageModel,
        api: String? = nil,
        tools: [Tool] = [],
        maxSteps: Int = 5,
        onFinish: ((ChatMessage, FinishDetails) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        onResponse: ((HTTPURLResponse) -> Void)? = nil
    ) {
        self.client = client
        self.model = model
        self.api = api
        self.tools = tools
        self.maxSteps = maxSteps
        self.onFinish = onFinish
        self.onError = onError
        self.onResponse = onResponse
    }
    
    // MARK: - Public Methods
    
    /// Send the current input as a new message
    @discardableResult
    public func sendMessage() async -> Bool {
        await send(content: input)
    }
    
    /// Send a message with the specified content
    /// - Parameter content: The message content to send
    /// - Returns: Whether the message was sent successfully
    @discardableResult
    public func send(content: String) async -> Bool {
        guard !content.isEmpty, status == .ready else { return false }
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: content)
        messages.append(userMessage)
        
        // Clear input
        input = ""
        
        // Update status
        status = .submitted
        error = nil
        
        // Start streaming
        await streamResponse()
        
        return true
    }
    
    /// Append a message to the chat
    /// - Parameter message: The message to append
    public func append(_ message: ChatMessage) async {
        messages.append(message)
        
        if message.role == .user {
            await streamResponse()
        }
    }
    
    /// Stop the current streaming response
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        status = .ready
    }
    
    /// Reload the last AI message
    public func reload() async {
        guard status == .ready || status == .error else { return }
        
        // Remove last assistant message if exists
        if let lastMessage = messages.last, lastMessage.role == .assistant {
            messages.removeLast()
        }
        
        // Reset error
        error = nil
        
        // Stream new response
        await streamResponse()
    }
    
    /// Set the messages directly
    /// - Parameter newMessages: The new message list
    public func setMessages(_ newMessages: [ChatMessage]) {
        messages = newMessages
    }
    
    /// Clear all messages
    public func clear() {
        messages = []
        input = ""
        status = .ready
        error = nil
        streamTask?.cancel()
        streamTask = nil
    }
    
    // MARK: - Private Methods
    
    private func streamResponse() async {
        streamTask?.cancel()
        
        streamTask = Task {
            do {
                status = .streaming
                
                // Create assistant message
                var assistantMessage = ChatMessage(role: .assistant, content: "")
                let messageIndex = messages.count
                messages.append(assistantMessage)
                
                // Convert ChatMessage to CoreMessage
                let coreMessages = messages.map { $0.toCoreMessage() }
                
                // Stream response
                let streamResult = await client.streamText(
                    model,
                    messages: coreMessages,
                    tools: tools,
                    maxSteps: maxSteps
                )
                
                var fullContent = ""
                var finishReason: FinishReason?
                var usage: TokenUsage?
                
                for try await chunk in streamResult.textStream {
                    if Task.isCancelled { break }
                    
                    // Accumulate text
                    if !chunk.delta.isEmpty {
                        fullContent += chunk.delta
                        assistantMessage.content = fullContent
                        if messageIndex < messages.count {
                            messages[messageIndex] = assistantMessage
                        }
                    }
                    
                    // Handle tool calls
                    if let toolCalls = chunk.toolCalls {
                        for toolCall in toolCalls {
                            assistantMessage.toolCalls.append(toolCall)
                            if messageIndex < messages.count {
                                messages[messageIndex] = assistantMessage
                            }
                        }
                    }
                    
                    // Update finish reason and usage
                    if let chunkFinishReason = chunk.finishReason {
                        finishReason = chunkFinishReason
                    }
                    
                    if let chunkUsage = chunk.usage {
                        usage = chunkUsage
                    }
                }
                
                status = .ready
                
                // Call onFinish callback
                if let finishReason = finishReason {
                    let details = FinishDetails(
                        usage: usage,
                        finishReason: finishReason
                    )
                    onFinish?(assistantMessage, details)
                }
                
            } catch {
                status = .error
                self.error = error
                onError?(error)
                
                // Remove empty assistant message on error
                if let lastMessage = messages.last,
                   lastMessage.role == .assistant,
                   lastMessage.content.isEmpty {
                    messages.removeLast()
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// The status of the chat
@available(iOS 16.0, macOS 13.0, *)
public enum ChatStatus: String, Sendable {
    /// Ready to accept new messages
    case ready
    /// Message has been submitted and awaiting response
    case submitted
    /// Response is actively streaming
    case streaming
    /// An error occurred
    case error
}

/// Details about a finished message
@available(iOS 16.0, macOS 13.0, *)
public struct FinishDetails: Sendable {
    /// Token usage information
    public let usage: TokenUsage?
    /// The reason the generation finished
    public let finishReason: FinishReason
}

/// A message in the chat
@available(iOS 16.0, macOS 13.0, *)
public struct ChatMessage: Identifiable, Sendable {
    /// Unique identifier for the message
    public let id: String
    /// The role of the message sender
    public let role: MessageRole
    /// The content of the message
    public var content: String
    /// Tool calls made in this message
    public var toolCalls: [ToolCall] = []
    /// Timestamp when the message was created
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        toolCalls: [ToolCall] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.timestamp = timestamp
    }
    
    /// Convert to CoreMessage for AIClient
    func toCoreMessage() -> CoreMessage {
        var messageContent: [MessageContent] = []
        
        if !content.isEmpty {
            messageContent.append(.text(content))
        }
        
        for toolCall in toolCalls {
            messageContent.append(.toolCall(toolCall))
        }
        
        return CoreMessage(role: role, content: messageContent)
    }
}