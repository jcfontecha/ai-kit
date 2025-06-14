import Foundation

// MARK: - Base AI Error

/// Base protocol for all AI-related errors
public protocol AIError: Error, LocalizedError, Sendable {
    /// Error code for programmatic handling
    var code: String { get }
    
    /// User-friendly error message
    var message: String { get }
    
    /// Additional context information
    var context: [String: String] { get }
    
    /// Underlying error if this is a wrapper
    var underlyingError: Error? { get }
    
    /// Whether this error is retryable
    var isRetryable: Bool { get }
    
    /// Request ID associated with this error
    var requestId: String? { get }
}

// MARK: - Core AI Errors

/// Provider-related errors
public enum AIProviderError: AIError {
    case invalidAPIKey(String)
    case invalidConfiguration(String)
    case unsupportedModel(String)
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case quotaExceeded
    case serviceUnavailable
    case timeout
    case networkError(Error)
    case authenticationFailed
    case authorizationFailed
    
    public var code: String {
        switch self {
        case .invalidAPIKey: return "INVALID_API_KEY"
        case .invalidConfiguration: return "INVALID_CONFIGURATION"
        case .unsupportedModel: return "UNSUPPORTED_MODEL"
        case .rateLimitExceeded: return "RATE_LIMIT_EXCEEDED"
        case .quotaExceeded: return "QUOTA_EXCEEDED"
        case .serviceUnavailable: return "SERVICE_UNAVAILABLE"
        case .timeout: return "TIMEOUT"
        case .networkError: return "NETWORK_ERROR"
        case .authenticationFailed: return "AUTHENTICATION_FAILED"
        case .authorizationFailed: return "AUTHORIZATION_FAILED"
        }
    }
    
    public var message: String {
        switch self {
        case .invalidAPIKey(let provider):
            return "Invalid API key for provider: \(provider)"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .unsupportedModel(let model):
            return "Unsupported model: \(model)"
        case .rateLimitExceeded(let retryAfter):
            let retryMessage = retryAfter.map { " Retry after \(Int($0)) seconds." } ?? ""
            return "Rate limit exceeded.\(retryMessage)"
        case .quotaExceeded:
            return "API quota exceeded"
        case .serviceUnavailable:
            return "AI service is currently unavailable"
        case .timeout:
            return "Request timed out"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationFailed:
            return "Authentication failed"
        case .authorizationFailed:
            return "Authorization failed"
        }
    }
    
    public var context: [String: String] {
        switch self {
        case .rateLimitExceeded(let retryAfter):
            return retryAfter.map { ["retryAfter": String($0)] } ?? [:]
        case .networkError(let error):
            return ["underlyingError": error.localizedDescription]
        default:
            return [:]
        }
    }
    
    public var underlyingError: Error? {
        switch self {
        case .networkError(let error):
            return error
        default:
            return nil
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .rateLimitExceeded, .serviceUnavailable, .timeout, .networkError:
            return true
        default:
            return false
        }
    }
    
    public var requestId: String? { nil }
    
    public var errorDescription: String? { message }
}

/// Generation-related errors
public enum AIGenerationError: AIError {
    case invalidPrompt(String)
    case contentFiltered(String)
    case maxTokensExceeded
    case invalidParameters(String)
    case modelOverloaded
    case unexpectedResponse(String)
    case streamingError(Error)
    case toolExecutionFailed(toolName: String, error: Error)
    case schemaValidationFailed([ValidationError])
    case objectParsingFailed(String)
    
    public var code: String {
        switch self {
        case .invalidPrompt: return "INVALID_PROMPT"
        case .contentFiltered: return "CONTENT_FILTERED"
        case .maxTokensExceeded: return "MAX_TOKENS_EXCEEDED"
        case .invalidParameters: return "INVALID_PARAMETERS"
        case .modelOverloaded: return "MODEL_OVERLOADED"
        case .unexpectedResponse: return "UNEXPECTED_RESPONSE"
        case .streamingError: return "STREAMING_ERROR"
        case .toolExecutionFailed: return "TOOL_EXECUTION_FAILED"
        case .schemaValidationFailed: return "SCHEMA_VALIDATION_FAILED"
        case .objectParsingFailed: return "OBJECT_PARSING_FAILED"
        }
    }
    
