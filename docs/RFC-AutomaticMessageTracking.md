# RFC: Automatic Message Tracking in AIKit

## Problem Statement

Currently, AIKit's streaming API requires host applications to manually track and format messages during streaming operations, particularly when tool calls are involved. This leads to:

1. **Complex client code**: Applications must manually create assistant messages, track tool calls, and format tool results
2. **Error-prone implementations**: Easy to miss tool call information or incorrectly format messages
3. **Inconsistent patterns**: Each application implements message tracking differently
4. **Poor developer experience**: Developers expect the framework to handle message formatting (as Vercel AI SDK does)

### Example of Current Complexity

```swift
// Current approach in ChatService - manual tracking required
private func streamAIResponse(for conversation: ChatConversation) async throws {
    // Manually create empty assistant message
    let assistantMessage = ChatMessage(
        conversationId: conversation.id,
        role: .assistant,
        content: ""
    )
    conversation.messages.append(assistantMessage)
    
    // Stream response
    let stream = client.streamText(model, messages: messages, tools: tools)
    
    var accumulatedText = ""
    var toolCalls: [ToolCall] = []
    
    for try await chunk in stream {
        accumulatedText += chunk.delta
        
        // Manually update message
        if let messageIndex = conversation.messages.firstIndex(where: { $0.id == assistantMessage.id }) {
            conversation.messages[messageIndex].content = accumulatedText
        }
        
        // Manually track tool calls
        if let chunkToolCalls = chunk.toolCalls {
            toolCalls.append(contentsOf: chunkToolCalls)
        }
    }
    
    // Manually create assistant message with tool calls
    if !toolCalls.isEmpty {
        // Complex logic to format message with tool calls
    }
}
```

## Proposed Solution

Transform AIKit's streaming API to automatically track messages during streaming, matching Vercel AI SDK's pattern where the framework handles message creation and formatting transparently.

### Key Changes

1. **StreamTextResult Wrapper**
   - Wraps the underlying stream while preserving streaming capabilities
   - Automatically tracks text, tool calls, and tool results
   - Provides access to properly formatted messages

2. **Automatic Message Tracking**
   - Framework creates assistant messages when content arrives
   - Tool calls are automatically included in assistant messages
   - Tool results become separate messages
   - Proper message ordering is maintained

3. **Simplified API**
   - No new public methods - existing `streamText` returns enhanced result
   - Backward compatible - can still iterate over chunks
   - Access formatted messages via `result.messages`

### Implementation Details

```swift
// New StreamTextResult type
public final class StreamTextResult {
    // Stream for real-time chunks
    public var textStream: AsyncThrowingStream<TextChunk, Error>
    
    // Accumulated properties
    public var text: String { get async }
    public var messages: [Message] { get async }
    public var usage: TokenUsage? { get async }
    public var finishReason: FinishReason? { get async }
    public var toolCalls: [ToolCall] { get async }
    public var toolResults: [ToolResult] { get async }
}

// Internal message tracking (actor-based for thread safety)
internal actor StreamingMessageTracker {
    func appendText(_ text: String)
    func addToolCall(_ toolCall: ToolCall)
    func addToolResult(_ toolResult: ToolResult)
    var responseMessages: [Message] { get }
}
```

### Usage After Implementation

```swift
// Simplified approach - framework handles everything
private func streamAIResponse(for conversation: ChatConversation) async throws {
    let result = client.streamText(model, messages: messages, tools: tools)
    
    // Stream chunks as before
    for try await chunk in result.textStream {
        // Update UI with streaming text
        updateUI(chunk.delta)
    }
    
    // Get properly formatted messages - no manual tracking needed!
    let responseMessages = await result.messages
    conversation.messages.append(contentsOf: responseMessages)
}
```

## Benefits

1. **Dramatically Simplified Client Code**
   - No manual message creation
   - No tracking of tool calls
   - No complex message formatting logic

2. **Consistency**
   - All applications get correctly formatted messages
   - Matches Vercel AI SDK patterns
   - Reduces bugs from incorrect message handling

3. **Better Developer Experience**
   - Intuitive API - just access `messages` property
   - Framework handles the complexity
   - Less code to write and maintain

4. **Thread Safety**
   - Actor-based implementation ensures thread safety
   - No race conditions during concurrent access

## Migration Path

The changes are backward compatible:

1. Existing code can continue to work by accessing `result.textStream`
2. New code can leverage `result.messages` for simplified handling
3. No breaking changes to public API

## Implementation Status

- ✅ Created `StreamingMessageTracker` actor for thread-safe message tracking
- ✅ Created `StreamTextResult` wrapper type
- ✅ Updated `streamText` methods to return `StreamTextResult`
- ✅ Comprehensive unit tests
- ⏳ Ready for review and integration

## Alternatives Considered

1. **Add separate method like `streamTextWithMessages`**
   - Rejected: Adds API complexity, confuses users about which method to use

2. **Return tuple `(stream, messages)`**
   - Rejected: Less elegant, doesn't allow for other accumulated properties

3. **Callback-based approach**
   - Rejected: Doesn't match Swift's async/await patterns

## Conclusion

This change brings AIKit's streaming API up to par with modern AI SDKs by handling message tracking automatically. It significantly reduces the complexity of client code while maintaining backward compatibility.