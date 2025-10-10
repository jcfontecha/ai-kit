import Foundation

// MARK: - Message Tracking System

/// Internal message tracking system for streaming operations.
///
/// This system automatically manages assistant messages, tool calls, and tool results
/// during streaming, matching Vercel AI SDK's behavior where the framework handles
/// message creation and updates transparently.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal actor StreamingMessageTracker {
    
    // MARK: - Types
    
    private struct Step {
        var messageId: String
        var content: [MessageContent]
        var toolResults: [ToolResult]
        
        var hasContent: Bool {
            !content.isEmpty || !toolResults.isEmpty
        }
        
        var toolCalls: [ToolCall] {
            content.compactMap { $0.toolCallValue }
        }
        
        var textValue: String {
            content.compactMap { $0.textValue }.joined()
        }
        
        mutating func appendText(_ text: String) {
            guard !text.isEmpty else { return }
            if let lastIndex = content.indices.last,
               case .text(let existing) = content[lastIndex] {
                content[lastIndex] = .text(existing + text)
            } else {
                content.append(.text(text))
            }
        }
        
        mutating func appendContent(_ newContent: MessageContent) {
            content.append(newContent)
        }
        
        mutating func appendToolCall(_ toolCall: ToolCall) {
            content.append(.toolCall(toolCall))
        }
        
        mutating func appendToolResult(_ toolResult: ToolResult) {
            toolResults.append(toolResult)
        }
    }
    
    private struct StreamingToolCallBuilder: Sendable {
        var id: String
        var name: String?
        var arguments: String = ""
        var type: ToolType = .function
        var timestamp: Date?
        var index: Int?
        
        mutating func registerStart(toolName: String) {
            name = toolName
            if timestamp == nil {
                timestamp = Date()
            }
        }
        
        mutating func appendArguments(_ delta: String) {
            arguments.append(delta)
        }
        
        func merged(with toolCall: ToolCall) -> ToolCall {
            if arguments.isEmpty {
                return toolCall
            }
            let updatedFunction = ToolCallFunction(
                name: toolCall.function.name,
                arguments: arguments
            )
            return ToolCall(
                id: toolCall.id,
                type: toolCall.type,
                function: updatedFunction,
                timestamp: toolCall.timestamp,
                index: toolCall.index
            )
        }
        
        func buildFallback() -> ToolCall? {
            guard let name else { return nil }
            let function = ToolCallFunction(name: name, arguments: arguments)
            return ToolCall(
                id: id,
                type: type,
                function: function,
                timestamp: timestamp ?? Date(),
                index: index
            )
        }
    }
    
    // MARK: - Properties
    
    private let initialMessageId: String
    private let generateMessageId: () -> String
    
    private var committedSteps: [Step] = []
    private var currentStep: Step?
    private var pendingNewStep = false
    private var streamingToolCallBuilders: [String: StreamingToolCallBuilder] = [:]
    
    // MARK: - Initialization
    
    init(
        messageId: String = UUID().uuidString,
        generateMessageId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.initialMessageId = messageId
        self.generateMessageId = generateMessageId
    }
    
    // MARK: - Step Management
    
    private func ensureCurrentStep() {
        if pendingNewStep {
            commitCurrentStep()
            currentStep = Step(messageId: generateMessageId(), content: [], toolResults: [])
            pendingNewStep = false
        } else if currentStep == nil {
            let id = committedSteps.isEmpty ? initialMessageId : generateMessageId()
            currentStep = Step(messageId: id, content: [], toolResults: [])
        }
    }
    
    private func commitCurrentStep() {
        flushStreamingToolCallsIntoCurrentStep()
        guard let step = currentStep else { return }
        if step.hasContent {
            committedSteps.append(step)
        }
        currentStep = nil
    }
    
    private func flushStreamingToolCallsIntoCurrentStep() {
        guard !streamingToolCallBuilders.isEmpty else { return }
        guard var step = currentStep else { return }
        
        for builder in streamingToolCallBuilders.values {
            if builder.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            if let toolCall = builder.buildFallback() {
                step.appendToolCall(toolCall)
            }
        }
        
        currentStep = step
        streamingToolCallBuilders.removeAll()
    }
    
    // MARK: - Event Handling
    
    func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        ensureCurrentStep()
        if var step = currentStep {
            step.appendText(text)
            currentStep = step
        }
    }
    
    func addToolCall(_ toolCall: ToolCall) {
        ensureCurrentStep()
        var finalToolCall = toolCall
        if var builder = streamingToolCallBuilders[toolCall.id] {
            builder.registerStart(toolName: toolCall.function.name)
            finalToolCall = builder.merged(with: toolCall)
            streamingToolCallBuilders.removeValue(forKey: toolCall.id)
        }
        
        if var step = currentStep {
            step.appendToolCall(finalToolCall)
            currentStep = step
        }
    }
    
    func addStreamingToolCallStart(_ start: ToolCallStreamingStart) {
        ensureCurrentStep()
        var builder = streamingToolCallBuilders[start.toolCallId] ?? StreamingToolCallBuilder(id: start.toolCallId)
        builder.registerStart(toolName: start.toolName)
        streamingToolCallBuilders[start.toolCallId] = builder
    }
    
    func addStreamingToolCallDelta(_ delta: ToolCallDelta) {
        ensureCurrentStep()
        var builder = streamingToolCallBuilders[delta.toolCallId] ?? StreamingToolCallBuilder(id: delta.toolCallId)
        builder.registerStart(toolName: delta.toolName)
        builder.appendArguments(delta.argsTextDelta)
        streamingToolCallBuilders[delta.toolCallId] = builder
    }
    
    func addToolResult(_ toolResult: ToolResult) {
        ensureCurrentStep()
        if var step = currentStep {
            step.appendToolResult(toolResult)
            currentStep = step
        }
        pendingNewStep = true
    }
    
    func addReasoning(_ reasoning: ReasoningContent) {
        ensureCurrentStep()
        if var step = currentStep {
            step.appendContent(.reasoning(reasoning))
            currentStep = step
        }
    }
    
    func addRedactedReasoning(_ redaction: ReasoningRedaction) {
        ensureCurrentStep()
        if var step = currentStep {
            step.appendContent(.redactedReasoning(redaction))
            currentStep = step
        }
    }
    
    func addReasoningSignature(_ signature: ReasoningSignature) {
        ensureCurrentStep()
        if var step = currentStep {
            step.appendContent(.reasoningSignature(signature))
            currentStep = step
        }
    }
    
    func addAnnotation(_ annotation: MessageAnnotation) {
        ensureCurrentStep()
        if var step = currentStep {
            step.appendContent(.annotation(annotation))
            currentStep = step
        }
    }
    
    // MARK: - Message Retrieval
    
    var responseMessages: [Message] {
        var messages: [Message] = []
        for step in committedSteps {
            messages.append(contentsOf: StepMessageBuilder.buildMessages(
                content: step.content,
                toolResults: step.toolResults,
                messageId: step.messageId,
                generateMessageId: generateMessageId
            ))
        }
        if let current = currentStep, current.hasContent {
            messages.append(contentsOf: StepMessageBuilder.buildMessages(
                content: current.content,
                toolResults: current.toolResults,
                messageId: current.messageId,
                generateMessageId: generateMessageId
            ))
        }
        return messages
    }
    
    var assistantMessage: Message? {
        responseMessages.last { $0.role == .assistant }
    }
    
    var allMessages: [Message] {
        responseMessages
    }
    
    // MARK: - State Queries
    
    var hasContent: Bool {
        !committedSteps.isEmpty || currentStep?.hasContent == true
    }
    
    var hasToolCalls: Bool {
        committedSteps.contains { !$0.toolCalls.isEmpty } || (currentStep?.toolCalls.isEmpty == false)
    }
    
    var text: String {
        let committed = committedSteps.map { $0.textValue }.joined()
        let current = currentStep?.textValue ?? ""
        return committed + current
    }
    
    var toolCalls: [ToolCall] {
        let committed = committedSteps.flatMap { $0.toolCalls }
        let current = currentStep?.toolCalls ?? []
        return committed + current
    }
    
    var toolResults: [ToolResult] {
        let committed = committedSteps.flatMap { $0.toolResults }
        let current = currentStep?.toolResults ?? []
        return committed + current
    }
    
    // MARK: - Finalization
    
    func finalize() {
        commitCurrentStep()
    }
}

