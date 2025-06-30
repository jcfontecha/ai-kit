import Foundation

// MARK: - Message Tracking System

/// Internal message tracking system for streaming operations.
///
/// This system automatically manages assistant messages, tool calls, and tool results
/// during streaming, matching Vercel AI SDK's behavior where the framework handles
/// message creation and updates transparently.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal actor StreamingMessageTracker {
    
    // MARK: - Properties
    
    /// Accumulated text content
    private var accumulatedText: String = ""
    
    /// Accumulated tool calls
    private var accumulatedToolCalls: [ToolCall] = []
    
    /// Accumulated tool results
    private var accumulatedToolResults: [ToolResult] = []
    
    /// Current message ID
    private let messageId: String
    
    /// Whether an assistant message has been created
    private var assistantMessageCreated: Bool = false
    
    /// The current assistant message being built
    private var currentAssistantMessage: Message?
    
    /// All messages in this streaming session
    private var messages: [Message] = []
    
    // MARK: - Initialization
    
    init(messageId: String = UUID().uuidString) {
        self.messageId = messageId
    }
    
    // MARK: - Text Accumulation
    
    /// Append text to the current assistant message
    func appendText(_ text: String) {
        accumulatedText += text
        updateAssistantMessage()
    }
    
    // MARK: - Tool Management
    
    /// Add a tool call to the current assistant message
    func addToolCall(_ toolCall: ToolCall) {
        accumulatedToolCalls.append(toolCall)
        updateAssistantMessage()
    }
    
    /// Add a tool result
    func addToolResult(_ toolResult: ToolResult) {
        accumulatedToolResults.append(toolResult)
        
        // Tool results become separate messages
        let toolMessage = Message.tool(result: toolResult)
        messages.append(toolMessage)
    }
    
    // MARK: - Message Building
    
    /// Update the assistant message with current accumulated content
    private func updateAssistantMessage() {
        // Build content array
        var content: [MessageContent] = []
        
        if !accumulatedText.isEmpty {
            content.append(.text(accumulatedText))
        }
        
        // Create or update the assistant message
        if !assistantMessageCreated && (!content.isEmpty || !accumulatedToolCalls.isEmpty) {
            // Create initial assistant message
            currentAssistantMessage = Message(
                role: .assistant,
                content: content,
                id: messageId,
                toolCalls: accumulatedToolCalls.isEmpty ? nil : accumulatedToolCalls
            )
            assistantMessageCreated = true
        } else if let _ = currentAssistantMessage {
            // Update existing message
            currentAssistantMessage = Message(
                role: .assistant,
                content: content,
                id: messageId,
                toolCalls: accumulatedToolCalls.isEmpty ? nil : accumulatedToolCalls
            )
        }
    }
    
    // MARK: - Message Retrieval
    
    /// Get the current assistant message (if any)
    var assistantMessage: Message? {
        return currentAssistantMessage
    }
    
    /// Get all messages generated during streaming
    var allMessages: [Message] {
        var result = messages
        
        // Add the assistant message if it exists and isn't already added
        if let assistant = currentAssistantMessage,
           !messages.contains(where: { $0.id == assistant.id }) {
            result.insert(assistant, at: 0) // Assistant message comes before tool results
        }
        
        return result
    }
    
    /// Get only the response messages (assistant + tool results)
    var responseMessages: [Message] {
        return allMessages
    }
    
    // MARK: - State Management
    
    /// Check if any content has been accumulated
    var hasContent: Bool {
        return !accumulatedText.isEmpty || !accumulatedToolCalls.isEmpty || !accumulatedToolResults.isEmpty
    }
    
    /// Check if tool calls are present
    var hasToolCalls: Bool {
        return !accumulatedToolCalls.isEmpty
    }
    
    /// Get accumulated text
    var text: String {
        return accumulatedText
    }
    
    /// Get tool calls
    var toolCalls: [ToolCall] {
        return accumulatedToolCalls
    }
    
    /// Get tool results
    var toolResults: [ToolResult] {
        return accumulatedToolResults
    }
    
    /// Finalize the message tracking
    func finalize() {
        // Ensure the assistant message is in the messages array
        if let assistant = currentAssistantMessage,
           !messages.contains(where: { $0.id == assistant.id }) {
            messages.insert(assistant, at: 0)
        }
    }
}

// MARK: - Step Message Builder

/// Builds response messages from streaming steps, matching Vercel's `toResponseMessages`
internal struct StepMessageBuilder {
    
    /// Build response messages from accumulated content
    static func buildMessages(
        text: String,
        toolCalls: [ToolCall],
        toolResults: [ToolResult],
        messageId: String,
        generateMessageId: () -> String = { UUID().uuidString }
    ) -> [Message] {
        var messages: [Message] = []
        
        // Build content array for assistant message
        var content: [MessageContent] = []
        
        // Add text content if present
        if !text.isEmpty {
            content.append(.text(text))
        }
        
        // Create assistant message if there's content or tool calls
        if !content.isEmpty || !toolCalls.isEmpty {
            let assistantMessage = Message(
                role: .assistant,
                content: content,
                id: messageId,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
            messages.append(assistantMessage)
        }
        
        // Add tool result messages
        for toolResult in toolResults {
            messages.append(.tool(result: toolResult))
        }
        
        return messages
    }
}

// MARK: - Stream Message Transformation

/// Transforms streaming chunks into properly formatted messages
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal struct StreamMessageTransformer {
    
    /// Transform a stream of chunks into a stream with message tracking
    static func transform<T: Sendable>(
        stream: AsyncThrowingStream<T, Error>,
        extractText: @escaping @Sendable (T) -> String?,
        extractToolCall: @escaping @Sendable (T) -> ToolCall?,
        extractToolResult: @escaping @Sendable (T) -> ToolResult?
    ) -> (stream: AsyncThrowingStream<T, Error>, tracker: StreamingMessageTracker) {
        let tracker = StreamingMessageTracker()
        
        let transformedStream = AsyncThrowingStream<T, Error> { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        // Extract and track content
                        if let text = extractText(chunk) {
                            await tracker.appendText(text)
                        }
                        
                        if let toolCall = extractToolCall(chunk) {
                            await tracker.addToolCall(toolCall)
                        }
                        
                        if let toolResult = extractToolResult(chunk) {
                            await tracker.addToolResult(toolResult)
                        }
                        
                        // Forward the chunk
                        continuation.yield(chunk)
                    }
                    
                    // Finalize tracking
                    await tracker.finalize()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        
        return (transformedStream, tracker)
    }
}