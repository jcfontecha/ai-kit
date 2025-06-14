import Foundation

// MARK: - Text Generation

/// Request for text generation
public struct TextGenerationRequest: Sendable {
    public let messages: [CoreMessage]
    public let tools: [AITool]?
    public let toolChoice: ToolChoice?
    public let system: String?
    public let maxSteps: Int?
    
    public init(
        messages: [CoreMessage],
        tools: [AITool]? = nil,
        toolChoice: ToolChoice? = nil,
        system: String? = nil,
        maxSteps: Int? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.system = system
        self.maxSteps = maxSteps
    }
}

/// Response from text generation
public struct TextGenerationResponse: Sendable {
    public let text: String
    public let finishReason: FinishReason
    public let usage: TokenUsage
    public let messages: [CoreMessage]
    public let steps: [GenerationStep]?
    public let responseId: String?
    public let modelId: String?
    public let timestamp: Date
    public let warnings: [String]?
    public let responseHeaders: [String: String]?
    
    public init(
        text: String,
        finishReason: FinishReason,
        usage: TokenUsage,
        messages: [CoreMessage],
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

// MARK: - Object Generation

/// Request for structured object generation
public struct ObjectGenerationRequest<T: Codable & Sendable>: Sendable {
    public let messages: [CoreMessage]
    public let schema: JSONSchema
    public let schemaName: String?
    public let schemaDescription: String?
    public let mode: ObjectGenerationMode
    public let system: String?
    public let tools: [AITool]?
    public let toolChoice: ToolChoice?
    public let maxSteps: Int?
    
    public init(
        messages: [CoreMessage],
        schema: JSONSchema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        mode: ObjectGenerationMode = .json,
        system: String? = nil,
        tools: [AITool]? = nil,
        toolChoice: ToolChoice? = nil,
        maxSteps: Int? = nil
    ) {
        self.messages = messages
        self.schema = schema
        self.schemaName = schemaName
        self.schemaDescription = schemaDescription
        self.mode = mode
        self.system = system
        self.tools = tools
        self.toolChoice = toolChoice
        self.maxSteps = maxSteps
    }
}

/// Response from object generation
public struct ObjectGenerationResponse<T: Codable & Sendable>: Sendable {
    public let object: T
    public let finishReason: FinishReason
    public let usage: TokenUsage
    public let messages: [CoreMessage]
    public let steps: [GenerationStep]?
    public let responseId: String?
    public let modelId: String?
    public let timestamp: Date
    public let warnings: [String]?
    public let responseHeaders: [String: String]?
    
    public init(
        object: T,
        finishReason: FinishReason,
        usage: TokenUsage,
        messages: [CoreMessage],
        steps: [GenerationStep]? = nil,
        responseId: String? = nil,
        modelId: String? = nil,
        timestamp: Date = Date(),
        warnings: [String]? = nil,
        responseHeaders: [String: String]? = nil
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
    }
}

// MARK: - Embedding

/// Request for embedding generation
public struct EmbeddingRequest: Sendable {
    public let value: EmbeddingInput
    public let modelId: String?
    public let dimensions: Int?
    
    public init(
        value: EmbeddingInput,
        modelId: String? = nil,
        dimensions: Int? = nil
    ) {
        self.value = value
        self.modelId = modelId
        self.dimensions = dimensions
    }
}

/// Response from embedding generation
public struct EmbeddingResponse: Sendable {
    public let embedding: [Float]
    public let usage: TokenUsage
    public let responseId: String?
    public let modelId: String?
    public let timestamp: Date
    
    public init(
        embedding: [Float],
        usage: TokenUsage,
        responseId: String? = nil,
        modelId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.embedding = embedding
        self.usage = usage
        self.responseId = responseId
        self.modelId = modelId
        self.timestamp = timestamp
    }
}

/// Request for batch embedding generation
public struct BatchEmbeddingRequest: Sendable {
    public let values: [EmbeddingInput]
    public let modelId: String?
    public let dimensions: Int?
    
    public init(
        values: [EmbeddingInput],
        modelId: String? = nil,
        dimensions: Int? = nil
    ) {
        self.values = values
        self.modelId = modelId
        self.dimensions = dimensions
    }
}

/// Response from batch embedding generation
public struct BatchEmbeddingResponse: Sendable {
    public let embeddings: [[Float]]
    public let usage: TokenUsage
    public let responseId: String?
    public let modelId: String?
    public let timestamp: Date
    
    public init(
        embeddings: [[Float]],
        usage: TokenUsage,
        responseId: String? = nil,
        modelId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.embeddings = embeddings
        self.usage = usage
        self.responseId = responseId
        self.modelId = modelId
        self.timestamp = timestamp
    }
}

// MARK: - Supporting Types

/// Possible finish reasons for generation
public enum FinishReason: String, Codable, Sendable {
    case stop
    case length
    case toolCalls = "tool-calls"
    case contentFilter = "content-filter"
    case cancel
    case error
    case other
    case unknown
}

/// Token usage information
public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    
    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

/// Generation step information for multi-step processes
public struct GenerationStep: Sendable {
    public let stepType: StepType
    public let stepId: String
    public let timestamp: Date
    public let usage: TokenUsage?
    public let messages: [CoreMessage]?
    public let toolCalls: [ToolCall]?
    public let toolResults: [ToolResult]?
    
    public init(
        stepType: StepType,
        stepId: String,
        timestamp: Date = Date(),
        usage: TokenUsage? = nil,
        messages: [CoreMessage]? = nil,
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil
    ) {
        self.stepType = stepType
        self.stepId = stepId
        self.timestamp = timestamp
        self.usage = usage
        self.messages = messages
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }
}

/// Types of generation steps
public enum StepType: String, Codable, Sendable {
    case initial
    case `continue`
    case toolCall = "tool-call"
    case toolResult = "tool-result"
}

/// Object generation modes
public enum ObjectGenerationMode: String, Codable, Sendable {
    case json
    case tool
    case grammar
}

/// Embedding input types
public enum EmbeddingInput: Sendable {
    case text(String)
    case tokens([Int])
    
    public var textValue: String? {
        if case .text(let value) = self {
            return value
        }
        return nil
    }
    
    public var tokensValue: [Int]? {
        if case .tokens(let value) = self {
            return value
        }
        return nil
    }
}