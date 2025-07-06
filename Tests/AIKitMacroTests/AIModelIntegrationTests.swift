import XCTest
@testable import AIKit
import AIKitMacro

// MARK: - Test Models using @AIModel

@AIModel
struct TestRecipe: Codable, Sendable {
    let title: String
    let ingredients: [String]
    let servings: Int
    let prepTime: Int?
}

@AIModel
struct TestProduct: Codable, Sendable {
    let name: String
    let price: Double
    let category: String
    let tags: [String]
    let inStock: Bool
}

@AIModel
struct TestUser: Codable, Sendable {
    let name: String
    let email: String
    let age: Int
    let profilePicture: URL?
    let createdAt: Date
}

@AIModel
struct TestUserProfile: Codable, Sendable {
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
struct TestProductWithConstraints: Codable, Sendable {
    @Field("Product name", minLength: 1, maxLength: 100)
    let name: String
    
    @Field("Price in USD", range: 0.01...99999.99)
    let price: Double
    
    @Field("Product category", enum: ["electronics", "books", "clothing"])
    let category: String
    
    @Field("Product tags", maxItems: 10)
    let tags: [String]
}

final class AIModelIntegrationTests: XCTestCase {
    
    // MARK: - Schema Generation Tests
    
    func testRecipeSchemaGeneration() {
        let schema = TestRecipe.schema
        
        XCTAssertEqual(schema.name, "TestRecipe")
        XCTAssertNotNil(schema.jsonSchema)
        
        // Validate schema has expected structure
        if case .definition(let def) = schema.jsonSchema,
           let properties = def.properties {
            XCTAssertEqual(properties.count, 4)
            XCTAssertNotNil(properties["title"])
            XCTAssertNotNil(properties["ingredients"])
            XCTAssertNotNil(properties["servings"])
            XCTAssertNotNil(properties["prepTime"])
        } else {
            XCTFail("Expected object schema definition")
        }
    }
    
    func testProductSchemaWithConstraints() {
        let schema = TestProductWithConstraints.schema
        
        XCTAssertEqual(schema.name, "TestProductWithConstraints")
        XCTAssertNotNil(schema.jsonSchema)
        
        if case .definition(let def) = schema.jsonSchema,
           let properties = def.properties {
            XCTAssertEqual(properties.count, 4)
            
            // Verify constraints are applied
            if case .definition(let nameDef) = properties["name"] {
                XCTAssertEqual(nameDef.minLength, 1)
                XCTAssertEqual(nameDef.maxLength, 100)
            }
            
            if case .definition(let priceDef) = properties["price"] {
                XCTAssertEqual(priceDef.minimum, 0.01)
                XCTAssertEqual(priceDef.maximum, 99999.99)
            }
            
            if case .definition(let categoryDef) = properties["category"] {
                let enumValues = categoryDef.enum?.compactMap { value in
                    if case .string(let str) = value {
                        return str
                    }
                    return nil
                }
                XCTAssertEqual(enumValues, ["electronics", "books", "clothing"])
            }
            
            if case .definition(let tagsDef) = properties["tags"] {
                XCTAssertEqual(tagsDef.maxItems, 10)
            }
        }
    }
    
    // MARK: - Partial Type Tests
    
    func testPartialTypeGeneration() {
        // Test that Partial type is generated
        let partial = TestRecipe.Partial(
            title: "Pasta",
            ingredients: nil,
            servings: nil,
            prepTime: nil,
            _fieldStatus: [
                "title": .completed,
                "ingredients": .notStarted,
                "servings": .notStarted,
                "prepTime": .notStarted
            ]
        )
        
        XCTAssertTrue(partial.isFieldComplete("title"))
        XCTAssertFalse(partial.isFieldComplete("ingredients"))
        
        // Test complete() throws when missing required fields
        XCTAssertThrowsError(try partial.complete()) { error in
            if let incompleteError = error as? IncompleteObjectError {
                XCTAssertTrue(incompleteError.missingFields.contains("ingredients"))
                XCTAssertTrue(incompleteError.missingFields.contains("servings"))
                XCTAssertEqual(incompleteError.presentFields, ["title"])
            } else {
                XCTFail("Expected IncompleteObjectError")
            }
        }
    }
    
