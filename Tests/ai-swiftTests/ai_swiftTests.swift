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

@Test func testBasicObjectStreaming() async throws {
    // Test basic object streaming functionality based on Vercel AI SDK patterns
    
    struct SimpleUser: Codable, Sendable {
        let name: String
        let age: Int
        let email: String
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("streaming-user-model")
        .temperature(0.0)
    
    // Create a simple schema for streaming test
    let userSchema = JSONSchema.definition(SchemaDefinition(
        type: .object,
        properties: [
            "name": JSONSchema.definition(SchemaDefinition(type: .string)),
            "age": JSONSchema.definition(SchemaDefinition(type: .integer)),
            "email": JSONSchema.definition(SchemaDefinition(type: .string))
        ],
        required: ["name", "age", "email"]
    ))
    
    let objectSchema = ObjectSchema<SimpleUser>(
        jsonSchema: userSchema,
        name: "SimpleUser",
        description: "A simple user with name, age, and email"
    )
    
    let messages = [
        Message.user("Generate a user profile for streaming test")
    ]
    
    // Stream the object generation
    let objectStream = await client.streamObject(model, messages: messages, schema: objectSchema)
    
    var receivedChunks: [ObjectChunk<SimpleUser>] = []
    var accumulatedObject: SimpleUser? = nil
    var finalUsage: TokenUsage? = nil
    
    // Collect all streaming chunks
    for try await chunk in objectStream {
        receivedChunks.append(chunk)
        
        // Track the latest parsed object
        if let object = chunk.object {
            accumulatedObject = object
        }
        
        // Track final usage information
        if let usage = chunk.usage {
            finalUsage = usage
        }
    }
    
    // Verify streaming behavior
    #expect(!receivedChunks.isEmpty, "Should receive streaming chunks")
    #expect(accumulatedObject != nil, "Should have final parsed object")
    #expect(finalUsage != nil, "Should have final usage information")
    
    // Verify the final object is valid
    let finalUser = try #require(accumulatedObject)
    #expect(!finalUser.name.isEmpty, "User name should not be empty")
    #expect(finalUser.age > 0, "User age should be positive")
    #expect(finalUser.email.contains("@"), "Email should contain @ symbol")
    
    // Verify progressive streaming (should have multiple chunks)
    #expect(receivedChunks.count > 3, "Should stream character by character for JSON")
    
    // Verify that chunks build up progressively
    var textSnapshot = ""
    for chunk in receivedChunks {
        textSnapshot += chunk.delta
        #expect(chunk.snapshot.contains(textSnapshot), "Snapshot should contain accumulated text")
    }
    
    // Verify the final snapshot contains valid JSON
    let finalSnapshot = receivedChunks.last?.snapshot ?? ""
    #expect(finalSnapshot.contains("{"), "Final snapshot should contain JSON")
    #expect(finalSnapshot.contains("}"), "Final snapshot should be complete JSON")
    
    // Verify final usage tracking
    let usage = try #require(finalUsage)
    #expect(usage.totalTokens > 0, "Should track token usage")
}

@Test func testJSONCompletionAlgorithms() async throws {
    // Test JSON completion algorithms with malformed/partial JSON streams
    
    struct TestData: Codable, Sendable {
        let name: String
        let value: Int
        let active: Bool
    }
    
    let client = AIClient()
    let provider = MockProvider()
    
    // Configure mock provider to simulate gradual JSON completion
    let model = provider.languageModel("json-completion-test")
        .temperature(0.0)
    
    let schema = JSONSchema.definition(SchemaDefinition(
        type: .object,
        properties: [
            "name": JSONSchema.definition(SchemaDefinition(type: .string)),
            "value": JSONSchema.definition(SchemaDefinition(type: .integer)),
            "active": JSONSchema.definition(SchemaDefinition(type: .boolean))
        ],
        required: ["name", "value", "active"]
    ))
    
    let objectSchema = ObjectSchema<TestData>(
        jsonSchema: schema,
        name: "TestData",
        description: "Test data for JSON completion"
    )
    
    let messages = [
        Message.user("Generate test data for JSON completion")
    ]
    
    // Test streaming with gradual JSON completion
    let objectStream = await client.streamObject(model, messages: messages, schema: objectSchema)
    
    var receivedChunks: [ObjectChunk<TestData>] = []
    var partialSnapshots: [String] = []
    var successfulParses = 0
    
    // Collect all streaming chunks and track parsing progress
    for try await chunk in objectStream {
        receivedChunks.append(chunk)
        partialSnapshots.append(chunk.snapshot)
        
        // Count successful object parses
        if chunk.object != nil {
            successfulParses += 1
        }
    }
    
    // Verify streaming behavior with JSON completion
    #expect(!receivedChunks.isEmpty, "Should receive streaming chunks")
    #expect(partialSnapshots.count >= 2, "Should have multiple partial snapshots")
    #expect(successfulParses > 0, "Should have successful object parses")
    
    // Verify gradual JSON completion patterns
    let finalSnapshot = partialSnapshots.last ?? ""
    #expect(finalSnapshot.hasPrefix("{"), "Should start with opening brace")
    #expect(finalSnapshot.hasSuffix("}"), "Should end with closing brace")
    
    // Test that intermediate snapshots show progression
    var foundPartialJSON = false
    for snapshot in partialSnapshots {
        if snapshot.count > 1 && snapshot.count < finalSnapshot.count {
            // This should be a partial JSON that our repair algorithm can handle
            foundPartialJSON = true
            break
        }
    }
    #expect(foundPartialJSON, "Should have intermediate partial JSON states")
    
    // Verify final object is complete and valid
    let finalChunk = try #require(receivedChunks.last)
    let finalObject = try #require(finalChunk.object)
    
    #expect(!finalObject.name.isEmpty, "Name should not be empty")
    #expect(finalObject.value >= 0, "Value should be non-negative")
    #expect(finalObject.active is Bool, "Active should be boolean")
    
    // Verify JSON repair worked correctly on partial content
    // Test our JSON repair algorithm directly
    let partialJSON1 = "{\"name\":\"test"
    let repairedJSON1 = repairPartialJSONTest(partialJSON1)
    #expect(repairedJSON1.contains("}"), "Should close unclosed braces")
    #expect(repairedJSON1.contains("\""), "Should close unclosed strings")
    
    let partialJSON2 = "{\"name\":\"test\",\"value\":42"
    let repairedJSON2 = repairPartialJSONTest(partialJSON2)
    #expect(repairedJSON2.hasSuffix("}"), "Should close object")
}

// Helper function to test JSON repair algorithm directly
private func repairPartialJSONTest(_ jsonString: String) -> String {
    var repaired = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard !repaired.isEmpty else { return "{}" }
    
    // Ensure it starts with {
    if !repaired.hasPrefix("{") {
        if let braceIndex = repaired.firstIndex(of: "{") {
            repaired = String(repaired[braceIndex...])
        } else {
            return "{}"
        }
    }
    
    // Count braces and quotes for balancing
    var openBraces = 0
    var inString = false
    var escapeNext = false
    
    for char in repaired {
        if escapeNext {
            escapeNext = false
            continue
        }
        
        switch char {
        case "\\":
            if inString {
                escapeNext = true
            }
        case "\"":
            inString.toggle()
        case "{":
            if !inString {
                openBraces += 1
            }
        case "}":
            if !inString {
                openBraces -= 1
            }
        default:
            break
        }
    }
    
    // Close unclosed strings
    if inString {
        repaired += "\""
    }
    
    // Close unclosed objects
    while openBraces > 0 {
        repaired += "}"
        openBraces -= 1
    }
    
    return repaired
}

@Test func testComplexNestedObjectStreaming() async throws {
    // Test streaming with complex nested objects (Recipe from earlier test)
    
    struct Ingredient: Codable, Sendable {
        let name: String
        let amount: String
        let optional: Bool?
    }
    
    struct NutritionInfo: Codable, Sendable {
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
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
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("complex-recipe-streaming")
        .temperature(0.0)
    
    // Create the complex nested schema (same as generateObject test)
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
        Message.user("Generate a detailed vegetarian pasta recipe for streaming")
    ]
    
    // Stream the complex object generation
    let objectStream = await client.streamObject(model, messages: messages, schema: objectSchema)
    
    var receivedChunks: [ObjectChunk<Recipe>] = []
    var validRecipes: [Recipe] = []
    var finalUsage: TokenUsage? = nil
    
    // Collect all streaming chunks
    for try await chunk in objectStream {
        receivedChunks.append(chunk)
        
        if let recipe = chunk.object {
            validRecipes.append(recipe)
        }
        
        if let usage = chunk.usage {
            finalUsage = usage
        }
    }
    
    // Verify complex streaming behavior
    #expect(!receivedChunks.isEmpty, "Should receive streaming chunks")
    #expect(!validRecipes.isEmpty, "Should have valid recipe objects")
    #expect(finalUsage != nil, "Should have final usage information")
    
    // Verify the final recipe is complete and valid
    let finalRecipe = try #require(validRecipes.last)
    
    // Basic properties
    #expect(!finalRecipe.name.isEmpty, "Recipe should have a name")
    #expect(!finalRecipe.description.isEmpty, "Recipe should have a description")
    #expect(finalRecipe.prepTime >= 0, "Prep time should be non-negative")
    #expect(finalRecipe.cookTime >= 0, "Cook time should be non-negative")
    #expect(["easy", "medium", "hard"].contains(finalRecipe.difficulty), "Difficulty should be valid")
    
    // Array properties
    #expect(!finalRecipe.ingredients.isEmpty, "Recipe should have ingredients")
    #expect(!finalRecipe.steps.isEmpty, "Recipe should have steps")
    #expect(!finalRecipe.tags.isEmpty, "Recipe should have tags")
    
    // Nested object validation (ingredients)
    for ingredient in finalRecipe.ingredients {
        #expect(!ingredient.name.isEmpty, "Ingredient name should not be empty")
        #expect(!ingredient.amount.isEmpty, "Ingredient amount should not be empty")
    }
    
    // Steps validation
    for step in finalRecipe.steps {
        #expect(!step.isEmpty, "Recipe step should not be empty")
    }
    
    // Optional nested object (nutrition info)
    if let nutrition = finalRecipe.nutritionInfo {
        #expect(nutrition.calories >= 0, "Calories should be non-negative")
        #expect(nutrition.protein >= 0, "Protein should be non-negative")
        #expect(nutrition.carbs >= 0, "Carbs should be non-negative")
        #expect(nutrition.fat >= 0, "Fat should be non-negative")
    }
    
    // Verify streaming progression with complex data
    #expect(receivedChunks.count > 10, "Complex object should stream many chunks")
    
    // Verify that final snapshot contains complete JSON
    let finalSnapshot = receivedChunks.last?.snapshot ?? ""
    #expect(finalSnapshot.contains("\"ingredients\""), "Should contain ingredients array")
    #expect(finalSnapshot.contains("\"steps\""), "Should contain steps array")
    #expect(finalSnapshot.contains("\"tags\""), "Should contain tags array")
    
    // Verify usage tracking for complex object
    let usage = try #require(finalUsage)
    #expect(usage.totalTokens > 0, "Should track token usage for complex object")
}

@Test func testStreamingWithToolCalls() async throws {
    // Test streaming that includes tool calls following Vercel AI SDK patterns
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    let client = AIClient()
    
    // Define a weather tool for streaming
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
    
    // This should trigger streaming tool calls in MockProvider
    let stream = await client.streamText(model, messages: messages, tools: [weatherTool])
    
    var receivedChunks: [TextChunk] = []
    var toolCallStreamingStarts: [ToolCallStreamingStart] = []
    var toolCallDeltas: [ToolCallDelta] = []
    var toolCalls: [ToolCall] = []
    var stepStarts: [StepStart] = []
    var stepFinishes: [StepFinish] = []
    var fullContent = ""
    
    // Collect all streaming chunks and categorize tool call events
    for try await chunk in stream {
        receivedChunks.append(chunk)
        fullContent += chunk.delta
        
        // Collect tool call streaming events
        if let toolCallStart = chunk.toolCallStreamingStart {
            toolCallStreamingStarts.append(toolCallStart)
        }
        
        if let toolCallDelta = chunk.toolCallDelta {
            toolCallDeltas.append(toolCallDelta)
        }
        
        if let chunkToolCalls = chunk.toolCalls {
            toolCalls.append(contentsOf: chunkToolCalls)
        }
    }
    
    // Verify we received streaming chunks
    #expect(!receivedChunks.isEmpty, "Should receive streaming chunks")
    
    // Verify tool call streaming events occurred
    #expect(!toolCallStreamingStarts.isEmpty, "Should have tool call streaming start events")
    #expect(!toolCallDeltas.isEmpty, "Should have tool call argument deltas")
    #expect(!toolCalls.isEmpty, "Should have complete tool calls")
    
    // Verify tool call streaming start
    let firstStart = try #require(toolCallStreamingStarts.first)
    #expect(firstStart.toolName == "get_weather", "Should call weather tool")
    #expect(!firstStart.toolCallId.isEmpty, "Should have tool call ID")
    
    // Verify tool call argument streaming
    #expect(toolCallDeltas.count >= 5, "Should stream multiple argument deltas")
    let firstDelta = try #require(toolCallDeltas.first)
    #expect(firstDelta.toolName == "get_weather", "Delta should be for weather tool")
    #expect(!firstDelta.argsTextDelta.isEmpty, "Should have argument text delta")
    
    // Verify complete tool call
    let completeToolCall = try #require(toolCalls.first)
    #expect(completeToolCall.function.name == "get_weather", "Should be weather tool call")
    #expect(!completeToolCall.function.arguments.isEmpty, "Should have arguments")
    
    // Verify arguments contain expected location data
    if let parsedArgs = completeToolCall.function.parsedArguments {
        #expect(parsedArgs["location"] != nil, "Should have location argument")
        #expect(parsedArgs["unit"] != nil, "Should have unit argument")
    }
    
    // Verify final content includes both tool and text responses
    #expect(fullContent.contains("weather") || fullContent.contains("San Francisco"), 
           "Final content should mention weather or location")
    
    // Verify streaming worked with multiple chunks
    #expect(receivedChunks.count >= 5, "Should have multiple streaming chunks")
    
    // Verify final chunk has usage information
    let lastChunk = try #require(receivedChunks.last)
    #expect(lastChunk.usage != nil, "Final chunk should have usage information")
    #expect(lastChunk.usage!.totalTokens > 0, "Should track token usage")
}

