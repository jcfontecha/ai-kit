# CLAUDE.md

Swift AI SDK - A type-safe, protocol-oriented Swift framework for AI model interactions, inspired by the Vercel AI SDK.

## 🎉 NEW: Automatic Tool Execution & Message Management

AIKit now provides Vercel AI SDK-style automatic tool execution and message management:

### Automatic Tool Execution in Streaming
```swift
// Just like Vercel - tools execute automatically during streaming!
let stream = await client.streamText(
    model,
    messages: messages,
    tools: tools,
    maxSteps: 3  // Multi-step execution
)

for try await chunk in stream {
    print(chunk.delta)  // Tool execution happens automatically
}
```

### Automatic Response Messages
```swift
// No more manual message formatting!
let response = try await client.generateText(model, messages: messages, tools: tools)

// Automatically formatted messages with tool calls
conversationHistory.append(contentsOf: response.responseMessages)
```

This eliminates common errors like forgetting to include tool calls in assistant messages.

## ⚠️ CRITICAL: Vercel AI SDK Reference Requirement

**IMPERATIVE**: Before implementing ANY feature, you MUST research how Vercel AI SDK implements it:

1. **Online Documentation**: Visit https://ai-sdk.dev/docs for public API patternsr
2. **Local Implementation**: Study `vercel-sdk/content/docs/` and `vercel-sdk/examples/` for technical details
3. **Plan Swift Translation**: Adapt TypeScript patterns to Swift idioms while maintaining API compatibility

Never implement features based on assumptions. Always consult Vercel AI SDK first.

The repo owner is jcfontech.

## Development Commands

### 🚨 Build Early and Often
Swift compiler errors cascade quickly. Build after every small change:

```bash
swift build              # Build constantly after code changes
swift test               # Run all tests
swift test --filter testName  # Run specific test
```

**Rule**: Never write more than 5-10 lines without building.

## Core Architecture

Three-layer design: `AIClient` (Framework) → `LanguageModel` (Configuration) → `AIProvider` (Translation)

- **AIClient**: Actor-based orchestration with async/await and streaming
- **LanguageModel**: Configuration container with builder pattern
- **AIProvider**: Protocol for provider-specific API translation

**Key Types** (`Sources/AIKit/Types/`):
- Messages, Streaming, Responses, Tools, Errors, Usage, ObjectSchema, SchemaProviding

## Development Patterns

### Provider Implementation
```swift
public struct YourProvider: AIProvider {
    public let name = "YourProvider"
    public func languageModel(_ modelId: String) -> LanguageModel
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
}
```

### Testing Strategy
- Use `MockProvider` for all test scenarios
- Tests organized by feature complexity
- Current: OpenAI provider implemented with comprehensive test coverage
- See `TEST-PLAN.md` for implementation roadmap

## Key Files
- `Sources/AIKit/AIKit.swift`: Main module interface
- `Sources/AIKit/Core/`: Core architecture components
- `Sources/AIKit/Types/SchemaProviding.swift`: Modern schema DSL and protocol
- `Tests/AIKitTests/`: Test suite with mock implementations

## Provider Implementation Workflow

1. **Research**: Study Vercel AI SDK provider patterns and official API docs
2. **Plan**: Create todo list, set up file structure in `Sources/AIKit/Providers/`
3. **Implement**: Build provider struct, API types, generateTextRaw, streamTextRaw, error handling
4. **Verify**: Build check, platform requirements, type safety, integration testing

## Test-Driven Development (TDD) Workflow

**5-Step TDD Methodology**:

1. **Study Architecture**: Read `SWIFT_AI_SDK_CORE_ARCHITECTURE.md` for Swift patterns
2. **Write Failing Tests (RED)**: Create tests based on Vercel AI SDK patterns
3. **Research Vercel Implementation**: Study `vercel-sdk/content/docs/` and examples
4. **Implement Swift Solution (GREEN)**: Write minimal code using Swift idioms
5. **Verify and Refactor**: Run all tests, clean up code, update documentation

**TDD Cycle Commands**:
```bash
swift test --filter testName  # Run single test (RED/GREEN)
swift test                    # Run all tests (verify)
swift build                   # Ensure compilation
```

## ⚠️ CRITICAL: E2E Test Model Requirements

**MANDATORY**: For E2E tests in `Tests/AIKitTests/E2EOpenAITests.swift`:

- **ALWAYS use `gpt-4.1-nano`** - This is the ONLY model allowed for E2E testing
- **NEVER change the model** - It's specifically chosen for cost-effectiveness and consistency
- **All E2E tests must use this exact model name**: `"gpt-4.1-nano"`

This ensures predictable costs and consistent test behavior across all E2E test scenarios.

## Schema Implementation Patterns

### 🎯 Modern Approach: SchemaProviding Protocol

**The recommended pattern for AIKit schema definition:**

