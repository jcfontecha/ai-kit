import Testing
import Foundation
@testable import AISwift

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

@Test func testGenerateArrayPattern() async throws {
    // Test array generation (Vercel pattern: generateObject({ model, schema }) with array schema)
    struct TodoItem: Codable, Sendable {
        let id: Int
        let task: String
        let completed: Bool
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let todoListSchema = ObjectSchema<[TodoItem]>(
        name: "TodoList",
        description: "A list of todo items"
    )
    
    let response = try await client.generateObject(
        model,
        prompt: "Generate 3 todo items for a daily routine",
        schema: todoListSchema
    )
    
    let todoList = response.object
    #expect(todoList.count == 3, "Should generate 3 todo items")
    
    for (index, item) in todoList.enumerated() {
        #expect(item.id > 0, "Todo item \(index) should have valid ID")
        #expect(!item.task.isEmpty, "Todo item \(index) should have task")
    }
    
    #expect(response.finishReason == .stop, "Should complete successfully")
    #expect(response.usage.totalTokens > 0, "Should track token usage")
}

@Test func testGenerateEnumPattern() async throws {
    // Test enum generation (Vercel pattern with enum schemas)
    enum Priority: String, Codable, CaseIterable, Sendable {
        case low = "low"
        case medium = "medium" 
        case high = "high"
        case urgent = "urgent"
    }
    
    struct Task: Codable, Sendable {
        let title: String
        let priority: Priority
        let estimatedHours: Int
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let taskSchema = ObjectSchema<Task>(
        name: "Task",
        description: "A task with priority level"
    )
    
    let response = try await client.generateObject(
        model,
        prompt: "Create a critical bug fix task",
        schema: taskSchema
    )
    
    let task = response.object
    #expect(!task.title.isEmpty, "Should have task title")
    #expect(task.estimatedHours > 0, "Should have estimated hours")
    #expect(Priority.allCases.contains(task.priority), "Should have valid priority")
    
    #expect(response.finishReason == .stop, "Should complete successfully")
}

@Test func testStreamObjectBasicPattern() async throws {
    // Test object streaming (Vercel pattern: streamObject({ model, schema, prompt }))
    struct WeatherReport: Codable, Sendable {
        let location: String
        let temperature: Int
        let condition: String
        let humidity: Int
    }
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let weatherSchema = ObjectSchema<WeatherReport>(
        name: "WeatherReport",
        description: "Current weather information"
    )
    
    let stream = await client.streamObject(
        model,
        messages: [Message.user("Generate weather report for San Francisco")],
        schema: weatherSchema
    )
    
    var partialObjects: [ObjectChunk<WeatherReport>] = []
    var finalObject: WeatherReport? = nil
    
    for try await chunk in stream {
        partialObjects.append(chunk)
        
        if let object = chunk.object {
            finalObject = object
        }
    }
    
    // Verify streaming behavior
    #expect(!partialObjects.isEmpty, "Should receive streaming chunks")
    #expect(finalObject != nil, "Should have final complete object")
    
    if let weather = finalObject {
        #expect(!weather.location.isEmpty, "Should have location")
        #expect(weather.temperature > -100 && weather.temperature < 200, "Should have reasonable temperature")
        #expect(!weather.condition.isEmpty, "Should have weather condition")
    }
    
    // Verify last chunk has completion metadata
    let lastChunk = try #require(partialObjects.last)
    #expect(lastChunk.finishReason == .stop, "Should finish with stop")
    #expect(lastChunk.usage != nil, "Should have usage information")
}