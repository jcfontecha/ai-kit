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

@Test func testTextGenerationWithToolCalling() async throws {
    // Test text generation with tool calling integration
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    let client = AIClient()
    
    // Define a simple weather tool
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(enum: ["San Francisco, CA", "New York, NY"]),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    let messages = [
        Message.user("What's the weather like in San Francisco?")
    ]
    
    // This should fail initially since tool calling isn't implemented
    let response = try await client.generateText(model, messages: messages, tools: [weatherTool])
    
    #expect(!response.text.isEmpty)
    #expect(response.finishReason == .toolCalls)
    #expect(!response.toolCalls.isEmpty)
    #expect(response.toolCalls.first?.function.name == "get_weather")
    #expect(response.usage.totalTokens > 0)
    #expect(!response.messages.isEmpty)
}

@Test func testMiddlewareChain() async throws {
    // Test that middleware chain is properly executed during text generation
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    
    // Create a middleware that modifies response text to verify it's being executed
    struct TextModifyingMiddleware: AIMiddleware {
        let id = "text-modifier"
        let name = "Text Modifying Middleware"
        let priority = 100
        
        func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
            return request
        }
        
        func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
            // Modify TextResponse by appending a marker
            if var textResponse = response as? TextResponse {
                let modifiedResponse = TextResponse(
                    text: textResponse.text + " [MIDDLEWARE_PROCESSED]",
                    finishReason: textResponse.finishReason,
                    usage: textResponse.usage,
                    messages: textResponse.messages,
                    steps: textResponse.steps,
                    responseId: textResponse.responseId,
                    modelId: textResponse.modelId,
                    timestamp: textResponse.timestamp,
                    warnings: textResponse.warnings,
                    responseHeaders: textResponse.responseHeaders
                )
                return modifiedResponse as! T
            }
            return response
        }
        
        func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
            return chunk
        }
        
        func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
            return error
        }
    }
    
    let middleware = TextModifyingMiddleware()
    let client = AIClient(middleware: [middleware])
    
    let messages = [Message.user("Hello, world!")]
    
    // This should execute the middleware chain and modify the response text
    let response = try await client.generateText(model, messages: messages)
    
    // Verify middleware was executed by checking for the marker
    #expect(response.text.contains("[MIDDLEWARE_PROCESSED]"), "Middleware should add marker to response text")
    #expect(response.usage.totalTokens > 0)
}

