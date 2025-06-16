import Testing
import Foundation
@testable import AISwift

@Test func testBasicTextGeneration() async throws {
    // Test basic text generation functionality using provider directly
    let provider = AISwift.mockProvider()
    
    // Test simple text generation
    let request = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("Hello world")],
        configuration: ModelConfiguration.default
    )
    
    let response = try await provider.generateTextRaw(request)
    
    // Verify response structure
    #expect(!response.content.isEmpty)
    #expect(response.usage.totalTokens > 0)
    #expect(response.usage.promptTokens > 0)
    #expect(response.usage.completionTokens > 0)
    #expect(response.finishReason == .stop)
    
    // Test with system message
    let systemRequest = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [
            Message.system("You are a helpful assistant"),
            Message.user("What is 2+2?")
        ],
        configuration: ModelConfiguration.default
    )
    
    let systemResponse = try await provider.generateTextRaw(systemRequest)
    #expect(!systemResponse.content.isEmpty)
    #expect(systemResponse.usage.totalTokens > 0)
}

@Test func testConversationHistory() async throws {
    // Test conversation history handling with multiple messages
    let provider = AISwift.mockProvider()
    
    // Create a conversation with multiple turns
    let conversationMessages = [
        Message.system("You are a helpful math tutor."),
        Message.user("What is 2 + 2?"),
        Message.assistant("2 + 2 equals 4."),
        Message.user("What about 3 + 3?"),
    ]
    
    let request = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: conversationMessages,
        configuration: ModelConfiguration.default
    )
    
    let response = try await provider.generateTextRaw(request)
    
    // Verify response handles conversation context
    #expect(!response.content.isEmpty)
    #expect(response.usage.totalTokens > 0)
    #expect(response.finishReason == .stop)
    
    // Verify metadata includes conversation context
    #expect(response.providerMetadata?["model_id"] == "mock-gpt-4")
    
    // Test conversation history affects token usage
    let singleMessageRequest = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("What is 2 + 2?")],
        configuration: ModelConfiguration.default
    )
    
    let singleResponse = try await provider.generateTextRaw(singleMessageRequest)
    
    // Conversation should use more prompt tokens than single message
    #expect(response.usage.promptTokens >= singleResponse.usage.promptTokens)
}

@Test func testCustomParameterConfiguration() async throws {
    // Test various parameter configurations and their impact on generation
    let provider = AISwift.mockProvider()
    
    // Test with different temperature settings
    let creativeCconfiguration = ModelConfiguration.default
        .temperature(0.9)
        .topP(0.95)
        .frequencyPenalty(0.5)
        .presencePenalty(0.3)
        .maxTokens(200)
    
    let creativeRequest = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("Write a creative story")],
        configuration: creativeCconfiguration
    )
    
    let creativeResponse = try await provider.generateTextRaw(creativeRequest)
    #expect(!creativeResponse.content.isEmpty)
    #expect(creativeResponse.usage.totalTokens > 0)
    
    // Test with conservative settings
    let conservativeConfiguration = ModelConfiguration.default
        .temperature(0.1)
        .topP(0.1)
        .maxTokens(50)
    
    let conservativeRequest = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("What is 2+2?")],
        configuration: conservativeConfiguration
    )
    
    let conservativeResponse = try await provider.generateTextRaw(conservativeRequest)
    #expect(!conservativeResponse.content.isEmpty)
    
    // Test with stop sequences
    let stopsConfiguration = ModelConfiguration.default
        .stopSequences([".", "!", "?"])
        .maxTokens(100)
    
    let stopsRequest = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("Count to 10")],
        configuration: stopsConfiguration
    )
    
    let stopsResponse = try await provider.generateTextRaw(stopsRequest)
    #expect(!stopsResponse.content.isEmpty)
    
    // Test with seed for reproducibility
    let seededConfiguration = ModelConfiguration.default
        .seed(12345)
        .temperature(0.5)
    
    let seededRequest = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("Generate a random number")],
        configuration: seededConfiguration
    )
    
    let seededResponse = try await provider.generateTextRaw(seededRequest)
    #expect(!seededResponse.content.isEmpty)
    #expect(seededResponse.finishReason == .stop)
}

@Test func testAIClientTextGeneration() async throws {
    // TRUE TDD: This test should FAIL first, then we implement to make it pass
    let client = AISwift.client()
    let provider = AISwift.mockProvider()
    let model = provider.languageModel("mock-gpt-4")
    
    // This will fail until we implement AIClient.generateText
    let response = try await client.generateText(model, prompt: "Hello world")
    
    // Verify the expected behavior once implemented
    #expect(!response.text.isEmpty)
    #expect(response.usage.totalTokens > 0)
    #expect(response.finishReason == .stop)
    #expect(!response.messages.isEmpty)
    #expect(response.messages.last?.role == .assistant)
}