# ObjectSchema API Guide

The ObjectSchema system provides automatic JSON schema generation from Swift Codable types with field-level descriptions and validation constraints. This enables high-quality structured output generation from AI models while maintaining type safety and Swift idioms.

## Quick Start

### Basic Usage

```swift
struct Person: Codable {
    let name: String
    let age: Int
    let email: String?
    let isActive: Bool
}

// Automatic schema generation
let schema = ObjectSchema<Person>()

// Use with any provider
let response = try await client.generateObject(
    model,
    prompt: "Create a sample user profile",
    schema: schema
)

let person: Person = response.object
```

### With Field Descriptions

Adding field descriptions significantly improves AI generation quality:

```swift
let schema = ObjectSchema<Person>()
    .describe(\.name, "Person's full legal name")
    .describe(\.age, "Age in years", minimum: 0, maximum: 150)
    .describe(\.email, "Optional contact email address")
    .describe(\.isActive, "Whether the account is currently active")
```

## API Reference

### ObjectSchema Initialization

```swift
// Automatic generation (recommended)
let schema = ObjectSchema<T>()

// Manual schema (when needed)
let schema = ObjectSchema<T>.manual(
    jsonSchema: .object(properties: [...]),
    name: "TypeName",
    description: "Type description"
)
```

### Field Descriptions

Use KeyPath-based field descriptions to guide AI generation:

```swift
func describe<Value>(
    _ keyPath: KeyPath<T, Value>,
    _ description: String,
    minimum: Double? = nil,
    maximum: Double? = nil,
    minLength: Int? = nil,
    maxLength: Int? = nil,
    enum: [String]? = nil,
    maxItems: Int? = nil
) -> ObjectSchema<T>
```

#### Constraint Parameters

- **minimum/maximum**: Numeric range constraints
- **minLength/maxLength**: String length constraints  
- **enum**: Allowed string values
- **maxItems**: Maximum array length

### Field Constraint Examples

```swift
let schema = ObjectSchema<Product>()
    .describe(\.price, "Product price in USD", minimum: 0.01, maximum: 10000.0)
    .describe(\.name, "Product name", minLength: 1, maxLength: 100)
    .describe(\.category, "Product category", enum: ["electronics", "books", "clothing"])
    .describe(\.tags, "Product tags", maxItems: 10)
```

## Advanced Usage

### Complex Types

ObjectSchema works with nested types, arrays, and optionals:

```swift
struct Order: Codable {
    let id: String
    let customer: Person
    let items: [OrderItem]
    let total: Double
    let notes: String?
}

struct OrderItem: Codable {
    let name: String
    let quantity: Int
    let price: Double
}

let schema = ObjectSchema<Order>()
    .describe(\.id, "Unique order identifier")
    .describe(\.customer, "Customer information")
    .describe(\.items, "Ordered items", maxItems: 50)
    .describe(\.total, "Order total in USD", minimum: 0)
    .describe(\.notes, "Optional order notes", maxLength: 500)
```

### Enums and Advanced Types

```swift
enum Priority: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"
}

struct Task: Codable {
    let title: String
    let priority: Priority
    let dueDate: Date?
    let completed: Bool
}

let schema = ObjectSchema<Task>()
    .describe(\.title, "Task title", minLength: 1, maxLength: 200)
    .describe(\.priority, "Task priority level", enum: Priority.allCases.map(\.rawValue))
    .describe(\.dueDate, "Optional due date in ISO format")
    .describe(\.completed, "Whether the task is completed")
```

## Provider Compatibility

ObjectSchema works seamlessly across all supported providers:

- **OpenAI**: Uses `response_format` with strict mode
- **Anthropic**: Implements tool-based object generation
- **Google**: Converts to OpenAPI format (when implemented)

The same schema works across all providers without modification.

## Error Handling

```swift
do {
    let response = try await client.generateObject(model, prompt: prompt, schema: schema)
    let object = response.object
} catch AIError.schemaValidationFailed(let details) {
    print("Schema validation failed: \(details)")
} catch AIError.invalidResponse(let message) {
    print("Invalid response: \(message)")
} catch {
    print("Generation error: \(error)")
}
```

## Best Practices

### 1. Provide Clear Field Descriptions

```swift
// Good: Specific and helpful
.describe(\.email, "Valid email address in standard format (user@domain.com)")

// Avoid: Vague descriptions
.describe(\.email, "Email")
```

### 2. Use Appropriate Constraints

```swift
// Good: Reasonable constraints
.describe(\.age, "Person's age in years", minimum: 0, maximum: 150)

// Avoid: Overly restrictive
.describe(\.age, "Age", minimum: 18, maximum: 65) // Excludes children and seniors
```

### 3. Leverage Enums for Categorical Data

```swift
// Good: Use enums for known categories
enum Status: String, Codable {
    case active, inactive, pending
}

.describe(\.status, "Account status", enum: Status.allCases.map(\.rawValue))

// Avoid: Free-form text for categories
.describe(\.status, "Status as text")
```

### 4. Handle Optional Fields Appropriately

```swift
// Good: Clear when fields are optional
struct User: Codable {
    let name: String        // Required
    let email: String?      // Optional
    let phone: String?      // Optional
}

.describe(\.email, "Optional contact email address")
.describe(\.phone, "Optional phone number in international format")
```

## Testing ObjectSchema

```swift
func testObjectSchemaGeneration() async throws {
    let schema = ObjectSchema<Person>()
        .describe(\.name, "Full name")
        .describe(\.age, "Age in years", minimum: 0, maximum: 150)
    
    // Test schema properties
    XCTAssertEqual(schema.name, "Person")
    XCTAssertNotNil(schema.jsonSchema)
    
    // Test with mock provider
    let mockProvider = MockProvider()
    let model = mockProvider.languageModel("test")
    let client = AIKit.client()
    
    let response = try await client.generateObject(
        model,
        prompt: "Generate a test person",
        schema: schema
    )
    
    XCTAssertNotNil(response.object)
    XCTAssertTrue(response.object.age >= 0)
}
```

## Migration Guide

### From Manual Schema Creation

```swift
// Old: Manual schema creation
let manualSchema = ObjectSchema<Person>.manual(
    jsonSchema: .object(properties: [
        "name": .string(description: "Person's name"),
        "age": .integer(description: "Person's age")
    ], required: ["name", "age"]),
    name: "Person"
)

// New: Automatic with descriptions
let autoSchema = ObjectSchema<Person>()
    .describe(\.name, "Person's name")
    .describe(\.age, "Person's age")
```

### From Provider-Specific Code

```swift
// Old: Provider-specific implementations
#if OPENAI
let openAISchema = OpenAIObjectSchema<Person>(...)
#elseif ANTHROPIC
let anthropicSchema = AnthropicToolSchema<Person>(...)
#endif

// New: Universal schema
let schema = ObjectSchema<Person>()
    .describe(\.name, "Person's name")
    .describe(\.age, "Person's age")
// Works with all providers automatically
```

## Performance Considerations

- Schema generation is performed once per type and cached
- Field descriptions are lightweight and don't impact runtime performance
- JSON schema validation occurs client-side for early error detection
- Provider-specific transformations happen internally without affecting the public API

## Future Enhancements

- [ ] Support for custom validation functions
- [ ] Conditional schema generation based on field values
- [ ] Schema inheritance and composition
- [ ] Integration with Swift macros for compile-time generation