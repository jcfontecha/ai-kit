import Testing
import Foundation
@testable import AIKit

// MARK: - Test Types

@AIModel
struct Person: Codable, Sendable {
    @Field("Full name", minLength: 1)
    let name: String
    
    @Field("Age in years", range: 0...150)
    let age: Int
    
    @Field("Email address")
    let email: String?
}

@AIModel
struct Recipe: Codable, Sendable {
    @Field("Recipe name")
    let name: String
    
    @Field("List of ingredients")
    let ingredients: [String]
    
    @Field("Cooking time in minutes")
    let cookingTime: Int
}

@AIModel
struct TodoItem: Codable, Sendable {
    @Field("Unique identifier", range: 1...999999)
    let id: Int
    
    @Field("Task description", minLength: 1)
    let task: String
    
    @Field("Completion status")
    let completed: Bool
}

enum Priority: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium" 
    case high = "high"
    case urgent = "urgent"
}

@AIModel
struct ProjectProjectTask: Codable, Sendable {
    @Field("Task title")
    let title: String
    
    @Field("Task priority level")
    let priority: Priority
    
    @Field("Estimated hours to complete")
    let estimatedHours: Int
}

// SchemaProviding test types
@AIModel
struct UserProfile: Codable, Sendable {
    @Field("Unique username", minLength: 3, maxLength: 20)
    let username: String
    
    @Field("User email address", format: "email")
    let email: String
    
    @Field("User age", range: 13...120)
    let age: Int
    
    @Field("Whether user account is active")
    let isActive: Bool
}

@AIModel
struct Product: Codable, Sendable {
    @Field("Product ID")
    let id: String
    
    @Field("Product name")
    let name: String
    
    @Field("Price in USD", range: 0.01...999999.99)
    let price: Double
    
    @Field("Stock availability")
    let inStock: Bool
}

// MARK: - Basic ObjectSchema Tests

@Test func testBasicObjectSchemaCreation() {
    // Test explicit schema creation with manual definition
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(minLength: 1),
            "age": .integer(minimum: 0, maximum: 150),
            "email": .string(format: "email")
        ], required: ["name", "age"]),
        name: "Person",
        description: "A person with basic information"
    )
    
    #expect(personSchema.name == "Person")
    #expect(personSchema.description == "A person with basic information")
    #expect(personSchema.validationMode == .strict)
    #expect(personSchema.allowAdditionalProperties == false)
}

@Test func testObjectSchemaBuilderMethods() {
    // Test builder pattern methods
    let recipeSchema = ObjectSchema<Recipe>.manual(
        jsonSchema: .object(properties: [
            "name": .string(),
            "ingredients": .array(items: .string()),
            "cookingTime": .integer(minimum: 1)
        ], required: ["name", "ingredients", "cookingTime"]),
        name: "Recipe"
    )
    .withDescription("Cooking recipe with ingredients")
    .withValidationMode(.lenient)
    .allowingAdditionalProperties(true)
    
    #expect(recipeSchema.name == "Recipe")
    #expect(recipeSchema.description == "Cooking recipe with ingredients")
    #expect(recipeSchema.validationMode == .lenient)
    #expect(recipeSchema.allowAdditionalProperties == true)
}

@Test func testObjectSchemaWithExamples() {
    // Test schema with examples
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(),
            "age": .integer(),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person"
    )
    
    let examplePerson = Person(name: "John Doe", age: 30, email: "john@example.com")
    let schemaWithExample = personSchema.withExample(examplePerson)
    
    #expect(schemaWithExample.examples?.count == 1)
    #expect(schemaWithExample.examples?.first?.name == "John Doe")
    #expect(schemaWithExample.examples?.first?.age == 30)
}

// MARK: - SchemaProviding Tests

@Test func testSchemaProvidingBasic() {
    // Test SchemaProviding protocol usage
    let userSchema = UserProfile.schema
    
    #expect(userSchema.name == "UserProfile")
    #expect(userSchema.description == "UserProfile object")
    #expect(userSchema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Verify properties exist
    if let properties = userSchema.jsonSchema.definition.properties {
        #expect(properties.keys.contains("username"))
        #expect(properties.keys.contains("email"))
        #expect(properties.keys.contains("age"))
        #expect(properties.keys.contains("isActive"))
    }
}

