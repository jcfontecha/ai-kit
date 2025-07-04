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

// MARK: - Test Types for E2E Tests

@AIModel
private struct E2EUserProfile: Codable, Sendable {
    @Field("Full name")
    let name: String
    
    @Field("Age in years")
    let age: Int
    
    @Field("Email address")
    let email: String
    
    @Field("Account active status")
    let active: Bool
}

@AIModel
private struct E2EIngredient: Codable, Sendable {
    @Field("Ingredient name")
    let name: String
    
    @Field("Amount with units")
    let amount: String
    
    @Field("Whether ingredient is optional")
    let optional: Bool?
}

@AIModel
private struct E2ERecipe: Codable, Sendable {
    @Field("Recipe name")
    let name: String
    
    @Field("Recipe description")
    let description: String
    
    @Field("Preparation time in minutes")
    let prepTime: Int
    
    @Field("Cooking time in minutes")
    let cookTime: Int
    
    @Field("Difficulty level", enum: ["easy", "medium", "hard"])
    let difficulty: String
    
    @Field("List of ingredients")
    let ingredients: [E2EIngredient]
    
    @Field("Cooking steps")
    let steps: [String]
    
    @Field("Number of servings")
    let servings: Int
}

@AIModel
private struct E2EPersonProfile: Codable, Sendable {
    @Field("Full name", minLength: 1, maxLength: 100)
    let name: String
    
    @Field("Age in years", range: 0...150)
    let age: Int
    
    @Field("Email address", format: "email")
    let email: String?
    
    @Field("Account active status")
    let isActive: Bool
}

@AIModel
private struct E2EProductInfo: Codable, Sendable {
    @Field("Product name", minLength: 1, maxLength: 200)
    let name: String
    
    @Field("Product SKU", pattern: "^[A-Z]{3}-\\d{4}$")
    let sku: String
    
    @Field("Price in USD", range: 0.01...99999.99)
    let price: Double
    
    @Field("Stock availability")
    let inStock: Bool
    
    @Field("Product category", enum: ["electronics", "books", "clothing", "home", "other"])
    let category: String
}

@AIModel
private struct E2ESimpleProduct: Codable, Sendable {
    @Field("Product identifier", minLength: 1)
    let id: String
    
    @Field("Product name", minLength: 1, maxLength: 100)
    let name: String
    
    @Field("Product price in USD", range: 0...999999.99)
    let price: Double
    
    @Field("Product description")
    let description: String?
    
    @Field("Product category")
    let category: String?
}

@AIModel
private struct E2EFieldValidationTest: Codable, Sendable {
    @Field("A code that MUST start with 'TEST-' followed by exactly 4 digits")
    let testCode: String
    
    @Field("A special number that MUST be exactly 42")
    let specialNumber: Int
    
    @Field("A greeting that MUST contain the word 'Swift'")
    let greeting: String
    
    @Field("A hex color code that MUST be in format #RRGGBB")
    let colorCode: String
    
    @Field("A score between 0 and 100 that MUST be divisible by 5")
    let score: Int
    
    @Field("An email that MUST end with '@aikit.test'")
    let email: String
    
    @Field("A boolean that MUST be true if score is greater than 50")
    let isPassing: Bool
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
        
        for try await chunk in stream.textStream {
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
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.0)
            .maxTokens(200)
        
        print("🧪 Testing object generation with real OpenAI API...")
        
        let response = try await client.generateObject(
            model,
            prompt: "Generate a user profile for John Doe, age 30, email john@example.com, active status true",
            type: E2EUserProfile.self
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
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.2)
            .maxTokens(800)
        
        print("🧪 Testing complex object generation with real OpenAI API...")
        
        let response = try await client.generateObject(
            model,
            prompt: "Generate a simple pasta recipe with 3-4 ingredients and clear cooking steps",
            type: E2ERecipe.self
        )
        
        // Verify the complex structure
        let recipe = response.object
        
