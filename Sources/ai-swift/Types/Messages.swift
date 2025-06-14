import Foundation

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

/// AI tool definition
public struct AITool: Codable, Sendable {
    public let type: ToolType
    public let function: ToolFunction
    
    public init(type: ToolType, function: ToolFunction) {
        self.type = type
        self.function = function
    }
}

/// Tool types
public enum ToolType: String, Codable, Sendable {
    case function
}

/// Tool function definition
public struct ToolFunction: Codable, Sendable {
    public let name: String
    public let description: String?
    public let parameters: JSONSchema
    public let strict: Bool?
    
    public init(
        name: String,
        description: String? = nil,
        parameters: JSONSchema,
        strict: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}

/// Tool choice options
public enum ToolChoice: Codable, Sendable {
    case none
    case auto
    case required
    case specific(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            switch string {
            case "none":
                self = .none
            case "auto":
                self = .auto
            case "required":
                self = .required
            default:
                self = .specific(string)
            }
        } else {
            throw DecodingError.typeMismatch(
                ToolChoice.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid tool choice")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .none:
            try container.encode("none")
        case .auto:
            try container.encode("auto")
        case .required:
            try container.encode("required")
        case .specific(let name):
            try container.encode(name)
        }
    }
}

/// Tool call from AI
public struct ToolCall: Codable, Sendable {
    public let id: String
    public let type: ToolType
    public let function: ToolCallFunction
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        type: ToolType,
        function: ToolCallFunction,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.function = function
        self.timestamp = timestamp
    }
}

/// Tool call function details
public struct ToolCallFunction: Codable, Sendable {
    public let name: String
    public let arguments: String
    
    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

/// Tool execution result
public struct ToolResult: Codable, Sendable {
    public let toolCallId: String
    public let result: ToolResultContent
    public let timestamp: Date
    public let executionTime: TimeInterval?
    public let isError: Bool
    
    public init(
        toolCallId: String,
        result: ToolResultContent,
        timestamp: Date = Date(),
        executionTime: TimeInterval? = nil,
        isError: Bool = false
    ) {
        self.toolCallId = toolCallId
        self.result = result
        self.timestamp = timestamp
        self.executionTime = executionTime
        self.isError = isError
    }
}

/// Tool result content types
public enum ToolResultContent: Codable, Sendable {
    case text(String)
    case json(Data)
    case error(String)
    case image(ImageContent)
    case file(FileContent)
    
    public var textValue: String? {
        if case .text(let value) = self {
            return value
        }
        return nil
    }
    
    public var jsonValue: Data? {
        if case .json(let value) = self {
            return value
        }
        return nil
    }
    
    public var errorValue: String? {
        if case .error(let value) = self {
            return value
        }
        return nil
    }
}

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
}