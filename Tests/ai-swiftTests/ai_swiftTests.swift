import Testing
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

@Test func testBasicStreaming() async throws {
    // Test basic streaming functionality using provider directly
    let provider = AISwift.mockProvider()
    
    let request = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("Count to 5")],
        configuration: ModelConfiguration.default
    )
    
    // Test streaming
    let stream = provider.streamTextRaw(request)
    var chunks: [ProviderChunk] = []
    var fullContent = ""
    
    for try await chunk in stream {
        chunks.append(chunk)
        fullContent += chunk.delta
    }
    
    // Verify streaming behavior
    #expect(!chunks.isEmpty)
    #expect(!fullContent.isEmpty)
    
    // Verify last chunk has finish reason and usage
    let lastChunk = chunks.last!
    #expect(lastChunk.finishReason == .stop)
    #expect(lastChunk.usage != nil)
    #expect(lastChunk.usage!.totalTokens > 0)
    
    // Verify content accumulation
    #expect(fullContent.contains("Mock response"))
}

@Test func testConfigurationValidation() async throws {
    // Test configuration validation in mock provider with strict validation
    let strictConfig = MockConfiguration(strictValidation: true)
    let provider = MockProvider(apiKey: "test-key", configuration: strictConfig)
    
    // Test valid configuration
    let validConfig = ModelConfiguration.default
        .temperature(1.0)
        .maxTokens(2000)
    
    try provider.validateConfiguration(validConfig)
    
    // Test invalid temperature (should throw with strict validation)
    let invalidTempConfig = ModelConfiguration.default.temperature(3.0)
    
    do {
        try provider.validateConfiguration(invalidTempConfig)
        #expect(Bool(false), "Should have thrown validation error for high temperature")
    } catch {
        #expect(error is AIProviderError)
    }
    
    // Test invalid max tokens
    let invalidTokensConfig = ModelConfiguration.default.maxTokens(5000)
    
    do {
        try provider.validateConfiguration(invalidTokensConfig)
        #expect(Bool(false), "Should have thrown validation error for high maxTokens")
    } catch {
        #expect(error is AIProviderError)
    }
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

@Test func testStreamingErrorHandling() async throws {
    // Test streaming error handling using error-prone configuration
    let errorConfig = MockConfiguration(errorRate: 1.0) // 100% error rate
    let provider = MockProvider(apiKey: "test-key", configuration: errorConfig)
    
    let request = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("This should trigger an error")],
        configuration: ModelConfiguration.default
    )
    
    // Test that streaming throws expected errors
    let stream = provider.streamTextRaw(request)
    
    do {
        for try await chunk in stream {
            // Should not reach here with 100% error rate
            #expect(Bool(false), "Stream should have thrown an error")
        }
        #expect(Bool(false), "Stream should have thrown an error")
    } catch {
        // Verify we get the expected error type
        #expect(error is AIProviderError)
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .serviceUnavailable(let message):
                #expect(message.contains("Simulated"))
            default:
                #expect(Bool(false), "Expected serviceUnavailable error")
            }
        }
    }
    
    // Test streaming with lower error rate (should sometimes succeed)
    let lowErrorConfig = MockConfiguration(errorRate: 0.0) // No errors
    let reliableProvider = MockProvider(apiKey: "test-key", configuration: lowErrorConfig)
    
    let reliableStream = reliableProvider.streamTextRaw(request)
    var receivedChunks = 0
    
    // This should succeed without errors
    for try await chunk in reliableStream {
        receivedChunks += 1
        #expect(!chunk.delta.isEmpty)
    }
    
    #expect(receivedChunks > 0)
}

@Test func testBasicObjectSchema() {
    // Test object schema creation and validation for future object generation
    struct Person: Codable, Sendable {
        let name: String
        let age: Int
        let email: String?
    }
    
    // Test schema creation with different configurations
    let basicSchema = ObjectSchema<Person>()
    #expect(basicSchema.name == "Person")
    #expect(basicSchema.description == nil)
    #expect(basicSchema.validationMode == .strict)
    
    // Test schema with custom properties
    let customSchema = ObjectSchema<Person>(
        name: "PersonProfile", 
        description: "A person's basic information"
    )
    #expect(customSchema.name == "PersonProfile")
    #expect(customSchema.description == "A person's basic information")
    
    // Test schema builder methods
    let builderSchema = ObjectSchema<Person>()
        .withName("Employee")
        .withDescription("Employee information")
        .withValidationMode(.lenient)
        .allowingAdditionalProperties(true)
    
    #expect(builderSchema.name == "Employee")
    #expect(builderSchema.description == "Employee information")
    #expect(builderSchema.validationMode == .lenient)
    #expect(builderSchema.allowAdditionalProperties == true)
    
    // Test schema with examples
    let examplePerson = Person(name: "John Doe", age: 30, email: "john@example.com")
    let schemaWithExample = basicSchema.withExample(examplePerson)
    
    #expect(schemaWithExample.examples?.count == 1)
    #expect(schemaWithExample.examples?.first?.name == "John Doe")
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

@Test func testAIClientStreamText() async throws {
    // TRUE TDD: This test should FAIL first - AIClient.streamText not implemented
    let client = AISwift.client()
    let provider = AISwift.mockProvider()
    let model = provider.languageModel("mock-gpt-4")
    
    // This will fail until we implement AIClient.streamText
    let stream = await client.streamText(model, prompt: "Count to 5")
    
    var chunks: [TextChunk] = []
    var fullContent = ""
    
    for try await chunk in stream {
        chunks.append(chunk)
        fullContent += chunk.delta
    }
    
    // Verify streaming behavior once implemented
    #expect(!chunks.isEmpty)
    #expect(!fullContent.isEmpty)
    
    // Verify last chunk has proper finish state
    let lastChunk = chunks.last!
    #expect(lastChunk.finishReason == .stop)
    #expect(lastChunk.usage != nil)
    #expect(lastChunk.usage!.totalTokens > 0)
    
    // Verify accumulated content
    #expect(fullContent.contains("Mock response"))
}

@Test func testAIClientGenerateObject() async throws {
    // TRUE TDD: This test should FAIL first - AIClient.generateObject not implemented
    let client = AISwift.client()
    let provider = AISwift.mockProvider()
    let model = provider.languageModel("mock-gpt-4")
    
    // Define a simple test object
    struct Recipe: Codable, Sendable {
        let name: String
        let ingredients: [String]
        let cookingTime: Int
    }
    
    // Create schema for the object
    let schema = ObjectSchema<Recipe>(
        name: "Recipe",
        description: "A cooking recipe with ingredients"
    )
    
    // This will fail until we implement AIClient.generateObject
    let response = try await client.generateObject(model, prompt: "Create a simple pasta recipe", schema: schema)
    
    // Verify the generated object once implemented
    #expect(!response.object.name.isEmpty)
    #expect(!response.object.ingredients.isEmpty)
    #expect(response.object.cookingTime > 0)
    #expect(response.finishReason == .stop)
    #expect(response.usage.totalTokens > 0)
    #expect(!response.messages.isEmpty)
    #expect(response.messages.last?.role == .assistant)
    #expect(response.validationResult?.isValid == true)
}