    public var message: String {
        switch self {
        case .invalidPrompt(let details):
            return "Invalid prompt: \(details)"
        case .contentFiltered(let reason):
            return "Content was filtered: \(reason)"
        case .maxTokensExceeded:
            return "Maximum token limit exceeded"
        case .invalidParameters(let details):
            return "Invalid parameters: \(details)"
        case .modelOverloaded:
            return "Model is currently overloaded"
        case .unexpectedResponse(let details):
            return "Unexpected response format: \(details)"
        case .streamingError(let error):
            return "Streaming error: \(error.localizedDescription)"
        case .toolExecutionFailed(let toolName, let error):
            return "Tool '\(toolName)' execution failed: \(error.localizedDescription)"
        case .schemaValidationFailed(let errors):
            return "Schema validation failed: \(errors.map { $0.message }.joined(separator: ", "))"
        case .objectParsingFailed(let details):
            return "Object parsing failed: \(details)"
        }
    }
    
    public var context: [String: String] {
        switch self {
        case .toolExecutionFailed(let toolName, let error):
            return ["toolName": toolName, "underlyingError": error.localizedDescription]
        case .schemaValidationFailed(let errors):
            return ["validationErrors": errors.map { $0.message }.joined(separator: "; ")]
        case .streamingError(let error):
            return ["underlyingError": error.localizedDescription]
        default:
            return [:]
        }
    }
    
    public var underlyingError: Error? {
        switch self {
        case .streamingError(let error), .toolExecutionFailed(_, let error):
            return error
        default:
            return nil
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .modelOverloaded, .streamingError:
            return true
        default:
            return false
        }
    }
    
    public var requestId: String? { nil }
    
    public var errorDescription: String? { message }
}

/// Embedding-related errors
public enum AIEmbeddingError: AIError {
    case invalidInput(String)
    case dimensionMismatch(expected: Int, actual: Int)
    case batchSizeExceeded(max: Int, actual: Int)
    case embeddingFailed(Error)
    
    public var code: String {
        switch self {
        case .invalidInput: return "INVALID_INPUT"
        case .dimensionMismatch: return "DIMENSION_MISMATCH"
        case .batchSizeExceeded: return "BATCH_SIZE_EXCEEDED"
        case .embeddingFailed: return "EMBEDDING_FAILED"
        }
    }
    
    public var message: String {
        switch self {
        case .invalidInput(let details):
            return "Invalid input for embedding: \(details)"
        case .dimensionMismatch(let expected, let actual):
            return "Dimension mismatch: expected \(expected), got \(actual)"
        case .batchSizeExceeded(let max, let actual):
            return "Batch size exceeded: max \(max), got \(actual)"
        case .embeddingFailed(let error):
            return "Embedding generation failed: \(error.localizedDescription)"
        }
    }
    
    public var context: [String: String] {
        switch self {
        case .dimensionMismatch(let expected, let actual):
            return ["expected": String(expected), "actual": String(actual)]
        case .batchSizeExceeded(let max, let actual):
            return ["max": String(max), "actual": String(actual)]
        case .embeddingFailed(let error):
            return ["underlyingError": error.localizedDescription]
        default:
            return [:]
        }
    }
    
    public var underlyingError: Error? {
        switch self {
        case .embeddingFailed(let error):
            return error
        default:
            return nil
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .embeddingFailed:
            return true
        default:
            return false
        }
    }
    
    public var requestId: String? { nil }
    
    public var errorDescription: String? { message }
}

/// Middleware-related errors
public enum AIMiddlewareError: AIError {
    case middlewareExecutionFailed(middlewareId: String, error: Error)
    case middlewareChainBroken(String)
    case cacheError(Error)
    case rateLimitError(RateLimitError)
    
