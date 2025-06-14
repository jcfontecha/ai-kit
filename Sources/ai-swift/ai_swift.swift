// The Swift AI SDK
// 
// A comprehensive Swift framework for AI model interactions, inspired by the Vercel AI SDK.
// Provides type-safe, protocol-oriented interfaces for text generation, object generation,
// embeddings, and streaming operations with built-in middleware support.

import Foundation

// MARK: - Public Module Interface

// Re-export core types for convenient access
public typealias AI = AISwift

/// Main namespace for the AI Swift SDK
public enum AISwift {
    
    // MARK: - Provider Factory
    
    /// Create a mock provider for testing and development
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public static func mockProvider(apiKey: String = "mock-key", middleware: [any AIMiddleware] = []) -> MockProvider {
        MockProvider(apiKey: apiKey, middleware: middleware)
    }
    
    // MARK: - Middleware Factory
    
    /// Create logging middleware
    public static func loggingMiddleware(logger: Logger = ConsoleLogger()) -> LoggingMiddleware {
        LoggingMiddleware(logger: logger)
    }
    
    /// Create caching middleware
    public static func cachingMiddleware(cache: Cache = MemoryCache()) -> CachingMiddleware {
        CachingMiddleware(cache: cache)
    }
    
    /// Create rate limiting middleware
    public static func rateLimitMiddleware(maxRequests: Int = 100, resetInterval: TimeInterval = 60) -> RateLimitMiddleware {
        let rateLimiter = MockRateLimiter(maxRequests: maxRequests, resetInterval: resetInterval)
        return RateLimitMiddleware(rateLimiter: rateLimiter)
    }
    
    /// Create retry middleware
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public static func retryMiddleware(maxRetries: Int = 3, backoffStrategy: BackoffStrategy = .exponential) -> RetryMiddleware {
        RetryMiddleware(maxRetries: maxRetries, backoffStrategy: backoffStrategy)
    }
    
    // MARK: - Utility Functions
    
    /// Calculate cosine similarity between two embeddings
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        fatalError("AISwift.cosineSimilarity not implemented")
    }
    
    /// Generate a unique ID for requests
    public static func generateID() -> String {
        UUID().uuidString
    }
    
    /// Validate JSON schema
    public static func validateSchema(_ data: Data, against schema: JSONSchema) throws -> ValidationResult {
        let validator = MockSchemaValidator()
        return try validator.validate(data, against: schema)
    }
    
    // MARK: - Configuration
    
    /// Default model configuration
    public static let defaultConfiguration = ModelConfiguration()
    
    /// Creative model configuration (high temperature)
    public static let creativeConfiguration = ModelConfiguration()
        .temperature(0.9)
        .topP(0.9)
    
    /// Precise model configuration (low temperature)
    public static let preciseConfiguration = ModelConfiguration()
        .temperature(0.1)
        .topP(0.1)
    
    /// Balanced model configuration
    public static let balancedConfiguration = ModelConfiguration()
        .temperature(0.5)
        .topP(0.5)
}

// MARK: - Version Information

public extension AISwift {
    /// SDK version information
    static let version = "1.0.0"
    
    /// SDK build information
    static let buildInfo = BuildInfo(
        version: version,
        buildDate: Date(),
        swiftVersion: "5.9"
    )
}

/// Build information structure
public struct BuildInfo: Sendable {
    public let version: String
    public let buildDate: Date
    public let swiftVersion: String
    
    public init(version: String, buildDate: Date, swiftVersion: String) {
        self.version = version
        self.buildDate = buildDate
        self.swiftVersion = swiftVersion
    }
}
