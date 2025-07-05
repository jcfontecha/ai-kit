import Foundation
import UniformTypeIdentifiers

// MARK: - Advanced Features Extension

@available(iOS 16.0, macOS 13.0, *)
extension AIChat {
    
    // MARK: - Attachments
    
    /// Send a message with attachments
    /// - Parameters:
    ///   - content: The message content
    ///   - attachments: File attachments to include
    /// - Returns: Whether the message was sent successfully
    @discardableResult
    public func sendMessage(withAttachments attachments: [ChatAttachment]) async -> Bool {
        guard !input.isEmpty || !attachments.isEmpty, status == .ready else { return false }
        
        // Create message content
        var content: [MessageContent] = []
        
        if !input.isEmpty {
            content.append(.text(input))
        }
        
        // Add attachments as file content
        for attachment in attachments {
            switch attachment {
            case .file(let fileContent):
                content.append(.file(fileContent))
            case .image(let imageContent):
                content.append(.image(imageContent))
            case .data(let data, let mimeType, let filename):
                let fileContent = FileContent.data(data, mimeType: mimeType, filename: filename)
                content.append(.file(fileContent))
            }
        }
        
        // Add user message
        let userMessage = ChatMessage(
            role: .user,
            content: input
        )
        messages.append(userMessage)
        
        // Track attachments for this message
        if !attachments.isEmpty {
            messageAttachments[userMessage.id] = attachments
        }
        
        // Clear input
        input = ""
        
        // Update status
        status = .submitted
        error = nil
        
        // Start streaming
        await streamResponseWithParts(content)
        
        return true
    }
    
    private func streamResponseWithParts(_ userParts: [MessageContent]) async {
        streamTask?.cancel()
        
        streamTask = Task {
            do {
                status = .streaming
                
                // Create assistant message
                var assistantMessage = ChatMessage(role: .assistant, content: "")
                let messageIndex = messages.count
                messages.append(assistantMessage)
                
                // Convert messages to CoreMessages with proper parts
                var coreMessages: [CoreMessage] = []
                
                for (index, message) in messages.enumerated() {
                    if index == messages.count - 2 { // The user message we just added
                        // Use the content we created with attachments
                        coreMessages.append(CoreMessage(role: .user, content: userParts))
                    } else {
                        coreMessages.append(message.toCoreMessage())
                    }
                }
                
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
                
                if let lastMessage = messages.last,
                   lastMessage.role == .assistant,
                   lastMessage.content.isEmpty {
                    messages.removeLast()
                }
            }
        }
    }
    
    // MARK: - Persistence
    
    /// Save the current chat state using the provided persistence implementation
    /// - Parameters:
    ///   - persistence: The persistence provider to use
    ///   - chatId: Unique identifier for this chat session
    public func save(using persistence: ChatPersistence, chatId: String) async throws {
        try await persistence.save(messages, for: chatId)
    }
    
    /// Load chat state using the provided persistence implementation
    /// - Parameters:
    ///   - persistence: The persistence provider to use
    ///   - chatId: Unique identifier for this chat session
    public func load(using persistence: ChatPersistence, chatId: String) async throws {
        let loadedMessages = try await persistence.load(for: chatId)
        messages = loadedMessages
        status = .ready
    }
    
    // MARK: - Legacy Persistence Methods (Deprecated)
    
    @available(*, deprecated, message: "Use save(using:chatId:) with a ChatPersistence implementation instead")
    public func save(to key: String = "AIChat.messages") {
        Task {
            let persistence = UserDefaultsChatPersistence()
            try? await save(using: persistence, chatId: key)
        }
    }
    
    @available(*, deprecated, message: "Use load(using:chatId:) with a ChatPersistence implementation instead")
    public func load(from key: String = "AIChat.messages") {
        Task {
            let persistence = UserDefaultsChatPersistence()
            try? await load(using: persistence, chatId: key)
        }
    }
    
    @available(*, deprecated, message: "Use save(using:chatId:) with FileChatPersistence instead")
    public func save(to url: URL) throws {
        // This is a synchronous method, so we can't easily convert to async
        // Just maintain the old implementation for backward compatibility
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(messages)
        try data.write(to: url)
    }
    
    @available(*, deprecated, message: "Use load(using:chatId:) with FileChatPersistence instead")
    public func load(from url: URL) throws {
        // This is a synchronous method, so we can't easily convert to async
        // Just maintain the old implementation for backward compatibility
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        messages = try decoder.decode([ChatMessage].self, from: data)
        status = .ready
    }
    