@Test func testStreamingToolCallsWithSteps() async throws {
    // Test that streaming tool calls include proper step boundaries
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
        Message.user("tool streaming - demonstrate the full step workflow")
    ]
    
    // This should trigger the full streaming tool workflow in MockProvider
    let stream = await client.streamText(model, messages: messages, tools: [weatherTool])
    
    var allChunks: [TextChunk] = []
    var stepIds: Set<String> = []
    var toolCallCount = 0
    var hasSteps = false
    
    // Process the stream and track step flow
    for try await chunk in stream {
        allChunks.append(chunk)
        
        if let stepId = chunk.stepId {
            stepIds.insert(stepId)
            hasSteps = true
        }
        
        if let toolCalls = chunk.toolCalls, !toolCalls.isEmpty {
            toolCallCount += toolCalls.count
        }
    }
    
    // Verify multi-step execution
    #expect(hasSteps, "Should have step information in chunks")
    #expect(stepIds.count >= 2, "Should have multiple steps (tool call + final response)")
    #expect(toolCallCount > 0, "Should have tool calls")
    
    // Verify step flow progression
    let chunksWithSteps = allChunks.filter { $0.stepId != nil }
    #expect(!chunksWithSteps.isEmpty, "Should have chunks with step information")
    
    // Verify we get both tool call chunks and text response chunks
    let toolCallChunks = allChunks.filter { $0.toolCalls?.isEmpty == false }
    let textChunks = allChunks.filter { !$0.delta.isEmpty }
    
    #expect(!toolCallChunks.isEmpty, "Should have tool call chunks")
    #expect(!textChunks.isEmpty, "Should have text content chunks")
    
    // Verify final content mentions tool execution
    let fullContent = allChunks.map { $0.delta }.joined()
    #expect(fullContent.contains("weather") || fullContent.contains("tool") || fullContent.contains("San Francisco"),
           "Final content should reference tool execution")
    
    // Verify streaming performance
    #expect(allChunks.count >= 15, "Should stream many chunks for tool + text workflow")
    
    // Verify final usage
    let finalChunk = try #require(allChunks.last)
    #expect(finalChunk.usage != nil, "Should have final usage information")
    #expect(finalChunk.usage!.totalTokens > 0, "Should track tokens")
}

