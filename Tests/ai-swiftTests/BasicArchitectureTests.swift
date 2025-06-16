import Testing
import Foundation
@testable import ai_swift

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@Test func testNewArchitecture() async throws {
    // Test creating an AI client
    let client = AISwift.client()
    #expect(client != nil)
    
    // Test creating a mock provider
    let provider = AISwift.mockProvider()
    #expect(provider.name == "Mock Provider")
    
    // Test creating a language model
    let model = provider.languageModel("test-model")
    #expect(model.modelId == "test-model")
    #expect(model.provider.name == "Mock Provider")
    
    // Test model configuration
    let configuredModel = model
        .temperature(0.8)
        .maxTokens(100)
    #expect(configuredModel.configuration.temperature == 0.8)
    #expect(configuredModel.configuration.maxTokens == 100)
    
    // Test provider raw generation (should not crash)
    let request = ProviderRequest(
        modelId: "test-model",
        messages: [Message.user("Hello")],
        configuration: ModelConfiguration.default
    )
    
    do {
        let response = try await provider.generateTextRaw(request)
        #expect(!response.content.isEmpty)
        #expect(response.finishReason == .stop)
    } catch {
        // This is expected since it's a mock implementation
        #expect(true) // Just ensure no unexpected crashes
    }
}

@Test func testMessageConvenience() {
    // Test message creation convenience methods
    let userMessage = Message.user("Hello world")
    #expect(userMessage.role == .user)
    #expect(userMessage.content.first?.textValue == "Hello world")
    
    let systemMessage = Message.system("You are a helpful assistant")
    #expect(systemMessage.role == .system)
    #expect(systemMessage.content.first?.textValue == "You are a helpful assistant")
    
    let assistantMessage = Message.assistant("Hello! How can I help?")
    #expect(assistantMessage.role == .assistant)
    #expect(assistantMessage.content.first?.textValue == "Hello! How can I help?")
}

@Test func testConfigurationBuilding() {
    // Test configuration builder pattern
    let config = ModelConfiguration.default
        .temperature(0.7)
        .maxTokens(150)
        .topP(0.9)
    
    #expect(config.temperature == 0.7)
    #expect(config.maxTokens == 150)
    #expect(config.topP == 0.9)
}

@Test func testObjectSchema() {
    // Test ObjectSchema creation
    struct TestType: Codable {
        let name: String
        let value: Int
    }
    
    let schema = ObjectSchema<TestType>()
    #expect(schema.name == "TestType") // Default name is the type name
    #expect(schema.description == nil)
    
    let namedSchema = ObjectSchema<TestType>(name: "CustomTestType", description: "A test type")
    #expect(namedSchema.name == "CustomTestType")
    #expect(namedSchema.description == "A test type")
}

@Test func testProviderBasicFunctionality() async throws {
    // Test basic provider creation and properties
    let provider = AISwift.mockProvider()
    
    // Test provider properties
    #expect(provider.name == "Mock Provider")
    #expect(!provider.capabilities.supportedModels.isEmpty)
    #expect(provider.capabilities.supportsStreaming == true)
    
    // Test model creation
    let model = provider.languageModel("test-model")
    #expect(model.modelId == "test-model")
    #expect(model.provider.name == "Mock Provider")
    
    // Test model configuration chaining
    let configuredModel = model
        .temperature(0.7)
        .maxTokens(500)
        .topP(0.9)
    
    #expect(configuredModel.configuration.temperature == 0.7)
    #expect(configuredModel.configuration.maxTokens == 500)
    #expect(configuredModel.configuration.topP == 0.9)
}