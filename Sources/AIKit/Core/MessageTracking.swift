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
        var text: String
        var toolCalls: [ToolCall]
        var toolResults: [ToolResult]
        
        var hasContent: Bool {
            !text.isEmpty || !toolCalls.isEmpty || !toolResults.isEmpty
        }
    }
    
    // MARK: - Properties
    
    private let initialMessageId: String
    private let generateMessageId: () -> String
    
    private var committedSteps: [Step] = []
    private var currentStep: Step?
    private var pendingNewStep = false
    
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
            currentStep = Step(messageId: generateMessageId(), text: "", toolCalls: [], toolResults: [])
            pendingNewStep = false
        } else if currentStep == nil {
            let id = committedSteps.isEmpty ? initialMessageId : generateMessageId()
            currentStep = Step(messageId: id, text: "", toolCalls: [], toolResults: [])
        }
    }
    
    private func commitCurrentStep() {
        guard let step = currentStep else { return }
        if step.hasContent {
            committedSteps.append(step)
        }
        currentStep = nil
    }
    
    // MARK: - Event Handling
    
    func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        ensureCurrentStep()
        currentStep?.text.append(text)
    }
    
    func addToolCall(_ toolCall: ToolCall) {
        ensureCurrentStep()
        currentStep?.toolCalls.append(toolCall)
    }
    
    func addToolResult(_ toolResult: ToolResult) {
        ensureCurrentStep()
        currentStep?.toolResults.append(toolResult)
        pendingNewStep = true
    }
    
    // MARK: - Message Retrieval
    
    var responseMessages: [Message] {
        var messages: [Message] = []
        for step in committedSteps {
            messages.append(contentsOf: StepMessageBuilder.buildMessages(
                text: step.text,
                toolCalls: step.toolCalls,
                toolResults: step.toolResults,
                messageId: step.messageId,
                generateMessageId: generateMessageId
            ))
        }
        if let current = currentStep, current.hasContent {
            messages.append(contentsOf: StepMessageBuilder.buildMessages(
                text: current.text,
                toolCalls: current.toolCalls,
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
        currentStep?.text ?? ""
    }
    
    var toolCalls: [ToolCall] {
        currentStep?.toolCalls ?? []
    }
    
    var toolResults: [ToolResult] {
        currentStep?.toolResults ?? []
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
        text: String,
        toolCalls: [ToolCall],
        toolResults: [ToolResult],
        messageId: String = UUID().uuidString,
        generateMessageId: () -> String = { UUID().uuidString }
    ) -> [Message] {
        var messages: [Message] = []

        var content: [MessageContent] = []

        if !text.isEmpty {
            content.append(.text(text))
        }

        if !toolCalls.isEmpty {
            content.append(contentsOf: toolCalls.map { MessageContent.toolCall($0) })
        }

        if !content.isEmpty {
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
