# Streaming

This guide covers real-time text streaming with AIKit, allowing you to process AI responses as they're generated.

## Overview

Streaming enables real-time processing of AI responses, providing immediate feedback to users and allowing for responsive user interfaces. Instead of waiting for the complete response, you receive chunks of text as they're generated.

## Basic Streaming

### Simple Stream

```swift
import AIKit

let provider = OpenAIProvider(apiKey: "your-api-key")
let model = provider.languageModel("gpt-4")
let client = AIKit.client()

let stream = client.streamText(model, prompt: "Write a story about a brave knight")

for try await chunk in stream {
    print(chunk.delta, terminator: "")
}
```

### Stream with Configuration

```swift
let model = provider.languageModel("gpt-4")
    .temperature(0.8)
    .maxTokens(1000)
    .stopSequences(["THE END"])

let stream = client.streamText(
    model,
    prompt: "Write a short story and end with 'THE END'"
)

for try await chunk in stream {
    print(chunk.delta, terminator: "")
    
    // Check if generation finished
    if let finishReason = chunk.finishReason {
        print("\\nFinished: \\(finishReason)")
        break
    }
}
```

## Stream Types

### TextStream
The primary streaming interface for text generation:

```swift
let stream: TextStream = client.streamText(model, prompt: "Hello")

// Stream provides AsyncSequence of StreamChunk
for try await chunk in stream {
    print("Delta: \\(chunk.delta)")
    print("Usage: \\(chunk.usage)")
}
```

### StreamChunk Structure

```swift
struct StreamChunk {
    let delta: String              // New text since last chunk
    let usage: Usage?              // Token usage (may be nil for intermediate chunks)
    let finishReason: FinishReason? // Why generation stopped (only in final chunk)
    let metadata: [String: Any]    // Provider-specific data
}
```

## Advanced Streaming Patterns

### Collecting Full Text

```swift
let stream = client.streamText(model, prompt: "Explain Swift optionals")

// Collect all text while streaming
var fullText = ""
for try await chunk in stream {
    fullText += chunk.delta
    print(chunk.delta, terminator: "")
}

print("\\nFull response: \\(fullText)")
```

### Stream with Error Handling

```swift
do {
    let stream = client.streamText(model, prompt: "Hello")
    
    for try await chunk in stream {
        print(chunk.delta, terminator: "")
        
        // Handle potential finish reasons
        if let finishReason = chunk.finishReason {
            switch finishReason {
            case .stop:
                print("\\nCompleted successfully")
            case .length:
                print("\\nReached token limit")
            case .contentFilter:
                print("\\nContent was filtered")
            case .toolCalls:
                print("\\nStopped for tool execution")
            }
        }
    }
} catch AIError.rateLimitExceeded(let retryAfter) {
    print("Rate limited. Retry after \\(retryAfter) seconds")
} catch {
    print("Streaming error: \\(error)")
}
```

## UI Integration

### SwiftUI Integration

```swift
import SwiftUI
import AIKit

struct StreamingView: View {
    @State private var streamedText = ""
    @State private var isStreaming = false
    
    let client = AIKit.client()
    let model: LanguageModel
    
    var body: some View {
        VStack {
            ScrollView {
                Text(streamedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            
            Button("Start Streaming") {
                Task {
                    await startStreaming()
                }
            }
            .disabled(isStreaming)
        }
    }
    
    private func startStreaming() async {
        isStreaming = true
        streamedText = ""
        
        do {
            let stream = client.streamText(
                model,
                prompt: "Write a detailed explanation of Swift async/await"
            )
            
            for try await chunk in stream {
                await MainActor.run {
                    streamedText += chunk.delta
                }
            }
        } catch {
            await MainActor.run {
                streamedText = "Error: \\(error.localizedDescription)"
            }
        }
        
        isStreaming = false
    }
}
```

### UIKit Integration

