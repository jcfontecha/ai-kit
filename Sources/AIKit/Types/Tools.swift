import Foundation

// MARK: - Tool System Types

/// Type alias for tool execution functions.
///
/// A tool executor is a function that takes a ToolCall and asynchronously
/// executes it, returning a ToolResult. This allows custom tool implementations
/// to be provided by the user.
///
/// ## Usage Example
/// ```swift
/// let executor: ToolExecutor = { toolCall in
///     switch toolCall.function.name {
///     case "get_weather":
///         let location = try parseLocation(from: toolCall.function.arguments)
///         let weather = try await weatherService.getWeather(for: location)
///         return ToolResult.success(toolCallId: toolCall.id, text: weather)
///     default:
///         throw AIGenerationError.noSuchTool(toolName: toolCall.function.name, availableTools: ["get_weather"])
///     }
/// }
/// ```
public typealias ToolExecutor = (ToolCall) async throws -> ToolResult

/// Tool and function calling system for AI models.
///
/// The tool system enables AI models to call external functions and tools
/// during generation, providing access to real-time data, calculations,
/// and external services. This follows the function calling patterns
/// established by OpenAI and adopted by other providers.

// MARK: - Tool Definition

/// A tool that can be called by an AI model.
///
/// Tools enable AI models to perform actions beyond text generation, such as:
/// - Fetching real-time data (weather, stock prices, news)
/// - Performing calculations
/// - Interacting with external APIs
/// - Searching databases
/// - Executing code
///
/// ## Usage Examples
///
/// ### Simple Tool Definition
/// ```swift
/// let weatherTool = Tool(
///     type: .function,
///     function: ToolFunction(
///         name: "get_weather",
///         description: "Get current weather for a location",
///         parameters: .object(properties: [
///             "location": .string(description: "The city and state, e.g. San Francisco, CA")
///         ], required: ["location"])
///     )
/// )
/// ```
///
/// ### Using Builder Pattern
/// ```swift
/// let calculatorTool = Tool.function(
///     name: "calculate",
///     description: "Perform mathematical calculations",
///     parameters: .object(properties: [
///         "expression": .string(description: "Mathematical expression to evaluate")
///     ])
/// )
/// ```
public struct Tool: Codable, Sendable {
    
    // MARK: - Properties
    
    /// The type of tool (currently only .function is supported by most providers).
    public let type: ToolType
    
    /// Function definition for this tool.
    public let function: ToolFunction
    
    /// Unique identifier for this tool instance.
    public let id: String
    
    /// Whether this tool should be enabled by default.
    public let enabled: Bool
    
    /// Additional metadata for this tool.
    public let metadata: [String: String]?
    
    // MARK: - Initialization
    
    /// Creates a new tool with the specified function definition.
    ///
    /// - Parameters:
    ///   - type: The type of tool (defaults to .function)
    ///   - function: The function definition
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - enabled: Whether the tool is enabled (defaults to true)
    ///   - metadata: Optional additional metadata
    public init(
        type: ToolType = .function,
        function: ToolFunction,
        id: String = UUID().uuidString,
        enabled: Bool = true,
        metadata: [String: String]? = nil
    ) {
        self.type = type
        self.function = function
        self.id = id
        self.enabled = enabled
        self.metadata = metadata
    }
}

// MARK: - Tool Type

/// The type of tool available to AI models.
///
/// Currently, most AI providers only support function tools, but this enum
/// is designed to be extensible for future tool types.
public enum ToolType: String, Codable, Sendable {
    
    /// Function tool that can be called with parameters.
    case function = "function"
    
    // Future tool types could include:
    // case browser = "browser"
    // case codeInterpreter = "code_interpreter"
    // case retrieval = "retrieval"
}

// MARK: - Tool Function

/// Definition of a function that can be called by an AI model.
///
/// `ToolFunction` describes the interface of a function, including its name,
/// description, and parameter schema. The AI model uses this information to
/// understand when and how to call the function.
public struct ToolFunction: Codable, Sendable {
    
    // MARK: - Properties
    
    /// The name of the function.
    ///
    /// Should be descriptive and follow naming conventions (e.g., "get_weather",
    /// "calculate_distance", "search_database"). The name is used by the AI model
    /// to identify which function to call.
    public let name: String
    
    /// Human-readable description of what this function does.
    ///
    /// This description helps the AI model understand when to use this function.
    /// Be specific about the function's purpose, inputs, and outputs.
    public let description: String?
    
    /// JSON schema describing the function's parameters.
    ///
    /// This schema defines the structure and types of parameters the function accepts.
    /// The AI model uses this to generate valid function calls.
    public let parameters: JSONSchema
    
    /// Whether the function parameters must strictly match the schema.
    ///
    /// When true, the AI provider will enforce strict validation of parameters
    /// against the schema. When false or nil, some flexibility may be allowed.
    public let strict: Bool?
    
    /// Examples of how to call this function.
    ///
    /// Providing examples can help the AI model understand proper usage patterns.
    public let examples: [ToolExample]?
    
    // MARK: - Initialization
    
