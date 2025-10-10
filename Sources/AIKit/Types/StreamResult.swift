import Foundation

// MARK: - Stream Result Types

/// Response data from a streaming text generation operation.
///
/// This type encapsulates the accumulated response data from streaming,
/// matching Vercel AI SDK's pattern where `response.messages` provides
/// properly formatted messages for conversation history.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct StreamTextResponse: Sendable {
    /// The properly formatted response messages.
    ///
    /// This includes assistant messages with tool calls and separate
    /// tool result messages, ready to be added to conversation history.
    public let messages: [Message]
    
    /// The complete generated text.
    public let text: String
    
    /// Token usage information.
    public let usage: TokenUsage?
    
    /// The finish reason.
    public let finishReason: FinishReason?
    
    /// Tool calls made during generation.
    public let toolCalls: [ToolCall]
    
    /// Tool results from execution.
    public let toolResults: [ToolResult]
    
    /// Stream data payloads emitted during generation.
    public let streamData: [[String: String]]
    
    internal init(
        messages: [Message],
        text: String,
        usage: TokenUsage?,
        finishReason: FinishReason?,
        toolCalls: [ToolCall],
        toolResults: [ToolResult],
        streamData: [[String: String]]
    ) {
        self.messages = messages
        self.text = text
        self.usage = usage
        self.finishReason = finishReason
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.streamData = streamData
    }
}

/// Result of a streaming text generation operation.
///
/// This type wraps the underlying stream and provides access to accumulated
/// results like messages, text, and tool calls, matching Vercel AI SDK's pattern
/// where the stream result exposes both the stream and the accumulated data.
///
/// ## Usage Example:
/// ```swift
/// let result = client.streamText(model, messages: messages, tools: tools)
/// 
/// // Stream chunks in real-time
/// for try await chunk in result.textStream {
///     print(chunk.delta)
/// }
/// 
/// // Access properly formatted messages after streaming
/// let responseMessages = await result.messages
/// conversation.append(contentsOf: responseMessages)
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class StreamTextResult: Sendable {
    
    // MARK: - Private Properties
    
    private let messageTracker: StreamingMessageTracker
    private let baseStream: AsyncThrowingStream<TextChunk, Error>
    private let tools: [Tool]?
    
    // Accumulated values
    private let textActor = TextAccumulator()
    private let usageActor = UsageAccumulator()
    private let finishReasonActor = FinishReasonAccumulator()
    
    @MainActor
    public private(set) var streamData: [[String: String]] = []
    
    // MARK: - Initialization
    
    internal init(
        stream: AsyncThrowingStream<TextChunk, Error>,
        messageTracker: StreamingMessageTracker,
        tools: [Tool]?
    ) {
        self.baseStream = stream
        self.messageTracker = messageTracker
        self.tools = tools
    }
    
    // MARK: - Stream Access
    
    /// The text stream that yields chunks in real-time.
    public var textStream: AsyncThrowingStream<TextChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in baseStream {
                        // Track content
                        await textActor.append(chunk.delta)
                        
                        if let usage = chunk.usage {
                            await usageActor.update(usage)
                        }
                        
                        if let finishReason = chunk.finishReason {
                            await finishReasonActor.update(finishReason)
                        }
                        
                        // Track in message tracker
                        if !chunk.delta.isEmpty {
                            await messageTracker.appendText(chunk.delta)
                        }
                        
                        if let streamingStart = chunk.toolCallStreamingStart {
                            await messageTracker.addStreamingToolCallStart(streamingStart)
                        }
                        
                        if let streamingDelta = chunk.toolCallDelta {
                            await messageTracker.addStreamingToolCallDelta(streamingDelta)
                        }
                        
                        if let toolCalls = chunk.toolCalls {
                            for toolCall in toolCalls {
                                await messageTracker.addToolCall(toolCall)
                            }
                        }
                        
                        if let reasonings = chunk.reasoning {
                            for reasoning in reasonings {
                                await messageTracker.addReasoning(reasoning)
                            }
                        }
                        
                        if let redactions = chunk.redactedReasoning {
                            for redaction in redactions {
                                await messageTracker.addRedactedReasoning(redaction)
                            }
                        }
                        
                        if let signatures = chunk.reasoningSignatures {
                            for signature in signatures {
                                await messageTracker.addReasoningSignature(signature)
                            }
                        }
                        
                        if let annotations = chunk.messageAnnotations {
                            for annotation in annotations {
                                await messageTracker.addAnnotation(annotation)
                            }
                        }
                        
                        if let streamDataEntries = chunk.streamData, !streamDataEntries.isEmpty {
                            await MainActor.run {
                                self.streamData.append(contentsOf: streamDataEntries)
                            }
                        }
                        
                        // Yield chunk
                        continuation.yield(chunk)
                    }
                    
                    await messageTracker.finalize()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Accumulated Properties
    
    /// The complete generated text after streaming completes.
    public var text: String {
        get async {
            await textActor.value
        }
    }
    
    /// The properly formatted response messages.
    ///
    /// This includes the assistant message with any tool calls and separate
    /// tool result messages, ready to be added to conversation history.
    public var messages: [Message] {
        get async {
            await messageTracker.responseMessages
        }
    }
    
    /// The final token usage after streaming completes.
    public var usage: TokenUsage? {
        get async {
            await usageActor.value
        }
    }
    
    /// The finish reason after streaming completes.
    public var finishReason: FinishReason? {
        get async {
            await finishReasonActor.value
        }
    }
    
    /// Tool calls made during generation.
    public var toolCalls: [ToolCall] {
        get async {
            await messageTracker.toolCalls
        }
    }
    
    /// Tool results from execution.
    public var toolResults: [ToolResult] {
        get async {
            await messageTracker.toolResults
        }
    }
    
    /// Aggregated stream data payloads emitted during streaming.
    public var streamDataValues: [[String: String]] {
        get async {
            await MainActor.run { streamData }
        }
    }
    
    /// The complete response object, matching Vercel AI SDK's pattern.
    ///
    /// This property provides access to the accumulated response data in a format
    /// that matches Vercel AI SDK's API. The response includes properly formatted
    /// messages that can be directly appended to conversation history.
    ///
    /// ## Usage Example:
    /// ```swift
    /// let result = client.streamText(model, messages: messages, tools: tools)
    /// 
    /// // Stream chunks
    /// for try await chunk in result.textStream {
    ///     print(chunk.delta)
    /// }
    /// 
    /// // Access response messages (Vercel-style)
    /// let response = await result.response
    /// conversation.append(contentsOf: response.messages)
    /// ```
    public var response: StreamTextResponse {
        get async {
            let streamDataSnapshot = await MainActor.run { streamData }
            return StreamTextResponse(
                messages: await messageTracker.responseMessages,
                text: await textActor.value,
                usage: await usageActor.value,
                finishReason: await finishReasonActor.value,
                toolCalls: await messageTracker.toolCalls,
                toolResults: await messageTracker.toolResults,
                streamData: streamDataSnapshot
            )
        }
    }
}

