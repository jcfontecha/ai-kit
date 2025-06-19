# CLAUDE.md

Swift AI SDK - A type-safe, protocol-oriented Swift framework for AI model interactions, inspired by the Vercel AI SDK.

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

**Key Types** (`Sources/ai-swift/Types/`):
- Messages, Streaming, Responses, Tools, Errors, Usage, ObjectSchema

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
- `Sources/ai-swift/ai_swift.swift`: Main module interface
- `Sources/ai-swift/Core/`: Core architecture components
- `Tests/ai-swiftTests/`: Test suite with mock implementations

## Provider Implementation Workflow

1. **Research**: Study Vercel AI SDK provider patterns and official API docs
2. **Plan**: Create todo list, set up file structure in `Sources/ai-swift/Providers/`
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

**MANDATORY**: For E2E tests in `Tests/ai-swiftTests/E2EOpenAITests.swift`:

- **ALWAYS use `gpt-4.1-nano`** - This is the ONLY model allowed for E2E testing
- **NEVER change the model** - It's specifically chosen for cost-effectiveness and consistency
- **All E2E tests must use this exact model name**: `"gpt-4.1-nano"`

This ensures predictable costs and consistent test behavior across all E2E test scenarios.

## ObjectSchema Implementation Patterns

### 🎯 Core Design Principles

**Based on Vercel AI SDK patterns adapted for Swift:**

1. **Automatic Generation**: `ObjectSchema<T>()` should generate working schemas from Codable types
2. **Field Descriptions**: Use KeyPath-based `.describe()` for AI guidance
3. **Provider Agnostic**: Same schema works across OpenAI, Anthropic, Google
4. **Type Safety**: Leverage Swift's type system and compile-time checks

### 🏗️ Implementation Patterns

#### Schema Creation
```swift
// Always prefer automatic generation
let schema = ObjectSchema<Person>()
    .describe(\.name, "Full legal name")
    .describe(\.age, "Age in years", minimum: 0, maximum: 150)
    .describe(\.email, "Optional contact email")

// Manual only when automatic fails
let manual = ObjectSchema<Person>.manual(
    jsonSchema: customSchema,
    name: "Person"
)
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
func testObjectSchemaGeneration() {
    let schema = ObjectSchema<TestType>()
    XCTAssertNotNil(schema.jsonSchema)
    XCTAssertEqual(schema.name, "TestType")
}
```

#### E2E Object Generation Tests
```swift
func testRealObjectGeneration() async throws {
    let schema = ObjectSchema<Person>()
        .describe(\.name, "Full name")
        .describe(\.age, "Age in years", minimum: 0, maximum: 150)
    
    let response = try await client.generateObject(
        model, // Always use gpt-4.1-nano for E2E
        prompt: "Generate a test person",
        schema: schema
    )
    
    XCTAssertTrue(response.object.age >= 0)
    XCTAssertTrue(response.object.age <= 150)
}
```

This methodology ensures high-quality, maintainable code that mirrors Vercel AI SDK while being idiomatic to Swift.