    /// Creates a new tool function definition.
    ///
    /// - Parameters:
    ///   - name: The function name
    ///   - description: Description of what the function does
    ///   - parameters: JSON schema for parameters
    ///   - strict: Whether to enforce strict parameter validation
    ///   - examples: Optional usage examples
    public init(
        name: String,
        description: String? = nil,
        parameters: JSONSchema,
        strict: Bool? = nil,
        examples: [ToolExample]? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
        self.examples = examples
    }
}

// MARK: - Tool Example

/// An example of how to call a tool function.
///
/// Examples help AI models understand proper usage patterns and can improve
/// the quality of function calls.
public struct ToolExample: Codable, Sendable {
    
    /// Description of what this example demonstrates.
    public let description: String
    
    /// Example input parameters.
    public let input: [String: JSONSchemaValue]
    
    /// Expected output or result description.
    public let output: String?
    
    public init(description: String, input: [String: JSONSchemaValue], output: String? = nil) {
        self.description = description
        self.input = input
        self.output = output
    }
}

// MARK: - Tool Choice

/// Controls which tools the AI model can use during generation.
///
/// `ToolChoice` allows fine-grained control over tool usage, from disabling
/// all tools to requiring specific tool calls.
public enum ToolChoice: Codable, Sendable {
    
    /// No tools should be called.
    case none
    
    /// The model can choose whether to call tools automatically.
    case auto
    
    /// The model must call at least one tool.
    case required
    
    /// The model must call this specific tool.
    case specific(String)
    
    // MARK: - Codable Implementation
    
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

// MARK: - Tool Call

/// A tool call made by an AI model.
///
/// When an AI model decides to use a tool, it generates a `ToolCall` that
/// specifies which function to call and with what parameters.
public struct ToolCall: Codable, Sendable {
    
    // MARK: - Properties
    
    /// Unique identifier for this tool call.
    public let id: String
    
    /// The type of tool being called.
    public let type: ToolType
    
    /// The function call details.
    public let function: ToolCallFunction
    
    /// Timestamp when this tool call was created.
    public let timestamp: Date
    
    /// Index of this tool call in a sequence (for multiple tool calls).
    public let index: Int?
    
    // MARK: - Initialization
    
    /// Creates a new tool call.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - type: Tool type (defaults to .function)
    ///   - function: Function call details
    ///   - timestamp: Call timestamp (current time if not provided)
    ///   - index: Index in a sequence of tool calls
    public init(
        id: String = UUID().uuidString,
        type: ToolType = .function,
        function: ToolCallFunction,
        timestamp: Date = Date(),
        index: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.function = function
        self.timestamp = timestamp
        self.index = index
    }
}

// MARK: - Tool Call Function

/// Function call details within a tool call.
///
/// Contains the specific function name and arguments that the AI model
/// wants to execute.
public struct ToolCallFunction: Codable, Sendable {
    
    /// The name of the function to call.
    public let name: String
    
    /// JSON string containing the function arguments.
    ///
    /// This is typically a JSON object with parameter names as keys
    /// and parameter values as values, serialized to a string.
    public let arguments: String
    