// MARK: - Step Message Builder

/// Builds response messages from streaming steps, matching Vercel's `toResponseMessages`
internal struct StepMessageBuilder {
    
    /// Build response messages from accumulated content
    static func buildMessages(
        content: [MessageContent],
        toolResults: [ToolResult],
        messageId: String = UUID().uuidString,
        generateMessageId: () -> String = { UUID().uuidString }
    ) -> [Message] {
        var messages: [Message] = []
        if !content.isEmpty {
            let toolCalls = content.compactMap { $0.toolCallValue }
            let assistantMessage = Message(
                role: .assistant,
                content: content,
                id: messageId,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
            messages.append(assistantMessage)
        }

        if !toolResults.isEmpty {
            let toolMessage = Message(
                role: .tool,
                content: toolResults.map { MessageContent.toolResult($0) },
                id: generateMessageId()
            )
            messages.append(toolMessage)
        }

        return messages
    }
}

// MARK: - Stream Message Transformation

/// Transforms streaming chunks into properly formatted messages
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal struct StreamMessageTransformer {
    
    /// Transform a stream of chunks into a stream with message tracking
    static func transform<T: Sendable>(
        stream: AsyncThrowingStream<T, Error>,
        extractText: @escaping @Sendable (T) -> String?,
        extractToolCall: @escaping @Sendable (T) -> ToolCall?,
        extractToolResult: @escaping @Sendable (T) -> ToolResult?
    ) -> (stream: AsyncThrowingStream<T, Error>, tracker: StreamingMessageTracker) {
        let tracker = StreamingMessageTracker()
        
        let transformedStream = AsyncThrowingStream<T, Error> { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        // Extract and track content
                        if let text = extractText(chunk) {
                            await tracker.appendText(text)
                        }
                        
                        if let toolCall = extractToolCall(chunk) {
                            await tracker.addToolCall(toolCall)
                        }
                        
                        if let toolResult = extractToolResult(chunk) {
                            await tracker.addToolResult(toolResult)
                        }
                        
                        // Forward the chunk
                        continuation.yield(chunk)
                    }
                    
                    // Finalize tracking
                    await tracker.finalize()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        
        return (transformedStream, tracker)
    }
}