// MARK: - Stream Object Result

/// Result of a streaming object generation operation.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class StreamObjectResult<T: Codable & Sendable>: Sendable {
    
    private let baseStream: AsyncThrowingStream<ObjectChunk<T>, Error>
    private let objectActor = ObjectAccumulator<T>()
    private let textActor = TextAccumulator()
    private let usageActor = UsageAccumulator()
    private let finishReasonActor = FinishReasonAccumulator()
    
    internal init(stream: AsyncThrowingStream<ObjectChunk<T>, Error>) {
        self.baseStream = stream
    }
    
    /// The object stream that yields chunks in real-time.
    public var objectStream: AsyncThrowingStream<ObjectChunk<T>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in baseStream {
                        // Track content
                        await textActor.append(chunk.delta)
                        
                        if let object = chunk.object {
                            await objectActor.update(object)
                        }
                        
                        if let usage = chunk.usage {
                            await usageActor.update(usage)
                        }
                        
                        if let finishReason = chunk.finishReason {
                            await finishReasonActor.update(finishReason)
                        }
                        
                        // Yield chunk
                        continuation.yield(chunk)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// The final generated object after streaming completes.
    public var object: T? {
        get async {
            await objectActor.value
        }
    }
    
    /// The raw text that was parsed into the object.
    public var text: String {
        get async {
            await textActor.value
        }
    }
    
    /// The final token usage after streaming completes.
    public var usage: TokenUsage? {
        get async {
            await usageActor.value
        }
    }
    
    /// The finish reason after streaming completes.
    public var finishReason: FinishReason? {
        get async {
            await finishReasonActor.value
        }
    }
}

// MARK: - Internal Accumulator Actors

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private actor TextAccumulator {
    private var text = ""
    
    func append(_ delta: String) {
        text += delta
    }
    
    var value: String {
        text
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private actor ObjectAccumulator<T> {
    private var object: T?
    
    func update(_ newObject: T) {
        object = newObject
    }
    
    var value: T? {
        object
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private actor UsageAccumulator {
    private var usage: TokenUsage?
    
    func update(_ newUsage: TokenUsage) {
        usage = newUsage
    }
    
    var value: TokenUsage? {
        usage
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private actor FinishReasonAccumulator {
    private var finishReason: FinishReason?
    
    func update(_ reason: FinishReason) {
        finishReason = reason
    }
    
    var value: FinishReason? {
        finishReason
    }
}