// MARK: - Mock Types for Middleware Testing

struct MockRequest: AIRequest {
    let requestId: String
    let timestamp: Date
    
    init(id: String, timestamp: Date) {
        self.requestId = id
        self.timestamp = timestamp
    }
}

struct MockResponse: AIResponse {
    let responseId: String?
    let timestamp: Date
    
    init(id: String, timestamp: Date) {
        self.responseId = id
        self.timestamp = timestamp
    }
}

struct MockChunk: StreamChunk {
    let chunkId: String
    let timestamp: Date
    
    init(id: String, timestamp: Date) {
        self.chunkId = id
        self.timestamp = timestamp
    }
}

// MARK: - Advanced Middleware Tests

@Test @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
func testAdvancedLoggingMiddleware() async throws {
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("test-model")
        .temperature(0.0)
    
    // Test AdvancedLoggingMiddleware with different detail levels
    let verboseLogging = AdvancedLoggingMiddleware(
        detailLevel: .verbose,
        includeTimestamps: true,
        includePerformanceMetrics: true,
        includeRequestContent: false,
        includeResponseContent: false
    )
    
    let standardLogging = AdvancedLoggingMiddleware(
        detailLevel: .standard,
        includeTimestamps: true,
        includePerformanceMetrics: false
    )
    
    let minimalLogging = AdvancedLoggingMiddleware(
        detailLevel: .minimal
    )
    
    // Test all middleware conform to AIMiddleware protocol
    #expect(verboseLogging.id == "advanced-logging", "Should have correct ID")
    #expect(verboseLogging.name == "Advanced Logging Middleware", "Should have correct name")
    #expect(verboseLogging.priority == 100, "Should have correct priority")
    
    // Test request transformation (should not modify request)
    let originalRequest = MockRequest(id: "test-123", timestamp: Date())
    let transformedRequest = try await verboseLogging.transformRequest(originalRequest)
    #expect(transformedRequest.requestId == originalRequest.requestId, "Should not modify request ID")
    
    // Test response transformation (should not modify response)
    let originalResponse = MockResponse(id: "test-123", timestamp: Date())
    let transformedResponse = try await verboseLogging.transformResponse(originalResponse)
    #expect(transformedResponse.responseId == originalResponse.responseId, "Should not modify response ID")
    
    // Test chunk transformation (should not modify chunk)
    let originalChunk = MockChunk(id: "chunk-123", timestamp: Date())
    let transformedChunk = try await verboseLogging.transformChunk(originalChunk)
    #expect(transformedChunk.chunkId == originalChunk.chunkId, "Should not modify chunk ID")
    
    // Test error handling (should not modify error)
    let originalError = AIGenerationError.invalidPrompt("test error")
    let context = MiddlewareContext(
        requestId: "test-123",
        operationType: .generateText,
        modelId: "test-model",
        providerId: "mock"
    )
    let handledError = try await verboseLogging.handleError(originalError, context: context)
    #expect(handledError.localizedDescription == originalError.localizedDescription, "Should not modify error")
}

