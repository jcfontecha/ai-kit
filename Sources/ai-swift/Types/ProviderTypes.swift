import Foundation

// MARK: - Provider Request/Response Types

/// Provider-specific types for the translation layer between AI SDK and provider APIs.
///
/// These types represent the standardized format used for communication between
/// the `AIClient` framework and `AIProvider` implementations. They serve as an
/// intermediate representation that providers can easily transform to their
/// specific API formats.

// MARK: - Provider Mode

/// Provider modes map to specific API formatting
public enum ProviderMode: Sendable {
    case regular(tools: [Tool]?, toolChoice: ToolChoice?)
    case objectJSON(schema: JSONSchema, name: String?, description: String?)
    case objectTool(tool: Tool) // Tool with schema as parameters
}

// MARK: - ProviderRequest

/// Standardized request format for provider translation layer.
///
/// `ProviderRequest` contains all the information needed by providers to make
/// API calls to their respective AI services. The provider is responsible for
/// transforming this standard format into their API-specific format.
///
/// ## Usage in Architecture
/// ```
/// AIClient → creates → ProviderRequest → provider transforms → API call
/// ```
///
/// ## Example Usage
/// ```swift
/// let request = ProviderRequest(
///     modelId: "gpt-4",
///     messages: [Message.user("Hello")],
///     configuration: ModelConfiguration().temperature(0.8),
///     tools: [weatherTool, calculatorTool]
/// )
/// let response = try await provider.generateTextRaw(request)
/// ```
public struct ProviderRequest: Sendable {
    
    // MARK: - Properties
    
    /// The model identifier to use for generation.
    ///
    /// This should match the model ID that was used to create the `LanguageModel`.
    /// Providers are responsible for validating that this model ID is supported.
    public let modelId: String
    
    /// The conversation messages to process.
    ///
    /// These messages follow the standard `Message` format and need to be
    /// transformed by the provider into their API's message format.
    public let messages: [Message]
    
    /// The model configuration parameters.
    ///
    /// Providers should extract the parameters they support and map them
    /// to their API's parameter names and formats.
    public let configuration: ModelConfiguration
    
    /// Optional tools available for the model to call.
    ///
    /// If provided, the provider should transform these into their API's
    /// tool/function calling format. If the provider doesn't support tools,
    /// this should be ignored.
    public let tools: [Tool]?
    
    /// Optional system message for the conversation.
    ///
    /// Some providers handle system messages separately from the main message
    /// array. Providers should use this field or incorporate it into the messages
    /// array as appropriate for their API.
    public let system: String?
    
    /// Maximum number of steps for multi-step tool execution.
    ///
    /// This controls how many tool call rounds are allowed before stopping.
    /// Providers that support tool calling should respect this limit.
    public let maxSteps: Int?
    
    /// Mode parameter tells provider how to format the request
    public let mode: ProviderMode
    
    /// Unique identifier for this request.
    ///
    /// Can be used for logging, debugging, and correlation across middleware
    /// and provider layers.
    public let requestId: String
    
    /// Timestamp when this request was created.
    public let timestamp: Date
    
    // MARK: - Initialization
    
    /// Creates a new provider request with the specified parameters.
    ///
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - messages: The conversation messages
    ///   - configuration: The model configuration
    ///   - tools: Optional tools for function calling
    ///   - system: Optional system message
    ///   - maxSteps: Maximum steps for tool execution
    ///   - mode: How the provider should format the request
    ///   - requestId: Unique request identifier (auto-generated if not provided)
    ///   - timestamp: Request timestamp (current time if not provided)
    public init(
        modelId: String,
        messages: [Message],
        configuration: ModelConfiguration,
        tools: [Tool]? = nil,
        system: String? = nil,
        maxSteps: Int? = nil,
        mode: ProviderMode = .regular(tools: nil, toolChoice: nil),
        requestId: String = UUID().uuidString,
        timestamp: Date = Date()
    ) {
        self.modelId = modelId
        self.messages = messages
        self.configuration = configuration
        self.tools = tools
        self.system = system
        self.maxSteps = maxSteps
        self.mode = mode
        self.requestId = requestId
        self.timestamp = timestamp
    }
}

// MARK: - ProviderResponse

