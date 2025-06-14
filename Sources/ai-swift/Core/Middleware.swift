import Foundation

// MARK: - Middleware Protocol

/// Protocol for AI middleware components
public protocol AIMiddleware: Sendable {
    /// Unique identifier for this middleware
    var id: String { get }
    
    /// Human-readable name for this middleware
    var name: String { get }
    
    /// Priority for middleware ordering (higher = executed first)
    var priority: Int { get }
    
    /// Transform request before sending to provider
    func transformRequest<T>(_ request: T) async throws -> T where T: AIRequest
    
    /// Transform response after receiving from provider
    func transformResponse<T>(_ response: T) async throws -> T where T: AIResponse
    
    /// Handle streaming chunks
    func transformChunk<T>(_ chunk: T) async throws -> T where T: StreamChunk
    
    /// Handle errors during processing
    func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error
}

// MARK: - Request/Response Protocols

/// Protocol for AI requests
public protocol AIRequest: Sendable {
    var requestId: String { get }
    var timestamp: Date { get }
}

/// Protocol for AI responses  
public protocol AIResponse: Sendable {
    var responseId: String? { get }
    var timestamp: Date { get }
}

/// Protocol for stream chunks
public protocol StreamChunk: Sendable {
    var chunkId: String { get }
    var timestamp: Date { get }
}

// MARK: - Middleware Context

/// Context information for middleware operations
public struct MiddlewareContext: Sendable {
    public let requestId: String
    public let operationType: OperationType
    public let modelId: String
    public let providerId: String
    public let metadata: [String: String]
    
    public init(
        requestId: String,
        operationType: OperationType,
        modelId: String,
        providerId: String,
        metadata: [String: String] = [:]
    ) {
        self.requestId = requestId
        self.operationType = operationType
        self.modelId = modelId
        self.providerId = providerId
        self.metadata = metadata
    }
}

/// Types of AI operations
public enum OperationType: String, Codable, Sendable {
    case generateText
    case streamText
    case generateObject
    case streamObject
    case embed
    case embedMany
}

// MARK: - Middleware Chain

/// Manages the execution of middleware chain
public actor MiddlewareChain {
    private let middlewares: [any AIMiddleware]
    
    public init(middlewares: [any AIMiddleware]) {
        self.middlewares = middlewares.sorted { $0.priority > $1.priority }
    }
    
    /// Execute request transformation chain
    public func transformRequest<T: AIRequest>(_ request: T, context: MiddlewareContext) async throws -> T {
        var transformedRequest = request
        
        for middleware in middlewares {
            do {
                transformedRequest = try await middleware.transformRequest(transformedRequest)
            } catch {
                let handledError = try await middleware.handleError(error, context: context)
                throw handledError
            }
        }
        
        return transformedRequest
    }
    
    /// Execute response transformation chain
    public func transformResponse<T: AIResponse>(_ response: T, context: MiddlewareContext) async throws -> T {
        var transformedResponse = response
        
        for middleware in middlewares.reversed() {
            do {
                transformedResponse = try await middleware.transformResponse(transformedResponse)
            } catch {
                let handledError = try await middleware.handleError(error, context: context)
                throw handledError
            }
        }
        
        return transformedResponse
    }
    
    /// Execute chunk transformation chain
    public func transformChunk<T: StreamChunk>(_ chunk: T, context: MiddlewareContext) async throws -> T {
        var transformedChunk = chunk
        
        for middleware in middlewares.reversed() {
            do {
                transformedChunk = try await middleware.transformChunk(transformedChunk)
            } catch {
                let handledError = try await middleware.handleError(error, context: context)
                throw handledError
            }
        }
        
        return transformedChunk
    }
}

// MARK: - Built-in Middleware

/// Logging middleware
public struct LoggingMiddleware: AIMiddleware {
    public let id = "logging"
    public let name = "Logging Middleware"
    public let priority = 100
    
    private let logger: Logger
    
    public init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
    }
    
    public func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        await logger.log("Request: \(request.requestId)", level: .info)
        return request
    }
    
    public func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        await logger.log("Response: \(response.responseId ?? "unknown")", level: .info)
        return response
    }
    
    public func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        await logger.log("Chunk: \(chunk.chunkId)", level: .debug)
        return chunk
    }
    
    public func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        await logger.log("Error: \(error.localizedDescription)", level: .error)
        return error
    }
}

/// Caching middleware
public struct CachingMiddleware: AIMiddleware {
    public let id = "caching"
    public let name = "Caching Middleware"
    public let priority = 200
    
    private let cache: Cache
    