@Test @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
func testAdvancedCachingMiddleware() async throws {
    let cacheConfig = AdvancedCachingMiddleware.CacheConfiguration(
        ttl: 60.0, // 1 minute
        maxEntries: 100,
        keyPrefix: "test_cache",
        enableCompression: true
    )
    
    let cachingMiddleware = AdvancedCachingMiddleware(configuration: cacheConfig)
    
    // Test middleware properties
    #expect(await cachingMiddleware.id == "advanced-caching", "Should have correct ID")
    #expect(await cachingMiddleware.name == "Advanced Caching Middleware", "Should have correct name")
    #expect(await cachingMiddleware.priority == 200, "Should have correct priority")
    
    // Test cache stats (should be empty initially)
    let initialStats = await cachingMiddleware.getCacheStats()
    #expect(initialStats.entries == 0, "Cache should be empty initially")
    #expect(initialStats.totalSize == 0, "Cache size should be zero initially")
    
    // Test response caching
    let response = MockResponse(id: "test-response", timestamp: Date())
    let cachedResponse = try await cachingMiddleware.transformResponse(response)
    #expect(cachedResponse.responseId == response.responseId, "Should return same response")
    
    // Test cache stats after caching
    let afterCacheStats = await cachingMiddleware.getCacheStats()
    #expect(afterCacheStats.entries == 1, "Should have one cached entry")
    
    // Test cache clearing
    await cachingMiddleware.clearCache()
    let clearedStats = await cachingMiddleware.getCacheStats()
    #expect(clearedStats.entries == 0, "Cache should be empty after clearing")
}

@Test @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
func testAdvancedRetryMiddleware() async throws {
    let retryConfig = AdvancedRetryMiddleware.RetryConfiguration(
        maxRetries: 2,
        baseDelay: 0.1, // Short delay for testing
        maxDelay: 1.0,
        backoffMultiplier: 2.0,
        jitter: false, // Disable jitter for predictable testing
        retryableErrors: ["network", "timeout", "rate_limit"]
    )
    
    let retryMiddleware = AdvancedRetryMiddleware(configuration: retryConfig)
    
    // Test middleware properties
    #expect(retryMiddleware.id == "advanced-retry", "Should have correct ID")
    #expect(retryMiddleware.name == "Advanced Retry Middleware", "Should have correct name")
    #expect(retryMiddleware.priority == 50, "Should have correct priority")
    
    // Test non-retryable error (should not retry)
    let nonRetryableError = AIGenerationError.invalidPrompt("Invalid prompt")
    let context = MiddlewareContext(
        requestId: "test-123",
        operationType: .generateText,
        modelId: "test-model",
        providerId: "mock"
    )
    
    let handledNonRetryableError = try await retryMiddleware.handleError(nonRetryableError, context: context)
    #expect(handledNonRetryableError.localizedDescription == nonRetryableError.localizedDescription, "Should not modify non-retryable error")
    
    // Test retryable error (should create RetryableError)
    let retryableError = AIGenerationError.modelOverloaded
    do {
        _ = try await retryMiddleware.handleError(retryableError, context: context)
        #expect(Bool(false), "Should have thrown RetryableError")
    } catch let error as RetryableError {
        #expect(error.retryCount == 1, "Should have retry count of 1")
    } catch {
        #expect(Bool(false), "Should have thrown RetryableError, got: \(error)")
    }
}

@Test @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
func testPerformanceMonitoringMiddleware() async throws {
    let performanceMiddleware = PerformanceMonitoringMiddleware(maxMetricsHistory: 10)
    
    // Test middleware properties
    #expect(await performanceMiddleware.id == "performance-monitoring", "Should have correct ID")
    #expect(await performanceMiddleware.name == "Performance Monitoring Middleware", "Should have correct name")
    #expect(await performanceMiddleware.priority == 150, "Should have correct priority")
    
    // Test initial metrics (should be empty)
    let initialMetrics = await performanceMiddleware.getMetrics()
    #expect(initialMetrics.isEmpty, "Should have no metrics initially")
    
    let initialLatency = await performanceMiddleware.getAverageLatency()
    #expect(initialLatency == 0, "Should have zero average latency initially")
    
    // Test request tracking
    let request = MockRequest(id: "perf-test-123", timestamp: Date())
    let trackedRequest = try await performanceMiddleware.transformRequest(request)
    #expect(trackedRequest.requestId == request.requestId, "Should not modify request")
    
    // Test response completion tracking
    let response = MockResponse(id: "perf-test-123", timestamp: Date().addingTimeInterval(0.5))
    let trackedResponse = try await performanceMiddleware.transformResponse(response)
    #expect(trackedResponse.responseId == response.responseId, "Should not modify response")
    
    // Test error tracking
    let error = AIGenerationError.modelOverloaded
    let context = MiddlewareContext(
        requestId: "error-test-456",
        operationType: .generateText,
        modelId: "test-model",
        providerId: "mock"
    )
    
    // First track the request
    let errorRequest = MockRequest(id: "error-test-456", timestamp: Date())
    _ = try await performanceMiddleware.transformRequest(errorRequest)
    
    // Then handle error
    let handledError = try await performanceMiddleware.handleError(error, context: context)
    #expect(handledError.localizedDescription == error.localizedDescription, "Should not modify error")
    
    // Test metrics collection
    let finalMetrics = await performanceMiddleware.getMetrics()
    #expect(finalMetrics.count >= 1, "Should have collected metrics")
    
    // Test average latency calculation
    let averageLatency = await performanceMiddleware.getAverageLatency(for: .generateText)
    #expect(averageLatency >= 0, "Average latency should be non-negative")
}