/// Standardized response format from provider translation layer.
///
/// `ProviderResponse` represents the result of a provider's API call in a
/// standardized format. The `AIClient` framework uses this to create the
/// final typed responses for users.
///
/// ## Usage in Architecture
/// ```
/// API response → provider transforms → ProviderResponse → AIClient processes → TextResponse
/// ```
///
/// ## Example Usage
/// ```swift
/// // Provider implementation
/// func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
///     let apiResponse = try await makeAPICall(request)
///     return ProviderResponse(
///         content: apiResponse.text,
///         usage: Usage(promptTokens: apiResponse.usage.prompt, ...),
///         finishReason: .stop
///     )
/// }
/// ```
public struct ProviderResponse: Sendable {
    
    // MARK: - Properties
    
    /// The generated text content.
    ///
    /// This is the main output from the AI model. For text generation,
    /// this contains the generated text. For tool calls, this may be empty
    /// or contain explanatory text.
    public let content: String
    
    /// Tool calls made by the model.
    ///
    /// If the model generated tool calls, they should be included here.
    /// The framework will handle tool execution and follow-up requests.
    public let toolCalls: [ToolCall]?
    
    /// Token usage information for this generation.
    ///
    /// Providers should include accurate token counts for billing and
    /// monitoring purposes.
    public let usage: Usage
    
    /// Reason why generation finished.
    ///
    /// Indicates whether generation completed normally, hit a length limit,
    /// was stopped by a stop sequence, etc.
    public let finishReason: FinishReason
    
    /// Additional model outputs (reasoning, thinking, etc.).
    ///
    /// Some models provide additional outputs like reasoning steps or
    /// internal monologue. These can be included here.
    public let additionalOutputs: [String: String]?
    
    /// Unique identifier for this response.
    ///
    /// Can be used for logging, debugging, and correlation.
    public let responseId: String?
    
    /// Timestamp when this response was created.
    public let timestamp: Date
    
    /// Provider-specific metadata.
    ///
    /// Providers can include additional metadata that might be useful
    /// for debugging or advanced use cases.
    public let providerMetadata: [String: String]?
    
    // MARK: - Initialization
    
    /// Creates a new provider response with the specified data.
    ///
    /// - Parameters:
    ///   - content: The generated text content
    ///   - toolCalls: Optional tool calls made by the model
    ///   - usage: Token usage information
    ///   - finishReason: Reason for generation completion
    ///   - additionalOutputs: Optional additional model outputs
    ///   - responseId: Unique response identifier (auto-generated if not provided)
    ///   - timestamp: Response timestamp (current time if not provided)
    ///   - providerMetadata: Optional provider-specific metadata
    public init(
        content: String,
        toolCalls: [ToolCall]? = nil,
        usage: Usage,
        finishReason: FinishReason,
        additionalOutputs: [String: String]? = nil,
        responseId: String? = UUID().uuidString,
        timestamp: Date = Date(),
        providerMetadata: [String: String]? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
        self.finishReason = finishReason
        self.additionalOutputs = additionalOutputs
        self.responseId = responseId
        self.timestamp = timestamp
        self.providerMetadata = providerMetadata
    }
}

// MARK: - ProviderChunk

/// Standardized streaming chunk format from provider translation layer.
///
/// `ProviderChunk` represents a single chunk in a streaming response from a
/// provider. The `AIClient` framework processes these chunks to create the
/// streaming response for users.
///
/// ## Usage in Architecture
/// ```
/// Streaming API → provider transforms → ProviderChunk → AIClient processes → TextChunk
/// ```
///
/// ## Example Usage
/// ```swift
/// // Provider streaming implementation
/// func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
///     AsyncThrowingStream { continuation in
///         // Process streaming response
///         for chunk in streamingResponse {
///             let providerChunk = ProviderChunk(
///                 delta: chunk.text,
///                 finishReason: chunk.done ? .stop : nil
///             )
///             continuation.yield(providerChunk)
///         }
///     }
/// }
/// ```
public struct ProviderChunk: Sendable {
    
    // MARK: - Properties
    
    /// The incremental text content for this chunk.
    ///
    /// This represents the new text that should be appended to the
    /// existing content. It should not include previously generated text.
    public let delta: String
    
    /// Tool call in progress or completed.
    ///
    /// For streaming tool calls, this may contain partial or complete
    /// tool call information as it becomes available.
    public let toolCall: ToolCall?
    
    /// Updated usage information.
    ///
    /// May be provided incrementally during streaming or only in the
    /// final chunk, depending on the provider's capabilities.
    public let usage: Usage?
    
    /// Finish reason if generation is complete.
    ///
    /// Should only be set in the final chunk of the stream to indicate
    /// why generation ended.
    public let finishReason: FinishReason?
    