@Test func testSchemaProvidingFromFactory() {
    // Test ObjectSchema.from() factory method with SchemaProviding types
    let productSchema = ObjectSchema.from(Product.self)
    
    #expect(productSchema.name == "Product")
    #expect(productSchema.description == "Product object")
    
    // Test with custom name and description
    let customProductSchema = ObjectSchema.from(
        Product.self,
        name: "CustomProduct",
        description: "Custom product schema"
    )
    
    #expect(customProductSchema.name == "CustomProduct")
    #expect(customProductSchema.description == "Custom product schema")
}

// MARK: - Schema DSL Tests

@Test func testSchemaDSLDefinition() {
    // Test the result builder DSL for schema definition
    let testSchema = ObjectSchema<UserProfile>.define(
        name: "TestUser",
        description: "Test user schema"
    ) {
        Schema.string("username", description: "Username", minLength: 3, maxLength: 20)
        Schema.email("email", description: "Email address")
        Schema.integer("age", description: "Age", minimum: 13, maximum: 120)
        Schema.boolean("isActive", description: "Active status")
    }
    
    #expect(testSchema.name == "TestUser")
    #expect(testSchema.description == "Test user schema")
    
    // Verify all properties are defined
    if let properties = testSchema.jsonSchema.definition.properties {
        #expect(properties.count == 4)
        #expect(properties.keys.contains("username"))
        #expect(properties.keys.contains("email"))
        #expect(properties.keys.contains("age"))
        #expect(properties.keys.contains("isActive"))
    }
    
    // Verify required fields
    if let required = testSchema.jsonSchema.definition.required {
        #expect(required.count == 4) // All fields required by default
        #expect(required.contains("username"))
        #expect(required.contains("email"))
        #expect(required.contains("age"))
        #expect(required.contains("isActive"))
    }
}

@Test func testSchemaPropertyTypes() {
    // Test different schema property types
    struct ComplexType: Codable, Sendable {
        let text: String
        let count: Int
        let price: Double
        let active: Bool
        let createdAt: String
        let id: String
        let website: String
        let contact: String
    }
    
    let complexSchema = ObjectSchema<ComplexType>.define(
        name: "ComplexType"
    ) {
        Schema.string("text", description: "Text field", maxLength: 100)
        Schema.integer("count", description: "Count field", minimum: 0)
        Schema.number("price", description: "Price field", minimum: 0.01)
        Schema.boolean("active", description: "Active flag")
        Schema.date("createdAt", description: "Creation date")
        Schema.uuid("id", description: "Unique identifier")
        Schema.url("website", description: "Website URL")
        Schema.email("contact", description: "Contact email")
    }
    
    #expect(complexSchema.name == "ComplexType")
    
    if let properties = complexSchema.jsonSchema.definition.properties {
        #expect(properties.count == 8)
        
        // Verify specific property types and formats
        if case .definition(let textDef) = properties["text"] {
            #expect(textDef.type == JSONSchemaType.string)
            #expect(textDef.maxLength == 100)
        }
        
        if case .definition(let dateDef) = properties["createdAt"] {
            #expect(dateDef.type == JSONSchemaType.string)
            #expect(dateDef.format == "date-time")
        }
        
        if case .definition(let uuidDef) = properties["id"] {
            #expect(uuidDef.type == JSONSchemaType.string)
            #expect(uuidDef.format == "uuid")
        }
    }
}

// MARK: - Field Description Tests

@Test func testFieldDescriptions() {
    // Test KeyPath-based field descriptions
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(),
            "age": .integer(),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person"
    )
    .describe(\.name, "Full legal name", minLength: 1, maxLength: 100)
    .describe(\.age, "Age in years", minimum: 0, maximum: 150)
    .describe(\.email, "Contact email address")
    
    #expect(personSchema.name == "Person")
    #expect(personSchema.jsonSchema.definition.type == JSONSchemaType.object)
    
    // Verify that the field descriptions are preserved in the schema
    if let properties = personSchema.jsonSchema.definition.properties {
        #expect(properties.keys.contains("name"))
        #expect(properties.keys.contains("age"))
        #expect(properties.keys.contains("email"))
    }
}

