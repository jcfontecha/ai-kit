import Testing
import Foundation
@testable import AIKit

// MARK: - Configuration Reader

/// Helper to read configuration from Config.plist
private struct GoogleConfigReader {
    static func loadAPIKey() throws -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") else {
            // Try to find Config.plist in the current working directory (project root)
            let currentWorkingDir = FileManager.default.currentDirectoryPath
            let configPath = "\(currentWorkingDir)/Config.plist"
            
            // Try to read from working directory (project root)
            
            guard FileManager.default.fileExists(atPath: configPath) else {
                throw E2ETestError.configNotFound("Config.plist not found at \(configPath)")
            }
            
            guard let plistData = FileManager.default.contents(atPath: configPath),
                  let plist = try PropertyListSerialization.propertyList(
                    from: plistData,
                    options: [],
                    format: nil
                  ) as? [String: Any] else {
                throw E2ETestError.configInvalid("Failed to load Config.plist")
            }
            
            guard let apiKey = plist["GOOGLE_API_KEY"] as? String, !apiKey.isEmpty else {
                throw E2ETestError.apiKeyMissing("GOOGLE_API_KEY not found or empty in Config.plist")
            }
            
            return apiKey
        }
        
        guard let plist = NSDictionary(contentsOfFile: path),
              let apiKey = plist["GOOGLE_API_KEY"] as? String, !apiKey.isEmpty else {
            throw E2ETestError.apiKeyMissing("GOOGLE_API_KEY not found or empty in Config.plist")
        }
        
        return apiKey
    }
}

/// E2E test specific errors
private enum E2ETestError: Error, LocalizedError {
    case configNotFound(String)
    case configInvalid(String)
    case apiKeyMissing(String)
    case testSkipped(String)
    
    var errorDescription: String? {
        switch self {
        case .configNotFound(let message), .configInvalid(let message), 
             .apiKeyMissing(let message), .testSkipped(let message):
            return message
        }
    }
}

// MARK: - E2E Tests with Real Google Provider

struct E2EGoogleTests {
    
    // MARK: - Test Setup
    
