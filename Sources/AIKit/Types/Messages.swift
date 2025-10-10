import Foundation

// MARK: - Message Types

/// Simplified message type for the new architecture
public typealias Message = CoreMessage


// MARK: - Core Message

/// Core message structure for AI interactions
public struct CoreMessage: Codable, Sendable {
    public let role: MessageRole
    public let content: [MessageContent]
    public let name: String?
    public let id: String
    public let timestamp: Date
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    
    public init(
        role: MessageRole,
        content: [MessageContent],
        name: String? = nil,
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.id = id
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

// MARK: - Message Role

/// Roles for different message types
public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Message Content

/// Content types for messages
public enum MessageContent: Codable, Sendable {
    case text(String)
    case image(ImageContent)
    case file(FileContent)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case reasoning(ReasoningContent)
    case redactedReasoning(ReasoningRedaction)
    case reasoningSignature(ReasoningSignature)
    case annotation(MessageAnnotation)
    
    public var textValue: String? {
        if case .text(let value) = self {
            return value
        }
        return nil
    }
    
    public var imageValue: ImageContent? {
        if case .image(let value) = self {
            return value
        }
        return nil
    }
    
    public var fileValue: FileContent? {
        if case .file(let value) = self {
            return value
        }
        return nil
    }
    
    public var toolCallValue: ToolCall? {
        if case .toolCall(let value) = self {
            return value
        }
        return nil
    }
    
    public var toolResultValue: ToolResult? {
        if case .toolResult(let value) = self {
            return value
        }
        return nil
    }
    
    public var reasoningValue: ReasoningContent? {
        if case .reasoning(let value) = self {
            return value
        }
        return nil
    }
    
    public var redactedReasoningValue: ReasoningRedaction? {
        if case .redactedReasoning(let value) = self {
            return value
        }
        return nil
    }
    
    public var reasoningSignatureValue: ReasoningSignature? {
        if case .reasoningSignature(let value) = self {
            return value
        }
        return nil
    }
    
    public var annotationValue: MessageAnnotation? {
        if case .annotation(let value) = self {
            return value
        }
        return nil
    }
}

// MARK: - Reasoning & Annotation Content

/// Reasoning trace emitted during streaming.
public struct ReasoningContent: Codable, Sendable, CustomStringConvertible {
    public let fragments: [String]
    public let rawJSON: String?
    
    public init(fragments: [String], rawJSON: String? = nil) {
        self.fragments = fragments
        self.rawJSON = rawJSON
    }
    
    public var description: String {
        "ReasoningContent(fragments: \(fragments))"
    }
}

/// Redacted reasoning payload emitted during streaming.
public struct ReasoningRedaction: Codable, Sendable, CustomStringConvertible {
    public let payload: [String: String]
    public let rawJSON: String?
    
    public init(payload: [String: String], rawJSON: String? = nil) {
        self.payload = payload
        self.rawJSON = rawJSON
    }
    
    public var description: String {
        "ReasoningRedaction(payload: \(payload))"
    }
}

/// Signature information accompanying reasoning traces.
public struct ReasoningSignature: Codable, Sendable, CustomStringConvertible {
    public let payload: [String: String]
    public let rawJSON: String?
    
    public init(payload: [String: String], rawJSON: String? = nil) {
        self.payload = payload
        self.rawJSON = rawJSON
    }
    
    public var signature: String? {
        payload["signature"]
    }
    
    public var description: String {
        "ReasoningSignature(payload: \(payload))"
    }
}

/// Message annotations emitted during streaming.
public struct MessageAnnotation: Codable, Sendable, CustomStringConvertible {
    public let values: [String]
    public let rawJSON: String?
    
    public init(values: [String], rawJSON: String? = nil) {
        self.values = values
        self.rawJSON = rawJSON
    }
    
    public var description: String {
        "MessageAnnotation(values: \(values))"
    }
}

// MARK: - Image Content

/// Image content in messages
public struct ImageContent: Codable, Sendable {
    public let data: Data?
    public let url: URL?
    public let mimeType: String
    public let alt: String?
    public let width: Int?
    public let height: Int?
    
    public init(
        data: Data? = nil,
        url: URL? = nil,
        mimeType: String,
        alt: String? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.data = data
        self.url = url
        self.mimeType = mimeType
        self.alt = alt
        self.width = width
        self.height = height
    }
}

// MARK: - File Content

/// File content in messages
public struct FileContent: Codable, Sendable {
    public let data: Data?
    public let url: URL?
    public let mimeType: String
    public let filename: String?
    public let size: Int?
    
    public init(
        data: Data? = nil,
        url: URL? = nil,
        mimeType: String,
        filename: String? = nil,
        size: Int? = nil
    ) {
        self.data = data
        self.url = url
        self.mimeType = mimeType
        self.filename = filename
        self.size = size
    }
}

// MARK: - Tool Types

/// Legacy alias for Tool
public typealias AITool = Tool




// MARK: - Message Convenience Extensions

public extension CoreMessage {
    /// Create a system message
    static func system(_ content: String, id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(role: .system, content: [.text(content)], id: id)
    }
    
    /// Create a user message
    static func user(_ content: String, id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(role: .user, content: [.text(content)], id: id)
    }
    
    /// Create an assistant message
    static func assistant(_ content: String, id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(role: .assistant, content: [.text(content)], id: id)
    }
    
    /// Create a user message with image
    static func user(_ text: String, image: ImageContent, id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(role: .user, content: [.text(text), .image(image)], id: id)
    }
    
    /// Create a user message with file
    static func user(_ text: String, file: FileContent, id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(role: .user, content: [.text(text), .file(file)], id: id)
    }
    
    /// Create a user message with audio file
    static func user(_ text: String, audio: FileContent, id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(role: .user, content: [.text(text), .file(audio)], id: id)
    }
    
    /// Create an assistant message with tool calls
    static func assistant(toolCalls: [ToolCall], id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(
            role: .assistant,
            content: toolCalls.map { .toolCall($0) },
            id: id,
            toolCalls: toolCalls
        )
    }
    
    /// Create a tool result message
    static func tool(result: ToolResult, id: String = UUID().uuidString) -> CoreMessage {
        CoreMessage(
            role: .tool,
            content: [.toolResult(result)],
            id: id,
            toolCallId: result.toolCallId
        )
    }
}

public extension ImageContent {
    /// Create image content from data
    static func data(_ data: Data, mimeType: String = "image/jpeg") -> ImageContent {
        ImageContent(data: data, mimeType: mimeType)
    }
    
    /// Create image content from URL
    static func url(_ url: URL, mimeType: String = "image/jpeg") -> ImageContent {
        ImageContent(url: url, mimeType: mimeType)
    }
}

public extension FileContent {
    /// Create file content from data
    static func data(_ data: Data, mimeType: String, filename: String? = nil) -> FileContent {
        FileContent(data: data, mimeType: mimeType, filename: filename)
    }
    
    /// Create file content from URL
    static func url(_ url: URL, mimeType: String, filename: String? = nil) -> FileContent {
        FileContent(url: url, mimeType: mimeType, filename: filename)
    }
    
    /// Create audio content from MP3 data
    static func mp3(_ data: Data, filename: String? = nil) -> FileContent {
        FileContent(data: data, mimeType: "audio/mpeg", filename: filename)
    }
    
    /// Create audio content from WAV data
    static func wav(_ data: Data, filename: String? = nil) -> FileContent {
        FileContent(data: data, mimeType: "audio/wav", filename: filename)
    }
    
    /// Create audio content from MP3 URL
    static func mp3URL(_ url: URL, filename: String? = nil) -> FileContent {
        FileContent(url: url, mimeType: "audio/mpeg", filename: filename)
    }
    
    /// Create audio content from WAV URL
    static func wavURL(_ url: URL, filename: String? = nil) -> FileContent {
        FileContent(url: url, mimeType: "audio/wav", filename: filename)
    }
}
