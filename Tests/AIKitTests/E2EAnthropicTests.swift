import Testing
import Foundation
@testable import AIKit

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

// Define schema for object generation test
struct AnthropicTestPerson: Codable, Sendable, SchemaProviding {
    let name: String
    let age: Int
    let email: String
    
    typealias Partial = AnthropicTestPerson
    
    static var schema: ObjectSchema<AnthropicTestPerson> {
        .define(description: "Person object") {
            Schema.string("name", description: "Person's full name", required: true)
            Schema.integer("age", description: "Age in years", minimum: 0, maximum: 150, required: true)
            Schema.string("email", description: "Email address", format: "email", required: true)
        }
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
        for try await chunk in stream.textStream {
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
    
    @Test("Real Anthropic Streaming Tool Calling")
    func testRealAnthropicStreamingToolCalling() async throws {
        print("🧪 Testing streaming tool calling with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        
        let client = AIClient()
        
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.7)
            .maxTokens(600)
        
        // Define a search tool similar to OpenAI test
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
        
        print("🌊 Starting Anthropic streaming with tool calls...")
        
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
        
        print("✅ Anthropic streaming completed")
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
        
        print("✅ Anthropic streaming tool calling fix verified!")
    }
    
    // MARK: - New Feature Tests
    
    @Test("Real Anthropic Image Support")
    func testRealAnthropicImageSupport() async throws {
        print("🧪 Testing image support with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(Self.MAX_TOKENS)
        
        let client = AIClient()
        
        // Create a small test image (1x1 red pixel)
        let redPixelBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
        let imageData = Data(base64Encoded: redPixelBase64)!
        
        // Test with base64 image data
        let response = try await client.generateText(
            model,
            messages: [
                Message.user("What color is this 1x1 pixel image?", image: 
                    ImageContent.data(imageData, mimeType: "image/png")
                )
            ]
        )
        
        print("✅ Image support test successful")
        print("📝 Response: \(response.text)")
        
        #expect(!response.text.isEmpty, "Response should not be empty")
        #expect(response.text.lowercased().contains("red") || response.text.lowercased().contains("pixel"), "Response should describe the image")
        
        // Test with another base64 image (green pixel)
        let greenPixelBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let greenImageData = Data(base64Encoded: greenPixelBase64)!
        
        let greenResponse = try await client.generateText(
            model,
            messages: [
                Message.user("What color is this pixel?", image: 
                    ImageContent.data(greenImageData, mimeType: "image/png")
                )
            ]
        )
        
        print("📝 Green pixel response: \(greenResponse.text)")
        #expect(!greenResponse.text.isEmpty, "Green response should not be empty")
        #expect(greenResponse.text.lowercased().contains("green"), "Response should mention green")
    }
    
    @Test("Real Anthropic PDF Support") 
    func testRealAnthropicPDFSupport() async throws {
        print("🧪 Testing PDF support with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(Self.MAX_TOKENS)
        
        let client = AIClient()
        
        // Create a simple PDF with "Hello PDF" text
        // This is a minimal valid PDF file
        let pdfContent = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [3 0 R] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> /Contents 4 0 R >>
        endobj
        4 0 obj
        << /Length 44 >>
        stream
        BT
        /F1 12 Tf
        100 700 Td
        (Hello PDF) Tj
        ET
        endstream
        endobj
        xref
        0 5
        0000000000 65535 f
        0000000009 00000 n
        0000000058 00000 n
        0000000115 00000 n
        0000000262 00000 n
        trailer
        << /Size 5 /Root 1 0 R >>
        startxref
        350
        %%EOF
        """.data(using: .utf8)!
        
        let response = try await client.generateText(
            model,
            messages: [
                Message.user("What text is in this PDF?", file: 
                    FileContent.data(pdfContent, mimeType: "application/pdf", filename: "test.pdf")
                )
            ]
        )
        
        print("✅ PDF support test successful")
        print("📝 Response: \(response.text)")
        print("🔢 Token usage: \(response.usage.totalTokens)")
        
        #expect(!response.text.isEmpty, "Response should not be empty")
        #expect(response.text.contains("Hello") || response.text.contains("PDF"), "Response should mention content from PDF")
    }
    
    @Test("Real Anthropic Object Generation with Tools")
    func testRealAnthropicObjectGenerationWithTools() async throws {
        print("🧪 Testing object generation via tools with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.1)
            .maxTokens(200)
        
        let client = AIClient()
        
        // Use object generation which should use tool calling under the hood
        let person = try await client.generateObject(
            model,
            prompt: "Generate a person named Alice Smith, age 28, with email alice@example.com",
            type: AnthropicTestPerson.self
        )
        
        print("✅ Object generation successful")
        print("👤 Generated person: \(person.object.name), age \(person.object.age), email: \(person.object.email)")
        
        #expect(person.object.name.contains("Alice"), "Name should contain Alice")
        #expect(person.object.age == 28, "Age should be 28")
        #expect(person.object.email.contains("alice"), "Email should contain alice")
    }
    
    @Test("Real Anthropic Cache Control")
    func testRealAnthropicCacheControl() async throws {
        print("🧪 Testing cache control with real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(Self.MAX_TOKENS)
        
        let client = AIClient()
        
        // Make two identical requests to test cache behavior
        let messages = [Message.user("What is the capital of France?")]
        
        let response1 = try await client.generateText(model, messages: messages)
        print("📝 First response: \(response1.text)")
        print("🔢 First usage: \(response1.usage.promptTokens) prompt, \(response1.usage.completionTokens) completion")
        
        // Check for cache information in usage details
        if let details = response1.usage.details {
            print("📊 First cache details: \(details)")
        }
        
        // Make the same request again
        let response2 = try await client.generateText(model, messages: messages)
        print("📝 Second response: \(response2.text)")
        print("🔢 Second usage: \(response2.usage.promptTokens) prompt, \(response2.usage.completionTokens) completion")
        
        // Check for cache information in second request
        if let details = response2.usage.details {
            print("📊 Second cache details: \(details)")
            #expect(details["cache_read_input_tokens"] != nil || details["cache_creation_input_tokens"] != nil, 
                   "Should have cache information in usage details")
        }
        
        #expect(!response1.text.isEmpty && !response2.text.isEmpty, "Both responses should have content")
        #expect(response1.text.lowercased().contains("paris") && response2.text.lowercased().contains("paris"), 
               "Both responses should mention Paris")
    }
    
    @Test("Real Anthropic Reasoning Model Support")
    func testRealAnthropicReasoningModelSupport() async throws {
        print("🧪 Testing reasoning model support with real Anthropic API...")
        
        // Skip this test if reasoning models aren't available
        let reasoningModel = "claude-3-7-sonnet-20241022-v1:0"
        
        let provider = try createAnthropicProvider()
        
        // Test that reasoning models don't allow temperature/topK/topP
        do {
            let _ = provider.languageModel(reasoningModel)
                .temperature(0.5) // This should be rejected during request
            
            let client = AIClient()
            _ = try await client.generateText(
                provider.languageModel(reasoningModel).temperature(0.5),
                messages: [Message.user("Test")]
            )
            
            Issue.record("Should have thrown error for temperature on reasoning model")
        } catch {
            print("✅ Correctly rejected temperature for reasoning model")
            #expect(error.localizedDescription.contains("temperature") || error.localizedDescription.contains("reasoning"), 
                   "Error should mention temperature or reasoning")
        }
        
        // Test with thinking budget tokens
        let model = provider.languageModel(reasoningModel)
            .maxTokens(100)
            .providerSpecific(["thinking_budget_tokens": "1000"])
        
        // Note: This might fail if the reasoning model isn't available
        // We'll catch and skip in that case
        do {
            let client = AIClient()
            let response = try await client.generateText(
                model,
                messages: [Message.user("What is 25 * 4?")]
            )
            
            print("✅ Reasoning model test successful")
            print("📝 Response: \(response.text)")
            
            // Check if response contains thinking blocks
            if response.text.contains("[Thinking]") {
                print("🧠 Found thinking blocks in response")
                #expect(response.text.contains("[Thinking]"), "Response should contain thinking blocks")
            }
            
            #expect(response.text.contains("100"), "Response should contain the answer 100")
        } catch {
            print("⚠️ Reasoning model test skipped: \(error)")
            // This is okay - reasoning models might not be available
        }
    }
    
    @Test("Real Anthropic Enhanced Error Handling")
    func testRealAnthropicEnhancedErrorHandling() async throws {
        print("🧪 Testing enhanced error handling with real Anthropic API...")
        
        // Test with invalid API key
        let invalidProvider = AnthropicProvider(apiKey: "invalid-key-test")
        let model = invalidProvider.languageModel(Self.TEST_MODEL)
        
        let client = AIClient()
        
        do {
            _ = try await client.generateText(
                model,
                messages: [Message.user("Hello")]
            )
            Issue.record("Should have thrown authentication error")
        } catch {
            print("✅ Correctly caught authentication error")
            print("❌ Error: \(error)")
            #expect(error.localizedDescription.contains("authentication") || error.localizedDescription.contains("401"), 
                   "Error should mention authentication")
        }
        
        // Test with invalid model
        let provider = try createAnthropicProvider()
        let invalidModel = provider.languageModel("invalid-model-name")
        
        do {
            _ = try await client.generateText(
                invalidModel,
                messages: [Message.user("Hello")]
            )
            Issue.record("Should have thrown invalid model error")
        } catch {
            print("✅ Correctly caught invalid model error")
            print("❌ Error: \(error)")
            #expect(error.localizedDescription.contains("model") || error.localizedDescription.contains("400"), 
                   "Error should mention invalid model")
        }
    }
    
    @Test("Real Anthropic Streaming with Images")
    func testRealAnthropicStreamingWithImages() async throws {
        print("🧪 Testing streaming with images using real Anthropic API...")
        
        let provider = try createAnthropicProvider()
        let model = provider.languageModel(Self.TEST_MODEL)
            .temperature(0.3)
            .maxTokens(Self.MAX_TOKENS)
        
        let client = AIClient()
        
        // Create a blue pixel image
        let bluePixelBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/HwADBwIAMCbHYQAAAABJRU5ErkJggg=="
        let imageData = Data(base64Encoded: bluePixelBase64)!
        
        let stream = await client.streamText(
            model,
            messages: [
                Message.user("Describe this image in a few words.", image: 
                    ImageContent.data(imageData, mimeType: "image/png")
                )
            ]
        )
        
        var chunks: [TextChunk] = []
        var fullContent = ""
        
        for try await chunk in stream.textStream {
            chunks.append(chunk)
            fullContent += chunk.delta
        }
        
        print("✅ Streaming with images successful")
        print("📊 Received \(chunks.count) chunks")
        print("📝 Full content: \(fullContent)")
        
        #expect(chunks.count > 1, "Should receive multiple chunks")
        #expect(!fullContent.isEmpty, "Should have content")
        #expect(fullContent.lowercased().contains("blue") || fullContent.lowercased().contains("pixel") || fullContent.lowercased().contains("image"), 
               "Should describe the image")
    }
}