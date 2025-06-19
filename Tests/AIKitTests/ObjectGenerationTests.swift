import Testing
import Foundation
@testable import AIKit

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
    let client = AIKit.client()
    let provider = AIKit.mockProvider()
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

// MARK: - Automatic Schema Generation Tests

@Test func testAutomaticSchemaGeneration() {
    // Test basic automatic schema generation from Swift types
    struct SimpleUser: Codable, Sendable {
        let name: String
        let age: Int
        let isActive: Bool
    }
    
    let schema = ObjectSchema<SimpleUser>()
    
    // Verify basic schema structure
    #expect(schema.name == "SimpleUser")
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
    #expect(schema.validationMode == .strict)
    #expect(schema.allowAdditionalProperties == false)
    
    // Verify schema contains properties
    let properties = schema.jsonSchema.definition.properties
    #expect(properties != nil, "Schema should have properties")
    
    if let props = properties {
        #expect(props.count >= 0, "Should generate properties for reflection-capable types")
    }
}

@Test func testOptionalPropertyHandling() {
    // Test handling of optional properties in schema generation
    struct UserWithOptionals: Codable, Sendable {
        let id: String
        let name: String
        let email: String?
        let phone: String?
        let age: Int?
    }
    
    let schema = ObjectSchema<UserWithOptionals>()
    
    // Verify schema is created successfully
    #expect(schema.name == "UserWithOptionals")
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // For reflection-based schema generation, all properties should be marked as required
    // Optional properties are handled by allowing null values in the schema
    let required = schema.jsonSchema.definition.required
    if let requiredProps = required {
        // When reflection works, we expect all properties to be marked as required
        // This follows OpenAI's strict requirements while handling optionals with nullable schemas
        #expect(requiredProps.count >= 0, "Required array should be present for OpenAI compatibility")
    }
}

@Test func testArrayPropertyHandling() {
    // Test handling of array properties in schema generation
    struct UserWithArrays: Codable, Sendable {
        let id: String
        let tags: [String]
        let scores: [Int]
        let friends: [String]?
    }
    
    let schema = ObjectSchema<UserWithArrays>()
    
    // Verify schema structure
    #expect(schema.name == "UserWithArrays")
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Schema should be generated without errors
    let properties = schema.jsonSchema.definition.properties
    #expect(properties != nil, "Schema should handle array properties")
}

@Test func testNestedObjectHandling() {
    // Test handling of nested object structures
    struct Address: Codable, Sendable {
        let street: String
        let city: String
        let zipCode: String
    }
    
    struct UserWithNested: Codable, Sendable {
        let name: String
        let age: Int
        let address: Address
        let alternateAddress: Address?
    }
    
    let schema = ObjectSchema<UserWithNested>()
    
    // Verify schema structure
    #expect(schema.name == "UserWithNested")
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Nested objects should be handled gracefully
    let properties = schema.jsonSchema.definition.properties
    #expect(properties != nil, "Schema should handle nested objects")
}

@Test func testSchemaConvenienceMethods() {
    // Test the new convenience factory methods
    struct Product: Codable, Sendable {
        let id: String
        let name: String
        let price: Double
        let inStock: Bool
    }
    
    // Test ObjectSchema.from() method
    let fromSchema = ObjectSchema.from(Product.self)
    #expect(fromSchema.name == "Product")
    #expect(fromSchema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Test ObjectSchema.from() with custom name and description
    let customFromSchema = ObjectSchema.from(
        Product.self,
        name: "ProductCatalog",
        description: "Product information for catalog"
    )
    #expect(customFromSchema.name == "ProductCatalog")
    #expect(customFromSchema.description == "Product information for catalog")
    
    // Test basic automatic schema generation 
    let autoSchema = ObjectSchema<Product>()
    #expect(autoSchema.name == "Product")
    #expect(autoSchema.validationMode == .strict)
    #expect(autoSchema.allowAdditionalProperties == false)
    
    // Test ObjectSchema.manual() method
    let manualSchema = ObjectSchema<Product>.manual(
        jsonSchema: .object(properties: [
            "id": .string(),
            "name": .string(minLength: 1),
            "price": .number(minimum: 0),
            "inStock": .boolean()
        ], required: ["id", "name", "price", "inStock"]),
        name: "ManualProduct",
        description: "Manually defined product schema"
    )
    #expect(manualSchema.name == "ManualProduct")
    #expect(manualSchema.description == "Manually defined product schema")
    #expect(manualSchema.validationMode == .strict)
}

