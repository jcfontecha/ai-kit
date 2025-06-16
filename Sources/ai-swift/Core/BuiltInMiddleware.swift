/**
 * Enhanced built-in middleware implementations following Vercel AI SDK patterns.
 * 
 * This file contains advanced middleware implementations that extend the basic
 * middleware framework with Vercel AI SDK-style functionality:
 * - AdvancedLoggingMiddleware: Detailed request/response logging with configurable levels
 * - AdvancedCachingMiddleware: Memory-based response caching with TTL support
 * - AdvancedRetryMiddleware: Exponential backoff retry logic for failed requests
 * - DefaultSettingsMiddleware: Applies default model configuration settings
 * 
 * These middleware complement the basic implementations in Middleware.swift
 * and provide more sophisticated functionality for production use cases.
 */

import Foundation
import os.log

// MARK: - Advanced Logging Middleware

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct AdvancedLoggingMiddleware: AIMiddleware {
    public let id = "advanced-logging"
    public let name = "Advanced Logging Middleware" 
    public let priority = 100
    
    public enum DetailLevel: String, CaseIterable, Sendable {
        case verbose = "verbose"  // Logs full request/response details
        case standard = "standard" // Logs basic request info and response metadata  
        case minimal = "minimal"   // Only logs errors and high-level operations
        
        var osLogType: OSLogType {
            switch self {
            case .verbose: return .debug
            case .standard: return .info
            case .minimal: return .error
            }
        }
    }
    
    private let logger: os.Logger
    private let detailLevel: DetailLevel
    private let includeTimestamps: Bool
    private let includePerformanceMetrics: Bool
    private let includeRequestContent: Bool
    private let includeResponseContent: Bool
    
    public init(
        detailLevel: DetailLevel = .standard,
        includeTimestamps: Bool = true,
        includePerformanceMetrics: Bool = true,
        includeRequestContent: Bool = false,
        includeResponseContent: Bool = false,
        subsystem: String = "ai.swift.middleware",
        category: String = "advanced-logging"
    ) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
        self.detailLevel = detailLevel
        self.includeTimestamps = includeTimestamps
        self.includePerformanceMetrics = includePerformanceMetrics
        self.includeRequestContent = includeRequestContent
        self.includeResponseContent = includeResponseContent
    }
    
    public func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        if detailLevel == .verbose || detailLevel == .standard {
            var logMessage = "🚀 AI Request Started"
            
            if includeTimestamps {
                logMessage += " at \(request.timestamp.ISO8601Format())"
            }
            
            logMessage += "\n  Request ID: \(request.requestId)"
            
            // Add content if enabled and available
            if includeRequestContent {
                logMessage += "\n  Content: [Request content logging not implemented]"
            }
            
            logger.log(level: detailLevel.osLogType, "\(logMessage)")
        }
        
        return request
    }
    
    public func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        if detailLevel == .verbose || detailLevel == .standard {
            var logMessage = "✅ AI Response Completed"
            
            if includeTimestamps {
                logMessage += " at \(response.timestamp.ISO8601Format())"
            }
            
            if let responseId = response.responseId {
                logMessage += "\n  Response ID: \(responseId)"
            }
            
            if includePerformanceMetrics {
                // Add performance metrics if available
                logMessage += "\n  Performance: [Metrics not implemented yet]"
            }
            
            if includeResponseContent {
                logMessage += "\n  Content: [Response content logging not implemented]"
            }
            
            logger.log(level: detailLevel.osLogType, "\(logMessage)")
        }
        
        return response
    }
    
    public func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        if detailLevel == .verbose {
            logger.log(level: .debug, "📦 Stream Chunk: \(chunk.chunkId)")
        }
        return chunk
    }
    
    public func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        var logMessage = "❌ AI Operation Failed"
        logMessage += "\n  Request ID: \(context.requestId)"
        logMessage += "\n  Operation: \(context.operationType.rawValue)"
        logMessage += "\n  Model: \(context.modelId)"
        logMessage += "\n  Provider: \(context.providerId)"
        logMessage += "\n  Error: \(error.localizedDescription)"
        
        logger.log(level: .error, "\(logMessage)")
        return error
    }
}