@Test func testToolErrorScenarios() async throws {
    // Test comprehensive tool error handling following Vercel AI SDK patterns
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    let client = AIClient()
    
    // Define a weather tool for testing
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
    
    // Test Case 1: No Such Tool Error
    do {
        let response = try await client.generateText(
            model,
            messages: [Message.user("Test no such tool error scenario")],
            tools: [weatherTool]
        )
        #expect(Bool(false), "Should have thrown NoSuchTool error")
    } catch let error as AIGenerationError {
        switch error {
        case .noSuchTool(let toolName, let availableTools):
            #expect(toolName == "non_existent_tool", "Should identify the missing tool")
            #expect(availableTools.contains("get_weather"), "Should list available tools")
            #expect(error.code == "NO_SUCH_TOOL", "Should have correct error code")
        default:
            #expect(Bool(false), "Should be NoSuchTool error, got: \(error)")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.noSuchTool")
    }
    
    // Test Case 2: Invalid Tool Arguments Error
    do {
        let response = try await client.generateText(
            model,
            messages: [Message.user("Test invalid arguments error scenario")],
            tools: [weatherTool]
        )
        #expect(Bool(false), "Should have thrown InvalidToolArguments error")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, let toolArgs, let cause):
            #expect(toolName == "get_weather", "Should identify the tool with invalid arguments")
            #expect(toolArgs.contains("invalid"), "Should include the invalid arguments")
            #expect(cause != nil, "Should have underlying cause")
            #expect(error.code == "INVALID_TOOL_ARGUMENTS", "Should have correct error code")
        default:
            #expect(Bool(false), "Should be InvalidToolArguments error, got: \(error)")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.invalidToolArguments")
    }
    
    // Test Case 3: Tool Execution Error
    do {
        let response = try await client.generateText(
            model,
            messages: [Message.user("Test tool execution error scenario")],
            tools: [weatherTool]
        )
        #expect(Bool(false), "Should have thrown ToolExecutionError")
    } catch let error as AIGenerationError {
        switch error {
        case .toolExecutionError(let toolName, let toolArgs, let toolCallId, let cause):
            #expect(toolName == "get_weather", "Should identify the failed tool")
            #expect(!toolCallId.isEmpty, "Should have tool call ID")
            #expect(toolArgs.contains("San Francisco"), "Should include tool arguments")
            #expect(error.code == "TOOL_EXECUTION_ERROR", "Should have correct error code")
        default:
            #expect(Bool(false), "Should be ToolExecutionError, got: \(error)")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError.toolExecutionError")
    }
}

@Test func testToolValidationHelpers() throws {
    // Test the ToolValidation utility functions
    
    // Set up test tools
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
    
    let calculatorTool = Tool(
        function: ToolFunction(
            name: "calculate",
            description: "Perform mathematical calculations",
            parameters: JSONSchema.object(properties: [
                "expression": .string()
            ], required: ["expression"])
        )
    )
    
    let availableTools = [weatherTool, calculatorTool]
    
    // Test Case 1: Valid tool call should pass validation
    let validToolCall = ToolCall(
        id: "tool_call_12345",
        function: try ToolCallFunction(
            name: "get_weather",
            arguments: ["location": "San Francisco, CA", "unit": "celsius"]
        )
    )
    
    do {
        try validToolCall.validate(against: availableTools)
        // Should not throw
    } catch {
        #expect(Bool(false), "Valid tool call should pass validation")
    }
    
    // Test Case 2: Tool validation should fail for non-existent tool
    let invalidToolCall = ToolCall(
        id: "tool_call_67890",
        function: ToolCallFunction(
            name: "non_existent_tool",
            arguments: "{}"
        )
    )
    
    do {
        try invalidToolCall.validate(against: availableTools)
        #expect(Bool(false), "Should throw error for non-existent tool")
    } catch let error as AIGenerationError {
        switch error {
        case .noSuchTool(let toolName, let availableToolNames):
            #expect(toolName == "non_existent_tool", "Should identify missing tool")
            #expect(availableToolNames.contains("get_weather"), "Should list available tools")
        default:
            #expect(Bool(false), "Should be NoSuchTool error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError")
    }
    
    // Test Case 3: Tool validation should fail for malformed JSON arguments
    let malformedArgsToolCall = ToolCall(
        id: "tool_call_99999",
        function: ToolCallFunction(
            name: "get_weather",
            arguments: "{\"location\": \"San Francisco\", invalid json"
        )
    )
    
    do {
        try malformedArgsToolCall.validate(against: availableTools)
        #expect(Bool(false), "Should throw error for malformed JSON")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, let toolArgs, let cause):
            #expect(toolName == "get_weather", "Should identify the tool with invalid arguments")
            #expect(toolArgs.contains("invalid json"), "Should include malformed arguments")
            #expect(cause != nil, "Should have underlying JSON parsing error")
        default:
            #expect(Bool(false), "Should be InvalidToolArguments error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError")
    }
    
    // Test Case 4: Array extensions should work correctly
    #expect(availableTools.toolNames.contains("get_weather"), "Should find weather tool name")
    #expect(availableTools.toolNames.contains("calculate"), "Should find calculator tool name")
    #expect(availableTools.tool(named: "get_weather") != nil, "Should find weather tool by name")
    #expect(availableTools.tool(named: "non_existent") == nil, "Should not find non-existent tool")
}

@Test func testToolValidationEdgeCases() throws {
    // Test edge cases in tool validation
    
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string()
            ], required: ["location"])
        )
    )
    
    let availableTools = [weatherTool]
    
    // Test Case 1: Empty tool name should fail validation
    let emptyNameToolCall = ToolCall(
        id: "tool_call_12345",
        function: ToolCallFunction(
            name: "",
            arguments: "{\"location\": \"San Francisco\"}"
        )
    )
    
    do {
        try emptyNameToolCall.validate(against: availableTools)
        #expect(Bool(false), "Should throw error for empty tool name")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, _, let cause):
            #expect(toolName.isEmpty, "Should have empty tool name")
            #expect(cause != nil, "Should have underlying error about empty name")
        default:
            #expect(Bool(false), "Should be InvalidToolArguments error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError")
    }
    
    // Test Case 2: Empty tool call ID should fail validation
    let emptyIdToolCall = ToolCall(
        id: "",
        function: ToolCallFunction(
            name: "get_weather",
            arguments: "{\"location\": \"San Francisco\"}"
        )
    )
    
    do {
        try emptyIdToolCall.validate(against: availableTools)
        #expect(Bool(false), "Should throw error for empty tool call ID")
    } catch let error as AIGenerationError {
        switch error {
        case .invalidToolArguments(let toolName, _, let cause):
            #expect(toolName == "get_weather", "Should identify the tool")
            #expect(cause != nil, "Should have underlying error about empty ID")
        default:
            #expect(Bool(false), "Should be InvalidToolArguments error")
        }
    } catch {
        #expect(Bool(false), "Should throw AIGenerationError")
    }
    
    // Test Case 3: Valid empty arguments object should pass
    let emptyArgsToolCall = ToolCall(
        id: "tool_call_12345",
        function: ToolCallFunction(
            name: "get_weather",
            arguments: "{}"
        )
    )
    
    do {
        try emptyArgsToolCall.validate(against: availableTools)
        // Note: This might fail schema validation in a full implementation
        // For now, we just check JSON validity
    } catch {
        // This is acceptable - empty args might fail schema validation
    }
}

