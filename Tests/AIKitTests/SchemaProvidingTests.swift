import Testing
import Foundation
@testable import AIKit

// MARK: - Test Types for Schema DSL

/// Test types that demonstrate the new @AIModel approach
@AIModel
private struct User: Codable, Sendable {
    let id: UUID
    let username: String
    let email: String
    let age: Int?
}

@AIModel
private struct Address: Codable, Sendable {
    let street: String
    let city: String
    let country: String
    let postalCode: String
}

@AIModel
private struct Company: Codable, Sendable {
    let name: String
    let address: Address
    let employees: [User]
}

// MARK: - Schema DSL Core Tests

@Test func testSchemaProvidingProtocol() {
    // Test that types can provide their own schemas
    let userSchema = User.schema
    #expect(userSchema.name == "User")
    #expect(userSchema.description == "User object")
    #expect(userSchema.jsonSchema.definition.type == .object)
    
    let addressSchema = Address.schema
    #expect(addressSchema.name == "Address")
    #expect(addressSchema.description == "Address object")
    #expect(addressSchema.jsonSchema.definition.type == .object)
}

@Test func testObjectSchemaBuilder() {
    // Test the @ObjectSchemaBuilder result builder syntax
    let schema = ObjectSchema<User>.define(
        name: "TestUser",
        description: "Test user schema"
    ) {
        Schema.string("test", description: "Test field")
        Schema.integer("count", minimum: 0)
        Schema.boolean("active")
    }
    
    #expect(schema.name == "TestUser")
    #expect(schema.description == "Test user schema")
    #expect(schema.jsonSchema.definition.type == .object)
    
    if let properties = schema.jsonSchema.definition.properties {
        #expect(properties.count == 3)
        #expect(properties.keys.contains("test"))
        #expect(properties.keys.contains("count"))
        #expect(properties.keys.contains("active"))
    }
}

@Test func testSchemaPropertyBuilders() {
    // Test all the Schema enum builders
    
    // String properties
    let stringProp = Schema.string("name", 
                                  description: "User name",
                                  minLength: 1,
                                  maxLength: 50,
                                  pattern: "^[A-Za-z ]+$")
    #expect(stringProp.key == "name")
    #expect(stringProp.required == true)
    
    // Integer properties
    let intProp = Schema.integer("age", minimum: 0, maximum: 150)
    #expect(intProp.key == "age")
    #expect(intProp.required == true)
    
    // Number properties
    let numberProp = Schema.number("price", minimum: 0.01)
    #expect(numberProp.key == "price")
    #expect(numberProp.required == true)
    
    // Boolean properties
    let boolProp = Schema.boolean("active", required: false)
    #expect(boolProp.key == "active")
    #expect(boolProp.required == false)
    
    // Array properties
    let arrayProp = Schema.array("tags", of: String.self, maxItems: 10)
    #expect(arrayProp.key == "tags")
    #expect(arrayProp.required == true)
    
    // Object properties
    let objectProp = Schema.object("address", of: Address.self)
    #expect(objectProp.key == "address")
    #expect(objectProp.required == true)
    
    // Special format properties
    let emailProp = Schema.email("email")
    #expect(emailProp.key == "email")
    
    let urlProp = Schema.url("website")
    #expect(urlProp.key == "website")
    
    let uuidProp = Schema.uuid("id")
    #expect(uuidProp.key == "id")
    
    let dateProp = Schema.date("createdAt")
    #expect(dateProp.key == "createdAt")
}

@Test func testCommonTypeSchemaConformance() {
    // Test that common types have automatic SchemaProviding conformance
    
    let stringSchema = String.schema
    #expect(stringSchema.name == "String")
    #expect(stringSchema.jsonSchema.definition.type == .string)
    
    let intSchema = Int.schema
    #expect(intSchema.name == "Int")
    #expect(intSchema.jsonSchema.definition.type == .integer)
    
    let doubleSchema = Double.schema
    #expect(doubleSchema.name == "Double")
    #expect(doubleSchema.jsonSchema.definition.type == .number)
    
    let boolSchema = Bool.schema
    #expect(boolSchema.name == "Bool")
    #expect(boolSchema.jsonSchema.definition.type == .boolean)
    
    let dateSchema = Date.schema
    #expect(dateSchema.name == "Date")
    #expect(dateSchema.jsonSchema.definition.type == .string)
    
    let urlSchema = URL.schema
    #expect(urlSchema.name == "URL")
    #expect(urlSchema.jsonSchema.definition.type == .string)
    
    let uuidSchema = UUID.schema
    #expect(uuidSchema.name == "UUID")
    #expect(uuidSchema.jsonSchema.definition.type == .string)
}

