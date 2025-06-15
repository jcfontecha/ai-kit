import Foundation

// MARK: - New Architecture Response Types

/// Response types for the new AI SDK architecture.
///
/// These response types represent the final, framework-level responses that
/// users receive after `AIClient` processes provider responses and applies
/// middleware transformations.

// MARK: - Text Response

/// Text generation response in the new architecture.
///
/// `TextResponse` is the final response type returned by `AIClient.generateText()`.
/// It contains the generated text along with comprehensive metadata about the
/// generation process.
///
/// ## Usage Example
/// ```swift
/// let client = AIClient()
/// let response = try await client.generateText(model, prompt: "Write a haiku")
/// 
/// print("Generated text: \(response.text)")
/// print("Tokens used: \(response.usage.totalTokens)")
/// print("Finish reason: \(response.finishReason)")
/// ```
public struct TextResponse: Sendable {
    
    // MARK: - Core Content
    
    /// The generated text content.
    ///
    /// This is the primary output from the AI model, containing the generated
    /// text in response to the input messages and prompt.
    public let text: String
    
    /// Reason why text generation finished.
    ///
    /// Indicates whether generation completed naturally, hit a length limit,
    /// was stopped by a stop sequence, etc.
    public let finishReason: FinishReason
    
    /// Token usage information for this generation.
    ///
    /// Provides detailed information about token consumption, including
    /// input tokens, output tokens, and cost information when available.
    public let usage: Usage
    
    /// The complete message conversation including the generated response.
    ///
    /// Contains the original input messages plus the assistant's response,
    /// useful for continuing conversations or understanding context.
    public let messages: [Message]
    
    // MARK: - Generation Metadata
    
    /// Step-by-step information for multi-step generations.
    ///
    /// When tool calling or multi-step reasoning is involved, this contains
    /// detailed information about each step in the generation process.
    public let steps: [GenerationStep]?
    
    /// Unique identifier for this response.
    ///
    /// Can be used for logging, debugging, and correlation across systems.
    public let responseId: String?
    
    /// The model identifier that was used for generation.
    ///
    /// Useful for tracking which specific model version generated the response.
    public let modelId: String?
    
    /// Timestamp when this response was created.
    public let timestamp: Date
    
    /// Any warnings generated during the process.
    ///
    /// Non-fatal issues that occurred during generation, such as content
    /// filtering warnings or parameter adjustments.
    public let warnings: [String]?
    
    /// HTTP response headers from the provider (if available).
    ///
    /// May contain provider-specific metadata, rate limit information, etc.
    public let responseHeaders: [String: String]?
    
    // MARK: - Initialization
    
    /// Creates a new TextResponse with the specified content and metadata.
    ///
    /// - Parameters:
    ///   - text: The generated text content
    ///   - finishReason: Why generation finished
    ///   - usage: Token usage information
    ///   - messages: Complete conversation messages
    ///   - steps: Optional generation steps
    ///   - responseId: Optional response identifier
    ///   - modelId: Optional model identifier
    ///   - timestamp: Response timestamp (current time if not provided)
    ///   - warnings: Optional warnings
    ///   - responseHeaders: Optional HTTP headers
    public init(
        text: String,
        finishReason: FinishReason,
        usage: Usage,
        messages: [Message],
        steps: [GenerationStep]? = nil,
        responseId: String? = nil,
        modelId: String? = nil,
        timestamp: Date = Date(),
        warnings: [String]? = nil,
        responseHeaders: [String: String]? = nil
    ) {
        self.text = text
        self.finishReason = finishReason
        self.usage = usage
        self.messages = messages
        self.steps = steps
        self.responseId = responseId
        self.modelId = modelId
        self.timestamp = timestamp
        self.warnings = warnings
        self.responseHeaders = responseHeaders
    }
}

// MARK: - Object Response