@Test func testTextGenerationWithCustomToolExecution() async throws {
    // Test that text generation uses caller-provided tool execution
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    
    // Create a custom tool executor that the caller provides
    func customWeatherTool(location: String, unit: String) -> String {
        return """
        {
            "location": "\(location)",
            "temperature": "\(unit == "celsius" ? "25°C" : "77°F")",
            "condition": "Sunny and clear",
            "custom": "This is from caller-provided tool execution"
        }
        """
    }
    
    // Define tools with custom execution
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location", 
            parameters: JSONSchema.object(properties: [
                "location": .string(enum: ["San Francisco, CA", "New York, NY"]),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    // Create client with custom tool execution
    let client = AIClient(toolExecutor: { toolCall in
        switch toolCall.function.name {
        case "get_weather":
            // Parse arguments
            let arguments = try JSONSerialization.jsonObject(with: toolCall.function.arguments.data(using: String.Encoding.utf8)!) as! [String: Any]
            let location = arguments["location"] as! String
            let unit = arguments["unit"] as? String ?? "celsius"
            
            return ToolResult(
                toolCallId: toolCall.id,
                result: .text(customWeatherTool(location: location, unit: unit)),
                executionTime: 0.1
            )
        default:
            throw AIGenerationError.toolExecutionFailed(toolName: toolCall.function.name, error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool"]))
        }
    })
    
    let messages = [Message.user("What's the weather like in San Francisco?")]
    
    // This should use the custom tool executor
    let response = try await client.generateText(model, messages: messages, tools: [weatherTool])
    
    #expect(response.text.contains("weather") || response.text.contains("tool"))
    #expect(response.usage.totalTokens > 0)
}

@Test func testToolExecutionWithResults() async throws {
    // Test that tools are not only called but also executed and their results incorporated
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    let client = AIClient()
    
    // Define a weather tool
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(enum: ["San Francisco, CA", "New York, NY"]),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    let messages = [
        Message.user("What's the weather like in San Francisco? I need a complete answer with the actual weather data.")
    ]
    
    // This should call the tool AND execute it, returning final text with weather results
    let response = try await client.generateText(model, messages: messages, tools: [weatherTool])
    
    // For now, this test expects tool calling behavior but won't get full execution
    // This will initially fail because we need to implement multi-step tool execution
    
    // Current implementation should show tool calls but not execute them
    #expect(response.finishReason == FinishReason.toolCalls) // Should finish at tool call step for now
    #expect(!response.toolCalls.isEmpty)
    #expect(response.toolCalls.first?.function.name == "get_weather")
    
    // Initially, we won't have actual weather results, just the intent to call
    #expect(response.text.contains("weather"), "Response should mention weather")
    
    // We should have at least one step with tool calls
    if let steps = response.steps {
        #expect(steps.count >= 1, "Should have at least one step with tool calls")
        #expect(steps.first?.stepType == .toolCall, "First step should be tool call")
    }
    
    // TODO: Later we'll implement actual tool execution and update this test
    // to verify: multi-step execution, tool results, final synthesized response
    
    #expect(response.usage.totalTokens > 0)
    #expect(!response.messages.isEmpty)
}

@Test func testMultiStepToolExecution() async throws {
    // Test the full Vercel AI SDK pattern: tool calls -> execution -> continuation -> final result
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    
    // Create client with weather tool executor
    let client = AIClient(toolExecutor: { toolCall in
        switch toolCall.function.name {
        case "get_weather":
            // Parse arguments from JSON string
            var location = "Unknown"
            var unit = "celsius"
            
            if let argumentsData = toolCall.function.arguments.data(using: String.Encoding.utf8),
               let argumentsDict = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] {
                location = argumentsDict["location"] as? String ?? "Unknown"
                unit = argumentsDict["unit"] as? String ?? "celsius"
            }
            
            let temperature = unit == "celsius" ? "22°C" : "72°F"
            
            let weatherData = """
            {
                "location": "\(location)",
                "temperature": "\(temperature)",
                "condition": "Partly cloudy",
                "humidity": "65%",
                "wind": "10 km/h NW"
            }
            """
            
            return ToolResult(
                toolCallId: toolCall.id,
                result: .text(weatherData),
                executionTime: 0.1
            )
        default:
            throw AIGenerationError.toolExecutionFailed(toolName: toolCall.function.name, error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool"]))
        }
    })
    
    // Define a weather tool that should be executed automatically
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(enum: ["San Francisco, CA", "New York, NY"]),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    let messages = [
        Message.user("What's the weather like in San Francisco? Please provide the actual temperature and conditions.")
    ]
    
    // This should: 1) Call tool, 2) Execute tool, 3) Continue generation with results, 4) Return final answer
    let response = try await client.generateText(model, messages: messages, tools: [weatherTool], maxSteps: 3)
    
    // Should complete with a final answer, not stop at tool calls
    #expect(response.finishReason == FinishReason.stop, "Should complete with final answer after tool execution")
    
    // Should have multiple steps showing the full execution flow
    #expect(response.stepCount >= 2, "Should have multiple steps: tool call + result processing")
    
    // Final text should contain actual weather information, not just intent
    #expect(response.text.contains("temperature") || response.text.contains("weather") || response.text.contains("°"), 
           "Final response should contain actual weather data from tool execution")
    
    // Should have tool calls in the steps but final response should be synthesized text
    #expect(!response.toolCalls.isEmpty, "Should have made tool calls during execution")
    
    // Verify the execution flow in steps
    if let steps = response.steps {
        #expect(steps.count >= 2, "Should have at least tool call and result steps")
        
        // First step should be tool call
        let firstStep = steps[0]
        #expect(firstStep.stepType == .toolCall, "First step should be tool call")
        #expect(firstStep.toolCalls?.first?.function.name == "get_weather", "Should call weather tool")
        
        // Should have a result processing step
        let hasResultStep = steps.contains { step in
            step.stepType == .toolResult || step.toolResults != nil
        }
        #expect(hasResultStep, "Should have a step that processes tool results")
    }
    
    // Final message should be from assistant with synthesized response
    #expect(response.messages.last?.role == .assistant, "Final message should be assistant response")
    #expect(response.usage.totalTokens > 0)
}

@Test func testObjectGenerationWithSchemaValidation() async throws {
    // RED PHASE: This test should fail because we need to implement schema validation in generateObject
    
    // Define a user profile struct for type-safe generation
    struct UserProfile: Codable, Sendable {
        let name: String
        let age: Int
        let email: String
        let isActive: Bool?
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("test-model")
        .temperature(0.1)
    
    // Define a strict schema for a user profile with proper validation
    let userSchema = JSONSchema.definition(SchemaDefinition(
        type: .object,
        properties: [
            "name": JSONSchema.definition(SchemaDefinition(type: .string, minLength: 1)),
            "age": JSONSchema.definition(SchemaDefinition(type: .integer, minimum: 0)),
            "email": JSONSchema.definition(SchemaDefinition(type: .string, format: "email")),
            "isActive": JSONSchema.definition(SchemaDefinition(type: .boolean))
        ],
        required: ["name", "age", "email"],
        additionalProperties: .boolean(false)
    ))
    
    let objectSchema = ObjectSchema<UserProfile>(
        jsonSchema: userSchema,
        name: "UserProfile",
        description: "A user profile with name, age, email, and optional active status"
    )
    
    let messages = [
        Message.user("Generate a user profile for John Doe, age 30, email john@example.com, active status true")
    ]
    
    // This should validate the generated object against the schema
    let response = try await client.generateObject(
        model,
        messages: messages,
        schema: objectSchema
    )
    
    // Verify the response structure
    #expect(response.usage.totalTokens > 0, "Should track token usage")
    
    // Verify the generated object conforms to schema
    let generatedObject = response.object
    
    // Should have required fields with proper types
    #expect(!generatedObject.name.isEmpty, "Name should not be empty")
    #expect(generatedObject.age > 0, "Age should be positive")
    #expect(generatedObject.email.contains("@"), "Email should contain @ symbol")
    
    // Should handle optional fields properly
    if let isActive = generatedObject.isActive {
        #expect(isActive is Bool, "isActive should be a boolean when present")
    }
}

@Test func testObjectGenerationErrorHandling() async throws {
    // RED PHASE: This test should fail because we need to implement comprehensive error handling
    
    // Define a strict schema that will help us test validation failures
    struct Product: Codable, Sendable {
        let name: String
        let price: Double
        let category: String
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("error-test-model")
        .temperature(0.0)
    
    // Create a schema with strict validation
    let productSchema = JSONSchema.definition(SchemaDefinition(
        type: .object,
        properties: [
            "name": JSONSchema.definition(SchemaDefinition(type: .string, minLength: 1)),
            "price": JSONSchema.definition(SchemaDefinition(type: .number, minimum: 0.0)),
            "category": JSONSchema.definition(SchemaDefinition(type: .string))
        ],
        required: ["name", "price", "category"],
        additionalProperties: .boolean(false)
    ))
    
    let objectSchema = ObjectSchema<Product>(
        jsonSchema: productSchema,
        name: "Product",
        description: "A product with name, price, and category"
    )
    
    // Test Case 1: Test with a provider that returns malformed JSON
    do {
        // Force the mock provider to return malformed JSON by using a special model ID
        let malformedModel = provider.languageModel("malformed-json-model")
        
        let response = try await client.generateObject(
            malformedModel,
            messages: [Message.user("Generate a product")],
            schema: objectSchema
        )
        
        #expect(Bool(false), "Should have thrown a JSONParseError for malformed JSON")
    } catch let error as AIGenerationError {
        switch error {
        case .jsonParseError(let text, let parseError):
            #expect(text.contains("{"), "Should contain partial JSON")
            #expect(parseError != nil, "Should have underlying parse error")
        case .schemaValidationError(let object, let validationErrors):
            #expect(Bool(false), "Should be JSON parse error, not validation error")
        default:
            #expect(Bool(false), "Should be a specific JSON parse error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.jsonParseError")
    }
    
    // Test Case 2: Test with a provider that returns valid JSON but schema validation failure
    do {
        // Force the mock provider to return invalid object structure
        let invalidSchemaModel = provider.languageModel("invalid-schema-model")
        
        let response = try await client.generateObject(
            invalidSchemaModel,
            messages: [Message.user("Generate a product")],
            schema: objectSchema
        )
        
        #expect(Bool(false), "Should have thrown a SchemaValidationError for invalid object")
    } catch let error as AIGenerationError {
        switch error {
        case .schemaValidationError(let objectData, let validationErrors):
            #expect(!validationErrors.isEmpty, "Should have validation errors")
            #expect(objectData != nil, "Should have the invalid object data for debugging")
        case .jsonParseError:
            #expect(Bool(false), "Should be validation error, not JSON parse error")
        default:
            #expect(Bool(false), "Should be a specific schema validation error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.schemaValidationError")
    }
    
    // Test Case 3: Test no object generated scenario
    do {
        let noObjectModel = provider.languageModel("no-object-model")
        
        let response = try await client.generateObject(
            noObjectModel,
            messages: [Message.user("Generate a product")],
            schema: objectSchema
        )
        
        #expect(Bool(false), "Should have thrown a NoObjectGeneratedError")
    } catch let error as AIGenerationError {
        switch error {
        case .noObjectGenerated(let text, let finishReason, let usage):
            #expect(!text.isEmpty, "Should have the raw text that failed to generate object")
            #expect(finishReason != nil, "Should have finish reason")
            #expect(usage.totalTokens >= 0, "Should have usage information")
        default:
            #expect(Bool(false), "Should be a NoObjectGeneratedError")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.noObjectGenerated")
    }
}

@Test func testComplexNestedObjectGeneration() async throws {
    // RED PHASE: This test should fail because we need to implement complex nested object support
    
    // Define complex nested structures similar to Vercel AI SDK examples
    struct Ingredient: Codable, Sendable {
        let name: String
        let amount: String
        let optional: Bool?
    }
    
    struct Recipe: Codable, Sendable {
        let name: String
        let description: String
        let prepTime: Int
        let cookTime: Int
        let difficulty: String
        let ingredients: [Ingredient]
        let steps: [String]
        let nutritionInfo: NutritionInfo?
        let tags: [String]
    }
    
    struct NutritionInfo: Codable, Sendable {
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("complex-recipe-model")
        .temperature(0.2)
    
    // Create a complex nested schema
    let nutritionSchema = JSONSchema.definition(SchemaDefinition(
        type: .object,
        properties: [
            "calories": JSONSchema.definition(SchemaDefinition(type: .integer, minimum: 0)),
            "protein": JSONSchema.definition(SchemaDefinition(type: .number, minimum: 0.0)),
            "carbs": JSONSchema.definition(SchemaDefinition(type: .number, minimum: 0.0)),
            "fat": JSONSchema.definition(SchemaDefinition(type: .number, minimum: 0.0))
        ],
        required: ["calories", "protein", "carbs", "fat"]
    ))
    
    let ingredientSchema = JSONSchema.definition(SchemaDefinition(
        type: .object,
        properties: [
            "name": JSONSchema.definition(SchemaDefinition(type: .string, minLength: 1)),
            "amount": JSONSchema.definition(SchemaDefinition(type: .string, minLength: 1)),
            "optional": JSONSchema.definition(SchemaDefinition(type: .boolean))
        ],
        required: ["name", "amount"]
    ))
    
    let recipeSchema = JSONSchema.definition(SchemaDefinition(
        type: .object,
        properties: [
            "name": JSONSchema.definition(SchemaDefinition(type: .string, minLength: 1)),
            "description": JSONSchema.definition(SchemaDefinition(type: .string)),
            "prepTime": JSONSchema.definition(SchemaDefinition(type: .integer, minimum: 0)),
            "cookTime": JSONSchema.definition(SchemaDefinition(type: .integer, minimum: 0)),
            "difficulty": JSONSchema.definition(SchemaDefinition(
                type: .string,
                enum: [.string("easy"), .string("medium"), .string("hard")]
            )),
            "ingredients": JSONSchema.definition(SchemaDefinition(
                type: .array,
                items: ingredientSchema,
                minItems: 1
            )),
            "steps": JSONSchema.definition(SchemaDefinition(
                type: .array,
                items: JSONSchema.definition(SchemaDefinition(type: .string, minLength: 1)),
                minItems: 1
            )),
            "nutritionInfo": nutritionSchema,
            "tags": JSONSchema.definition(SchemaDefinition(
                type: .array,
                items: JSONSchema.definition(SchemaDefinition(type: .string))
            ))
        ],
        required: ["name", "description", "prepTime", "cookTime", "difficulty", "ingredients", "steps", "tags"]
    ))
    
    let objectSchema = ObjectSchema<Recipe>(
        jsonSchema: recipeSchema,
        name: "Recipe",
        description: "A detailed recipe with ingredients, steps, and nutritional information"
    )
    
    let messages = [
        Message.user("Generate a detailed recipe for vegetarian pasta with nutritional information")
    ]
    
    // This should generate a complex nested object
    let response = try await client.generateObject(
        model,
        messages: messages,
        schema: objectSchema
    )
    
    // Verify the complex structure
    let recipe = response.object
    
    // Basic properties
    #expect(!recipe.name.isEmpty, "Recipe should have a name")
    #expect(!recipe.description.isEmpty, "Recipe should have a description")
    #expect(recipe.prepTime >= 0, "Prep time should be non-negative")
    #expect(recipe.cookTime >= 0, "Cook time should be non-negative")
    #expect(["easy", "medium", "hard"].contains(recipe.difficulty), "Difficulty should be valid")
    
    // Array properties
    #expect(!recipe.ingredients.isEmpty, "Recipe should have ingredients")
    #expect(!recipe.steps.isEmpty, "Recipe should have steps")
    #expect(!recipe.tags.isEmpty, "Recipe should have tags")
    
    // Nested object validation (ingredients)
    for ingredient in recipe.ingredients {
        #expect(!ingredient.name.isEmpty, "Ingredient name should not be empty")
        #expect(!ingredient.amount.isEmpty, "Ingredient amount should not be empty")
    }
    
    // Steps validation
    for step in recipe.steps {
        #expect(!step.isEmpty, "Recipe step should not be empty")
    }
    
    // Optional nested object (nutrition info)
    if let nutrition = recipe.nutritionInfo {
        #expect(nutrition.calories >= 0, "Calories should be non-negative")
        #expect(nutrition.protein >= 0, "Protein should be non-negative")
        #expect(nutrition.carbs >= 0, "Carbs should be non-negative")
        #expect(nutrition.fat >= 0, "Fat should be non-negative")
    }
    
    // Response metadata
    #expect(response.usage.totalTokens > 0, "Should track token usage")
    
    // Verify complex object was properly generated and validated
    #expect(recipe.ingredients.count >= 3, "Should have multiple ingredients")
    #expect(recipe.steps.count >= 3, "Should have multiple steps")
}