    /// Parsed arguments as a dictionary (convenience property).
    ///
    /// This property attempts to parse the arguments string into a dictionary
    /// for easier access. Returns nil if parsing fails.
    public var parsedArguments: [String: Any]? {
        guard let data = arguments.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    
    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
    
    /// Convenience initializer with dictionary arguments.
    ///
    /// - Parameters:
    ///   - name: Function name
    ///   - arguments: Arguments as a dictionary
    public init(name: String, arguments: [String: Any]) throws {
        self.name = name
        let data = try JSONSerialization.data(withJSONObject: arguments)
        self.arguments = String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Tool Result

/// The result of executing a tool call.
///
/// After a tool is called by the AI model, the execution result is wrapped
/// in a `ToolResult` and can be sent back to the model for further processing.
public struct ToolResult: Codable, Sendable {
    
    // MARK: - Properties
    
    /// The ID of the tool call this result corresponds to.
    public let toolCallId: String
    
    /// The result content from the tool execution.
    public let result: ToolResultContent
    
    /// Timestamp when this result was created.
    public let timestamp: Date
    
    /// Time taken to execute the tool (in seconds).
    public let executionTime: TimeInterval?
    
    /// Whether this result represents an error.
    public let isError: Bool
    
    /// Additional metadata about the execution.
    public let metadata: [String: String]?
    
    // MARK: - Initialization
    
    /// Creates a new tool result.
    ///
    /// - Parameters:
    ///   - toolCallId: ID of the corresponding tool call
    ///   - result: The result content
    ///   - timestamp: Result timestamp (current time if not provided)
    ///   - executionTime: Time taken to execute
    ///   - isError: Whether this is an error result
    ///   - metadata: Additional metadata
    public init(
        toolCallId: String,
        result: ToolResultContent,
        timestamp: Date = Date(),
        executionTime: TimeInterval? = nil,
        isError: Bool = false,
        metadata: [String: String]? = nil
    ) {
        self.toolCallId = toolCallId
        self.result = result
        self.timestamp = timestamp
        self.executionTime = executionTime
        self.isError = isError
        self.metadata = metadata
    }
}

// MARK: - Tool Result Content

/// The content of a tool execution result.
///
/// Tool results can contain different types of content depending on what
/// the tool returns. This enum supports the most common result types.
public enum ToolResultContent: Codable, Sendable {
    
    /// Plain text result.
    case text(String)
    
    /// JSON data result.
    case json(Data)
    
    /// Error message.
    case error(String)
    
    /// Image result.
    case image(ImageContent)
    
    /// File result.
    case file(FileContent)
    
    /// Binary data result.
    case data(Data, mimeType: String)
    
    // MARK: - Convenience Accessors
    
    /// Get the text value if this is a text result.
    public var textValue: String? {
        if case .text(let value) = self {
            return value
        }
        return nil
    }
    
    /// Get the JSON data if this is a JSON result.
    public var jsonValue: Data? {
        if case .json(let value) = self {
            return value
        }
        return nil
    }
    
    /// Get the error message if this is an error result.
    public var errorValue: String? {
        if case .error(let value) = self {
            return value
        }
        return nil
    }
    
    /// Get the image content if this is an image result.
    public var imageValue: ImageContent? {
        if case .image(let value) = self {
            return value
        }
        return nil
    }
    
    /// Get the file content if this is a file result.
    public var fileValue: FileContent? {
        if case .file(let value) = self {
            return value
        }
        return nil
    }
    
    /// Check if this result represents an error.
    public var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
    
    // MARK: - Codable Implementation
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case "json":
            let value = try container.decode(Data.self, forKey: .value)
            self = .json(value)
        case "error":
            let value = try container.decode(String.self, forKey: .value)
            self = .error(value)
        case "image":
            let value = try container.decode(ImageContent.self, forKey: .value)
            self = .image(value)
        case "file":
            let value = try container.decode(FileContent.self, forKey: .value)
            self = .file(value)
        case "data":
            let value = try container.decode(Data.self, forKey: .value)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .data(value, mimeType: mimeType)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool result content type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .json(let value):
            try container.encode("json", forKey: .type)
            try container.encode(value, forKey: .value)
        case .error(let value):
            try container.encode("error", forKey: .type)
            try container.encode(value, forKey: .value)
        case .image(let value):
            try container.encode("image", forKey: .type)
            try container.encode(value, forKey: .value)
        case .file(let value):
            try container.encode("file", forKey: .type)
            try container.encode(value, forKey: .value)
        case .data(let value, let mimeType):
            try container.encode("data", forKey: .type)
            try container.encode(value, forKey: .value)
            try container.encode(mimeType, forKey: .mimeType)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case mimeType = "mime_type"
    }
}

// MARK: - Tool Builder Extensions

public extension Tool {
    
    
    /// Create a function tool with a single string parameter.
    ///
    /// - Parameters:
    ///   - name: Function name
    ///   - description: Function description
    ///   - parameterName: Name of the string parameter
    ///   - parameterDescription: Description of the parameter
    /// - Returns: A new Tool instance
    static func stringFunction(
        name: String,
        description: String,
        parameterName: String = "input",
        parameterDescription: String
    ) -> Tool {
        Tool.function(
            name: name,
            description: description,
            parameters: .object(
                properties: [
                    parameterName: .string().withDescription(parameterDescription)
                ],
                required: [parameterName]
            )
        )
    }
}

// MARK: - Tool Result Builder Extensions

public extension ToolResult {
    
    /// Create a successful text result.
    ///
    /// - Parameters:
    ///   - toolCallId: ID of the tool call
    ///   - text: Result text
    ///   - executionTime: Optional execution time
    /// - Returns: A new ToolResult
    static func success(
        toolCallId: String,
        text: String,
        executionTime: TimeInterval? = nil
    ) -> ToolResult {
        ToolResult(
            toolCallId: toolCallId,
            result: .text(text),
            executionTime: executionTime,
            isError: false
        )
    }
    
    /// Create an error result.
    ///
    /// - Parameters:
    ///   - toolCallId: ID of the tool call
    ///   - error: Error message
    ///   - executionTime: Optional execution time
    /// - Returns: A new ToolResult
    static func error(
        toolCallId: String,
        error: String,
        executionTime: TimeInterval? = nil
    ) -> ToolResult {
        ToolResult(
            toolCallId: toolCallId,
            result: .error(error),
            executionTime: executionTime,
            isError: true
        )
    }
    
    /// Create a JSON result.
    ///
    /// - Parameters:
    ///   - toolCallId: ID of the tool call
    ///   - object: Object to encode as JSON
    ///   - executionTime: Optional execution time
    /// - Returns: A new ToolResult
    /// - Throws: JSON encoding errors
    static func json<T: Codable>(
        toolCallId: String,
        object: T,
        executionTime: TimeInterval? = nil
    ) throws -> ToolResult {
        let data = try JSONEncoder().encode(object)
        return ToolResult(
            toolCallId: toolCallId,
            result: .json(data),
            executionTime: executionTime,
            isError: false
        )
    }
}