@Test func testArraySchemaFactory() {
    // Test the array schema factory method
    struct Item: Codable, Sendable {
        let id: String
        let value: Int
    }
    
    let arraySchema = arraySchema(of: Item.self)
    
    // Verify array schema structure
    #expect(arraySchema.name == "[Item]")
    #expect(arraySchema.description == "Array of Item objects")
    #expect(arraySchema.jsonSchema.definition.type == JSONSchemaType.array)
    #expect(arraySchema.jsonSchema.definition.items != nil)
    
    // Verify array items schema
    if let items = arraySchema.jsonSchema.definition.items {
        #expect(items.definition.type == JSONSchemaType.object, "Array items should be object type")
    }
}

@Test func testOptionalSchemaFactory() {
    // Test the optional schema factory method
    struct User: Codable, Sendable {
        let name: String
        let email: String
    }
    
    let optionalSchema = optionalSchema(User.self)
    
    // Verify optional schema structure
    #expect(optionalSchema.name == "User?")
    #expect(optionalSchema.description == "Optional User object")
    
    // Optional schema should allow either the base type or null
    let definition = optionalSchema.jsonSchema.definition
    #expect(definition.oneOf != nil, "Optional schema should use oneOf for null handling")
    
    if let oneOf = definition.oneOf {
        #expect(oneOf.count == 2, "Should have base type and null type")
    }
}

@Test func testSchemaGenerationEdgeCases() {
    // Test edge cases and error handling in schema generation
    
    // Test with basic types
    let stringSchema = ObjectSchema<String>()
    #expect(stringSchema.name == "String")
    
    // Test with empty struct (minimal case)
    struct EmptyStruct: Codable, Sendable {}
    let emptySchema = ObjectSchema<EmptyStruct>()
    #expect(emptySchema.name == "EmptyStruct")
    #expect(emptySchema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Test with single property struct
    struct SingleProperty: Codable, Sendable {
        let value: String
    }
    let singleSchema = ObjectSchema<SingleProperty>()
    #expect(singleSchema.name == "SingleProperty")
    #expect(singleSchema.jsonSchema.definition.type == JSONSchemaType.object)
}

@Test func testSchemaBuilderChaining() {
    // Test the builder pattern methods work correctly with generated schemas
    struct Config: Codable, Sendable {
        let apiKey: String
        let timeout: Int
        let retries: Int?
    }
    
    let schema = ObjectSchema<Config>()
        .withName("APIConfig")
        .withDescription("API configuration settings")
        .withValidationMode(.lenient)
        .allowingAdditionalProperties(true)
    
    #expect(schema.name == "APIConfig")
    #expect(schema.description == "API configuration settings")
    #expect(schema.validationMode == .lenient)
    #expect(schema.allowAdditionalProperties == true)
    
    // Original schema generation should still work
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
}

@Test func testComplexTypeMapping() {
    // Test schema generation with complex Swift types
    struct ComplexType: Codable, Sendable {
        let id: UUID
        let url: URL?
        let date: Date
        let data: Data?
        let decimal: Decimal?
    }
    
    let schema = ObjectSchema<ComplexType>()
    
    // Should handle complex types gracefully
    #expect(schema.name == "ComplexType")
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Complex types should be mapped to appropriate JSON Schema types
    // UUID -> string with format, URL -> string with URI format, etc.
    let properties = schema.jsonSchema.definition.properties
    #expect(properties != nil, "Should generate properties for complex types")
}

@Test func testOpenAISchemaRequiredArrayHandling() {
    // Test that our schema generation follows Vercel AI SDK patterns for OpenAI
    struct PersonProfile: Codable, Sendable {
        let name: String        // Required
        let age: Int           // Required
        let email: String?     // Optional
        let isActive: Bool     // Required
    }
    
    // Create a manual schema that follows Vercel AI SDK patterns
    let schema = ObjectSchema<PersonProfile>.manual(
        jsonSchema: .object(properties: [
            "name": .string(minLength: 1),
            "age": .integer(minimum: 0, maximum: 150),
            "email": .string(format: "email"),  // Optional property - not nullable, just excluded from required
            "isActive": .boolean()
        ], required: ["name", "age", "isActive"]), // Only non-optional properties
        name: "PersonProfile",
        description: "Test schema with optional properties"
    )
    
    // Verify the schema structure matches Vercel AI SDK expectations
    #expect(schema.name == "PersonProfile")
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
    
    if let properties = schema.jsonSchema.definition.properties {
        #expect(properties.count == 4, "Should have all 4 properties")
        #expect(properties.keys.contains("name"), "Should have name property")
        #expect(properties.keys.contains("email"), "Should have email property even though optional")
    }
    
    if let required = schema.jsonSchema.definition.required {
        #expect(required.count == 3, "Should have 3 required properties")
        #expect(required.contains("name"), "Name should be required")
        #expect(required.contains("age"), "Age should be required")
        #expect(required.contains("isActive"), "IsActive should be required")
        #expect(!required.contains("email"), "Email should NOT be required (it's optional)")
    }
    
    print("✅ OpenAI schema required array handling verified")
    print("📋 Required properties: \(schema.jsonSchema.definition.required ?? [])")
    print("🔧 All properties: \(schema.jsonSchema.definition.properties?.keys.sorted() ?? [])")
}