```swift
import UIKit
import AIKit

class StreamingViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var streamButton: UIButton!
    
    let client = AIKit.client()
    let model: LanguageModel
    
    @IBAction func startStreaming(_ sender: UIButton) {
        Task {
            await performStreaming()
        }
    }
    
    private func performStreaming() async {
        await MainActor.run {
            streamButton.isEnabled = false
            textView.text = ""
        }
        
        do {
            let stream = client.streamText(
                model,
                prompt: "Explain iOS app architecture patterns"
            )
            
            for try await chunk in stream {
                await MainActor.run {
                    textView.text += chunk.delta
                    
                    // Auto-scroll to bottom
                    let bottom = NSMakeRange(textView.text.count - 1, 1)
                    textView.scrollRangeToVisible(bottom)
                }
            }
        } catch {
            await MainActor.run {
                textView.text = "Error: \\(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            streamButton.isEnabled = true
        }
    }
}
```

## Stream Processing Utilities

### Stream Transformations

```swift
extension TextStream {
    /// Collect only the text deltas, ignoring metadata
    func deltas() -> AsyncMapSequence<TextStream, String> {
        return self.map { $0.delta }
    }
    
    /// Collect the full text from the stream
    func collectText() async throws -> String {
        var fullText = ""
        for try await chunk in self {
            fullText += chunk.delta
        }
        return fullText
    }
    
    /// Filter chunks based on a condition
    func filter(_ predicate: @escaping (StreamChunk) -> Bool) -> AsyncFilterSequence<TextStream> {
        return self.filter(predicate)
    }
}

// Usage
let stream = client.streamText(model, prompt: "Hello")

// Get only deltas
for try await delta in stream.deltas() {
    print(delta, terminator: "")
}

// Collect full text
let fullText = try await stream.collectText()
```

### Buffered Streaming

```swift
actor StreamBuffer {
    private var buffer: String = ""
    private let flushSize: Int
    
    init(flushSize: Int = 50) {
        self.flushSize = flushSize
    }
    
    func add(_ delta: String) -> String? {
        buffer += delta
        
        if buffer.count >= flushSize {
            let result = buffer
            buffer = ""
            return result
        }
        
        return nil
    }
    
    func flush() -> String {
        let result = buffer
        buffer = ""
        return result
    }
}

// Usage
let buffer = StreamBuffer(flushSize: 100)
let stream = client.streamText(model, prompt: "Write a long essay")

for try await chunk in stream {
    if let bufferedText = await buffer.add(chunk.delta) {
        // Process buffered text
        updateUI(with: bufferedText)
    }
}

// Process remaining buffer
let remaining = await buffer.flush()
if !remaining.isEmpty {
    updateUI(with: remaining)
}
```

## Message-Based Streaming

### Streaming Conversations

```swift
let messages = [
    Message.system("You are a helpful assistant"),
    Message.user("Tell me about Swift concurrency"),
    Message.assistant("Swift concurrency includes async/await..."),
    Message.user("Can you elaborate on actors?")
]

let stream = client.streamText(model, messages: messages)

for try await chunk in stream {
    print(chunk.delta, terminator: "")
}
```

### Building Conversational Interfaces

```swift
class ConversationManager {
    private let client: AIClient
    private let model: LanguageModel
    private var messages: [Message] = []
    
    init(client: AIClient, model: LanguageModel) {
        self.client = client
        self.model = model
        
        // Add system message
        messages.append(Message.system("You are a helpful assistant"))
    }
    
    func sendMessage(_ text: String) -> TextStream {
        // Add user message
        messages.append(Message.user(text))
        
        // Stream response
        let stream = client.streamText(model, messages: messages)
        
        // Collect assistant response for message history
        Task {
            var assistantResponse = ""
            for try await chunk in stream {
                assistantResponse += chunk.delta
            }
            messages.append(Message.assistant(assistantResponse))
        }
        
        return stream
    }
}
```

## Performance Optimization

### Concurrent Streaming

```swift
// Stream multiple responses concurrently
let prompts = [
    "Explain async/await",
    "Describe actors in Swift",
    "What are Task groups?"
]

await withTaskGroup(of: Void.self) { group in
    for prompt in prompts {
        group.addTask {
            let stream = client.streamText(model, prompt: prompt)
            for try await chunk in stream {
                print("[\\(prompt)]: \\(chunk.delta)", terminator: "")
            }
        }
    }
}
```

### Stream Cancellation

```swift
let task = Task {
    let stream = client.streamText(model, prompt: "Write a very long story")
    
    for try await chunk in stream {
        print(chunk.delta, terminator: "")
        
        // Check for cancellation
        if Task.isCancelled {
            break
        }
    }
}

// Cancel after 5 seconds
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    task.cancel()
}
```

