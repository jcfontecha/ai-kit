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

## 🎵 NEW: Audio File Support

AIKit now supports sending audio files to AI models, following Vercel AI SDK patterns:

### Supported Models
- ✅ **`gpt-4o-audio-preview`** - Full audio transcription and analysis support
- ❌ **`gpt-4o-mini-audio-preview`** - Model exists but doesn't process audio content

### Sending Audio Files
```swift
// Load audio data
let audioData = try Data(contentsOf: audioURL)

// Create audio content using convenience methods
let mp3Audio = FileContent.mp3(audioData, filename: "audio.mp3")
let wavAudio = FileContent.wav(audioData, filename: "audio.wav")

// Send audio in messages - use gpt-4o-audio-preview!
let message = CoreMessage.user("What's in this audio?", audio: mp3Audio)

// Or combine with text
let message = CoreMessage(
    role: .user,
    content: [
        .text("Please transcribe this audio:"),
        .file(wavAudio)
    ]
)

let response = try await client.generateText(model, messages: [message])
```

### Provider Support
- **OpenAI**: Converts audio to `input_audio` format
  - **Supported formats**: MP3 (`audio/mpeg`, `audio/mp3`) and WAV (`audio/wav`) only
  - **Unsupported formats**: M4A, AAC, OGG, FLAC will throw an error
  - Only `gpt-4o-audio-preview` actually processes audio
  - Other formats must be converted to MP3 or WAV before sending
- **Google**: Supports audio via `inlineData` 
  - Works with Gemini models
  - Supports various audio formats (MP3, WAV, M4A, etc.)
- **Anthropic**: Currently supports only PDF files, not audio

### Audio Convenience Methods
```swift
// From Data
FileContent.mp3(data)          // audio/mpeg
FileContent.wav(data)          // audio/wav

// From URLs
FileContent.mp3URL(url)        // audio/mpeg URL
FileContent.wavURL(url)        // audio/wav URL

// Generic file support
FileContent.data(data, mimeType: "audio/flac", filename: "audio.flac")
```

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

### 🎯 Primary Approach: @AIModel Macro

**The recommended pattern for AIKit schema definition:**

1. **@AIModel Macro**: Automatic schema generation with field annotations
2. **Type Safety**: Compile-time verification of schemas
3. **Provider Agnostic**: Same schema works across OpenAI, Anthropic, Google
4. **Clean API**: Simple, declarative syntax that's hard to misuse

### 🏗️ Implementation Patterns

#### @AIModel Types (Recommended - 90% of use cases)
```swift
@AIModel
struct Person {
    @Field("Full legal name", minLength: 1)
    let name: String
    
    @Field("Age in years", range: 0...150)
    let age: Int
    
    @Field("Optional contact email", format: "email")
    let email: String?
}

// Clean, type-safe API
let person = try await client.generateObject(model, prompt: "Create a person", type: Person.self)
```

#### Manual ObjectSchema (For external types only)
```swift
// Only use when you can't modify the type to add @AIModel
let schema = ObjectSchema<ExternalType>.manual(
    jsonSchema: .object(properties: [
        "name": .string(minLength: 1),
        "age": .integer(minimum: 0, maximum: 150)
    ], required: ["name", "age"]),
    name: "ExternalType"
)
let response = try await client.generateObject(model, prompt: "Create a person", schema: schema)
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

#### Field Constraint Patterns with @Field
```swift
@AIModel
struct Product {
    @Field("Price in USD", range: 0.01...99999.99)
    let price: Double
    
    @Field("Product name", minLength: 1, maxLength: 100)
    let name: String
    
    @Field("Category", enum: ["electronics", "books", "clothing"])
    let category: String
    
    @Field("Product tags", maxItems: 10)
    let tags: [String]
}
```

### 🧪 Testing Patterns

#### Schema Generation Tests
```swift
@AIModel
struct TestType {
    @Field("Test field")
    let field: String
}

func testAIModelTypes() {
    let schema = TestType.schema
    XCTAssertNotNil(schema.jsonSchema)
    XCTAssertEqual(schema.name, "TestType")
    
    // Test clean API
    let result = try await client.generateObject(model, prompt: "test", type: TestType.self)
}
```

#### E2E Object Generation Tests
```swift
@AIModel
struct TestPerson {
    @Field("Full name")
    let name: String
    
    @Field("Age in years", range: 0...150)
    let age: Int
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

### ✨ Schema Evolution: From Manual to Macro-Based

**Old Approach (Manual):**
```swift
// ❌ Verbose, error-prone manual implementation
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
```

**New Approach (Recommended):**
```swift
// ✅ Clean, declarative, automatic
@AIModel
struct Person {
    @Field("Full name")
    let name: String
    
    @Field("Age", range: 0...150)
    let age: Int
}

// Same clean API
let person = try await client.generateObject(model, prompt: "Create person", type: Person.self)
```

### 🏆 Benefits of @AIModel

1. **🏗️ Clean Syntax**: Simple, declarative field annotations
2. **⚡ Compile-time Safety**: All schemas verified at compile time
3. **🔗 Automatic Nesting**: Reference other @AIModel types seamlessly
4. **📝 Self-Documenting**: Field descriptions are part of the property declaration
5. **🎯 Type-safe API**: `generateObject(type: T.self)` just works
6. **🔄 Composable**: Easy to build complex nested structures
7. **🚀 Zero Boilerplate**: No manual schema definitions needed
8. **🛡️ Hard to Misuse**: One clear way to define schemas

This methodology ensures high-quality, maintainable code that mirrors Vercel AI SDK while being idiomatic to Swift.