    // MARK: - Message Management
    
    /// Remove a message by ID
    /// - Parameter id: The ID of the message to remove
    public func removeMessage(id: String) {
        messages.removeAll { $0.id == id }
    }
    
    /// Edit a message
    /// - Parameters:
    ///   - id: The ID of the message to edit
    ///   - newContent: The new content for the message
    public func editMessage(id: String, newContent: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].content = newContent
        }
    }
    
    /// Get the last user message
    public var lastUserMessage: ChatMessage? {
        messages.last { $0.role == .user }
    }
    
    /// Get the last assistant message
    public var lastAssistantMessage: ChatMessage? {
        messages.last { $0.role == .assistant }
    }
    
    // MARK: - Export
    
    /// Export chat as markdown
    public func exportAsMarkdown() -> String {
        var markdown = "# Chat Export\n\n"
        markdown += "Generated on: \(Date().formatted())\n\n"
        
        for message in messages {
            markdown += "## \(message.role == .user ? "User" : "Assistant")\n"
            markdown += "_\(message.timestamp.formatted())_\n\n"
            markdown += "\(message.content)\n\n"
            
            if !message.toolCalls.isEmpty {
                markdown += "**Tool Calls:**\n"
                for toolCall in message.toolCalls {
                    markdown += "- `\(toolCall.function.name)`\n"
                }
                markdown += "\n"
            }
        }
        
        return markdown
    }
}

// MARK: - Chat Attachment

/// Represents an attachment that can be sent with a message
@available(iOS 16.0, macOS 13.0, *)
public enum ChatAttachment: Sendable {
    /// A file attachment
    case file(FileContent)
    /// An image attachment
    case image(ImageContent)
    /// Raw data attachment
    case data(Data, mimeType: String, filename: String?)
}

// MARK: - Attachment Management

@available(iOS 16.0, macOS 13.0, *)
extension AIChat {
    /// Get attachments for a specific message
    public func attachments(for message: ChatMessage) -> [ChatAttachment] {
        return messageAttachments[message.id] ?? []
    }
    
    /// Get attachments for a message by ID
    public func attachments(for messageId: String) -> [ChatAttachment] {
        return messageAttachments[messageId] ?? []
    }
}

// MARK: - Codable Conformance

@available(iOS 16.0, macOS 13.0, *)
extension ChatMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case id, role, content, toolCalls, timestamp, orderedContent
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Try to decode orderedContent first (new format)
        if let decodedOrderedContent = try? container.decode([MessageContent].self, forKey: .orderedContent) {
            // New format with orderedContent preserved
            self.orderedContent = decodedOrderedContent
        } else {
            // Fallback to legacy format for backward compatibility
            let contentString = try container.decode(String.self, forKey: .content)
            let toolCallsArray = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls) ?? []
            
            var orderedContent: [MessageContent] = []
            if !contentString.isEmpty {
                orderedContent.append(.text(contentString))
            }
            for toolCall in toolCallsArray {
                orderedContent.append(.toolCall(toolCall))
            }
            self.orderedContent = orderedContent
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(timestamp, forKey: .timestamp)
        
        // Encode both legacy format (for backward compatibility) and new format
        try container.encode(content, forKey: .content)
        try container.encode(toolCalls, forKey: .toolCalls)
        
        // Encode the full orderedContent array
        try container.encode(orderedContent, forKey: .orderedContent)
    }
}

// MARK: - SwiftUI Helpers

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public extension View {
    /// Automatically save and load chat state using the provided persistence
    /// - Parameters:
    ///   - chat: The AIChat instance to persist
    ///   - persistence: The persistence provider to use
    ///   - chatId: Unique identifier for this chat session
    func chatAutosave(
        _ chat: AIChat,
        using persistence: ChatPersistence,
        chatId: String
    ) -> some View {
        self
            .task {
                // Load on appear
                try? await chat.load(using: persistence, chatId: chatId)
            }
            .onDisappear {
                // Save on disappear
                Task {
                    try? await chat.save(using: persistence, chatId: chatId)
                }
            }
    }
    
    /// Legacy autosave using UserDefaults (deprecated)
    @available(*, deprecated, message: "Use chatAutosave(_:using:chatId:) with a ChatPersistence implementation instead")
    func chatAutosave(_ chat: AIChat, key: String = "AIChat.messages") -> some View {
        chatAutosave(chat, using: UserDefaultsChatPersistence(), chatId: key)
    }
}
#endif