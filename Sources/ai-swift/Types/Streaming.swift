import Foundation

// MARK: - Text Streaming

/// Chunk of streamed text
public struct TextChunk: Sendable {
    public let delta: String
    public let snapshot: String
    public let finishReason: FinishReason?
    public let usage: TokenUsage?
    public let chunkId: String
    public let timestamp: Date
    public let stepId: String?
    
    public init(
        delta: String,
        snapshot: String,
        finishReason: FinishReason? = nil,
        usage: TokenUsage? = nil,
        chunkId: String = UUID().uuidString,
        timestamp: Date = Date(),
        stepId: String? = nil
    ) {
        self.delta = delta
        self.snapshot = snapshot
        self.finishReason = finishReason
        self.usage = usage
        self.chunkId = chunkId
        self.timestamp = timestamp
        self.stepId = stepId
    }
}

// MARK: - Object Streaming

/// Type-erased object chunk for stream events
public struct AnyObjectChunk: Sendable {
    public let delta: String
    public let snapshot: String
    public let finishReason: FinishReason?
    public let usage: TokenUsage?
    public let chunkId: String
    public let timestamp: Date
    public let stepId: String?
    
    public init(
        delta: String,
        snapshot: String,
        finishReason: FinishReason? = nil,
        usage: TokenUsage? = nil,
        chunkId: String = UUID().uuidString,
        timestamp: Date = Date(),
        stepId: String? = nil
    ) {
        self.delta = delta
        self.snapshot = snapshot
        self.finishReason = finishReason
        self.usage = usage
        self.chunkId = chunkId
        self.timestamp = timestamp
        self.stepId = stepId
    }
}

/// Chunk of streamed object
public struct ObjectChunk<T: Codable & Sendable>: Sendable {
    public let delta: String
    public let snapshot: String
    public let object: T?
    public let finishReason: FinishReason?
    public let usage: TokenUsage?
    public let chunkId: String
    public let timestamp: Date
    public let stepId: String?
    
    public init(
        delta: String,
        snapshot: String,
        object: T? = nil,
        finishReason: FinishReason? = nil,
        usage: TokenUsage? = nil,
        chunkId: String = UUID().uuidString,
        timestamp: Date = Date(),
        stepId: String? = nil
    ) {
        self.delta = delta
        self.snapshot = snapshot
        self.object = object
        self.finishReason = finishReason
        self.usage = usage
        self.chunkId = chunkId
        self.timestamp = timestamp
        self.stepId = stepId
    }
}

// MARK: - Stream Event Types

/// Events that can occur during streaming
public enum StreamEvent: Sendable {
    case textDelta(TextChunk)
    case objectDelta(AnyObjectChunk)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case error(AIError)
    case finish(FinishReason, TokenUsage?)
    
    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
    
    public var isFinish: Bool {
        if case .finish = self { return true }
        return false
    }
}

// MARK: - Stream State

/// Current state of a streaming operation
public struct StreamState: Sendable {
    public let isComplete: Bool
    public let finishReason: FinishReason?
    public let totalUsage: TokenUsage?
    public let currentStep: String?
    public let activeToolCalls: Set<String>
    
    public init(
        isComplete: Bool = false,
        finishReason: FinishReason? = nil,
        totalUsage: TokenUsage? = nil,
        currentStep: String? = nil,
        activeToolCalls: Set<String> = []
    ) {
        self.isComplete = isComplete
        self.finishReason = finishReason
        self.totalUsage = totalUsage
        self.currentStep = currentStep
        self.activeToolCalls = activeToolCalls
    }
}

// MARK: - Stream Configuration

/// Configuration for streaming behavior
public struct StreamConfiguration: Sendable {
    public let bufferSize: Int
    public let enableJSONCompletion: Bool
    public let enablePartialObjects: Bool
    public let maxRetries: Int
    public let timeoutInterval: TimeInterval
    
    public init(
        bufferSize: Int = 1024,
        enableJSONCompletion: Bool = true,
        enablePartialObjects: Bool = true,
        maxRetries: Int = 3,
        timeoutInterval: TimeInterval = 60.0
    ) {
        self.bufferSize = bufferSize
        self.enableJSONCompletion = enableJSONCompletion
        self.enablePartialObjects = enablePartialObjects
        self.maxRetries = maxRetries
        self.timeoutInterval = timeoutInterval
    }
}

// MARK: - Stream Protocol

/// Protocol for streaming operations
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol AIStream: AsyncSequence where Element: Sendable {
    
    /// Current state of the stream
    var state: StreamState { get async }
    
    /// Cancel the streaming operation
    func cancel() async
    
    /// Collect all chunks into final result
    func collect() async throws -> [Element]
}

// MARK: - Convenience Stream Types

/// Type alias for text streaming
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public typealias TextStream = AsyncThrowingStream<TextChunk, Error>

/// Type alias for object streaming
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public typealias ObjectStream<T: Codable> = AsyncThrowingStream<ObjectChunk<T>, Error>

// MARK: - Stream Utilities

/// Utilities for working with streams
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct StreamUtils {
    
    /// Merge multiple text streams into one
    public static func merge(_ streams: [TextStream]) -> TextStream {
        fatalError("StreamUtils.merge not implemented")
    }
    
    /// Buffer stream chunks for batch processing
    public static func buffer<T>(_ stream: AsyncThrowingStream<T, Error>, size: Int) -> AsyncThrowingStream<[T], Error> {
        fatalError("StreamUtils.buffer not implemented")
    }
    
    /// Transform stream elements
    public static func map<Input, Output>(
        _ stream: AsyncThrowingStream<Input, Error>,
        transform: @escaping @Sendable (Input) throws -> Output
    ) -> AsyncThrowingStream<Output, Error> {
        fatalError("StreamUtils.map not implemented")
    }
    
    /// Filter stream elements
    public static func filter<T>(
        _ stream: AsyncThrowingStream<T, Error>,
        predicate: @escaping @Sendable (T) -> Bool
    ) -> AsyncThrowingStream<T, Error> {
        fatalError("StreamUtils.filter not implemented")
    }
}