1. **SchemaProviding Protocol**: Types define their own schemas via protocol conformance
2. **SwiftUI-like DSL**: Declarative schema definition with result builders
3. **Compile-time Safety**: No runtime reflection, all schemas verified at compile time
4. **Provider Agnostic**: Same schema works across OpenAI, Anthropic, Google
5. **Type Safety**: Leverage Swift's type system and compile-time checks

### 🏗️ Implementation Patterns

#### SchemaProviding Types (Recommended)
```swift
struct Person: SchemaProviding {
    let name: String
    let age: Int
    let email: String?
    
    static var schema: ObjectSchema<Person> {
        .define(description: "A person profile") {
            Schema.string("name", description: "Full legal name", minLength: 1)
            Schema.integer("age", description: "Age in years", minimum: 0, maximum: 150)
            Schema.email("email", description: "Optional contact email", required: false)
        }
    }
}

// Clean, type-safe API
let person = try await client.generateObject(model, prompt: "Create a person", type: Person.self)
```

#### Manual ObjectSchema (When needed)
```swift
// Manual only when you need full control
let manual = ObjectSchema<Person>.manual(
    jsonSchema: customSchema,
    name: "Person"
)
let response = try await client.generateObject(model, prompt: "Create a person", schema: manual)
```

#### Provider Integration Pattern
```swift
// Each provider handles schema transformation internally
protocol AIProvider {
    func formatSchemaForAPI<T>(_ schema: ObjectSchema<T>) -> ProviderAPIFormat
}

// OpenAI: response_format with strict mode
// Anthropic: tool input_schema format  
// Google: OpenAPI conversion
```

#### Field Constraint Patterns
```swift
// Numeric constraints
.describe(\.price, "Price in USD", minimum: 0.01, maximum: 99999.99)

// String constraints  
.describe(\.name, "Product name", minLength: 1, maxLength: 100)

// Enum constraints
.describe(\.category, "Category", enum: ["electronics", "books", "clothing"])

// Array constraints
.describe(\.tags, "Product tags", maxItems: 10)
```

### 🧪 Testing Patterns

#### Schema Generation Tests
```swift
struct TestType: SchemaProviding {
    let field: String
    
    static var schema: ObjectSchema<TestType> {
        .define {
            Schema.string("field", description: "Test field")
        }
    }
}

func testSchemaProvidingTypes() {
    let schema = TestType.schema
    XCTAssertNotNil(schema.jsonSchema)
    XCTAssertEqual(schema.name, "TestType")
    
    // Test clean API
    // let result = try await client.generateObject(model, prompt: "test", type: TestType.self)
}
```

#### E2E Object Generation Tests
```swift
struct TestPerson: SchemaProviding {
    let name: String
    let age: Int
    
    static var schema: ObjectSchema<TestPerson> {
        .define {
            Schema.string("name", description: "Full name")
            Schema.integer("age", description: "Age in years", minimum: 0, maximum: 150)
        }
    }
}

func testRealObjectGeneration() async throws {
    let person = try await client.generateObject(
        model, // Always use gpt-4.1-nano for E2E
        prompt: "Generate a test person",
        type: TestPerson.self  // Clean type-safe API
    )
    
    XCTAssertTrue(person.age >= 0)
    XCTAssertTrue(person.age <= 150)
}
```

### ✨ Schema Evolution: From Reflection to Protocol-Based Design

**Old Approach (Deprecated):**
```swift
// ❌ Unsafe runtime reflection, no compile-time guarantees
let schema = ObjectSchema<Person>()
    .describe(\.name, "Full name")  // KeyPath-based, brittle
    .describe(\.age, "Age", minimum: 0, maximum: 150)
```

**New Approach (Recommended):**
```swift
// ✅ Compile-time safety, explicit schema definition
struct Person: SchemaProviding {
    let name: String
    let age: Int
    
    static var schema: ObjectSchema<Person> {
        .define {
            Schema.string("name", description: "Full name")
            Schema.integer("age", minimum: 0, maximum: 150)
        }
    }
}

// Clean API that leverages the schema
let person = try await client.generateObject(model, prompt: "Create person", type: Person.self)
```

### 🏆 Benefits of SchemaProviding

1. **🏗️ SwiftUI-like DSL**: Familiar declarative syntax with result builders
2. **⚡ Compile-time Safety**: No runtime failures, all schemas verified upfront
3. **🔗 Automatic Nesting**: Reference other SchemaProviding types seamlessly
4. **📝 Self-Documenting**: Schema lives with the type, improving discoverability
5. **🎯 Type-safe API**: `generateObject(type: T.self)` vs manual schema passing
6. **🔄 Composable**: Easy to build complex nested structures
7. **🚀 Performance**: No reflection overhead, faster execution

This methodology ensures high-quality, maintainable code that mirrors Vercel AI SDK while being idiomatic to Swift.