/// Object generation response in the new architecture.
///
/// `ObjectResponse<T>` is the final response type returned by `AIClient.generateObject()`.
/// It contains the generated and validated object along with comprehensive metadata.
///
/// ## Usage Example
/// ```swift
/// struct Recipe: Codable {
///     let name: String
///     let ingredients: [String]
/// }
/// 
/// let schema = ObjectSchema<Recipe>()
/// let response = try await client.generateObject(model, prompt: "Create a recipe", schema: schema)
/// 
/// let recipe: Recipe = response.object
/// print("Recipe name: \(recipe.name)")
/// ```
public struct ObjectResponse<T: Codable & Sendable>: Sendable {
    
    // MARK: - Core Content
    
    /// The generated and validated object.
    ///
    /// This object has been generated by the AI model and validated against
    /// the provided schema. It is guaranteed to be of type T.
    public let object: T
    
    /// Reason why object generation finished.
    ///
    /// Indicates whether generation completed successfully, hit limits, etc.
    public let finishReason: FinishReason
    
    /// Token usage information for this generation.
    ///
    /// Includes tokens used for the prompt, schema, and generated object.
    public let usage: Usage
    
    /// The complete message conversation including the generated response.
    ///
    /// Contains the original input messages plus the assistant's structured response.
    public let messages: [Message]
    
    // MARK: - Generation Metadata
    
    /// Step-by-step information for multi-step generations.
    ///
    /// Particularly relevant when tool calling is involved in object generation.
    public let steps: [GenerationStep]?
    
    /// Unique identifier for this response.
    public let responseId: String?
    
    /// The model identifier that was used for generation.
    public let modelId: String?
    
    /// Timestamp when this response was created.
    public let timestamp: Date
    
    /// Any warnings generated during the process.
    ///
    /// May include schema validation warnings or generation issues.
    public let warnings: [String]?
    
    /// HTTP response headers from the provider (if available).
    public let responseHeaders: [String: String]?
    
    // MARK: - Object-Specific Metadata
    
    /// The raw JSON string that was parsed into the object.
    ///
    /// Useful for debugging schema issues or understanding what the model
    /// actually generated before validation.
    public let rawJSON: String?
    
    /// Schema validation result.
    ///
    /// Contains information about how well the generated object matched
    /// the provided schema.
    public let validationResult: ObjectValidationResult?
    
    // MARK: - Initialization
    
    /// Creates a new ObjectResponse with the specified object and metadata.
    ///
    /// - Parameters:
    ///   - object: The generated and validated object
    ///   - finishReason: Why generation finished
    ///   - usage: Token usage information
    ///   - messages: Complete conversation messages
    ///   - steps: Optional generation steps
    ///   - responseId: Optional response identifier
    ///   - modelId: Optional model identifier
    ///   - timestamp: Response timestamp (current time if not provided)
    ///   - warnings: Optional warnings
    ///   - responseHeaders: Optional HTTP headers
    ///   - rawJSON: Optional raw JSON string
    ///   - validationResult: Optional validation result
    public init(
        object: T,
        finishReason: FinishReason,
        usage: Usage,
        messages: [Message],
        steps: [GenerationStep]? = nil,
        responseId: String? = nil,
        modelId: String? = nil,
        timestamp: Date = Date(),
        warnings: [String]? = nil,
        responseHeaders: [String: String]? = nil,
        rawJSON: String? = nil,
        validationResult: ObjectValidationResult? = nil
    ) {
        self.object = object
        self.finishReason = finishReason
        self.usage = usage
        self.messages = messages
        self.steps = steps
        self.responseId = responseId
        self.modelId = modelId
        self.timestamp = timestamp
        self.warnings = warnings
        self.responseHeaders = responseHeaders
        self.rawJSON = rawJSON
        self.validationResult = validationResult
    }
}

// MARK: - Supporting Types

/// Possible finish reasons for AI generation.
///
/// These reasons indicate why the AI model stopped generating content.
public enum FinishReason: String, Codable, Sendable {
    
    /// Generation completed naturally.
    case stop
    