    public var code: String {
        switch self {
        case .middlewareExecutionFailed: return "MIDDLEWARE_EXECUTION_FAILED"
        case .middlewareChainBroken: return "MIDDLEWARE_CHAIN_BROKEN"
        case .cacheError: return "CACHE_ERROR"
        case .rateLimitError: return "RATE_LIMIT_ERROR"
        }
    }
    
    public var message: String {
        switch self {
        case .middlewareExecutionFailed(let middlewareId, let error):
            return "Middleware '\(middlewareId)' execution failed: \(error.localizedDescription)"
        case .middlewareChainBroken(let details):
            return "Middleware chain broken: \(details)"
        case .cacheError(let error):
            return "Cache error: \(error.localizedDescription)"
        case .rateLimitError(let error):
            return "Rate limit error: retry after \(Int(error.retryAfter)) seconds"
        }
    }
    
    public var context: [String: String] {
        switch self {
        case .middlewareExecutionFailed(let middlewareId, let error):
            return ["middlewareId": middlewareId, "underlyingError": error.localizedDescription]
        case .cacheError(let error):
            return ["underlyingError": error.localizedDescription]
        case .rateLimitError(let error):
            return ["retryAfter": String(error.retryAfter)]
        default:
            return [:]
        }
    }
    
    public var underlyingError: Error? {
        switch self {
        case .middlewareExecutionFailed(_, let error), .cacheError(let error):
            return error
        case .rateLimitError(let error):
            return error
        default:
            return nil
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .middlewareExecutionFailed, .rateLimitError:
            return true
        default:
            return false
        }
    }
    
    public var requestId: String? { nil }
    
    public var errorDescription: String? { message }
}

// MARK: - Error Result Type

/// Wrapper for any AI error that conforms to Error
public struct AnyAIError: Error, Sendable {
    public let wrapped: any AIError
    
    public init(_ error: any AIError) {
        self.wrapped = error
    }
}

/// Result type for AI operations
public typealias AIResult<T> = Result<T, AnyAIError>

// MARK: - Error Handling Utilities

/// Utilities for error handling
public struct ErrorHandler {
    
    /// Convert any error to AIError
    public static func wrapError(_ error: Error, requestId: String? = nil) -> any AIError {
        if let aiError = error as? any AIError {
            return aiError
        }
        
        // Map common Foundation errors
        if let urlError = error as? URLError {
            return AIProviderError.networkError(urlError)
        }
        
        if error is DecodingError {
            return AIGenerationError.objectParsingFailed(error.localizedDescription)
        }
        
        // Default wrapper
        return GenericAIError(
            code: "UNKNOWN_ERROR",
            message: error.localizedDescription,
            underlyingError: error,
            requestId: requestId
        )
    }
    
    /// Check if error is retryable
    public static func isRetryable(_ error: Error) -> Bool {
        if let aiError = error as? any AIError {
            return aiError.isRetryable
        }
        
        // Check common retryable errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    /// Extract retry delay from error
    public static func retryDelay(from error: Error) -> TimeInterval? {
        if case AIProviderError.rateLimitExceeded(let retryAfter) = error {
            return retryAfter
        }
        
        if case AIMiddlewareError.rateLimitError(let rateLimitError) = error {
            return rateLimitError.retryAfter
        }
        
        return nil
    }
}

// MARK: - Generic AI Error

/// Generic AIError implementation for wrapping other errors
public struct GenericAIError: AIError {
    public let code: String
    public let message: String
    public let context: [String: String]
    public let underlyingError: Error?
    public let isRetryable: Bool
    public let requestId: String?
    
    public init(
        code: String,
        message: String,
        context: [String: String] = [:],
        underlyingError: Error? = nil,
        isRetryable: Bool = false,
        requestId: String? = nil
    ) {
        self.code = code
        self.message = message
        self.context = context
        self.underlyingError = underlyingError
        self.isRetryable = isRetryable
        self.requestId = requestId
    }
    
    public var errorDescription: String? { message }
}