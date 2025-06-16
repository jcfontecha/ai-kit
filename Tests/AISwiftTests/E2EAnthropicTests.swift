import Testing
import Foundation
@testable import AISwift

// MARK: - Configuration Reader for Anthropic

/// Helper to read Anthropic configuration from Config.plist
private struct AnthropicConfigReader {
    static func loadAPIKey() throws -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") else {
            // Try to find Config.plist in the current working directory (project root)
            let currentWorkingDir = FileManager.default.currentDirectoryPath
            let configPath = "\(currentWorkingDir)/Config.plist"
            
            guard FileManager.default.fileExists(atPath: configPath) else {
                throw E2EAnthropicTestError.configNotFound("Config.plist not found at \(configPath)")
            }
            
            guard let plistData = FileManager.default.contents(atPath: configPath),
                  let plist = try PropertyListSerialization.propertyList(
                    from: plistData,
                    options: [],
                    format: nil
                  ) as? [String: Any] else {
                throw E2EAnthropicTestError.configInvalid("Failed to load Config.plist")
            }
            
            guard let apiKey = plist["ANTHROPIC_API_KEY"] as? String, !apiKey.isEmpty else {
                throw E2EAnthropicTestError.apiKeyMissing("ANTHROPIC_API_KEY not found or empty in Config.plist")
            }
            
            return apiKey
        }
        
        guard let plist = NSDictionary(contentsOfFile: path),
              let apiKey = plist["ANTHROPIC_API_KEY"] as? String, !apiKey.isEmpty else {
            throw E2EAnthropicTestError.apiKeyMissing("ANTHROPIC_API_KEY not found or empty in Config.plist")
        }
        
        return apiKey
    }
}

/// E2E test specific errors for Anthropic
private enum E2EAnthropicTestError: Error, LocalizedError {
    case configNotFound(String)
    case configInvalid(String)
    case apiKeyMissing(String)
    case testTimeout(String)
    case unexpectedResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .configNotFound(let message):
            return "Configuration not found: \(message)"
        case .configInvalid(let message):
            return "Invalid configuration: \(message)"
        case .apiKeyMissing(let message):
            return "API key missing: \(message)"
        case .testTimeout(let message):
            return "Test timeout: \(message)"
        case .unexpectedResponse(let message):
            return "Unexpected response: \(message)"
        }
    }
}

// MARK: - Test Data Structures

struct AnthropicUser: Codable {
    let name: String
    let age: Int
    let email: String
    let active: Bool
}

struct AnthropicRecipe: Codable {
    let name: String
    let description: String
    let prepTime: String
    let cookTime: String
    let difficulty: String
    let servings: Int
    let ingredients: [String]
    let steps: [String]
    
    enum CodingKeys: String, CodingKey {
        case name, description, servings, ingredients, steps, difficulty
        case prepTime = "prep_time"
        case cookTime = "cook_time"
    }
}

// MARK: - E2E Tests for Anthropic

@Suite("Real Anthropic API E2E Tests")
struct E2EAnthropicTests {
    
    // Test configuration - using Claude 3.5 Sonnet which is fast and cost-effective
    private static let TEST_MODEL = "claude-3-5-sonnet-20241022"
    private static let MAX_TOKENS = 150  // Keep low for cost efficiency
    private static let TIMEOUT_SECONDS: TimeInterval = 10.0
    
    private func createAnthropicProvider() throws -> AnthropicProvider {
        let apiKey = try AnthropicConfigReader.loadAPIKey()
        return AnthropicProvider(apiKey: apiKey)
    }
    
