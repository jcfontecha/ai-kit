import Testing
import Foundation
@testable import AIKit

// MARK: - Configuration Reader

/// Helper to read configuration from Config.plist
private struct ConfigReader {
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
            
            guard let apiKey = plist["OPENAI_API_KEY"] as? String, !apiKey.isEmpty else {
                throw E2ETestError.apiKeyMissing("OPENAI_API_KEY not found or empty in Config.plist")
            }
            
            return apiKey
        }
        
        guard let plist = NSDictionary(contentsOfFile: path),
              let apiKey = plist["OPENAI_API_KEY"] as? String, !apiKey.isEmpty else {
            throw E2ETestError.apiKeyMissing("OPENAI_API_KEY not found or empty in Config.plist")
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

// MARK: - E2E Tests with Real OpenAI Provider

struct E2EOpenAITests {
    
    // MARK: - Test Setup
    
    /// Create an OpenAI provider for testing, or skip if no API key
    private static func createOpenAIProviderOrSkip() throws -> OpenAIProvider {
        do {
            let apiKey = try ConfigReader.loadAPIKey()
            return OpenAIProvider(apiKey: apiKey)
        } catch {
            throw E2ETestError.testSkipped("Skipping E2E tests: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Basic Text Generation Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIBasicTextGeneration() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.1)
            .maxTokens(50)
        
        print("🧪 Testing basic text generation with real OpenAI API...")
        
        let response = try await client.generateText(model, prompt: "Say hello and explain what you are in one sentence.")
        
        // Verify response structure
        #expect(!response.text.isEmpty, "Response text should not be empty")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        #expect(response.usage.promptTokens > 0, "Should track prompt tokens")
        #expect(response.usage.completionTokens > 0, "Should track completion tokens")
        #expect(response.finishReason == FinishReason.stop, "Should finish normally")
        #expect(!response.messages.isEmpty, "Should have message history")
        #expect(response.messages.last?.role == .assistant, "Last message should be from assistant")
        
        print("✅ Basic text generation successful")
        print("📝 Response: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens) total (\(response.usage.promptTokens) prompt + \(response.usage.completionTokens) completion)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIConversation() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.3)
            .maxTokens(100)
        
        print("🧪 Testing conversation with real OpenAI API...")
        
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
        #expect(response.finishReason == FinishReason.stop, "Should finish normally")
        
        print("✅ Conversation test successful")
        print("📝 Response: \(response.text)")
    }
    
    // MARK: - Streaming Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIStreaming() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.2)
            .maxTokens(100)
        
        print("🧪 Testing streaming with real OpenAI API...")
        
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
        #expect(chunks.count > 5, "Should receive multiple chunks for this response")
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
    @Test func testRealOpenAIObjectGeneration() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        // Define a simple test object using SchemaProviding
        struct UserProfile: SchemaProviding {
            let name: String
            let age: Int
            let email: String
            let active: Bool
            
            static var schema: ObjectSchema<UserProfile> {
                .define(
                    name: "UserProfile",
                    description: "A user profile with name, age, email, and active status"
                ) {
                    Schema.string("name", description: "User's full name")
                    Schema.integer("age", description: "User's age", minimum: 18, maximum: 99)
                    Schema.email("email", description: "User's email address")
                    Schema.boolean("active", description: "Whether the user account is active")
                }
            }
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.0)
            .maxTokens(200)
        
        print("🧪 Testing object generation with real OpenAI API...")
        
        let response = try await client.generateObject(
            model,
            prompt: "Generate a user profile for John Doe, age 30, email john@example.com, active status true",
            type: UserProfile.self
        )
        
        // Verify the generated object
        let userProfile = response.object
        
        #expect(!userProfile.name.isEmpty, "Name should not be empty")
        #expect(userProfile.age >= 18 && userProfile.age <= 99, "Age should be within valid range")
        #expect(userProfile.email.contains("@"), "Email should contain @ symbol")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        #expect(response.finishReason == .stop || response.finishReason == .toolCalls, "Should finish normally (stop or toolCalls)")
        
        print("✅ Object generation successful")
        print("👤 Generated user: \(userProfile.name), age \(userProfile.age), email: \(userProfile.email), active: \(userProfile.active)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIComplexObjectGeneration() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        // Define complex nested structures using SchemaProviding
        struct Ingredient: SchemaProviding {
            let name: String
            let amount: String
            let optional: Bool?
            
            static var schema: ObjectSchema<Ingredient> {
                .define(
                    name: "Ingredient",
                    description: "Recipe ingredient with quantity"
                ) {
                    Schema.string("name", description: "Ingredient name")
                    Schema.string("amount", description: "Quantity needed")
                    Schema.boolean("optional", description: "Whether ingredient is optional", required: false)
                }
            }
        }
        
        struct Recipe: SchemaProviding {
            let name: String
            let description: String
            let prepTime: Int
            let cookTime: Int
            let difficulty: String
            let ingredients: [Ingredient]
            let steps: [String]
            let servings: Int
            
            static var schema: ObjectSchema<Recipe> {
                .define(
                    name: "Recipe",
                    description: "A detailed recipe with ingredients and cooking instructions"
                ) {
                    Schema.string("name", description: "Recipe name")
                    Schema.string("description", description: "Recipe description")
                    Schema.integer("prepTime", description: "Preparation time in minutes", minimum: 0)
                    Schema.integer("cookTime", description: "Cooking time in minutes", minimum: 0)
                    Schema.string("difficulty", 
                                 description: "Recipe difficulty level",
                                 enum: ["easy", "medium", "hard"])
                    Schema.array("ingredients", 
                                of: Ingredient.self,
                                description: "List of recipe ingredients",
                                minItems: 2)
                    Schema.array("steps", 
                                elementSchema: .string(minLength: 1),
                                description: "Cooking instructions",
                                minItems: 3)
                    Schema.integer("servings", description: "Number of servings", minimum: 1)
                }
            }
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.2)
            .maxTokens(800)
        
        print("🧪 Testing complex object generation with real OpenAI API...")
        
        let response = try await client.generateObject(
            model,
            prompt: "Generate a simple pasta recipe with 3-4 ingredients and clear cooking steps",
            type: Recipe.self
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
        #expect(response.finishReason == .stop || response.finishReason == .toolCalls, "Should finish normally (stop or toolCalls)")
        
        print("✅ Complex object generation successful")
        print("🍝 Generated recipe: \(recipe.name)")
        print("⏱️  Prep: \(recipe.prepTime)min, Cook: \(recipe.cookTime)min, Difficulty: \(recipe.difficulty)")
        print("🥘 Ingredients: \(recipe.ingredients.count), Steps: \(recipe.steps.count), Servings: \(recipe.servings)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    // MARK: - Tool Calling Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIToolCalling() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
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
            default:
                throw AIGenerationError.toolExecutionFailed(
                    toolName: toolCall.function.name,
                    error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool"])
                )
            }
        })
        
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.2)
            .maxTokens(300)
        
        print("🧪 Testing tool calling with real OpenAI API...")
        
        // Define a weather tool
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
        
        let response = try await client.generateText(
            model,
            messages: [Message.user("What's the weather like in San Francisco? Please provide actual weather data.")],
            tools: [weatherTool],
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
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIStreamingToolCalling() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient(toolExecutor: { toolCall in
            switch toolCall.function.name {
            case "search_notes":
                // Parse arguments
                let arguments = toolCall.function.parsedArguments ?? [:]
                let query = arguments["query"] as? String ?? "unknown"
                
                let searchResults = """
                Found 3 notes matching '\(query)':
                1. Bachata Spins Fundamentals - Cross-body lead with right hand connection
                2. Salsa Turn Patterns - Multiple spin sequences from basic position  
                3. Kizomba Rotation Techniques - Close-hold spinning variations
                """
                
                return ToolResult(
                    toolCallId: toolCall.id,
                    result: .text(searchResults),
                    executionTime: 0.2
                )
            default:
                throw AIGenerationError.toolExecutionFailed(
                    toolName: toolCall.function.name,
                    error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool"])
                )
            }
        })
        
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.7)
            .maxTokens(500)
        
        print("🧪 Testing streaming tool calling with real OpenAI API...")
        
        // Define a search tool similar to the user's use case
        let searchTool = Tool(
            function: ToolFunction(
                name: "search_notes",
                description: "Search through the user's dance notes by content, title, instructor, dance style, or tags",
                parameters: JSONSchema.object(properties: [
                    "query": .string()
                ], required: ["query"])
            )
        )
        
        // Test streaming with tool calls
        var accumulatedText = ""
        var toolCallsReceived: [ToolCall] = []
        var toolCallStreamingEvents: [ToolCallStreamingStart] = []
        var toolCallDeltas: [ToolCallDelta] = []
        var chunkCount = 0
        var hasToolCallFinishReason = false
        
        let stream = await client.streamText(
            model,
            messages: [Message.user("Search through my notes for types of spins")],
            tools: [searchTool],
            toolChoice: .auto
        )
        
        for try await chunk in stream {
            chunkCount += 1
            print("📦 Chunk \(chunkCount): delta='\(chunk.delta)', toolCalls=\(chunk.toolCalls?.count ?? 0)")
            
            // Accumulate text
            accumulatedText += chunk.delta
            
            // Collect tool calls
            if let toolCalls = chunk.toolCalls {
                toolCallsReceived.append(contentsOf: toolCalls)
                print("🔧 Received \(toolCalls.count) tool call(s)")
                for toolCall in toolCalls {
                    print("   - \(toolCall.function.name): \(toolCall.function.arguments)")
                }
            }
            
            // Collect streaming events
            if let streamingStart = chunk.toolCallStreamingStart {
                toolCallStreamingEvents.append(streamingStart)
                print("🌊 Tool call streaming started: \(streamingStart.toolName) (ID: \(streamingStart.toolCallId))")
            }
            
            if let delta = chunk.toolCallDelta {
                toolCallDeltas.append(delta)
                print("🔄 Tool call delta: \(delta.toolName) - '\(delta.argsTextDelta)'")
            }
            
            // Check finish reason
            if let finishReason = chunk.finishReason {
                print("🏁 Stream finished with reason: \(finishReason)")
                if finishReason == .toolCalls {
                    hasToolCallFinishReason = true
                }
            }
        }
        
        print("✅ Streaming completed")
        print("📊 Chunks received: \(chunkCount)")
        print("📝 Accumulated text: '\(accumulatedText)'")
        print("🔧 Tool calls: \(toolCallsReceived.count)")
        print("🌊 Streaming start events: \(toolCallStreamingEvents.count)")  
        print("🔄 Tool call deltas: \(toolCallDeltas.count)")
        
        // Verify streaming tool call behavior
        #expect(hasToolCallFinishReason, "Should have toolCalls finish reason")
        #expect(!toolCallsReceived.isEmpty, "Should receive tool calls in streaming")
        #expect(toolCallsReceived.first?.function.name == "search_notes", "Should call search_notes tool")
        #expect(!toolCallStreamingEvents.isEmpty, "Should receive tool call streaming start events")
        #expect(!toolCallDeltas.isEmpty, "Should receive tool call delta events")
        
        // Verify tool call arguments are properly accumulated
        if let firstToolCall = toolCallsReceived.first {
            #expect(!firstToolCall.function.arguments.isEmpty, "Tool call arguments should not be empty")
            #expect(firstToolCall.function.parsedArguments != nil, "Should be able to parse tool arguments")
            print("🔍 Tool arguments: \(firstToolCall.function.arguments)")
        }
        
        print("✅ Streaming tool calling fix verified!")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIStreamingToolCallExecution() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient(toolExecutor: { toolCall in
            switch toolCall.function.name {
            case "search_notes":
                let arguments = toolCall.function.parsedArguments ?? [:]
                let query = arguments["query"] as? String ?? "unknown"
                
                let searchResults = """
                Found 3 notes matching '\(query)':
                1. Bachata Basic Turns - Right and left basic turns from cross-body position
                2. Salsa Multiple Turns - Continuous turn sequences with proper timing
                3. Partner Connection During Turns - Maintaining frame while spinning
                """
                
                return ToolResult(
                    toolCallId: toolCall.id,
                    result: .text(searchResults),
                    executionTime: 0.2
                )
            default:
                throw AIGenerationError.toolExecutionFailed(
                    toolName: toolCall.function.name,
                    error: NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool"])
                )
            }
        })
        
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.7)
            .maxTokens(500)
        
        print("🧪 Testing full streaming tool call execution flow...")
        
        let searchTool = Tool(
            function: ToolFunction(
                name: "search_notes",
                description: "Search through the user's dance notes by content, title, instructor, dance style, or tags",
                parameters: JSONSchema.object(properties: [
                    "query": .string()
                ], required: ["query"])
            )
        )
        
        // Step 1: Initial streaming request with tools
        var messages: [Message] = [Message.user("Can you search my notes and tell me which types of turns I should practice?")]
        var accumulatedText = ""
        var toolCallsReceived: [ToolCall] = []
        var hasToolCallFinishReason = false
        
        print("🌊 Step 1: Initial streaming request...")
        let initialStream = await client.streamText(
            model,
            messages: messages,
            tools: [searchTool],
            toolChoice: .auto
        )
        
        for try await chunk in initialStream {
            accumulatedText += chunk.delta
            if let toolCalls = chunk.toolCalls {
                toolCallsReceived.append(contentsOf: toolCalls)
            }
            if let finishReason = chunk.finishReason, finishReason == .toolCalls {
                hasToolCallFinishReason = true
            }
        }
        
        print("✅ Initial stream completed")
        print("🔧 Tool calls received: \(toolCallsReceived.count)")
        
        #expect(!toolCallsReceived.isEmpty, "Should receive tool calls")
        #expect(hasToolCallFinishReason, "Should have toolCalls finish reason")
        
        // Step 2: Execute tools and add results to conversation
        print("🔧 Step 2: Executing tools...")
        
        // Add assistant message with tool calls
        if accumulatedText.isEmpty {
            messages.append(.assistant(toolCalls: toolCallsReceived))
        } else {
            let assistantMessage = Message(
                role: .assistant,
                content: [.text(accumulatedText)],
                toolCalls: toolCallsReceived
            )
            messages.append(assistantMessage)
        }
        
        // Execute tools and add results
        for toolCall in toolCallsReceived {
            print("🔧 Executing tool: \(toolCall.function.name)")
            // Manually execute the tool since we can't access the client's executor directly
            let toolResult = try await executeSearchNotesTool(toolCall)
            messages.append(.tool(result: toolResult))
        }
        
        // Helper function to execute the search tool
        func executeSearchNotesTool(_ toolCall: ToolCall) async throws -> ToolResult {
            let arguments = toolCall.function.parsedArguments ?? [:]
            let query = arguments["query"] as? String ?? "unknown"
            
            let searchResults = """
            Found 3 notes matching '\(query)':
            1. Bachata Basic Turns - Right and left basic turns from cross-body position
            2. Salsa Multiple Turns - Continuous turn sequences with proper timing
            3. Partner Connection During Turns - Maintaining frame while spinning
            """
            
            return ToolResult(
                toolCallId: toolCall.id,
                result: .text(searchResults),
                executionTime: 0.2
            )
        }
        
        // Step 3: Get follow-up response with tool results
        print("🔄 Step 3: Getting follow-up response...")
        var followUpText = ""
        var followUpChunks = 0
        
        let followUpStream = await client.streamText(model, messages: messages) // No tools in follow-up
        for try await chunk in followUpStream {
            followUpChunks += 1
            followUpText += chunk.delta
            
            if let finishReason = chunk.finishReason {
                print("🏁 Follow-up finished with reason: \(finishReason)")
            }
        }
        
        print("✅ Follow-up stream completed")
        print("📊 Follow-up chunks: \(followUpChunks)")
        print("📝 Follow-up text length: \(followUpText.count)")
        print("📝 Follow-up response: \(followUpText)")
        
        // Verify the complete flow worked
        #expect(!followUpText.isEmpty, "Should have follow-up response text")
        #expect(followUpText.contains("turn") || followUpText.contains("practice") || followUpText.contains("notes"), 
               "Response should reference the search results")
        
        print("✅ Complete streaming tool execution flow verified!")
    }
    
    // MARK: - Error Handling Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIErrorHandling() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .maxTokens(1) // Very low token limit to trigger length finish reason
        
        print("🧪 Testing error handling with real OpenAI API...")
        
        let response = try await client.generateText(model, prompt: "Write a long essay about artificial intelligence and its impact on society")
        
        // Should finish due to length constraint
        #expect(response.finishReason == .length, "Should finish due to length limit")
        #expect(!response.text.isEmpty, "Should still have some content")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Error handling test successful")
        print("🚫 Finish reason: \(response.finishReason)")
        print("📝 Partial response: \(response.text)")
    }
    
    // MARK: - Performance Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIPerformance() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.1)
            .maxTokens(50)
        
        print("🧪 Testing performance with real OpenAI API...")
        
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
    
    // MARK: - Automatic Schema Generation Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAISchemaProvidingGeneration() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        // Test SchemaProviding with OpenAI E2E integration
        let client = AIClient()
        
        // Use gpt-4.1-nano as mandated by CLAUDE.md for E2E testing
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.0)  // Lower temperature for more consistent testing
            .maxTokens(300)
        
        // Define a test struct using SchemaProviding with various property types
        struct PersonProfile: SchemaProviding {
            let name: String
            let age: Int
            let email: String?
            let isActive: Bool
            
            static var schema: ObjectSchema<PersonProfile> {
                .define(
                    name: "PersonProfile",
                    description: "A person profile with name, age, optional email, and active status"
                ) {
                    Schema.string("name", description: "Person's full name", minLength: 1)
                    Schema.integer("age", description: "Person's age", minimum: 0, maximum: 150)
                    Schema.email("email", description: "Person's email address", required: false)
                    Schema.boolean("isActive", description: "Whether the person is active")
                }
            }
        }
        
        print("🧪 Testing SchemaProviding generation with real OpenAI API...")
        
        // Debug: Print the schema to see what OpenAI receives
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let schemaData = try? encoder.encode(PersonProfile.schema),
           let schemaString = String(data: schemaData, encoding: .utf8) {
            print("🔍 SchemaProviding schema for PersonProfile:")
            print(schemaString)
        }
        
        let response = try await client.generateObject(
            model,
            prompt: """
            Create a person profile with the following details:
            - Name: "Alice Johnson"
            - Age: 28
            - Email: "alice.johnson@example.com" 
            - Is Active: true
            """,
            type: PersonProfile.self
        )
        
        let person = response.object
        
        // Verify the generated object matches our expectations
        #expect(person.name.contains("Alice"), "Name should contain Alice")
        #expect(person.age >= 25 && person.age <= 30, "Age should be around 28")
        #expect(person.email?.contains("alice") == true, "Email should contain alice")
        #expect(person.isActive == true, "Active status should be true")
        
        // Verify response metadata
        #expect(response.finishReason == FinishReason.stop || response.finishReason == FinishReason.toolCalls, "Should complete successfully (stop or toolCalls)")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        // Verify schema validation passed
        #expect(response.validationResult?.isValid == true, "Schema validation should pass")
        
        print("✅ SchemaProviding generation successful")
        print("👤 Generated person: \(person.name), age \(person.age), email: \(person.email ?? "nil"), active: \(person.isActive)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAISchemaConvenienceMethods() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        // Test the SchemaProviding convenience with optional properties
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.0)
            .maxTokens(200)
        
        // Define a struct with optional properties using SchemaProviding
        struct ProductInfo: SchemaProviding {
            let id: String
            let name: String
            let price: Double
            let description: String?
            let category: String?
            
            static var schema: ObjectSchema<ProductInfo> {
                .define(
                    name: "ProductInfo",
                    description: "Product information with optional fields"
                ) {
                    Schema.string("id", description: "Product identifier", minLength: 1)
                    Schema.string("name", description: "Product name", minLength: 1, maxLength: 100)
                    Schema.number("price", description: "Product price in USD", minimum: 0)
                    Schema.string("description", description: "Product description", required: false)
                    Schema.string("category", description: "Product category", required: false)
                }
            }
        }
        
        print("🧪 Testing schema convenience methods with real OpenAI API...")
        
        // Debug: Print the SchemaProviding schema
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let schemaData = try? encoder.encode(ProductInfo.schema),
           let schemaString = String(data: schemaData, encoding: .utf8) {
            print("🔍 SchemaProviding schema for ProductInfo:")
            print(schemaString)
        }
        
        let response = try await client.generateObject(
            model,
            prompt: """
            Create a product with:
            - ID: "PROD-001"
            - Name: "Wireless Headphones"
            - Price: 99.99
            - Description: "High-quality wireless headphones"
            - Category: "Electronics"
            """,
            type: ProductInfo.self
        )
        
        let product = response.object
        
        // Verify the generated object
        #expect(product.id.contains("PROD"), "ID should contain PROD")
        #expect(product.name.lowercased().contains("headphones"), "Name should contain headphones")
        #expect(product.price > 50.0 && product.price < 150.0, "Price should be reasonable")
        #expect(product.description?.lowercased().contains("headphones") == true, "Description should mention headphones")
        #expect(product.category?.lowercased().contains("electronics") == true, "Category should be Electronics")
        
        // Verify response metadata
        #expect(response.finishReason == FinishReason.stop || response.finishReason == FinishReason.toolCalls, "Should complete successfully (stop or toolCalls)")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Schema convenience methods test successful")
        print("🛍️ Generated product: \(product.name) (\(product.id)) - $\(product.price)")
        print("📝 Description: \(product.description ?? "nil")")
        print("🏷️ Category: \(product.category ?? "nil")")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    // MARK: - Image Support Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIImageSupport() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        // Use a vision-capable model for image analysis
        let model = provider.languageModel("gpt-4o-mini")
            .temperature(0.5)
            .maxTokens(150)
        
        print("🧪 Testing image support with real OpenAI API...")
        
        // Load the sample image
        let testBundle = Bundle.module
        guard let imagePath = testBundle.path(forResource: "sample_image", ofType: "jpg") else {
            print("⚠️ Could not find sample_image.jpg, skipping test")
            return
        }
        
        let imageURL = URL(fileURLWithPath: imagePath)
        let imageData = try Data(contentsOf: imageURL)
        
        print("📸 Loaded image: \(imageData.count) bytes")
        
        // Create message with image
        let imageContent = ImageContent.data(imageData, mimeType: "image/jpeg")
        let messages = [CoreMessage.user("What do you see in this image? Please describe it briefly.", image: imageContent)]
        
        let response = try await client.generateText(model, messages: messages)
        
        // Verify response
        #expect(!response.text.isEmpty, "Should have a response describing the image")
        #expect(response.text.count > 20, "Response should be substantive")
        #expect(response.text.lowercased().contains("cat"), "Response should identify the cat in the image")
        #expect(response.finishReason == FinishReason.stop, "Should finish normally")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Image support test successful")
        print("📝 Image description: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIImageURLSupport() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        // Use a vision-capable model for image analysis
        let model = provider.languageModel("gpt-4o-mini")
            .temperature(0.5)
            .maxTokens(100)
        
        print("🧪 Testing image URL support with real OpenAI API...")
        
        // Use a public image URL for testing
        let imageURL = URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/320px-Cat03.jpg")!
        let imageContent = ImageContent.url(imageURL, mimeType: "image/jpeg")
        let messages = [CoreMessage.user("What animal is in this image?", image: imageContent)]
        
        let response = try await client.generateText(model, messages: messages)
        
        // Verify response mentions a cat
        #expect(!response.text.isEmpty, "Should have a response")
        #expect(response.text.lowercased().contains("cat"), "Response should identify the cat")
        #expect(response.finishReason == FinishReason.stop, "Should finish normally")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Image URL support test successful")
        print("📝 Response: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIMultipleImagesAndText() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        // Use a vision-capable model
        let model = provider.languageModel("gpt-4o-mini")
            .temperature(0.5)
            .maxTokens(150)
        
        print("🧪 Testing multiple images with text using real OpenAI API...")
        
        // Create a message with text and image content mixed
        let imageURL = URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4d/Cat_November_2010-1a.jpg/320px-Cat_November_2010-1a.jpg")!
        let message = CoreMessage(
            role: .user,
            content: [
                .text("I have a question about this image:"),
                .image(ImageContent.url(imageURL)),
                .text("What color is the cat in the image?")
            ]
        )
        
        let response = try await client.generateText(model, messages: [message])
        
        // Verify response
        #expect(!response.text.isEmpty, "Should have a response")
        #expect(response.text.count > 10, "Response should be substantive")
        #expect(response.finishReason == FinishReason.stop, "Should finish normally")
        
        print("✅ Multiple content types test successful")
        print("📝 Response: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIMultipleImagesInSingleMessage() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        // Use a vision-capable model
        let model = provider.languageModel("gpt-4o-mini")
            .temperature(0.5)
            .maxTokens(200)
        
        print("🧪 Testing multiple images (cat and dog) in single message with real OpenAI API...")
        
        // Load both sample images
        let testBundle = Bundle.module
        guard let catImagePath = testBundle.path(forResource: "sample_image", ofType: "jpg"),
              let dogImagePath = testBundle.path(forResource: "sample_image_2", ofType: "jpg") else {
            print("⚠️ Could not find sample images, skipping test")
            return
        }
        
        let catImageURL = URL(fileURLWithPath: catImagePath)
        let dogImageURL = URL(fileURLWithPath: dogImagePath)
        
        let catImageData = try Data(contentsOf: catImageURL)
        let dogImageData = try Data(contentsOf: dogImageURL)
        
        print("📸 Loaded cat image: \(catImageData.count) bytes")
        print("📸 Loaded dog image: \(dogImageData.count) bytes")
        
        // Create message with both images
        let catImageContent = ImageContent.data(catImageData, mimeType: "image/jpeg")
        let dogImageContent = ImageContent.data(dogImageData, mimeType: "image/jpeg")
        
        let message = CoreMessage(
            role: .user,
            content: [
                .text("Look at these two images:"),
                .image(catImageContent),
                .text("and"),
                .image(dogImageContent),
                .text("What animals do you see in these images? Please describe both.")
            ]
        )
        
        let response = try await client.generateText(model, messages: [message])
        
        // Verify response mentions both animals
        #expect(!response.text.isEmpty, "Should have a response")
        #expect(response.text.lowercased().contains("cat"), "Response should mention the cat")
        #expect(response.text.lowercased().contains("dog") || response.text.lowercased().contains("puppy"), "Response should mention the dog/puppy")
        #expect(response.finishReason == FinishReason.stop, "Should finish normally")
        #expect(response.usage.totalTokens > 0, "Should track token usage")
        
        print("✅ Multiple images test successful")
        print("📝 Response: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
}