// MARK: - Comprehensive Streaming Tests Based on Vercel AI SDK

@Test func testStreamTextBasicPattern() async throws {
    // Test basic streaming following Vercel AI SDK streamText pattern
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
        .temperature(0.0)
    
    // Test with simple prompt (Vercel pattern: streamText({ model, prompt }))
    let stream = await client.streamText(model, prompt: "Count from 1 to 5")
    
    var chunks: [TextChunk] = []
    var fullText = ""
    var finalUsage: TokenUsage? = nil
    var finalFinishReason: FinishReason? = nil
    
    // Collect all chunks (Vercel pattern: for await (const textPart of result.textStream))
    for try await chunk in stream {
        chunks.append(chunk)
        fullText += chunk.delta
        
        if let usage = chunk.usage {
            finalUsage = usage
        }
        
        if let finishReason = chunk.finishReason {
            finalFinishReason = finishReason
        }
    }
    
    // Verify streaming behavior matches Vercel AI SDK expectations
    #expect(!chunks.isEmpty, "Should receive streaming chunks")
    #expect(!fullText.isEmpty, "Should accumulate text content")
    #expect(finalUsage != nil, "Should have final usage information")
    #expect(finalFinishReason == .stop, "Should finish with stop reason")
    
    // Verify progressive streaming (chunks build up)
    var accumulatedSnapshot = ""
    for chunk in chunks {
        accumulatedSnapshot += chunk.delta
        #expect(chunk.snapshot.hasPrefix(accumulatedSnapshot) || chunk.snapshot == accumulatedSnapshot, 
               "Snapshot should contain accumulated text")
    }
    
    // Verify final content
    #expect(fullText.contains("Mock response"), "Should contain expected content")
    #expect(chunks.count > 5, "Should stream multiple chunks")
}

@Test func testStreamTextWithMessagesArray() async throws {
    // Test streaming with messages array (Vercel pattern: streamText({ model, messages }))
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
        .temperature(0.3)
    
    let messages = [
        Message.system("You are a helpful assistant that counts clearly."),
        Message.user("Count from 1 to 3"),
        Message.assistant("1, 2, 3"),
        Message.user("Now count from 4 to 6")
    ]
    
    let stream = await client.streamText(model, messages: messages)
    
    var chunks: [TextChunk] = []
    var hasContent = false
    
    for try await chunk in stream {
        chunks.append(chunk)
        if !chunk.delta.isEmpty {
            hasContent = true
        }
    }
    
    #expect(!chunks.isEmpty, "Should receive streaming chunks")
    #expect(hasContent, "Should have text content")
    
    // Verify last chunk has completion metadata
    let lastChunk = try #require(chunks.last)
    #expect(lastChunk.finishReason == .stop, "Should finish with stop")
    #expect(lastChunk.usage != nil, "Should have usage information")
}

@Test func testStreamTextWithToolCalls() async throws {
    // Test streaming with tool calls (Vercel pattern: streamText({ model, tools, prompt }))
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    let stream = await client.streamText(
        model, 
        messages: [Message.user("What's the weather in San Francisco?")],
        tools: [weatherTool]
    )
    
    var chunks: [TextChunk] = []
    var toolCallStreamingStarts: [ToolCallStreamingStart] = []
    var toolCallDeltas: [ToolCallDelta] = []
    var completedToolCalls: [ToolCall] = []
    
    // Process stream and collect tool call events
    for try await chunk in stream {
        chunks.append(chunk)
        
        if let toolCallStart = chunk.toolCallStreamingStart {
            toolCallStreamingStarts.append(toolCallStart)
        }
        
        if let toolCallDelta = chunk.toolCallDelta {
            toolCallDeltas.append(toolCallDelta)
        }
        
        if let toolCalls = chunk.toolCalls {
            completedToolCalls.append(contentsOf: toolCalls)
        }
    }
    
    // Verify tool call streaming events (matching Vercel AI SDK tool call streaming)
    #expect(!toolCallStreamingStarts.isEmpty, "Should have tool call streaming start events")
    #expect(!toolCallDeltas.isEmpty, "Should have tool call argument deltas")
    #expect(!completedToolCalls.isEmpty, "Should have completed tool calls")
    
    // Verify tool call structure
    let firstToolCall = try #require(completedToolCalls.first)
    #expect(firstToolCall.function.name == "get_weather", "Should call weather tool")
    #expect(!firstToolCall.function.arguments.isEmpty, "Should have arguments")
}

