import Testing
import Foundation
@testable import AIKit

@Test func testStreamCancellationWithTask() async throws {
    // Test stream cancellation via Task cancellation
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let task = Task {
        let result = await client.streamText(model, prompt: "Generate a very long response")
        
        var chunkCount = 0
        for try await _ in result.textStream {
            chunkCount += 1
            // This should be interrupted by task cancellation
        }
        
        return chunkCount
    }
    
    // Cancel the task after a short delay
    try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
    task.cancel()
    
    do {
        let result = try await task.value
        // Task should have been cancelled before completion
        #expect(result < 100, "Task should have been cancelled early")
    } catch is CancellationError {
        // This is expected - cancellation should throw CancellationError
        #expect(Bool(true), "Expected cancellation error")
    }
}

@Test func testStreamInterruptionViaBreak() async throws {
    // Test stream interruption via loop break (existing functionality)
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let result = await client.streamText(model, prompt: "Generate a response")
    
    var chunkCount = 0
    let maxChunks = 3
    
    // Early termination to test interruption
    for try await _ in result.textStream {
        chunkCount += 1
        if chunkCount >= maxChunks {
            break // This should cleanly interrupt the stream
        }
    }
    
    #expect(chunkCount == maxChunks, "Should interrupt stream correctly via break")
}

@Test func testStreamCancellationCleanup() async throws {
    // Test that cancelled streams clean up properly
    let client = AIClient()
    let config = MockConfiguration(chunkDelay: 0.02) // Add delay to make cancellation possible
    let provider = MockProvider(configuration: config)
    let model = provider.languageModel("gpt-4.1-nano")
    
    let flag = CancellationFlag()

    let task = Task<Void, Error> { @MainActor in
        do {
            let result = await client.streamText(model, prompt: "Test cancellation cleanup Generate a longer response with many words to ensure multiple chunks")

            for try await _ in result.textStream {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        } catch is CancellationError {
            await flag.mark()
            throw CancellationError()
        }
    }
    
    // Give the stream a moment to start, then cancel
    try await Task.sleep(nanoseconds: 30_000_000) // 0.03 seconds
    task.cancel()
    
    do {
        try await task.value
        #expect(Bool(false), "Task should have thrown CancellationError")
    } catch is CancellationError {
        let wasCancelled = await flag.value
        #expect(wasCancelled, "Stream should have detected cancellation")
    }
}

@Test func testConcurrentStreamCancellation() async throws {
    // Test cancelling multiple streams concurrently
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let tasks = (0..<3).map { index in
        Task {
            let result = await client.streamText(model, prompt: "Stream \(index)")
            var count = 0
            
            for try await _ in result.textStream {
                count += 1
                try await Task.sleep(nanoseconds: 5_000_000) // 0.005 seconds
            }
            
            return count
        }
    }
    
    // Cancel all tasks after a short delay
    try await Task.sleep(nanoseconds: 20_000_000) // 0.02 seconds
    tasks.forEach { $0.cancel() }
    
    var cancelledTasks = 0
    for task in tasks {
        do {
            let _ = try await task.value
        } catch is CancellationError {
            cancelledTasks += 1
        }
    }
    
    #expect(cancelledTasks > 0, "At least some tasks should have been cancelled")
}

private actor CancellationFlag {
    private(set) var value = false

    func mark() {
        value = true
    }
}