    /// Create a Google provider for testing, or skip if no API key
    private static func createGoogleProviderOrSkip() throws -> GoogleProvider {
        do {
            let apiKey = try GoogleConfigReader.loadAPIKey()
            return GoogleProvider(apiKey: apiKey)
        } catch {
            throw E2ETestError.testSkipped("Skipping E2E tests: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Basic Text Generation Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleBasicTextGeneration() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.1)
            .maxTokens(50)
        
        print("🧪 Testing basic text generation with real Google Gemini API...")
        
        let response = try await client.generateText(model, prompt: "Say hello and explain what you are in one sentence.")
        
        // Verify response structure
        #expect(!response.text.isEmpty, "Response text should not be empty")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        #expect(response.usage.promptTokens > 0, "Should track prompt tokens")
        #expect(response.usage.completionTokens > 0, "Should track completion tokens")
        #expect(response.finishReason == .stop, "Should finish normally")
        #expect(!response.messages.isEmpty, "Should have message history")
        #expect(response.messages.last?.role == .assistant, "Last message should be from assistant")
        
        print("✅ Basic text generation successful")
        print("📝 Response: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens) total (\(response.usage.promptTokens) prompt + \(response.usage.completionTokens) completion)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleConversation() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.3)
            .maxTokens(100)
        
        print("🧪 Testing conversation with real Google Gemini API...")
        
        let messages = [
            Message.system("You are a helpful math tutor."),
            Message.user("What is 15 + 27?"),
            Message.assistant("15 + 27 = 42"),
            Message.user("What about 42 * 2?")
        ]
        
        let response = try await client.generateText(model, messages: messages)
        
        // Verify conversation handling
        #expect(!response.text.isEmpty, "Response text should not be empty")
        #expect(response.text.contains("84"), "Should contain the correct answer (84)")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        #expect(response.finishReason == .stop, "Should finish normally")
        
        print("✅ Conversation test successful")
        print("📝 Response: \(response.text)")
    }
    
    // MARK: - Streaming Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleStreaming() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.2)
            .maxTokens(100)
        
        print("🧪 Testing streaming with real Google Gemini API...")
        
        let stream = await client.streamText(model, prompt: "Count from 1 to 5, saying 'Number X' for each number.")
        
        var chunks: [TextChunk] = []
        var fullContent = ""
        var finalUsage: TokenUsage?
        
        for try await chunk in stream {
            chunks.append(chunk)
            fullContent += chunk.delta
            
            if let usage = chunk.usage {
                finalUsage = usage
            }
            
            // Print real-time chunks to see streaming in action
            if !chunk.delta.isEmpty {
                print(chunk.delta, terminator: "")
            }
        }
        print() // New line after streaming
        
        // Verify streaming behavior
        #expect(!chunks.isEmpty, "Should receive streaming chunks")
        #expect(chunks.count > 3, "Should receive multiple chunks for this response")
        #expect(!fullContent.isEmpty, "Should accumulate content")
        
        // Usage information may or may not be included depending on the model
        if let usage = finalUsage {
            #expect(usage.totalTokens > 0, "Should track token usage when available")
        }
        
        // Verify content makes sense
        #expect(fullContent.lowercased().contains("1") || fullContent.lowercased().contains("one"), "Should contain counting")
        
        // Verify last chunk has finish reason
        let lastChunk = chunks.last!
        #expect(lastChunk.finishReason == .stop, "Should finish normally")
        
        print("✅ Streaming test successful")
        print("📊 Received \(chunks.count) chunks")
        print("📝 Full content: \(fullContent)")
    }
    
    // MARK: - Object Generation Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleObjectGeneration() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        // Define a simple test object
        struct UserProfile: Codable, Sendable {
            let name: String
            let age: Int
            let email: String
            let active: Bool
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.0)
            .maxTokens(200)
        
        print("🧪 Testing object generation with real Google Gemini API...")
        
        // Create schema for the object
        let userSchema = JSONSchema.definition(SchemaDefinition(
            type: .object,
            properties: [
                "name": JSONSchema.definition(SchemaDefinition(type: .string)),
                "age": JSONSchema.definition(SchemaDefinition(type: .integer, minimum: 18, maximum: 99)),
                "email": JSONSchema.definition(SchemaDefinition(type: .string)), // Remove format for Google compatibility
                "active": JSONSchema.definition(SchemaDefinition(type: .boolean))
            ],
            required: ["name", "age", "email", "active"],
            additionalProperties: .boolean(false)
        ))
        
        let objectSchema = ObjectSchema<UserProfile>.manual(
            jsonSchema: userSchema,
            name: "UserProfile",
            description: "A user profile with name, age, email, and active status"
        )
        
        let response = try await client.generateObject(
            model,
            prompt: "Generate a user profile for John Doe, age 30, email john@example.com, active status true",
            schema: objectSchema
        )
        
        // Verify the generated object
        let userProfile = response.object
        
        #expect(!userProfile.name.isEmpty, "Name should not be empty")
        #expect(userProfile.age >= 18 && userProfile.age <= 99, "Age should be within valid range")
        #expect(userProfile.email.contains("@"), "Email should contain @ symbol")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        #expect(response.finishReason == .stop, "Should finish normally")
        
        print("✅ Object generation successful")
        print("👤 Generated user: \(userProfile.name), age \(userProfile.age), email: \(userProfile.email), active: \(userProfile.active)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleComplexObjectGeneration() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        // Define complex nested structures
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
            let servings: Int
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.2)
            .maxTokens(800)
        
        print("🧪 Testing complex object generation with real Google Gemini API...")
        
        // Create complex nested schema
        let ingredientSchema = JSONSchema.definition(SchemaDefinition(
            type: .object,
            properties: [
                "name": JSONSchema.definition(SchemaDefinition(type: .string)),
                "amount": JSONSchema.definition(SchemaDefinition(type: .string)),
                "optional": JSONSchema.definition(SchemaDefinition(type: .boolean))
            ],
            required: ["name", "amount", "optional"]
        ))
        
        let recipeSchema = JSONSchema.definition(SchemaDefinition(
            type: .object,
            properties: [
                "name": JSONSchema.definition(SchemaDefinition(type: .string)),
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
                    minItems: 2
                )),
                "steps": JSONSchema.definition(SchemaDefinition(
                    type: .array,
                    items: JSONSchema.definition(SchemaDefinition(type: .string)),
                    minItems: 3
                )),
                "servings": JSONSchema.definition(SchemaDefinition(type: .integer, minimum: 1))
            ],
            required: ["name", "description", "prepTime", "cookTime", "difficulty", "ingredients", "steps", "servings"]
        ))
        