    /// Generation stopped due to maximum length reached.
    case length
    
    /// Generation stopped to make tool calls.
    case toolCalls = "tool-calls"
    
    /// Generation stopped due to content filtering.
    case contentFilter = "content-filter"
    
    /// Generation was cancelled by the user.
    case cancel
    
    /// Generation stopped due to an error.
    case error
    
    /// Generation stopped for another reason.
    case other
    
    /// Unknown finish reason.
    case unknown
}

/// Information about a single step in the generation process.
///
/// Used for multi-step generations involving tool calls or reasoning chains.
public struct GenerationStep: Sendable {
    
    /// The type of step.
    public let stepType: StepType
    
    /// Unique identifier for this step.
    public let stepId: String
    
    /// Timestamp when this step occurred.
    public let timestamp: Date
    
    /// Token usage for this specific step.
    public let usage: Usage?
    
    /// Messages involved in this step.
    public let messages: [Message]?
    
    /// Tool calls made in this step.
    public let toolCalls: [ToolCall]?
    
    /// Tool results received in this step.
    public let toolResults: [ToolResult]?
    
    /// Additional metadata for this step.
    public let metadata: [String: String]?
    
    public init(
        stepType: StepType,
        stepId: String = UUID().uuidString,
        timestamp: Date = Date(),
        usage: Usage? = nil,
        messages: [Message]? = nil,
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.stepType = stepType
        self.stepId = stepId
        self.timestamp = timestamp
        self.usage = usage
        self.messages = messages
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.metadata = metadata
    }
}

/// Types of generation steps.
public enum StepType: String, Codable, Sendable {
    
    /// Initial generation step.
    case initial
    
    /// Continuation of generation.
    case `continue`
    
    /// Tool call step.
    case toolCall = "tool-call"
    
    /// Tool result processing step.
    case toolResult = "tool-result"
    
    /// Reasoning or thinking step.
    case reasoning
    
    /// Validation step.
    case validation
}

// MARK: - Response Extensions

public extension TextResponse {
    
    /// Check if this response involved tool calls.
    var hasToolCalls: Bool {
        return steps?.contains { !($0.toolCalls?.isEmpty ?? true) } ?? false
    }
    
    /// Get all tool calls made during text generation.
    var toolCalls: [ToolCall] {
        return steps?.flatMap { $0.toolCalls ?? [] } ?? []
    }
    
    /// Get the total number of steps in the generation process.
    var stepCount: Int {
        return steps?.count ?? 1
    }
    
    /// Check if generation completed successfully.
    var isSuccess: Bool {
        return finishReason == .stop
    }
    
    /// Get the assistant's message from the conversation.
    var assistantMessage: Message? {
        return messages.last { $0.role == .assistant }
    }
    
    /// Get a summary of this response for logging.
    var summary: String {
        return "TextResponse(length: \(text.count), tokens: \(usage.totalTokens), reason: \(finishReason))"
    }
}

public extension ObjectResponse {
    
    /// Check if this response involved tool calls.
    var hasToolCalls: Bool {
        return steps?.contains { !($0.toolCalls?.isEmpty ?? true) } ?? false
    }
    
    /// Get the total number of steps in the generation process.
    var stepCount: Int {
        return steps?.count ?? 1
    }
    
    /// Check if generation completed successfully.
    var isSuccess: Bool {
        return finishReason == .stop
    }
    
    /// Check if the object passed validation.
    var passedValidation: Bool {
        return validationResult?.isValid ?? true
    }
    
    /// Get a summary of this response for logging.
    var summary: String {
        return "ObjectResponse(type: \(T.self), tokens: \(usage.totalTokens), reason: \(finishReason))"
    }
}

// MARK: - Protocol Conformances

extension TextResponse: AIResponse {
    // Inherited properties satisfy the protocol requirements
}

extension ObjectResponse: AIResponse {
    // Inherited properties satisfy the protocol requirements
}