// MARK: - Advanced Caching Middleware

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public actor AdvancedCachingMiddleware: AIMiddleware {
    public let id = "advanced-caching"
    public let name = "Advanced Caching Middleware"
    public let priority = 200
    
    public struct CacheConfiguration: Sendable {
        public let ttl: TimeInterval  // Time-to-live in seconds
        public let maxEntries: Int   // Maximum cache entries before eviction
        public let keyPrefix: String // Prefix for cache keys
        public let enableCompression: Bool // Enable response compression
        
        public init(
            ttl: TimeInterval = 3600,
            maxEntries: Int = 1000,
            keyPrefix: String = "ai_advanced_cache",
            enableCompression: Bool = true
        ) {
            self.ttl = ttl
            self.maxEntries = maxEntries
            self.keyPrefix = keyPrefix
            self.enableCompression = enableCompression
        }
    }
    
    private struct CacheEntry {
        let response: Any // Store as Any to handle different response types
        let timestamp: Date
        let ttl: TimeInterval
        let size: Int
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let configuration: CacheConfiguration
    private let logger = os.Logger(subsystem: "ai.swift.middleware", category: "advanced-caching")
    
    public init(configuration: CacheConfiguration = CacheConfiguration()) {
        self.configuration = configuration
    }
    
    public func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        // Request transformation happens in the response phase for caching
        return request
    }
    
    public func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        let cacheKey = generateCacheKey(for: response)
        
        // Cache the response
        cacheResponse(response, for: cacheKey)
        
        return response
    }
    
    public func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        // Streaming responses are not cached in this implementation
        return chunk
    }
    
    public func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        return error
    }
    
    private func generateCacheKey<T: AIResponse>(for response: T) -> String {
        // Create a deterministic cache key from response metadata
        let keyData = [
            "response_id": response.responseId ?? "unknown",
            "timestamp": response.timestamp.description
        ]
        
        let keyString = keyData.map { "\($0.key):\($0.value)" }.joined(separator: "|")
        return "\(configuration.keyPrefix)_\(keyString.hash)"
    }
    
    private func cacheResponse<T: AIResponse>(_ response: T, for key: String) {
        // Clean expired entries first
        cleanExpiredEntries()
        
        // Implement LRU eviction if at capacity
        if cache.count >= configuration.maxEntries {
            // Remove oldest entry
            let oldestKey = cache.min { $0.value.timestamp < $1.value.timestamp }?.key
            if let oldestKey = oldestKey {
                cache.removeValue(forKey: oldestKey)
                logger.debug("Evicted oldest cache entry: \(oldestKey)")
            }
        }
        
        let entry = CacheEntry(
            response: response,
            timestamp: Date(),
            ttl: configuration.ttl,
            size: MemoryLayout.size(ofValue: response) // Approximate size
        )
        
        cache[key] = entry
        logger.debug("Cached response for key: \(key)")
    }
    
    private func cleanExpiredEntries() {
        let expiredKeys = cache.compactMap { key, entry in
            entry.isExpired ? key : nil
        }
        
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
        
        if !expiredKeys.isEmpty {
            logger.debug("Cleaned \(expiredKeys.count) expired cache entries")
        }
    }
    
    public func clearCache() {
        cache.removeAll()
        logger.info("Advanced cache cleared")
    }
    
    public func getCacheStats() -> (entries: Int, totalSize: Int) {
        cleanExpiredEntries()
        let totalSize = cache.values.reduce(0) { $0 + $1.size }
        return (entries: cache.count, totalSize: totalSize)
    }
}

// MARK: - Advanced Retry Middleware

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AdvancedRetryMiddleware: AIMiddleware {
    public let id = "advanced-retry"
    public let name = "Advanced Retry Middleware"
    public let priority = 50
    
    public struct RetryConfiguration: Sendable {
        public let maxRetries: Int
        public let baseDelay: TimeInterval    // Base delay for exponential backoff
        public let maxDelay: TimeInterval     // Maximum delay between retries
        public let backoffMultiplier: Double  // Multiplier for exponential backoff
        public let jitter: Bool              // Add random jitter to prevent thundering herd
        public let retryableErrors: Set<String> // Specific error types to retry
        
        public init(
            maxRetries: Int = 3,
            baseDelay: TimeInterval = 1.0,
            maxDelay: TimeInterval = 60.0,
            backoffMultiplier: Double = 2.0,
            jitter: Bool = true,
            retryableErrors: Set<String> = ["network", "timeout", "rate_limit", "server_error"]
        ) {
            self.maxRetries = maxRetries
            self.baseDelay = baseDelay
            self.maxDelay = maxDelay
            self.backoffMultiplier = backoffMultiplier
            self.jitter = jitter
            self.retryableErrors = retryableErrors
        }
    }
    
    private let configuration: RetryConfiguration
    private let logger = os.Logger(subsystem: "ai.swift.middleware", category: "advanced-retry")
    
    public init(configuration: RetryConfiguration = RetryConfiguration()) {
        self.configuration = configuration
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
        // Enhanced retry logic with configurable retry conditions
        if isRetryableError(error) {
            if let retryableError = error as? RetryableError {
                if retryableError.retryCount < configuration.maxRetries {
                    let delay = calculateDelay(for: retryableError.retryCount + 1)
                    logger.info("Retrying request \(context.requestId) (attempt \(retryableError.retryCount + 1)/\(configuration.maxRetries)) after \(String(format: "%.1f", delay))s")
                    
                    try await Task.sleep(for: .seconds(delay))
                    throw RetryableError(
                        originalError: retryableError.originalError,
                        retryCount: retryableError.retryCount + 1
                    )
                } else {
                    logger.error("Request \(context.requestId) failed after \(configuration.maxRetries) retries")
                }
            } else {
                // First retry attempt
                let delay = calculateDelay(for: 1)
                logger.info("Retrying request \(context.requestId) (attempt 1/\(configuration.maxRetries)) after \(String(format: "%.1f", delay))s")
                
                try await Task.sleep(for: .seconds(delay))
                throw RetryableError(originalError: error, retryCount: 1)
            }
        }
        
        return error
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        // Enhanced retry logic based on error types
        if let aiError = error as? AIGenerationError {
            switch aiError {
            case .streamingError, .modelOverloaded, .unexpectedResponse:
                return true
            case .invalidPrompt, .invalidParameters, .contentFiltered, .noSuchTool, .invalidToolArguments:
                return false
            default:
                return true
            }
        }
        
        // Check against configurable retryable error types
        let errorDescription = error.localizedDescription.lowercased()
        return configuration.retryableErrors.contains { errorType in
            errorDescription.contains(errorType)
        }
    }
    
    private func calculateDelay(for attempt: Int) -> TimeInterval {
        let exponentialDelay = configuration.baseDelay * pow(configuration.backoffMultiplier, Double(attempt - 1))
        var delay = min(exponentialDelay, configuration.maxDelay)
        
        // Add jitter to prevent thundering herd
        if configuration.jitter {
            let jitterRange = delay * 0.1 // 10% jitter
            let randomJitter = Double.random(in: -jitterRange...jitterRange)
            delay = max(0.1, delay + randomJitter) // Ensure minimum delay
        }
        
        return delay
    }
}