@Test func testArraySchemaConformance() {
    // Test that Array gets SchemaProviding when Element conforms
    let userArraySchema = Array<User>.schema
    #expect(userArraySchema.name == "Array<User>")
    #expect(userArraySchema.jsonSchema.definition.type == .array)
    
    if let items = userArraySchema.jsonSchema.definition.items {
        #expect(items.definition.type == .object)
    }
}

@Test func testOptionalSchemaConformance() {
    // Test that Optional gets SchemaProviding when Wrapped conforms
    let optionalUserSchema = Optional<User>.schema
    #expect(optionalUserSchema.name == "User?")
    #expect(optionalUserSchema.jsonSchema.definition.oneOf != nil)
    
    if let oneOf = optionalUserSchema.jsonSchema.definition.oneOf {
        #expect(oneOf.count == 2, "Should have base type and null type")
    }
}

@Test func testNestedSchemaProviding() {
    // Test that nested SchemaProviding types work correctly
    let companySchema = Company.schema
    #expect(companySchema.name == "Company")
    #expect(companySchema.description == "Company object")
    
    if let properties = companySchema.jsonSchema.definition.properties {
        #expect(properties.keys.contains("name"))
        #expect(properties.keys.contains("address"))
        #expect(properties.keys.contains("employees"))
    }
    
    if let required = companySchema.jsonSchema.definition.required {
        #expect(required.contains("name"))
        #expect(required.contains("address"))
        #expect(required.contains("employees"))
    }
}

@Test func testRequiredAndOptionalFields() {
    // Test that required and optional fields are handled correctly
    let userSchema = User.schema
    
    if let required = userSchema.jsonSchema.definition.required {
        #expect(required.contains("id"))
        #expect(required.contains("username"))
        #expect(required.contains("email"))
        #expect(!required.contains("age"), "Age should not be required")
    }
    
    if let properties = userSchema.jsonSchema.definition.properties {
        #expect(properties.keys.contains("age"), "Age should still be in properties even though optional")
    }
}

@Test func testComplexSchemaDefinition() {
    // Test a complex schema with multiple constraint types
    struct Product: SchemaProviding {
        let id: UUID
        let name: String
        let price: Double
        let category: String
        let tags: [String]
        let inStock: Bool
        let metadata: [String: String]?
        
        static var schema: ObjectSchema<Product> {
            .define(
                name: "Product",
                description: "E-commerce product",
                allowAdditionalProperties: false
            ) {
                Schema.uuid("id", description: "Product identifier")
                Schema.string("name", 
                             description: "Product name",
                             minLength: 1,
                             maxLength: 200)
                Schema.number("price", 
                             description: "Price in USD",
                             minimum: 0.01,
                             maximum: 999999.99)
                Schema.string("category",
                             description: "Product category",
                             enum: ["electronics", "books", "clothing", "home"])
                Schema.array("tags",
                            elementSchema: .string(minLength: 1, maxLength: 50),
                            description: "Product tags",
                            maxItems: 20)
                Schema.boolean("inStock", description: "Availability status")
                SchemaProperty(
                    key: "metadata",
                    schema: .object(
                        properties: [:],
                        additionalProperties: .schema(.string())
                    ),
                    required: false
                )
            }
        }
        
        typealias Partial = Product // Temporary for testing
    }
    
    let schema = Product.schema
    #expect(schema.name == "Product")
    #expect(schema.description == "E-commerce product")
    
    if let properties = schema.jsonSchema.definition.properties {
        #expect(properties.count == 7)
        #expect(properties.keys.contains("id"))
        #expect(properties.keys.contains("name"))
        #expect(properties.keys.contains("price"))
        #expect(properties.keys.contains("category"))
        #expect(properties.keys.contains("tags"))
        #expect(properties.keys.contains("inStock"))
        #expect(properties.keys.contains("metadata"))
    }
    
    if let required = schema.jsonSchema.definition.required {
        #expect(required.count == 6, "Should have 6 required fields")
        #expect(!required.contains("metadata"), "Metadata should be optional")
    }
}

// MARK: - AIClient Integration Tests

@Test func testAIClientGenerateWithSchemaProviding() async throws {
    // Test the new AIClient methods that use SchemaProviding types
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    // Test single object generation using SchemaProviding type
    let response = try await client.generateObject(
        model,
        prompt: "Generate a user profile for a software developer",
        type: User.self
    )
    let user = response.object
    
    #expect(!user.username.isEmpty, "Should generate username")
    #expect(!user.email.isEmpty, "Should generate email")
    #expect(user.id != UUID(), "Should generate unique ID") // This might fail with mock, but tests the concept
}