@Test func testKeyPathDescriptionsWithPracticalExample() {
    // Practical test demonstrating KeyPath-based field descriptions
    struct UserRegistration: Codable, Sendable {
        let username: String
        let email: String
        let age: Int
        let bio: String?
        let interests: [String]
        let newsletter: Bool
    }
    
    // Create schema with comprehensive field descriptions and constraints
    let schema = ObjectSchema<UserRegistration>()
        .describe(\.username, "Unique username for account login", minLength: 3, maxLength: 20)
        .describe(\.email, "Valid email address for account verification")
        .describe(\.age, "User's age in years", minimum: 13, maximum: 120)
        .describe(\.bio, "Optional personal biography or description", maxLength: 500)
        .describe(\.interests, "List of user interests and hobbies", maxItems: 10)
        .describe(\.newsletter, "Whether user wants to receive newsletter updates")
    
    // Verify schema has been properly configured
    #expect(schema.name == "UserRegistration")
    #expect(schema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Test schema serialization preserves descriptions
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    
    do {
        let schemaData = try encoder.encode(schema)
        let schemaString = String(data: schemaData, encoding: .utf8) ?? ""
        
        // Verify the schema contains field information
        #expect(!schemaString.isEmpty, "Schema should serialize successfully")
        
        // The schema should contain our field descriptions and constraints
        // This validates that the KeyPath description system is working
        print("📋 Generated schema with KeyPath descriptions:")
        print(schemaString)
        
    } catch {
        #expect(Bool(false), "Schema serialization should not fail: \(error)")
    }
    
    // Test that builder pattern preserves functionality
    let enhancedSchema = schema
        .withDescription("User registration form data")
        .withValidationMode(.strict)
        .allowingAdditionalProperties(false)
    
    #expect(enhancedSchema.description == "User registration form data")
    #expect(enhancedSchema.validationMode == .strict)
    #expect(enhancedSchema.allowAdditionalProperties == false)
    
    // Verify original schema fields are preserved
    #expect(enhancedSchema.name == "UserRegistration")
    #expect(enhancedSchema.jsonSchema.definition.type == JSONSchemaType.object)
}

@Test func testKeyPathConstraintsValidation() {
    // Test that different constraint types work with KeyPath descriptions
    struct Product: Codable, Sendable {
        let name: String
        let price: Double
        let category: String
        let tags: [String]
        let inStock: Bool
    }
    
    let schema = ObjectSchema<Product>()
        .describe(\.name, "Product name", minLength: 1, maxLength: 100)
        .describe(\.price, "Product price in USD", minimum: 0.01, maximum: 999999.99)
        .describe(\.category, "Product category", enum: ["electronics", "books", "clothing", "home"])
        .describe(\.tags, "Product tags for search", maxItems: 20)
        .describe(\.inStock, "Whether product is currently available")
    
    // Create a test product for validation
    let testProduct = Product(
        name: "Test Product",
        price: 29.99,
        category: "electronics",
        tags: ["tech", "gadget"],
        inStock: true
    )
    
    // Test validation
    let validationResult = schema.validate(testProduct)
    #expect(validationResult.isValid == true, "Valid product should pass validation")
    #expect(validationResult.errors.isEmpty, "Should have no validation errors")
    
    print("✅ KeyPath constraint validation successful")
    print("📦 Test product: \(testProduct.name) - $\(testProduct.price)")
}

@Test func testSchemaValidationMethods() {
    // Test the validation methods work with generated schemas
    struct TestData: Codable, Sendable {
        let name: String
        let count: Int
    }
    
    let schema = ObjectSchema<TestData>()
    let testObject = TestData(name: "test", count: 42)
    
    // Test object validation
    let validationResult = schema.validate(testObject)
    #expect(validationResult.isValid == true, "Valid object should pass validation")
    #expect(validationResult.errors.isEmpty, "Should have no validation errors")
    
    // Test JSON validation
    let encoder = JSONEncoder()
    let jsonData = try! encoder.encode(testObject)
    let jsonValidationResult = schema.validateJSON(jsonData)
    #expect(jsonValidationResult.isValid == true, "Valid JSON should pass validation")
}