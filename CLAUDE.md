# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Swift AI SDK - A comprehensive Swift framework for AI model interactions, inspired by the Vercel AI SDK. This is a type-safe, protocol-oriented library that provides text generation, object generation, and streaming operations with built-in middleware support.

## ⚠️ CRITICAL: Vercel AI SDK Reference Requirement

**IMPERATIVE**: When implementing ANY feature for this Swift AI SDK, you MUST **ALWAYS** consult how the Vercel AI SDK implements that feature BEFORE attempting to write any Swift code. This is a mandatory two-step consultation process:

### 📚 **Step 1: Public API Documentation (Online)**
For public APIs, user-facing features, and general understanding:
- **Browse online documentation**: Visit https://ai-sdk.dev/docs URLs directly
- **Study API patterns**: Understand the public interface and user experience
- **Review usage examples**: See how developers use the features
- **Check error handling**: Understand expected error scenarios and messages

### 🔍 **Step 2: Implementation Details (Local vercel-sdk/)**
For implementation specifics, internal architecture, and technical details:
- **Complete Documentation**: `vercel-sdk/content/docs/` - Comprehensive API documentation and patterns
- **Code Examples**: `vercel-sdk/examples/` - Real implementation examples across frameworks  
- **Reference Implementation**: `vercel-sdk/content/docs/07-reference/01-ai-sdk-core/` - Detailed API specifications
- **Provider Patterns**: `vercel-sdk/providers/` - How different AI providers are implemented
- **Advanced Features**: `vercel-sdk/content/docs/06-advanced/` - Middleware, streaming, tool calling patterns

### 🚨 **MANDATORY Consultation Workflow**
**Before implementing ANY feature, you MUST:**

1. **Research Online First**: Visit the relevant https://ai-sdk.dev/docs URL to understand the public API
2. **Deep Dive Local Implementation**: Read through `vercel-sdk/content/docs/` for detailed patterns
3. **Study Examples**: Examine relevant examples in `vercel-sdk/examples/`
4. **Check Provider Patterns**: Review `vercel-sdk/providers/` for provider-specific implementations
5. **Plan Swift Translation**: Determine how to adapt TypeScript patterns to Swift idioms
6. **Implement with Parity**: Ensure Swift implementation maintains API compatibility and design patterns

**This dual consultation is MANDATORY** - you must NEVER implement a feature without first understanding both how Vercel AI SDK exposes it publicly AND how they implement it internally. The Swift SDK must maintain conceptual and functional parity with the Vercel AI SDK while being idiomatic to Swift.

**CRITICAL**: Do not attempt to implement features based on assumptions or general knowledge. ALWAYS consult the Vercel AI SDK first using both online documentation and the local `vercel-sdk/` repository.

## Development Commands

### 🚨 **CRITICAL: Build Early and Often**
**MANDATORY**: Swift is prone to developing cascading error "snowballs" where small issues compound into complex tangles of compiler errors. To prevent this:

**Build after EVERY code change:**
- After adding a new function or property
- After modifying any type signatures
- After implementing any protocol conformance
- After adding imports or dependencies
- After ANY edit that could affect compilation

**The rule: If you write more than 5-10 lines without building, you're taking a risk.**

```bash
# ALWAYS run after making changes - build constantly!
swift build              # Build immediately after code changes

# If build fails, FIX IMMEDIATELY before continuing
# Don't write more code until build passes
```

### Building and Testing
```bash
swift build              # Build the package - RUN THIS CONSTANTLY
swift test               # Run all tests  
swift test --filter testBasicTextGeneration  # Run specific test
```

### Package Management
```bash
swift package clean      # Clean build artifacts
swift package reset     # Reset package dependencies  
swift package show-dependencies  # Show dependency tree
```

### 🔧 **Error Prevention Workflow**
1. **Make small change**
2. **Build immediately** (`swift build`)
3. **Fix any errors BEFORE adding more code**
4. **Repeat** - never let errors accumulate

This prevents the Swift compiler error avalanche that can make debugging extremely difficult.

## Core Architecture

### Three-Layer Design Pattern
The SDK follows a clean separation of concerns with three main layers:

```
AIClient (Framework) → LanguageModel (Configuration) → AIProvider (Translation)
```

**Key Components:**
- **AIClient** (`Sources/ai-swift/Core/AIClient.swift`): Actor-based framework implementation handling orchestration, middleware, streaming, and tool execution
- **LanguageModel** (`Sources/ai-swift/Core/LanguageModel.swift`): Configuration container with fluent builder pattern for model parameters  
- **AIProvider** (`Sources/ai-swift/Core/AIProvider.swift`): Protocol defining translation layer between SDK format and provider APIs