## Error Handling in Streams

### Stream-Specific Errors

```swift
do {
    let stream = client.streamText(model, prompt: "Hello")
    
    for try await chunk in stream {
        print(chunk.delta, terminator: "")
    }
} catch AIError.streamInterrupted(let reason) {
    print("Stream was interrupted: \\(reason)")
} catch AIError.rateLimitExceeded(let retryAfter) {
    print("Rate limited during streaming")
} catch {
    print("Streaming error: \\(error)")
}
```

### Graceful Degradation

```swift
func streamWithFallback(prompt: String) async throws -> String {
    do {
        // Try streaming first
        let stream = client.streamText(model, prompt: prompt)
        var result = ""
        
        for try await chunk in stream {
            result += chunk.delta
        }
        
        return result
        
    } catch {
        print("Streaming failed, falling back to regular generation")
        
        // Fallback to non-streaming
        let response = try await client.generateText(model, prompt: prompt)
        return response.text
    }
}
```

## Testing Streaming

### Unit Tests

```swift
import XCTest
@testable import AIKit

class StreamingTests: XCTestCase {
    func testBasicStreaming() async throws {
        let provider = MockProvider()
        let model = provider.languageModel("test-model")
        let client = AIKit.client()
        
        let stream = client.streamText(model, prompt: "Hello")
        
        var chunks: [StreamChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        
        XCTAssertFalse(chunks.isEmpty)
        
        let fullText = chunks.map { $0.delta }.joined()
        XCTAssertFalse(fullText.isEmpty)
    }
    
    func testStreamCancellation() async throws {
        let provider = MockProvider()
        let model = provider.languageModel("test-model")
        let client = AIKit.client()
        
        let task = Task {
            let stream = client.streamText(model, prompt: "Long text")
            
            for try await chunk in stream {
                if Task.isCancelled { break }
            }
        }
        
        // Cancel immediately
        task.cancel()
        
        // Should not throw
        _ = await task.result
    }
}
```

### Performance Tests

```swift
func testStreamingPerformance() async throws {
    let provider = OpenAIProvider(apiKey: "test-key")
    let model = provider.languageModel("gpt-3.5-turbo")
    let client = AIKit.client()
    
    let startTime = CFAbsoluteTimeGetCurrent()
    
    let stream = client.streamText(
        model,
        prompt: "Write a 500-word essay about Swift"
    )
    
    var firstChunkTime: CFAbsoluteTime?
    var chunkCount = 0
    
    for try await chunk in stream {
        if firstChunkTime == nil {
            firstChunkTime = CFAbsoluteTimeGetCurrent()
        }
        chunkCount += 1
    }
    
    let totalTime = CFAbsoluteTimeGetCurrent() - startTime
    let timeToFirstChunk = firstChunkTime! - startTime
    
    print("Time to first chunk: \\(timeToFirstChunk)s")
    print("Total time: \\(totalTime)s")
    print("Chunks received: \\(chunkCount)")
}
```

## Best Practices

### 1. Handle UI Updates on Main Thread

```swift
for try await chunk in stream {
    await MainActor.run {
        // Update UI here
        textView.text += chunk.delta
    }
}
```

### 2. Implement Proper Cancellation

```swift
let streamingTask = Task {
    let stream = client.streamText(model, prompt: prompt)
    
    for try await chunk in stream {
        guard !Task.isCancelled else { break }
        // Process chunk
    }
}

// Cancel when needed
streamingTask.cancel()
```

### 3. Monitor Token Usage

```swift
var totalTokens = 0

for try await chunk in stream {
    if let usage = chunk.usage {
        totalTokens = usage.totalTokens
    }
    
    // Warn if approaching limits
    if totalTokens > 3000 {
        print("Warning: High token usage")
    }
}
```

### 4. Buffer for Smooth Display

```swift
let buffer = StreamBuffer(flushSize: 50)

for try await chunk in stream {
    if let bufferedText = await buffer.add(chunk.delta) {
        updateUI(with: bufferedText)
    }
}
```

## Next Steps

- [Object Generation](object-generation.md) - Stream structured data
- [Tool Calling](tool-calling.md) - Stream with function calls
- [Middleware](middleware.md) - Transform streaming responses
- [Error Handling](error-handling.md) - Handle streaming errors