        let objectSchema = ObjectSchema<Recipe>.manual(
            jsonSchema: recipeSchema,
            name: "Recipe",
            description: "A detailed recipe with ingredients and cooking instructions"
        )
        
        let response = try await client.generateObject(
            model,
            prompt: "Generate a simple pasta recipe with 3-4 ingredients and clear cooking steps",
            schema: objectSchema
        )
        
        // Verify the complex structure
        let recipe = response.object
        
        #expect(!recipe.name.isEmpty, "Recipe should have a name")
        #expect(!recipe.description.isEmpty, "Recipe should have a description")
        #expect(recipe.prepTime >= 0, "Prep time should be non-negative")
        #expect(recipe.cookTime >= 0, "Cook time should be non-negative")
        #expect(["easy", "medium", "hard"].contains(recipe.difficulty), "Difficulty should be valid")
        #expect(recipe.ingredients.count >= 2, "Should have at least 2 ingredients")
        #expect(recipe.steps.count >= 3, "Should have at least 3 steps")
        #expect(recipe.servings >= 1, "Should serve at least 1 person")
        
        // Verify nested objects
        for ingredient in recipe.ingredients {
            #expect(!ingredient.name.isEmpty, "Ingredient name should not be empty")
            #expect(!ingredient.amount.isEmpty, "Ingredient amount should not be empty")
        }
        