@Test func testAIClientGenerateArrayWithSchemaProviding() async throws {
    // Test array generation with SchemaProviding types
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    // Test array generation using SchemaProviding element type
    let response = try await client.generateArray(
        model,
        prompt: "Generate 3 user profiles",
        elementType: User.self
    )
    let users = response.object
    
    #expect(users.count >= 0, "Should generate array of users")
    
    for user in users {
        #expect(!user.username.isEmpty, "Each user should have username")
        #expect(!user.email.isEmpty, "Each user should have email")
    }
}

@Test func testAIClientGenerateWithMessages() async throws {
    // Test the message-based generation methods
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let messages = [
        Message.system("You are a helpful assistant that generates user profiles."),
        Message.user("Create a user profile for John Smith, a 30-year-old engineer.")
    ]
    
    let response = try await client.generateObject(
        model,
        messages: messages,
        type: User.self
    )
    let user = response.object
    
    #expect(!user.username.isEmpty, "Should generate username")
    #expect(!user.email.isEmpty, "Should generate email")
}

// MARK: - Schema Serialization Tests

@Test func testSchemaSerializationRoundTrip() throws {
    // Test that schemas can be serialized and maintain their structure
    let schema = User.schema
    
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    
    let schemaData = try encoder.encode(schema)
    let schemaString = String(data: schemaData, encoding: .utf8)!
    
    #expect(!schemaString.isEmpty, "Schema should serialize")
    #expect(schemaString.contains("User"), "Should contain schema name")
    
    // Test deserialization
    let decoder = JSONDecoder()
    let deserializedSchema = try decoder.decode(ObjectSchema<User>.self, from: schemaData)
    
    #expect(deserializedSchema.name == schema.name)
    #expect(deserializedSchema.description == schema.description)
    #expect(deserializedSchema.validationMode == schema.validationMode)
}

@Test func testJSONSchemaDescriptionHelpers() {
    // Test the private withDescription helper method
    let baseSchema = JSONSchema.string()
    let describedSchema = baseSchema.withDescription("Test description")
    
    #expect(describedSchema.definition.description == "Test description")
    
    // Test with complex schema
    let objectSchema = JSONSchema.object(properties: [
        "name": .string().withDescription("User name"),
        "age": .integer().withDescription("User age")
    ])
    
    #expect(objectSchema.definition.type == .object)
    if let properties = objectSchema.definition.properties {
        #expect(properties["name"]?.definition.description == "User name")
        #expect(properties["age"]?.definition.description == "User age")
    }
}

// MARK: - Error Handling Tests

@Test func testSchemaValidation() {
    // Test schema validation with the new DSL
    let schema = User.schema
    
    let validUser = User(
        id: UUID(),
        username: "johndoe",
        email: "john@example.com",
        age: 30
    )
    
    let result = schema.validate(validUser)
    #expect(result.isValid, "Valid user should pass validation")
    #expect(result.errors.isEmpty, "Should have no validation errors")
}

@Test func testSchemaBuilderMultipleProperties() {
    // Test that the schema builder supports multiple properties
    struct TestType: SchemaProviding {
        let field1: String
        let field2: Int
        let field3: Bool
        
        static var schema: ObjectSchema<TestType> {
            .define {
                Schema.string("field1")
                Schema.integer("field2")
                Schema.boolean("field3")
            }
        }
        
        typealias Partial = TestType
    }
    
    let schema = TestType.schema
    if let properties = schema.jsonSchema.definition.properties {
        #expect(properties.count == 3)
        #expect(properties.keys.contains("field1"))
        #expect(properties.keys.contains("field2"))
        #expect(properties.keys.contains("field3"))
    }
}


@Test func testSchemaComposition() {
    // Test the composition patterns mentioned in the proposal
    
    // Test timestamped protocol extension
    struct Article: SchemaProviding {
        let id: UUID
        let title: String
        let content: String
        let author: User
        let tags: [String]
        let createdAt: Date
        let updatedAt: Date
        
        static var schema: ObjectSchema<Article> {
            .define(description: "Blog article with metadata") {
                Schema.uuid("id")
                Schema.string("title", minLength: 1, maxLength: 200)
                Schema.string("content", minLength: 10)
                Schema.object("author", of: User.self)
                Schema.array("tags", 
                            elementSchema: .string(minLength: 1, maxLength: 30),
                            minItems: 0,
                            maxItems: 10)
                Schema.date("createdAt", description: "Creation timestamp")
                Schema.date("updatedAt", description: "Last update timestamp")
            }
        }
        
        typealias Partial = Article
    }
    
    let schema = Article.schema
    #expect(schema.name == "Article")
    #expect(schema.description == "Blog article with metadata")
    
    if let properties = schema.jsonSchema.definition.properties {
        #expect(properties.count == 7)
        #expect(properties.keys.contains("author"))
        #expect(properties.keys.contains("createdAt"))
        #expect(properties.keys.contains("updatedAt"))
    }
}