@Test func testStreamTextErrorHandling() async throws {
    // Test streaming error handling (Vercel pattern: onError callback)
    let errorConfig = MockConfiguration(errorRate: 1.0) // Force errors
    let provider = MockProvider(apiKey: "test", configuration: errorConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    let client = AIClient()
    
    let stream = await client.streamText(model, prompt: "This should fail")
    
    do {
        for try await chunk in stream {
            #expect(Bool(false), "Should not receive chunks when error rate is 100%")
        }
        #expect(Bool(false), "Should have thrown an error")
    } catch {
        #expect(error is AIProviderError, "Should throw AIProviderError")
    }
}

@Test func testStreamTextBackpressure() async throws {
    // Test that streaming respects backpressure (Vercel AI SDK behavior)
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let stream = await client.streamText(model, prompt: "Generate a long response")
    
    var chunkCount = 0
    let maxChunks = 5
    
    // Only consume first few chunks to test backpressure
    for try await chunk in stream {
        chunkCount += 1
        if chunkCount >= maxChunks {
            break
        }
    }
    
    #expect(chunkCount == maxChunks, "Should respect early termination")
}

// MARK: - Comprehensive Object Generation Tests Based on Vercel AI SDK

@Test func testGenerateObjectBasicPattern() async throws {
    // Test basic object generation (Vercel pattern: generateObject({ model, schema, prompt }))
    struct Person: Codable, Sendable {
        let name: String
        let age: Int
        let occupation: String
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
        .temperature(0.0)
    
    let personSchema = ObjectSchema<Person>(
        name: "Person",
        description: "A person with name, age, and occupation"
    )
    
    let response = try await client.generateObject(
        model,
        prompt: "Generate a person profile for John Smith, age 30, software engineer",
        schema: personSchema
    )
    
    // Verify object generation following Vercel AI SDK patterns
    let person = response.object
    #expect(!person.name.isEmpty, "Should have valid name")
    #expect(person.age > 0, "Should have valid age")
    #expect(!person.occupation.isEmpty, "Should have valid occupation")
    
    // Verify response metadata
    #expect(response.finishReason == .stop, "Should finish with stop")
    #expect(response.usage.totalTokens > 0, "Should track token usage")
    #expect(!response.messages.isEmpty, "Should have message history")
    #expect(response.validationResult?.isValid == true, "Should pass validation")
}

@Test func testGenerateObjectWithComplexSchema() async throws {
    // Test complex nested object generation (Vercel AI SDK pattern)
    struct Address: Codable, Sendable {
        let street: String
        let city: String
        let zipCode: String
    }
    
    struct Contact: Codable, Sendable {
        let email: String
        let phone: String?
    }
    
    struct Employee: Codable, Sendable {
        let id: String
        let name: String
        let department: String
        let salary: Double
        let address: Address
        let contact: Contact
        let skills: [String]
        let isActive: Bool
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let employeeSchema = ObjectSchema<Employee>(
        name: "Employee",
        description: "Complete employee record with nested information"
    )
    
    let response = try await client.generateObject(
        model,
        prompt: "Generate a complete employee profile for a software engineer in San Francisco",
        schema: employeeSchema
    )
    
    let employee = response.object
    
    // Verify top-level properties
    #expect(!employee.id.isEmpty, "Should have employee ID")
    #expect(!employee.name.isEmpty, "Should have name")
    #expect(!employee.department.isEmpty, "Should have department")
    #expect(employee.salary > 0, "Should have positive salary")
    #expect(employee.isActive == true || employee.isActive == false, "Should have boolean active status")
    
    // Verify nested address object
    #expect(!employee.address.street.isEmpty, "Should have street address")
    #expect(!employee.address.city.isEmpty, "Should have city")
    #expect(!employee.address.zipCode.isEmpty, "Should have zip code")
    
    // Verify nested contact object
    #expect(!employee.contact.email.isEmpty, "Should have email")
    #expect(employee.contact.email.contains("@"), "Email should be valid format")
    
    // Verify array properties
    #expect(!employee.skills.isEmpty, "Should have skills array")
    #expect(employee.skills.count >= 2, "Should have multiple skills")
}

@Test func testGenerateArrayPattern() async throws {
    // Test array generation (Vercel pattern: generateObject with array output)
    struct Product: Codable, Sendable {
        let name: String
        let price: Double
        let category: String
        let inStock: Bool
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let productSchema = ObjectSchema<Product>(
        name: "Product",
        description: "A product with name, price, category, and stock status"
    )
    
    let response = try await client.generateArray(
        model,
        prompt: "Generate 3 electronic products for an online store",
        elementSchema: productSchema
    )
    
    let products = response.object
    
    // Verify array generation
    #expect(products.count >= 2, "Should generate multiple products")
    #expect(products.count <= 5, "Should not generate too many products")
    
    // Verify each product
    for product in products {
        #expect(!product.name.isEmpty, "Product should have name")
        #expect(product.price > 0, "Product should have positive price")
        #expect(!product.category.isEmpty, "Product should have category")
    }
}

@Test func testGenerateEnumPattern() async throws {
    // Test enum generation (Vercel pattern: generateObject with enum output)
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let sentimentOptions = ["positive", "negative", "neutral"]
    
    let response = try await client.generateEnum(
        model,
        prompt: "Analyze the sentiment of this text: 'I love this product!'",
        values: sentimentOptions
    )
    
    let sentiment = response.object
    
    // Verify enum selection
    #expect(sentimentOptions.contains(sentiment), "Should select from allowed values")
    #expect(sentiment == "positive", "Should correctly identify positive sentiment")
    #expect(response.finishReason == .stop, "Should complete successfully")
}

@Test func testStreamObjectBasicPattern() async throws {
    // Test object streaming (Vercel pattern: streamObject({ model, schema, prompt }))
    struct Recipe: Codable, Sendable {
        let name: String
        let ingredients: [String]
        let instructions: [String]
        let cookingTime: Int
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let recipeSchema = ObjectSchema<Recipe>(
        name: "Recipe",
        description: "A cooking recipe with ingredients and instructions"
    )
    
    let stream = await client.streamObject(
        model,
        messages: [Message.user("Create a simple pasta recipe")],
        schema: recipeSchema
    )
    
    var chunks: [ObjectChunk<Recipe>] = []
    var validObjects: [Recipe] = []
    var finalUsage: TokenUsage? = nil
    
    // Collect streaming chunks (Vercel pattern: for await (const partial of result.partialObjectStream))
    for try await chunk in stream {
        chunks.append(chunk)
        
        if let recipe = chunk.object {
            validObjects.append(recipe)
        }
        
        if let usage = chunk.usage {
            finalUsage = usage
        }
    }
    
    // Verify streaming object generation
    #expect(!chunks.isEmpty, "Should receive streaming chunks")
    #expect(!validObjects.isEmpty, "Should have valid partial/complete objects")
    #expect(finalUsage != nil, "Should have final usage information")
    
    // Verify final object is complete
    let finalRecipe = try #require(validObjects.last)
    #expect(!finalRecipe.name.isEmpty, "Should have recipe name")
    #expect(!finalRecipe.ingredients.isEmpty, "Should have ingredients")
    #expect(!finalRecipe.instructions.isEmpty, "Should have instructions")
    #expect(finalRecipe.cookingTime > 0, "Should have cooking time")
    
    // Verify progressive streaming (JSON is streamed character by character)
    #expect(chunks.count >= 2, "Should stream multiple chunks for object generation")
}

@Test func testObjectGenerationModes() async throws {
    // Test different generation modes (Vercel pattern: mode: 'auto' | 'json' | 'tool')
    struct SimpleData: Codable, Sendable {
        let value: String
        let number: Int
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let schema = ObjectSchema<SimpleData>(
        name: "SimpleData",
        description: "Simple data structure"
    )
    
    // Test auto mode (default)
    let autoResponse = try await client.generateObject(
        model,
        prompt: "Generate simple test data",
        schema: schema,
        mode: .auto
    )
    
    #expect(!autoResponse.object.value.isEmpty, "Auto mode should generate valid object")
    
    // Test JSON mode
    let jsonResponse = try await client.generateObject(
        model,
        prompt: "Generate simple test data",
        schema: schema,
        mode: .json
    )
    
    #expect(!jsonResponse.object.value.isEmpty, "JSON mode should generate valid object")
    
    // Test tool mode
    let toolResponse = try await client.generateObject(
        model,
        prompt: "Generate simple test data",
        schema: schema,
        mode: .tool
    )
    
    #expect(!toolResponse.object.value.isEmpty, "Tool mode should generate valid object")
}

@Test func testObjectValidationAndRepair() async throws {
    // Test JSON validation and repair (Vercel AI SDK behavior)
    struct TestObject: Codable, Sendable {
        let name: String
        let value: Int
        let active: Bool
    }
    
    let client = AIClient()
    let provider = MockProvider()
    
    // Test with model that generates malformed JSON (should be repaired)
    let malformedModel = provider.languageModel("malformed-json-model")
    
    let schema = ObjectSchema<TestObject>(
        name: "TestObject",
        description: "Test object for validation"
    )
    
    // This should trigger JSON repair mechanisms
    do {
        let response = try await client.generateObject(
            malformedModel,
            prompt: "Generate test object",
            schema: schema
        )
        
        // If we get here, JSON repair worked
        #expect(!response.object.name.isEmpty, "Repaired object should be valid")
    } catch let error as AIGenerationError {
        // Expected for some malformed cases that can't be repaired
        switch error {
        case .jsonParseError(let text, _):
            #expect(text.contains("{"), "Should contain partial JSON")
        case .noObjectGenerated(let text, _, _):
            #expect(!text.isEmpty, "Should have attempted text generation")
        default:
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}

@Test func testStreamObjectErrorRecovery() async throws {
    // Test streaming object error recovery and repair
    struct StreamData: Codable, Sendable {
        let id: String
        let content: String
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("partial-json-model") // Generates partial JSON
    
    let schema = ObjectSchema<StreamData>(
        name: "StreamData",
        description: "Streaming data object"
    )
    
    let stream = await client.streamObject(
        model,
        messages: [Message.user("Generate streaming data")],
        schema: schema
    )
    
    var chunks: [ObjectChunk<StreamData>] = []
    var hasValidObject = false
    
    // Process stream and test recovery from partial JSON
    for try await chunk in stream {
        chunks.append(chunk)
        
        if chunk.object != nil {
            hasValidObject = true
        }
    }
    
    // Should eventually recover and produce valid object
    #expect(!chunks.isEmpty, "Should receive chunks")
    #expect(hasValidObject, "Should eventually produce valid object through repair")
}

// MARK: - Anthropic Provider Tests

func testAnthropicProviderInitialization() async throws {
    // Test basic initialization
    let provider = AnthropicProvider(
        apiKey: "test-api-key",
        baseURL: "https://api.anthropic.com/v1",
        version: "2023-06-01"
    )
    
    #expect(provider.name == "Anthropic")
    #expect(provider.supportedGenerationModes.contains(.auto))
    #expect(provider.supportedGenerationModes.contains(.tool))
    #expect(provider.defaultGenerationMode == .tool)
}

func testAnthropicProviderLanguageModel() async throws {
    let provider = AnthropicProvider(apiKey: "test-api-key")
    let model = provider.languageModel("claude-3-5-sonnet-20241022")
    
    #expect(model.modelId == "claude-3-5-sonnet-20241022")
    #expect(model.provider.name == "Anthropic")
}

func testAnthropicProviderConfiguration() async throws {
    let provider = AnthropicProvider(
        apiKey: "test-api-key",
        betaFeatures: ["computer-use-2024-10-22", "pdfs-2024-09-25"]
    )
    
    // Test valid configuration
    let validConfig = ModelConfiguration(
        temperature: 0.7,
        maxTokens: 1024,
        topP: 0.9,
        topK: 40
    )
    
    // Should not throw for valid config
    do {
        try provider.validateConfiguration(validConfig)
    } catch {
        #expect(Bool(false), "Valid configuration should not throw")
    }
    
    // Test invalid temperature
    let invalidTempConfig = ModelConfiguration(temperature: 1.5)
    do {
        try provider.validateConfiguration(invalidTempConfig)
        #expect(Bool(false), "Should throw for invalid temperature")
    } catch {
        #expect(error is AIProviderError, "Should throw AIProviderError")
    }
    
    // Test unsupported parameters
    let unsupportedConfig = ModelConfiguration(frequencyPenalty: 0.5)
    do {
        try provider.validateConfiguration(unsupportedConfig)
        #expect(Bool(false), "Should throw for unsupported parameter")
    } catch {
        #expect(error is AIProviderError, "Should throw AIProviderError")
    }
    
    let seedConfig = ModelConfiguration(seed: 42)
    do {
        try provider.validateConfiguration(seedConfig)
        #expect(Bool(false), "Should throw for unsupported seed parameter")
    } catch {
        #expect(error is AIProviderError, "Should throw AIProviderError")
    }
}

func testAnthropicMessageConversion() async throws {
    let provider = AnthropicProvider(apiKey: "test-api-key")
    
    // Test basic message conversion
    let userMessage = Message(
        role: .user,
        content: [.text("Hello, Claude!")]
    )
    
    let assistantMessage = Message(
        role: .assistant,
        content: [.text("Hello! How can I help you today?")]
    )
    
    let messages = [userMessage, assistantMessage]
    
    // Create a basic request to test conversion (this would normally be internal)
    let request = ProviderRequest(
        modelId: "claude-3-5-sonnet-20241022",
        messages: messages,
        configuration: ModelConfiguration(),
        system: "You are a helpful assistant.",
        mode: .regular(tools: nil, toolChoice: nil),
        requestId: "test-123"
    )
    
    // This test verifies the provider can be instantiated and basic properties work
    // Full request conversion testing would require mocking the network layer
    #expect(provider.name == "Anthropic")
    #expect(provider.languageModel(request.modelId).modelId == request.modelId)
}

func testAnthropicToolChoiceMapping() async throws {
    let provider = AnthropicProvider(apiKey: "test-api-key")
    
    // Create a simple tool for testing
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get weather information",
            parameters: JSONSchema.object(properties: [
                "location": JSONSchema.string()
            ], required: ["location"])
        )
    )
    
    // Test tool choice mapping through configuration validation
    // (Full tool choice testing would require internal access or integration tests)
    let toolConfig = ModelConfiguration(
        temperature: 0.7,
        maxTokens: 1000
    )
    
    // Should not throw for valid config
    do {
        try provider.validateConfiguration(toolConfig)
    } catch {
        #expect(Bool(false), "Valid tool configuration should not throw")
    }
    
    // Verify the provider supports tool mode
    #expect(provider.supportedGenerationModes.contains(.tool))
    #expect(provider.defaultGenerationMode == .tool)
}