// MARK: - Validation Tests

@Test func testObjectValidation() {
    // Test object validation against schema
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(minLength: 1),
            "age": .integer(minimum: 0, maximum: 150),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person"
    )
    
    let validPerson = Person(name: "John Doe", age: 30, email: "john@example.com")
    let validationResult = personSchema.validate(validPerson)
    
    #expect(validationResult.isValid == true)
    #expect(validationResult.errors.isEmpty == true)
}

@Test func testJSONValidation() {
    // Test JSON validation
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(),
            "age": .integer(),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person"
    )
    
    let validPerson = Person(name: "Jane Smith", age: 25, email: nil)
    let encoder = JSONEncoder()
    let jsonData = try! encoder.encode(validPerson)
    
    let jsonValidationResult = personSchema.validateJSON(jsonData)
    #expect(jsonValidationResult.isValid == true)
}

// MARK: - Array and Optional Schema Tests

@Test func testArraySchemaFactory() {
    // Test array schema creation
    let todoArraySchema = arraySchema(of: TodoItem.self)
    
    #expect(todoArraySchema.name == "[TodoItem]")
    #expect(todoArraySchema.description == "Array of TodoItem objects")
    #expect(todoArraySchema.jsonSchema.definition.type == JSONSchemaType.array)
    
    if let items = todoArraySchema.jsonSchema.definition.items {
        #expect(items.definition.type == JSONSchemaType.object)
    }
}

@Test func testOptionalSchemaFactory() {
    // Test optional schema creation  
    let optionalPersonSchema = optionalSchema(Person.self)
    
    #expect(optionalPersonSchema.name == "Person?")
    #expect(optionalPersonSchema.description == "Optional Person object")
    
    // Optional schema should handle null values
    if let oneOf = optionalPersonSchema.jsonSchema.definition.oneOf {
        #expect(oneOf.count == 2) // Should have base type and null type
    }
}

// MARK: - Basic Type Conformance Tests

@Test func testBasicTypeSchemaProviding() {
    // Test that basic types conform to SchemaProviding
    let stringSchema = String.schema
    #expect(stringSchema.name == "String")
    #expect(stringSchema.jsonSchema.definition.type == JSONSchemaType.string)
    
    let intSchema = Int.schema
    #expect(intSchema.name == "Int")
    #expect(intSchema.jsonSchema.definition.type == JSONSchemaType.integer)
    
    let doubleSchema = Double.schema
    #expect(doubleSchema.name == "Double")
    #expect(doubleSchema.jsonSchema.definition.type == JSONSchemaType.number)
    
    let boolSchema = Bool.schema
    #expect(boolSchema.name == "Bool")
    #expect(boolSchema.jsonSchema.definition.type == JSONSchemaType.boolean)
    
    let dateSchema = Date.schema
    #expect(dateSchema.name == "Date")
    #expect(dateSchema.jsonSchema.definition.type == JSONSchemaType.string)
    #expect(dateSchema.jsonSchema.definition.format == "date-time")
}

@Test func testArrayTypeSchemaProviding() {
    // Test Array conformance to SchemaProviding when Element conforms
    let stringArraySchema = Array<String>.schema
    #expect(stringArraySchema.name == "Array<String>")
    #expect(stringArraySchema.jsonSchema.definition.type == JSONSchemaType.array)
    
    if let items = stringArraySchema.jsonSchema.definition.items {
        #expect(items.definition.type == JSONSchemaType.string)
    }
}

@Test func testOptionalTypeSchemaProviding() {
    // Test Optional conformance to SchemaProviding when Wrapped conforms
    let optionalStringSchema = Optional<String>.schema
    #expect(optionalStringSchema.name == "String?")
    
    // Should use oneOf pattern for nullable values
    if let oneOf = optionalStringSchema.jsonSchema.definition.oneOf {
        #expect(oneOf.count == 2)
    }
}

// MARK: - Edge Cases and Error Handling Tests