### Actor-Based Concurrency
- `AIClient` is implemented as an actor for thread-safe operations
- All async operations use Swift's modern concurrency with async/await
- Streaming uses AsyncThrowingStream for real-time data flow

### Type System Organization
Located in `Sources/ai-swift/Types/`:
- **Messages.swift**: Conversation and message handling
- **Streaming.swift**: TextChunk, ObjectChunk, and stream utilities
- **Responses.swift**: TextResponse, ObjectResponse with metadata
- **Tools.swift**: Tool calling system (future implementation)
- **Errors.swift**: Comprehensive error hierarchy
- **Usage.swift**: Token usage and billing information
- **ObjectSchema.swift**: JSON schema validation for structured outputs

## Development Patterns

### Provider Implementation
New providers must conform to `AIProvider` protocol:
```swift
public struct YourProvider: AIProvider {
    public let name = "YourProvider"
    public func languageModel(_ modelId: String) -> LanguageModel
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
}
```

### Testing Strategy
- **Mock Provider**: Use `MockProvider` for all testing scenarios
- **Test Structure**: Tests are organized in phases from basic functionality to advanced features
- **Current Status**: 12 passing tests covering foundation, provider management, text generation, and streaming
- **Test Plan**: Comprehensive roadmap in `TEST-PLAN.md` with 140+ planned test methods

## Key Files and Purposes

### Core Implementation
- `Sources/ai-swift/ai_swift.swift`: Main module interface and factory methods
- `Sources/ai-swift/Core/`: All core architecture components
- `Sources/ai-swift/Extensions/ConvenienceExtensions.swift`: Builder patterns and utilities

### Testing Infrastructure  
- `Tests/ai-swiftTests/ai_swiftTests.swift`: Complete test suite with mock implementations
- `TEST-PLAN.md`: Detailed implementation roadmap tracking test progress

### Documentation
- `README.md`: Comprehensive usage documentation with examples
- `SWIFT_AI_SDK_CORE_ARCHITECTURE.md`: Detailed architecture documentation
- `Examples.md`: Usage patterns and code examples

## Implementation Status

### ✅ Completed
- Core three-layer architecture with actor-based concurrency
- Basic text generation and streaming functionality  
- Object schema foundation and validation
- Mock provider implementation for testing
- Configuration builder pattern with fluent API
- Comprehensive test coverage (12 passing tests)
- Message handling and conversation management
- **OpenAI Provider implementation** - Full production-ready provider with streaming, tool calling, and error handling

### 🚧 In Progress  
- Additional provider implementations (Anthropic, Google, etc.)
- Tool calling system implementation
- Middleware system (logging, caching, retry, rate limiting)
- Advanced streaming features and error handling

## Development Notes

### Swift Version Requirements
- Minimum Swift 6.1 (uses modern concurrency features)
- Supports iOS, macOS, watchOS, tvOS
- No external dependencies - clean SPM implementation

### Code Style Conventions
- Protocol-oriented design throughout
- Comprehensive Sendable conformance for concurrency safety
- Builder pattern for configuration
- Extensive use of Swift generics for type safety
- AsyncThrowingStream for all streaming operations

### Error Handling
- Comprehensive error hierarchy in `Types/Errors.swift`
- Provider-specific error mapping
- Graceful error propagation through middleware chain
- Future: Retry logic and circuit breaker patterns

### Performance Considerations
- Actor isolation prevents data races
- Streaming minimizes memory usage for large responses
- Configurable buffer sizes and timeout intervals
- Future: Connection pooling and request batching

The codebase demonstrates excellent Swift architectural patterns with a clear roadmap for extending with real AI providers while maintaining type safety and modern concurrency features.

## Provider Implementation Workflow

When implementing new AI providers, follow this proven workflow based on the successful OpenAI provider implementation:

### 1. Research Phase
- **Study Vercel AI SDK**: Examine the corresponding provider in `vercel-sdk/packages/[provider-name]/`
- **API Documentation**: Review the provider's official API documentation
- **Request/Response Formats**: Understand the provider's specific JSON schemas and data structures
- **Authentication**: Note API key requirements, headers, and endpoint structure

### 2. Planning Phase
- **Create Todo List**: Break down implementation into discrete tasks:
  - Research and documentation review
  - Core provider struct creation
  - generateTextRaw method implementation
  - streamTextRaw method implementation  
  - Error handling and response mapping
  - Testing and validation
- **Set Up File Structure**: Create the provider file in `Sources/ai-swift/Providers/`