    func testCompletePartialObject() throws {
        // Test successful completion
        let partial = TestRecipe.Partial(
            title: "Pasta Carbonara",
            ingredients: ["pasta", "eggs", "bacon", "parmesan"],
            servings: 4,
            prepTime: 30,
            _fieldStatus: [
                "title": .completed,
                "ingredients": .completed,
                "servings": .completed,
                "prepTime": .completed
            ]
        )
        
        let complete = try partial.complete()
        XCTAssertEqual(complete.title, "Pasta Carbonara")
        XCTAssertEqual(complete.ingredients.count, 4)
        XCTAssertEqual(complete.servings, 4)
        XCTAssertEqual(complete.prepTime, 30)
    }
    
    func testOptionalFieldHandling() throws {
        // Test partial with optional field missing
        let partial = TestRecipe.Partial(
            title: "Quick Salad",
            ingredients: ["lettuce", "tomatoes"],
            servings: 2,
            prepTime: nil, // Optional field
            _fieldStatus: [
                "title": .completed,
                "ingredients": .completed,
                "servings": .completed,
                "prepTime": .notStarted
            ]
        )
        
        // Should complete successfully even with nil optional
        let complete = try partial.complete()
        XCTAssertEqual(complete.title, "Quick Salad")
        XCTAssertNil(complete.prepTime)
    }
    
    // MARK: - Integration Tests with AIClient
    
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testObjectGenerationWithAIModel() async throws {
        let client = AIClient()
        let provider = MockProvider()
        let model = provider.languageModel("gpt-4")
        
        // Use the clean type-safe API
        let response = try await client.generateObject(
            model,
            prompt: "Create a cookie recipe",
            type: TestRecipe.self
        )
        
        XCTAssertFalse(response.object.title.isEmpty, "Recipe should have a title")
        XCTAssertTrue(response.object.ingredients.count >= 1, "Recipe should have ingredients")
        XCTAssertTrue(response.object.servings > 0, "Recipe should have servings")
        // prepTime is optional, may be nil
    }
    
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testArrayGenerationWithAIModel() async throws {
        let client = AIClient()
        let provider = MockProvider()
        let model = provider.languageModel("gpt-4")
        
        // Use the clean array generation API
        let response = try await client.generateArray(
            model,
            prompt: "Generate a list of products",
            elementType: TestProduct.self
        )
        
        XCTAssertTrue(response.object.count >= 1, "Should generate at least one product")
        XCTAssertFalse(response.object[0].name.isEmpty, "Product should have a name")
        XCTAssertTrue(response.object[0].price > 0, "Product should have a price")
    }
    
    // MARK: - SchemaProviding Conformance Tests
    
    func testAIModelConformsToSchemaProviding() {
        // Verify that @AIModel types conform to SchemaProviding
        XCTAssertTrue((TestRecipe.self as Any) is any SchemaProviding.Type)
        XCTAssertTrue((TestProduct.self as Any) is any SchemaProviding.Type)
        XCTAssertTrue((TestUser.self as Any) is any SchemaProviding.Type)
    }
    
    func testFieldAnnotations() {
        let schema = TestUserProfile.schema
        
        // Verify field descriptions are captured
        if case .definition(let def) = schema.jsonSchema,
           let properties = def.properties {
            
            if case .definition(let nameDef) = properties["name"] {
                XCTAssertEqual(nameDef.description, "Full name")
            }
            
            if case .definition(let ageDef) = properties["age"] {
                XCTAssertEqual(ageDef.description, "Age in years")
            }
        }
    }
}