@Test func testEmptyStructSchema() {
    // Test schema generation for empty struct
    struct EmptyStruct: Codable, Sendable {}
    
    let emptySchema = ObjectSchema<EmptyStruct>.manual(
        jsonSchema: .object(properties: [:]),
        name: "EmptyStruct"
    )
    
    #expect(emptySchema.name == "EmptyStruct")
    #expect(emptySchema.jsonSchema.definition.type == JSONSchemaType.object)
}

@Test func testSinglePropertySchema() {
    // Test schema for struct with single property
    struct SingleProperty: Codable, Sendable {
        let value: String
    }
    
    let singleSchema = ObjectSchema<SingleProperty>.manual(
        jsonSchema: .object(properties: [
            "value": .string()
        ], required: ["value"]),
        name: "SingleProperty"
    )
    
    #expect(singleSchema.name == "SingleProperty")
    #expect(singleSchema.jsonSchema.definition.type == JSONSchemaType.object)
    
    if let properties = singleSchema.jsonSchema.definition.properties {
        #expect(properties.count == 1)
        #expect(properties.keys.contains("value"))
    }
}

@Test func testNestedObjectSchema() {
    // Test nested object handling
    struct Address: Codable, Sendable {
        let street: String
        let city: String
        let zipCode: String
    }
    
    struct UserWithAddress: Codable, Sendable {
        let name: String
        let address: Address
    }
    
    let addressSchema = ObjectSchema<Address>.manual(
        jsonSchema: .object(properties: [
            "street": .string(),
            "city": .string(),
            "zipCode": .string()
        ], required: ["street", "city", "zipCode"]),
        name: "Address"
    )
    
    let userSchema = ObjectSchema<UserWithAddress>.manual(
        jsonSchema: .object(properties: [
            "name": .string(),
            "address": addressSchema.jsonSchema
        ], required: ["name", "address"]),
        name: "UserWithAddress"
    )
    
    #expect(userSchema.name == "UserWithAddress")
    #expect(userSchema.jsonSchema.definition.type == JSONSchemaType.object)
    
    if let properties = userSchema.jsonSchema.definition.properties {
        #expect(properties.count == 2)
        #expect(properties.keys.contains("name"))
        #expect(properties.keys.contains("address"))
    }
}

@Test func testValidationModes() {
    // Test different validation modes
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(),
            "age": .integer(),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person"
    )
    
    let strictSchema = personSchema.withValidationMode(.strict)
    #expect(strictSchema.validationMode == .strict)
    
    let lenientSchema = personSchema.withValidationMode(.lenient)
    #expect(lenientSchema.validationMode == .lenient)
    
    let noValidationSchema = personSchema.withValidationMode(.none)
    #expect(noValidationSchema.validationMode == .none)
}

// MARK: - AIClient Integration Tests

@Test func testAIClientGenerateObjectWithSchema() async throws {
    // Test AIClient.generateObject with explicit schema
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
        .temperature(0.0)
    
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(minLength: 1),
            "age": .integer(minimum: 0, maximum: 150),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person",
        description: "A person with name, age, and optional email"
    )
    
    let response = try await client.generateObject(
        model,
        prompt: "Generate a person profile for John Smith, age 30, software engineer",
        schema: personSchema
    )
    
    // Verify the generated object
    let person = response.object
    #expect(!person.name.isEmpty, "Should have valid name")
    #expect(person.age > 0, "Should have valid age")
    
    // Verify response metadata
    #expect(response.finishReason == FinishReason.stop, "Should finish with stop")
    #expect(response.usage.totalTokens > 0, "Should track token usage")
    #expect(!response.messages.isEmpty, "Should have message history")
    #expect(response.validationResult?.isValid == true, "Should pass validation")
}

@Test func testAIClientGenerateObjectWithSchemaProviding() async throws {
    // Test AIClient.generateObject with SchemaProviding type
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let response = try await client.generateObject(
        model,
        prompt: "Create a user profile",
        type: UserProfile.self
    )
    
    let userProfile = response.object
    #expect(!userProfile.username.isEmpty, "Should have username")
    #expect(!userProfile.email.isEmpty, "Should have email")
    #expect(userProfile.age > 0, "Should have valid age")
    
    #expect(response.finishReason == FinishReason.stop, "Should complete successfully")
    #expect(response.usage.totalTokens > 0, "Should track token usage")
}

