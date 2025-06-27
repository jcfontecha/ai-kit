import Testing
import Foundation
@testable import AIKit

@Test func testStreamCancellationWithTask() async throws {
    // Test stream cancellation via Task cancellation
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let task = Task {
        let stream = await client.streamText(model, prompt: "Generate a very long response")
        
        var chunkCount = 0
        for try await _ in stream {
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
    
    let stream = await client.streamText(model, prompt: "Generate a response")
    
    var chunkCount = 0
    let maxChunks = 3
    
    // Early termination to test interruption
    for try await _ in stream {
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
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    var streamWasCancelled = false
    
    let task = Task {
        do {
            let stream = await client.streamText(model, prompt: "Test cancellation cleanup")
            
            for try await _ in stream {
                // This loop should be interrupted by cancellation
                try await Task.sleep(nanoseconds: 1_000_000) // Small delay
            }
        } catch is CancellationError {
            streamWasCancelled = true
            throw CancellationError()
        }
    }
    
    // Cancel immediately
    task.cancel()
    
    do {
        try await task.value
        #expect(Bool(false), "Task should have thrown CancellationError")
    } catch is CancellationError {
        #expect(streamWasCancelled, "Stream should have detected cancellation")
    }
}

@Test func testConcurrentStreamCancellation() async throws {
    // Test cancelling multiple streams concurrently
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let tasks = (0..<3).map { index in
        Task {
            let stream = await client.streamText(model, prompt: "Stream \(index)")
            var count = 0
            
            for try await _ in stream {
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