    @Test("Real Anthropic Basic Text Generation")
    func testRealAnthropicBasicTextGeneration() async throws {
        print("🧪 Testing basic text generation with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.7)
            .maxTokens(Self.MAX_TOKENS)
        
        let client = AIClient()
        let response = try await client.generateText(
            model,
            messages: [Message.user("Hello! Please introduce yourself in one sentence.")]
        )
        
        print("✅ Basic text generation successful")
        print("📝 Response: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens) total (\(response.usage.promptTokens) prompt + \(response.usage.completionTokens) completion)")
        
        #expect(!response.text.isEmpty, "Response should not be empty")
        #expect(response.text.count > 10, "Response should be substantial")
        #expect(response.usage.promptTokens > 0, "Should have prompt tokens")
        #expect(response.usage.completionTokens > 0, "Should have completion tokens")
        #expect(response.finishReason == .stop, "Should finish normally")
    }
    
    @Test("Real Anthropic Streaming")
    func testRealAnthropicStreaming() async throws {
        print("🧪 Testing streaming with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(Self.MAX_TOKENS)
        
        let client = AIClient()
        let stream = await client.streamText(
            model,
            messages: [Message.user("Count from 1 to 5, each number on a new line.")]
        )
        
        var chunks: [TextChunk] = []
        var fullContent = ""
        
        let startTime = Date()
        for try await chunk in stream {
            chunks.append(chunk)
            fullContent += chunk.delta
            
            // Prevent infinite loops
            if Date().timeIntervalSince(startTime) > Self.TIMEOUT_SECONDS {
                throw E2EAnthropicTestError.testTimeout("Streaming took longer than \(Self.TIMEOUT_SECONDS) seconds")
            }
        }
        
        print("✅ Streaming test successful")
        print("📊 Received \(chunks.count) chunks")
        print("📝 Full content: \(fullContent)")
        
        #expect(chunks.count > 1, "Should receive multiple chunks")
        #expect(!fullContent.isEmpty, "Should have content")
        #expect(fullContent.contains("1"), "Should contain count numbers")
        
        // Check that we have some chunks with usage info (usually at the end)
        let chunksWithUsage = chunks.filter { $0.usage != nil }
        #expect(chunksWithUsage.count > 0, "Should have chunks with usage information")
    }
    
    @Test("Real Anthropic Object Generation")
    func testRealAnthropicObjectGeneration() async throws {
        print("🧪 Testing object generation with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(200)
        
        let client = AIClient()
        
        // Note: Anthropic doesn't support structured outputs like OpenAI
        // We'll use tool calling to generate structured data
        let userTool = Tool(
            function: ToolFunction(
                name: "create_user",
                description: "Create a user profile",
                parameters: JSONSchema.object(properties: [
                    "name": JSONSchema.string(),
                    "age": JSONSchema.integer(),
                    "email": JSONSchema.string(),
                    "active": JSONSchema.boolean()
                ], required: ["name", "age", "email", "active"])
            )
        )
        
        let response = try await client.generateText(
            model,
            messages: [Message.user("Create a user profile for John Doe, age 30, email john@example.com, active status true. Use the create_user tool.")],
            tools: [userTool]
        )
        
        print("✅ Object generation successful")
        print("🔧 Tool calls: \(response.toolCalls.count)")
        
        #expect(response.toolCalls.count > 0, "Should have tool calls")
        
        if let toolCall = response.toolCalls.first {
            #expect(toolCall.function.name == "create_user", "Should call create_user function")
            
            // Parse the arguments to verify structure
            if let parsedArgs = toolCall.function.parsedArguments {
                print("👤 Generated user: \(parsedArgs["name"] ?? "unknown"), age \(parsedArgs["age"] ?? 0), email: \(parsedArgs["email"] ?? "unknown"), active: \(parsedArgs["active"] ?? false)")
                
                #expect(parsedArgs["name"] != nil, "Should have name")
                #expect(parsedArgs["age"] != nil, "Should have age")
                #expect(parsedArgs["email"] != nil, "Should have email")
                #expect(parsedArgs["active"] != nil, "Should have active status")
            }
        }
        
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @Test("Real Anthropic Tool Calling")
    func testRealAnthropicToolCalling() async throws {
        print("🧪 Testing tool calling with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(Self.MAX_TOKENS)
        
        let weatherTool = Tool(
            function: ToolFunction(
                name: "get_weather",
                description: "Get weather information for a location",
                parameters: JSONSchema.object(properties: [
                    "location": JSONSchema.string(),
                    "unit": JSONSchema.string()
                ], required: ["location"])
            )
        )
        
        // Note: This test demonstrates tool calling but doesn't include custom execution
        // The AIClient will make the tool call but won't execute the function
        
        let client = AIClient()
        let response = try await client.generateText(
            model,
            messages: [Message.user("What's the weather like in San Francisco?")],
            tools: [weatherTool]
        )
        
        print("✅ Tool calling successful")
        print("🔧 Tools called: \(response.toolCalls.count)")
        print("📝 Final response: \(response.text)")
        
        #expect(response.toolCalls.count > 0, "Should have tool calls")
        if let toolCall = response.toolCalls.first {
            #expect(toolCall.function.name == "get_weather", "Should call weather function")
        }
    }
    
    @Test("Real Anthropic Conversation")
    func testRealAnthropicConversation() async throws {
        print("🧪 Testing conversation with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.7)
            .maxTokens(Self.MAX_TOKENS)
        
        let client = AIClient()
        
        // First message
        let firstResponse = try await client.generateText(
            model,
            messages: [Message.user("Hello! What is 21 * 2?")]
        )
        
        print("🤖 Assistant: \(firstResponse.text)")
        
        // Second message with conversation history
        let secondResponse = try await client.generateText(
            model,
            messages: [
                Message.user("Hello! What is 21 * 2?"),
                Message.assistant(firstResponse.text),
                Message.user("Now multiply that result by 2.")
            ]
        )
        
        print("✅ Conversation test successful")
        print("📝 Response: \(secondResponse.text)")
        
        #expect(!firstResponse.text.isEmpty, "First response should not be empty")
        #expect(!secondResponse.text.isEmpty, "Second response should not be empty")
        #expect(firstResponse.text.contains("42"), "First response should contain 42")
        #expect(secondResponse.text.contains("84"), "Second response should contain 84")
    }
    
    @Test("Real Anthropic Complex Recipe Generation")
    func testRealAnthropicComplexRecipeGeneration() async throws {
        print("🧪 Testing complex recipe generation with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.5)
            .maxTokens(400)
        
        let recipeTool = Tool(
            function: ToolFunction(
                name: "create_recipe",
                description: "Create a detailed recipe",
                parameters: JSONSchema.object(properties: [
                    "name": JSONSchema.string(),
                    "description": JSONSchema.string(),
                    "prep_time": JSONSchema.string(),
                    "cook_time": JSONSchema.string(),
                    "difficulty": JSONSchema.string(),
                    "servings": JSONSchema.integer(),
                    "ingredients": JSONSchema.array(items: JSONSchema.string()),
                    "steps": JSONSchema.array(items: JSONSchema.string())
                ], required: ["name", "description", "prep_time", "cook_time", "difficulty", "servings", "ingredients", "steps"])
            )
        )
        
        let client = AIClient()
        let response = try await client.generateText(
            model,
            messages: [Message.user("I need you to create a recipe using the create_recipe tool. Please call the create_recipe function to generate a simple pasta recipe for 2 people. Do not provide the recipe in text form - only use the tool.")],
            tools: [recipeTool]
        )
        
        print("✅ Complex recipe generation successful")
        print("🔧 Tool calls: \(response.toolCalls.count)")
        print("📝 Response text: \(response.text)")
        
        // Claude might choose to use tools or respond directly, both are valid
        if response.toolCalls.count > 0 {
            print("🛠️ Claude used the tool to generate the recipe")
            if let toolCall = response.toolCalls.first,
               let parsedArgs = toolCall.function.parsedArguments {
                
                print("🍝 Generated recipe: \(parsedArgs["name"] ?? "Unknown")")
                print("⏱️  Prep: \(parsedArgs["prep_time"] ?? "Unknown"), Cook: \(parsedArgs["cook_time"] ?? "Unknown"), Difficulty: \(parsedArgs["difficulty"] ?? "Unknown")")
                
                if let ingredients = parsedArgs["ingredients"] as? [String],
                   let steps = parsedArgs["steps"] as? [String],
                   let servings = parsedArgs["servings"] as? Int {
                    print("🥘 Ingredients: \(ingredients.count), Steps: \(steps.count), Servings: \(servings)")
                    
                    #expect(ingredients.count > 0, "Should have ingredients")
                    #expect(steps.count > 0, "Should have cooking steps")
                    #expect(servings > 0, "Should have positive servings")
                }
            }
        } else {
            print("📝 Claude provided the recipe directly in text")
            #expect(response.text.lowercased().contains("pasta"), "Response should mention pasta")
            #expect(response.text.count > 50, "Response should be substantial")
        }
        
        print("🔢 Token usage: \(response.usage.totalTokens)")
    }
    
    @Test("Real Anthropic Error Handling")
    func testRealAnthropicErrorHandling() async throws {
        print("🧪 Testing error handling with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        
        // Test with very low max tokens to trigger length limit
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.7)
            .maxTokens(5)  // Very low to trigger max_tokens finish reason
        
        let client = AIClient()
        let response = try await client.generateText(
            model,
            messages: [Message.user("Please write a detailed explanation of artificial intelligence and machine learning.")]
        )
        
        print("✅ Error handling test successful")
        print("🚫 Finish reason: \(response.finishReason)")
        print("📝 Partial response: \(response.text)")
        
        #expect(response.finishReason == .length, "Should finish due to length limit")
        #expect(!response.text.isEmpty, "Should have partial response")
        #expect(response.text.count < 50, "Response should be truncated")
    }
    
    @Test("Real Anthropic Performance")
    func testRealAnthropicPerformance() async throws {
        print("🧪 Testing performance with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(50)  // Keep small for speed
        
        let client = AIClient()
        
        let startTime = Date()
        let response = try await client.generateText(
            model,
            messages: [Message.user("Hello from Swift AI SDK!")]
        )
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Performance test successful")
        print("⏱️  Duration: \(String(format: "%.2f", duration)) seconds")
        print("📝 Response: \(response.text)")
        
        #expect(duration < 15.0, "Response should be received within 15 seconds")
        #expect(!response.text.isEmpty, "Should have response")
        #expect(response.usage.totalTokens > 0, "Should have token usage")
    }
}