### 3. Implementation Phase
- **Provider Struct**: Create the basic provider conforming to `AIProvider` protocol
- **API Types**: Define private structs for request/response JSON mapping
- **generateTextRaw**: Implement non-streaming text generation with full API integration
- **streamTextRaw**: Implement Server-Sent Events streaming with proper chunk processing
- **Error Handling**: Map provider-specific errors to standard SDK errors
- **Validation**: Implement parameter validation for provider-specific constraints

### 4. Verification Phase
- **Build Check**: Ensure `swift build` passes without errors
- **Platform Requirements**: Update availability annotations if needed (e.g., macOS 12.0+ for URLSession.bytes)
- **Type Safety**: Verify all JSON conversions handle optional fields properly
- **Integration**: Test with existing MockProvider patterns to ensure compatibility

## Test-Driven Development (TDD) Workflow

The Swift AI SDK follows a **strict Test-Driven Development methodology** that ensures high-quality, Vercel AI SDK-compatible implementations. This proven workflow has been used successfully to implement all major features including schema validation, error handling, complex object generation, and tool calling.

### 🎯 **5-Step TDD Methodology**

#### **Step 1: Study Swift AI SDK Architecture**
- **Read Core Architecture**: Study `SWIFT_AI_SDK_CORE_ARCHITECTURE.md` for Swift-specific design patterns
- **Review Current Implementation**: Understand existing Swift patterns, actor-based concurrency, protocol design
- **Check Swift Idioms**: Identify how Swift patterns differ from TypeScript (actors, async/await, protocols)
- **Understand Type System**: Review how Swift's type safety integrates with AI operations

```bash
# Example: Before implementing generateObject error handling
# Read: SWIFT_AI_SDK_CORE_ARCHITECTURE.md (Swift patterns)
# Read: VERCEL_AI_SDK_ANALYSIS.md (comparative analysis)
# Understand: Swift actor patterns, async/await, protocol design
```

#### **Step 2: Write Failing Tests (RED Phase)**
- **Create Test Structure**: Define comprehensive test scenarios based on Vercel AI SDK patterns
- **Focus on API Compatibility**: Ensure Swift API mirrors TypeScript API where appropriate
- **Test Error Cases**: Include comprehensive error scenarios from Step 1 research
- **Verify Failure**: Run `swift test --filter testName` to confirm test fails

```swift
@Test func testObjectGenerationErrorHandling() async throws {
    // RED PHASE: This test should fail because we need comprehensive error handling
    
    // Test Case 1: Malformed JSON
    do {
        let response = try await client.generateObject(malformedModel, ...)
        #expect(Bool(false), "Should have thrown JSONParseError")
    } catch let error as AIGenerationError {
        switch error {
        case .jsonParseError(let text, let parseError):
            #expect(text.contains("{"), "Should contain partial JSON")
            #expect(parseError != nil, "Should have underlying parse error")
        default:
            #expect(Bool(false), "Should be specific JSON parse error")
        }
    }
}
```

#### **Step 3: Research Vercel AI SDK Implementation Details**
- **Deep Dive**: Use the Task tool to examine Vercel AI SDK source code and examples
- **Study Documentation**: Read `vercel-sdk/content/docs/07-reference/01-ai-sdk-core/` for API specifications
- **Review Error Handling**: Study `vercel-sdk/content/docs/07-reference/05-ai-sdk-errors/` for error patterns
- **Check Examples**: Look at `vercel-sdk/examples/` and `vercel-sdk/content/cookbook/` for real-world usage
- **Pattern Analysis**: Understand how Vercel handles specific scenarios (streaming, errors, object parsing)
- **TypeScript → Swift Translation**: Plan how to adapt TypeScript patterns to Swift idioms
- **Cross-Reference Analysis**: Use `VERCEL_AI_SDK_ANALYSIS.md` for comparative patterns

```bash
# Use Task tool for comprehensive research:
# "Research how Vercel AI SDK handles JSONParseError and SchemaValidationError 
#  in their examples and implementation. Focus on error recovery patterns."
# Read: vercel-sdk/content/docs/07-reference/05-ai-sdk-errors/ai-json-parse-error.mdx
# Read: vercel-sdk/content/docs/07-reference/05-ai-sdk-errors/ai-type-validation-error.mdx
```

#### **Step 4: Implement Swift Solution (GREEN Phase)**
- **Minimal Implementation**: Write just enough code to make the test pass
- **Swift Idioms**: Use Swift-native patterns (actors, async/await, protocols)
- **Error Mapping**: Implement Vercel-compatible error types and messages
- **Type Safety**: Leverage Swift's type system for compile-time safety