        #expect(!recipe.name.isEmpty, "Recipe should have a name")
        #expect(!recipe.description.isEmpty, "Recipe should have a description")
        #expect(recipe.prepTime >= 0, "Prep time should be non-negative")
        #expect(recipe.cookTime >= 0, "Cook time should be non-negative")
        #expect(["easy", "medium", "hard"].contains(recipe.difficulty.lowercased()), "Difficulty should be valid")
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
        
        let client = AIClient()
        
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
            ),
            execute: { @Sendable toolCall in
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
            }
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
        
        let client = AIClient()
        
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
            ),
            execute: { @Sendable toolCall in
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
            }
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
            toolChoice: ToolChoice.auto
        )
        
        for try await chunk in stream.textStream {
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
        
        let client = AIClient()
        
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
            ),
            execute: { @Sendable toolCall in
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
            }
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
            toolChoice: ToolChoice.auto
        )
        
        for try await chunk in initialStream.textStream {
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
        for try await chunk in followUpStream.textStream {
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
        
        print("🧪 Testing SchemaProviding generation with real OpenAI API...")
        
        // Debug: Print the schema to see what OpenAI receives
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let schemaData = try? encoder.encode(E2EPersonProfile.schema),
           let schemaString = String(data: schemaData, encoding: .utf8) {
            print("🔍 SchemaProviding schema for E2EPersonProfile:")
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
            type: E2EPersonProfile.self
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
        
        print("🧪 Testing schema convenience methods with real OpenAI API...")
        
        // Debug: Print the SchemaProviding schema
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let schemaData = try? encoder.encode(E2ESimpleProduct.schema),
           let schemaString = String(data: schemaData, encoding: .utf8) {
            print("🔍 SchemaProviding schema for E2ESimpleProduct:")
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
            type: E2ESimpleProduct.self
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
    
    // MARK: - Audio Support Tests
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIAudioFileSupport() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        
        // Use gpt-4o-audio-preview as it actually works with audio
        let model = provider.languageModel("gpt-4o-audio-preview")
            .temperature(0.7)
            .maxTokens(200)
        
        print("🧪 Testing audio file support with real OpenAI API...")
        
        // Load sample audio file
        let testBundle = Bundle.module
        guard let audioPath = testBundle.path(forResource: "sample_audio", ofType: "mp3") else {
            print("⚠️ Could not find sample MP3 file, skipping test")
            return
        }
        
        let audioURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: audioURL)
        
        print("🎵 Loaded MP3 file: \(audioData.count) bytes")
        
        // Create audio content using the MP3 convenience method
        let audioContent = FileContent.mp3(audioData, filename: "sample_audio.mp3")
        
        // Create message with audio - use direct transcription prompt that works
        let message = CoreMessage(
            role: .user,
            content: [
                .text("If there is any speech in this audio, please transcribe it. If not, describe what you hear."),
                .file(audioContent)
            ]
        )
        
        do {
            let response = try await client.generateText(model, messages: [message])
            
            // The model should transcribe the audio content
            #expect(!response.text.isEmpty, "Should have a response")
            #expect(response.finishReason == FinishReason.stop, "Should finish normally")
            #expect(response.usage.totalTokens > 0, "Should track token usage")
            
            // The sample audio says "This is a sample audio file"
            let responseLower = response.text.lowercased()
            #expect(responseLower.contains("sample") && responseLower.contains("audio"), 
                   "Response should contain transcribed content: '\(response.text)'")
            
            print("✅ Audio file test successful")
            print("📝 Response: \(response.text)")
            print("🔢 Token usage: \(response.usage.totalTokens)")
        } catch {
            // This should work with audio-capable models
            print("❌ Audio test failed with error: \(error)")
            throw error
        }
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test(.disabled("OpenAI API returning 500 errors for audio")) 
    func testRealOpenAIAudioWithVisualContext() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        
        // Use gpt-4o-mini-audio-preview as it works with visual context
        let model = provider.languageModel("gpt-4o-mini-audio-preview")
            .temperature(0.7)
            .maxTokens(200)
        
        print("🧪 Testing audio with visual context (matching working example)...")
        
        // Load sample audio file
        let testBundle = Bundle.module
        guard let audioPath = testBundle.path(forResource: "sample_audio", ofType: "mp3") else {
            print("⚠️ Could not find sample MP3 file, skipping test")
            return
        }
        
        let audioURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: audioURL)
        
        print("🎵 Loaded MP3 file: \(audioData.count) bytes")
        
        // Create audio content using the MP3 convenience method
        let audioContent = FileContent.mp3(audioData, filename: "sample_audio.mp3")
        
        // Test 1: Direct transcription (this works!)
        print("\n📍 Test 1: Direct transcription request...")
        let message1 = CoreMessage(
            role: .user,
            content: [
                .text("If there is any speech in this audio, please transcribe it. If not, describe what you hear."),
                .file(audioContent)
            ]
        )
        
        do {
            let response1 = try await client.generateText(model, messages: [message1])
            
            #expect(!response1.text.isEmpty, "Should have a response")
            #expect(response1.finishReason == FinishReason.stop, "Should finish normally")
            #expect(response1.usage.totalTokens > 0, "Should track token usage")
            
            // Should transcribe "This is a sample audio file"
            let responseLower = response1.text.lowercased()
            #expect(responseLower.contains("sample") && responseLower.contains("audio"), 
                   "Should transcribe the audio content: '\(response1.text)'")
            
            print("✅ Direct transcription: \(response1.text)")
            
            // Test 2: With visual context (model says it can't analyze)
            print("\n📍 Test 2: With visual context (for comparison)...")
            let contextText = """
            Please analyze this audio and determine if it contains speech that should be transcribed.
            
            Visual context of the video:
            - Description: A person speaking directly to the camera in what appears to be a tutorial or presentation setting
            - Main subject: A person presenting information
            - Visual style: Talking head style video shot
            """
            
            let message2 = CoreMessage(
                role: .user,
                content: [
                    .text(contextText),
                    .file(audioContent)
                ]
            )
            
            let response2 = try await client.generateText(model, messages: [message2])
            print("📝 With context response: \(response2.text)")
            
            print("\n✅ Both audio tests completed successfully")
            print("🔢 Total token usage: \(response1.usage.totalTokens + response2.usage.totalTokens)")
        } catch {
            print("❌ Audio with context test failed with error: \(error)")
            throw error
        }
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test(.disabled("OpenAI API returning 500 errors for WAV audio")) 
    func testRealOpenAIWavAudioSupport() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4o-mini-audio-preview-2024-12-17")
            .temperature(0.7)
            .maxTokens(200)
        
        print("🧪 Testing WAV audio support with real OpenAI API...")
        
        // Create a simple WAV file data (44 bytes WAV header + minimal audio data)
        // This is a valid but tiny WAV file for testing
        let wavHeader: [UInt8] = [
            // RIFF header
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            0x24, 0x00, 0x00, 0x00, // File size - 8
            0x57, 0x41, 0x56, 0x45, // "WAVE"
            // fmt chunk
            0x66, 0x6D, 0x74, 0x20, // "fmt "
            0x10, 0x00, 0x00, 0x00, // Chunk size = 16
            0x01, 0x00,             // Audio format = 1 (PCM)
            0x01, 0x00,             // Number of channels = 1
            0x44, 0xAC, 0x00, 0x00, // Sample rate = 44100
            0x88, 0x58, 0x01, 0x00, // Byte rate = 88200
            0x02, 0x00,             // Block align = 2
            0x10, 0x00,             // Bits per sample = 16
            // data chunk
            0x64, 0x61, 0x74, 0x61, // "data"
            0x00, 0x00, 0x00, 0x00  // Data size = 0
        ]
        let wavData = Data(wavHeader)
        
        // Create WAV audio content
        let audioContent = FileContent.wav(wavData, filename: "test.wav")
        
        // Create message with audio and text
        let message = CoreMessage(
            role: .user,
            content: [
                .text("This is a test WAV audio file. Please acknowledge that you received it."),
                .file(audioContent)
            ]
        )
        
        do {
            let response = try await client.generateText(model, messages: [message])
            
            #expect(!response.text.isEmpty, "Should have a response")
            #expect(response.finishReason == FinishReason.stop, "Should finish normally")
            #expect(response.usage.totalTokens > 0, "Should track token usage")
            
            print("✅ WAV audio test successful")
            print("📝 Response: \(response.text)")
            print("🔢 Token usage: \(response.usage.totalTokens)")
        } catch {
            // This should work with audio-capable models
            print("❌ WAV audio test failed with error: \(error)")
            throw error
        }
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    @Test func testRealOpenAIFieldDescriptionValidation() async throws {
        let provider: OpenAIProvider
        do {
            provider = try Self.createOpenAIProviderOrSkip()
        } catch E2ETestError.testSkipped(let message) {
            print("⚠️ \(message)")
            return
        }
        
        let client = AIClient()
        let model = provider.languageModel("gpt-4.1-nano")
            .temperature(0.0)  // Zero temperature for consistent results
            .maxTokens(300)
        
        print("🧪 Testing @Field description validation with real OpenAI API...")
        
        // Debug: Print the schema to verify field descriptions are included
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let schemaData = try? encoder.encode(E2EFieldValidationTest.schema),
           let schemaString = String(data: schemaData, encoding: .utf8) {
            print("🔍 Schema with field descriptions:")
            print(schemaString)
        }
        
        let response = try await client.generateObject(
            model,
            prompt: """
            Generate an object that follows all the field descriptions exactly.
            Pay special attention to the specific requirements in each field's description.
            For the score field, choose a value like 75 or 85 (which are divisible by 5 and > 50).
            """,
            type: E2EFieldValidationTest.self
        )
        
        let result = response.object
        
        // Validate that the AI followed the field descriptions
        #expect(result.testCode.hasPrefix("TEST-"), "testCode should start with 'TEST-'")
        #expect(result.testCode.count == 9, "testCode should be 'TEST-' + 4 digits = 9 chars")
        let digits = result.testCode.dropFirst(5)
        #expect(digits.count == 4, "testCode should have exactly 4 digits after 'TEST-'")
        #expect(digits.allSatisfy { $0.isNumber }, "testCode should end with 4 digits")
        
        #expect(result.specialNumber == 42, "specialNumber should be exactly 42 as per description")
        
        #expect(result.greeting.lowercased().contains("swift"), "greeting should contain 'Swift'")
        
        #expect(result.colorCode.hasPrefix("#"), "colorCode should start with #")
        #expect(result.colorCode.count == 7, "colorCode should be #RRGGBB format (7 chars)")
        let hexPart = result.colorCode.dropFirst()
        #expect(hexPart.allSatisfy { $0.isHexDigit }, "colorCode should contain only hex digits after #")
        
        #expect(result.score >= 0 && result.score <= 100, "score should be between 0 and 100")
        #expect(result.score % 5 == 0, "score should be divisible by 5")
        
        #expect(result.email.hasSuffix("@aikit.test"), "email should end with '@aikit.test'")
        
        // Validate the logical constraint
        if result.score > 50 {
            #expect(result.isPassing == true, "isPassing should be true when score > 50")
        } else {
            #expect(result.isPassing == false, "isPassing should be false when score <= 50")
        }
        
        print("✅ Field description validation successful")
        print("📋 Generated object:")
        print("   - testCode: \(result.testCode)")
        print("   - specialNumber: \(result.specialNumber)")
        print("   - greeting: \(result.greeting)")
        print("   - colorCode: \(result.colorCode)")
        print("   - score: \(result.score)")
        print("   - email: \(result.email)")
        print("   - isPassing: \(result.isPassing)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
}