    public init(cache: Cache = MemoryCache()) {
        self.cache = cache
    }
    
    public func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        // Check cache for existing response
        return request
    }
    
    public func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        // Cache the response
        return response
    }
    
    public func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        return chunk
    }
    
    public func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        return error
    }
}

/// Rate limiting middleware
public struct RateLimitMiddleware: AIMiddleware {
    public let id = "rate-limit"
    public let name = "Rate Limit Middleware"
    public let priority = 300
    
    private let rateLimiter: RateLimiter
    
    public init(rateLimiter: RateLimiter) {
        self.rateLimiter = rateLimiter
    }
    
    public func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        try await rateLimiter.checkLimit()
        return request
    }
    
    public func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        return response
    }
    
    public func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        return chunk
    }
    
    public func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        return error
    }
}

/// Retry middleware
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct RetryMiddleware: AIMiddleware {
    public let id = "retry"
    public let name = "Retry Middleware"
    public let priority = 50
    
    private let maxRetries: Int
    private let backoffStrategy: BackoffStrategy
    
    public init(maxRetries: Int = 3, backoffStrategy: BackoffStrategy = .exponential) {
        self.maxRetries = maxRetries
        self.backoffStrategy = backoffStrategy
    }
    
    public func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        return request
    }
    
    public func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        return response
    }
    
    public func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        return chunk
    }
    
    public func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        if let retryableError = error as? RetryableError {
            if retryableError.retryCount < maxRetries {
                let delay = backoffStrategy.delay(for: retryableError.retryCount)
                try await Task.sleep(for: .seconds(delay))
                throw RetryableError(
                    originalError: retryableError.originalError,
                    retryCount: retryableError.retryCount + 1
                )
            }
        }
        return error
    }
}

// MARK: - Supporting Types

/// Protocol for logging
public protocol Logger: Sendable {
    func log(_ message: String, level: LogLevel) async
}

/// Log levels
public enum LogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

/// Console logger implementation
public struct ConsoleLogger: Logger {
    public init() {}
    
    public func log(_ message: String, level: LogLevel) async {
        print("[\(level.rawValue.uppercased())] \(message)")
    }
}

/// Protocol for caching
public protocol Cache: Sendable {
    func get<T: Codable & Sendable>(_ key: String, type: T.Type) async -> T?
    func set<T: Codable & Sendable>(_ key: String, value: T, expiration: TimeInterval?) async
    func remove(_ key: String) async
}

/// Memory cache implementation
public actor MemoryCache: Cache {
    private var storage: [String: CacheEntry] = [:]
    
    public init() {}
    
    public func get<T: Codable & Sendable>(_ key: String, type: T.Type) async -> T? {
        guard let entry = storage[key], !entry.isExpired else {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value as? T
    }
    
    public func set<T: Codable & Sendable>(_ key: String, value: T, expiration: TimeInterval?) async {
        let expirationDate = expiration.map { Date().addingTimeInterval($0) }
        storage[key] = CacheEntry(value: value, expiration: expirationDate)
    }
    
    public func remove(_ key: String) async {
        storage.removeValue(forKey: key)
    }
    
    private struct CacheEntry {
        let value: Any
        let expiration: Date?
        
        var isExpired: Bool {
            guard let expiration = expiration else { return false }
            return Date() > expiration
        }
    }
}

/// Protocol for rate limiting
public protocol RateLimiter: Sendable {
    func checkLimit() async throws
}

/// Rate limiting error
public struct RateLimitError: Error, Sendable {
    public let retryAfter: TimeInterval
    
    public init(retryAfter: TimeInterval) {
        self.retryAfter = retryAfter
    }
}

/// Retryable error wrapper
public struct RetryableError: Error, Sendable {
    public let originalError: Error
    public let retryCount: Int
    
    public init(originalError: Error, retryCount: Int = 0) {
        self.originalError = originalError
        self.retryCount = retryCount
    }
}

/// Backoff strategies for retries
public enum BackoffStrategy: Sendable {
    case fixed(TimeInterval)
    case exponential
    case linear
    
    func delay(for retryCount: Int) -> TimeInterval {
        switch self {
        case .fixed(let interval):
            return interval
        case .exponential:
            return pow(2.0, Double(retryCount))
        case .linear:
            return TimeInterval(retryCount + 1)
        }
    }
}

// MARK: - Middleware Extensions

/// Default middleware implementations
public extension AIMiddleware {
    func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        return request
    }
    
    func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        return response
    }
    
    func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        return chunk
    }
    
    func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        return error
    }
}