```swift
// Add new error cases to AIGenerationError
case jsonParseError(text: String, parseError: Error?)
case schemaValidationError(objectData: String?, validationErrors: [String])
case noObjectGenerated(text: String, finishReason: FinishReason?, usage: Usage)

// Implement proper JSON parsing in AIClient
private func parseJSONResponse<T: Codable>(_ content: String, as type: T.Type) throws -> T {
    let jsonString = extractJSONFromResponse(content)
    // ... proper parsing with error handling
}
```

#### **Step 5: Verify and Refactor**
- **Run All Tests**: Execute `swift test` to ensure no regressions
- **Refactor**: Clean up code, remove test artifacts from production code
- **Architecture Review**: Ensure clean separation (AIClient = production, MockProvider = testing)
- **Documentation**: Update test plan and implementation status

```bash
swift test                    # Verify all tests pass
swift build                   # Ensure clean compilation
# Update TEST-PLAN.md with ✅ completed items
```

### 🔄 **TDD Cycle Examples**

#### **Schema Validation Implementation**
1. **Study**: Read `SWIFT_AI_SDK_CORE_ARCHITECTURE.md` for Swift patterns and `VERCEL_AI_SDK_ANALYSIS.md`
2. **Test**: Write `testObjectGenerationWithSchemaValidation()` - FAILS
3. **Research**: Examine `vercel-sdk/content/docs/03-ai-sdk-core/10-generating-structured-data.mdx` and how Vercel validates Zod schemas vs Swift ObjectSchema
4. **Implement**: Add JSON parsing and schema validation to AIClient following Swift patterns
5. **Verify**: All tests pass, clean architecture maintained

#### **Error Handling Implementation**  
1. **Study**: Review Swift error handling patterns in `SWIFT_AI_SDK_CORE_ARCHITECTURE.md`
2. **Test**: Write `testObjectGenerationErrorHandling()` - FAILS
3. **Research**: Study `vercel-sdk/content/docs/07-reference/05-ai-sdk-errors/` and understand Vercel's error hierarchy vs Swift error enums
4. **Implement**: Add `AIGenerationError` cases following Swift conventions and MockProvider error scenarios
5. **Verify**: Comprehensive error handling with proper error context

#### **Complex Object Generation**
1. **Study**: Review Swift type system integration from `SWIFT_AI_SDK_CORE_ARCHITECTURE.md`
2. **Test**: Write `testComplexNestedObjectGeneration()` - FAILS  
3. **Research**: Examine Vercel's nested object examples in `vercel-sdk/examples/` and how Vercel handles arrays, nested objects, optional properties
4. **Implement**: Enhanced JSON generation following Swift Codable patterns, robust parsing in AIClient
5. **Verify**: Full nested object support with Swift type safety

### 🎯 **TDD Best Practices**

#### **RED Phase (Failing Test)**
- **Write comprehensive tests first** - never start with implementation
- **Test should fail for the right reason** - not compilation errors
- **Include edge cases** based on Vercel AI SDK documentation
- **Focus on the public API** that users will interact with

#### **GREEN Phase (Make It Pass)**
- **Write minimal code** to make test pass
- **Resist over-engineering** - implement only what the test requires
- **Maintain Swift idioms** while preserving Vercel AI SDK compatibility
- **Keep production code clean** - no test artifacts

#### **Refactor Phase**
- **Clean up code** without changing functionality
- **Separate concerns** - move mock code to MockProvider
- **Ensure architecture** follows the three-layer pattern
- **Verify all tests still pass** after refactoring

### 📊 **Success Metrics**

This TDD workflow has delivered:
- **23 passing tests** with 100% success rate
- **Production-ready architecture** with clean separation of concerns
- **Vercel AI SDK compatibility** in API design and error handling
- **Comprehensive error coverage** including all major error scenarios
- **Complex object support** with nested structures and arrays
- **Type-safe implementation** leveraging Swift's strengths

### 🔧 **Tools and Commands**

```bash
# TDD Test Cycle
swift test --filter testSpecificFeature  # Run single test (RED/GREEN)
swift test                               # Run all tests (verify)
swift build                              # Ensure compilation

# Research Tools
# Use Task tool for Vercel AI SDK research
# Read tool for examining specific files
# Grep tool for finding patterns

# Documentation Updates
# Update TEST-PLAN.md with ✅ completed features
# Update CLAUDE.md with new patterns
```

This TDD methodology ensures **high-quality, maintainable code** that closely mirrors the Vercel AI SDK while being idiomatic to Swift. Every feature is thoroughly tested before implementation, resulting in robust, production-ready code.