@Test func testAIClientGenerateObjectWithMessages() async throws {
    // Test AIClient.generateObject with message array
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let messages = [
        Message.system("You are a helpful assistant that generates structured data."),
        Message.user("Create a product entry for a laptop")
    ]
    
    let response = try await client.generateObject(
        model,
        messages: messages,
        type: Product.self
    )
    
    let product = response.object
    #expect(!product.id.isEmpty, "Should have product ID")
    #expect(!product.name.isEmpty, "Should have product name")
    #expect(product.price > 0, "Should have valid price")
    
    #expect(response.messages.count == 3, "Should have all messages including response")
    #expect(response.messages.last?.role == .assistant, "Last message should be assistant response")
}

@Test func testAIClientGenerateArray() async throws {
    // Test AIClient.generateArray with explicit element schema
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let todoSchema = ObjectSchema<TodoItem>.manual(
        jsonSchema: .object(properties: [
            "id": .integer(minimum: 1),
            "task": .string(minLength: 1),
            "completed": .boolean()
        ], required: ["id", "task", "completed"]),
        name: "TodoItem",
        description: "A todo item with ID, task, and completion status"
    )
    
    let response = try await client.generateArray(
        model,
        prompt: "Generate 3 todo items for a daily routine",
        elementSchema: todoSchema
    )
    
    let todoList = response.object
    #expect(todoList.count >= 1, "Should generate at least 1 todo item")
    
    for (index, item) in todoList.enumerated() {
        #expect(item.id > 0, "Todo item \(index) should have valid ID")
        #expect(!item.task.isEmpty, "Todo item \(index) should have task")
    }
    
    #expect(response.finishReason == FinishReason.stop, "Should complete successfully")
    #expect(response.usage.totalTokens > 0, "Should track token usage")
}

@Test func testAIClientGenerateArrayWithSchemaProvidingType() async throws {
    // Test AIClient.generateArray with SchemaProviding element type
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let response = try await client.generateArray(
        model,
        prompt: "Generate a list of products",
        elementType: Product.self
    )
    
    let products = response.object
    #expect(products.count >= 1, "Should generate at least 1 product")
    
    for product in products {
        #expect(!product.id.isEmpty, "Product should have ID")
        #expect(!product.name.isEmpty, "Product should have name")
        #expect(product.price > 0, "Product should have valid price")
    }
    
    #expect(response.finishReason == FinishReason.stop, "Should complete successfully")
}

@Test func testAIClientGenerateEnum() async throws {
    // Test AIClient.generateEnum with predefined values
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let priorityValues = ["low", "medium", "high", "urgent"]
    
    let response = try await client.generateEnum(
        model,
        prompt: "What priority should we assign to fixing a critical security bug?",
        values: priorityValues
    )
    
    let selectedPriority = response.object
    #expect(priorityValues.contains(selectedPriority), "Should select valid priority value")
    
    #expect(response.finishReason == FinishReason.stop, "Should complete successfully")
    #expect(response.usage.totalTokens > 0, "Should track token usage")
    #expect(response.validationResult?.isValid == true, "Enum validation should pass")
}

@Test func testAIClientGenerateEnumWithMessages() async throws {
    // Test AIClient.generateEnum with message array
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let messages = [
        Message.system("You are a project manager assistant."),
        Message.user("We have a bug that prevents users from logging in. What priority should this have?")
    ]
    
    let priorityValues = Priority.allCases.map { $0.rawValue }
    
    let response = try await client.generateEnum(
        model,
        messages: messages,
        values: priorityValues
    )
    
    let selectedPriority = response.object
    #expect(priorityValues.contains(selectedPriority), "Should select valid priority")
    
    #expect(response.messages.count == 3, "Should have all messages including response")
}

// MARK: - Generation Mode Tests