        for step in recipe.steps {
            #expect(!step.isEmpty, "Recipe step should not be empty")
        }
        
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Complex object generation successful")
        print("🍝 Generated recipe: \(recipe.name)")
        print("⏱️  Prep: \(recipe.prepTime)min, Cook: \(recipe.cookTime)min, Difficulty: \(recipe.difficulty)")
        print("🥘 Ingredients: \(recipe.ingredients.count), Steps: \(recipe.steps.count), Servings: \(recipe.servings)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    // MARK: - Tool Calling Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleToolCalling() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient(toolExecutor: { toolCall in
            switch toolCall.function.name {
            case "get_weather":
                // Parse arguments
                let arguments = toolCall.function.parsedArguments ?? [:]
                let location = arguments["location"] as? String ?? "Unknown"
                let unit = arguments["unit"] as? String ?? "celsius"
                
                let temperature = unit == "celsius" ? "22°C" : "72°F"
                
                let weatherData = """
                {
                    "location": "\(location)",
                    "temperature": "\(temperature)",
                    "condition": "Sunny",
                    "humidity": "60%"
                }
                """
                
                return ToolResult(
                    toolCallId: toolCall.id,
                    result: .text(weatherData),
                    executionTime: 0.1
                )
            case "calculate":
                // Parse arguments
                let arguments = toolCall.function.parsedArguments ?? [:]
                let operation = arguments["operation"] as? String ?? "add"
                let a = arguments["a"] as? Double ?? 0
                let b = arguments["b"] as? Double ?? 0
                
                let result: Double
                switch operation {
                case "add":
                    result = a + b
                case "subtract":
                    result = a - b
                case "multiply":
                    result = a * b
                case "divide":
                    result = b != 0 ? a / b : 0
                default:
                    result = 0
                }
                
                return ToolResult(
                    toolCallId: toolCall.id,
                    result: .text("The result of \(operation)ing \(a) and \(b) is \(result)"),
                    executionTime: 0.05
                )
            default:
                throw AIGenerationError.toolExecutionFailed(
                    toolName: toolCall.function.name,
                    error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool"])
                )
            }
        })
        
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.2)
            .maxTokens(300)
        
        print("🧪 Testing tool calling with real Google Gemini API...")
        
        // Define tools
        let weatherTool = Tool(
            function: ToolFunction(
                name: "get_weather",
                description: "Get current weather for a location",
                parameters: JSONSchema.object(properties: [
                    "location": .string(enum: ["San Francisco, CA", "New York, NY", "London, UK"]),
                    "unit": .string(enum: ["celsius", "fahrenheit"])
                ], required: ["location", "unit"])
            )
        )
        
        let calculatorTool = Tool(
            function: ToolFunction(
                name: "calculate",
                description: "Perform basic mathematical calculations",
                parameters: JSONSchema.object(properties: [
                    "operation": .string(enum: ["add", "subtract", "multiply", "divide"]),
                    "a": .number(),
                    "b": .number()
                ], required: ["operation", "a", "b"])
            )
        )
        
        let response = try await client.generateText(
            model,
            messages: [Message.user("What's the weather like in San Francisco in celsius? Use the get_weather tool to get the actual weather data.")],
            tools: [weatherTool, calculatorTool],
            maxSteps: 3
        )
        
        // Verify tool calling behavior
        #expect(response.finishReason == FinishReason.stop, "Should complete with final answer after tool execution")
        #expect(!response.toolCalls.isEmpty, "Should have made tool calls")
        #expect(response.toolCalls.first?.function.name == "get_weather", "Should call weather tool")
        #expect(response.stepCount >= 2, "Should have multiple steps")
        #expect(response.text.contains("temperature") || response.text.contains("weather") || response.text.contains("°"), 
               "Final response should contain weather information")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Tool calling successful")
        print("🔧 Tools called: \(response.toolCalls.count)")
        print("📝 Final response: \(response.text)")
    }
    
    // MARK: - Multiple Tool Calls Test
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleMultipleToolCalls() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient(toolExecutor: { toolCall in
            switch toolCall.function.name {
            case "get_weather":
                let arguments = toolCall.function.parsedArguments ?? [:]
                let location = arguments["location"] as? String ?? "Unknown"
                let unit = arguments["unit"] as? String ?? "celsius"
                
                let temperature = unit == "celsius" ? "22°C" : "72°F"
                
                return ToolResult(
                    toolCallId: toolCall.id,
                    result: .text("Weather in \(location): \(temperature), Sunny"),
                    executionTime: 0.1
                )
            case "calculate":
                let arguments = toolCall.function.parsedArguments ?? [:]
                let operation = arguments["operation"] as? String ?? "add"
                let a = arguments["a"] as? Double ?? 0
                let b = arguments["b"] as? Double ?? 0
                
                let result: Double
                switch operation {
                case "add":
                    result = a + b
                case "multiply":
                    result = a * b
                default:
                    result = 0
                }
                
                return ToolResult(
                    toolCallId: toolCall.id,
                    result: .text("Result: \(result)"),
                    executionTime: 0.05
                )
            default:
                throw AIGenerationError.toolExecutionFailed(
                    toolName: toolCall.function.name,
                    error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool"])
                )
            }
        })
        
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.3)
            .maxTokens(400)
        
        print("🧪 Testing multiple tool calls with real Google Gemini API...")
        
        let weatherTool = Tool(
            function: ToolFunction(
                name: "get_weather",
                description: "Get current weather for a location",
                parameters: JSONSchema.object(properties: [
                    "location": .string(),
                    "unit": .string(enum: ["celsius", "fahrenheit"])
                ], required: ["location", "unit"])
            )
        )
        
        let calculatorTool = Tool(
            function: ToolFunction(
                name: "calculate",
                description: "Perform basic mathematical calculations",
                parameters: JSONSchema.object(properties: [
                    "operation": .string(enum: ["add", "multiply"]),
                    "a": .number(),
                    "b": .number()
                ], required: ["operation", "a", "b"])
            )
        )
        
        let response = try await client.generateText(
            model,
            messages: [Message.user("What's the weather in London? Also, calculate 15 + 25.")],
            tools: [weatherTool, calculatorTool],
            maxSteps: 5
        )
        
        // Verify multiple tool usage
        #expect(response.finishReason == FinishReason.stop, "Should complete successfully")
        #expect(response.toolCalls.count >= 2, "Should call at least 2 tools")
        #expect(response.stepCount >= 3, "Should have multiple steps")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        // Check that both tools were called
        let toolNames = Set(response.toolCalls.map { $0.function.name })
        #expect(toolNames.contains("get_weather"), "Should call weather tool")
        #expect(toolNames.contains("calculate"), "Should call calculator tool")
        
        print("✅ Multiple tool calls successful")
        print("🔧 Tools called: \(response.toolCalls.count)")
        print("📋 Tool names: \(Array(toolNames))")
        print("📝 Final response: \(response.text)")
    }
    
    // MARK: - Error Handling Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleErrorHandling() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .maxTokens(10) // Very low token limit to trigger length finish reason
        
        print("🧪 Testing error handling with real Google Gemini API...")
        
        let response = try await client.generateText(model, prompt: "Write a long essay about artificial intelligence and its impact on society")
        
        // Should finish due to length constraint
        #expect(response.finishReason == .length, "Should finish due to length limit")
        #expect(!response.text.isEmpty, "Should still have some content")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Error handling test successful")
        print("🚫 Finish reason: \(response.finishReason)")
        print("📝 Partial response: \(response.text)")
    }
    
    // MARK: - Safety Settings Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleSafetySettings() async throws {
        let provider: GoogleProvider
        do {
            let apiKey = try GoogleConfigReader.loadAPIKey()
            
            // Create provider with safety settings
            provider = GoogleProvider(
                apiKey: apiKey,
                safetySettings: [
                    GoogleSafetySetting(category: .harassment, threshold: .blockLowAndAbove),
                    GoogleSafetySetting(category: .hateSpeech, threshold: .blockMediumAndAbove)
                ]
            )
        } catch {
            if case E2ETestError.testSkipped(let message) = error {
                print("⚠️ \(message)")
            } else {
                print("⚠️ Skipping E2E tests: \(error.localizedDescription)")
            }
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.1)
            .maxTokens(100)
        
        print("🧪 Testing safety settings with real Google Gemini API...")
        
        // Test with benign content that should pass safety filters
        let response = try await client.generateText(model, prompt: "Write a friendly greeting and wish someone a good day.")
        
        // Should complete successfully with safety settings
        #expect(!response.text.isEmpty, "Should have response text")
        #expect(response.finishReason == .stop, "Should finish normally")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Safety settings test successful")
        print("📝 Response: \(response.text)")
    }
    
    // MARK: - Performance Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGooglePerformance() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gemini-2.0-flash-exp")
            .temperature(0.1)
            .maxTokens(50)
        
        print("🧪 Testing performance with real Google Gemini API...")
        
        let startTime = Date()
        
        let response = try await client.generateText(model, prompt: "Say 'Hello from Swift AI SDK!' and nothing else.")
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        #expect(!response.text.isEmpty, "Should have response")
        #expect(duration < 30.0, "Should complete within 30 seconds")
        
        print("✅ Performance test successful")
        print("⏱️  Duration: \(String(format: "%.2f", duration)) seconds")
        print("📝 Response: \(response.text)")
    }
    
    // MARK: - Model Variants Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealGoogleDifferentModels() async throws {
        let provider: GoogleProvider
        do {
            provider = try Self.createGoogleProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        
        print("🧪 Testing different Google models...")
        
        // Test multiple model variants
        let models = [
            "gemini-2.0-flash-exp",
            "gemini-1.5-flash"
        ]
        
        for modelId in models {
            print("Testing model: \(modelId)")
            
            let model = provider.languageModel(modelId)
                .temperature(0.2)
                .maxTokens(30)
            
            let response = try await client.generateText(model, prompt: "Say hello briefly.")
            
            #expect(!response.text.isEmpty, "Model \(modelId) should generate text")
            #expect(response.usage.totalTokens > 0, "Model \(modelId) should track usage")
            
            print("✅ Model \(modelId): \(response.text)")
        }
        
        print("✅ Multiple model test successful")
    }
}