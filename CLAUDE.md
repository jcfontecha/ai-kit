# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Swift AI SDK - A comprehensive Swift framework for AI model interactions, inspired by the Vercel AI SDK. This is a type-safe, protocol-oriented library that provides text generation, object generation, and streaming operations with built-in middleware support.

## ⚠️ CRITICAL: Vercel AI SDK Reference Requirement

**IMPERATIVE**: When implementing ANY feature for this Swift AI SDK, you MUST consistently reference the original Vercel AI SDK located at `vercel-sdk/` in this repository. This directory contains:

- **Complete Documentation**: `vercel-sdk/content/docs/` - Comprehensive API documentation and patterns
- **Code Examples**: `vercel-sdk/examples/` - Real implementation examples across frameworks  
- **Reference Implementation**: `vercel-sdk/content/docs/07-reference/01-ai-sdk-core/` - Detailed API specifications
- **Provider Patterns**: `vercel-sdk/providers/` - How different AI providers are implemented
- **Advanced Features**: `vercel-sdk/content/docs/06-advanced/` - Middleware, streaming, tool calling patterns

**Before implementing any feature:**
1. Study the corresponding Vercel AI SDK documentation in `vercel-sdk/content/docs/`
2. Examine relevant examples in `vercel-sdk/examples/`
3. Check provider implementations in `vercel-sdk/providers/`
4. Ensure Swift implementation maintains API compatibility and design patterns

**This reference is MANDATORY** - the Swift SDK must maintain conceptual and functional parity with the Vercel AI SDK while being idiomatic to Swift.

## Development Commands

### Building and Testing
```bash
swift build              # Build the package
swift test               # Run all tests  
swift test --filter testBasicTextGeneration  # Run specific test
```

### Package Management
```bash
swift package clean      # Clean build artifacts
swift package reset     # Reset package dependencies  
swift package show-dependencies  # Show dependency tree
```

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

### Model Configuration Pattern
Uses fluent builder pattern:
```swift
let model = provider.languageModel("model-id")
    .temperature(0.7)
    .maxTokens(500)
    .topP(0.9)
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

### 🚧 In Progress  
- Real provider implementations (OpenAI, Anthropic, etc.)
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