@Test func testGenerationModes() async throws {
    // Test different generation modes
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let personSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(),
            "age": .integer(),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person"
    )
    
    // Test JSON mode
    let jsonResponse = try await client.generateObject(
        model,
        prompt: "Generate a person",
        schema: personSchema,
        mode: .json
    )
    #expect(!jsonResponse.object.name.isEmpty, "JSON mode should work")
    
    // Test tool mode
    let toolResponse = try await client.generateObject(
        model,
        prompt: "Generate a person",
        schema: personSchema,
        mode: .tool
    )
    #expect(!toolResponse.object.name.isEmpty, "Tool mode should work")
    
    // Test auto mode (default)
    let autoResponse = try await client.generateObject(
        model,
        prompt: "Generate a person", 
        schema: personSchema,
        mode: .auto
    )
    #expect(!autoResponse.object.name.isEmpty, "Auto mode should work")
}

// MARK: - Error Handling Tests

@Test func testInvalidEnumValue() async throws {
    // Test error handling when enum response is invalid
    let client = AIClient()
    let provider = MockProvider(configuration: MockConfiguration(errorRate: 0.0)) // No random errors
    let model = provider.languageModel("gpt-4.1-nano")
    
    let values = ["red", "green", "blue"]
    
    // This should succeed with MockProvider as it generates valid responses
    let response = try await client.generateEnum(
        model,
        prompt: "Pick a color",
        values: values
    )
    
    #expect(values.contains(response.object), "Should generate valid enum value")
}

@Test func testSchemaValidation() async throws {
    // Test schema validation during object generation
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let strictPersonSchema = ObjectSchema<Person>.manual(
        jsonSchema: .object(properties: [
            "name": .string(minLength: 1, maxLength: 50),
            "age": .integer(minimum: 0, maximum: 150),
            "email": .string()
        ], required: ["name", "age"]),
        name: "Person"
    )
    .withValidationMode(.strict)
    
    let response = try await client.generateObject(
        model,
        prompt: "Generate a person",
        schema: strictPersonSchema
    )
    
    // MockProvider should generate valid data that passes validation
    #expect(response.validationResult?.isValid == true, "Validation should pass")
    #expect(response.validationResult?.errors.isEmpty == true, "Should have no validation errors")
}

// MARK: - Complex Object Tests

@Test func testComplexObjectGeneration() async throws {
    // Test generation of more complex objects with nested structures
    let userProfileSchema = ObjectSchema<UserProfile>.manual(
        jsonSchema: JSONSchema.object(properties: [
            "username": JSONSchema.string(minLength: 3, maxLength: 20),
            "email": JSONSchema.string(format: "email"),
            "age": JSONSchema.integer(minimum: 13, maximum: 120),
            "isActive": JSONSchema.boolean()
        ], required: ["username", "email", "age", "isActive"]),
        name: "UserProfile",
        description: "User profile with validation"
    )
    
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let response = try await client.generateObject(
        model,
        prompt: "Create a user profile for a software developer",
        schema: userProfileSchema
    )
    
    let userProfile = response.object
    #expect(!userProfile.username.isEmpty, "Should have username")
    #expect(!userProfile.email.isEmpty, "Should have email")
    #expect(userProfile.age > 0, "Should have valid age")
    
    #expect(response.finishReason == FinishReason.stop, "Should complete successfully")
}

// MARK: - Performance and Edge Case Tests

@Test func testLargeArrayGeneration() async throws {
    // Test generating larger arrays to verify performance
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let response = try await client.generateArray(
        model,
        prompt: "Generate a list of user profiles",
        elementType: UserProfile.self
    )
    
    let profiles = response.object
    #expect(profiles.count >= 1, "Should generate at least 1 profile")
    
    // Verify all profiles are valid
    for profile in profiles {
        #expect(!profile.username.isEmpty, "Profile should have username")
        #expect(!profile.email.isEmpty, "Profile should have email")
    }
}

@Test func testEmptyMessageHandling() async throws {
    // Test handling of edge case inputs
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    // Test with minimal prompt
    let response = try await client.generateObject(
        model,
        prompt: "person",
        type: UserProfile.self
    )
    
    #expect(!response.object.username.isEmpty, "Should handle minimal prompt")
    #expect(response.finishReason == FinishReason.stop, "Should complete successfully")
}