    /// Additional outputs for this chunk.
    ///
    /// Some models provide streaming reasoning or other outputs that
    /// can be included here.
    public let additionalOutputs: [String: String]?
    
    /// Unique identifier for this chunk.
    public let chunkId: String
    
    /// Timestamp when this chunk was created.
    public let timestamp: Date
    
    /// Index of this chunk in the stream.
    ///
    /// Can be useful for ordering and debugging streaming issues.
    public let chunkIndex: Int?
    
    // MARK: - Initialization
    
    /// Creates a new provider chunk with the specified data.
    ///
    /// - Parameters:
    ///   - delta: The incremental text content
    ///   - toolCall: Optional tool call information
    ///   - usage: Optional usage information
    ///   - finishReason: Optional finish reason (for final chunk)
    ///   - additionalOutputs: Optional additional outputs
    ///   - chunkId: Unique chunk identifier (auto-generated if not provided)
    ///   - timestamp: Chunk timestamp (current time if not provided)
    ///   - chunkIndex: Optional index of this chunk in the stream
    public init(
        delta: String,
        toolCall: ToolCall? = nil,
        usage: Usage? = nil,
        finishReason: FinishReason? = nil,
        additionalOutputs: [String: String]? = nil,
        chunkId: String = UUID().uuidString,
        timestamp: Date = Date(),
        chunkIndex: Int? = nil
    ) {
        self.delta = delta
        self.toolCall = toolCall
        self.usage = usage
        self.finishReason = finishReason
        self.additionalOutputs = additionalOutputs
        self.chunkId = chunkId
        self.timestamp = timestamp
        self.chunkIndex = chunkIndex
    }
}

// MARK: - Provider Type Extensions

/// Extensions for provider types to support common operations and conversions.
public extension ProviderRequest {
    
    /// Check if this request includes tool calling.
    var hasTools: Bool {
        return tools?.isEmpty == false
    }
    
    /// Get the effective system message.
    ///
    /// Returns the explicit system parameter if set, otherwise extracts
    /// the first system message from the messages array.
    var effectiveSystemMessage: String? {
        if let system = system {
            return system
        }
        
        return messages.first { $0.role == .system }?.content.first?.textValue
    }
    
    /// Get only the non-system messages.
    ///
    /// Useful for providers that handle system messages separately.
    var nonSystemMessages: [Message] {
        return messages.filter { $0.role != .system }
    }
    
    /// Convert to a dictionary for logging or debugging.
    var debugDescription: [String: Any] {
        return [
            "requestId": requestId,
            "modelId": modelId,
            "messageCount": messages.count,
            "hasTools": hasTools,
            "hasSystem": system != nil,
            "maxSteps": maxSteps as Any,
            "timestamp": timestamp
        ]
    }
}

public extension ProviderResponse {
    
    /// Check if this response includes tool calls.
    var hasToolCalls: Bool {
        return toolCalls?.isEmpty == false
    }
    
    /// Check if generation completed successfully.
    var isComplete: Bool {
        return finishReason == .stop
    }
    
    /// Get the total token count.
    var totalTokens: Int {
        return usage.totalTokens
    }
    
    /// Convert to a dictionary for logging or debugging.
    var debugDescription: [String: Any] {
        return [
            "responseId": responseId as Any,
            "contentLength": content.count,
            "hasToolCalls": hasToolCalls,
            "finishReason": finishReason.rawValue,
            "totalTokens": totalTokens,
            "timestamp": timestamp
        ]
    }
}

public extension ProviderChunk {
    
    /// Check if this is a final chunk (has finish reason).
    var isFinal: Bool {
        return finishReason != nil
    }
    
    /// Check if this chunk contains tool call information.
    var hasToolCall: Bool {
        return toolCall != nil
    }
    
    /// Check if this chunk contains only text content.
    var isTextOnly: Bool {
        return !delta.isEmpty && toolCall == nil
    }
    
    /// Convert to a dictionary for logging or debugging.
    var debugDescription: [String: Any] {
        return [
            "chunkId": chunkId,
            "deltaLength": delta.count,
            "hasToolCall": hasToolCall,
            "isFinal": isFinal,
            "chunkIndex": chunkIndex as Any,
            "timestamp": timestamp
        ]
    }
}

// MARK: - Protocol Conformances

extension ProviderRequest: AIRequest {
    // Inherited properties satisfy the protocol requirements
}

extension ProviderResponse: AIResponse {
    // Inherited properties satisfy the protocol requirements
}

extension ProviderChunk: StreamChunk {
    // Inherited properties satisfy the protocol requirements
}