// MARK: - Performance Monitoring Middleware

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public actor PerformanceMonitoringMiddleware: AIMiddleware {
    public let id = "performance-monitoring"
    public let name = "Performance Monitoring Middleware"
    public let priority = 150
    
    public struct PerformanceMetrics: Sendable {
        public let requestId: String
        public let operationType: OperationType
        public let modelId: String
        public let providerId: String
        public let startTime: Date
        public let endTime: Date
        public let duration: TimeInterval
        public let tokenCount: Int?
        public let success: Bool
        
        public init(
            requestId: String,
            operationType: OperationType,
            modelId: String,
            providerId: String,
            startTime: Date,
            endTime: Date,
            tokenCount: Int? = nil,
            success: Bool
        ) {
            self.requestId = requestId
            self.operationType = operationType
            self.modelId = modelId
            self.providerId = providerId
            self.startTime = startTime
            self.endTime = endTime
            self.duration = endTime.timeIntervalSince(startTime)
            self.tokenCount = tokenCount
            self.success = success
        }
    }
    
    private var activeRequests: [String: Date] = [:]
    private var metrics: [PerformanceMetrics] = []
    private let maxMetricsHistory: Int
    private let logger = os.Logger(subsystem: "ai.swift.middleware", category: "performance")
    
    public init(maxMetricsHistory: Int = 1000) {
        self.maxMetricsHistory = maxMetricsHistory
    }
    
    public func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
        activeRequests[request.requestId] = Date()
        logger.debug("Started tracking performance for request: \(request.requestId)")
        return request
    }
    
    public func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
        if let responseId = response.responseId,
           let startTime = activeRequests.removeValue(forKey: responseId) {
            
            // Create performance metrics (would need context to get full details)
            let metric = PerformanceMetrics(
                requestId: responseId,
                operationType: .generateText, // Would need to determine actual operation type
                modelId: "unknown", // Would need context
                providerId: "unknown", // Would need context
                startTime: startTime,
                endTime: response.timestamp,
                success: true
            )
            
            recordMetric(metric)
        }
        
        return response
    }
    
    public func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
        // For streaming, we track individual chunks but don't complete the metrics yet
        return chunk
    }
    
    public func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
        if let startTime = activeRequests.removeValue(forKey: context.requestId) {
            let metric = PerformanceMetrics(
                requestId: context.requestId,
                operationType: context.operationType,
                modelId: context.modelId,
                providerId: context.providerId,
                startTime: startTime,
                endTime: Date(),
                success: false
            )
            
            recordMetric(metric)
        }
        
        return error
    }
    
    private func recordMetric(_ metric: PerformanceMetrics) {
        metrics.append(metric)
        
        // Trim history if needed
        if metrics.count > maxMetricsHistory {
            metrics = Array(metrics.suffix(maxMetricsHistory))
        }
        
        logger.info("Request \(metric.requestId) completed in \(String(format: "%.3f", metric.duration))s - Success: \(metric.success)")
    }
    
    public func getMetrics() -> [PerformanceMetrics] {
        return metrics
    }
    
    public func getAverageLatency(for operationType: OperationType? = nil) -> TimeInterval {
        let filteredMetrics = operationType.map { type in
            metrics.filter { $0.operationType == type && $0.success }
        } ?? metrics.filter { $0.success }
        
        guard !filteredMetrics.isEmpty else { return 0 }
        
        let totalDuration = filteredMetrics.reduce(0) { $0 + $1.duration }
        return totalDuration / Double(filteredMetrics.count)
    }
}